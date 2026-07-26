//! The script library: §Phase 4's list of scripts, and the session it restores.
//!
//! **The index is a cache.** §Phase 4 says so in as many words — "it is a
//! *cache*, and the app must work correctly if it is deleted" — and everything
//! here follows from it:
//!
//! * [`Library::load`] cannot fail. A missing, truncated or hand-mangled index
//!   is an empty one.
//! * Nothing is stored here that cannot be recovered by opening the file again.
//!   The path is the only fact; the title, size and modification time are
//!   restated from the filesystem on every [`Library::refresh`].
//! * Removing a script from the library never touches the file. §Phase 4 lists
//!   "remove-from-library" and "delete-file" as two different commands, and the
//!   difference is the whole point of a library that is only a cache.
//!
//! A missing file stays in the list, marked [`ScriptEntry::missing`] — §Phase 4:
//! "missing files shown as missing, not silently dropped". A script on an
//! unmounted drive is not a script the user threw away.

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
    /// Stable name derived from the path — the same one the journal and the
    /// backup directory use, so all three can be found from any one of them.
    pub id: String,
    pub path: PathBuf,
    /// The script's title, from its title page if it has one, else its file
    /// name. Restated on refresh; never authoritative.
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
    /// §7 entities the writer chose to keep even with no occurrences. This is
    /// per-script cache metadata and is never serialised into Fountain.
    pub pinned_entities: Vec<PinnedEntity>,
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
    scripts: Vec<ScriptEntry>,
}

const INDEX_VERSION: u32 = 1;

/// The library, in memory.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Library {
    entries: Vec<ScriptEntry>,
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
            .filter(|entry| entry.open && !entry.missing)
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
