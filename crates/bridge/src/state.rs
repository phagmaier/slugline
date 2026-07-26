//! Everything the core knows, and the only place a [`Document`] is stored.
//!
//! One instance of this lives on the actor thread (see [`crate::actor`]) and is
//! reachable from nowhere else, so no field here needs a lock.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use slugline_document::{BlockId, Document, EntityIndex, EntityKind, Patch};
use slugline_layout::{LayoutEngine, PageConfig, PaginatedScript};
use slugline_storage::journal::Journal;
use slugline_storage::library::Library;
use slugline_storage::watch::{FileWatcher, OwnWrites};
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
    /// The files this process has itself written, so that the watcher can tell
    /// the echo of our own save from another program's edit (F4).
    ///
    /// Held here rather than inside the watcher because the save path needs it
    /// and the watcher may not exist: a build with no inotify still writes
    /// files, and a registry that only appeared when the watcher did would be a
    /// second thing to reason about. It is an `Arc` because the only other
    /// thread that reads it is `notify`'s.
    pub own_writes: Arc<OwnWrites>,
    /// The newest successful save awaiting a page count, per library entry.
    ///
    /// Pagination is allowed to finish out of order. The token is deliberately
    /// process-local cache bookkeeping: only the resulting count is persisted.
    pub(crate) page_count_jobs: HashMap<String, u64>,
    pub(crate) next_page_count_job: u64,
}

impl Storage {
    pub fn begin_page_count(&mut self, id: &str) -> u64 {
        self.next_page_count_job = self.next_page_count_job.wrapping_add(1);
        let token = self.next_page_count_job;
        self.page_count_jobs.insert(id.to_owned(), token);
        token
    }

