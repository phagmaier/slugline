//! The managed library's rebuildable index and session convenience state.
//!
//! [`Library::load`] tolerates missing/corrupt caches. [`Library::rebuild`]
//! discovers projects in the active root and reads authoritative identity,
//! display name, archive state and entity pins from their sidecars (ADR 0068).
//! The index retains only reading position, recency, page counts and open state.
//! Losing it cannot lose or unarchive a project.
//!
//! Missing script files remain visible as damaged entries. An unavailable root
//! must be reported by the caller while retaining the last known convenience
//! state. The legacy arbitrary-path index is retained as migration input before
//! the managed cache replaces it; neither rebuilding nor migration deletes its
//! external sources.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::atomic::{save_atomically, SaveError};
use crate::journal::script_id;

/// One script the library knows about.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ScriptEntry {
    /// Path-derived cache/journal locator. Durable identity is [Self::project_id].
    pub id: String,
    pub path: PathBuf,
    /// Cached project display name, read from project metadata on rebuild.
    /// Legacy entries instead derive their title from the external file.
    pub title: String,
    pub modified_millis: u64,
    pub bytes: u64,
    /// Filled in by `layout` after a successful save. Zero means "not counted
    /// yet", which is what the library shows for an entry last written by a
    /// build without layout support.
    pub page_count: u32,
    /// The file was not there at the last refresh.
    pub missing: bool,
    pub last_opened_millis: u64,
    /// Session restore (§Phase 4): whether this script was open when the
    /// application last exited, and where the writer was in it.
    pub open: bool,
    pub scroll_row: u32,
    /// Entities the writer chose to keep even with no occurrences. Managed
    /// sidecars own these values; legacy cache values are migration input.
    pub pinned_entities: Vec<PinnedEntity>,
    pub project_id: String,
    pub archived: bool,
    pub problem: Option<String>,
    pub migration_status: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct PinnedEntity {
    pub kind: String,
    pub value: String,
}

impl Default for ScriptEntry {
    fn default() -> ScriptEntry {
        ScriptEntry {
            id: String::new(),
            path: PathBuf::new(),
            title: String::new(),
            modified_millis: 0,
            bytes: 0,
            page_count: 0,
            missing: false,
            last_opened_millis: 0,
            open: false,
            scroll_row: 0,
            pinned_entities: Vec::new(),
            project_id: String::new(),
            archived: false,
            problem: None,
            migration_status: None,
        }
    }
}

impl ScriptEntry {
    fn for_path(path: &Path) -> ScriptEntry {
        ScriptEntry {
            id: script_id(path),
            title: default_title(path),
            path: path.to_path_buf(),
            ..ScriptEntry::default()
        }
    }
}

/// What the index file holds. Versioned so that a future shape can be
/// recognised and discarded rather than misread — it is a cache, so discarding
/// it is always allowed.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct Index {
    version: u32,
    #[serde(default)]
    root: Option<PathBuf>,
    #[serde(default)]
    scripts: Vec<ScriptEntry>,
}

const INDEX_VERSION: u32 = 2;

/// The library, in memory.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Library {
    entries: Vec<ScriptEntry>,
    root: Option<PathBuf>,
}

impl Library {
    /// Reads the index. Any problem at all yields an empty library.
    pub fn load(path: &Path) -> Library {
        let index: Index = fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        if index.version != INDEX_VERSION {
            return Library::default();
        }
        // An entry with no path is not a script; nothing can be done with it and
        // showing it would be showing a row that does nothing.
        Library {
            root: index.root,
            entries: index
                .scripts
                .into_iter()
                .filter(|entry| !entry.path.as_os_str().is_empty())
                .collect(),
        }
    }

    /// Writes the index, atomically.
    pub fn save(&self, path: &Path) -> Result<(), SaveError> {
        if let Some(parent) = path.parent() {
            if let Err(error) = fs::create_dir_all(parent) {
                return Err(SaveError::Io {
                    path: parent.to_path_buf(),
                    message: error.to_string(),
                });
            }
        }
        let index = Index {
            version: INDEX_VERSION,
            root: self.root.clone(),
            scripts: self.entries.clone(),
        };
        let text = serde_json::to_string_pretty(&index)
            .map(|mut text| {
                text.push('\n');
                text
            })
            .map_err(|error| SaveError::Io {
                path: path.to_path_buf(),
                message: error.to_string(),
            })?;
        save_atomically(path, &text)
    }

    /// Every script, most recently opened first, then by title.
    pub fn entries(&self) -> &[ScriptEntry] {
        &self.entries
    }

