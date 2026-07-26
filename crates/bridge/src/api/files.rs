//! The persistence half of the §6 bridge API: lifecycle, library, save,
//! recovery, backups, preferences.
//!
//! Everything here obeys the same three rules as [`crate::api::doc`] — UTF-16
//! offsets, nothing holds a document, an edit answers with a patch — and adds
//! two of its own:
//!
//! 1. **Long jobs run against a snapshot** (§2.3). A save asks the actor thread
//!    for the bytes and the path, lets go of it, writes the file on the FRB
//!    worker thread, and comes back to the actor only to record what happened.
//!    The actor is never blocked on a disk.
//! 2. **A failed write is a value, not a panic.** [`SaveOutcome`] carries the
//!    reason and the path, because §Phase 4 wants read-only, full-disk and
//!    permission-denied each handled with a distinct message and a Save As
//!    escape hatch — and the UI can only offer that if it is told which one
//!    happened.
//!
//! ## Where the clock is
//!
//! There is no timer in this file, and there is none in the actor either. §Phase
//! 4's autosave is "debounced after edit inactivity (default 2 s) and on a hard
//! interval (default 30 s)", and both of those are driven from Dart, which calls
//! [`doc_autosave`] when they fire. That is not an evasion; it is the only place
//! the decision can be made correctly. The same paragraph says autosave "never
//! runs while a modal is open or during an active IME composition", and neither
//! of those facts exists in Rust — a modal is a widget and a composition is a
//! state of the platform's input connection. The core is told when to save; it
//! decides how.
//!
//! Keeping the clock out of the core also keeps §1.3's 0% idle CPU budget met by
//! construction: the actor thread blocks on its channel and wakes only when
//! something happens.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::{Arc, PoisonError};

use flutter_rust_bridge::frb;

use slugline_document as model;
use slugline_storage::backup::{self, Retention};
use slugline_storage::journal::{self, Journal};
use slugline_storage::library::{Library, ScriptEntry};
use slugline_storage::watch::{FileWatcher, OwnWrites};
use slugline_storage::{atomic, paths::Paths, prefs, Preferences as CorePreferences};

use crate::actor::actor;
use crate::api::doc::DocumentHandle;
use crate::api::events::{emit, CoreEvent};
use crate::api::layout;
use crate::state::{AppState, Session, Storage};

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

/// Why a write did not happen. One variant per message §Phase 4 asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveFailure {
    /// The file is read-only. Offer Save As.
    ReadOnly,
    /// The directory will not take the file. Offer Save As.
    PermissionDenied,
    /// The filesystem is full, or the user is over quota. Offer Save As.
    NoSpace,
    /// The directory does not exist.
    NoSuchDirectory,
    /// Anything else the operating system said.
    Io,
    /// The document handle is not open.
    NoSuchDocument,
    /// The document has never been saved and no path was given. The UI must ask
    /// for one; this is not an error so much as a question.
    NoPath,
    /// There is already a file there and the caller did not say to replace it.
    /// Like [`SaveFailure::NoPath`] this is a question rather than a fault: the
    /// UI asks, and calls again saying yes (ADR 0029).
    AlreadyExists,
    /// The destination is a script this application has open. Refused outright:
    /// writing it from outside its own session would leave that session's
    /// journal describing bytes the file no longer holds (ADR 0029).
    ScriptIsOpen,
}

/// What a save did.
///
/// `Ok` rather than a thrown exception because a save failing is an ordinary
/// thing that happens to people with full disks, and the caller has to show a
/// blocking dialog with a specific message rather than catch something.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveOutcome {
    Saved {
        path: String,
        bytes: u32,
        /// The backup written alongside, if one was.
        backup: Option<BackupView>,
    },
    /// Nothing needed writing. Autosave hits this constantly and it is not news.
    Unchanged,
    Failed {
        failure: SaveFailure,
        /// The file the user asked for, never the temporary one.
        path: String,
        /// Human-readable, and specific: it names the file and the reason.
        message: String,
    },
}

/// One script in the library (§6's `ScriptEntry`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScriptView {
    pub id: String,
    pub path: String,
    pub title: String,
    /// Unix milliseconds. Dart formats it: a date's appearance is a locale
    /// question and the core has no locale.
    pub modified_millis: u64,
    pub bytes: u64,
    /// Zero until a layout-capable build successfully saves and paginates this
    /// script; otherwise the number of screenplay pages in the saved snapshot.
    pub page_count: u32,
    /// The file was not there when the library was last refreshed. Shown as
    /// missing, never dropped (§Phase 4).
    pub missing: bool,
    pub open: bool,
    pub scroll_row: u32,
}

/// One rolling backup (§Phase 4's "Restore previous version" list).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackupView {
    pub path: String,
    pub written_millis: u64,
    pub bytes: u64,
}

/// A crashed session, as an offer to the user.
///
/// §Phase 4: "Recovery presents a diff summary ('14 edits since last save') and
/// Recover / Discard, never auto-applies." This is that summary; nothing has
/// been applied to anything when one of these is handed to Dart.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryOffer {
    /// Names this offer in [`recovery_accept`] and [`recovery_discard`].
    pub journal: String,
    /// The script it belongs to. Empty for a script that was never saved.
    pub script: String,
    /// A file name, or "Untitled" — what to put in the dialog.
    pub title: String,
    /// The "14" in "14 edits since last save".
    pub edits: u32,
    /// The journal's last record was incomplete, which is the ordinary shape of
    /// a crash. Worth saying, because it means the very last keystroke is gone.
    pub damaged: bool,
    /// Why this offer cannot be taken, if it cannot. `None` means it can.
    pub blocked: Option<String>,
}

/// What accepting a recovery offer did.
///
/// Three states rather than `Option<DocumentHandle>` because the middle one is
/// real and used to be invisible: the edits replayed, but the successor journal
/// could not be written, so the session is live with nothing recording it. That
/// is worth a sentence to the writer, and §Phase 4's "losing user text is a P0
/// bug" does not allow it to be the silent default.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryOutcome {
    /// Replayed, and a journal describing the recovered edits is on disk. This
    /// is the ordinary answer.
    Recovered { handle: DocumentHandle },
    /// Replayed and open, but not journalled: the old journal was kept, so the
    /// recovered text is still durable, and nothing typed from here is.
    ///
    /// `message` names the reason. The correct advice is Save As somewhere the
    /// state directory's problem does not apply, or relaunch — the offer will
    /// still be there.
    Degraded {
        handle: DocumentHandle,
        message: String,
    },
    /// Nothing was opened and nothing was removed. The offer can be made again.
    Failed { message: String },
}

/// §6's `Preferences`, as far as Phase 4 defines them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreferencesView {
    pub autosave_enabled: bool,
    pub autocomplete_enabled: bool,
    pub autosave_idle_ms: u64,
    pub autosave_interval_ms: u64,
    pub backup_dir: Option<String>,
    pub backup_keep_versions: u32,
    pub backup_keep_days: u32,
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// §6's `init`. Tells the core where its directories are and reads what is in
/// them.
///
/// Async because it touches the disk: it reads the preferences and the library
/// index, and starts the file watcher.
///
/// Empty strings mean "work it out from XDG", which is what the application
/// passes. A test passes three temporary directories and gets a core that
/// cannot see the real ones.
pub async fn init(config_dir: String, data_dir: String, state_dir: String) -> bool {
    let paths = if config_dir.is_empty() {
        match Paths::discover() {
            Some(paths) => paths,
            None => return false,
        }
    } else {
        Paths::at(config_dir, data_dir, state_dir)
    };

    let prefs = CorePreferences::load(&paths.preferences());
    let mut library = Library::load(&paths.library_index());
    library.refresh();

    // The watcher's callback runs on `notify`'s thread and does one thing: push
    // an event at Dart. It must not touch `AppState` — that would be a second
    // thread reaching the actor's data, which §2.3 exists to prevent.
    //
    // `own_writes` is the exception that proves it: the one thing the callback
    // has to know that the save path knows is which writes were ours, and it is
    // its own lock-guarded register precisely so that asking does not mean
    // reaching into the actor's state (F4, ADR 0028).
    let own_writes = OwnWrites::shared();
    let watcher = FileWatcher::new(Arc::clone(&own_writes), |path| {
        emit(CoreEvent::FileChangedOnDisk {
            path: path.to_string_lossy().into_owned(),
        });
    })
    .ok();

    actor().run(move |state| {
        state.set_storage(Storage {
            paths,
            prefs,
            library,
            watcher,
            own_writes,
            page_count_jobs: Default::default(),
            next_page_count_job: 0,
        });
    });
    true
}

/// Ends the session cleanly: every journal is discarded and the library index is
/// written.
///
/// Dart calls this from the window's close handler. If it never runs — because
/// the process was killed — the journals stay on disk and the next startup finds
/// them, which is exactly the behaviour they exist for.
pub async fn shutdown() {
    actor().run(|state| {
        for handle in state.handles() {
            state.close(handle);
        }
        save_library(state);
    });
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

/// §6's `library_list`.
pub async fn library_list() -> Vec<ScriptView> {
    actor().run(|state| {
        let Some(storage) = state.storage_mut() else {
            return Vec::new();
        };
        storage.library.refresh();
        storage.library.entries().iter().map(script_view).collect()
    })
}

/// §6's `library_open`. Reads the file and hands back a document.
///
/// Opening a file that is already open returns the handle it is already open
/// under. Two documents over one file would be two undo histories racing to
/// overwrite each other.
///
/// The check below is an optimisation, not the guarantee: the read between it
/// and the open is off the actor, so two concurrent opens of one path can both
/// miss it. [`open_source`] makes the same check again where it is atomic with
/// the insert, and that is the one that holds.
pub async fn library_open(path: String) -> Option<DocumentHandle> {
    let path = PathBuf::from(path);
    if let Some(existing) = actor().run({
        let path = path.clone();
        move |state| state.handle_for(&path)
    }) {
        return Some(DocumentHandle { id: existing });
    }

    // The read happens here, off the actor thread: a 120-page script is half a
    // megabyte and a cold file is a disk seek.
    let source = std::fs::read_to_string(&path).ok()?;
    Some(open_source(path, source, false))
}

/// §6's `library_create`. A new, empty script at `path`.
///
/// The file is written immediately, and the handle only comes back if it was:
/// "create" that leaves nothing on disk is a promise the library index would
/// then be holding a broken pointer to.
pub async fn library_create(path: String) -> Option<DocumentHandle> {
    let path = PathBuf::from(path);
    if path.exists() {
        return None;
    }
    atomic::save_atomically(&path, "").ok()?;
    Some(open_source(path, String::new(), true))
}

/// §6's `library_rename`. Moves the file and follows it.
pub async fn library_rename(id: String, new_path: String) -> SaveOutcome {
    let new_path = PathBuf::from(new_path);
    let Some(old_path) = actor().run({
        let id = id.clone();
        move |state| {
            state
                .storage()
                .and_then(|storage| storage.library.get(&id))
                .map(|entry| entry.path.clone())
        }
    }) else {
        return failed(SaveFailure::NoSuchDocument, &new_path, "no such script");
    };

    if new_path.exists() {
        return failed(
            SaveFailure::Io,
            &new_path,
            &format!("{} already exists", new_path.display()),
        );
    }
    if let Err(error) = std::fs::rename(&old_path, &new_path) {
        return failed(SaveFailure::Io, &new_path, &error.to_string());
    }

    let renamed_to = new_path.clone();
    actor().run(move |state| {
        let new_path = renamed_to;
        let new_id = state
            .storage_mut()
            .and_then(|storage| storage.library.renamed(&id, &new_path));
        // Any document open on the old path follows it, journal and all: the
        // journal is keyed by the path, so it has to be reopened under the new
        // one or a crash would offer to recover onto a file that moved.
        if let (Some(new_id), Some(handle)) = (new_id, state.handle_for(&old_path)) {
            rebind(state, handle, new_path.clone(), new_id);
        }
        save_library(state);
    });
    SaveOutcome::Saved {
        path: new_path.to_string_lossy().into_owned(),
        bytes: 0,
        backup: None,
    }
}

/// §6's `library_duplicate`. Copies the file beside itself and adds the copy.
pub async fn library_duplicate(id: String) -> Option<ScriptView> {
    let source_path = actor().run({
        let id = id.clone();
        move |state| {
            state
                .storage()
                .and_then(|storage| storage.library.get(&id))
                .map(|entry| entry.path.clone())
        }
    })?;

    let contents = std::fs::read_to_string(&source_path).ok()?;
    let copy = unused_path(&source_path)?;
    atomic::save_atomically(&copy, &contents).ok()?;

    actor().run(move |state| {
        let storage = state.storage_mut()?;
        let new_id = storage.library.add(&copy);
        let view = storage.library.get(&new_id).map(script_view);
        save_library(state);
        view
    })
}

/// §6's `library_remove`. Forgets the script, and deletes the file only if asked.
///
/// The two are separate on purpose (§Phase 4 lists "remove-from-library" and
/// "delete-file" as different commands). Removing from the library is
/// reversible by opening the file again; deleting is not, which is why it is a
/// different word in the UI and a different argument here.
pub async fn library_remove(id: String, delete_file: bool) -> bool {
    let path = actor().run({
        let id = id.clone();
        move |state| {
            let storage = state.storage_mut()?;
            let entry = storage.library.remove(&id)?;
            save_library(state);
            Some(entry.path)
        }
    });
    let Some(path) = path else { return false };
    if delete_file {
        return std::fs::remove_file(&path).is_ok();
    }
    true
}

/// §6's `session_restore`: the scripts that were open when the application last
/// exited, with the scroll position each was at.
///
/// Returns entries rather than ids, so Dart can show the list and reopen it in
/// one pass rather than asking about each one.
pub async fn session_restore() -> Vec<ScriptView> {
    actor().run(|state| {
        state
            .storage()
            .map(|storage| storage.library.session().iter().map(script_view).collect())
            .unwrap_or_default()
    })
}

/// Records where the writer is in a script, so that a crash does not lose the
/// scroll position along with everything else.
#[frb(sync)]
pub fn doc_set_scroll(handle: DocumentHandle, row: u32) {
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return;
        };
        session.set_scroll_row(row);
        let id = session.id().map(str::to_owned);
        if let (Some(storage), Some(id)) = (state.storage_mut(), id) {
            storage.library.set_scroll(&id, row);
        }
    });
}

