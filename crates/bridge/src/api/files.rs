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

use std::path::{Path, PathBuf};

use flutter_rust_bridge::frb;

use slugline_document as model;
use slugline_storage::backup::{self, Retention};
use slugline_storage::journal::{self, Journal};
use slugline_storage::library::{Library, ScriptEntry};
use slugline_storage::watch::FileWatcher;
use slugline_storage::{atomic, paths::Paths, prefs, Preferences as CorePreferences};

use crate::actor::actor;
use crate::api::doc::DocumentHandle;
use crate::api::events::{emit, CoreEvent};
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
    /// Zero until Phase 6's `layout` crate can count pages.
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
    let watcher = FileWatcher::new(|path| {
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

/// Save As, and §6's `doc_export_fountain` — the same operation.
///
/// The document follows the new path: after Save As, this *is* the file, and
/// the journal, the backups and the library entry all move with it.
pub async fn doc_save_as(handle: DocumentHandle, path: String) -> SaveOutcome {
    write_document(handle, Some(PathBuf::from(path)), true).await
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
async fn write_document(
    handle: DocumentHandle,
    save_as: Option<PathBuf>,
    with_backup: bool,
) -> SaveOutcome {
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
            let session = state.session(handle.id)?;
            let path = save_as.or_else(|| session.path().map(Path::to_path_buf));
            Some(Plan {
                path,
                text: session.document().serialise(),
                revision: session.document().revision(),
                dirty: session.document().is_dirty(),
                storage: storage_paths,
            })
        }
    });

    let Some(plan) = plan else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "no document with that handle",
        );
    };
    let Some(path) = plan.path else {
        return SaveOutcome::Failed {
            failure: SaveFailure::NoPath,
            path: String::new(),
            message: "this script has never been saved".to_owned(),
        };
    };
    // Save As always writes, even to a document nobody has edited: the user
    // asked for a file at a new path and a clean document is still a file.
    if !plan.dirty && save_as.is_none() {
        return SaveOutcome::Unchanged;
    }

    // Step two, off the actor thread: the disk (§2.3).
    if let Err(error) = atomic::save_atomically(&path, &plan.text) {
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }

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

    // Step three, back on the actor thread: record that it happened.
    let bytes = plan.text.len().min(u32::MAX as usize) as u32;
    actor().run({
        let path = path.clone();
        let text = plan.text;
        move |state| {
            let Some(session) = state.session_mut(handle.id) else {
                return;
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
            // The journal starts again from the bytes now on disk. Everything
            // before this point is in the file.
            if let Some(session) = state.session_mut(handle.id) {
                if let Some(journal) = session.journal_mut() {
                    let _ = journal.checkpoint(&path, &text);
                }
            }
            if let Some(storage) = state.storage_mut() {
                storage.library.refresh();
            }
            save_library(state);
        }
    });

    emit(CoreEvent::SaveStateChanged {
        handle: handle.id,
        dirty: false,
    });
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes,
        backup,
    }
}

struct Plan {
    path: Option<PathBuf>,
    text: String,
    revision: u64,
    dirty: bool,
    storage: Option<(PathBuf, Retention)>,
}

// ---------------------------------------------------------------------------
// External modification
// ---------------------------------------------------------------------------

/// What the file on disk says now, next to what the document says.
///
/// Dart calls this when a [`CoreEvent::FileChangedOnDisk`] names a path it has
/// open. §Phase 4: reload silently when the document is unmodified, prompt when
/// it is not — and the two facts that decision needs are exactly the two here.
#[frb(sync)]
pub fn doc_external_change(handle: DocumentHandle) -> Option<(bool, bool)> {
    actor().run(move |state| {
        let session = state.session(handle.id)?;
        let path = session.path()?;
        let on_disk = std::fs::read_to_string(path).ok()?;
        Some((
            session.document().is_dirty(),
            on_disk != session.document().serialise(),
        ))
    })
}

/// "Take Theirs": throws away what is in memory and reads the file again.
///
/// The undo history goes with it. It has to: the transactions in it invert edits
/// against a document that no longer exists, and applying one would produce text
/// that was never anywhere.
pub async fn doc_reload(handle: DocumentHandle) -> bool {
    let path = actor().run(move |state| {
        state
            .session(handle.id)
            .and_then(|session| session.path())
            .map(Path::to_path_buf)
    });
    let Some(path) = path else { return false };
    let Ok(source) = std::fs::read_to_string(&path) else {
        return false;
    };

    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return false;
        };
        let document = model::Document::parse(&source);
        *session.document_mut() = if document.blocks().is_empty() {
            model::Document::blank()
        } else {
            document
        };
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
        let session = state.session(handle.id)?;
        Some((
            session.path()?.to_path_buf(),
            session.document().serialise(),
            root,
        ))
    });
    let Some((path, current, root)) = plan else {
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

    if let Err(error) = atomic::save_atomically(&path, &contents) {
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }

    let bytes = contents.len().min(u32::MAX as usize) as u32;
    actor().run({
        let contents = contents.clone();
        move |state| {
            let Some(session) = state.session_mut(handle.id) else {
                return;
            };
            let document = model::Document::parse(&contents);
            *session.document_mut() = if document.blocks().is_empty() {
                model::Document::blank()
            } else {
                document
            };
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
pub async fn recovery_accept(journal_path: String) -> Option<DocumentHandle> {
    let path = PathBuf::from(&journal_path);
    let recovery = journal::read(&path).ok()?;
    let source = journal::verify(&recovery.header).ok()?;
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
    for patch in &recovery.patches {
        // A patch that does not fit stops the replay. What is already applied is
        // still offered — those edits did happen — and the rest is not guessed
        // at.
        if document.replay(patch).is_err() {
            break;
        }
    }

    let script = recovery.header.script.clone();
    let handle = actor().run(move |state| {
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
    });

    // The journal has been consumed. A fresh one starts from the document as it
    // now stands, so that a second crash during recovery loses nothing either.
    let _ = journal::discard_at(&path);
    let recovered = actor().run(move |state| {
        let text = state.session(handle)?.document().serialise();
        restart_journal(state, handle, &text);
        Some(())
    });
    recovered?;
    Some(DocumentHandle { id: handle })
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
