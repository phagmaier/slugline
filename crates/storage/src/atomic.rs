//! The atomic save of §Phase 4, and nothing else.
//!
//! The sequence is specified exactly, and it is implemented exactly:
//!
//! 1. Write to `<name>.tmp-<pid>-<nonce>` in the **same directory** as the target
//! 2. `fsync` the temp file
//! 3. `rename(2)` the temp file over the target
//! 4. `fsync` the containing **directory**
//! 5. Preserve the original file's mode and ownership where permitted
//!
//! Each step earns its place. Same directory, because `rename(2)` is only atomic
//! within one filesystem — a temp file in `/tmp` would become a copy, and a copy
//! interrupted is a truncated script. `fsync` on the file before the rename,
//! because a rename that reaches the disk before the data does leaves the target
//! pointing at a file full of zeroes after a power loss. `fsync` on the
//! *directory* after, because the rename itself is metadata and lives in the
//! directory's own blocks.
//!
//! What the sequence guarantees is the property §10 asks for: at every instant,
//! the path either holds the complete old file or the complete new one. There is
//! no window in which it holds neither, and none in which it holds half of
//! either.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Why a save did not happen.
///
/// These are separate variants rather than one message because §Phase 4 asks for
/// them to be: "read-only file, full disk, and permission-denied are each handled
/// with a distinct message and a Save As escape hatch". The variant is what the
/// UI switches on to decide what to offer.
///
/// In every case the target file is exactly as it was. A save either happened or
/// did not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveError {
    /// The file exists and this process cannot write to it. Offer Save As.
    ReadOnly { path: PathBuf },
    /// The directory will not take a new file. Offer Save As.
    PermissionDenied { path: PathBuf },
    /// `ENOSPC` or `EDQUOT`. Offer Save As, somewhere else.
    NoSpace { path: PathBuf },
    /// The directory the file would go in does not exist.
    NoSuchDirectory { path: PathBuf },
    /// Anything else, with the message the operating system gave.
    Io { path: PathBuf, message: String },
}

impl SaveError {
    pub fn path(&self) -> &Path {
        match self {
            SaveError::ReadOnly { path }
            | SaveError::PermissionDenied { path }
            | SaveError::NoSpace { path }
            | SaveError::NoSuchDirectory { path }
            | SaveError::Io { path, .. } => path,
        }
    }

    /// Classifies an OS error against the path it happened on.
    pub(crate) fn from_io(path: &Path, error: &io::Error) -> SaveError {
        // ENOSPC is 28 and EDQUOT is 122 on Linux. `io::ErrorKind` has had
        // `StorageFull` and `QuotaExceeded` since 1.83, and the workspace floor
        // is 1.85, so this raw-number guard is now a fallback the named kinds
        // already cover — the match below is on `error.kind()`, so a toolchain
        // with the kinds answers through the front door either way. Removing
        // the guard touches the save path's error classification, which wants
        // the full-disk test rather than a drive-by; it is logged under "Found
        // along the way" in `docs/BACKLOG.md`.
        let full = matches!(error.raw_os_error(), Some(28) | Some(122));
        let path = path.to_path_buf();
        match error.kind() {
            _ if full => SaveError::NoSpace { path },
            io::ErrorKind::PermissionDenied => SaveError::PermissionDenied { path },
            io::ErrorKind::NotFound => SaveError::NoSuchDirectory { path },
            _ => SaveError::Io {
                path,
                message: error.to_string(),
            },
        }
    }
}

impl std::fmt::Display for SaveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SaveError::ReadOnly { path } => {
                write!(f, "{} is read-only", path.display())
            }
            SaveError::PermissionDenied { path } => {
                write!(f, "no permission to write to {}", path.display())
            }
            SaveError::NoSpace { path } => {
                write!(
                    f,
                    "no space left on the filesystem holding {}",
                    path.display()
                )
            }
            SaveError::NoSuchDirectory { path } => match path.parent() {
                Some(parent) => write!(f, "{} does not exist", parent.display()),
                None => write!(f, "{} has no directory", path.display()),
            },
            SaveError::Io { path, message } => write!(f, "{}: {message}", path.display()),
        }
    }
}

impl std::error::Error for SaveError {}

/// Writes `contents` to `path`, atomically.
///
/// On success the file at `path` holds exactly `contents` and has reached the
/// disk. On failure the file at `path` is untouched and no temporary file is
/// left behind.
/// Atomic exclusive file publication, used for migration snapshots.
pub fn save_new_atomically(path: &Path, contents: impl AsRef<[u8]>) -> Result<(), SaveError> {
    prepare_save(path, contents.as_ref(), |_| Ok(()))?
        .publish_new()
        .map(drop)
        .map_err(|e| SaveError::from_io(path, &e))
}

pub fn save_atomically(path: &Path, contents: impl AsRef<[u8]>) -> Result<(), SaveError> {
    let prepared = prepare_save(path, contents.as_ref(), |_| Ok(()))?;
    prepared
        .publish()
        .map(drop)
        .map_err(|error| SaveError::from_io(path, &error))
}

