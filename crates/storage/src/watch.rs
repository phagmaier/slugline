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
//!
//! It does decide one thing: whether the change was **ours**. See [`OwnWrites`].
//!
//! ## And what it is not allowed to be
//!
//! Everything above can fail to run at all, and on somebody's machine it does:
//! a kernel without inotify, a filesystem it cannot watch, a process that has
//! reached `max_user_watches`. The paragraph above about NFS says the same thing
//! from the other side. So this is a **prompt** mechanism, not a correctness
//! boundary — the thing that makes overwriting somebody else's edits impossible
//! is [`DiskState`], which the save path consults on the way to the disk whether
//! there is a watcher or not.

use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use notify::event::{EventKind, ModifyKind, RenameMode};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};

/// Watches the files of the open documents.
pub struct FileWatcher {
    watcher: RecommendedWatcher,
    /// Directory → how many watched files are in it. A directory is unwatched
    /// when its last file is.
    directories: HashMap<PathBuf, usize>,
    watched: Arc<Mutex<Vec<PathBuf>>>,
    own: Arc<OwnWrites>,
}

impl FileWatcher {
    /// Starts a watcher that calls `on_change` with the path of any watched file
    /// that changed — except when `own` says we changed it ourselves.
    ///
    /// `on_change` runs on `notify`'s own thread, so it must not block. In the
    /// bridge it does one thing: push a `CoreEvent` at Dart.
    pub fn new(
        own: Arc<OwnWrites>,
        on_change: impl Fn(PathBuf) + Send + 'static,
    ) -> notify::Result<FileWatcher> {
        let watched: Arc<Mutex<Vec<PathBuf>>> = Arc::new(Mutex::new(Vec::new()));
        let interesting = Arc::clone(&watched);
        let ours = Arc::clone(&own);
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
                if !watched.iter().any(|candidate| candidate == path) {
                    continue;
                }
                // …and the echo of our own save is nobody's business at all.
                if ours.is_echo(path) {
                    continue;
                }
                on_change(path.clone());
            }
        })?;
        Ok(FileWatcher {
            watcher,
            directories: HashMap::new(),
            watched,
            own,
        })
    }

    /// The register of writes this application made itself, for the save path to
    /// record into.
    pub fn own_writes(&self) -> Arc<OwnWrites> {
        Arc::clone(&self.own)
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
        if !self.directories.contains_key(directory) {
            // Non-recursive: we care about one directory's own entries, and a
            // recursive watch on a home directory full of scripts would be a
            // descriptor per subdirectory for no benefit.
            if let Err(error) = self.watcher.watch(directory, RecursiveMode::NonRecursive) {
                // A retry (or another script in this directory) must not claim
                // a watch the OS never installed. Roll back the path too.
                self.watched
                    .lock()
                    .expect("watch list mutex poisoned")
                    .retain(|candidate| candidate != path);
                return Err(error);
            }
        }
        // Count only successful registrations. The list lock above is released
        // before calling the backend, which may be delivering an event itself.
        *self.directories.entry(directory.to_path_buf()).or_insert(0) += 1;
        Ok(())
    }

    /// Stops reporting changes to `path`.
    pub fn unwatch(&mut self, path: &Path) -> notify::Result<()> {
        // A path nobody is watching cannot produce an event to suppress, so the
        // record for it is dead weight. This is one of the two places stale
        // suppression is cleared; the other is an event that does not match it.
        self.own.forget(path);
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

/// The writes this application made itself, so that the watcher can tell its own
/// echo from somebody else's editor (F4, ADR 0024, ADR 0028).
///
/// ## Why this is needed at all
///
/// [`crate::atomic`] saves by renaming over the target, and the watch is on the
/// directory, so **every save this application makes produces an event about
/// itself**. That was harmless while the check that follows the event —
/// `doc_external_change` — could answer "unmodified here, identical there". It
/// stops being harmless the moment the writer types between the rename and the
/// event being handled: the document is then dirty and different, and they get a
/// modal accusing another program of writing their file, about their own
/// autosave.
///
/// ## The lifecycle of one record
///
/// One record per path, holding a generation and — once there is one — a
/// fingerprint of the file we produced.
///
/// 1. **[`OwnWrites::begin`]**, immediately before the bytes go to the disk.
///    Records the path with no fingerprint yet and returns a generation. From
///    here until step 2 the path is *in flight*, and every event about it is
///    swallowed: it is either the rename we are in the middle of, or a write by
///    somebody else that our rename is about to overwrite regardless.
/// 2. **[`OwnWrites::finished`]**, immediately after a successful write, or
///    **[`OwnWrites::abandoned`]** after a failed one. `finished` stats the file
///    and stores what it found; `abandoned` drops the record, because a write
///    that did not happen has no echo to suppress. Both ignore a record a later
///    write has since claimed, which is what the generation is for.
/// 3. **[`OwnWrites::is_echo`]**, on `notify`'s thread, for every event about a
///    watched path. A record whose fingerprint still describes the file means
///    the file is *exactly* what we wrote, and there is nothing to report. A
///    fingerprint that no longer matches means somebody else has been here
///    since: the record is dropped and the event is reported.
/// 4. **[`OwnWrites::forget`]**, when the path stops being watched or the
///    session moves to another one.
///
/// Nothing here expires on a clock. A record is cleared by the first event that
/// contradicts it, by the next write to the same path, or by `forget` — and one
/// that is never cleared costs a `HashMap` entry for a file the application has
/// open. §1.3's idle budget is why: a timer to sweep a few paths would be a
/// wakeup in an idle process, and there is nothing here that gets less true with
/// age.
///
/// ## What it deliberately does not do
///
/// It never decides that a file *has* changed — only that one particular event
/// is our own noise. `doc_external_change` still reads the file and compares it,
/// for every event that gets through, and that is what remains authoritative
/// (ADR 0024). Losing a record costs one spurious prompt; it cannot cost
/// correctness.
#[derive(Default)]
pub struct OwnWrites {
    writes: Mutex<HashMap<PathBuf, OwnWrite>>,
    next_generation: AtomicU64,
}

struct OwnWrite {
    /// Which write this record belongs to. A `finished` or `abandoned` call
    /// carrying an older generation is one whose record has already been taken
    /// over by a newer write, and it must not touch it.
    generation: u64,
    /// The file as our write left it. `None` while the write is still at the
    /// disk.
    wrote: Option<FileFingerprint>,
}

/// Enough of a file's identity to say "this is still exactly the file we wrote,
/// and nothing has happened to it since".
///
/// The inode and device because an atomic save replaces the file rather than
/// editing it, so anybody else's save changes them; the length and the
/// modification time because an in-place write does not. Linux timestamps are
/// nanosecond-resolution, so two distinct writes cannot share one.
///
/// It answers "has anything happened here", never "are the bytes different" — a
/// file rewritten with the bytes it already had has a new fingerprint and the
/// same contents. That is why [`DiskState`] carries a second half.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct FileFingerprint {
    device: u64,
    inode: u64,
    len: u64,
    modified_secs: i64,
    modified_nanos: i64,
}

