//! Everything the core knows, and the only place a [`Document`] is stored.
//!
//! One instance of this lives on the actor thread (see [`crate::actor`]) and is
//! reachable from nowhere else, so no field here needs a lock.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use slugline_document::Document;

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
}

impl AppState {
    /// Takes ownership of a document and returns the handle Dart names it by.
    pub fn open(&mut self, document: Document) -> u64 {
        self.next_handle += 1;
        let handle = self.next_handle;
        self.documents.insert(handle, Session::new(document));
        handle
    }

    pub fn close(&mut self, handle: u64) {
        self.documents.remove(&handle);
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
    document: Document,
    /// When the last edit was applied, for the coalescing window above.
    last_edit: Option<Instant>,
}

impl Session {
    fn new(document: Document) -> Session {
        Session {
            document,
            last_edit: None,
        }
    }

    pub fn document(&self) -> &Document {
        &self.document
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
        let mut session = Session::new(Document::parse("abc\n"));
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
        let mut session = Session::new(Document::parse("abc\n"));
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
