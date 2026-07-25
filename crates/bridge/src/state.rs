//! Everything the core knows, and the only place a [`Document`] is stored.
//!
//! One instance of this lives on the actor thread (see [`crate::actor`]) and is
//! reachable from nowhere else, so no field here needs a lock.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use slugline_document::{Document, Patch};
use slugline_storage::journal::Journal;
use slugline_storage::library::Library;
use slugline_storage::watch::FileWatcher;
use slugline_storage::{Paths, Preferences};

/// §3.4: consecutive text edits to the same block coalesce into one undo
/// transaction while they keep coming within this window.
///
/// `document` has no clock on purpose (ADR 0008), so the window is measured
/// here — lazily, at the next edit, rather than by a timer. The two are the same
/// thing as far as anyone can observe: a transaction boundary is only ever
/// visible to an undo, and an undo closes the open transaction first. A timer
/// would only add a wakeup to an idle process (§1.3).
const COALESCE_WINDOW: Duration = Duration::from_millis(600);

#[derive(Default)]
pub struct AppState {
    documents: HashMap<u64, Session>,
    next_handle: u64,
    /// Everything that touches the disk, once Dart has said where the disk is.
    ///
    /// `None` until `init` runs, and that is a supported state rather than a
    /// half-built one: the core parses, edits and answers questions about a
    /// document perfectly well with nowhere to put it. Every widget test and
    /// every Phase 1–3 test runs in exactly that state, and so does the first
    /// instant of a real session.
    storage: Option<Storage>,
}

/// The disk-facing half of the core.
pub struct Storage {
    pub paths: Paths,
    pub prefs: Preferences,
    pub library: Library,
    /// `None` when `notify` could not start — a kernel without inotify, or a
    /// process out of watch descriptors. External-change detection is a
    /// convenience; nothing else depends on it, so it fails quietly.
    pub watcher: Option<FileWatcher>,
}

impl AppState {
    /// Takes ownership of a document and returns the handle Dart names it by.
    pub fn open(&mut self, document: Document) -> u64 {
        self.next_handle += 1;
        let handle = self.next_handle;
        self.documents
            .insert(handle, Session::new(handle, document));
        handle
    }

    /// Closes a document, ending its journal cleanly.
    ///
    /// The journal's *absence* is what tells the next startup that this session
    /// did not crash, so a close that forgets to discard it is a close that
    /// offers a spurious recovery.
    pub fn close(&mut self, handle: u64) {
        if let Some(mut session) = self.documents.remove(&handle) {
            if let Some(journal) = session.journal.take() {
                let _ = journal.discard();
            }
            if let (Some(storage), Some(id)) = (self.storage.as_mut(), session.id.as_ref()) {
                storage.library.closed(id, session.scroll_row());
                if let (Some(watcher), Some(path)) =
                    (storage.watcher.as_mut(), session.path.as_ref())
                {
                    let _ = watcher.unwatch(path);
                }
            }
        }
    }

    pub fn storage(&self) -> Option<&Storage> {
        self.storage.as_ref()
    }

    pub fn storage_mut(&mut self) -> Option<&mut Storage> {
        self.storage.as_mut()
    }

    pub fn set_storage(&mut self, storage: Storage) {
        self.storage = Some(storage);
    }

    /// The handles of every open document, for the shutdown sweep.
    pub fn handles(&self) -> Vec<u64> {
        let mut handles: Vec<u64> = self.documents.keys().copied().collect();
        handles.sort_unstable();
        handles
    }

    /// The handle already holding `path`, if any. Opening the same file twice
    /// would be two documents editing one file, and whichever saved second
    /// would win silently.
    pub fn handle_for(&self, path: &Path) -> Option<u64> {
        self.documents
            .iter()
            .find(|(_, session)| session.path.as_deref() == Some(path))
            .map(|(handle, _)| *handle)
    }

    pub fn session(&self, handle: u64) -> Option<&Session> {
        self.documents.get(&handle)
    }

    pub fn session_mut(&mut self, handle: u64) -> Option<&mut Session> {
        self.documents.get_mut(&handle)
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.documents.len()
    }
}

/// One open script.
pub struct Session {
    /// The handle Dart names this session by. Kept here so that anything with a
    /// session in hand can say which document it is talking about — an event
    /// pushed from an edit, for one.
    handle: u64,
    document: Document,
    /// When the last edit was applied, for the coalescing window above.
    last_edit: Option<Instant>,
    /// The file this document is. `None` for a script that has never been
    /// saved — which still gets a journal (see [`Session::journal`]), because an
    /// unsaved script is the one a crash hurts most.
    path: Option<PathBuf>,
    /// Its entry in the library index.
    id: Option<String>,
    /// The crash journal. Every edit is appended to it; a save checkpoints it;
    /// a clean close removes it.
    journal: Option<Journal>,
    /// Set once the journal has failed to write. We stop trying rather than
    /// failing on every keystroke, and Dart is told once.
    journal_broken: bool,
    /// Where the writer had scrolled to, for session restore. Dart owns the
    /// scroll (§2.1); this is where it parks the number.
    scroll_row: u32,
}