impl FileFingerprint {
    /// One `stat`. This runs on `notify`'s thread, where blocking is forbidden,
    /// and only for a path this process has itself just written — so the inode
    /// is in the kernel's cache and this is not a disk read.
    pub fn of(path: &Path) -> Option<FileFingerprint> {
        let metadata = std::fs::metadata(path).ok()?;
        Some(FileFingerprint {
            device: metadata.dev(),
            inode: metadata.ino(),
            len: metadata.len(),
            modified_secs: metadata.mtime(),
            modified_nanos: metadata.mtime_nsec(),
        })
    }
}

/// What a file held when this application last read or wrote it — the record a
/// save checks before it replaces those bytes with something else.
///
/// ## Why the save path needs its own answer
///
/// The watcher above is how the writer finds out *promptly* that another program
/// has been in their script, and §Phase 4's whole external-modification rule
/// hangs off it. But it is a convenience that a machine is entitled not to
/// provide (see the module comment), and until this existed a save path with no
/// watcher behind it would replace an external edit without a word — the
/// protection would be missing exactly where nobody could see it was missing.
///
/// So the check moved to where the overwrite happens. A save compares this
/// against the file it is about to replace, and a file that is not what we left
/// there is not overwritten until somebody has decided about it. The watcher
/// becomes what it should always have been: the thing that asks the question
/// early, rather than the only thing that asks it.
///
/// ## The two halves
///
/// The `stat` is the cheap half and is asked first: unchanged means the file has
/// not been touched at all since we left it, which is the answer on every save
/// of every session where nothing is wrong, and it costs one cached `stat`.
///
/// The content hash is the half that decides, and it is only ever consulted when
/// the `stat` says something happened. `touch`, a `git checkout` that restored
/// the same text, another editor writing back what it read: all of those change
/// a file's identity without changing a screenplay, and prompting about them
/// would train the writer to dismiss the prompt that matters.
///
/// A 64-bit hash rather than the bytes themselves, because the alternative is
/// holding a second copy of every open script in memory for a comparison that
/// happens once per save. It is never persisted and never crosses a process
/// boundary, so it needs no stability beyond this run.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct DiskState {
    /// `None` when the file could not be stat'ed when the record was made —
    /// which forces the content read below rather than skipping the check.
    stat: Option<FileFingerprint>,
    contents: u64,
}