    pub fn retain_legacy(path: &Path, retained: &Path) -> Result<(), SaveError> {
        if retained.exists() || !path.exists() {
            return Ok(());
        }
        let bytes = fs::read(path).map_err(|e| SaveError::from_io(path, &e))?;
        let version = serde_json::from_slice::<serde_json::Value>(&bytes)
            .ok()
            .and_then(|v| v.get("version").and_then(|v| v.as_u64()));
        if version == Some(INDEX_VERSION as u64) {
            return Ok(());
        }
        // Raw compatibility input, including damaged older data, is never overwritten.
        crate::atomic::save_new_atomically(retained, &bytes)
    }

    /// Old arbitrary-path entries are compatibility input, never editable state.
    pub fn legacy(path: &Path) -> Vec<ScriptEntry> {
        fs::read(path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Index>(&bytes).ok())
            .filter(|index| index.version == 1)
            .map(|index| index.scripts)
            .unwrap_or_default()
    }

    pub fn rebuild(&mut self, root: &Path) -> Result<(), SaveError> {
        let resolved = crate::project::root(root, false)?;
        let projects = crate::project::scan(&resolved)?;
        let old = if self.root.as_ref() == Some(&resolved) {
            std::mem::take(&mut self.entries)
        } else {
            Vec::new()
        };
        self.root = Some(resolved);
        self.entries = projects
            .iter()
            .map(|project| {
                let path = project.script();
                let id = script_id(&path);
                let mut entry = old
                    .iter()
                    .find(|entry| entry.id == id)
                    .cloned()
                    .unwrap_or_else(|| ScriptEntry::for_path(&path));
                entry.project_id = project.metadata.id.clone();
                entry.title = project.metadata.name.clone();
                entry.archived = project.metadata.archived;
                entry.pinned_entities = project.metadata.pinned_entities.clone();
                entry.problem = project.problem.clone();
                entry.migration_status = project.migration_status();
                if entry.archived {
                    entry.open = false;
                }
                entry
            })
            .collect();
        self.refresh();
        Ok(())
    }

    pub fn merge_cached_state(&mut self, latest: &Library) {
        for entry in &mut self.entries {
            if let Some(current) = latest.get(&entry.id) {
                entry.scroll_row = current.scroll_row;
                entry.page_count = current.page_count;
                entry.last_opened_millis = current.last_opened_millis;
                entry.open = current.open && !entry.archived;
            }
        }
        self.sort();
    }

    pub fn cache_project(&mut self, project: &crate::project::Project) -> String {
        let id = self.add(&project.script());
        self.root = project.directory.parent().map(Path::to_path_buf);
        if let Some(index) = self.position(&id) {
            let entry = &mut self.entries[index];
            entry.project_id = project.metadata.id.clone();
            entry.title = project.metadata.name.clone();
            entry.archived = project.metadata.archived;
            entry.pinned_entities = project.metadata.pinned_entities.clone();
            entry.problem = project.problem.clone();
            entry.migration_status = project.migration_status();
        }
        id
    }

    pub fn get(&self, id: &str) -> Option<&ScriptEntry> {
        self.entries.iter().find(|entry| entry.id == id)
    }

    fn position(&self, id: &str) -> Option<usize> {
        self.entries.iter().position(|entry| entry.id == id)
    }

    /// Adds `path` if it is not already known, and returns its id either way.
    pub fn add(&mut self, path: &Path) -> String {
        let entry = ScriptEntry::for_path(path);
        let id = entry.id.clone();
        if self.position(&id).is_none() {
            self.entries.push(entry);
        }
        self.refresh_one(&id);
        id
    }

    /// Records that a script was opened, which is what the recent list orders by.
    pub fn opened(&mut self, id: &str) {
        if let Some(index) = self.position(id) {
            self.entries[index].last_opened_millis = now_millis();
            self.entries[index].open = true;
        }
        self.sort();
    }

    /// Records that a script was closed, and where the writer had scrolled to.
    pub fn closed(&mut self, id: &str, scroll_row: u32) {
        if let Some(index) = self.position(id) {
            self.entries[index].open = false;
            self.entries[index].scroll_row = scroll_row;
        }
    }

    /// Records where the writer is, without closing the script. The session
    /// restore of §Phase 4 needs this to survive a crash, not just a clean exit.
    pub fn set_scroll(&mut self, id: &str, scroll_row: u32) {
        if let Some(index) = self.position(id) {
            self.entries[index].scroll_row = scroll_row;
        }
    }

    pub fn set_pinned(&mut self, id: &str, entities: Vec<PinnedEntity>) {
        if let Some(index) = self.position(id) {
            self.entries[index].pinned_entities = entities;
        }
    }