// ---------------------------------------------------------------------------
// Saving
// ---------------------------------------------------------------------------

/// Whether the document has edits that are not in its file (§6's `doc_dirty`).
#[frb(sync)]
pub fn doc_dirty(handle: DocumentHandle) -> bool {
    actor().run(move |state| {
        state
            .session(handle.id)
            .is_some_and(|session| session.document().is_dirty())
    })
}

/// The file this document is, or `None` for one that has never been saved.
#[frb(sync)]
pub fn doc_path(handle: DocumentHandle) -> Option<String> {
    actor().run(move |state| {
        state
            .session(handle.id)
            .and_then(|session| session.path())
            .map(|path| path.to_string_lossy().into_owned())
    })
}

/// How many edits are in the journal since the last save, and whether the
/// journal is still working. The status bar shows both.
#[frb(sync)]
pub fn doc_journal_state(handle: DocumentHandle) -> (u32, bool) {
    actor().run(move |state| {
        state
            .session(handle.id)
            .map(|session| {
                (
                    session.journalled().min(u32::MAX as u64) as u32,
                    session.journal_broken(),
                )
            })
            .unwrap_or((0, false))
    })
}

/// §6's `doc_save`.
pub async fn doc_save(handle: DocumentHandle) -> SaveOutcome {
    write_document(handle, None, true).await
}

/// Save As.
///
/// The document **follows** the new path: after Save As, this *is* the file, and
/// the journal, the backups, the watch and the library entry all move with it.
/// That is the difference from [`doc_export_fountain`], which writes a copy and
/// changes nothing (ADR 0029).
pub async fn doc_save_as(handle: DocumentHandle, path: String) -> SaveOutcome {
    write_document(handle, Some(PathBuf::from(path)), true).await
}

/// §6's `doc_export_fountain`: write a copy of the script somewhere else, and
/// carry on editing this one.
///
/// ## What it deliberately does not do
///
/// Everything [`doc_save_as`] does. Export writes one file and touches nothing
/// else: the document keeps its path, its identity in the library, its watch,
/// its journal — base and all — and its dirty flag, because the copy is not
/// where this script lives and the writer's unsaved work is still unsaved. No
/// backup is written either: backups are the history of *this* script's file,
/// and a copy is not a version of it. Nothing is recorded on the actor
/// afterwards, so there is no state a failed export could be caught halfway
/// through.
///
/// It follows that the session is never armed here — no [`Session::begin_save`],
/// so no [`abandon_save`] on the way out — and that the write needs no
/// own-write bracket: the destination is refused if it is a file this
/// application has open, and an open script is the only file it watches.
///
/// ## The two refusals
///
/// * A destination that is already there comes back as
///   [`SaveFailure::AlreadyExists`] unless `overwrite` says otherwise. Export is
///   a file chooser away from silently replacing a script the writer spent a
///   month on, and the core is the layer that can make that impossible rather
///   than merely unlikely.
/// * A destination that is an open script comes back as
///   [`SaveFailure::ScriptIsOpen`], and `overwrite` does not lift it. That
///   file's session has a journal whose base is the bytes now being replaced;
///   after such a write a crash would recover onto a file that no longer
///   matches, so the answer is to save that script rather than to export over
///   it (ADR 0029).
pub async fn doc_export_fountain(
    handle: DocumentHandle,
    path: String,
    overwrite: bool,
) -> SaveOutcome {
    let path = PathBuf::from(path);
    if path.as_os_str().is_empty() {
        return failed(SaveFailure::NoPath, &path, "no file was chosen");
    }

    // The only thing this takes from the actor: the bytes, and where the open
    // scripts live. Both in one trip, and neither leaves anything armed.
    let Some((text, open_scripts)) = actor().run({
        let handle = handle.id;
        move |state| {
            let text = state.session(handle)?.document().serialise();
            let open_scripts = state
                .handles()
                .into_iter()
                .filter_map(|open| state.session(open))
                .filter_map(Session::path)
                .map(Path::to_path_buf)
                .collect::<Vec<_>>();
            Some((text, open_scripts))
        }
    }) else {
        return failed(
            SaveFailure::NoSuchDocument,
            &path,
            "no document with that handle",
        );
    };

    if open_scripts.iter().any(|open| same_file(open, &path)) {
        return failed(
            SaveFailure::ScriptIsOpen,
            &path,
            &format!(
                "{} is open here; save that script rather than exporting over it",
                path.display()
            ),
        );
    }
    // Checked here rather than left to the write, because `save_atomically`
    // replaces whatever is there and answers `Ok`. A race between this and the
    // rename is possible and is the same race a file chooser has; what matters
    // is that the ordinary case cannot overwrite without having been asked.
    if !overwrite && path.exists() {
        return failed(
            SaveFailure::AlreadyExists,
            &path,
            &format!("{} is already there", path.display()),
        );
    }

    // Off the actor, like every other write (§2.3).
    if let Err(error) = atomic::save_atomically(&path, &text) {
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: text.len().min(u32::MAX as usize) as u32,
        backup: None,
    }
}

/// The autosave, called by Dart's own timers.
///
/// Identical to [`doc_save`] except that it writes no backup — a backup per
/// autosave would be a hundred a day and would push yesterday's draft out of the
/// retention window by lunchtime — and that it answers [`SaveOutcome::Unchanged`]
/// quietly when there is nothing to write, which is most of the time.
pub async fn doc_autosave(handle: DocumentHandle) -> SaveOutcome {
    let outcome = write_document(handle, None, false).await;
    if let SaveOutcome::Failed {
        failure, message, ..
    } = &outcome
    {
        // §6's `AutosaveFailed`. An autosave is not something the user asked
        // for, so it must not throw a modal at them — but it must not fail in
        // silence either, because they are still typing into a document that is
        // no longer being written anywhere.
        emit(CoreEvent::AutosaveFailed {
            handle: handle.id,
            failure: *failure,
            message: message.clone(),
        });
    }
    outcome
}

/// The common path behind save, Save As and autosave.
///
/// ## Why it starts by waiting
///
/// The three steps below are each serialised by the actor thread; the *sequence*
/// is not. Two saves of one script — an autosave already past its timer and a
/// Ctrl+S, most often — could plan in order and write out of order, leaving the
/// file holding older bytes than the save that had already answered "Saved".
/// [`Session::save_lock`] makes the sequence atomic per session, and step zero
/// is where it is taken.
///
/// The second save **waits** rather than being refused. The plan is made after
/// the wait, so it writes whatever the document says by then: the newest
/// revision, or — if the save it queued behind already wrote everything —
/// nothing, and it says [`SaveOutcome::Unchanged`]. That is the coalescing, and
/// it falls out of replanning rather than needing a queue.
async fn write_document(
    handle: DocumentHandle,
    save_as: Option<PathBuf>,
    with_backup: bool,
) -> SaveOutcome {
    // Step zero, off the actor thread: wait for any write of this document that
    // is already in flight.
    let lock = actor().run(move |state| state.session(handle.id).map(Session::save_lock));
    let Some(lock) = lock else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "no document with that handle",
        );
    };
    // A poisoned lock means a previous save panicked. It guards ordering, not
    // data, so there is nothing to be inconsistent — and refusing to save
    // because an earlier save crashed is the wrong way round.
    let _writing = lock.lock().unwrap_or_else(PoisonError::into_inner);

    // Step one, on the actor thread: what to write and where. This is the only
    // part that touches the document.
    let plan = actor().run({
        let save_as = save_as.clone();
        move |state| {
            let storage_paths = state.storage().map(|storage| {
                (
                    storage
                        .prefs
                        .backup_dir
                        .clone()
                        .unwrap_or_else(|| storage.paths.backup_dir()),
                    storage.prefs.retention(),
                )
            });
            let own_writes = state
                .storage()
                .map(|storage| Arc::clone(&storage.own_writes));
            let session = state.session_mut(handle.id)?;
            // Arms the buffer that keeps the records for anything typed from
            // here until step three, in the same closure that reads the bytes
            // — so there is no instant in which an edit is in neither.
            let revision = session.begin_save();
            let generation = session.document_generation();
            let path = save_as.or_else(|| session.path().map(Path::to_path_buf));
            Some(Plan {
                path,
                text: session.document().serialise(),
                revision,
                dirty: session.document().is_dirty(),
                storage: storage_paths,
                own_writes,
                snapshot: slugline_layout::ScriptSnapshot::from_document(session.document()),
                generation,
            })
        }
    });

    let Some(plan) = plan else {
        // Nothing was armed: there is no session to have armed it.
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "no document with that handle",
        );
    };
    // Every way out from here has to disarm, or the session goes on buffering
    // patches for a save that is never going to land.
    let Some(path) = plan.path else {
        abandon_save(handle.id);
        return SaveOutcome::Failed {
            failure: SaveFailure::NoPath,
            path: String::new(),
            message: "this script has never been saved".to_owned(),
        };
    };
    // Save As always writes, even to a document nobody has edited: the user
    // asked for a file at a new path and a clean document is still a file.
    if !plan.dirty && save_as.is_none() {
        abandon_save(handle.id);
        return SaveOutcome::Unchanged;
    }

    // Step two, off the actor thread: the disk (§2.3).
    //
    // The write is bracketed by the own-write register, so that the watcher can
    // recognise the event this rename is about to cause as our own (F4). It is
    // taken *before* the write rather than recorded after it: the event can be
    // delivered while the rename is still returning, long before an actor round
    // trip could record anything, and an event that arrives inside the bracket
    // is by definition about a file we are in the middle of replacing.
    let own_write = OwnWrite::begin(plan.own_writes.as_ref(), &path);
    #[cfg(test)]
    stall::reached(&path);
    if let Err(error) = atomic::save_atomically(&path, &plan.text) {
        own_write.abandoned();
        abandon_save(handle.id);
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }
    own_write.finished();

    // §Phase 4's rolling backups. Written after the file, so a backup only ever
    // exists for a state that reached the disk.
    let backup = match (with_backup, &plan.storage) {
        (true, Some((root, retention))) => backup::write(root, &path, &plan.text, *retention)
            .ok()
            .map(|written| BackupView {
                path: written.path.to_string_lossy().into_owned(),
                written_millis: written.written_millis,
                bytes: written.bytes,
            }),
        _ => None,
    };
    if let Some(written) = &backup {
        emit(CoreEvent::BackupWritten {
            handle: handle.id,
            path: written.path.clone(),
        });
    }

    // Step three, back on the actor thread: record that it happened. Answers
    // whether the document is *still* dirty, which is not the same question as
    // "did the save work": an edit that landed while the file was being written
    // is unsaved, and the event below must say so rather than assert a clean
    // document the disk does not have.
    let bytes = plan.text.len().min(u32::MAX as usize) as u32;
    let snapshot = plan.snapshot;
    let generation = plan.generation;
    let (still_dirty, page_count_job) = actor().run({
        let path = path.clone();
        let text = plan.text;
        move |state| {
            let Some(session) = state.session_mut(handle.id) else {
                return (false, None);
            };
            // Only as far as the revision we actually wrote. An edit that landed
            // while the file was being written is still unsaved, and marking the
            // whole document clean would be quietly dropping it.
            session.document_mut().mark_saved_at(plan.revision);

            let moved = session.path() != Some(path.as_path());
            if moved {
                let id = journal::script_id(&path);
                rebind(state, handle.id, path.clone(), id);
            }
            // The journal starts again from the bytes now on disk — carrying
            // whatever was typed while they were being written, because those
            // edits are not in them (F15).
            //
            // `checkpoint` alone would say "everything up to here is in the
            // file", which is true of every record this save covered and false
            // of the ones after it. Dropping those while `mark_saved_at` above
            // correctly leaves the document dirty is how a keystroke ends up in
            // neither the file nor the journal.
            if let Some(session) = state.session_mut(handle.id) {
                let unsaved = session.finish_save();
                if let Some(journal) = session.journal_mut() {
                    if unsaved.is_empty() {
                        let _ = journal.checkpoint(&path, &text);
                    } else {
                        // Rebuilt at its own path, not by id: a Save As has
                        // already changed the id by now and the journal file
                        // has not moved. Written atomically, so a crash in the
                        // middle leaves the old journal whole.
                        let at = journal.path().to_path_buf();
                        if let Ok(successor) = Journal::rebuild_at(&at, &path, &text, &unsaved) {
                            *journal = successor;
                        }
                        // A failed rebuild leaves the journal exactly as it was:
                        // its base no longer matches the file, so recovery will
                        // refuse it rather than replay onto the wrong bytes —
                        // but nothing has been destroyed, which is the property
                        // that matters. Same shape as a failed `checkpoint`.
                    }
                }
            }
            if let Some(storage) = state.storage_mut() {
                storage.library.refresh();
            }
            let page_count_job = state
                .session(handle.id)
                .and_then(Session::id)
                .map(str::to_owned)
                .and_then(|id| {
                    state.storage_mut().map(|storage| SavedPagination {
                        token: storage.begin_page_count(&id),
                        id,
                        handle: handle.id,
                        generation,
                        snapshot,
                    })
                });
            save_library(state);
            (
                state
                    .session(handle.id)
                    .is_some_and(|session| session.document().is_dirty()),
                page_count_job,
            )
        }
    });

    emit(CoreEvent::SaveStateChanged {
        handle: handle.id,
        dirty: still_dirty,
    });
    // The file is already safely on disk and the save state has already been
    // recorded. Pagination is best-effort cache work from this point on.
    drop(_writing);
    if let Some(job) = page_count_job {
        update_saved_page_count(job);
    }
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes,
        backup,
    }
}

