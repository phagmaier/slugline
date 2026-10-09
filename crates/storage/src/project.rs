//! Directory-backed managed projects (ADR 0068). No index owns user data.
use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File};
use std::io::{self, Read};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::atomic::{save_atomically, SaveError};
use crate::library::PinnedEntity;

pub const FORMAT: u32 = 1;
pub const SCRIPT: &str = "script.fountain";
const META: &str = "project.json";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Origin {
    pub path: PathBuf,
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub legacy_id: Option<String>,
    #[serde(default)]
    pub history_complete: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Metadata {
    pub version: u32,
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub archived: bool,
    #[serde(default)]
    pub pinned_entities: Vec<PinnedEntity>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<Origin>,
    #[serde(flatten)]
    pub unknown: BTreeMap<String, Value>,
}

impl Metadata {
    pub fn new(name: String) -> Result<Self, SaveError> {
        Ok(Self {
            version: FORMAT,
            id: random_id()?,
            name,
            archived: false,
            pinned_entities: Vec::new(),
            origin: None,
            unknown: BTreeMap::new(),
        })
    }
}

#[derive(Debug, Clone)]
pub struct Project {
    pub directory: PathBuf,
    pub metadata: Metadata,
    /// Damage is visible; readable scripts are retained for repair/export.
    pub problem: Option<String>,
}

impl Project {
    pub fn script(&self) -> PathBuf {
        self.directory.join(SCRIPT)
    }
    pub fn versions(&self) -> PathBuf {
        self.directory.join("versions")
    }
    pub fn migration_status(&self) -> Option<String> {
        self.metadata
            .origin
            .as_ref()
            .filter(|o| o.legacy_id.is_some() && !o.history_complete)
            .map(|_| "Previous versions need migration retry".into())
    }
    pub fn writable(&self) -> bool {
        self.problem.is_none()
    }
}

pub fn valid_id(id: &str) -> bool {
    id.len() == 32
        && id
            .bytes()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
}

pub fn folder_id(path: &Path) -> Option<String> {
    let name = path.file_name()?.to_str()?;
    let (_, id) = name.rsplit_once("--")?;
    valid_id(id).then(|| id.to_owned())
}

fn random_id() -> Result<String, SaveError> {
    let path = Path::new("/dev/urandom");
    let mut bytes = [0u8; 16];
    File::open(path)
        .and_then(|mut file| file.read_exact(&mut bytes))
        .map_err(|error| SaveError::from_io(path, &error))?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

/// Discovery never creates a library. Only an explicitly new root may be made.
pub fn root(path: &Path, create: bool) -> Result<PathBuf, SaveError> {
    if create && !path.exists() {
        fs::create_dir_all(path).map_err(|error| SaveError::from_io(path, &error))?;
    }
    let resolved = path
        .canonicalize()
        .map_err(|error| SaveError::from_io(path, &error))?;
    if !resolved.is_dir() {
        return Err(error(&resolved, "the library location is not a directory"));
    }
    Ok(resolved)
}

fn error(path: &Path, message: &str) -> SaveError {
    SaveError::Io {
        path: path.to_path_buf(),
        message: message.to_owned(),
    }
}

fn ordinary(path: &Path, directory: bool) -> Result<(), SaveError> {
    let stat = fs::symlink_metadata(path).map_err(|e| SaveError::from_io(path, &e))?;
    if stat.file_type().is_symlink()
        || (directory && !stat.is_dir())
        || (!directory && !stat.is_file())
    {
        return Err(error(
            path,
            "project contents must be ordinary files/directories, not symlinks",
        ));
    }
    Ok(())
}

pub fn read(directory: &Path) -> Result<Project, SaveError> {
    ordinary(directory, true)?;
    let id = folder_id(directory).ok_or_else(|| error(directory, "invalid project folder ID"))?;
    let script_problem = ordinary(&directory.join(SCRIPT), false)
        .err()
        .map(|e| e.to_string());
    let mut problem = script_problem;
    let meta_path = directory.join(META);
    let parsed = ordinary(&meta_path, false)
        .and_then(|()| fs::read(&meta_path).map_err(|e| SaveError::from_io(&meta_path, &e)))
        .and_then(|bytes| {
            serde_json::from_slice::<Metadata>(&bytes)
                .map_err(|e| error(&meta_path, &e.to_string()))
        });
    let metadata = match parsed {
        Ok(metadata) if metadata.version == FORMAT && metadata.id == id => metadata,
        Ok(metadata) => {
            problem = Some(if metadata.version != FORMAT {
                format!("unsupported project format {}", metadata.version)
            } else {
                "project and folder identities disagree".to_owned()
            });
            metadata
        }
        Err(e) => {
            problem = Some(format!("metadata needs repair: {e}"));
            Metadata {
                version: FORMAT,
                id,
                name: directory
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .rsplit_once("--")
                    .unwrap()
                    .0
                    .to_owned(),
                archived: false,
                pinned_entities: Vec::new(),
                origin: None,
                unknown: BTreeMap::new(),
            }
        }
    };
    for child in ["versions", "imports"] {
        let path = directory.join(child);
        if fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
            problem = Some(format!("{} is a child symlink", path.display()));
        }
    }
    Ok(Project {
        directory: directory.to_path_buf(),
        metadata,
        problem,
    })
}

/// One level only: no parsing scripts or traversing reference files.
pub fn scan(root: &Path) -> Result<Vec<Project>, SaveError> {
    let root = self::root(root, false)?;
    let mut projects = Vec::new();
    for entry in fs::read_dir(&root).map_err(|e| SaveError::from_io(&root, &e))? {
        let entry = entry.map_err(|e| SaveError::from_io(&root, &e))?;
        let path = entry.path();
        if let Some(id) = folder_id(&path) {
            match read(&path) {
                Ok(project) => projects.push(project),
                Err(e) => projects.push(Project {
                    directory: path.clone(),
                    metadata: Metadata {
                        version: FORMAT,
                        id,
                        name: path.file_name().unwrap().to_string_lossy().into_owned(),
                        archived: false,
                        pinned_entities: Vec::new(),
                        origin: None,
                        unknown: BTreeMap::new(),
                    },
                    problem: Some(e.to_string()),
                }),
            }
        } else if path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.starts_with(".staging-"))
            && ordinary(&path, true).is_ok()
            && ordinary(&path.join(SCRIPT), false).is_ok()
        {
            // Crash remnants belong to the writer. Never purge or make them editable.
            let metadata = fs::read(path.join(META))
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Metadata>(&bytes).ok())
                .unwrap_or_else(|| Metadata {
                    version: FORMAT,
                    id: path
                        .file_name()
                        .unwrap()
                        .to_string_lossy()
                        .trim_start_matches(".staging-")
                        .to_owned(),
                    name: "Interrupted project creation".into(),
                    archived: false,
                    pinned_entities: Vec::new(),
                    origin: None,
                    unknown: BTreeMap::new(),
                });
            projects.push(Project { directory: path, metadata, problem: Some("interrupted project creation; export readable text before removing this folder".into()) });
        }
    }
    let mut counts = HashMap::new();
    for project in &projects {
        *counts.entry(project.metadata.id.clone()).or_insert(0) += 1;
    }
    for project in &mut projects {
        if counts[&project.metadata.id] > 1 {
            project.problem = Some(
                "duplicate project ID; use explicit Duplicate to create an independent copy"
                    .to_owned(),
            );
        }
    }
    projects.sort_by(|a, b| a.directory.cmp(&b.directory));
    Ok(projects)
}