    /// Caches the number of screenplay pages produced for the bytes on disk.
    ///
    /// Zero remains the sentinel for an entry that has never been processed by
    /// a layout-capable build. A real pagination always has at least one page.
    pub fn set_page_count(&mut self, id: &str, page_count: u32) {
        if let Some(index) = self.position(id) {
            self.entries[index].page_count = page_count;
        }
    }

    /// Forgets a script. The file is untouched — deleting it is a separate
    /// decision the user makes separately (§Phase 4).
    pub fn remove(&mut self, id: &str) -> Option<ScriptEntry> {
        self.position(id).map(|index| self.entries.remove(index))
    }

    /// Follows a script to a new path, keeping its place in the list.
    ///
    /// The id is derived from the path, so it changes. Anything filed under the
    /// old id — the journal, the backups — belongs to the old path and stays
    /// there; a rename is not a reason to lose the backups of what the file was
    /// called yesterday.
    pub fn renamed(&mut self, id: &str, new_path: &Path) -> Option<String> {
        let index = self.position(id)?;
        let new_id = script_id(new_path);
        let entry = &mut self.entries[index];
        entry.id = new_id.clone();
        entry.path = new_path.to_path_buf();
        entry.title = default_title(new_path);
        self.refresh_one(&new_id);
        Some(new_id)
    }

    /// Which scripts to reopen. §6's `session_restore`.
    pub fn session(&self) -> Vec<ScriptEntry> {
        self.entries
            .iter()
            .filter(|entry| {
                entry.open && !entry.missing && !entry.archived && entry.problem.is_none()
            })
            .cloned()
            .collect()
    }

    /// Restates every entry from the filesystem: size, modification time, and
    /// whether the file is there at all.
    pub fn refresh(&mut self) {
        for index in 0..self.entries.len() {
            self.stat(index);
        }
        self.sort();
    }

    fn refresh_one(&mut self, id: &str) {
        if let Some(index) = self.position(id) {
            self.stat(index);
        }
    }

    fn stat(&mut self, index: usize) {
        let entry = &mut self.entries[index];
        match fs::metadata(&entry.path) {
            Ok(metadata) => {
                entry.missing = false;
                entry.bytes = metadata.len();
                entry.modified_millis = metadata
                    .modified()
                    .ok()
                    .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                    .map(|since| since.as_millis() as u64)
                    .unwrap_or(0);
            }
            // Not cleared: the size and date from when it was last seen are
            // better than zeroes for telling the user which script this was.
            Err(_) => entry.missing = true,
        }
    }

    /// Most recently opened first; never-opened scripts by title after them.
    fn sort(&mut self) {
        self.entries.sort_by(|a, b| {
            b.last_opened_millis
                .cmp(&a.last_opened_millis)
                .then_with(|| a.title.cmp(&b.title))
        });
    }
}