impl Session {
    fn new(handle: u64, document: Document) -> Session {
        Session {
            handle,
            document,
            last_edit: None,
            path: None,
            id: None,
            journal: None,
            journal_broken: false,
            scroll_row: 0,
        }
    }

    pub fn handle(&self) -> u64 {
        self.handle
    }

    pub fn document(&self) -> &Document {
        &self.document
    }

    /// The document, with no effect on the coalescing window. For the paths that
    /// mutate without being an edit — recovery replay, a reload from disk.
    pub fn document_mut(&mut self) -> &mut Document {
        &mut self.document
    }

    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    pub fn id(&self) -> Option<&str> {
        self.id.as_deref()
    }

    pub fn scroll_row(&self) -> u32 {
        self.scroll_row
    }

    pub fn set_scroll_row(&mut self, row: u32) {
        self.scroll_row = row;
    }

    /// Attaches this session to a file. Called by open, create, and Save As.
    pub fn set_file(&mut self, path: PathBuf, id: String) {
        self.path = Some(path);
        self.id = Some(id);
    }

    pub fn set_journal(&mut self, journal: Option<Journal>) {
        self.journal = journal;
        self.journal_broken = false;
    }

    pub fn journal_mut(&mut self) -> Option<&mut Journal> {
        self.journal.as_mut()
    }

    /// How many edits are in the journal since the last save.
    pub fn journalled(&self) -> u64 {
        self.journal.as_ref().map(Journal::records).unwrap_or(0)
    }

    /// Whether the journal has stopped working. Dart shows this once: a session
    /// whose journal is broken is still safe to keep typing in — the file and
    /// the autosave both still work — but the last few seconds are no longer
    /// covered, and that is the user's to know.
    pub fn journal_broken(&self) -> bool {
        self.journal_broken
    }

    /// Appends what one edit did.
    ///
    /// Returns whether the journal has just broken, so that the caller can push
    /// exactly one notification rather than one per keystroke. A journal failure
    /// never fails the edit: the edit is in the document, and refusing it
    /// afterwards would be losing text to protect against losing text.
    pub fn record(&mut self, patch: &Patch) -> bool {
        if self.journal_broken {
            return false;
        }
        let Some(journal) = self.journal.as_mut() else {
            return false;
        };
        if journal.append(patch).is_err() {
            self.journal_broken = true;
            return true;
        }
        false
    }

    /// The document, with the undo transaction closed first if the previous
    /// edit is now older than the coalescing window.
    ///
    /// Every edit path goes through here, so there is one place that decides
    /// what "the same run of typing" means.
    pub fn editing(&mut self, now: Instant) -> &mut Document {
        if self
            .last_edit
            .is_some_and(|last| now.saturating_duration_since(last) > COALESCE_WINDOW)
        {
            self.document.commit();
        }
        self.last_edit = Some(now);
        &mut self.document
    }

    /// Ends the current run of typing, whatever the clock says. Undo and redo
    /// use this: an undo in the middle of a run must take the whole run back and
    /// then leave the next keystroke starting a fresh transaction.
    pub fn interrupt(&mut self) -> &mut Document {
        self.last_edit = None;
        &mut self.document
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use slugline_document::EditCommand;

    fn session_over(document: Document) -> Session {
        Session::new(1, document)
    }

    fn typed(session: &mut Session, at: Instant, offset: u32, text: &str) {
        let id = session.document().blocks()[0].id();
        session
            .editing(at)
            .apply(EditCommand::ReplaceText {
                block: id,
                range: offset..offset,
                with: text.to_owned(),
            })
            .expect("the edit applies");
    }

    #[test]
    fn typing_within_the_window_is_one_undo_step() {
        let start = Instant::now();
        let mut session = session_over(Document::parse("abc\n"));
        typed(&mut session, start, 0, "x");
        typed(&mut session, start + Duration::from_millis(100), 1, "y");
        typed(&mut session, start + Duration::from_millis(200), 2, "z");
        assert_eq!(session.document().blocks()[0].text(), "xyzabc");

        session.interrupt().undo().expect("something to undo");
        assert_eq!(session.document().blocks()[0].text(), "abc");
    }

    #[test]
    fn a_pause_longer_than_the_window_starts_a_new_undo_step() {
        let start = Instant::now();
        let mut session = session_over(Document::parse("abc\n"));
        typed(&mut session, start, 0, "x");
        typed(&mut session, start + Duration::from_millis(601), 1, "y");
        assert_eq!(session.document().blocks()[0].text(), "xyabc");

        session.interrupt().undo().expect("something to undo");
        assert_eq!(session.document().blocks()[0].text(), "xabc");
        session.interrupt().undo().expect("something to undo");
        assert_eq!(session.document().blocks()[0].text(), "abc");
    }

    #[test]
    fn handles_are_never_reused() {
        let mut state = AppState::default();
        let first = state.open(Document::blank());
        state.close(first);
        let second = state.open(Document::blank());
        assert_ne!(first, second);
        assert!(state.session(first).is_none());
        assert!(state.session(second).is_some());
        assert_eq!(state.len(), 1);
    }
}