/// Prepares a complete successor while keeping its exact descriptor open.
///
/// `prepare` runs before any bytes are written, so a journal can lock the new
/// inode before it can become visible under its final name.
pub(crate) fn prepare_save<'a>(
    path: &'a Path,
    contents: &[u8],
    prepare: impl FnOnce(&File) -> io::Result<()>,
) -> Result<PreparedSave<'a>, SaveError> {
    // The original's mode and ownership, read before anything is written, so
    // that step 5 has something to restore. `None` for a file that does not
    // exist yet, which takes the umask's answer instead.
    let original = fs::metadata(path).ok();

    // A file the user has marked read-only is refused here rather than
    // overwritten. `rename(2)` needs write permission on the *directory* and
    // asks nothing of the target, so without this check the read-only bit would
    // be silently defeated — and §Phase 4 asks for a distinct message and a Save
    // As escape hatch, which is only possible if we stop.
    if let Some(metadata) = &original {
        if metadata.permissions().readonly() {
            return Err(SaveError::ReadOnly {
                path: path.to_path_buf(),
            });
        }
    }

    let temp = temp_path(path);
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&temp)
        .map_err(|error| SaveError::from_io(path, &error))?;
    let mut prepared = PreparedSave {
        path,
        temp,
        file: Some(file),
    };
    let file = prepared.file.as_mut().expect("the prepared file is open");
    prepare(file)
        .and_then(|()| file.write_all(contents))
        .and_then(|()| file.sync_all())
        .map_err(|error| SaveError::from_io(path, &error))?;

    // Step 5, before the rename rather than after: the file that will exist at
    // `path` is the temp file, so it is the one that has to carry the mode. Done
    // after the rename it would be a window in which the new file is visible
    // with the wrong permissions.
    if let Some(metadata) = &original {
        // Best effort by specification — "where permitted". Changing ownership
        // needs `CAP_CHOWN` unless the ids already match, and a save must not
        // fail because a script the user copied in belongs to someone else.
        // Mask to 0o777: the temp file must not inherit setuid/setgid/sticky
        // bits from the original.
        let _ = fs::set_permissions(
            &prepared.temp,
            fs::Permissions::from_mode(metadata.mode() & 0o777),
        );
        let _ =
            std::os::unix::fs::chown(&prepared.temp, Some(metadata.uid()), Some(metadata.gid()));
    }

    Ok(prepared)
}

pub(crate) struct PreparedSave<'a> {
    path: &'a Path,
    temp: PathBuf,
    file: Option<File>,
}

impl PreparedSave<'_> {
    /// Atomically replaces an existing destination without reopening the inode.
    pub(crate) fn publish(mut self) -> io::Result<File> {
        fs::rename(&self.temp, self.path)?;
        sync_directory(self.path);
        Ok(self.file.take().expect("the prepared file is open"))
    }

    /// Publishes a missing destination atomically, refusing any existing entry.
    ///
    /// Linking the already prepared inode has `create_new`'s no-clobber
    /// semantics, without exposing an unlocked or half-written destination.
    pub(crate) fn publish_new(mut self) -> io::Result<File> {
        fs::hard_link(&self.temp, self.path)?;
        let _ = fs::remove_file(&self.temp);
        sync_directory(self.path);
        Ok(self.file.take().expect("the prepared file is open"))
    }
}

impl Drop for PreparedSave<'_> {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.temp);
    }
}

fn sync_directory(path: &Path) {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    // The publication has already happened. As with ordinary atomic saves, a
    // directory sync failure cannot be rolled back.
    if let Ok(handle) = File::open(directory) {
        let _ = handle.sync_all();
    }
}

/// `<name>.tmp-<pid>-<nonce>`, beside the target.
///
/// The pid keeps two Slugline processes saving the same file apart; the nonce
/// keeps one process saving it twice apart, including across a crash, because a
/// leftover temp file from a killed process must never be one we would try to
/// create again. The counter is monotonic within the process and the clock
/// separates processes that reused a pid. The two are concatenated rather than
/// XORed: XOR can collide (`c1^t1 == c2^t2` for distinct pairs) and turn two
/// different saves into the same temp name.
fn temp_path(path: &Path) -> PathBuf {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.subsec_nanos() as u64)
        .unwrap_or(0);
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let temp = format!("{name}.tmp-{}-{counter:x}-{nanos:x}", std::process::id());
    match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.join(temp),
        _ => PathBuf::from(temp),
    }
}