/// Canonical aliases to a project are accepted, but child symlinks are refused.
pub fn resolve(root: &Path, script: &Path) -> Result<Project, SaveError> {
    let root = self::root(root, false)?;
    if let Some(parent) = script.parent() {
        if parent
            .parent()
            .and_then(|p| p.canonicalize().ok())
            .as_deref()
            == Some(root.as_path())
        {
            ordinary(parent, true)?;
            ordinary(script, false)?;
        }
    }
    let resolved = script
        .canonicalize()
        .map_err(|e| SaveError::from_io(script, &e))?;
    if resolved.file_name().is_none_or(|n| n != SCRIPT)
        || resolved.parent().and_then(Path::parent) != Some(root.as_path())
    {
        return Err(error(
            script,
            "choose a script in the active library, or import an external copy",
        ));
    }
    let project = scan(&root)?
        .into_iter()
        .find(|p| p.script() == resolved)
        .ok_or_else(|| error(script, "unrecognized managed project"))?;
    if let Some(problem) = &project.problem {
        return Err(error(script, problem));
    }
    Ok(project)
}

/// Saving refuses missing scripts, unmounted roots, archive/conflict, or escape.
pub fn validate_save(root: &Path, script: &Path) -> Result<Project, SaveError> {
    let project = resolve(root, script)?;
    if project.metadata.archived {
        return Err(error(
            script,
            "restore this archived project before editing",
        ));
    }
    Ok(project)
}

