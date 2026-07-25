//! Noticing that a file changed underneath us (§Phase 4, "external
//! modification").
//!
//! ## Why the directory and not the file
//!
//! An inotify watch follows the **inode**, not the name. Every careful writer of
//! files on Linux saves the way [`crate::atomic`] does — write a temp file,
//! rename it over the target — so after one save by another editor, a watch
//! placed on the file is watching an inode that nothing refers to any more, and
//! it will never fire again. Watching the containing directory and filtering by
//! name is the only version of this that keeps working. It is also what catches
//! the file being deleted or replaced by `git checkout`.
//!
//! ## Why there is no timer
//!
//! `notify`'s default features include a polling backend for filesystems inotify
//! cannot watch. It is off (see `Cargo.toml`): §1.3 budgets idle CPU at zero,
//! and a poller is a wakeup several times a second for a question whose answer
//! is almost always "no". The cost of the choice is that a script on an NFS
//! mount will not report external changes, which is the right trade — the
//! feature is a convenience, and the save path protects the file either way.
//!
//! ## What it does not decide
//!
//! Whether to reload silently or to ask is not this module's business. It
//! reports that a path changed; the bridge knows whether the document is dirty,
//! and §Phase 4 makes the decision turn entirely on that.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use notify::event::{EventKind, ModifyKind, RenameMode};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};

/// Watches the files of the open documents.
pub struct FileWatcher {
    watcher: RecommendedWatcher,
    /// Directory → how many watched files are in it. A directory is unwatched
    /// when its last file is.
    directories: HashMap<PathBuf, usize>,
    watched: Arc<Mutex<Vec<PathBuf>>>,
}

impl FileWatcher {
    /// Starts a watcher that calls `on_change` with the path of any watched file
    /// that changed.
    ///
    /// `on_change` runs on `notify`'s own thread, so it must not block. In the
    /// bridge it does one thing: push a `CoreEvent` at Dart.
    pub fn new(on_change: impl Fn(PathBuf) + Send + 'static) -> notify::Result<FileWatcher> {
        let watched: Arc<Mutex<Vec<PathBuf>>> = Arc::new(Mutex::new(Vec::new()));
        let interesting = Arc::clone(&watched);
        let watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
            let Ok(event) = event else { return };
            if !is_content_change(&event.kind) {
                return;
            }
            let Ok(watched) = interesting.lock() else {
                return;
            };
            for path in &event.paths {
                // The directory watch reports every file in the directory. Only
                // the ones somebody asked about are anybody's business.
                if watched.iter().any(|candidate| candidate == path) {
                    on_change(path.clone());
                }
            }
        })?;
        Ok(FileWatcher {
            watcher,
            directories: HashMap::new(),
            watched,
        })
    }

    /// Starts reporting changes to `path`.
    pub fn watch(&mut self, path: &Path) -> notify::Result<()> {
        let Some(directory) = path.parent() else {
            return Ok(());
        };
        {
            let mut watched = self.watched.lock().expect("watch list mutex poisoned");
            if watched.iter().any(|candidate| candidate == path) {
                return Ok(());
            }
            watched.push(path.to_path_buf());
        }
        let count = self.directories.entry(directory.to_path_buf()).or_insert(0);
        *count += 1;
        if *count == 1 {
            // Non-recursive: we care about one directory's own entries, and a
            // recursive watch on a home directory full of scripts would be a
            // descriptor per subdirectory for no benefit.
            self.watcher.watch(directory, RecursiveMode::NonRecursive)?;
        }
        Ok(())
    }

    /// Stops reporting changes to `path`.
    pub fn unwatch(&mut self, path: &Path) -> notify::Result<()> {
        {
            let mut watched = self.watched.lock().expect("watch list mutex poisoned");
            let before = watched.len();
            watched.retain(|candidate| candidate != path);
            if watched.len() == before {
                return Ok(());
            }
        }
        let Some(directory) = path.parent() else {
            return Ok(());
        };
        if let Some(count) = self.directories.get_mut(directory) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                self.directories.remove(directory);
                self.watcher.unwatch(directory)?;
            }
        }
        Ok(())
    }

    /// The files currently being watched, for tests and for the bridge's own
    /// assertions.
    pub fn watching(&self) -> Vec<PathBuf> {
        self.watched
            .lock()
            .map(|watched| watched.clone())
            .unwrap_or_default()
    }
}