/// Lets go of a save that planned but is not going to write.
///
/// [`Session::begin_save`] arms a buffer inside the plan closure, before it is
/// known whether there is anywhere to write or anything to write. Every early
/// return after that point comes through here, so a refused save does not leave
/// the session holding patches for a checkpoint that never comes.
fn abandon_save(handle: u64) {
    actor().run(move |state| {
        if let Some(session) = state.session_mut(handle) {
            session.finish_save();
        }
    });
}

struct Plan {
    path: Option<PathBuf>,
    text: String,
    revision: u64,
    dirty: bool,
    storage: Option<(PathBuf, Retention)>,
    /// `None` before `init`, which is a supported state (see [`AppState`]) and
    /// one in which there is no watcher to suppress anything for either.
    own_writes: Option<Arc<OwnWrites>>,
    /// The exact document whose serialisation is in `text`.
    snapshot: slugline_layout::ScriptSnapshot,
    /// Monotonic identity of that snapshot within the open session.
    generation: u64,
}

struct SavedPagination {
    token: u64,
    id: String,
    handle: u64,
    generation: u64,
    snapshot: slugline_layout::ScriptSnapshot,
}

fn update_saved_page_count(job: SavedPagination) {
    let result = catch_unwind(AssertUnwindSafe(|| {
        layout::paginate_snapshot(
            job.handle,
            job.generation,
            job.snapshot,
            &slugline_layout::PageConfig::default(),
        )
    }));
    let pagination = match result {
        Ok(pagination) => pagination,
        Err(_) => {
            eprintln!(
                "slugline: pagination failed after saving library entry {}",
                job.id
            );
            return;
        }
    };
    let page_count = u32::try_from(pagination.script.pages.len()).unwrap_or(u32::MAX);
    actor().run(move |state| {
        commit_saved_page_count(state, &job.id, job.token, page_count);
    });
}

fn commit_saved_page_count(state: &mut AppState, id: &str, token: u64, page_count: u32) {
    let Some(storage) = state.storage_mut() else {
        return;
    };
    if !storage.page_count_is_current(id, token) {
        return;
    }
    storage.library.set_page_count(id, page_count);
    save_library(state);
}

/// One write of one file, bracketed so the watcher can recognise its own echo.
///
/// A small thing with a name because the bracket has to be closed on **every**
/// path out of a write, and `abandoned` is as important as `finished`: a record
/// left in flight would swallow the next real external change to that file. See
/// [`OwnWrites`] for the lifecycle this is one turn of.
struct OwnWrite<'a> {
    register: Option<&'a Arc<OwnWrites>>,
    path: &'a Path,
    generation: u64,
}

impl<'a> OwnWrite<'a> {
    fn begin(register: Option<&'a Arc<OwnWrites>>, path: &'a Path) -> OwnWrite<'a> {
        let generation = register.map_or(0, |register| register.begin(path));
        OwnWrite {
            register,
            path,
            generation,
        }
    }

    /// The bytes are on the disk. Anything the watcher says about this file from
    /// here until somebody else touches it is our own noise.
    fn finished(self) {
        if let Some(register) = self.register {
            register.finished(self.path, self.generation);
        }
    }

    /// Nothing was written, so there is nothing to suppress.
    fn abandoned(self) {
        if let Some(register) = self.register {
            register.abandoned(self.path, self.generation);
        }
    }
}

/// A seam for the save-serialisation tests, and nothing else.
///
/// [`write_document`] spans two threads, and the property Phase 4A repairs —
/// that two saves of one script cannot land out of order — is only observable
/// if one of them can be held between planning its bytes and writing them. This
/// is that hold. Everything in here is `#[cfg(test)]`, so the shipped library
/// has neither the map nor the call site.
///
/// Holds are keyed by the file being written so that tests running side by side
/// in one binary cannot stall each other's saves.
#[cfg(test)]
mod stall {
    use std::collections::HashMap;
    use std::path::{Path, PathBuf};
    use std::sync::{Arc, Mutex, PoisonError};

    type Hold = Arc<dyn Fn() + Send + Sync>;

    static HOLDS: Mutex<Option<HashMap<PathBuf, Hold>>> = Mutex::new(None);

    fn holds() -> impl std::ops::DerefMut<Target = Option<HashMap<PathBuf, Hold>>> {
        HOLDS.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Runs `hold` on the writing thread, immediately before the bytes for
    /// `path` reach the disk.
    pub fn before_writing(path: &Path, hold: impl Fn() + Send + Sync + 'static) {
        holds()
            .get_or_insert_with(HashMap::new)
            .insert(path.to_path_buf(), Arc::new(hold));
    }

    pub fn forget(path: &Path) {
        if let Some(holds) = holds().as_mut() {
            holds.remove(path);
        }
    }

    pub fn reached(path: &Path) {
        // Cloned out and the map unlocked before the hold runs: a hold blocks,
        // and blocking with the map locked would stall every other test too.
        let hold = holds()
            .as_ref()
            .and_then(|holds| holds.get(path))
            .map(Arc::clone);
        if let Some(hold) = hold {
            hold();
        }
    }
}

/// A seam that holds an external-change check after its actor snapshot and
/// before its disk read. Like [`stall`], this exists only to make a cross-thread
/// ordering observable in tests.
#[cfg(test)]
mod external_change_stall {
    use std::collections::HashMap;
    use std::path::{Path, PathBuf};
    use std::sync::{Arc, Mutex, PoisonError};

    type Hold = Arc<dyn Fn() + Send + Sync>;

    static HOLDS: Mutex<Option<HashMap<PathBuf, Hold>>> = Mutex::new(None);

    fn holds() -> impl std::ops::DerefMut<Target = Option<HashMap<PathBuf, Hold>>> {
        HOLDS.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub fn before_reading(path: &Path, hold: impl Fn() + Send + Sync + 'static) {
        holds()
            .get_or_insert_with(HashMap::new)
            .insert(path.to_path_buf(), Arc::new(hold));
    }

    pub fn forget(path: &Path) {
        if let Some(holds) = holds().as_mut() {
            holds.remove(path);
        }
    }

    pub fn reached(path: &Path) {
        let hold = holds()
            .as_ref()
            .and_then(|holds| holds.get(path))
            .map(Arc::clone);
        if let Some(hold) = hold {
            hold();
        }
    }
}

// ---------------------------------------------------------------------------
// External modification
// ---------------------------------------------------------------------------

/// What the file on disk says now, next to what the document says.
///
/// Dart calls this when a [`CoreEvent::FileChangedOnDisk`] names a path it has
/// open. §Phase 4: reload silently when the document is unmodified, prompt when
/// it is not — and the two facts that decision needs are exactly the two here.
pub async fn doc_external_change(handle: DocumentHandle) -> Option<(bool, bool)> {
    let save_lock =
        actor().run(move |state| state.session(handle.id).map(|session| session.save_lock()))?;
    // Keep every save behind the comparison. Dart suppresses its autosave
    // timer too, but this is the authoritative boundary and also covers an
    // explicit save arriving from another bridge worker.
    let _claim = save_lock.lock().unwrap_or_else(PoisonError::into_inner);

    loop {
        let plan = actor().run(move |state| {
            let session = state.session(handle.id)?;
            Some(ExternalChangePlan {
                path: session.path()?.to_path_buf(),
                dirty: session.document().is_dirty(),
                generation: session.document_generation(),
                snapshot: session.document().serialisation_snapshot(),
            })
        })?;

        #[cfg(test)]
        external_change_stall::reached(&plan.path);
        let on_disk = std::fs::read_to_string(&plan.path).ok()?;
        let differs = on_disk != plan.snapshot.serialise();

        let validation = actor().run(move |state| {
            let session = state.session(handle.id)?;
            if session.path() != Some(plan.path.as_path()) {
                return None;
            }
            Some(
                (session.document_generation() == plan.generation
                    && session.document().is_dirty() == plan.dirty)
                    .then_some((plan.dirty, differs)),
            )
        });
        match validation {
            Some(Some(result)) => return Some(result),
            // An edit invalidated the snapshot. Keep saves held and compare the
            // new revision rather than returning a refusal that lets autosave
            // overwrite the external version without a decision.
            Some(None) => continue,
            None => return None,
        }
    }
}

struct ExternalChangePlan {
    path: PathBuf,
    dirty: bool,
    generation: u64,
    snapshot: model::SerialisationSnapshot,
}

/// "Take Theirs": throws away what is in memory and reads the file again.
///
/// The undo history goes with it. It has to: the transactions in it invert edits
/// against a document that no longer exists, and applying one would produce text
/// that was never anywhere.
pub async fn doc_reload(handle: DocumentHandle, only_if_clean: bool) -> bool {
    let save_lock =
        actor().run(move |state| state.session(handle.id).map(|session| session.save_lock()));
    let Some(save_lock) = save_lock else {
        return false;
    };
    // A reload and a save both replace the meaning of "what is on disk". The
    // same per-session claim keeps an older save from landing after the reload
    // and then marking the replacement document clean against different bytes.
    let _claim = save_lock.lock().unwrap_or_else(PoisonError::into_inner);

    let plan = actor().run(move |state| {
        let session = state.session(handle.id)?;
        if only_if_clean && session.document().is_dirty() {
            return None;
        }
        Some((session.path()?.to_path_buf(), session.document_generation()))
    });
    let Some((path, generation)) = plan else {
        return false;
    };
    let Ok(source) = std::fs::read_to_string(&path) else {
        return false;
    };

    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return false;
        };
        if session.path() != Some(path.as_path())
            || session.document_generation() != generation
            || (only_if_clean && session.document().is_dirty())
        {
            return false;
        }
        let document = model::Document::parse(&source);
        session.replace_document(if document.blocks().is_empty() {
            model::Document::blank()
        } else {
            document
        });
        session.rebuild_entities();
        restart_journal(state, handle.id, &source);
        true
    })
}