/// A script's file name without its extension. The title page's `Title:` is a
/// better answer and the bridge substitutes it once the file has been parsed —
/// but this crate does not open scripts, and a library that cannot list a file
/// until it has parsed it is a library that is slow for no reason.
fn default_title(path: &Path) -> String {
    path.file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;

    fn script(dir: &TempDir, name: &str, contents: &str) -> PathBuf {
        let path = dir.path().join(name);
        fs::write(&path, contents).unwrap();
        path
    }

    #[test]
    fn a_missing_index_is_an_empty_library_rather_than_a_failure() {
        let dir = TempDir::new("library-missing");
        let library = Library::load(&dir.path().join("library.json"));
        assert!(library.entries().is_empty());
    }

    #[test]
    fn a_corrupt_index_is_an_empty_library() {
        let dir = TempDir::new("library-corrupt");
        let path = dir.path().join("library.json");
        fs::write(&path, "\u{0}\u{0}not json at all").unwrap();
        assert!(Library::load(&path).entries().is_empty());
    }

    #[test]
    fn the_index_round_trips() {
        let dir = TempDir::new("library-round-trip");
        let path = dir.path().join("library.json");
        let heat = script(&dir, "heat.fountain", "INT. HOUSE - DAY\n");

        let mut library = Library::default();
        let id = library.add(&heat);
        library.opened(&id);
        library.set_pinned(
            &id,
            vec![PinnedEntity {
                kind: "character".to_owned(),
                value: "ALICE".to_owned(),
            }],
        );
        library.save(&path).unwrap();

        let reloaded = Library::load(&path);
        assert_eq!(reloaded.entries().len(), 1);
        let entry = reloaded.get(&id).expect("the entry survived");
        assert_eq!(entry.path, heat);
        assert_eq!(entry.title, "heat");
        assert_eq!(entry.bytes, 17);
        assert!(entry.open);
        assert_eq!(entry.pinned_entities[0].value, "ALICE");
    }

    #[test]
    fn a_page_count_round_trips_as_cache_data() {
        let dir = TempDir::new("library-page-count");
        let index = dir.path().join("library.json");
        let path = script(&dir, "heat.fountain", "INT. HOUSE - DAY\n");
        let mut library = Library::default();
        let id = library.add(&path);

        library.set_page_count(&id, 117);
        library.save(&index).unwrap();

        assert_eq!(Library::load(&index).get(&id).unwrap().page_count, 117);
    }

    #[test]
    fn adding_the_same_script_twice_is_one_entry() {
        let dir = TempDir::new("library-duplicate");
        let heat = script(&dir, "heat.fountain", "text\n");
        let mut library = Library::default();
        let first = library.add(&heat);
        let second = library.add(&heat);
        assert_eq!(first, second);
        assert_eq!(library.entries().len(), 1);
    }

    #[test]
    fn a_missing_file_is_marked_missing_and_kept() {
        let dir = TempDir::new("library-gone");
        let heat = script(&dir, "heat.fountain", "text\n");
        let mut library = Library::default();
        let id = library.add(&heat);
        assert!(!library.get(&id).unwrap().missing);

        fs::remove_file(&heat).unwrap();
        library.refresh();
        let entry = library.get(&id).expect("still listed");
        assert!(entry.missing);
        assert_eq!(entry.bytes, 5, "and still says how big it was");
    }

    #[test]
    fn removing_a_script_from_the_library_leaves_the_file_alone() {
        let dir = TempDir::new("library-remove");
        let heat = script(&dir, "heat.fountain", "text\n");
        let mut library = Library::default();
        let id = library.add(&heat);
        library.remove(&id);
        assert!(library.entries().is_empty());
        assert!(heat.exists(), "the file is the user's, not the library's");
    }

    #[test]
    fn a_rename_keeps_the_entry_and_changes_its_identity() {
        let dir = TempDir::new("library-rename");
        let heat = script(&dir, "heat.fountain", "text\n");
        let mut library = Library::default();
        let id = library.add(&heat);
        library.opened(&id);

        let renamed = dir.path().join("heat-final.fountain");
        fs::rename(&heat, &renamed).unwrap();
        let new_id = library.renamed(&id, &renamed).expect("the entry is there");

        assert_ne!(new_id, id);
        assert_eq!(library.entries().len(), 1);
        let entry = library.get(&new_id).unwrap();
        assert_eq!(entry.path, renamed);
        assert_eq!(entry.title, "heat-final");
        assert!(!entry.missing);
    }

    #[test]
    fn the_session_is_the_scripts_that_were_open() {
        let dir = TempDir::new("library-session");
        let one = script(&dir, "one.fountain", "a\n");
        let two = script(&dir, "two.fountain", "b\n");
        let three = script(&dir, "three.fountain", "c\n");

        let mut library = Library::default();
        let one_id = library.add(&one);
        let two_id = library.add(&two);
        library.add(&three);
        library.opened(&one_id);
        library.opened(&two_id);
        library.set_scroll(&one_id, 412);
        library.closed(&two_id, 7);

        let session = library.session();
        assert_eq!(session.len(), 1);
        assert_eq!(session[0].path, one);
        assert_eq!(session[0].scroll_row, 412, "and where the writer was in it");
    }

    #[test]
    fn a_script_that_vanished_is_not_reopened_by_session_restore() {
        let dir = TempDir::new("library-session-gone");
        let one = script(&dir, "one.fountain", "a\n");
        let mut library = Library::default();
        let id = library.add(&one);
        library.opened(&id);
        fs::remove_file(&one).unwrap();
        library.refresh();
        assert!(library.session().is_empty());
        assert_eq!(library.entries().len(), 1, "but it is still in the list");
    }

    #[test]
    fn the_recent_list_is_ordered_by_when_it_was_last_opened() {
        let dir = TempDir::new("library-recent");
        let one = script(&dir, "alpha.fountain", "a\n");
        let two = script(&dir, "beta.fountain", "b\n");
        let mut library = Library::default();
        let one_id = library.add(&one);
        let two_id = library.add(&two);

        library.entries[0].last_opened_millis = 1_000;
        library.entries[1].last_opened_millis = 2_000;
        library.refresh();
        assert_eq!(library.entries()[0].id, two_id);
        assert_eq!(library.entries()[1].id, one_id);
    }

    #[test]
    fn an_index_from_another_version_is_discarded_rather_than_misread() {
        let dir = TempDir::new("library-version");
        let path = dir.path().join("library.json");
        fs::write(&path, r#"{"version":99,"scripts":[{"path":"/x"}]}"#).unwrap();
        assert!(Library::load(&path).entries().is_empty());
    }
}