/// Whether an event means "the bytes at this path may be different now".
///
/// Access times and permission changes are not that. A rename **to** a path is,
/// because that is exactly how another editor's atomic save arrives, and so is a
/// removal — a script that vanished is news.
fn is_content_change(kind: &EventKind) -> bool {
    matches!(
        kind,
        EventKind::Any
            | EventKind::Create(_)
            | EventKind::Remove(_)
            | EventKind::Modify(
                ModifyKind::Any
                    | ModifyKind::Data(_)
                    | ModifyKind::Name(RenameMode::To | RenameMode::Both)
            )
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;
    use notify::event::{AccessKind, DataChange, MetadataKind};
    use std::sync::mpsc;
    use std::time::Duration;

    #[test]
    fn a_write_to_a_watched_file_is_reported() {
        let dir = TempDir::new("watch-write");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let (sender, receiver) = mpsc::channel();
        let mut watcher = FileWatcher::new(move |path| {
            let _ = sender.send(path);
        })
        .expect("inotify is available");
        watcher.watch(&script).unwrap();

        std::fs::write(&script, "somebody else wrote this\n").unwrap();
        let changed = receiver
            .recv_timeout(Duration::from_secs(5))
            .expect("the change is reported");
        assert_eq!(changed, script);
    }

    #[test]
    fn a_save_by_rename_is_reported_too() {
        // The case a watch on the file itself would miss entirely: this is how
        // every careful editor on this platform saves, ours included.
        let dir = TempDir::new("watch-rename");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let (sender, receiver) = mpsc::channel();
        let mut watcher = FileWatcher::new(move |path| {
            let _ = sender.send(path);
        })
        .unwrap();
        watcher.watch(&script).unwrap();

        let temp = dir.path().join("heat.fountain.tmp-1-2");
        std::fs::write(&temp, "replaced\n").unwrap();
        std::fs::rename(&temp, &script).unwrap();

        let changed = receiver
            .recv_timeout(Duration::from_secs(5))
            .expect("a rename over the file is a change");
        assert_eq!(changed, script);
    }

    #[test]
    fn a_change_to_a_neighbour_is_not_reported() {
        let dir = TempDir::new("watch-neighbour");
        let script = dir.path().join("heat.fountain");
        let other = dir.path().join("other.fountain");
        std::fs::write(&script, "a\n").unwrap();
        std::fs::write(&other, "b\n").unwrap();

        let (sender, receiver) = mpsc::channel();
        let mut watcher = FileWatcher::new(move |path| {
            let _ = sender.send(path);
        })
        .unwrap();
        watcher.watch(&script).unwrap();

        std::fs::write(&other, "changed\n").unwrap();
        assert!(
            receiver.recv_timeout(Duration::from_millis(500)).is_err(),
            "the directory watch must not leak its other entries"
        );
    }

    #[test]
    fn unwatching_stops_the_reports() {
        let dir = TempDir::new("watch-stop");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "a\n").unwrap();

        let (sender, receiver) = mpsc::channel();
        let mut watcher = FileWatcher::new(move |path| {
            let _ = sender.send(path);
        })
        .unwrap();
        watcher.watch(&script).unwrap();
        assert_eq!(watcher.watching(), vec![script.clone()]);
        watcher.unwatch(&script).unwrap();
        assert!(watcher.watching().is_empty());

        std::fs::write(&script, "changed\n").unwrap();
        assert!(receiver.recv_timeout(Duration::from_millis(500)).is_err());
    }

    #[test]
    fn two_scripts_in_one_directory_share_a_watch() {
        let dir = TempDir::new("watch-share");
        let one = dir.path().join("one.fountain");
        let two = dir.path().join("two.fountain");
        std::fs::write(&one, "a\n").unwrap();
        std::fs::write(&two, "b\n").unwrap();

        let mut watcher = FileWatcher::new(|_| {}).unwrap();
        watcher.watch(&one).unwrap();
        watcher.watch(&two).unwrap();
        assert_eq!(watcher.directories.len(), 1);
        assert_eq!(watcher.directories[dir.path()], 2);

        // Closing one script must not stop the other from being watched.
        watcher.unwatch(&one).unwrap();
        assert_eq!(watcher.directories[dir.path()], 1);
        watcher.unwatch(&two).unwrap();
        assert!(watcher.directories.is_empty());
    }

    #[test]
    fn reading_a_file_is_not_a_change() {
        assert!(!is_content_change(&EventKind::Access(AccessKind::Read)));
        assert!(!is_content_change(&EventKind::Modify(
            ModifyKind::Metadata(MetadataKind::AccessTime)
        )));
        assert!(is_content_change(&EventKind::Modify(ModifyKind::Data(
            DataChange::Content
        ))));
        assert!(is_content_change(&EventKind::Modify(ModifyKind::Name(
            RenameMode::To
        ))));
    }
}