    pub fn page_count_is_current(&self, id: &str, token: u64) -> bool {
        self.page_count_jobs.get(id).copied() == Some(token)
    }
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
                if let Some(path) = session.path.as_ref() {
                    // A path this session is no longer holding has nothing left
                    // to suppress. `unwatch` forgets it too; this is the half
                    // that still runs when there is no watcher to unwatch from.
                    storage.own_writes.forget(path);
                    if let Some(watcher) = storage.watcher.as_mut() {
                        let _ = watcher.unwatch(path);
                    }
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
    /// §7's per-block index. Built once on open, then touched only for ids in
    /// an edit patch.
    entities: EntityIndex,
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
    /// Held for the whole of one write of this document's file.
    ///
    /// A save is three steps on purpose — plan on the actor, write off it,
    /// record back on it (§2.3) — and the actor serialises each step but not
    /// the sequence. Two saves of one script could therefore plan in order and
    /// write out of order, leaving the file holding older bytes than the save
    /// that had already answered "Saved". This is what stops that.
    ///
    /// A lock rather than a "busy" flag because the second save must not be
    /// *dropped*: §10 does not allow a save to be quietly skipped because the
    /// timing was awkward. It waits, and because the plan is made after the
    /// wait it writes the newest revision, or finds there is nothing left to
    /// write and says so. It is per session, so two scripts still save at the
    /// same time.
    ///
    /// It is only ever locked **off** the actor thread, by the save path in
    /// `api::files`. Nothing that runs inside an actor closure may take it: the
    /// whole point is that the actor stays free while the disk is busy.
    save_lock: Arc<Mutex<()>>,
    /// The patches recorded while a save is between planning its bytes and
    /// recording that it wrote them. `None` when no save is in flight.
    ///
    /// A save writes the bytes it planned, and `Journal::checkpoint` then
    /// truncates the journal to a header saying "everything up to here is in
    /// the file". That is true of every record the save covered and false of
    /// anything typed while it was writing — and throwing those records away
    /// while `mark_saved_at` correctly leaves the document dirty is how a
    /// keystroke ends up in neither the file nor the journal (F15).
    ///
    /// So the save keeps them and rebuilds the journal around them instead of
    /// emptying it. Armed by [`Session::begin_save`] and taken by
    /// [`Session::finish_save`], so a session that is not saving buffers
    /// nothing at all: the cost falls on the one file write, not on typing.
    saving: Option<Vec<Patch>>,
    /// Changes whenever the in-memory document changes or is replaced.
    ///
    /// Unlike `Document::revision`, this never moves backwards on undo and does
    /// not restart when a reload installs a new document. Async snapshot jobs
    /// use it to reject answers about state that is no longer current.
    document_generation: u64,
    /// This session's pagination: the engine, its cache, and the last result
    /// (ADR 0020). Nothing in here is touched by an edit.
    pagination: PaginationState,
}

impl Session {
    fn new(handle: u64, document: Document) -> Session {
        let entities = EntityIndex::build(&document);
        Session {
            handle,
            document,
            entities,
            last_edit: None,
            path: None,
            id: None,
            journal: None,
            journal_broken: false,
            scroll_row: 0,
            save_lock: Arc::new(Mutex::new(())),
            saving: None,
            document_generation: 0,
            pagination: PaginationState::default(),
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

    pub fn document_generation(&self) -> u64 {
        self.document_generation
    }

    pub fn pagination(&self) -> &PaginationState {
        &self.pagination
    }

    pub fn pagination_mut(&mut self) -> &mut PaginationState {
        &mut self.pagination
    }

    /// Records a successful mutation performed through [`Session::document_mut`],
    /// [`Session::editing`], or [`Session::interrupt`].
    pub fn document_changed(&mut self) {
        self.document_generation = self.document_generation.wrapping_add(1);
    }

    /// Installs a document loaded from disk and invalidates async snapshots of
    /// the document it replaces.
    pub fn replace_document(&mut self, document: Document) {
        self.document = document;
        self.document_changed();
    }

    pub fn entities(&self) -> &EntityIndex {
        &self.entities
    }

    pub fn entities_mut(&mut self) -> &mut EntityIndex {
        &mut self.entities
    }

    pub fn refresh_entities(&mut self, ids: impl IntoIterator<Item = BlockId>) {
        self.entities.update(ids, &self.document);
    }

    pub fn rebuild_entities(&mut self) {
        let pins = self.entities.pinned();
        self.entities = EntityIndex::build(&self.document);
        self.load_pins(pins);
    }

    pub fn load_pins(&mut self, pins: impl IntoIterator<Item = (EntityKind, String)>) {
        for (kind, value) in pins {
            self.entities.pin(kind, &value);
        }
    }

    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    pub fn id(&self) -> Option<&str> {
        self.id.as_deref()
    }

    /// The claim a writer of this document's file has to take first.
    ///
    /// Cloned out rather than locked here, because the caller holds it across a
    /// disk write and the actor must not be inside that. See [`Session::save_lock`]
    /// the field for why it exists.
    pub fn save_lock(&self) -> Arc<Mutex<()>> {
        Arc::clone(&self.save_lock)
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
        // The buffer describes records in the journal being replaced, so it
        // cannot survive it: a reload or a restore that lands while a save is in
        // flight would otherwise have those records rebuilt into a journal that
        // never held them, for a document that no longer exists.
        self.saving = None;
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
    ///
    /// Takes the patch by value: the only other thing that wants it is
    /// [`Session::saving`], and moving it there costs nothing where cloning it
    /// on every keystroke would.
    pub fn record(&mut self, patch: Patch) -> bool {
        if self.journal_broken {
            return false;
        }
        let Some(journal) = self.journal.as_mut() else {
            return false;
        };
        if journal.append(&patch).is_err() {
            self.journal_broken = true;
            return true;
        }
        // Kept only while a save is in flight, and only after the append, so
        // what is buffered is exactly what is in the journal file and not in
        // the bytes that save is writing.
        if let Some(since) = self.saving.as_mut() {
            since.push(patch);
        }
        false
    }

    /// Marks the start of a save, from inside the same actor closure that reads
    /// the bytes to be written — so no edit can land between the two.
    ///
    /// Returns the revision those bytes are, which is what the save later marks
    /// the document clean up to.
    pub fn begin_save(&mut self) -> u64 {
        self.saving = Some(Vec::new());
        self.document.revision()
    }

    /// Ends it, and hands back the edits that arrived while the file was being
    /// written. Empty is the ordinary answer.
    ///
    /// Safe to call when no save is in flight, which is what makes it usable as
    /// the "this save is not going to happen after all" path as well.
    pub fn finish_save(&mut self) -> Vec<Patch> {
        self.saving.take().unwrap_or_default()
    }

    #[cfg(test)]
    pub fn is_saving(&self) -> bool {
        self.saving.is_some()
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

/// One pagination, and the state of the document it describes (ADR 0020).
///
/// Cloning one is cheap: the pages behind [`PaginatedScript`] are an `Arc`, so
/// what a clone copies is the checkpoint list and a handful of words.
#[derive(Clone)]
pub struct Pagination {
    /// [`Session::document_generation`] at the instant the snapshot was taken.
    /// A result whose generation is no longer the session's is stale: it is
    /// still a correct pagination of a document that existed, and it is not a
    /// pagination of *this* one, so nothing may be derived from it.
    pub generation: u64,
    /// The page setup it was computed for. A pagination of the same generation
    /// under a different paper size is a different answer.
    pub config: PageConfig,
    pub script: PaginatedScript,
    /// The block the engine was told had changed, if it was told. Advisory
    /// (ADR 0022): a wrong hint costs time and cannot cost correctness.
    pub hinted_block: Option<BlockId>,
}

/// Everything one session knows about paginating itself.
///
/// The engine and its cache live here rather than in a static, because the
/// checkpoints and per-block wraps of ADR 0022 are only reusable against the
/// document they were computed from. They are **lent** to a worker thread for
/// the length of one pagination and given back with it: a `LayoutEngine` is
/// `&mut` to run, and the actor thread must not be the one running it (§2.3).
///
/// [`PaginationState::lock`] is what makes lending safe. It is the same shape
/// as [`Session::save_lock`] and is taken in the same place — off the actor,
/// before the plan — so a second pagination of one document waits for the first
/// rather than starting beside it with a fresh engine.
#[derive(Default)]
pub struct PaginationState {
    lock: Arc<Mutex<()>>,
    /// `None` exactly while a worker holds it.
    engine: Option<LayoutEngine>,
    /// One fingerprint per block of the snapshot `engine` last paginated, in
    /// document order. The changed-block hint is the first disagreement between
    /// this and the snapshot being paginated now.
    fingerprints: Vec<(BlockId, u64)>,
    last: Option<Pagination>,
    /// How many paginations have actually run for this session. The coalescing
    /// in `api::layout` is only observable as this number not moving.
    #[cfg(test)]
    runs: u64,
}

impl PaginationState {
    /// The claim a paginator of this document has to take first. Cloned out
    /// rather than locked here: the caller holds it across the pagination, and
    /// the actor must not be inside that.
    pub fn lock(&self) -> Arc<Mutex<()>> {
        Arc::clone(&self.lock)
    }

    /// The committed pagination, if there is one and it still describes
    /// `generation` under `config`. This is what makes a run of saves with no
    /// edits between them cost one pagination rather than one each.
    pub fn ready(&self, generation: u64, config: &PageConfig) -> Option<&Pagination> {
        self.last
            .as_ref()
            .filter(|last| last.generation == generation && &last.config == config)
    }

    /// Hands the engine and its fingerprints to a worker. A caller that did not
    /// take [`PaginationState::lock`] first can find the engine already lent,
    /// and gets a cold one — correct, and slower, which is the right way round.
    pub fn lend(&mut self) -> (LayoutEngine, Vec<(BlockId, u64)>) {
        #[cfg(test)]
        {
            self.runs += 1;
        }
        (
            self.engine.take().unwrap_or_default(),
            std::mem::take(&mut self.fingerprints),
        )
    }

    /// Takes them back, with the fingerprints of the snapshot just paginated.
    /// Always called, even for a stale result: the engine's checkpoints describe
    /// the snapshot it saw, which is what it validates the next one against.
    pub fn returned(&mut self, engine: LayoutEngine, fingerprints: Vec<(BlockId, u64)>) {
        self.engine = Some(engine);
        self.fingerprints = fingerprints;
    }

    /// Records a pagination that still describes the current document. A stale
    /// one never reaches here, which is what stops an older result replacing a
    /// newer one.
    pub fn commit(&mut self, pagination: Pagination) {
        self.last = Some(pagination);
    }

    #[cfg(test)]
    pub fn runs(&self) -> u64 {
        self.runs
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