// ---------------------------------------------------------------------------
// Backups
// ---------------------------------------------------------------------------

/// Every rolling backup of this document, newest first.
pub async fn backups_list(handle: DocumentHandle) -> Vec<BackupView> {
    let plan = actor().run(move |state| {
        let root = state.storage().map(|storage| {
            storage
                .prefs
                .backup_dir
                .clone()
                .unwrap_or_else(|| storage.paths.backup_dir())
        })?;
        let path = state.session(handle.id)?.path()?.to_path_buf();
        Some((root, path))
    });
    let Some((root, path)) = plan else {
        return Vec::new();
    };
    backup::list(&root, &path)
        .into_iter()
        .map(|found| BackupView {
            path: found.path.to_string_lossy().into_owned(),
            written_millis: found.written_millis,
            bytes: found.bytes,
        })
        .collect()
}

/// §Phase 4's "Restore previous version".
///
/// "Restoring a backup writes the current state to a new backup first" — so this
/// saves before it restores, which means the restore is itself undoable by
/// restoring the copy it just made.
pub async fn backup_restore(handle: DocumentHandle, backup_path: String) -> SaveOutcome {
    let Ok(contents) = std::fs::read_to_string(&backup_path) else {
        return failed(
            SaveFailure::Io,
            Path::new(&backup_path),
            "that backup cannot be read",
        );
    };

    // The same claim [`write_document`] takes, for the same reason: a restore
    // *is* a write of this document's file, and an autosave landing in the
    // middle of one would leave the file and the document describing different
    // versions of the script.
    let lock = actor().run(move |state| state.session(handle.id).map(Session::save_lock));
    let Some(lock) = lock else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(&backup_path),
            "no document with that handle",
        );
    };
    let _writing = lock.lock().unwrap_or_else(PoisonError::into_inner);

    // The current state, backed up first. If this fails there is nothing to
    // restore *to*, so it stops here.
    let plan = actor().run(move |state| {
        let root = state.storage().map(|storage| {
            (
                storage
                    .prefs
                    .backup_dir
                    .clone()
                    .unwrap_or_else(|| storage.paths.backup_dir()),
                storage.prefs.retention(),
            )
        });
        let own_writes = state
            .storage()
            .map(|storage| Arc::clone(&storage.own_writes));
        let session = state.session(handle.id)?;
        Some((
            session.path()?.to_path_buf(),
            session.document().serialise(),
            root,
            own_writes,
        ))
    });
    let Some((path, current, root, own_writes)) = plan else {
        return failed(
            SaveFailure::NoPath,
            Path::new(""),
            "no file to restore into",
        );
    };
    if let Some((root, retention)) = &root {
        if let Err(error) = backup::write(root, &path, &current, *retention) {
            return SaveOutcome::Failed {
                failure: failure_of(&error),
                path: path.to_string_lossy().into_owned(),
                message: format!("could not preserve the current version: {error}"),
            };
        }
    }

    // A restore is a write of this document's file by another name, so it gets
    // the same bracket as [`write_document`]'s: the watcher must not report it
    // as somebody else's edit either.
    let own_write = OwnWrite::begin(own_writes.as_ref(), &path);
    if let Err(error) = atomic::save_atomically(&path, &contents) {
        own_write.abandoned();
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }
    own_write.finished();

    let bytes = contents.len().min(u32::MAX as usize) as u32;
    actor().run({
        let contents = contents.clone();
        move |state| {
            let Some(session) = state.session_mut(handle.id) else {
                return;
            };
            let document = model::Document::parse(&contents);
            session.replace_document(if document.blocks().is_empty() {
                model::Document::blank()
            } else {
                document
            });
            session.rebuild_entities();
            restart_journal(state, handle.id, &contents);
        }
    });
    emit(CoreEvent::SaveStateChanged {
        handle: handle.id,
        dirty: false,
    });
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes,
        backup: None,
    }
}

// ---------------------------------------------------------------------------
// Recovery
// ---------------------------------------------------------------------------

/// Every crashed session found at startup.
///
/// Reads the journals but applies nothing. §Phase 4 is explicit that recovery
/// "never auto-applies", and this is where that is enforced: the only thing that
/// can turn an offer into a document is the user answering the dialog.
pub async fn recovery_pending() -> Vec<RecoveryOffer> {
    let directory = actor().run(|state| state.storage().map(|storage| storage.paths.journal_dir()));
    let Some(directory) = directory else {
        return Vec::new();
    };

    let mut offers = Vec::new();
    for path in journal::pending(&directory) {
        let Ok(recovery) = journal::read(&path) else {
            // A journal we cannot read at all is a journal we cannot offer. It
            // is left on disk rather than deleted: it is the user's text, in a
            // form a person could still pick apart by hand.
            continue;
        };
        if recovery.is_empty() {
            // Nothing was typed after the last save. Not a loss, and not worth a
            // dialog — but the file has served its purpose, so it goes.
            let _ = journal::discard_at(&path);
            continue;
        }
        let untitled = journal::is_untitled(&recovery.header);
        let blocked = journal::verify(&recovery.header)
            .err()
            .map(|why| why.to_string());
        offers.push(RecoveryOffer {
            journal: path.to_string_lossy().into_owned(),
            script: recovery.header.script.to_string_lossy().into_owned(),
            title: if untitled {
                "Untitled".to_owned()
            } else {
                recovery
                    .header
                    .script
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned())
                    .unwrap_or_else(|| "Untitled".to_owned())
            },
            edits: recovery.patches.len().min(u32::MAX as usize) as u32,
            damaged: recovery.damaged,
            blocked,
        });
    }
    offers
}

/// Takes an offer: replays the journal and opens the result.
///
/// The document comes back **dirty**, and that is the point — the file on disk
/// is still the one from before the crash, and the writer decides whether to
/// keep what they are being shown.
///
/// ## The durability sequence
///
/// Recovery is the one moment in this program where the only durable copy of the
/// writer's text is a journal rather than a file. Everything below is arranged
/// around one rule: **that journal does not stop existing until an equivalent
/// one does.**
///
/// 1. Read and verify the old journal. Verification returns the file's real
///    bytes, which are still the pre-crash ones.
/// 2. Replay onto those bytes, remembering exactly which patches applied. A
///    patch that does not fit stops the replay, and the ones after it are not in
///    the recovered document, so they must not be in its journal either.
/// 3. Open the document and bind it to its file, library entry and watch.
/// 4. Write the **successor journal**: same `base` — the file has not changed —
///    plus the patches that replayed. [`Journal::rebuild`] writes it through the
///    atomic save, so it either exists whole or does not exist.
/// 5. Only now remove the old journal, and only if the successor did not already
///    replace it at the same path.
///
/// What this buys, and what the previous sequence did not: a second crash before
/// the writer saves or types anything recovers exactly what the first one did,
/// and a second crash *after* they type more recovers both. The old sequence
/// removed the journal at step 3 and started an empty one whose `base` was the
/// in-memory text, which matched no file — so the recovered edits existed only in
/// memory, and a journal written against them came back from [`journal::verify`]
/// as `blocked`.
///
/// Notice what is *not* here: a save. Recovery still never writes the script.
pub async fn recovery_accept(journal_path: String) -> RecoveryOutcome {
    let path = PathBuf::from(&journal_path);
    let recovery = match journal::read(&path) {
        Ok(recovery) => recovery,
        Err(why) => {
            return RecoveryOutcome::Failed {
                message: why.to_string(),
            }
        }
    };
    let source = match journal::verify(&recovery.header) {
        Ok(source) => source,
        Err(why) => {
            return RecoveryOutcome::Failed {
                message: why.to_string(),
            }
        }
    };
    let untitled = journal::is_untitled(&recovery.header);

    let mut document = if untitled {
        model::Document::blank()
    } else {
        let parsed = model::Document::parse(&source);
        if parsed.blocks().is_empty() {
            model::Document::blank()
        } else {
            parsed
        }
    };
    // A patch that does not fit stops the replay. What is already applied is
    // still offered — those edits did happen — and the rest is not guessed at.
    // `applied` is where the replay stopped, and it is what the successor
    // journal records: a journal must describe the document it belongs to.
    let mut applied = 0;
    for patch in &recovery.patches {
        if document.replay(patch).is_err() {
            break;
        }
        applied += 1;
    }
    if applied == 0 && !recovery.patches.is_empty() {
        // Nothing replayed, so there is nothing to recover and nothing to write
        // a successor from — and rebuilding here would replace a journal full of
        // the writer's text with an empty one. `recovery_pending` leaves a
        // journal it cannot read on disk for exactly this reason: it is their
        // text, in a form a person can still pick apart by hand.
        return RecoveryOutcome::Failed {
            message: "none of the recorded edits fit the file, so nothing could be \
                      recovered; the journal has been left where it is"
                .to_owned(),
        };
    }
    let applied = &recovery.patches[..applied];

    let script = recovery.header.script.clone();
    let handle = actor().run({
        let script = script.clone();
        move |state| {
            let handle = state.open(document);
            if !untitled {
                let id = journal::script_id(&script);
                if let Some(session) = state.session_mut(handle) {
                    session.set_file(script.clone(), id.clone());
                }
                if let Some(storage) = state.storage_mut() {
                    storage.library.add(&script);
                    storage.library.opened(&id);
                }
                hydrate_pins(state, handle, &id);
                watch(state, &script);
                save_library(state);
            }
            handle
        }
    });

    // The successor, against the bytes the file still holds. Off the actor: it
    // is a disk write (§2.3).
    let directory = actor().run(|state| state.storage().map(|storage| storage.paths.journal_dir()));
    let Some(directory) = directory else {
        return degraded(handle, "the core has no state directory to journal into");
    };
    let id = if untitled {
        format!("untitled-{}-{handle}", std::process::id())
    } else {
        journal::script_id(&script)
    };
    let successor = match Journal::rebuild(&directory, &id, &script, &source, applied) {
        Ok(successor) => successor,
        Err(error) => {
            // The old journal is untouched, so the recovered text is still on
            // disk in the form it arrived in. Nothing typed from here is.
            return degraded(
                handle,
                &format!("the recovery journal could not be written: {error}"),
            );
        }
    };

    // The recovered edits are now described by two journals, or by one file that
    // replaced the other. Either way there has not been an instant with none.
    let successor_path = successor.path().to_path_buf();
    actor().run(move |state| {
        if let Some(session) = state.session_mut(handle) {
            session.set_journal(Some(successor));
        }
    });
    if successor_path != path {
        let _ = journal::discard_at(&path);
    }
    RecoveryOutcome::Recovered {
        handle: DocumentHandle { id: handle },
    }
}

/// Open, replayed, and not being recorded. Says so rather than looking like a
/// normal session that happens to be losing keystrokes.
fn degraded(handle: u64, message: &str) -> RecoveryOutcome {
    actor().run(move |state| {
        if let Some(session) = state.session_mut(handle) {
            session.set_journal(None);
        }
    });
    RecoveryOutcome::Degraded {
        handle: DocumentHandle { id: handle },
        message: message.to_owned(),
    }
}