/// Whether a directory entry is one of our temporary files.
///
/// The library scan uses this: a save in flight must not show up as a script.
/// Matched as `<name>.tmp-<pid>-<hex>(-<hex>)?` so that a script legitimately
/// named `my.tmp-foo.fountain` is still listed.
pub fn is_temp_file(name: &str) -> bool {
    let Some(dot_tmp) = name.rfind(".tmp-") else {
        return false;
    };
    let suffix = &name[dot_tmp + ".tmp-".len()..];
    let mut parts = suffix.split('-');
    let pid_ok = parts
        .next()
        .is_some_and(|pid| !pid.is_empty() && pid.bytes().all(|b| b.is_ascii_digit()));
    // One hex part (old `<pid>-<nonce>` names) or two (new
    // `<pid>-<counter>-<nanos>` names); both are ours.
    let mut hex_parts = 0;
    let mut all_hex = true;
    for part in parts {
        if part.is_empty() || !part.bytes().all(|b| b.is_ascii_hexdigit()) {
            all_hex = false;
            break;
        }
        hex_parts += 1;
    }
    pid_ok && all_hex && (hex_parts == 1 || hex_parts == 2)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;

    #[test]
    fn a_save_writes_the_bytes_and_leaves_no_temp_file() {
        let dir = TempDir::new("atomic-write");
        let path = dir.path().join("script.fountain");
        save_atomically(&path, "INT. HOUSE - DAY\n").expect("the save succeeds");

        assert_eq!(fs::read_to_string(&path).unwrap(), "INT. HOUSE - DAY\n");
        assert_eq!(dir.entries().len(), 1, "only the script is left");
    }

    #[test]
    fn a_second_save_replaces_the_first() {
        let dir = TempDir::new("atomic-replace");
        let path = dir.path().join("script.fountain");
        save_atomically(&path, "first\n").unwrap();
        save_atomically(&path, "second\n").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "second\n");
        assert_eq!(dir.entries().len(), 1);
    }

    #[test]
    fn the_temp_file_is_a_sibling_of_the_target() {
        // Not `/tmp`: `rename(2)` is atomic only within one filesystem, and the
        // whole guarantee rests on that.
        let temp = temp_path(Path::new("/home/writer/scripts/heat.fountain"));
        assert_eq!(temp.parent(), Some(Path::new("/home/writer/scripts")));
        let name = temp.file_name().unwrap().to_string_lossy().into_owned();
        assert!(name.starts_with("heat.fountain.tmp-"), "{name}");
        assert!(name.contains(&std::process::id().to_string()));
        assert!(is_temp_file(&name));
    }

    #[test]
    fn two_temp_paths_never_collide() {
        let path = Path::new("/tmp/x.fountain");
        let mut seen = std::collections::HashSet::new();
        for _ in 0..1000 {
            assert!(seen.insert(temp_path(path)), "a nonce repeated");
        }
    }

    #[test]
    fn the_mode_of_an_existing_file_survives_a_save() {
        let dir = TempDir::new("atomic-mode");
        let path = dir.path().join("script.fountain");
        fs::write(&path, "first\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o640)).unwrap();

        save_atomically(&path, "second\n").unwrap();
        let mode = fs::metadata(&path).unwrap().mode() & 0o777;
        assert_eq!(
            mode, 0o640,
            "the rename must not reset the mode to the umask's"
        );
    }

    #[test]
    fn a_read_only_file_is_refused_rather_than_overwritten() {
        let dir = TempDir::new("atomic-readonly");
        let path = dir.path().join("script.fountain");
        fs::write(&path, "original\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o444)).unwrap();

        let error = save_atomically(&path, "new\n").expect_err("a read-only file refuses");
        assert!(matches!(error, SaveError::ReadOnly { .. }), "{error:?}");
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "original\n",
            "and the file is untouched"
        );
        assert_eq!(dir.entries().len(), 1, "with no temp file beside it");
    }

    #[test]
    fn a_missing_directory_is_its_own_error() {
        let dir = TempDir::new("atomic-missing");
        let path = dir.path().join("nowhere").join("script.fountain");
        let error = save_atomically(&path, "text\n").expect_err("there is no directory");
        assert!(
            matches!(error, SaveError::NoSuchDirectory { .. }),
            "{error:?}"
        );
    }

    #[test]
    fn an_unwritable_directory_is_permission_denied() {
        let dir = TempDir::new("atomic-perm");
        let closed = dir.path().join("closed");
        fs::create_dir(&closed).unwrap();
        fs::set_permissions(&closed, fs::Permissions::from_mode(0o500)).unwrap();

        let path = closed.join("script.fountain");
        let error = save_atomically(&path, "text\n").expect_err("the directory is closed");
        // Running as root defeats the permission bits entirely, and CI does.
        if !matches!(error, SaveError::PermissionDenied { .. }) {
            assert!(
                std::os::unix::fs::MetadataExt::uid(&fs::metadata(&closed).unwrap()) == 0,
                "unexpected error: {error:?}"
            );
        }
        fs::set_permissions(&closed, fs::Permissions::from_mode(0o700)).unwrap();
    }

    #[test]
    fn every_error_carries_the_path_the_user_asked_for() {
        // Not the temp file's path. The user chose one file name and it is the
        // one that has to appear in the message.
        let dir = TempDir::new("atomic-path");
        let path = dir.path().join("nowhere").join("script.fountain");
        let error = save_atomically(&path, "text\n").unwrap_err();
        assert_eq!(error.path(), path);
    }
}