/// What [`DiskState::compare`] found at the path.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DiskVerdict {
    /// Nothing has happened to the file since we last wrote or read it.
    Unchanged,
    /// Something rewrote it with the bytes it already had. There is nothing to
    /// decide, and the refreshed record is here so the next save can go back to
    /// answering with one `stat`.
    Restamped(DiskState),
    /// The file holds bytes we have never seen. A save must not replace them
    /// until somebody has been asked.
    Changed,
    /// The file cannot be read now: deleted, or replaced by something that is
    /// not text.
    ///
    /// **Not** a refusal. A save refused here would be a save refused with no
    /// way for the writer to resolve it — the prompt that follows a refusal
    /// reads the file too — and the certain cost of that is the writer's text
    /// staying in memory, against a suspicion about bytes that are already gone.
    Unreadable,
}

impl DiskState {
    /// What we know about `path` having just written or read `contents` there.
    ///
    /// The `stat` happens after the bytes, deliberately: it describes the file
    /// as it is now, not as the write intended it.
    pub fn recorded(path: &Path, contents: &str) -> DiskState {
        DiskState {
            stat: FileFingerprint::of(path),
            contents: hash_of(contents),
        }
    }

    /// Whether `path` still holds what this record says it does.
    ///
    /// Off the actor thread: the second branch reads the whole file.
    pub fn compare(&self, path: &Path) -> DiskVerdict {
        let now = FileFingerprint::of(path);
        if now.is_some() && now == self.stat {
            return DiskVerdict::Unchanged;
        }
        let Ok(contents) = std::fs::read_to_string(path) else {
            return DiskVerdict::Unreadable;
        };
        if hash_of(&contents) != self.contents {
            return DiskVerdict::Changed;
        }
        DiskVerdict::Restamped(DiskState {
            stat: now,
            contents: self.contents,
        })
    }
}

fn hash_of(contents: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    contents.as_bytes().hash(&mut hasher);
    hasher.finish()
}

impl OwnWrites {
    pub fn shared() -> Arc<OwnWrites> {
        Arc::new(OwnWrites::default())
    }

    /// Step 1: we are about to write `path`. Returns the generation to hand back
    /// when the write ends, either way.
    pub fn begin(&self, path: &Path) -> u64 {
        let generation = self.next_generation.fetch_add(1, Ordering::Relaxed) + 1;
        self.writes().insert(
            path.to_path_buf(),
            OwnWrite {
                generation,
                wrote: None,
            },
        );
        generation
    }

    /// Step 2, on success: what we wrote is now the file.
    ///
    /// A file we cannot stat is one we cannot recognise later, so the record
    /// goes rather than staying behind as an in-flight write that never ends —
    /// the event falls through to `doc_external_change`, which is the backstop.
    pub fn finished(&self, path: &Path, generation: u64) {
        let mut writes = self.writes();
        let Some(write) = writes.get_mut(path) else {
            return;
        };
        if write.generation != generation {
            return;
        }
        match FileFingerprint::of(path) {
            Some(fingerprint) => write.wrote = Some(fingerprint),
            None => {
                writes.remove(path);
            }
        }
    }

    /// Step 2, on failure: there is no echo, because there was no write.
    pub fn abandoned(&self, path: &Path, generation: u64) {
        let mut writes = self.writes();
        if writes
            .get(path)
            .is_some_and(|write| write.generation == generation)
        {
            writes.remove(path);
        }
    }