pub fn update(project: &Project, metadata: &Metadata) -> Result<(), SaveError> {
    use std::os::fd::AsRawFd;
    let claim =
        File::open(&project.directory).map_err(|e| SaveError::from_io(&project.directory, &e))?;
    // SAFETY: a live directory descriptor, held until this metadata transaction ends.
    if unsafe { libc::flock(claim.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(SaveError::from_io(
            &project.directory,
            &io::Error::last_os_error(),
        ));
    }
    let current = read(&project.directory)?;
    if !current.writable() || current.metadata.id != metadata.id || metadata.version != FORMAT {
        return Err(error(
            &project.directory,
            "repair/upgrade project metadata before changing it",
        ));
    }
    // Merge the fields this transaction changed. Preserve concurrent unrelated metadata/unknown fields.
    let mut next = current.metadata;
    if metadata.name != project.metadata.name {
        next.name = metadata.name.clone();
    }
    if metadata.archived != project.metadata.archived {
        next.archived = metadata.archived;
    }
    if metadata.pinned_entities != project.metadata.pinned_entities {
        next.pinned_entities = metadata.pinned_entities.clone();
    }
    if metadata.origin != project.metadata.origin {
        next.origin = metadata.origin.clone();
    }
    for key in project
        .metadata
        .unknown
        .keys()
        .chain(metadata.unknown.keys())
    {
        if metadata.unknown.get(key) != project.metadata.unknown.get(key) {
            match metadata.unknown.get(key) {
                Some(value) => {
                    next.unknown.insert(key.clone(), value.clone());
                }
                None => {
                    next.unknown.remove(key);
                }
            }
        }
    }
    let bytes =
        serde_json::to_vec_pretty(&next).map_err(|e| error(&project.directory, &e.to_string()))?;
    save_atomically(&project.directory.join(META), bytes)
}

/// Explicit repair preserves the original sidecar, including unknown raw bytes.
pub fn repair(project: &Project) -> Result<(), SaveError> {
    ordinary(&project.directory, true)?;
    let path = project.directory.join(META);
    if fs::symlink_metadata(&path).is_ok() {
        ordinary(&path, false)?;
    }
    if let Ok(bytes) = fs::read(&path) {
        if serde_json::from_slice::<Value>(&bytes)
            .ok()
            .and_then(|v| v.get("version").and_then(Value::as_u64))
            .is_some_and(|v| v != FORMAT as u64)
        {
            return Err(error(
                &path,
                "unsupported metadata cannot be repaired by this version",
            ));
        }
        let preserved = project
            .directory
            .join(format!("project.damaged-{}.json", random_id()?));
        crate::atomic::save_new_atomically(&preserved, &bytes)?;
    }
    ordinary(&project.script(), false)?;
    let bytes =
        serde_json::to_vec_pretty(&project.metadata).map_err(|e| error(&path, &e.to_string()))?;
    save_atomically(&path, bytes)
}

fn prefix(name: &str) -> String {
    let safe: String = name
        .chars()
        .take(60)
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    if safe.is_empty() {
        "Untitled".to_owned()
    } else {
        safe
    }
}

struct Stage(PathBuf);
impl Drop for Stage {
    fn drop(&mut self) {
        if !self.0.as_os_str().is_empty() {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
}

/// Linux is the supported platform. RENAME_NOREPLACE never replaces a directory.
fn publish(stage: &Path, destination: &Path) -> io::Result<()> {
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    let from = CString::new(stage.as_os_str().as_bytes())?;
    let to = CString::new(destination.as_os_str().as_bytes())?;
    // SAFETY: both C strings are alive and NUL-terminated; no pointer is retained.
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

pub fn create(
    root: &Path,
    metadata: Metadata,
    bytes: &[u8],
    fdx: Option<&[u8]>,
) -> Result<Project, SaveError> {
    std::str::from_utf8(bytes)
        .map_err(|_| error(root, "unsupported Fountain encoding; use UTF-8"))?;
    if !valid_id(&metadata.id) || metadata.version != FORMAT {
        return Err(error(root, "invalid project identity/format"));
    }
    let root = self::root(root, false)?;
    use std::os::fd::AsRawFd;
    let root_claim = File::open(&root).map_err(|e| SaveError::from_io(&root, &e))?;
    // Kernel ownership only, no persisted lock file. Serialize ID check/publication across processes.
    if unsafe { libc::flock(root_claim.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(SaveError::from_io(&root, &io::Error::last_os_error()));
    }
    if scan(&root)?.iter().any(|p| p.metadata.id == metadata.id) {
        return Err(error(&root, "project ID already exists"));
    }
    let final_path = root.join(format!("{}--{}", prefix(&metadata.name), metadata.id));
    // Staging has an independent random name, exclusively created. Never purge others.
    let mut stage = Stage(root.join(format!(".staging-{}", random_id()?)));
    fs::create_dir(&stage.0).map_err(|e| SaveError::from_io(&stage.0, &e))?;
    save_atomically(&stage.0.join(SCRIPT), bytes)?;
    let json = serde_json::to_vec_pretty(&metadata).map_err(|e| error(&stage.0, &e.to_string()))?;
    save_atomically(&stage.0.join(META), json)?;
    fs::create_dir(stage.0.join("versions")).map_err(|e| SaveError::from_io(&stage.0, &e))?;
    if let Some(fdx) = fdx {
        fs::create_dir(stage.0.join("imports")).map_err(|e| SaveError::from_io(&stage.0, &e))?;
        save_atomically(&stage.0.join("imports/source.fdx"), fdx)?;
    }
    File::open(&stage.0)
        .and_then(|dir| dir.sync_all())
        .map_err(|e| SaveError::from_io(&stage.0, &e))?;
    publish(&stage.0, &final_path).map_err(|e| SaveError::from_io(&final_path, &e))?;
    stage.0 = PathBuf::new();
    File::open(&root).and_then(|dir| dir.sync_all()).map_err(|e| error(&final_path, &format!("project published at {}; parent synchronization failed: {e}. Reopen this project before retrying", final_path.display())))?;
    read(&final_path)
}

/// All recognized project contents are protected, even outside the active root.
/// Resolve existing prefixes as well as whole paths (a new export may not exist).
pub fn protected_destination(path: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    // Replacing a hard-link alias is forbidden too; its other name may be a managed file.
    if fs::metadata(path).is_ok_and(|m| m.nlink() > 1 && m.is_file()) {
        return true;
    }
    let mut prefix = path.to_path_buf();
    while !prefix.exists() {
        if !prefix.pop() {
            return false;
        }
    }
    let Ok(resolved) = prefix.canonicalize() else {
        return true;
    };
    resolved.ancestors().any(|p| {
        (folder_id(p).is_some()
            || p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.strip_prefix(".staging-").is_some_and(valid_id)))
            && (p.join(META).exists() || p.join(SCRIPT).exists())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;
    #[test]
    fn metadata_updates_merge_concurrent_fields_and_unknown_changes() {
        let dir = TempDir::new("metadata-merge");
        let original = create(
            dir.path(),
            Metadata::new("one".into()).unwrap(),
            b"Text\n",
            None,
        )
        .unwrap();
        let mut renamed = original.metadata.clone();
        renamed.name = "new label".into();
        update(&original, &renamed).unwrap();
        let mut pins = original.metadata.clone();
        pins.pinned_entities.push(PinnedEntity {
            kind: "character".into(),
            value: "ALICE".into(),
        });
        pins.unknown.insert(
            "creation_journal".into(),
            Value::String("pending.log".into()),
        );
        update(&original, &pins).unwrap();
        let latest = read(&original.directory).unwrap();
        assert_eq!(latest.metadata.name, "new label");
        assert_eq!(latest.metadata.pinned_entities, pins.pinned_entities);
        let mut completed = latest.metadata.clone();
        completed.unknown.remove("creation_journal");
        update(&latest, &completed).unwrap();
        assert!(!read(&original.directory)
            .unwrap()
            .metadata
            .unknown
            .contains_key("creation_journal"));
    }
    #[test]
    fn concurrent_publication_allows_one_owner_and_retains_crash_staging_text() {
        use std::sync::{Arc, Barrier};
        let dir = TempDir::new("projects-concurrent");
        let meta = Metadata::new("same".into()).unwrap();
        let barrier = Arc::new(Barrier::new(4));
        let threads: Vec<_> = (0..4)
            .map(|_| {
                let root = dir.path().to_path_buf();
                let meta = meta.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    create(&root, meta, b"complete\n", None).is_ok()
                })
            })
            .collect();
        assert_eq!(
            threads
                .into_iter()
                .map(|t| t.join().unwrap())
                .filter(|ok| *ok)
                .count(),
            1
        );
        let staging = dir
            .path()
            .join(format!(".staging-{}", random_id().unwrap()));
        fs::create_dir(&staging).unwrap();
        fs::write(staging.join(SCRIPT), b"crash text\n").unwrap();
        let scanned = scan(dir.path()).unwrap();
        assert_eq!(scanned.len(), 2);
        assert!(scanned
            .iter()
            .any(|p| p.directory == staging && p.problem.is_some()));
        assert!(protected_destination(&staging.join(SCRIPT)));
        assert_eq!(fs::read(staging.join(SCRIPT)).unwrap(), b"crash text\n");
    }

    #[test]
    fn exact_copy_and_cache_free_discovery_preserve_metadata() {
        let dir = TempDir::new("projects-exact");
        let bytes = b"\xef\xbb\xbfTitle: My Case\r\n\r\nUnknown  \r\n";
        let mut meta = Metadata::new("My / Unicode \u{1f30d}".into()).unwrap();
        meta.pinned_entities.push(PinnedEntity {
            kind: "character".into(),
            value: "ALICE".into(),
        });
        meta.unknown
            .insert("future".into(), serde_json::json!({"a":1}));
        let project = create(dir.path(), meta.clone(), bytes, Some(b"<raw/>")).unwrap();
        assert_eq!(fs::read(project.script()).unwrap(), bytes);
        assert_eq!(
            fs::read(project.directory.join("imports/source.fdx")).unwrap(),
            b"<raw/>"
        );
        meta.archived = true;
        meta.name = "new name".into();
        update(&project, &meta).unwrap();
        let discovered = scan(dir.path()).unwrap();
        assert_eq!(discovered[0].metadata, meta);
        assert_eq!(discovered[0].directory, project.directory);
        assert!(protected_destination(
            &project.versions().join("new.fountain")
        ));
    }
    #[test]
    fn publication_is_exclusive_even_for_an_empty_existing_directory() {
        let dir = TempDir::new("projects-collision");
        let meta = Metadata::new("same".into()).unwrap();
        let destination = dir.path().join(format!("same--{}", meta.id));
        fs::create_dir(&destination).unwrap();
        assert!(create(dir.path(), meta, b"text", None).is_err());
        assert_eq!(fs::read_dir(destination).unwrap().count(), 0);
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }
    #[test]
    fn missing_corrupt_future_and_duplicate_metadata_are_visible_and_retained() {
        let dir = TempDir::new("projects-damage");
        let project = create(
            dir.path(),
            Metadata::new("one".into()).unwrap(),
            b"text",
            None,
        )
        .unwrap();
        fs::write(project.directory.join(META), b"{truncated").unwrap();
        let damaged = scan(dir.path()).unwrap().remove(0);
        assert!(damaged.problem.is_some());
        assert_eq!(damaged.metadata.id, project.metadata.id);
        repair(&damaged).unwrap();
        assert!(fs::read_dir(&damaged.directory).unwrap().any(|e| e
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with("project.damaged-")));
        let mut future = project.metadata.clone();
        future.version = 99;
        fs::write(
            project.directory.join(META),
            serde_json::to_vec(&future).unwrap(),
        )
        .unwrap();
        assert!(repair(&scan(dir.path()).unwrap()[0]).is_err());
        assert_eq!(fs::read(project.script()).unwrap(), b"text");
        future.version = FORMAT;
        fs::write(
            project.directory.join(META),
            serde_json::to_vec(&future).unwrap(),
        )
        .unwrap();
        let duplicate = dir.path().join(format!("copied--{}", future.id));
        fs::create_dir(&duplicate).unwrap();
        fs::copy(project.script(), duplicate.join(SCRIPT)).unwrap();
        fs::copy(project.directory.join(META), duplicate.join(META)).unwrap();
        assert!(scan(dir.path()).unwrap().iter().all(|p| p
            .problem
            .as_deref()
            .unwrap()
            .contains("duplicate")));
        assert!(resolve(dir.path(), &project.script()).is_err());
    }
    #[test]
    fn root_aliases_open_the_same_file_but_child_escapes_are_refused() {
        use std::os::unix::fs::symlink;
        let dir = TempDir::new("projects-alias");
        let root = dir.path().join("library");
        fs::create_dir(&root).unwrap();
        let project = create(&root, Metadata::new("one".into()).unwrap(), b"text", None).unwrap();
        let alias = dir.path().join("alias");
        symlink(&root, &alias).unwrap();
        let path = alias
            .join(project.directory.file_name().unwrap())
            .join(SCRIPT);
        assert_eq!(resolve(&alias, &path).unwrap().script(), project.script());
        let outside = dir.path().join("outside");
        fs::write(&outside, b"outside").unwrap();
        fs::remove_file(project.script()).unwrap();
        symlink(&outside, project.script()).unwrap();
        assert!(resolve(&root, &project.script()).is_err());
        assert_eq!(fs::read(outside).unwrap(), b"outside");
    }
    #[test]
    fn configured_missing_roots_are_not_recreated_and_bad_encoding_is_rejected() {
        let dir = TempDir::new("projects-missing");
        let missing = dir.path().join("missing");
        assert!(root(&missing, false).is_err());
        assert!(!missing.exists());
        assert!(create(
            dir.path(),
            Metadata::new("bad".into()).unwrap(),
            b"\xff",
            None
        )
        .is_err());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }
}