/// Declines an offer. The journal is deleted; the file is untouched.
pub async fn recovery_discard(journal_path: String) -> bool {
    journal::discard_at(Path::new(&journal_path)).is_ok()
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

#[frb(sync)]
pub fn prefs_get() -> PreferencesView {
    actor().run(|state| {
        state
            .storage()
            .map(|storage| prefs_view(&storage.prefs))
            .unwrap_or_else(|| prefs_view(&CorePreferences::default()))
    })
}

pub async fn prefs_set(preferences: PreferencesView) -> bool {
    actor().run(move |state| {
        let Some(storage) = state.storage_mut() else {
            return false;
        };
        storage.prefs = prefs::Preferences {
            autosave_enabled: preferences.autosave_enabled,
            autocomplete_enabled: preferences.autocomplete_enabled,
            autosave_idle_ms: preferences.autosave_idle_ms,
            autosave_interval_ms: preferences.autosave_interval_ms,
            backup_dir: preferences.backup_dir.map(PathBuf::from),
            backup_keep_versions: preferences.backup_keep_versions,
            backup_keep_days: preferences.backup_keep_days,
        };
        let path = storage.paths.preferences();
        storage.prefs.save(&path).is_ok()
    })
}

// ---------------------------------------------------------------------------
// Shared machinery
// ---------------------------------------------------------------------------

/// Opens a document over a file: the handle, the library entry, the watch and
/// the journal, in one place so that no path can forget one of them.
fn open_source(path: PathBuf, source: String, blank_if_empty: bool) -> DocumentHandle {
    let parsed = model::Document::parse(&source);
    let document = if parsed.blocks().is_empty() || (blank_if_empty && source.is_empty()) {
        model::Document::blank()
    } else {
        parsed
    };

    let id = journal::script_id(&path);
    DocumentHandle {
        id: actor().run(move |state| {
            // The check `library_open` already made, made again where it is
            // atomic with the insert. Both callers read the file off the actor
            // first, so two opens of one path can arrive here having both been
            // told it was free — and two documents over one file is two undo
            // histories, two journals and two savers racing for it. The parse
            // above is thrown away in that case, which costs a read the loser
            // had already paid for.
            if let Some(existing) = state.handle_for(&path) {
                return existing;
            }
            let handle = state.open(document);
            if let Some(session) = state.session_mut(handle) {
                session.set_file(path.clone(), id.clone());
            }
            if let Some(storage) = state.storage_mut() {
                storage.library.add(&path);
                storage.library.opened(&id);
            }
            hydrate_pins(state, handle, &id);
            watch(state, &path);
            restart_journal(state, handle, &source);
            save_library(state);
            handle
        }),
    }
}

/// Moves an open session to a new path, taking its journal and its library entry
/// with it.
fn rebind(state: &mut AppState, handle: u64, path: PathBuf, id: String) {
    let old_path = state
        .session(handle)
        .and_then(Session::path)
        .map(Path::to_path_buf);
    if let (Some(storage), Some(old)) = (state.storage_mut(), old_path.as_ref()) {
        // The suppression record for the path this session is leaving goes with
        // the watch on it. A Save As has already written the *new* path by the
        // time this runs, so only the old one is forgotten.
        storage.own_writes.forget(old);
        if let Some(watcher) = storage.watcher.as_mut() {
            let _ = watcher.unwatch(old);
        }
    }
    if let Some(session) = state.session_mut(handle) {
        session.set_file(path.clone(), id.clone());
    }
    if let Some(storage) = state.storage_mut() {
        storage.library.add(&path);
        storage.library.opened(&id);
    }
    hydrate_pins(state, handle, &id);
    watch(state, &path);
}

fn hydrate_pins(state: &mut AppState, handle: u64, id: &str) {
    let pins = state
        .storage()
        .and_then(|storage| storage.library.get(id))
        .map(|entry| entry.pinned_entities.clone())
        .unwrap_or_default()
        .into_iter()
        .filter_map(|pin| {
            let kind = match pin.kind.as_str() {
                "character" => model::EntityKind::Character,
                "location" => model::EntityKind::Location,
                "scene_prefix" => model::EntityKind::ScenePrefix,
                "time_of_day" => model::EntityKind::TimeOfDay,
                "transition" => model::EntityKind::Transition,
                _ => return None,
            };
            Some((kind, pin.value))
        })
        .collect::<Vec<_>>();
    if let Some(session) = state.session_mut(handle) {
        session.load_pins(pins);
    }
}

/// Starts a fresh journal for a session, against `base` as the file's contents.
///
/// A session with no file still gets one, keyed by its handle: the script a
/// crash costs most is the one that has never been saved anywhere.
fn restart_journal(state: &mut AppState, handle: u64, base: &str) {
    let Some(storage) = state.storage() else {
        return;
    };
    let directory = storage.paths.journal_dir();
    let Some(session) = state.session(handle) else {
        return;
    };
    let (id, script) = match session.path() {
        Some(path) => (journal::script_id(path), path.to_path_buf()),
        None => (
            format!("untitled-{}-{handle}", std::process::id()),
            PathBuf::new(),
        ),
    };
    let journal = Journal::create(&directory, &id, &script, base).ok();
    if let Some(session) = state.session_mut(handle) {
        session.set_journal(journal);
    }
}

fn watch(state: &mut AppState, path: &Path) {
    if let Some(storage) = state.storage_mut() {
        if let Some(watcher) = storage.watcher.as_mut() {
            let _ = watcher.watch(path);
        }
    }
}

/// Writes the library index. Best effort by design: it is a cache (§Phase 4), so
/// failing to write it costs the recent list and nothing else, and a save that
/// failed because the index could not be written would be absurd.
fn save_library(state: &mut AppState) {
    if let Some(storage) = state.storage() {
        let path = storage.paths.library_index();
        let _ = storage.library.save(&path);
    }
}

fn script_view(entry: &ScriptEntry) -> ScriptView {
    ScriptView {
        id: entry.id.clone(),
        path: entry.path.to_string_lossy().into_owned(),
        title: entry.title.clone(),
        modified_millis: entry.modified_millis,
        bytes: entry.bytes,
        page_count: entry.page_count,
        missing: entry.missing,
        open: entry.open,
        scroll_row: entry.scroll_row,
    }
}

fn prefs_view(preferences: &CorePreferences) -> PreferencesView {
    PreferencesView {
        autosave_enabled: preferences.autosave_enabled,
        autocomplete_enabled: preferences.autocomplete_enabled,
        autosave_idle_ms: preferences.autosave_idle_ms,
        autosave_interval_ms: preferences.autosave_interval_ms,
        backup_dir: preferences
            .backup_dir
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned()),
        backup_keep_versions: preferences.backup_keep_versions,
        backup_keep_days: preferences.backup_keep_days,
    }
}

fn failure_of(error: &atomic::SaveError) -> SaveFailure {
    match error {
        atomic::SaveError::ReadOnly { .. } => SaveFailure::ReadOnly,
        atomic::SaveError::PermissionDenied { .. } => SaveFailure::PermissionDenied,
        atomic::SaveError::NoSpace { .. } => SaveFailure::NoSpace,
        atomic::SaveError::NoSuchDirectory { .. } => SaveFailure::NoSuchDirectory,
        atomic::SaveError::Io { .. } => SaveFailure::Io,
    }
}

fn failed(failure: SaveFailure, path: &Path, message: &str) -> SaveOutcome {
    SaveOutcome::Failed {
        failure,
        path: path.to_string_lossy().into_owned(),
        message: message.to_owned(),
    }
}

/// Whether two paths name the same file.
///
/// Compared as written first — the cheap answer, and the only one available for
/// a destination that does not exist yet — and through the filesystem second, so
/// that a symlinked directory or a `..` cannot spell an open script differently
/// enough to get past [`doc_export_fountain`]'s refusal.
fn same_file(one: &Path, other: &Path) -> bool {
    if one == other {
        return true;
    }
    match (one.canonicalize(), other.canonicalize()) {
        (Ok(one), Ok(other)) => one == other,
        _ => false,
    }
}