    /// Step 3: is this event about a file we ourselves put there?
    ///
    /// Answered for **every** event describing that file, not just the first.
    /// One atomic save is one rename, but a filesystem is entitled to report it
    /// as several events — a create and a modify, or a rename pair — and
    /// "swallow one" would let the rest through as a phantom external change.
    /// The fingerprint is what makes that safe: the second event is swallowed
    /// because the file is still ours, not because we are counting.
    pub fn is_echo(&self, path: &Path) -> bool {
        let mut writes = self.writes();
        let Some(write) = writes.get(path) else {
            return false;
        };
        let Some(ours) = write.wrote else {
            // In flight. See the lifecycle above: our own rename is imminent, so
            // whatever this event is, the file is about to be ours.
            return true;
        };
        if FileFingerprint::of(path) == Some(ours) {
            return true;
        }
        // Somebody else has written since we did. The record describes a version
        // of this file that no longer exists, so it goes — and this event, and
        // every one after it, is real.
        writes.remove(path);
        false
    }

    /// Step 4: this path is no longer ours to suppress.
    pub fn forget(&self, path: &Path) {
        self.writes().remove(path);
    }

    /// A poisoned lock here means a previous holder panicked mid-update. There is
    /// nothing to be inconsistent — a map of hints — and refusing to suppress
    /// echoes for the rest of the session would be a worse answer than carrying
    /// on.
    fn writes(&self) -> impl std::ops::DerefMut<Target = HashMap<PathBuf, OwnWrite>> + '_ {
        self.writes.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// How many suppression records are being held, so that a test can prove
    /// they do not accumulate.
    pub fn len(&self) -> usize {
        self.writes().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
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

    /// How long an event is given to arrive before the test calls it missing,
    /// and how long the absence of one is watched for before the test calls it
    /// absent. The second is the expensive direction, so it is the shorter one.
    const ARRIVES: Duration = Duration::from_secs(5);
    const STAYS_QUIET: Duration = Duration::from_millis(750);

    #[test]
    fn a_failed_watch_is_not_registered_and_can_be_retried() {
        let dir = TempDir::new("watch-retry");
        let missing = dir.path().join("not-created-yet");
        let first = missing.join("first.fountain");
        let second = missing.join("second.fountain");
        let (send, recv) = mpsc::channel();
        let mut watcher = FileWatcher::new(Arc::new(OwnWrites::default()), move |path| {
            let _ = send.send(path);
        })
        .unwrap();

        assert!(watcher.watch(&first).is_err());
        assert!(watcher.watching().is_empty());
        assert!(watcher.watch(&first).is_err(), "a retry must reach the OS");
        assert!(watcher.watch(&second).is_err(), "no directory watch exists");

        std::fs::create_dir(&missing).unwrap();
        watcher.watch(&first).unwrap();
        std::fs::write(&first, "INT. HOUSE - DAY\n").unwrap();
        assert_eq!(recv.recv_timeout(ARRIVES).unwrap(), first);
        watcher.unwatch(&first).unwrap();
        assert!(watcher.watching().is_empty());
    }

    /// Everything a suppression test needs: a watched script, the register the
    /// save path writes into, and the events that got through.
    struct Watched {
        _dir: TempDir,
        script: PathBuf,
        own: Arc<OwnWrites>,
        reported: mpsc::Receiver<PathBuf>,
        _watcher: FileWatcher,
    }

    impl Watched {
        fn new(label: &str) -> Watched {
            let dir = TempDir::new(label);
            let script = dir.path().join("heat.fountain");
            std::fs::write(&script, "original\n").unwrap();

            let own = OwnWrites::shared();
            let (sender, reported) = mpsc::channel();
            let mut watcher = FileWatcher::new(Arc::clone(&own), move |path| {
                let _ = sender.send(path);
            })
            .expect("inotify is available");
            watcher.watch(&script).unwrap();
            Watched {
                _dir: dir,
                script,
                own,
                reported,
                _watcher: watcher,
            }
        }

        /// A save by this application, through the real atomic sequence, with the
        /// correlation the bridge's save path performs around it.
        fn we_save(&self, text: &str) {
            let generation = self.own.begin(&self.script);
            crate::atomic::save_atomically(&self.script, text).expect("the save works");
            self.own.finished(&self.script, generation);
        }

        /// Somebody else's editor, saving the same way.
        fn somebody_else_saves(&self, text: &str) {
            crate::atomic::save_atomically(&self.script, text).expect("the save works");
        }

        fn reported(&self) -> bool {
            self.reported.recv_timeout(ARRIVES).is_ok()
        }

        fn stayed_quiet(&self) -> bool {
            self.reported.recv_timeout(STAYS_QUIET).is_err()
        }
    }

    /// F4. The event our own save causes must not reach the bridge, because by
    /// the time Dart handles it the writer may have typed — and then the check
    /// finds the document dirty and different, and accuses another program of
    /// writing the file.
    #[test]
    fn our_own_save_is_not_reported() {
        let it = Watched::new("watch-own-save");
        it.we_save("we wrote this\n");
        assert!(
            it.stayed_quiet(),
            "the watcher reported the application's own save"
        );
    }

    /// The other half, and the one that would make the repair worthless if it
    /// failed: suppression must not outlive the write it describes.
    #[test]
    fn an_external_write_straight_after_our_own_save_is_still_reported() {
        let it = Watched::new("watch-own-then-theirs");
        it.we_save("we wrote this\n");
        assert!(it.stayed_quiet());

        it.somebody_else_saves("they wrote this\n");
        assert!(
            it.reported(),
            "a real external change was eaten by the suppression of our own"
        );
    }

    /// Two saves in a row are two records, not a record and an echo of one.
    #[test]
    fn a_second_save_suppresses_its_own_event_too() {
        let it = Watched::new("watch-two-saves");
        it.we_save("first\n");
        it.we_save("second\n");
        assert!(it.stayed_quiet());
        assert_eq!(it.own.len(), 1, "one path, one record");
    }

    /// One atomic save is one rename, but a filesystem is entitled to report it
    /// as several events. Suppression is a property of the file, not a count, so
    /// asking twice gives the same answer — which is what a second event is.
    #[test]
    fn every_event_from_one_save_is_swallowed_not_just_the_first() {
        let dir = TempDir::new("own-many-events");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let generation = own.begin(&script);
        crate::atomic::save_atomically(&script, "ours\n").unwrap();
        own.finished(&script, generation);

        for event in 0..5 {
            assert!(own.is_echo(&script), "event {event} was let through");
        }
    }

    /// The window the ADR 0024 sequence left open: the event can arrive before
    /// the write that caused it has finished being recorded.
    #[test]
    fn an_event_while_we_are_still_writing_is_swallowed() {
        let dir = TempDir::new("own-in-flight");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        own.begin(&script);
        assert!(own.is_echo(&script), "an in-flight write reports itself");
    }

    /// A write that failed wrote nothing, so there is no echo — and leaving the
    /// record behind would swallow the next real event about the file.
    #[test]
    fn an_abandoned_write_suppresses_nothing() {
        let dir = TempDir::new("own-abandoned");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let generation = own.begin(&script);
        own.abandoned(&script, generation);
        assert!(!own.is_echo(&script));
        assert!(own.is_empty(), "and it left nothing behind");
    }

    /// Generations: a record belongs to one write, and the write that has been
    /// overtaken must not finish or abandon somebody else's.
    #[test]
    fn a_write_cannot_finish_or_abandon_a_later_writes_record() {
        let dir = TempDir::new("own-generations");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let overtaken = own.begin(&script);
        let current = own.begin(&script);
        assert_ne!(overtaken, current);

        own.abandoned(&script, overtaken);
        assert!(
            own.is_echo(&script),
            "the older write cleared the newer one's record"
        );

        // And the older one cannot fingerprint it either: after its `finished`
        // the record must still be the newer write's, in flight.
        std::fs::write(&script, "somebody else\n").unwrap();
        own.finished(&script, overtaken);
        assert!(own.is_echo(&script));
        own.finished(&script, current);
        assert!(
            own.is_echo(&script),
            "the newer write recorded what it wrote"
        );
    }

    /// Stale records are cleared by the event that contradicts them, so nothing
    /// accumulates for a file somebody else is also editing.
    #[test]
    fn the_event_that_did_not_match_clears_the_record() {
        let dir = TempDir::new("own-stale");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let generation = own.begin(&script);
        crate::atomic::save_atomically(&script, "ours\n").unwrap();
        own.finished(&script, generation);
        assert_eq!(own.len(), 1);

        crate::atomic::save_atomically(&script, "theirs\n").unwrap();
        assert!(!own.is_echo(&script));
        assert!(
            own.is_empty(),
            "a record that has been contradicted once is not kept to be asked again"
        );
    }

    /// A file that is gone is news, not an echo — even if the last thing that
    /// happened to it was our own save.
    #[test]
    fn a_deleted_file_is_not_our_own_write() {
        let dir = TempDir::new("own-deleted");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let generation = own.begin(&script);
        crate::atomic::save_atomically(&script, "ours\n").unwrap();
        own.finished(&script, generation);

        std::fs::remove_file(&script).unwrap();
        assert!(!own.is_echo(&script));
    }

    /// Closing a script drops its suppression record with its watch.
    #[test]
    fn unwatching_forgets_what_we_wrote_there() {
        let dir = TempDir::new("own-unwatch");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let own = OwnWrites::shared();
        let mut watcher = FileWatcher::new(Arc::clone(&own), |_| {}).unwrap();
        watcher.watch(&script).unwrap();
        let generation = own.begin(&script);
        crate::atomic::save_atomically(&script, "ours\n").unwrap();
        own.finished(&script, generation);
        assert_eq!(own.len(), 1);

        watcher.unwatch(&script).unwrap();
        assert!(own.is_empty());
    }

    #[test]
    fn a_write_to_a_watched_file_is_reported() {
        let dir = TempDir::new("watch-write");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "original\n").unwrap();

        let (sender, receiver) = mpsc::channel();
        let mut watcher = FileWatcher::new(OwnWrites::shared(), move |path| {
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
        let mut watcher = FileWatcher::new(OwnWrites::shared(), move |path| {
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
        let mut watcher = FileWatcher::new(OwnWrites::shared(), move |path| {
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
        let mut watcher = FileWatcher::new(OwnWrites::shared(), move |path| {
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

        let mut watcher = FileWatcher::new(OwnWrites::shared(), |_| {}).unwrap();
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

    // -----------------------------------------------------------------------
    // The half that does not depend on inotify running at all
    // -----------------------------------------------------------------------

    /// The ordinary answer, and the one every save of every quiet session gets:
    /// one `stat`, and the file is the one we left.
    #[test]
    fn a_file_nobody_touched_is_unchanged() {
        let dir = TempDir::new("disk-quiet");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "ours\n").unwrap();

        let known = DiskState::recorded(&script, "ours\n");
        assert_eq!(known.compare(&script), DiskVerdict::Unchanged);
    }

    /// The one that matters: another program's save, seen by a save path with no
    /// watcher behind it at all.
    #[test]
    fn somebody_elses_bytes_are_a_change() {
        let dir = TempDir::new("disk-theirs");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "ours\n").unwrap();
        let known = DiskState::recorded(&script, "ours\n");

        crate::atomic::save_atomically(&script, "theirs\n").unwrap();
        assert_eq!(known.compare(&script), DiskVerdict::Changed);
    }

    /// `touch`, a `git checkout` that restored the same text, another editor
    /// writing back what it read. The file's identity is new and the screenplay
    /// is not, and prompting about it would train the writer to dismiss the
    /// prompt that matters.
    #[test]
    fn the_same_bytes_written_again_are_not_a_change() {
        let dir = TempDir::new("disk-restamp");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "ours\n").unwrap();
        let known = DiskState::recorded(&script, "ours\n");

        // Through the atomic sequence, so the inode and the timestamps are all
        // new — everything the cheap half of the check looks at.
        crate::atomic::save_atomically(&script, "ours\n").unwrap();
        let DiskVerdict::Restamped(refreshed) = known.compare(&script) else {
            panic!("identical bytes were reported as somebody else's edit");
        };
        assert_eq!(
            refreshed.compare(&script),
            DiskVerdict::Unchanged,
            "the refreshed record must cost one stat next time, not another read"
        );
    }

    /// A file that is gone cannot be compared — and must not be a refusal, or a
    /// writer whose script was deleted under them could not save it anywhere.
    #[test]
    fn a_file_that_is_gone_is_unreadable_rather_than_changed() {
        let dir = TempDir::new("disk-deleted");
        let script = dir.path().join("heat.fountain");
        std::fs::write(&script, "ours\n").unwrap();
        let known = DiskState::recorded(&script, "ours\n");

        std::fs::remove_file(&script).unwrap();
        assert_eq!(known.compare(&script), DiskVerdict::Unreadable);
    }

    /// A record made when there was nothing there still knows what it expects,
    /// so the file appearing underneath us is a change rather than a `stat` that
    /// happens to match.
    #[test]
    fn a_record_of_a_file_that_did_not_exist_still_compares() {
        let dir = TempDir::new("disk-absent");
        let script = dir.path().join("heat.fountain");
        let known = DiskState::recorded(&script, "ours\n");

        std::fs::write(&script, "theirs\n").unwrap();
        assert_eq!(known.compare(&script), DiskVerdict::Changed);
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