/// `heat.fountain` → `heat copy.fountain`, then `heat copy 2.fountain`.
fn unused_path(path: &Path) -> Option<PathBuf> {
    let parent = path.parent()?;
    let stem = path.file_stem()?.to_string_lossy().into_owned();
    let extension = path
        .extension()
        .map(|extension| format!(".{}", extension.to_string_lossy()))
        .unwrap_or_default();
    for attempt in 0..100 {
        let name = match attempt {
            0 => format!("{stem} copy{extension}"),
            n => format!("{stem} copy {}{extension}", n + 1),
        };
        let candidate = parent.join(name);
        if !candidate.exists() {
            return Some(candidate);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Phase 4A: two saves of one script cannot write out of order.
///
/// These run against the real save path — the actor, the plan, the atomic
/// write, the journal checkpoint — rather than against a model of it, because
/// the defect they cover lives in the *seam* between those steps and a model
/// would have to reproduce the seam to be wrong in the same way.
#[cfg(test)]
mod tests {
    use super::*;

    use std::fs;
    use std::future::Future;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::sync::mpsc::{self, Receiver, Sender};
    use std::sync::{Mutex, MutexGuard};
    use std::task::{Context, Poll, Waker};
    use std::thread;
    use std::time::Duration;

    use crate::api::doc::{doc_apply, doc_blocks, doc_source, EditCommand};

    const SCRIPT: &str = "The house is quiet.\n";

    /// How long a save is given to reach the disk before the test calls it
    /// stuck. Generous: a wrong answer here should mean a deadlock, not a busy
    /// machine.
    const PATIENCE: Duration = Duration::from_secs(10);

    /// How long a queued save is given to overtake the one in flight. It never
    /// should, so this is time the test spends *not* seeing something — long
    /// enough that its absence means the lock held, short enough to pay twice.
    const LONG_ENOUGH_TO_OVERTAKE: Duration = Duration::from_millis(500);

    /// The async functions in this module have no `.await` in them — they call
    /// the actor, which blocks — so a single poll drives one to completion.
    /// That is the whole runtime this crate needs, and the panic below is what
    /// would notice if it ever stopped being true.
    fn block_on<F: Future>(future: F) -> F::Output {
        let mut future = Box::pin(future);
        match future
            .as_mut()
            .poll(&mut Context::from_waker(Waker::noop()))
        {
            Poll::Ready(value) => value,
            Poll::Pending => panic!("a bridge future yielded, and this crate has no runtime"),
        }
    }

    /// `AppState` has one `storage`, and these tests point it at their own
    /// temporary directories, so they must not run beside each other. Every
    /// fixture holds this for its whole life.
    static STORAGE: Mutex<()> = Mutex::new(());

    /// A state directory, a script file, and that script open.
    struct Fixture {
        _storage: MutexGuard<'static, ()>,
        root: PathBuf,
        script: PathBuf,
        handle: DocumentHandle,
    }

    impl Fixture {
        fn open(label: &str) -> Fixture {
            Self::open_source(label, SCRIPT)
        }

        fn open_source(label: &str, source: &str) -> Fixture {
            let storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
            let root = temp_root(label);
            let script = root.join(format!("{label}.fountain"));
            fs::write(&script, source).expect("the script is written");

            let paths = Paths::under(&root);
            let library = Library::load(&paths.library_index());
            let storage_state = Storage {
                paths,
                prefs: CorePreferences::default(),
                library,
                // No inotify: the watcher's own filtering is proved against real
                // events in `storage::watch`, and a watch descriptor per test
                // would be a slow way to find that out again. What these tests
                // watch instead is the register the watcher asks — which is the
                // half the save path owns.
                watcher: None,
                own_writes: OwnWrites::shared(),
                page_count_jobs: Default::default(),
                next_page_count_job: 0,
            };
            actor().run(move |state| state.set_storage(storage_state));

            let handle = block_on(library_open(script.to_string_lossy().into_owned()))
                .expect("the script opens");
            Fixture {
                _storage: storage,
                root,
                script,
                handle,
            }
        }

        /// A second script under the same state directory. A second `Fixture`
        /// would deadlock on [`STORAGE`] and install a second set of
        /// directories over the first.
        fn beside(&self, label: &str) -> Sibling {
            let script = self.root.join(format!("{label}.fountain"));
            fs::write(&script, SCRIPT).expect("the script is written");
            let handle = block_on(library_open(script.to_string_lossy().into_owned()))
                .expect("the script opens");
            Sibling { script, handle }
        }

        fn on_disk(&self) -> String {
            fs::read_to_string(&self.script).expect("the script is readable")
        }

        fn in_memory(&self) -> String {
            doc_source(self.handle)
        }

        fn dirty(&self) -> bool {
            doc_dirty(self.handle)
        }

        fn page_count(&self) -> u32 {
            let id = journal::script_id(&self.script);
            actor().run(move |state| {
                state
                    .storage()
                    .and_then(|storage| storage.library.get(&id))
                    .map(|entry| entry.page_count)
                    .unwrap_or(0)
            })
        }

        fn pagination_runs(&self) -> u64 {
            let handle = self.handle.id;
            actor().run(move |state| {
                state
                    .session(handle)
                    .map(|session| session.pagination().runs())
                    .unwrap_or(0)
            })
        }

        /// Types at the front of the first block, through the same edit path
        /// the editor uses — so the journal sees it too.
        fn types(&self, text: &str) {
            let block = doc_blocks(self.handle, 0, 1)[0].id;
            let _ = doc_apply(
                self.handle,
                EditCommand::ReplaceText {
                    block,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: text.to_owned(),
                },
                None,
            );
        }

        fn journal_path(&self) -> PathBuf {
            let directory = actor().run(|state| {
                state
                    .storage()
                    .map(|storage| storage.paths.journal_dir())
                    .expect("storage is installed")
            });
            directory.join(format!("{}.log", journal::script_id(&self.script)))
        }

        /// What the crash journal would recover to. `Ok` only if the journal on
        /// disk still describes the file on disk — which is the property a save
        /// that checkpointed against bytes it did not write would break.
        fn journal_agrees_with_the_file(&self) -> bool {
            let Ok(recovery) = journal::read(&self.journal_path()) else {
                return false;
            };
            journal::verify(&recovery.header).is_ok_and(|base| base == self.on_disk())
        }

        /// The text this session would come back as if the process were killed
        /// right now: the file on disk, with the journal replayed onto it.
        ///
        /// This is `recovery_accept`'s sequence, at the level a unit test can
        /// reach — the whole point of a journal is that this equals what the
        /// writer can see, and F15 is a window in which it did not.
        fn recovers_to(&self) -> String {
            let recovery = journal::read(&self.journal_path()).expect("the journal reads");
            let source =
                journal::verify(&recovery.header).expect("the journal describes the file on disk");
            let mut document = model::Document::parse(&source);
            for patch in &recovery.patches {
                document.replay(patch).expect("every record replays");
            }
            document.serialise()
        }

        fn journalled(&self) -> u32 {
            doc_journal_state(self.handle).0
        }

        /// The file this session's journal says it is the journal *for*. What a
        /// Save As moves and an export must not (F9).
        fn journal_describes(&self) -> Option<PathBuf> {
            journal::read(&self.journal_path())
                .ok()
                .map(|recovery| recovery.header.script)
        }

        fn library_has(&self, id: &str) -> bool {
            let id = id.to_owned();
            actor().run(move |state| {
                state
                    .storage()
                    .is_some_and(|storage| storage.library.get(&id).is_some())
            })
        }

        fn is_saving(&self) -> bool {
            let handle = self.handle;
            actor().run(move |state| {
                state
                    .session(handle.id)
                    .is_some_and(|session| session.is_saving())
            })
        }

        /// The register the watcher consults. Reaching for it directly is what
        /// lets these tests ask the F4 question — "would this event be reported
        /// as somebody else's?" — without an inotify descriptor and a wait.
        fn own_writes(&self) -> Arc<OwnWrites> {
            actor().run(|state| {
                state
                    .storage()
                    .map(|storage| Arc::clone(&storage.own_writes))
                    .expect("storage is installed")
            })
        }

        /// Whether a watcher event about this script right now would reach Dart.
        fn would_be_reported(&self) -> bool {
            !self.own_writes().is_echo(&self.script)
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            stall::forget(&self.script);
            external_change_stall::forget(&self.script);
            let handle = self.handle;
            actor().run(move |state| state.close(handle.id));
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    /// A second open script, sharing the fixture's state directory.
    struct Sibling {
        script: PathBuf,
        handle: DocumentHandle,
    }

    impl Sibling {
        fn types(&self, text: &str) {
            let block = doc_blocks(self.handle, 0, 1)[0].id;
            let _ = doc_apply(
                self.handle,
                EditCommand::ReplaceText {
                    block,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: text.to_owned(),
                },
                None,
            );
        }

        fn on_disk(&self) -> String {
            fs::read_to_string(&self.script).expect("the script is readable")
        }

        fn in_memory(&self) -> String {
            doc_source(self.handle)
        }
    }

    impl Drop for Sibling {
        fn drop(&mut self) {
            stall::forget(&self.script);
            let handle = self.handle;
            actor().run(move |state| state.close(handle.id));
        }
    }

    fn temp_root(label: &str) -> PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "slugline-4a-{label}-{}-{unique}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("a temporary directory");
        root
    }

    /// Holds the **first** write of `path` between its plan and the disk, so a
    /// second save has somewhere to overtake it from.
    struct Gate {
        arrived: Receiver<()>,
        release: Sender<()>,
    }

    impl Gate {
        fn hold_the_first_write(path: &Path) -> Gate {
            let (arrived, waiting) = mpsc::channel();
            let (release, released) = mpsc::channel::<()>();
            let released = Mutex::new(released);
            let first = AtomicBool::new(true);
            stall::before_writing(path, move || {
                if !first.swap(false, Ordering::SeqCst) {
                    return;
                }
                arrived.send(()).expect("the test is waiting for this save");
                released
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .recv()
                    .expect("the test releases this save");
            });
            Gate {
                arrived: waiting,
                release,
            }
        }

        fn hold_external_change_read(path: &Path) -> Gate {
            let (arrived, waiting) = mpsc::channel();
            let (release, released) = mpsc::channel::<()>();
            let released = Mutex::new(released);
            let first = AtomicBool::new(true);
            external_change_stall::before_reading(path, move || {
                if !first.swap(false, Ordering::SeqCst) {
                    return;
                }
                arrived
                    .send(())
                    .expect("the test is waiting for this check");
                released
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .recv()
                    .expect("the test releases this check");
            });
            Gate {
                arrived: waiting,
                release,
            }
        }

        fn wait(&self) {
            self.arrived
                .recv_timeout(PATIENCE)
                .expect("the save reached the disk");
        }

        fn release(&self) {
            self.release
                .send(())
                .expect("a save is waiting on the gate");
        }
    }

    /// A save running on its own thread, the way a save really runs: `doc_save`
    /// and `doc_autosave` are `async` and FRB calls them from a worker pool.
    struct Saving {
        thread: thread::JoinHandle<SaveOutcome>,
        finished: Receiver<()>,
    }

    impl Saving {
        fn explicit(handle: DocumentHandle) -> Saving {
            Saving::spawn(move || block_on(doc_save(handle)))
        }

        fn auto(handle: DocumentHandle) -> Saving {
            Saving::spawn(move || block_on(doc_autosave(handle)))
        }

        fn spawn(save: impl FnOnce() -> SaveOutcome + Send + 'static) -> Saving {
            let (done, finished) = mpsc::channel();
            let thread = thread::spawn(move || {
                let outcome = save();
                let _ = done.send(());
                outcome
            });
            Saving { thread, finished }
        }

        /// Whether this save finished while another was still in flight. The
        /// answer must be no, and the wait is how long it is given to be wrong.
        fn overtook(&self) -> bool {
            self.finished.recv_timeout(LONG_ENOUGH_TO_OVERTAKE).is_ok()
        }

        fn outcome(self) -> SaveOutcome {
            self.thread.join().expect("the save thread finished")
        }
    }

    fn bytes_of(outcome: &SaveOutcome) -> u32 {
        match outcome {
            SaveOutcome::Saved { bytes, .. } => *bytes,
            other => panic!("expected a save, got {other:?}"),
        }
    }

    /// F5, exactly as the audit describes it: two saves plan in order and could
    /// write in reverse, leaving the file holding older bytes than the save that
    /// already answered "Saved".
    #[test]
    fn an_older_save_cannot_land_after_a_newer_one() {
        let it = Fixture::open("inversion");
        let gate = Gate::hold_the_first_write(&it.script);

        it.types("One. ");
        let older = it.in_memory();
        let first = Saving::explicit(it.handle);
        gate.wait();

        // The edit that makes the second save newer. It lands while the first
        // is at the disk, which is the whole difficulty: the bytes the first
        // save is carrying are already out of date.
        it.types("Two. ");
        let newest = it.in_memory();
        assert_ne!(older, newest);
        let second = Saving::explicit(it.handle);

        assert!(
            !second.overtook(),
            "the second save wrote while the first was still in flight"
        );
        gate.release();

        let first = first.outcome();
        let second = second.outcome();
        assert_eq!(
            it.on_disk(),
            newest,
            "the file must end with the newest text, not the save that started first"
        );
        assert_eq!(
            bytes_of(&first),
            older.len() as u32,
            "the first save reports the bytes it actually wrote"
        );
        assert_eq!(bytes_of(&second), newest.len() as u32);
        assert!(!it.dirty(), "everything typed is now in the file");
        assert!(
            it.journal_agrees_with_the_file(),
            "the journal is checkpointed against the bytes that won"
        );
    }

    /// The overlap the audit says is reachable today: `AutosaveDriver._saving`
    /// guards the driver's own calls, and Ctrl+S is not one of them.
    #[test]
    fn an_explicit_save_queued_behind_an_autosave_still_writes_the_newest_text() {
        let it = Fixture::open("explicit-over-auto");
        let gate = Gate::hold_the_first_write(&it.script);

        it.types("Autosaved. ");
        let automatic = Saving::auto(it.handle);
        gate.wait();

        it.types("Then Ctrl+S. ");
        let newest = it.in_memory();
        let explicit = Saving::explicit(it.handle);

        assert!(
            !explicit.overtook(),
            "Ctrl+S wrote over an autosave in flight"
        );
        gate.release();

        let automatic = automatic.outcome();
        let explicit = explicit.outcome();
        assert!(matches!(automatic, SaveOutcome::Saved { .. }));
        assert!(matches!(explicit, SaveOutcome::Saved { .. }));
        assert_eq!(it.on_disk(), newest);
        assert!(!it.dirty());
        assert!(it.journal_agrees_with_the_file());
    }

    /// The coalescing half of the decision. A save that queues behind one which
    /// wrote everything it would have written does not write again — and says
    /// so, rather than reporting a save that did not happen.
    #[test]
    fn a_save_with_nothing_left_to_write_says_unchanged() {
        let it = Fixture::open("coalesce");
        let gate = Gate::hold_the_first_write(&it.script);

        it.types("Once. ");
        let text = it.in_memory();
        let first = Saving::explicit(it.handle);
        gate.wait();

        // No edit this time: by the time the second save can plan, the first
        // has written exactly the bytes it would have.
        let second = Saving::auto(it.handle);
        assert!(!second.overtook());
        gate.release();

        assert!(matches!(first.outcome(), SaveOutcome::Saved { .. }));
        assert_eq!(
            second.outcome(),
            SaveOutcome::Unchanged,
            "a redundant queued save writes nothing and reports nothing"
        );
        assert_eq!(it.on_disk(), text);
    }

    #[test]
    fn an_explicit_save_updates_the_library_page_count() {
        let it = Fixture::open("page-count-explicit");
        it.types("Saved. ");

        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.page_count(), 1);
    }

    #[test]
    fn an_autosave_updates_the_library_page_count() {
        let it = Fixture::open("page-count-auto");
        it.types("Autosaved. ");

        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.page_count(), 1);
    }

    #[test]
    fn pagination_failure_does_not_fail_the_save_or_replace_the_count() {
        let it = Fixture::open("page-count-failure");
        it.types("First. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.page_count(), 1);

        it.types("Second. ");
        layout::stall::before_recording(it.handle.id, || panic!("injected pagination failure"));
        let outcome = block_on(doc_save(it.handle));
        layout::stall::forget(it.handle.id);

        assert!(matches!(outcome, SaveOutcome::Saved { .. }));
        assert_eq!(it.page_count(), 1, "the previous cache value survives");
    }

    #[test]
    fn an_older_pagination_result_cannot_replace_a_newer_page_count() {
        let it = Fixture::open("page-count-stale");
        let id = journal::script_id(&it.script);
        let (older, newer) = actor().run({
            let id = id.clone();
            move |state| {
                let storage = state.storage_mut().unwrap();
                let older = storage.begin_page_count(&id);
                let newer = storage.begin_page_count(&id);
                (older, newer)
            }
        });

        actor().run({
            let id = id.clone();
            move |state| {
                commit_saved_page_count(state, &id, newer, 120);
                commit_saved_page_count(state, &id, older, 1);
            }
        });

        assert_eq!(it.page_count(), 120);
    }

    #[test]
    fn listing_the_library_does_not_eagerly_paginate_scripts() {
        let it = Fixture::open("page-count-scan");
        assert_eq!(it.pagination_runs(), 0);

        let scripts = block_on(library_list());

        assert_eq!(scripts.len(), 1);
        assert_eq!(scripts[0].page_count, 0);
        assert_eq!(it.pagination_runs(), 0);
    }

    #[test]
    fn page_count_survives_a_library_restart() {
        let it = Fixture::open("page-count-restart");
        it.types("Saved. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        let index = it.root.join("data").join("library.json");
        let id = journal::script_id(&it.script);

        let loaded = Library::load(&index);

        assert_eq!(loaded.get(&id).unwrap().page_count, 1);
    }

    #[test]
    fn bridge_rss_with_the_reference_script_and_its_saved_layout_is_under_budget() {
        const MIB: u64 = 1024 * 1024;
        const BUDGET: u64 = 250 * MIB;
        let source = include_str!("../../../../testdata/reference-feature.fountain");
        let it = Fixture::open_source("page-count-rss", source);
        let before = linux_rss();
        it.types(" ");

        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert!(it.page_count() > 100, "the reference feature was paginated");

        let rss = linux_rss();
        eprintln!(
            "bridge RSS with {}-page reference script open: {:.1} MiB; retained layout delta: {:.1} MiB (budget: 250 MiB)",
            it.page_count(),
            rss as f64 / MIB as f64,
            rss.saturating_sub(before) as f64 / MIB as f64,
        );
        assert!(
            rss < BUDGET,
            "RSS is {:.1} MiB, over the 250 MiB budget",
            rss as f64 / MIB as f64
        );
    }

    fn linux_rss() -> u64 {
        let status = fs::read_to_string("/proc/self/status").expect("Linux exposes process RSS");
        status
            .lines()
            .find_map(|line| line.strip_prefix("VmRSS:"))
            .and_then(|value| value.split_whitespace().next())
            .and_then(|value| value.parse::<u64>().ok())
            .map(|kib| kib * 1024)
            .expect("VmRSS is reported in KiB")
    }

    /// The lock is per session, not per process: one script stuck at the disk
    /// must not hold up another. Without this the repair would trade a rare
    /// interleaving for a common stall.
    #[test]
    fn one_script_at_the_disk_does_not_hold_up_another() {
        let held = Fixture::open("held");
        let free = held.beside("free");
        let gate = Gate::hold_the_first_write(&held.script);

        held.types("Waiting. ");
        let stuck = Saving::explicit(held.handle);
        gate.wait();

        free.types("Not waiting. ");
        let independent = Saving::explicit(free.handle);
        assert!(
            independent.overtook(),
            "a save of a different script waited for one it has nothing to do with"
        );
        assert!(matches!(independent.outcome(), SaveOutcome::Saved { .. }));
        assert_eq!(free.on_disk(), free.in_memory());

        gate.release();
        assert!(matches!(stuck.outcome(), SaveOutcome::Saved { .. }));
    }

    /// F15. A save writes the bytes it planned; anything typed while it is
    /// writing is not in them, and `checkpoint` used to throw those records away
    /// along with the ones the save really did cover — leaving the keystroke in
    /// neither the file nor the journal, and `recovery_pending` discarding an
    /// empty journal as a clean session.
    #[test]
    fn an_edit_typed_during_a_save_is_still_in_the_journal() {
        let it = Fixture::open("mid-write");
        let gate = Gate::hold_the_first_write(&it.script);

        it.types("One. ");
        let written = it.in_memory();
        let saving = Saving::explicit(it.handle);
        gate.wait();

        it.types("Two. ");
        let newest = it.in_memory();
        gate.release();
        assert!(matches!(saving.outcome(), SaveOutcome::Saved { .. }));

        // The save wrote what it planned and said so honestly.
        assert_eq!(it.on_disk(), written);
        assert!(it.dirty(), "the edit typed during the write is unsaved");
        assert_eq!(it.journalled(), 1, "and exactly it is journalled");

        // The property: killed here, the writer gets everything back.
        assert_eq!(
            it.recovers_to(),
            newest,
            "the journal must still carry the edit the file does not have"
        );
        assert!(it.journal_agrees_with_the_file());
    }

    /// The ordinary case, which must not have grown a rebuild: nothing was
    /// typed during the write, so the journal is emptied as before.
    #[test]
    fn a_save_with_nothing_typed_during_it_empties_the_journal() {
        let it = Fixture::open("plain-checkpoint");
        it.types("Once. ");
        assert_eq!(it.journalled(), 1);

        let outcome = block_on(doc_save(it.handle));
        assert!(matches!(outcome, SaveOutcome::Saved { .. }));
        assert_eq!(it.journalled(), 0, "everything recorded is in the file");
        assert!(!it.dirty());
        assert_eq!(it.recovers_to(), it.on_disk());
        assert!(!it.is_saving(), "and the save let go of its buffer");
    }

    /// The two ways a save can plan and then not write. Both arm the buffer
    /// before they know that, so both have to disarm it.
    #[test]
    fn a_save_that_writes_nothing_does_not_leave_the_session_buffering() {
        let it = Fixture::open("abandoned");

        // Clean: nothing to write.
        assert_eq!(block_on(doc_save(it.handle)), SaveOutcome::Unchanged);
        assert!(!it.is_saving());

        // Unwritable: the directory is gone.
        it.types("Doomed. ");
        fs::remove_file(&it.script).expect("the script is removed");
        fs::remove_dir_all(it.script.parent().expect("a parent")).expect("the folder is removed");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Failed { .. }
        ));
        assert!(!it.is_saving());

        // And a document with nowhere to go at all.
        let untitled = crate::api::doc::doc_new();
        assert!(matches!(
            block_on(doc_save(untitled)),
            SaveOutcome::Failed {
                failure: SaveFailure::NoPath,
                ..
            }
        ));
        let saving = actor().run(move |state| {
            state
                .session(untitled.id)
                .is_some_and(|session| session.is_saving())
        });
        assert!(!saving);
        actor().run(move |state| state.close(untitled.id));
    }

    /// The same check-then-act the audit found beside F5. Both callers of
    /// `open_source` read the file off the actor first, so both can arrive here
    /// having been told the path was free; the second must still get the first
    /// one's handle.
    #[test]
    fn opening_one_path_twice_over_is_one_document() {
        let it = Fixture::open("one-document");

        // Exactly what two concurrent `library_open` calls do once both have
        // passed the check and read the file.
        let again = open_source(it.script.clone(), SCRIPT.to_owned(), false);
        assert_eq!(
            again.id, it.handle.id,
            "a second open of one path must not make a second document"
        );

        let opens: Vec<u64> = thread::scope(|scope| {
            let racers: Vec<_> = (0..8)
                .map(|_| {
                    let path = it.script.to_string_lossy().into_owned();
                    scope.spawn(move || block_on(library_open(path)).expect("it opens").id)
                })
                .collect();
            racers
                .into_iter()
                .map(|racer| racer.join().unwrap())
                .collect()
        });
        assert!(
            opens.iter().all(|id| *id == it.handle.id),
            "eight concurrent opens produced more than one document: {opens:?}"
        );
    }

    // -----------------------------------------------------------------------
    // Phase 4B — the app's own save is not somebody else's edit
    // -----------------------------------------------------------------------

    /// F4, in the shape the audit describes it: the interval autosave fires
    /// mid-typing by design, so the writer types between our rename and the
    /// event about it, and the check then finds the document dirty and
    /// different. Before the repair that was the full "Something else has
    /// written to this file" modal, about our own autosave.
    #[test]
    fn a_save_is_not_reported_as_somebody_elses_write() {
        let it = Fixture::open("own-echo");
        it.types("One. ");
        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Saved { .. }
        ));

        // The keystroke that used to turn the echo into a modal.
        it.types("Two. ");
        let typed = it.in_memory();
        assert!(
            !it.would_be_reported(),
            "the event caused by our own save reached Dart"
        );

        // And the backstop still says what it always said — dirty here,
        // different there — which is exactly why suppression had to happen
        // before it rather than inside it.
        assert_eq!(block_on(doc_external_change(it.handle)), Some((true, true)));
        assert_eq!(it.in_memory(), typed, "nothing typed was disturbed");
    }

    /// The repair is worth nothing if it eats a real one. A write by another
    /// program straight after ours must still be reported.
    #[test]
    fn an_external_write_straight_after_our_save_is_still_reported() {
        let it = Fixture::open("own-then-theirs");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert!(!it.would_be_reported());

        atomic::save_atomically(&it.script, "Somebody else wrote this.\n")
            .expect("their save works");
        assert!(
            it.would_be_reported(),
            "a real external change was swallowed as our own"
        );
        assert!(
            it.own_writes().is_empty(),
            "and the record it contradicted was dropped rather than asked again"
        );
        assert_eq!(
            block_on(doc_external_change(it.handle)),
            Some((false, true))
        );
    }

    // -----------------------------------------------------------------------
    // Phase 4C — external-change disk work never occupies the actor
    // -----------------------------------------------------------------------

    #[test]
    fn a_slow_external_change_read_does_not_block_an_edit_and_revalidates() {
        let it = Fixture::open("external-slow");
        let gate = Gate::hold_external_change_read(&it.script);
        let handle = it.handle;
        let checking = thread::spawn(move || block_on(doc_external_change(handle)));
        gate.wait();

        let block = doc_blocks(it.handle, 0, 1)[0].id;
        let handle = it.handle;
        let (done, finished) = mpsc::channel();
        let editing = thread::spawn(move || {
            let outcome = doc_apply(
                handle,
                EditCommand::ReplaceText {
                    block,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "Still typing. ".to_owned(),
                },
                None,
            );
            done.send(()).expect("the test is waiting for the edit");
            outcome
        });

        let edited_while_reading = finished.recv_timeout(PATIENCE).is_ok();
        gate.release();
        let result = checking.join().expect("the check thread finished");
        let _ = editing.join().expect("the edit thread finished");

        assert!(
            edited_while_reading,
            "the disk read held the actor and blocked a queued edit"
        );
        assert_eq!(
            result,
            Some((true, true)),
            "the pre-edit answer must be discarded and recomputed"
        );
    }

    #[test]
    fn external_change_keeps_clean_dirty_and_matching_content_semantics() {
        let it = Fixture::open("external-semantics");
        assert_eq!(
            block_on(doc_external_change(it.handle)),
            Some((false, false))
        );

        it.types("Mine. ");
        assert_eq!(block_on(doc_external_change(it.handle)), Some((true, true)));

        fs::write(&it.script, it.in_memory()).expect("the external write lands");
        assert_eq!(
            block_on(doc_external_change(it.handle)),
            Some((true, false)),
            "comparison remains against the current in-memory serialization"
        );
    }

    #[test]
    fn external_change_auto_reload_refuses_an_edit_after_the_check() {
        let it = Fixture::open("external-reload-race");
        fs::write(&it.script, "Somebody else wrote this.\n").expect("the external write lands");
        assert_eq!(
            block_on(doc_external_change(it.handle)),
            Some((false, true))
        );

        it.types("Newly typed. ");
        let current = it.in_memory();
        assert!(
            !block_on(doc_reload(it.handle, true)),
            "automatic reload must refuse a document that became dirty"
        );
        assert_eq!(it.in_memory(), current, "the new edit must survive");
    }

    #[test]
    fn external_change_check_holds_a_save_until_comparison_finishes() {
        let it = Fixture::open("external-check-save");
        it.types("Unsaved. ");
        let gate = Gate::hold_external_change_read(&it.script);
        let handle = it.handle;
        let checking = thread::spawn(move || block_on(doc_external_change(handle)));
        gate.wait();

        let saving = Saving::explicit(it.handle);
        let overtook = saving.overtook();
        gate.release();

        assert!(
            !overtook,
            "save wrote while external comparison was pending"
        );
        assert_eq!(
            checking.join().expect("the check thread finished"),
            Some((true, true))
        );
        assert!(matches!(saving.outcome(), SaveOutcome::Saved { .. }));
    }

    #[test]
    fn external_change_reload_waits_for_an_in_flight_save() {
        let it = Fixture::open("external-reload-save");
        let gate = Gate::hold_the_first_write(&it.script);
        it.types("Saving. ");
        let saving = Saving::explicit(it.handle);
        gate.wait();

        let handle = it.handle;
        let (done, finished) = mpsc::channel();
        let reloading = thread::spawn(move || {
            let outcome = block_on(doc_reload(handle, false));
            done.send(()).expect("the test is waiting for the reload");
            outcome
        });
        let overtook = finished.recv_timeout(LONG_ENOUGH_TO_OVERTAKE).is_ok();

        gate.release();
        assert!(matches!(saving.outcome(), SaveOutcome::Saved { .. }));
        assert!(reloading.join().expect("the reload thread finished"));
        assert!(!overtook, "reload overtook the save already at the disk");
        assert_eq!(it.in_memory(), it.on_disk());
        assert!(!it.dirty());
    }

    #[test]
    fn missing_and_non_utf8_files_refuse_external_change_comparison() {
        let missing = Fixture::open("external-missing");
        fs::remove_file(&missing.script).expect("the script is removed");
        assert_eq!(block_on(doc_external_change(missing.handle)), None);
        drop(missing);

        let invalid = Fixture::open("external-non-utf8");
        fs::write(&invalid.script, [0xff, 0xfe]).expect("invalid UTF-8 is written");
        assert_eq!(block_on(doc_external_change(invalid.handle)), None);
        drop(invalid);

        let unreadable = Fixture::open("external-unreadable");
        fs::remove_file(&unreadable.script).expect("the script is removed");
        fs::create_dir(&unreadable.script).expect("a directory replaces the file");
        assert_eq!(block_on(doc_external_change(unreadable.handle)), None);
    }

    /// The window ADR 0024's sequence left open, and the reason the bracket is
    /// taken before the write rather than recorded after it: the event can be
    /// delivered while the rename is still returning, long before an actor round
    /// trip could record anything.
    #[test]
    fn a_save_still_at_the_disk_already_suppresses_its_own_event() {
        let it = Fixture::open("own-in-flight");
        let gate = Gate::hold_the_first_write(&it.script);

        it.types("Being written. ");
        let saving = Saving::explicit(it.handle);
        gate.wait();
        assert!(
            !it.would_be_reported(),
            "an event arriving mid-write would have been reported as external"
        );

        gate.release();
        assert!(matches!(saving.outcome(), SaveOutcome::Saved { .. }));
        assert!(!it.would_be_reported());
    }

    /// A write that failed wrote nothing, so it has no echo to suppress — and a
    /// record left in flight would swallow the next real event about the file.
    #[test]
    fn a_failed_save_leaves_nothing_suppressed() {
        let it = Fixture::open("own-failed");
        it.types("Doomed. ");
        let read_only = fs::Permissions::from_mode(0o555);
        fs::set_permissions(&it.root, read_only).expect("the folder is made read-only");

        let outcome = block_on(doc_save(it.handle));
        fs::set_permissions(&it.root, fs::Permissions::from_mode(0o755))
            .expect("the folder is writable again");
        assert!(matches!(outcome, SaveOutcome::Failed { .. }));
        assert!(it.would_be_reported());
        assert!(it.own_writes().is_empty());
    }

    /// Save As leaves one path and takes another. The record follows the file
    /// that was written, and the one left behind is dropped with its watch —
    /// otherwise a script the writer went back to editing elsewhere would have
    /// its next real change swallowed.
    #[test]
    fn save_as_suppresses_the_new_path_and_forgets_the_old_one() {
        let it = Fixture::open("own-save-as");
        let elsewhere = it.root.join("elsewhere.fountain");
        it.types("Moving. ");
        let outcome = block_on(doc_save_as(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
        ));
        assert!(matches!(outcome, SaveOutcome::Saved { .. }));

        let own = it.own_writes();
        assert!(own.is_echo(&elsewhere), "the file we just wrote is ours");
        assert!(
            !own.is_echo(&it.script),
            "the path the session left is nobody's to suppress"
        );
        assert_eq!(own.len(), 1);
    }

    /// Closing a script clears what it wrote. This is the third way a record
    /// goes — the other two being the next write to the same path and the first
    /// event that contradicts it — and together they are why nothing here needs
    /// a timer to expire.
    #[test]
    fn closing_a_script_forgets_what_we_wrote_there() {
        let it = Fixture::open("own-close");
        it.types("Once. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        let own = it.own_writes();
        assert_eq!(own.len(), 1);

        let handle = it.handle;
        actor().run(move |state| state.close(handle.id));
        assert!(own.is_empty());
    }

    // -----------------------------------------------------------------------
    // Phase 7: an export is a copy, and Save As is a move
    //
    // F9: the two used to be one function. These tests are written in pairs on
    // purpose — the same question asked of `doc_save_as` and of
    // `doc_export_fountain` — because what makes an export correct is not what
    // it writes but everything it leaves alone (ADR 0029).
    // -----------------------------------------------------------------------

    fn exported(outcome: &SaveOutcome) -> &str {
        match outcome {
            SaveOutcome::Saved { path, .. } => path,
            other => panic!("expected an export, got {other:?}"),
        }
    }

    fn failure_of_outcome(outcome: &SaveOutcome) -> SaveFailure {
        match outcome {
            SaveOutcome::Failed { failure, .. } => *failure,
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    /// Save As moves the session: the path it answers to afterwards is the new
    /// file, and the old one is left as it was.
    #[test]
    fn save_as_changes_the_active_path() {
        let it = Fixture::open("save-as-path");
        let elsewhere = it.root.join("moved.fountain");
        it.types("Moving. ");
        let moved = it.in_memory();

        let outcome = block_on(doc_save_as(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
        ));

        assert_eq!(exported(&outcome), elsewhere.to_string_lossy());
        assert_eq!(doc_path(it.handle).as_deref(), elsewhere.to_str());
        assert_eq!(fs::read_to_string(&elsewhere).unwrap(), moved);
        assert_eq!(it.on_disk(), SCRIPT, "the file left behind is untouched");
        assert!(!it.dirty(), "a Save As saved this document");
    }

    /// …and takes the journal, the library entry and the watch with it. The
    /// own-writes half is `save_as_suppresses_the_new_path_and_forgets_the_old_one`
    /// above; this is the rest of the binding.
    #[test]
    fn save_as_rebinds_the_journal_and_the_library_entry() {
        let it = Fixture::open("save-as-binding");
        let elsewhere = it.root.join("rebound.fountain");
        it.types("Rebinding. ");
        block_on(doc_save_as(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
        ));

        assert_eq!(
            it.journal_describes().as_deref(),
            Some(elsewhere.as_path()),
            "the journal now covers the file the session moved to"
        );
        let id = journal::script_id(&elsewhere);
        assert!(
            it.library_has(&id),
            "the library learned the script's new identity"
        );
        assert!(it.own_writes().is_echo(&elsewhere));
    }

    /// The bytes an export writes are the document as it stands, exactly as a
    /// save would have written them.
    #[test]
    fn an_export_writes_the_expected_bytes() {
        let it = Fixture::open("export-bytes");
        it.types("A copy of this. ");
        let copy = it.root.join("copy.fountain");

        let outcome = block_on(doc_export_fountain(
            it.handle,
            copy.to_string_lossy().into_owned(),
            false,
        ));

        assert_eq!(exported(&outcome), copy.to_string_lossy());
        assert_eq!(fs::read_to_string(&copy).unwrap(), it.in_memory());
        assert_eq!(bytes_of(&outcome) as usize, it.in_memory().len());
    }

    /// F9 itself: the session goes on being the session. Path, journal, dirty
    /// flag, library identity — an export moves none of them, which is the whole
    /// difference between it and the two tests above.
    #[test]
    fn an_export_leaves_the_session_exactly_where_it_was() {
        let it = Fixture::open("export-session");
        it.types("Still editing. ");
        let before = it.in_memory();
        let journalled = it.journalled();
        let id = journal::script_id(&it.script);
        let copy = it.root.join("copy.fountain");

        block_on(doc_export_fountain(
            it.handle,
            copy.to_string_lossy().into_owned(),
            false,
        ));

        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
        assert!(it.dirty(), "the copy is not where this script lives");
        assert_eq!(it.in_memory(), before);
        assert_eq!(it.on_disk(), SCRIPT, "the script's own file is untouched");
        assert_eq!(
            it.journal_describes().as_deref(),
            Some(it.script.as_path()),
            "the journal still covers the file the session is bound to"
        );
        assert!(
            it.journal_agrees_with_the_file(),
            "an export must not re-base the journal"
        );
        assert_eq!(it.journalled(), journalled);
        assert_eq!(it.recovers_to(), before, "the crash journal still recovers");
        assert!(it.library_has(&id), "the library entry did not move");
        assert!(!it.is_saving(), "an export arms nothing");
        assert!(
            it.own_writes().is_empty(),
            "the copy is not a file this session watches"
        );
    }

    /// An export never quietly replaces a file. The refusal is the core's, not
    /// the dialog's, so no Phase 7 chooser can skip it (ADR 0029).
    #[test]
    fn an_export_refuses_to_overwrite_until_it_is_told_to() {
        let it = Fixture::open("export-overwrite");
        it.types("New words. ");
        let occupied = it.root.join("occupied.fountain");
        fs::write(&occupied, "Somebody else's script.\n").expect("the file is written");

        let refused = block_on(doc_export_fountain(
            it.handle,
            occupied.to_string_lossy().into_owned(),
            false,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::AlreadyExists);
        assert_eq!(
            fs::read_to_string(&occupied).unwrap(),
            "Somebody else's script.\n",
            "a refused export writes nothing"
        );

        let confirmed = block_on(doc_export_fountain(
            it.handle,
            occupied.to_string_lossy().into_owned(),
            true,
        ));
        assert!(matches!(confirmed, SaveOutcome::Saved { .. }));
        assert_eq!(fs::read_to_string(&occupied).unwrap(), it.in_memory());
    }

    /// A script this application has open is never a destination, however the
    /// path is spelled and however firmly the caller insists. Writing one from
    /// outside its session would leave its journal describing bytes the file no
    /// longer has, and a crash would then recover onto the wrong file.
    #[test]
    fn an_export_never_writes_a_script_that_is_open() {
        let it = Fixture::open("export-open");
        let other = it.beside("also-open");
        it.types("Mine. ");

        for (destination, description) in [
            (it.script.clone(), "its own file"),
            (other.script.clone(), "another open script"),
        ] {
            let refused = block_on(doc_export_fountain(
                it.handle,
                destination.to_string_lossy().into_owned(),
                true,
            ));
            assert_eq!(
                failure_of_outcome(&refused),
                SaveFailure::ScriptIsOpen,
                "exporting over {description} must be refused"
            );
        }
        assert_eq!(it.on_disk(), SCRIPT);
        assert_eq!(other.on_disk(), SCRIPT);

        // The same file, spelled through a symlinked directory. A comparison of
        // the paths as written would let this one through.
        let linked = it.root.join("link");
        std::os::unix::fs::symlink(&it.root, &linked).expect("the symlink is made");
        let sideways = linked.join(
            other
                .script
                .file_name()
                .expect("the sibling has a file name"),
        );
        let refused = block_on(doc_export_fountain(
            it.handle,
            sideways.to_string_lossy().into_owned(),
            true,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::ScriptIsOpen);
        assert_eq!(other.on_disk(), SCRIPT);
        assert_eq!(other.in_memory(), SCRIPT);
    }

    /// A failed export is a failed write and nothing else: there is no state it
    /// could have got halfway through, and the test says so rather than trusting
    /// the argument.
    #[test]
    fn a_failed_export_changes_nothing() {
        let it = Fixture::open("export-failed");
        it.types("Unwritten. ");
        let before = it.in_memory();
        let journalled = it.journalled();
        let nowhere = it.root.join("no-such-folder").join("copy.fountain");

        let outcome = block_on(doc_export_fountain(
            it.handle,
            nowhere.to_string_lossy().into_owned(),
            false,
        ));

        assert_eq!(failure_of_outcome(&outcome), SaveFailure::NoSuchDirectory);
        assert!(!nowhere.exists());
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
        assert_eq!(it.in_memory(), before);
        assert!(it.dirty());
        assert_eq!(it.journalled(), journalled);
        assert!(it.journal_agrees_with_the_file());
        assert!(!it.is_saving(), "a refused export leaves nothing armed");
        assert!(it.own_writes().is_empty());
    }

    /// The two answers that are questions rather than faults, given without a
    /// document to hand: the UI has to tell them apart before it can ask
    /// anything.
    #[test]
    fn an_export_with_nowhere_to_go_says_so() {
        let it = Fixture::open("export-nowhere");
        assert_eq!(
            failure_of_outcome(&block_on(doc_export_fountain(
                it.handle,
                String::new(),
                false
            ))),
            SaveFailure::NoPath
        );
        assert_eq!(
            failure_of_outcome(&block_on(doc_export_fountain(
                DocumentHandle { id: u64::MAX },
                it.root.join("copy.fountain").to_string_lossy().into_owned(),
                false,
            ))),
            SaveFailure::NoSuchDocument
        );
    }
}
