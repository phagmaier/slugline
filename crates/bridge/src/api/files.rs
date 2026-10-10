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
//!    permission-denied each handled with a distinct message and a copy export
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
use std::sync::{Arc, Mutex, PoisonError};

use flutter_rust_bridge::frb;

use slugline_document as model;
use slugline_fdx as fdx;
use slugline_layout::PageConfig;
use slugline_render_pdf as render_pdf;
use slugline_storage::backup::{self, Retention};
use slugline_storage::journal::{self, Journal};
use slugline_storage::library::{Library, ScriptEntry};
use slugline_storage::watch::{DiskState, DiskVerdict, FileWatcher, OwnWrites};
use slugline_storage::{atomic, paths::Paths, prefs, Preferences as CorePreferences};

use crate::actor::actor;
use crate::api::doc::DocumentHandle;
use crate::api::events::{emit, CoreEvent};
use crate::api::{layout, spell};
use crate::state::{AppState, ProjectCandidate, ProjectContext, Session, Storage};
use slugline_storage::project::{self, Metadata, Origin, Project};

static PROJECT_OPERATIONS: Mutex<()> = Mutex::new(());
static MIGRATIONS: Mutex<()> = Mutex::new(());

const AUTOSAVE_BACKUP_INTERVAL_MILLIS: u64 = 10 * 60 * 1_000;

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

/// Why a write did not happen. One variant per message §Phase 4 asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveFailure {
    /// The file is read-only. Offer Export a copy.
    ReadOnly,
    /// The directory will not take the file. Offer Export a copy.
    PermissionDenied,
    /// The filesystem is full, or the user is over quota. Offer Export a copy.
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
    /// The file holds bytes this session has never seen: another program wrote
    /// it, and replacing it now would destroy that edit without anybody having
    /// decided to.
    ///
    /// A question rather than a fault, like [`SaveFailure::NoPath`] and
    /// [`SaveFailure::AlreadyExists`] — and the question is §Phase 4's
    /// external-modification prompt, which is already on its way when this comes
    /// back: the same `FileChangedOnDisk` the watcher would have pushed is
    /// emitted with it. "Keep mine" answers it by calling
    /// [`doc_accept_disk_state`], and the next save writes.
    ChangedOnDisk,
    LibraryDestination,
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

/// FDX conversion opens an isolated unsaved session, never the source file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FdxImportOutcome {
    Imported {
        handle: DocumentHandle,
        warnings: Vec<String>,
    },
    Failed {
        message: String,
    },
}

/// Warnings require approval for the exact snapshot that will be exported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FdxExportOutcome {
    NeedsConfirmation {
        warnings: Vec<String>,
        revision: u64,
    },
    Finished {
        outcome: SaveOutcome,
        warnings: Vec<String>,
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
    pub project_id: String,
    pub archived: bool,
    pub problem: Option<String>,
    pub migration_status: Option<String>,
}

/// One rolling backup (§Phase 4's "Restore previous version" list).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackupView {
    pub path: String,
    pub written_millis: u64,
    pub bytes: u64,
}

/// Reading a previous version never opens or changes a document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BackupReadOutcome {
    Read {
        source: String,
        has_bom: Option<bool>,
    },
    Failed {
        message: String,
    },
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
    /// `message` names the reason. The correct advice is Export a copy somewhere the
    /// state directory's problem does not apply, or relaunch — the offer will
    /// still be there.
    Degraded {
        handle: DocumentHandle,
        message: String,
    },
    /// Nothing was opened and nothing was removed. The offer can be made again.
    Failed { message: String },
}

/// §6's preferences, through Phase 10.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreferencesView {
    pub autosave_enabled: bool,
    pub autocomplete_enabled: bool,
    pub navigator_visible: bool,
    pub spell_enabled: bool,
    pub spell_language: Option<String>,
    pub appearance: String,
    pub editor_text_size: u16,
    pub default_paper: String,
    pub scene_numbers: String,
    pub bold_scene_headings: bool,
    pub number_first_page: bool,
    pub pdf_font_path: Option<String>,
    pub distraction_free: bool,
    pub page_view: bool,
    pub autosave_idle_ms: u64,
    pub autosave_interval_ms: u64,
    pub backup_dir: Option<String>,
    pub library_dir: Option<String>,
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

    let mut prefs = load_preferences(&paths);
    // Retain compatibility input before a v2 cache can replace v1. Never rewrite originals.
    let legacy_path = paths.legacy_library_index();
    if Library::retain_legacy(&paths.library_index(), &legacy_path).is_err() {
        return false;
    }
    let legacy = Library::legacy(&legacy_path);
    let selected_root = prefs
        .library_dir
        .clone()
        .unwrap_or_else(|| paths.default_library().to_path_buf());
    let library_root = selected_root.canonicalize().unwrap_or(selected_root);
    let mut library = Library::load(&paths.library_index());
    let library_error = if !library_root.exists() && prefs.library_dir.is_none() {
        library = Library::default();
        None
    } else {
        library.rebuild(&library_root).err().map(|e| e.to_string())
    };
    // Discovery, dictionary parsing and personal-dictionary I/O all happen on
    // this async worker before the actor sees the resulting immutable state.
    let spelling = spell::initialise(&paths, &prefs);
    prefs.spell_language = spelling.language.clone();

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
        *state.spelling_mut() = spelling;
        state.set_storage(Storage {
            paths,
            prefs,
            library,
            library_root,
            library_error,
            legacy,
            watcher,
            own_writes,
            page_count_jobs: Default::default(),
            next_page_count_job: 0,
        });
    });
    true
}

fn load_preferences(paths: &Paths) -> CorePreferences {
    let current = paths.preferences();
    if current.exists() {
        return CorePreferences::load(&current);
    }
    let legacy_path = paths.legacy_preferences();
    let legacy = CorePreferences::load(&legacy_path);
    if legacy_path.exists() {
        // Phase 10 shortened the public name to `prefs.json`. Keep the old
        // file as a harmless fallback and atomically write the new one.
        let _ = legacy.save(&current);
    }
    legacy
}

/// Ends the session cleanly: every journal is discarded and the library index is
/// written.
///
/// Dart calls this from the window's close handler. If it never runs — because
/// the process was killed — the journals stay on disk and the next startup finds
/// them, which is exactly the behaviour they exist for.
///
/// A script still open here is one the writer quit out of, not one they put
/// away, so it stays marked open and [`session_restore`] gives it back to the
/// next launch. Dart must therefore call this *before* it closes that script.
pub async fn shutdown() {
    actor().run(|state| {
        for handle in state.handles() {
            state.park(handle);
        }
        save_library(state);
    });
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

/// §6's `library_list`.
pub async fn library_list() -> Vec<ScriptView> {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some((root, mut library)) = actor().run(|state| {
        state
            .storage()
            .map(|s| (s.library_root.clone(), s.library.clone()))
    }) else {
        return Vec::new();
    };
    let error = if !root.exists() && library.entries().is_empty() {
        let configured = actor().run(|state| {
            state
                .storage()
                .is_some_and(|s| s.prefs.library_dir.is_some())
        });
        configured.then(|| format!("Library unavailable: {}", root.display()))
    } else {
        library.rebuild(&root).err().map(|e| e.to_string())
    };
    actor().run(move |state| {
        let Some(storage) = state.storage_mut() else {
            return Vec::new();
        };
        if storage.library_root != root {
            return Vec::new();
        }
        library.merge_cached_state(&storage.library);
        storage.library_error = error;
        storage.library = library;
        storage.library.entries().iter().map(script_view).collect()
    })
}

#[derive(Debug, Clone)]
pub struct LibraryStatus {
    pub path: String,
    pub error: Option<String>,
    pub legacy_count: u32,
}

#[frb(sync)]
pub fn library_status() -> LibraryStatus {
    actor().run(|state| {
        state
            .storage()
            .map(|s| LibraryStatus {
                path: s.library_root.to_string_lossy().into_owned(),
                error: s.library_error.clone(),
                legacy_count: s.legacy.len() as u32,
            })
            .unwrap_or(LibraryStatus {
                path: String::new(),
                error: Some("Storage unavailable".into()),
                legacy_count: 0,
            })
    })
}

fn active_root(create_default: bool) -> Result<PathBuf, atomic::SaveError> {
    let Some((root, lazy)) = actor().run(|state| {
        state
            .storage()
            .map(|s| (s.library_root.clone(), s.prefs.library_dir.is_none()))
    }) else {
        return Err(atomic::SaveError::Io {
            path: PathBuf::new(),
            message: "Storage unavailable".into(),
        });
    };
    project::root(&root, create_default && lazy)
}

/// Public open only accepts a validated project in the active root.
pub async fn library_open(path: String) -> Option<DocumentHandle> {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let root = active_root(false).ok()?;
    let project = project::validate_save(&root, Path::new(&path)).ok()?;
    let path = project.script();
    if let Some(existing) = actor().run({
        let path = path.clone();
        move |state| state.handle_for(&path)
    }) {
        return Some(DocumentHandle { id: existing });
    }
    // Never bypass an undecided recovery, including aliases.
    if recovery_for(&path) {
        return None;
    }
    let source = std::fs::read_to_string(&path).ok()?;
    let retention = actor().run(|state| state.storage().map(|s| s.prefs.retention()))?;
    let backup = backup::write_if_changed(&root, &path, &source, retention, 0)
        .ok()
        .flatten();
    actor().run({
        let project = project.clone();
        move |state| {
            if let Some(s) = state.storage_mut() {
                s.library.cache_project(&project);
            }
        }
    });
    let handle = open_source(path, source, false);
    actor().run(move |state| {
        if let Some(s) = state.session_mut(handle.id) {
            s.project = Some(ProjectContext {
                root,
                id: project.metadata.id,
            });
        }
    });
    if let Some(written) = backup {
        emit(CoreEvent::BackupWritten {
            handle: handle.id,
            path: written.backup.path.to_string_lossy().into_owned(),
        });
    }
    Some(handle)
}

fn recovery_for(path: &Path) -> bool {
    let directory = actor().run(|state| state.storage().map(|s| s.paths.journal_dir()));
    directory.is_some_and(|dir| {
        journal::pending(&dir).iter().any(|p| {
            // A live owner is equally authoritative. Path IDs are canonical here.
            p.file_stem()
                .is_some_and(|name| name == journal::script_id(path).as_str())
                || journal::RecoveryGuard::try_open(p)
                    .ok()
                    .and_then(|g| g.read().ok())
                    .is_some_and(|r| same_file(&r.header.script, path))
        })
    })
}

/// Create inside the library. The argument is a display name, never a destination.
pub async fn library_create(path: String) -> Option<DocumentHandle> {
    let name = if path.trim().is_empty() {
        "Untitled".to_owned()
    } else {
        path
    };
    let metadata = Metadata::new(name.clone()).ok()?;
    let source = starter_source(Path::new(&name));
    let candidate = create_candidate(
        model::Document::parse(&source),
        ProjectCandidate {
            metadata,
            bytes: Some(source.into_bytes()),
            fdx: None,
            predecessor: None,
            published: None,
        },
    );
    match doc_commit_project(candidate).await {
        SaveOutcome::Saved { .. } => Some(candidate),
        outcome => {
            let message = match outcome {
                SaveOutcome::Failed { message, .. } => message,
                _ => "Project creation did not finish".into(),
            };
            actor().run(move |state| {
                if let Some(s) = state.storage_mut() {
                    s.library_error = Some(message);
                }
            });
            crate::api::doc::doc_close(candidate);
            None
        }
    }
}

fn starter_source(path: &Path) -> String {
    let title = path
        .file_stem()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("Untitled");
    format!("Title: {title}\nCredit: Written by\nAuthor:\n\nINT. LOCATION - DAY\n\n")
}

/// Rename display metadata only. Stable paths keep journal, history and row keys.
pub async fn library_rename(id: String, new_path: String) -> SaveOutcome {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some(path) = entry_path(&id) else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "No such project",
        );
    };
    let root = match active_root(false) {
        Ok(r) => r,
        Err(e) => return storage_failed(e),
    };
    let project = match project::resolve(&root, &path) {
        Ok(p) => p,
        Err(e) => return storage_failed(e),
    };
    if new_path.trim().is_empty() {
        return failed(SaveFailure::Io, &path, "The display name cannot be empty");
    }
    let mut metadata = project.metadata.clone();
    metadata.name = new_path;
    if let Err(e) = project::update(&project, &metadata) {
        return storage_failed(e);
    }
    let project = project::read(&project.directory).unwrap_or(project);
    actor().run(move |state| {
        if let Some(s) = state.storage_mut() {
            s.library.cache_project(&project);
        }
        save_library(state);
    });
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: 0,
        backup: None,
    }
}

fn entry_path(id: &str) -> Option<PathBuf> {
    let id = id.to_owned();
    actor().run(move |state| state.storage()?.library.get(&id).map(|e| e.path.clone()))
}

/// Capture unsaved active bytes, or closed saved bytes; never copy version/reference files.
pub async fn library_duplicate(id: String) -> Option<ScriptView> {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let path = entry_path(&id)?;
    let root = active_root(false).ok()?;
    let parent = project::scan(&root).ok()?.into_iter().find(|p| {
        p.script() == path
            && p.metadata.version == project::FORMAT
            && p.problem
                .as_deref()
                .is_none_or(|problem| problem.starts_with("duplicate project ID"))
    })?;
    let active = actor().run({
        let path = path.clone();
        move |state| {
            state
                .handle_for(&path)
                .and_then(|h| state.session(h))
                .map(|s| s.document().serialise().into_bytes())
        }
    });
    let bytes = active.or_else(|| std::fs::read(&path).ok())?;
    let mut metadata = Metadata::new(format!("{} copy", parent.metadata.name)).ok()?;
    metadata.pinned_entities = parent.metadata.pinned_entities;
    let project = project::create(&root, metadata, &bytes, None).ok()?;
    let retention = actor().run(|state| state.storage().map(|s| s.prefs.retention()))?;
    let _ = backup::write_if_changed(
        &root,
        &project.script(),
        std::str::from_utf8(&bytes).ok()?,
        retention,
        0,
    );
    actor().run(move |state| {
        let s = state.storage_mut()?;
        let id = s.library.cache_project(&project);
        let view = s.library.get(&id).map(script_view);
        save_library(state);
        view
    })
}

/// Compatibility name: removal is reversible archive; delete_file is ignored.
pub async fn library_remove(id: String, delete_file: bool) -> bool {
    let _ = delete_file;
    library_archive(id, true, None).await
}

pub async fn library_archive(
    id: String,
    archived: bool,
    resolved_handle: Option<DocumentHandle>,
) -> bool {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some(path) = entry_path(&id) else {
        return false;
    };
    // Resolve an active editor first; this core API cannot discard its session.
    if actor().run({
        let path = path.clone();
        move |state| {
            state
                .handle_for(&path)
                .is_some_and(|h| resolved_handle.map(|d| d.id) != Some(h))
        }
    }) {
        return false;
    }
    let Ok(root) = active_root(false) else {
        return false;
    };
    let Ok(project) = project::resolve(&root, &path) else {
        return false;
    };
    let mut metadata = project.metadata.clone();
    metadata.archived = archived;
    if project::update(&project, &metadata).is_err() {
        return false;
    }
    let project = project::read(&project.directory).unwrap_or(project);
    actor().run(move |state| {
        if let Some(s) = state.storage_mut() {
            s.library.cache_project(&project);
        }
        save_library(state);
    });
    true
}

pub async fn library_repair(id: String) -> bool {
    let Some(path) = entry_path(&id) else {
        return false;
    };
    let Ok(root) = active_root(false) else {
        return false;
    };
    let Ok(projects) = project::scan(&root) else {
        return false;
    };
    let Some(project) = projects.iter().find(|p| p.script() == path) else {
        return false;
    };
    if project
        .problem
        .as_deref()
        .is_none_or(|p| !p.starts_with("metadata needs repair"))
    {
        return false;
    }
    project::repair(project).is_ok()
}

/// Rescue readable bytes from damaged/future metadata without opening a mutable session.
pub async fn library_rescue(id: String, path: String, overwrite: bool) -> SaveOutcome {
    let Some(source) = entry_path(&id) else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(&path),
            "No such project",
        );
    };
    let path = PathBuf::from(path);
    if project::protected_destination(&path) {
        return failed(
            SaveFailure::LibraryDestination,
            &path,
            "Choose a destination outside managed projects",
        );
    }
    if actor().run({
        let path = path.clone();
        move |state| {
            state.handles().iter().any(|h| {
                state
                    .session(*h)
                    .and_then(Session::path)
                    .is_some_and(|p| same_file(p, &path))
            })
        }
    }) {
        return failed(
            SaveFailure::ScriptIsOpen,
            &path,
            "Destination is an open script",
        );
    }
    if path.exists() && !overwrite {
        return failed(
            SaveFailure::AlreadyExists,
            &path,
            "Destination already exists",
        );
    }
    let root = match active_root(false) {
        Ok(root) => root,
        Err(e) => return storage_failed(e),
    };
    if source.parent().and_then(Path::parent) != Some(root.as_path())
        || source.parent().is_none_or(|p| {
            std::fs::symlink_metadata(p).map_or(true, |m| !m.is_dir() || m.file_type().is_symlink())
        })
        || std::fs::symlink_metadata(&source).is_ok_and(|m| m.file_type().is_symlink())
    {
        return failed(
            SaveFailure::LibraryDestination,
            &source,
            "Child symlinks cannot be read as project contents",
        );
    }
    let bytes = match std::fs::read(&source) {
        Ok(b) => b,
        Err(e) => return failed(SaveFailure::Io, &source, &e.to_string()),
    };
    if let Err(e) = atomic::save_atomically(&path, &bytes) {
        return storage_failed(e);
    }
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: bytes.len() as u32,
        backup: None,
    }
}

fn storage_failed(error: atomic::SaveError) -> SaveOutcome {
    SaveOutcome::Failed {
        failure: failure_of(&error),
        path: error.path().to_string_lossy().into_owned(),
        message: error.to_string(),
    }
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

/// Writes down which scripts are open and where the writer is in each, so that
/// a process that dies comes back to that and not to whatever the index held
/// the last time something else wrote it.
///
/// Dart says when — once scrolling has settled, and when a script is put away.
/// There is no clock here to do it (ADR 0014), and [`doc_set_scroll`] runs for
/// every row scrolled past, which is far too often for a file write.
pub async fn session_park() {
    actor().run(save_library);
}

/// Records where the writer is in a script. In memory only: a quit writes it
/// with everything else, and [`session_park`] writes it for a crash.
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
///
/// ## The two refusals
///
/// Save As is a file chooser away from replacing a script the writer spent a
/// month on, exactly as an export is, so it answers the same two refusals for
/// the same two reasons — and answers them **here**, not in the dialog, so that
/// no chooser can be written that skips them:
///
/// * A destination that is already there comes back as
///   [`SaveFailure::AlreadyExists`] unless `overwrite` says otherwise. The one
///   exception is the session's own file: Save As onto where this script already
///   lives is a save, and asking the writer to confirm replacing themselves
///   would be a question with only one answer.
/// * A destination that is a **different** open script comes back as
///   [`SaveFailure::ScriptIsOpen`], and `overwrite` does not lift it. That
///   session's journal has the bytes now being replaced as its base; after such
///   a write a crash would recover onto a file that no longer matches.
///
/// Like the export's, the checks are a moment before the write rather than
/// atomic with it. That is the same race any file chooser has; what matters is
/// that the ordinary case cannot overwrite without having been asked.
pub async fn doc_save_as(handle: DocumentHandle, path: String, overwrite: bool) -> SaveOutcome {
    let _ = overwrite;
    let current = doc_path(handle);
    if current
        .as_deref()
        .is_some_and(|p| same_file(Path::new(p), Path::new(&path)))
    {
        return doc_save(handle).await;
    }
    failed(
        SaveFailure::LibraryDestination,
        Path::new(&path),
        "Scripts stay in the library. Use Export a copy.",
    )
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
    if project::protected_destination(&path) {
        return failed(SaveFailure::LibraryDestination, &path, "Export cannot replace managed project contents; choose a destination outside a project.");
    }
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

/// Import FDX as a new dirty Fountain document with its own crash journal.
///
/// Parsing precedes session creation. The caller may close an unadopted
/// candidate after reviewing warnings without disturbing its current editor.
pub async fn doc_import_fdx(path: String) -> FdxImportOutcome {
    if recovery_for(Path::new(&path)) {
        return FdxImportOutcome::Failed {
            message: "Resolve pending recovery before import".into(),
        };
    }
    let source = match std::fs::read(&path) {
        Ok(source) => source,
        Err(error) => {
            return FdxImportOutcome::Failed {
                message: format!("could not read {path}: {error}"),
            };
        }
    };
    let imported = match fdx::read(&source) {
        Ok(imported) => imported,
        Err(error) => {
            return FdxImportOutcome::Failed {
                message: format!("could not import {path}: {error}"),
            };
        }
    };
    let mut metadata = match Metadata::new(
        Path::new(&path)
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned(),
    ) {
        Ok(m) => m,
        Err(e) => {
            return FdxImportOutcome::Failed {
                message: e.to_string(),
            }
        }
    };
    metadata.origin = Some(Origin {
        path: PathBuf::from(&path)
            .canonicalize()
            .unwrap_or_else(|_| PathBuf::from(&path)),
        kind: "fdx".into(),
        legacy_id: None,
        history_complete: true,
    });
    actor().run(move |state| {
        let document = match model::Document::from_script(imported.script) {
            Ok(document) => document,
            Err(error) => {
                return FdxImportOutcome::Failed {
                    message: format!("could not import {path}: {error}"),
                };
            }
        };
        let mut snapshots = document.blocks().iter().enumerate().map(|(index, block)| {
            (
                index.min(u32::MAX as usize) as u32,
                model::BlockSnapshot {
                    id: block.id(),
                    kind: block.kind(),
                    text: block.text().to_owned(),
                    forced: block.forced(),
                    dual: block.dual(),
                },
            )
        });
        let first = snapshots.next().expect("an imported document has a body").1;
        let initial = model::Patch {
            changed: vec![first],
            inserted: snapshots.collect(),
            title_page: Some(document.title_page().clone()),
            ..model::Patch::default()
        };
        let handle = state.open(document);
        if let Some(session) = state.session_mut(handle) {
            session.candidate = Some(ProjectCandidate {
                metadata,
                bytes: None,
                fdx: Some(source),
                predecessor: None,
                published: None,
            });
        }
        restart_journal(state, handle, "", Restart::Fresh);
        if let Some(session) = state.session_mut(handle) {
            crate::api::doc::record_patch(session, initial);
        }
        FdxImportOutcome::Imported {
            handle: DocumentHandle { id: handle },
            warnings: imported.warnings,
        }
    })
}

/// Export an immutable FDX copy without rebinding or saving the native script.
///
/// A warning approval belongs to one revision. If the document changes while a
/// conversion dialog is open, the new snapshot must be approved independently.
pub async fn doc_export_fdx(
    handle: DocumentHandle,
    path: String,
    overwrite: bool,
    confirmed_revision: Option<u64>,
) -> FdxExportOutcome {
    let path = PathBuf::from(path);
    let finish = |outcome, warnings| FdxExportOutcome::Finished { outcome, warnings };
    if path.as_os_str().is_empty() {
        return finish(
            failed(SaveFailure::NoPath, &path, "no file was chosen"),
            Vec::new(),
        );
    }
    let Some((snapshot, revision, open_scripts)) = actor().run({
        let handle = handle.id;
        move |state| {
            let document = state.session(handle)?.document();
            let snapshot = document.serialisation_snapshot();
            let revision = document.revision();
            let open_scripts = state
                .handles()
                .into_iter()
                .filter_map(|open| state.session(open))
                .filter_map(Session::path)
                .map(Path::to_path_buf)
                .collect::<Vec<_>>();
            Some((snapshot, revision, open_scripts))
        }
    }) else {
        return finish(
            failed(
                SaveFailure::NoSuchDocument,
                &path,
                "no document with that handle",
            ),
            Vec::new(),
        );
    };
    if open_scripts.iter().any(|open| same_file(open, &path)) {
        return finish(
            failed(
                SaveFailure::ScriptIsOpen,
                &path,
                &format!(
                    "{} is open here; save that script rather than exporting over it",
                    path.display()
                ),
            ),
            Vec::new(),
        );
    }
    if project::protected_destination(&path) {
        return finish(failed(SaveFailure::LibraryDestination, &path, "Export cannot replace managed project contents; choose a destination outside a project."), Vec::new());
    }
    if !overwrite && path.exists() {
        return finish(
            failed(
                SaveFailure::AlreadyExists,
                &path,
                &format!("{} is already there", path.display()),
            ),
            Vec::new(),
        );
    }
    let exported = match fdx::write(snapshot.title_page(), snapshot.elements()) {
        Ok(exported) => exported,
        Err(error) => {
            return finish(
                failed(
                    SaveFailure::Io,
                    &path,
                    &format!("could not export FDX: {error}"),
                ),
                Vec::new(),
            );
        }
    };
    if !exported.warnings.is_empty() && confirmed_revision != Some(revision) {
        return FdxExportOutcome::NeedsConfirmation {
            warnings: exported.warnings,
            revision,
        };
    }
    let outcome = match atomic::save_atomically(&path, &exported.xml) {
        Ok(()) => SaveOutcome::Saved {
            path: path.to_string_lossy().into_owned(),
            bytes: exported.xml.len().min(u32::MAX as usize) as u32,
            backup: None,
        },
        Err(error) => SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        },
    };
    finish(outcome, exported.warnings)
}

/// §6's `export_pdf`. Paginates the document and writes a PDF (§Phase 7).
///
/// ## It is an export, so ADR 0029 applies unchanged
///
/// The session stays exactly where it is: no path is rebound, no journal moves,
/// the dirty flag is untouched, and nothing is armed. The two refusals are
/// [`doc_export_fountain`]'s two refusals, for its two reasons — a destination
/// that is already there is a question, and a destination that is a script open
/// here is refused outright because writing it from outside its own session
/// would leave that session's journal describing bytes the file no longer has.
/// A `.pdf` is very unlikely to be an open script; "unlikely" is not the
/// standard §1.2 sets for losing a writer's work.
///
/// ## Where the work happens
///
/// Off the actor, like every long job (§2.3), and in the order §2.3 asks for:
/// visit the actor for what is needed, let go, paginate and render, come back
/// only to write nothing. The pagination goes through [`layout::paginate`], so
/// it takes the session's own engine and its warm per-block cache (ADR 0022)
/// rather than starting cold, and an export straight after a save costs no
/// pagination at all because the save already did it.
///
/// A pagination that came back [stale](layout::PaginationOutcome::Stale) is
/// retried once. It means the writer typed while it ran; the second attempt is
/// against what they typed, and if they are still typing the export goes ahead
/// with the newer of the two rather than chasing them.
pub async fn doc_export_pdf(
    handle: DocumentHandle,
    setup: layout::PageSetup,
    path: String,
    overwrite: bool,
) -> SaveOutcome {
    let path = PathBuf::from(path);
    if path.as_os_str().is_empty() {
        return failed(SaveFailure::NoPath, &path, "no file was chosen");
    }

    let Some((info, open_scripts, pdf_font_path)) = actor().run({
        let handle = handle.id;
        move |state| {
            let session = state.session(handle)?;
            let title_page = session.document().title_page();
            let info = render_pdf::DocumentInfo {
                title: title_page
                    .get(&model::TitleField::Title)
                    .map(str::to_owned)
                    .unwrap_or_else(|| {
                        state
                            .storage()
                            .and_then(|s| {
                                session
                                    .path()
                                    .and_then(|p| s.library.get(&journal::script_id(p)))
                            })
                            .map(|e| e.title.clone())
                            .unwrap_or_else(|| script_name(session.path()))
                    }),
                author: title_page
                    .get(&model::TitleField::Author)
                    .or_else(|| title_page.get(&model::TitleField::Authors))
                    .unwrap_or_default()
                    .to_owned(),
                created_epoch_seconds: 0,
            };
            let open_scripts = state
                .handles()
                .into_iter()
                .filter_map(|open| state.session(open))
                .filter_map(Session::path)
                .map(Path::to_path_buf)
                .collect::<Vec<_>>();
            let pdf_font_path = state
                .storage()
                .and_then(|storage| storage.prefs.pdf_font_path.clone());
            Some((info, open_scripts, pdf_font_path))
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
    if project::protected_destination(&path) {
        return failed(SaveFailure::LibraryDestination, &path, "Export cannot replace managed project contents; choose a destination outside a project.");
    }
    if !overwrite && path.exists() {
        return failed(
            SaveFailure::AlreadyExists,
            &path,
            &format!("{} is already there", path.display()),
        );
    }

    // Read once, here, so that every page of one export carries the same
    // timestamp and `SOURCE_DATE_EPOCH` is honoured (§Phase 7).
    let info = render_pdf::DocumentInfo {
        created_epoch_seconds: render_pdf::creation_time(),
        ..info
    };
    let config = layout::page_config(&setup);
    let Some(pagination) = paginate_for_export(handle.id, &config) else {
        return failed(
            SaveFailure::NoSuchDocument,
            &path,
            "the document was closed while it was being paginated",
        );
    };

    let custom_font = match pdf_font_path {
        Some(font_path) => match std::fs::read(&font_path) {
            Ok(bytes) => Some(bytes),
            Err(error) => {
                return failed(
                    SaveFailure::Io,
                    &path,
                    &format!(
                        "the selected PDF font {} could not be read: {error}",
                        font_path.display()
                    ),
                );
            }
        },
        None => None,
    };
    let bytes = match custom_font {
        Some(ref font) => {
            match render_pdf::render_with_font(&pagination.script, &config, &info, font) {
                Ok(bytes) => bytes,
                Err(message) => return failed(SaveFailure::Io, &path, &message),
            }
        }
        None => render_pdf::render(&pagination.script, &config, &info),
    };
    if let Err(error) = atomic::save_atomically(&path, &bytes) {
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: bytes.len().min(u32::MAX as usize) as u32,
        backup: None,
    }
}

/// Paginates for an export, giving a document that moved on one second chance.
fn paginate_for_export(handle: u64, config: &PageConfig) -> Option<crate::state::Pagination> {
    let (pagination, current) = layout::paginate(handle, config)?;
    if current {
        return Some(pagination);
    }
    layout::paginate(handle, config).map(|(newer, _)| newer)
}

/// A title for a document whose title page does not give one.
///
/// The file's stem, which is what the library shows for the same script, so an
/// exported PDF and the shelf it came off agree.
fn script_name(path: Option<&Path>) -> String {
    path.and_then(Path::file_stem)
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| "Untitled".to_owned())
}

/// The autosave, called by Dart's own timers.
///
/// Writes a changed snapshot at most once per ten minutes, decided from the
/// newest backup's filename when this save is already running (ADR 0043).
/// Answers [`SaveOutcome::Unchanged`] quietly when there is nothing to write.
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
/// revision. An autosave with nothing left to write says
/// [`SaveOutcome::Unchanged`]; an explicit save still records a version.
///
/// ## Why it checks the file it is about to replace
///
/// §Phase 4's external-modification rule used to live entirely in the watcher:
/// `notify` reported that somebody else had written the file, Dart asked, and
/// the writer decided. A save asked nothing. That made the watcher the *only*
/// thing between an autosave and another program's edit — and the watcher is
/// allowed not to be there at all (`watch::DiskState` has the list). On a
/// machine out of inotify descriptors the protection was simply absent, and
/// absent invisibly.
///
/// So the check is here as well, at the one instant that matters: between
/// knowing what is on disk and replacing it. It costs one cached `stat` when
/// nothing has happened, which is every save of every ordinary session, and it
/// makes the watcher what it should be — the thing that asks the question early
/// rather than the only thing that asks it.
///
/// A Save As is exempt: its destination was named by the writer through a
/// chooser that has already asked about replacing what is there, and refusing a
/// path somebody just typed would be answering a question with the question.
async fn write_document(
    handle: DocumentHandle,
    save_as: Option<PathBuf>,
    explicit_save: bool,
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
                project: session.project.clone(),
                disk: session.disk_state(),
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
    let active_library = actor().run(|state| state.storage().map(|s| s.library_root.clone()));
    let validated = plan
        .project
        .as_ref()
        .filter(|context| active_library.as_ref() == Some(&context.root))
        .and_then(|context| {
            project::validate_save(&context.root, &path)
                .ok()
                .filter(|p| p.metadata.id == context.id)
        });
    if validated.is_none() {
        abandon_save(handle.id);
        return failed(SaveFailure::LibraryDestination, &path, "Library/project unavailable, archived or invalid. Retain unsaved edits and Export a copy.");
    }
    // Explicit saves always write and snapshot, even if autosave already made
    // the document clean. Only redundant autosaves are coalesced.
    if !plan.dirty && save_as.is_none() && !explicit_save {
        abandon_save(handle.id);
        return SaveOutcome::Unchanged;
    }

    // Step one and a half, off the actor: is the file still the one we think we
    // are replacing? See the header. Only for a save of this session's own file
    // — a Save As is a destination the writer named — and only when we know what
    // we last left there.
    if save_as.is_none() {
        if let Some(expected) = plan.disk {
            match expected.compare(&path) {
                // The ordinary answer, and the cheap one: one `stat`.
                DiskVerdict::Unchanged => {}
                // Somebody rewrote the file with the bytes it already had. There
                // is nothing to decide and nothing to say; the record is left
                // stale on purpose, because the write below is about to replace
                // it with a fresh one anyway.
                DiskVerdict::Restamped(_) => {}
                // Gone, or no longer text. Nothing here to preserve, and a save
                // refused for a file that cannot be read is one the writer has
                // no way to un-refuse.
                DiskVerdict::Unreadable => {}
                DiskVerdict::Changed => {
                    abandon_save(handle.id);
                    // The same event the watcher would have pushed, so that one
                    // Dart path handles both — and so that the prompt happens
                    // even on a machine where the watcher never started, which
                    // is the whole reason this check exists.
                    emit(CoreEvent::FileChangedOnDisk {
                        path: path.to_string_lossy().into_owned(),
                    });
                    return failed(
                        SaveFailure::ChangedOnDisk,
                        &path,
                        &format!(
                            "{} was changed by something else since it was last read here",
                            path.display()
                        ),
                    );
                }
            }
        }
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
    // What the file is now, taken here rather than in the actor closure below:
    // it is a `stat` and a hash of bytes we already hold, and the actor thread
    // does no disk work (§2.3).
    let wrote = DiskState::recorded(&path, &plan.text);

    // §Phase 4's rolling backups. Written after the file, so a backup only ever
    // exists for a state that reached the disk.
    //
    // `written.origin` is deliberately not reported. It is the label on the
    // backup directory, not a copy of anybody's text, and the whole cost of
    // losing it is that a directory named after a hash cannot say what it is
    // without the library index; the next backup writes it again. A save that
    // worked must not grow a warning over that.
    let backup = plan.storage.as_ref().and_then(|(root, retention)| {
        let written = if explicit_save {
            backup::write(root, &path, &plan.text, *retention).ok()
        } else {
            backup::write_if_changed(
                root,
                &path,
                &plan.text,
                *retention,
                AUTOSAVE_BACKUP_INTERVAL_MILLIS,
            )
            .ok()
            .flatten()
        };
        written.map(|written| BackupView {
            path: written.backup.path.to_string_lossy().into_owned(),
            written_millis: written.backup.written_millis,
            bytes: written.backup.bytes,
        })
    });
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
    let identities: Vec<_> = snapshot.blocks.iter().map(|block| block.id).collect();
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
            // After the rebind, which clears what was known about the file this
            // session has just left. The next save checks against these bytes,
            // and an edit that landed while they were being written does not
            // change what is *on disk* — which is the only thing this describes.
            if let Some(session) = state.session_mut(handle.id) {
                session.set_disk_state(Some(wrote));
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
                        let _ = journal.checkpoint_with_identities(&path, &text, &identities);
                    } else {
                        // Rebuilt at its own path, not by id: a Save As has
                        // already changed the id by now and the journal file
                        // has not moved. Written atomically, so a crash in the
                        // middle leaves the old journal whole.
                        if let Ok(successor) =
                            journal.rebuild_at_with_identities(&path, &text, &unsaved, &identities)
                        {
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
                    let config = state
                        .storage()
                        .map(|storage| preference_page_config(&storage.prefs))
                        .unwrap_or_default();
                    state.storage_mut().map(|storage| SavedPagination {
                        token: storage.begin_page_count(&id),
                        id,
                        handle: handle.id,
                        generation,
                        snapshot,
                        config,
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
    /// What the session last knew the file to hold, read here so the comparison
    /// against the disk happens off the actor with the save claim held.
    disk: Option<DiskState>,
    project: Option<ProjectContext>,
}

struct SavedPagination {
    token: u64,
    id: String,
    handle: u64,
    generation: u64,
    snapshot: slugline_layout::ScriptSnapshot,
    config: PageConfig,
}

fn update_saved_page_count(job: SavedPagination) {
    let result = catch_unwind(AssertUnwindSafe(|| {
        layout::paginate_snapshot(job.handle, job.generation, job.snapshot, &job.config)
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

pub(super) fn preference_page_config(preferences: &CorePreferences) -> PageConfig {
    let config = if preferences.default_paper == prefs::PAPER_A4 {
        PageConfig::a4()
    } else {
        PageConfig::us_letter()
    };
    config
        .with_scene_numbers(match preferences.scene_numbers.as_str() {
            prefs::SCENE_NUMBERS_LEFT => slugline_layout::SceneNumberGutters::Left,
            prefs::SCENE_NUMBERS_RIGHT => slugline_layout::SceneNumberGutters::Right,
            prefs::SCENE_NUMBERS_BOTH => slugline_layout::SceneNumberGutters::Both,
            _ => slugline_layout::SceneNumberGutters::None,
        })
        .with_bold_scene_headings(preferences.bold_scene_headings)
        .with_number_first_page(preferences.number_first_page)
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
        // Only when the file turns out to hold exactly what we have. Then there
        // is nothing to protect and nothing to ask about, and recording it is
        // what stops a save being refused for ever over a `touch` — the file was
        // re-stamped, the bytes are ours, and the next save proceeds.
        //
        // The other way round is deliberately *not* done here: a file that
        // differs stays unacknowledged until the writer has decided, because
        // this call is only ever the beginning of that decision.
        let seen = (!differs).then(|| DiskState::recorded(&plan.path, &on_disk));

        let validation = actor().run(move |state| {
            let session = state.session_mut(handle.id)?;
            if session.path() != Some(plan.path.as_path()) {
                return None;
            }
            if let Some(seen) = seen {
                session.set_disk_state(Some(seen));
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

/// "Keep mine": the writer has been shown what is in the file and has chosen
/// their own version, so the file stops being news.
///
/// This is the one door out of a [`SaveFailure::ChangedOnDisk`] that keeps the
/// writer's text. Without it the refusal would be permanent — every save from
/// here would find the same unfamiliar bytes and refuse again — and a save the
/// writer cannot complete is §1.2's P0 arriving by a different road.
///
/// It records what the file holds *now* rather than clearing the record: the
/// next save is authorised to replace the version the writer was shown, and
/// nothing else. Somebody writing the file again between this and that save is a
/// new external change and asks again.
///
/// Answers `true` when the session came away with a definite answer, including a
/// file that has since been deleted — there is nothing left there to protect and
/// the save may recreate it.
pub async fn doc_accept_disk_state(handle: DocumentHandle) -> bool {
    // Behind the save claim, like every other statement about what is on disk:
    // an autosave already past its timer must not slip between the read below
    // and the record being kept.
    let Some(save_lock) =
        actor().run(move |state| state.session(handle.id).map(|session| session.save_lock()))
    else {
        return false;
    };
    let _claim = save_lock.lock().unwrap_or_else(PoisonError::into_inner);

    let Some(path) = actor().run(move |state| {
        state
            .session(handle.id)
            .and_then(Session::path)
            .map(Path::to_path_buf)
    }) else {
        return false;
    };
    let accepted = std::fs::read_to_string(&path)
        .ok()
        .map(|contents| DiskState::recorded(&path, &contents));

    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return false;
        };
        // A session that moved while the file was being read has nothing to
        // accept: what it was shown was about a file it no longer holds.
        if session.path() != Some(path.as_path()) {
            return false;
        }
        session.set_disk_state(accepted);
        true
    })
}

/// Whether external changes to this document's file are being watched for
/// (§Phase 4).
///
/// `false` means no notification will arrive when another program writes this
/// script — not that it could be overwritten unnoticed, which the save path
/// prevents on its own. The status line says so for the whole session, because
/// the alternative is a writer relying on a prompt that is never coming.
#[frb(sync)]
pub fn doc_watch_state(handle: DocumentHandle) -> bool {
    actor().run(move |state| {
        state
            .session(handle.id)
            .is_none_or(|session| !session.watch_broken())
    })
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
    // Taking theirs is agreeing that what is on disk is the file: from here it
    // is what the next save checks itself against.
    let disk = DiskState::recorded(&path, &source);

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
        session.set_disk_state(Some(disk));
        let document = model::Document::parse(&source);
        session.replace_document(if document.blocks().is_empty() {
            model::Document::blank()
        } else {
            document
        });
        session.rebuild_entities();
        restart_journal(state, handle.id, &source, Restart::Rebased);
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

/// Reads the literal Fountain snapshot off the actor, including its title page.
pub async fn backup_read(backup_path: String) -> BackupReadOutcome {
    match std::fs::read_to_string(&backup_path) {
        Ok(source) => BackupReadOutcome::Read {
            has_bom: Some(source.starts_with('\u{feff}')),
            source,
        },
        Err(error) => BackupReadOutcome::Failed {
            message: format!("could not read {backup_path}: {error}"),
        },
    }
}

/// Writes the already viewed snapshot to a new file, without touching the
/// current session. Using the snapshot rather than rereading the backup keeps
/// the copy identical to the view even if retention removes the backup meanwhile.
/// Existing destinations are never replaced, including the backup itself.
pub async fn backup_copy(handle: DocumentHandle, source: String, path: String) -> SaveOutcome {
    let path = PathBuf::from(path);
    if path.as_os_str().is_empty() {
        return failed(SaveFailure::NoPath, &path, "no file was chosen");
    }
    let Some(open_scripts) = actor().run(move |state| {
        state.session(handle.id)?;
        Some(
            state
                .handles()
                .into_iter()
                .filter_map(|open| state.session(open))
                .filter_map(Session::path)
                .map(Path::to_path_buf)
                .collect::<Vec<_>>(),
        )
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
            "that script is open; choose a new file for the copy",
        );
    }
    if project::protected_destination(&path) {
        return failed(
            SaveFailure::LibraryDestination,
            &path,
            "Choose a copy destination outside managed projects",
        );
    }
    if path.exists() {
        return failed(
            SaveFailure::AlreadyExists,
            &path,
            "that file already exists; choose a new name for the copy",
        );
    }
    // The same chooser-to-rename race as Fountain export; no write or session
    // bookkeeping runs on the actor.
    if let Err(error) = atomic::save_atomically(&path, &source) {
        return SaveOutcome::Failed {
            failure: failure_of(&error),
            path: path.to_string_lossy().into_owned(),
            message: error.to_string(),
        };
    }
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: source.len().min(u32::MAX as usize) as u32,
        backup: None,
    }
}

/// §Phase 4's "Restore previous version".
///
/// "Restoring a backup writes the current state to a new backup first" — so this
/// saves before it restores, which means the restore is itself undoable by
/// restoring the copy it just made.
pub async fn backup_restore(handle: DocumentHandle, backup_path: String) -> SaveOutcome {
    let Some((context, path)) = actor().run(move |state| {
        let s = state.session(handle.id)?;
        Some((s.project.clone()?, s.path()?.to_path_buf()))
    }) else {
        return failed(
            SaveFailure::LibraryDestination,
            Path::new(&backup_path),
            "Restore requires a managed project",
        );
    };
    let Ok(project) = project::validate_save(&context.root, &path) else {
        return failed(
            SaveFailure::LibraryDestination,
            &path,
            "Managed project unavailable",
        );
    };
    let Ok(backup_resolved) = Path::new(&backup_path).canonicalize() else {
        return failed(
            SaveFailure::Io,
            Path::new(&backup_path),
            "Previous version is unavailable",
        );
    };
    if backup_resolved.parent() != Some(project.versions().as_path()) {
        return failed(
            SaveFailure::LibraryDestination,
            &backup_resolved,
            "Choose a previous version belonging to this project",
        );
    }
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
    // The restored bytes are the file now, so they are what the next save
    // checks itself against — exactly as after an ordinary save.
    let restored = DiskState::recorded(&path, &contents);

    let bytes = contents.len().min(u32::MAX as usize) as u32;
    actor().run({
        let contents = contents.clone();
        move |state| {
            let Some(session) = state.session_mut(handle.id) else {
                return;
            };
            session.set_disk_state(Some(restored));
            let document = model::Document::parse(&contents);
            session.replace_document(if document.blocks().is_empty() {
                model::Document::blank()
            } else {
                document
            });
            session.rebuild_entities();
            restart_journal(state, handle.id, &contents, Restart::Rebased);
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
/// Live journals are skipped. Hold the lock through reading and empty-journal
/// cleanup; a stale offer is checked again by accept and discard.
pub async fn recovery_pending() -> Vec<RecoveryOffer> {
    let directory = actor().run(|state| state.storage().map(|storage| storage.paths.journal_dir()));
    let Some(directory) = directory else {
        return Vec::new();
    };

    let mut offers = Vec::new();
    for path in journal::pending(&directory) {
        let Ok(guard) = journal::RecoveryGuard::try_open(&path) else {
            continue;
        };
        let Ok(recovery) = guard.read() else {
            // A journal we cannot read at all is a journal we cannot offer. It
            // is left on disk rather than deleted: it is the user's text, in a
            // form a person could still pick apart by hand.
            continue;
        };
        if recovery.is_empty() {
            // Nothing was typed after the last save. Not a loss, and not worth a
            // dialog — but the file has served its purpose, so it goes.
            let _ = guard.discard();
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
/// 1. Lock, read and verify the old journal. Verification returns the file's real
///    bytes, which are still the pre-crash ones. A live owner refuses the lock.
/// 2. Replay onto those bytes, remembering exactly which patches applied. A
///    patch that does not fit stops the replay, and the ones after it are not in
///    the recovered document, so they must not be in its journal either.
/// 3. Open the document and bind it to its file, library entry and watch.
/// 4. Write the **successor journal**: same `base` — the file has not changed —
///    plus the patches that replayed. [`journal::RecoveryGuard::rebuild`] locks
///    the successor before publishing it through the atomic save.
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
    let guard = match journal::RecoveryGuard::try_open(&path) {
        Ok(guard) => guard,
        Err(why) => {
            return RecoveryOutcome::Failed {
                message: why.to_string(),
            }
        }
    };
    let recovery = match guard.read() {
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

    let root = active_root(false).ok();
    let managed = root
        .as_ref()
        .and_then(|root| project::resolve(root, &recovery.header.script).ok());
    if managed.as_ref().is_some_and(|p| p.metadata.archived) {
        return RecoveryOutcome::Failed {
            message:
                "Restore the archived project before accepting recovery; the journal is retained."
                    .into(),
        };
    }
    if managed.is_none()
        && root.as_ref().is_some_and(|r| {
            recovery.header.script.parent().and_then(Path::parent) == Some(r.as_path())
        })
    {
        return RecoveryOutcome::Failed { message: "Repair the managed project metadata or library availability before accepting recovery; the journal is retained.".into() };
    }
    if managed.is_none() {
        // Legacy/untitled recovery is an isolated candidate. Cancellation never consumes predecessor.
        let mut metadata = match Metadata::new(script_name(Some(&recovery.header.script))) {
            Ok(m) => m,
            Err(e) => {
                return RecoveryOutcome::Failed {
                    message: e.to_string(),
                }
            }
        };
        if !untitled {
            let legacy = actor().run({
                let script = recovery.header.script.clone();
                move |state| {
                    state
                        .storage()
                        .and_then(|s| s.legacy.iter().find(|e| same_file(&e.path, &script)))
                        .cloned()
                }
            });
            metadata.origin = Some(Origin {
                path: recovery.header.script.clone(),
                kind: "recovery migration".into(),
                legacy_id: legacy.as_ref().map(|e| e.id.clone()),
                history_complete: false,
            });
            if let Some(entry) = legacy {
                metadata.name = entry.title;
                metadata.pinned_entities = entry.pinned_entities;
            }
        }
        let handle = create_candidate(
            document,
            ProjectCandidate {
                metadata,
                bytes: None,
                fdx: None,
                predecessor: Some(path),
                published: None,
            },
        );
        return RecoveryOutcome::Recovered { handle };
    }
    let managed = managed.unwrap();
    let script = recovery.header.script.clone();
    // `journal::verify` has just answered that the file still holds `source`, so
    // that is what this session knows about it — and a save of the recovered
    // document, which arrives dirty, is checked against exactly those bytes.
    let disk = (!untitled).then(|| DiskState::recorded(&script, &source));
    let handle = actor().run({
        let script = script.clone();
        move |state| {
            let handle = state.open(document);
            if !untitled {
                let id = journal::script_id(&script);
                if let Some(session) = state.session_mut(handle) {
                    session.set_file(script.clone(), id.clone());
                    session.set_disk_state(disk);
                    session.project = Some(ProjectContext {
                        root: root.clone().unwrap(),
                        id: managed.metadata.id.clone(),
                    });
                }
                if let Some(storage) = state.storage_mut() {
                    storage.library.add(&script);
                    storage.library.opened(&id);
                }
                hydrate_pins(state, handle, &id);
                watch(state, handle, &script);
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
    let successor = match guard.rebuild(&directory, &id, &script, &source, applied) {
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

    // The guard kept the old journal locked until a locked successor existed,
    // then removed it only when the successor was at a different path.
    actor().run(move |state| {
        if let Some(session) = state.session_mut(handle) {
            session.set_journal(Some(successor));
        }
    });
    RecoveryOutcome::Recovered {
        handle: DocumentHandle { id: handle },
    }
}

/// Open, replayed, and not being recorded. Says so rather than looking like a
/// normal session that happens to be losing keystrokes.
fn degraded(handle: u64, message: &str) -> RecoveryOutcome {
    // The dialog says this once, and the status line goes on saying it: a
    // recovered session whose successor journal could not be written is exactly
    // as unprotected as one whose journal broke mid-session, and `set_journal`
    // would have cleared that flag rather than set it.
    actor().run(move |state| {
        unprotected(state, handle);
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
/// Capture an external Fountain once. Nothing is published until commit.
pub async fn doc_prepare_import(path: String) -> FdxImportOutcome {
    prepare_import(path)
}

fn prepare_import(path: String) -> FdxImportOutcome {
    let source_path = match Path::new(&path).canonicalize() {
        Ok(p) => p,
        Err(e) => {
            return FdxImportOutcome::Failed {
                message: format!("Could not read {path}: {e}"),
            }
        }
    };
    if active_root(false)
        .ok()
        .is_some_and(|r| source_path.parent().and_then(Path::parent) == Some(r.as_path()))
    {
        return FdxImportOutcome::Failed {
            message: "Open or repair this active-library project; import is for external files"
                .into(),
        };
    }
    if recovery_for(&source_path) {
        return FdxImportOutcome::Failed {
            message: "Resolve this script's pending recovery before importing its saved file"
                .into(),
        };
    }
    let bytes = match std::fs::read(&source_path) {
        Ok(b) => b,
        Err(e) => {
            return FdxImportOutcome::Failed {
                message: e.to_string(),
            }
        }
    };
    let source = match std::str::from_utf8(&bytes) {
        Ok(s) => s,
        Err(_) => {
            return FdxImportOutcome::Failed {
                message: "Unsupported Fountain encoding; use UTF-8".into(),
            }
        }
    };
    let document = model::Document::parse(source);
    let mut metadata = match Metadata::new(
        source_path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned(),
    ) {
        Ok(m) => m,
        Err(e) => {
            return FdxImportOutcome::Failed {
                message: e.to_string(),
            }
        }
    };
    metadata.origin = Some(Origin {
        path: source_path,
        kind: "fountain".into(),
        legacy_id: None,
        history_complete: true,
    });
    FdxImportOutcome::Imported {
        handle: create_candidate(
            document,
            ProjectCandidate {
                metadata,
                bytes: Some(bytes),
                fdx: None,
                predecessor: None,
                published: None,
            },
        ),
        warnings: Vec::new(),
    }
}

fn initial_outcome(document: &model::Document) -> model::Patch {
    let mut blocks = document.blocks().iter().enumerate().map(|(i, b)| {
        (
            i as u32,
            model::BlockSnapshot {
                id: b.id(),
                kind: b.kind(),
                text: b.text().to_owned(),
                forced: b.forced(),
                dual: b.dual(),
            },
        )
    });
    model::Patch {
        changed: blocks.next().map(|b| b.1).into_iter().collect(),
        inserted: blocks.collect(),
        title_page: Some(document.title_page().clone()),
        ..model::Patch::default()
    }
}

fn create_candidate(document: model::Document, candidate: ProjectCandidate) -> DocumentHandle {
    actor().run(move |state| {
        let document = if document.blocks().is_empty() {
            model::Document::blank()
        } else {
            document
        };
        let initial = initial_outcome(&document);
        let handle = state.open(document);
        restart_journal(state, handle, "", Restart::Fresh);
        if let Some(s) = state.session_mut(handle) {
            s.candidate = Some(candidate);
            crate::api::doc::record_patch(s, initial);
        }
        DocumentHandle { id: handle }
    })
}

/// Durable publication followed by adoption, without replacing Document or history.
pub async fn doc_commit_project(handle: DocumentHandle) -> SaveOutcome {
    commit_project(handle)
}

fn commit_project(handle: DocumentHandle) -> SaveOutcome {
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some(lock) = actor().run(move |state| state.session(handle.id).map(Session::save_lock))
    else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "Candidate is no longer open",
        );
    };
    let _claim = lock.lock().unwrap_or_else(PoisonError::into_inner);
    let Some((mut candidate, text, revision, ids)) = actor().run(move |state| {
        let session = state.session_mut(handle.id)?;
        let candidate = session.candidate.clone()?;
        let text = if session.document_generation() == 0 {
            candidate
                .bytes
                .clone()
                .and_then(|b| String::from_utf8(b).ok())
                .unwrap_or_else(|| session.document().serialise())
        } else {
            session.document().serialise()
        };
        let ids = session
            .document()
            .blocks()
            .iter()
            .map(|b| b.id())
            .collect::<Vec<_>>();
        let revision = session.begin_save();
        Some((candidate, text, revision, ids))
    }) else {
        return failed(
            SaveFailure::NoSuchDocument,
            Path::new(""),
            "Not an import/new-project candidate",
        );
    };
    let root = match active_root(true) {
        Ok(r) => r,
        Err(e) => {
            abandon_save(handle.id);
            return storage_failed(e);
        }
    };
    // Record that a formerly lazy root now exists. A disappearance cannot silently recreate it.
    let Some((mut prefs, prefs_path)) = actor().run(|state| {
        state
            .storage()
            .map(|s| (s.prefs.clone(), s.paths.preferences()))
    }) else {
        abandon_save(handle.id);
        return failed(SaveFailure::Io, &root, "Storage unavailable");
    };
    prefs.library_dir = Some(root.clone());
    if let Err(e) = prefs.save(&prefs_path) {
        abandon_save(handle.id);
        return storage_failed(e);
    }
    actor().run({
        let root = root.clone();
        move |state| {
            if let Some(s) = state.storage_mut() {
                s.prefs = prefs;
                s.library_root = root;
                s.library_error = None;
            }
        }
    });
    let predecessor_guard = match candidate
        .predecessor
        .as_ref()
        .map(|p| journal::RecoveryGuard::try_open(p))
        .transpose()
    {
        Ok(g) => g,
        Err(e) => {
            abandon_save(handle.id);
            return failed(
                SaveFailure::Io,
                &root,
                &format!("Legacy recovery remains owned/unresolved: {e}"),
            );
        }
    };
    // The candidate journal and predecessor identify an interrupted publication across restarts.
    let creation_journal =
        actor().run(move |state| state.session(handle.id).and_then(Session::journal_path));
    if let Some(path) = creation_journal {
        candidate.metadata.unknown.insert(
            "creation_journal".into(),
            path.to_string_lossy().into_owned().into(),
        );
    }
    if let Some(path) = &candidate.predecessor {
        candidate.metadata.unknown.insert(
            "recovery_predecessor".into(),
            path.to_string_lossy().into_owned().into(),
        );
    }
    if candidate.published.is_none() {
        if let Ok(projects) = project::scan(&root) {
            let recovered = projects.into_iter().find(|p| {
                candidate.predecessor.as_ref().is_some_and(|path| {
                    ["recovery_predecessor", "creation_journal"]
                        .iter()
                        .any(|key| {
                            p.metadata
                                .unknown
                                .get(*key)
                                .and_then(|v| v.as_str())
                                .is_some_and(|v| Path::new(v) == path)
                        })
                })
            });
            if let Some(project) = recovered {
                candidate.published = Some(project.script());
                candidate.metadata = project.metadata;
            }
        }
    }
    let project = if let Some(path) = candidate.published.as_ref() {
        match project::resolve(&root, path) {
            Ok(p) if p.metadata.id == candidate.metadata.id => {
                if std::fs::read(p.script()).ok().as_deref() != Some(text.as_bytes()) {
                    abandon_save(handle.id);
                    return failed(SaveFailure::ChangedOnDisk, path, "An interrupted publication already exists with different text. Resolve its recovery or export this candidate; no second project was created.");
                }
                p
            }
            _ => {
                abandon_save(handle.id);
                return failed(
                    SaveFailure::Io,
                    path,
                    "Previously published project is unavailable; retain candidate and retry",
                );
            }
        }
    } else {
        match project::create(
            &root,
            candidate.metadata.clone(),
            text.as_bytes(),
            candidate.fdx.as_deref(),
        ) {
            Ok(p) => p,
            Err(e) => {
                // Publication followed by failed directory sync is durable enough to reconcile, never erase.
                if e.to_string().contains("project published at") {
                    let path = e.path().join(project::SCRIPT);
                    actor().run(move |state| {
                        if let Some(c) = state
                            .session_mut(handle.id)
                            .and_then(|s| s.candidate.as_mut())
                        {
                            c.published = Some(path);
                        }
                    });
                }
                abandon_save(handle.id);
                return storage_failed(e);
            }
        }
    };
    let path = project.script();
    actor().run({
        let path = path.clone();
        move |state| {
            if let Some(c) = state
                .session_mut(handle.id)
                .and_then(|s| s.candidate.as_mut())
            {
                c.published = Some(path);
            }
        }
    });
    let disk = DiskState::recorded(&path, &text);
    let directory = actor().run(|state| state.storage().unwrap().paths.journal_dir());
    let id = journal::script_id(&path);
    // The old candidate journal stays locked and intact until successor installation.
    let mut successor = match Journal::create(&directory, &id, &path, &text) {
        Ok(j) => Some(j),
        Err(_) => {
            // Retry only a verified empty checkpoint. Recorded outcomes require recovery,
            // and a live successor remains protected by its flock.
            let pending = directory.join(format!("{id}.log"));
            journal::RecoveryGuard::try_open(&pending)
                .ok()
                .and_then(|guard| {
                    let recovery = guard.read().ok()?;
                    if recovery.header.script != path
                        || !recovery.patches.is_empty()
                        || journal::verify(&recovery.header).ok().as_deref() != Some(text.as_str())
                    {
                        return None;
                    }
                    guard.rebuild(&directory, &id, &path, &text, &[]).ok()
                })
        }
    };
    let adopted = actor().run({
        let path = path.clone();
        let project = project.clone();
        let root = root.clone();
        let text = text.clone();
        move |state| {
            let Some(s) = state.session_mut(handle.id) else {
                return false;
            };
            let unsaved = s.finish_save();
            if let Some(j) = successor.as_mut() {
                if j.checkpoint_with_identities(&path, &text, &ids)
                    .and_then(|()| {
                        for patch in &unsaved {
                            j.append(patch)?;
                        }
                        Ok(())
                    })
                    .is_err()
                {
                    successor = None;
                }
            }
            // Legacy migration requires a protected successor before retiring predecessor.
            if (candidate.predecessor.is_some() || directory.join(format!("{id}.log")).exists())
                && successor.is_none()
            {
                return false;
            }
            let old = s.take_journal();
            if let Some(journal) = successor {
                s.set_journal(Some(journal));
                if let Some(old) = old {
                    let _ = old.discard();
                }
            } else {
                // New stored project remains usable; keep old journal evidence and sticky warning.
                s.set_journal_unavailable();
                emit(CoreEvent::JournalBroken { handle: handle.id });
            }
            s.document_mut().mark_saved_at(revision);
            s.set_file(path.clone(), id.clone());
            s.set_disk_state(Some(disk));
            s.project = Some(ProjectContext {
                root,
                id: project.metadata.id.clone(),
            });
            s.candidate = None;
            if let Some(storage) = state.storage_mut() {
                storage.library.cache_project(&project);
                storage.library.opened(&id);
                if let Some(legacy_id) = project
                    .metadata
                    .origin
                    .as_ref()
                    .and_then(|o| o.legacy_id.as_ref())
                {
                    if let Some(entry) = storage.legacy.iter().find(|e| &e.id == legacy_id) {
                        storage.library.set_scroll(&id, entry.scroll_row);
                    }
                }
            }
            hydrate_pins(state, handle.id, &id);
            watch(state, handle.id, &path);
            save_library(state);
            true
        }
    });
    if !adopted {
        return failed(SaveFailure::Io, &path, "Project published, but recovery protection/adoption failed. The previous journal is retained; retry this candidate.");
    }
    if let Some(guard) = predecessor_guard {
        if let Err(e) = guard.discard() {
            return failed(
                SaveFailure::Io,
                &path,
                &format!("Managed successor is ready; legacy recovery journal retained: {e}"),
            );
        }
    }
    let mut completed = project.metadata.clone();
    if let Some(origin) = completed.origin.as_mut().filter(|o| o.legacy_id.is_some()) {
        let legacy_root = actor().run(|state| {
            let s = state.storage().unwrap();
            s.prefs
                .backup_dir
                .clone()
                .unwrap_or_else(|| s.paths.backup_dir())
        });
        origin.history_complete = migrate_history(&project, &legacy_root, &origin.path).is_ok();
    }
    completed.unknown.remove("creation_journal");
    completed.unknown.remove("recovery_predecessor");
    if project::update(&project, &completed).is_ok() {
        if let Ok(project) = project::read(&project.directory) {
            actor().run(move |state| {
                if let Some(s) = state.storage_mut() {
                    s.library.cache_project(&project);
                }
            });
        }
    }
    let retention = actor().run(|state| state.storage().unwrap().prefs.retention());
    let _ = backup::write_if_changed(&root, &path, &text, retention, 0);
    SaveOutcome::Saved {
        path: path.to_string_lossy().into_owned(),
        bytes: text.len() as u32,
        backup: None,
    }
}

/// Origin matches are choices, never implicit synchronization or content identity.
pub async fn library_origin_copies(path: String) -> Vec<ScriptView> {
    let source = PathBuf::from(path);
    let Ok(root) = active_root(false) else {
        return Vec::new();
    };
    let Ok(projects) = project::scan(&root) else {
        return Vec::new();
    };
    let paths: Vec<_> = projects
        .into_iter()
        .filter(|p| {
            p.metadata
                .origin
                .as_ref()
                .is_some_and(|o| same_file(&o.path, &source))
        })
        .map(|p| p.script())
        .collect();
    library_list()
        .await
        .into_iter()
        .filter(|entry| paths.contains(&PathBuf::from(&entry.path)))
        .collect()
}

pub async fn library_legacy() -> Vec<ScriptView> {
    actor().run(|state| {
        state
            .storage()
            .map(|s| s.legacy.iter().map(script_view).collect())
            .unwrap_or_default()
    })
}

#[derive(Debug, Clone)]
pub struct MigrationResult {
    pub id: String,
    pub project: Option<ScriptView>,
    pub complete: bool,
    pub message: String,
}

/// Explicit selective migration. Durable per-project markers make retries idempotent.
pub async fn library_migrate(id: String) -> MigrationResult {
    let _migration = MIGRATIONS.lock().unwrap_or_else(PoisonError::into_inner);
    let Some(entry) = actor().run({
        let id = id.clone();
        move |state| state.storage()?.legacy.iter().find(|e| e.id == id).cloned()
    }) else {
        return MigrationResult {
            id,
            project: None,
            complete: false,
            message: "No such legacy entry".into(),
        };
    };
    if recovery_for(&entry.path) {
        return MigrationResult {
            id,
            project: None,
            complete: false,
            message: "Resolve pending recovery before migration".into(),
        };
    }
    let existing = active_root(false)
        .ok()
        .and_then(|r| project::scan(&r).ok())
        .and_then(|ps| {
            ps.into_iter().find(|p| {
                p.metadata
                    .origin
                    .as_ref()
                    .is_some_and(|o| o.legacy_id.as_deref() == Some(&id))
            })
        });
    let project = if let Some(p) = existing {
        p
    } else {
        let FdxImportOutcome::Imported { handle, .. } =
            prepare_import(entry.path.to_string_lossy().into_owned())
        else {
            return MigrationResult {
                id,
                project: None,
                complete: false,
                message: "Source missing, unreadable, unsupported, or recovery unresolved".into(),
            };
        };
        actor().run({
            let entry = entry.clone();
            move |state| {
                if let Some(c) = state
                    .session_mut(handle.id)
                    .and_then(|s| s.candidate.as_mut())
                {
                    c.metadata.name = entry.title;
                    c.metadata.pinned_entities = entry.pinned_entities;
                    if let Some(o) = c.metadata.origin.as_mut() {
                        o.kind = "migration".into();
                        o.legacy_id = Some(entry.id);
                        o.history_complete = false;
                    }
                }
            }
        });
        let result = commit_project(handle);
        crate::api::doc::doc_close(handle);
        let SaveOutcome::Saved { path, .. } = result else {
            return MigrationResult {
                id,
                project: None,
                complete: false,
                message: format!("Migration incomplete: {result:?}"),
            };
        };
        match project::read(Path::new(&path).parent().unwrap()) {
            Ok(p) => p,
            Err(e) => {
                return MigrationResult {
                    id,
                    project: None,
                    complete: false,
                    message: e.to_string(),
                }
            }
        }
    };
    let (legacy_root, paths) = actor().run(|state| {
        let s = state.storage().unwrap();
        (
            s.prefs
                .backup_dir
                .clone()
                .unwrap_or_else(|| s.paths.backup_dir()),
            s.paths.clone(),
        )
    });
    // Never run retention against the legacy store. Copy exact recognized files exclusively.
    let complete = migrate_history(&project, &legacy_root, &entry.path);
    let message = match complete {
        Ok(()) => "Imported current script and previous versions".into(),
        Err(e) => format!("Current script imported; previous versions need retry: {e}"),
    };
    let complete = message == "Imported current script and previous versions";
    let mut metadata = project.metadata.clone();
    if let Some(o) = metadata.origin.as_mut() {
        o.history_complete = complete;
    }
    let metadata_saved = project::update(&project, &metadata).is_ok();
    let view = actor().run({
        let project = Project {
            metadata,
            ..project
        };
        move |state| {
            let s = state.storage_mut()?;
            let new_id = s.library.cache_project(&project);
            s.library.set_scroll(&new_id, entry.scroll_row);
            let view = s.library.get(&new_id).map(script_view);
            let _ = s.library.save(&paths.library_index());
            view
        }
    });
    MigrationResult {
        id,
        project: view,
        complete: complete && metadata_saved,
        message: if metadata_saved {
            message
        } else {
            "Current script imported; migration metadata write failed, retry safely".into()
        },
    }
}

fn migrate_history(
    project: &Project,
    legacy_root: &Path,
    source: &Path,
) -> Result<(), atomic::SaveError> {
    // Validate the version store before writes; a symlinked tree is never followed.
    let versions = project.versions();
    if std::fs::symlink_metadata(&versions)
        .map_or(true, |m| !m.is_dir() || m.file_type().is_symlink())
    {
        return Err(atomic::SaveError::Io {
            path: versions.clone(),
            message: "version store is unavailable or a child symlink".into(),
        });
    }
    let directory = legacy_root.join(journal::script_id(source));
    if !directory.exists() {
        return Ok(());
    }
    if std::fs::symlink_metadata(&directory)
        .map_or(true, |m| !m.is_dir() || m.file_type().is_symlink())
    {
        return Err(atomic::SaveError::Io {
            path: directory,
            message: "legacy version store is not an ordinary directory".into(),
        });
    }
    let entries = std::fs::read_dir(&directory).map_err(|e| atomic::SaveError::Io {
        path: directory.clone(),
        message: e.to_string(),
    })?;
    for entry in entries {
        let entry = entry.map_err(|e| atomic::SaveError::Io {
            path: directory.clone(),
            message: e.to_string(),
        })?;
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "fountain")
            || path
                .file_stem()
                .and_then(|s| s.to_str())
                .is_none_or(|s| s.parse::<u64>().is_err())
        {
            continue;
        }
        if std::fs::symlink_metadata(&path)
            .map_or(true, |m| !m.is_file() || m.file_type().is_symlink())
        {
            return Err(atomic::SaveError::Io {
                path,
                message: "legacy version is not an ordinary file".into(),
            });
        }
        let bytes = std::fs::read(&path).map_err(|e| atomic::SaveError::Io {
            path: path.clone(),
            message: e.to_string(),
        })?;
        let mut target = versions.join(path.file_name().unwrap());
        if target.exists() {
            if std::fs::read(&target).ok().as_deref() == Some(bytes.as_slice()) {
                continue;
            }
            // A deterministic alternate timestamp lets retry reconcile exact bytes without overwrite.
            let mut stamp = path
                .file_stem()
                .unwrap()
                .to_str()
                .unwrap()
                .parse::<u64>()
                .unwrap();
            loop {
                stamp = stamp.checked_add(1).ok_or_else(|| atomic::SaveError::Io {
                    path: versions.clone(),
                    message: "version timestamp collision cannot be resolved".into(),
                })?;
                target = versions.join(format!("{stamp}.fountain"));
                if !target.exists()
                    || std::fs::read(&target).ok().as_deref() == Some(bytes.as_slice())
                {
                    break;
                }
            }
            if target.exists() {
                continue;
            }
        }
        // Atomic no-clobber publication; no overwrite when another process races migration.
        atomic::save_new_atomically(&target, &bytes)?;
    }
    Ok(())
}

pub async fn backup_open_copy(handle: DocumentHandle, source: String) -> Option<DocumentHandle> {
    let exists = actor().run(move |state| state.session(handle.id).is_some());
    if !exists {
        return None;
    }
    let candidate = create_candidate(
        model::Document::parse(&source),
        ProjectCandidate {
            metadata: Metadata::new("Previous version copy".into()).ok()?,
            bytes: Some(source.into_bytes()),
            fdx: None,
            predecessor: None,
            published: None,
        },
    );
    if matches!(
        doc_commit_project(candidate).await,
        SaveOutcome::Saved { .. }
    ) {
        Some(candidate)
    } else {
        crate::api::doc::doc_close(candidate);
        None
    }
}

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
    let _operation = PROJECT_OPERATIONS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    let Some((old, paths, current_root, cache)) = actor().run(|state| {
        state.storage().map(|s| {
            (
                s.prefs.clone(),
                s.paths.clone(),
                s.library_root.clone(),
                s.library.clone(),
            )
        })
    }) else {
        return false;
    };
    let next = prefs::Preferences {
        autosave_enabled: preferences.autosave_enabled,
        autocomplete_enabled: preferences.autocomplete_enabled,
        navigator_visible: preferences.navigator_visible,
        // Dictionary loading stays on `spell_configure`; this general
        // surface preserves the values owned by that worker-backed call.
        spell_enabled: old.spell_enabled,
        spell_language: old.spell_language.clone(),
        appearance: preferences.appearance,
        editor_text_size: preferences.editor_text_size,
        default_paper: preferences.default_paper,
        scene_numbers: preferences.scene_numbers,
        bold_scene_headings: preferences.bold_scene_headings,
        number_first_page: preferences.number_first_page,
        pdf_font_path: preferences.pdf_font_path.map(PathBuf::from),
        distraction_free: preferences.distraction_free,
        page_view: preferences.page_view,
        autosave_idle_ms: preferences.autosave_idle_ms,
        autosave_interval_ms: preferences.autosave_interval_ms,
        backup_dir: preferences.backup_dir.map(PathBuf::from),
        library_dir: preferences.library_dir.map(PathBuf::from),
        backup_keep_versions: preferences.backup_keep_versions,
        backup_keep_days: preferences.backup_keep_days,
    }
    .sanitised();
    let desired = next
        .library_dir
        .clone()
        .unwrap_or_else(|| paths.default_library().to_path_buf());
    let changing = desired.canonicalize().unwrap_or_else(|_| desired.clone()) != current_root;
    let mut library = cache;
    let root = if changing {
        let Ok(root) = project::root(&desired, true) else {
            return false;
        };
        if library.rebuild(&root).is_err() {
            return false;
        }
        root
    } else {
        current_root
    };
    let mut next = next;
    if changing || old.library_dir.is_some() {
        next.library_dir = Some(root.clone());
    }
    if next.save(&paths.preferences()).is_err() {
        return false;
    }
    actor().run(move |state| {
        let Some(s) = state.storage_mut() else {
            return false;
        };
        s.prefs = next;
        if changing {
            s.library_root = root;
            s.library = library;
            s.library_error = None;
        }
        true
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
    // What the file holds, established here off the actor and from the same
    // bytes the document was parsed from. A save from this session checks
    // against it before it replaces them.
    //
    // `blank_if_empty` and the empty-parse fallback above both leave the
    // document saying something the file does not; that is a difference between
    // the document and the disk, which is what `dirty` is for, and it changes
    // nothing about what is *on* the disk.
    let disk = DiskState::recorded(&path, &source);
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
                session.set_disk_state(Some(disk));
            }
            if let Some(storage) = state.storage_mut() {
                storage.library.add(&path);
                storage.library.opened(&id);
            }
            hydrate_pins(state, handle, &id);
            watch(state, handle, &path);
            restart_journal(state, handle, &source, Restart::Fresh);
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
    // The session leaves the old file's entry as well: left marked open, it
    // would be a script for the next launch to come back to.
    let left = state.session_mut(handle).map(|session| {
        let old_id = session.id().map(str::to_owned);
        session.set_file(path.clone(), id.clone());
        (old_id, session.scroll_row())
    });
    if let (Some(storage), Some((old_id, scroll_row))) = (state.storage_mut(), left) {
        if let Some(old_id) = old_id.filter(|old_id| *old_id != id) {
            storage.library.closed(&old_id, scroll_row);
        }
        storage.library.add(&path);
        storage.library.opened(&id);
        storage.library.set_scroll(&id, scroll_row);
    }
    hydrate_pins(state, handle, &id);
    watch(state, handle, &path);
}

pub(super) fn hydrate_pins(state: &mut AppState, handle: u64, id: &str) {
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
///
/// Returns whether the session came away journalled. **Every** way of coming
/// away without one — no state directory, a name held by a pending recovery, a
/// journal directory that is full or unwritable — leaves the session marked
/// unprotected and pushes `JournalBroken`, because they all have the same
/// consequence for the writer: from here, nothing typed is being recorded. The
/// failures used to be dropped with an `.ok()`, which left the session looking
/// ordinary while the crash protection it advertises was not there at all.
///
/// A failure never fails the *open*. The editor still works, the file still
/// saves, and the difference is the last few seconds — which is the writer's to
/// know about, not the core's to decide by refusing to open their script.
fn restart_journal(state: &mut AppState, handle: u64, base: &str, restart: Restart) -> bool {
    let Some(storage) = state.storage() else {
        // No state directory at all: `init` never found or was never given one,
        // so there is nowhere to journal into and there never will be.
        return unprotected(state, handle);
    };
    let directory = storage.paths.journal_dir();
    let Some(session) = state.session(handle) else {
        return false;
    };
    let (id, script) = match session.path() {
        Some(path) => (journal::script_id(path), path.to_path_buf()),
        None => (
            format!("untitled-{}-{handle}", std::process::id()),
            PathBuf::new(),
        ),
    };
    let started = match restart {
        Restart::Fresh => Journal::create(&directory, &id, &script, base),
        Restart::Rebased => match state.session_mut(handle).and_then(Session::journal_mut) {
            Some(journal) => journal.replace(&script, base),
            // An unprotected session has no ownership of an existing journal.
            None => Journal::create(&directory, &id, &script, base),
        },
    };
    match started {
        Ok(journal) => {
            if let Some(session) = state.session_mut(handle) {
                session.set_journal(Some(journal));
            }
            true
        }
        // `AlreadyExists` is the one that is not a fault: the journal name
        // belongs to a crashed session whose records nobody has decided about
        // yet, so this session gets none rather than erasing them. The rest are
        // the disk saying no. They are reported identically because the writer's
        // question is the same either way.
        Err(_) => unprotected(state, handle),
    }
}

/// Marks a session as one that is not being recorded, and tells Dart once.
///
/// Always returns `false`, so that it reads as the "no journal" answer at the
/// call sites that return it.
fn unprotected(state: &mut AppState, handle: u64) -> bool {
    if let Some(session) = state.session_mut(handle) {
        session.set_journal_unavailable();
        emit(CoreEvent::JournalBroken { handle });
    }
    false
}

/// Whether a restart may take over a journal file that already exists.
///
/// The distinction is [`Journal::create`]'s, and it is here because both answers
/// have a caller: a session that is *starting* has no claim on a journal already
/// on disk, and a session that is *rebasing* one it already holds does.
enum Restart {
    /// An open, a create, or a recovery declined into an ordinary session. The
    /// name must be free; a file there is a pending recovery.
    Fresh,
    /// A reload or a restore from backup. The document has just been replaced by
    /// bytes that are on disk, so the records this session's journal holds
    /// describe something that no longer exists.
    Rebased,
}

/// Starts reporting external changes to a session's file, and says so when it
/// cannot.
///
/// The two ways it cannot are the same one from the writer's side: `notify`
/// never started (no inotify, no descriptors left, `init` found no storage), or
/// this particular directory would not take a watch. Both used to be discarded
/// — the constructor into an `.ok()` and this call into a `let _` — and the
/// result was an application that went on offering §Phase 4's
/// external-modification protection in its documentation and not in its
/// behaviour, with nothing anywhere saying which of the two you had.
///
/// It never fails the open, for [`restart_journal`]'s reason: what has been lost
/// is a warning, and the writer's script is not worth less without it.
fn watch(state: &mut AppState, handle: u64, path: &Path) {
    let watching = state
        .storage_mut()
        .and_then(|storage| storage.watcher.as_mut())
        .is_some_and(|watcher| watcher.watch(path).is_ok());
    if let Some(session) = state.session_mut(handle) {
        // News only the first time, so a Save As in an unwatchable directory
        // does not say it again for every save that follows.
        if session.set_watching(watching) && !watching {
            emit(CoreEvent::ExternalWatchUnavailable { handle });
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
        project_id: entry.project_id.clone(),
        archived: entry.archived,
        problem: entry.problem.clone(),
        migration_status: entry.migration_status.clone(),
    }
}

fn prefs_view(preferences: &CorePreferences) -> PreferencesView {
    PreferencesView {
        autosave_enabled: preferences.autosave_enabled,
        autocomplete_enabled: preferences.autocomplete_enabled,
        navigator_visible: preferences.navigator_visible,
        spell_enabled: preferences.spell_enabled,
        spell_language: preferences.spell_language.clone(),
        appearance: preferences.appearance.clone(),
        editor_text_size: preferences.editor_text_size,
        default_paper: preferences.default_paper.clone(),
        scene_numbers: preferences.scene_numbers.clone(),
        bold_scene_headings: preferences.bold_scene_headings,
        number_first_page: preferences.number_first_page,
        pdf_font_path: preferences
            .pdf_font_path
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned()),
        distraction_free: preferences.distraction_free,
        page_view: preferences.page_view,
        autosave_idle_ms: preferences.autosave_idle_ms,
        autosave_interval_ms: preferences.autosave_interval_ms,
        backup_dir: preferences
            .backup_dir
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned()),
        library_dir: preferences
            .library_dir
            .as_ref()
            .map(|p| p.to_string_lossy().into_owned()),
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
    use std::os::unix::fs::MetadataExt;
    if let (Ok(a), Ok(b)) = (std::fs::metadata(one), std::fs::metadata(other)) {
        if a.dev() == b.dev() && a.ino() == b.ino() {
            return true;
        }
    }
    match (one.canonicalize(), other.canonicalize()) {
        (Ok(one), Ok(other)) => one == other,
        _ => false,
    }
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
    use slugline_storage::library::PinnedEntity;

    use std::fs;
    use std::future::Future;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::sync::mpsc::{self, Receiver, Sender};
    use std::sync::{Mutex, MutexGuard};
    use std::task::{Context, Poll, Waker};
    use std::thread;
    use std::time::Duration;

    use crate::api::doc::{
        doc_apply, doc_blocks, doc_close, doc_line_break, doc_redo, doc_source, doc_undo,
        DocPosition, DocSelection, EditCommand, EditOutcome,
    };

    const SCRIPT: &str = "The house is quiet.\n";
    #[test]
    fn managed_initialization_resolves_root_alias_before_open_and_save() {
        let it = Fixture::open("init-root-alias");
        doc_close(it.handle);
        let paths = Paths::under(&it.root);
        let alias = it.root.join("linked-library");
        std::os::unix::fs::symlink(paths.default_library(), &alias).unwrap();
        let preferences = CorePreferences {
            library_dir: Some(alias.clone()),
            ..CorePreferences::default()
        };
        preferences.save(&paths.preferences()).unwrap();
        assert!(block_on(init(
            paths.config_dir().to_string_lossy().into_owned(),
            paths.data_dir().to_string_lossy().into_owned(),
            paths.state_dir().to_string_lossy().into_owned(),
        )));
        assert_eq!(
            library_status().path,
            paths
                .default_library()
                .canonicalize()
                .unwrap()
                .to_string_lossy()
        );
        let project_name = it.script.parent().unwrap().file_name().unwrap();
        let alias_script = alias.join(project_name).join("script.fountain");
        let handle = block_on(library_open(alias_script.to_string_lossy().into_owned())).unwrap();
        let block = doc_blocks(handle, 0, 1)[0].id;
        doc_apply(
            handle,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: "Alias. ".into(),
            },
            None,
        );
        assert!(matches!(
            block_on(doc_save(handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(
            fs::read_to_string(&it.script).unwrap(),
            "Alias. The house is quiet.\n"
        );
        doc_close(handle);
    }
    #[test]
    fn managed_root_switch_is_durable_and_unavailable_roots_never_recreate() {
        let it = Fixture::open("root-switch");
        it.types("Kept. ");
        let text = it.in_memory();
        let old_root = Paths::under(&it.root).default_library().to_path_buf();
        let old_bytes = it.on_disk();
        let next = it.root.join("another-library");
        let mut prefs = prefs_get();
        prefs.library_dir = Some(next.to_string_lossy().into_owned());
        assert!(block_on(prefs_set(prefs)));
        assert_eq!(library_status().path, next.to_string_lossy());
        assert!(block_on(library_list()).is_empty());
        let result = block_on(doc_save(it.handle));
        assert!(matches!(
            result,
            SaveOutcome::Failed {
                failure: SaveFailure::LibraryDestination,
                ..
            }
        ));
        assert_eq!(it.on_disk(), old_bytes);
        assert_eq!(it.in_memory(), text);
        assert!(it.dirty());
        fs::remove_dir(&next).unwrap();
        assert!(block_on(library_create("No fallback".into())).is_none());
        assert!(!next.exists());
        let rescue = it.root.join("rescue.fountain");
        assert!(matches!(
            block_on(doc_export_fountain(
                it.handle,
                rescue.to_string_lossy().into_owned(),
                false
            )),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(fs::read_to_string(rescue).unwrap(), text);
        let mut prefs = prefs_get();
        prefs.library_dir = Some(old_root.to_string_lossy().into_owned());
        assert!(block_on(prefs_set(prefs)));
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), text);
    }
    #[test]
    fn managed_future_metadata_can_be_rescued_and_migration_history_failure_is_partial() {
        let it = Fixture::open("damage-rescue");
        doc_close(it.handle);
        let root = Paths::under(&it.root).default_library().to_path_buf();
        let project = project::resolve(&root, &it.script).unwrap();
        let meta_path = project.directory.join("project.json");
        let original = fs::read_to_string(&meta_path).unwrap();
        fs::write(
            &meta_path,
            original.replace("\"version\": 1", "\"version\": 99"),
        )
        .unwrap();
        let entry = block_on(library_list())
            .into_iter()
            .find(|e| Path::new(&e.path) == it.script)
            .unwrap();
        assert!(entry.problem.is_some());
        assert!(!block_on(library_repair(entry.id.clone())));
        let target = it.root.join("rescued.fountain");
        assert!(matches!(
            block_on(library_rescue(
                entry.id,
                target.to_string_lossy().into_owned(),
                false
            )),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(fs::read_to_string(&target).unwrap(), SCRIPT);
        fs::write(&meta_path, original).unwrap();
        let source = it.root.join("old.fountain");
        fs::write(&source, SCRIPT).unwrap();
        let mut legacy = Library::default();
        let id = legacy.add(&source);
        let entry = legacy.get(&id).unwrap().clone();
        actor().run(move |state| state.storage_mut().unwrap().legacy.push(entry));
        let legacy_versions = Paths::under(&it.root).backup_dir().join(&id);
        fs::create_dir_all(&legacy_versions).unwrap();
        fs::write(legacy_versions.join("2.fountain"), b"second\n").unwrap();
        std::os::unix::fs::symlink(&source, legacy_versions.join("1.fountain")).unwrap();
        let partial = block_on(library_migrate(id.clone()));
        assert!(!partial.complete);
        let imported = partial.project.unwrap();
        assert!(imported.migration_status.is_some());
        assert_eq!(fs::read_to_string(&imported.path).unwrap(), SCRIPT);
        fs::remove_file(legacy_versions.join("1.fountain")).unwrap();
        fs::write(legacy_versions.join("1.fountain"), b"first\n").unwrap();
        let retry = block_on(library_migrate(id));
        assert!(retry.complete, "{}", retry.message);
        assert_eq!(retry.project.unwrap().project_id, imported.project_id);
        assert_eq!(fs::read_to_string(source).unwrap(), SCRIPT);
    }

    #[test]
    fn managed_read_only_import_is_exact_isolated_and_reopens_with_versions() {
        let it = Fixture::open("import-isolation");
        let source = it.root.join("read-only.fountain");
        let raw = "\u{feff}Title: My Case\r\nX-Unknown: untouched  \r\n\r\nInt. Library - Day\r\n\r\nAuthored words.  \r\n\r\n/* unknown */\r\n";
        fs::write(&source, raw).unwrap();
        fs::set_permissions(&source, fs::Permissions::from_mode(0o444)).unwrap();
        assert!(block_on(library_open(source.to_string_lossy().into_owned())).is_none());
        let FdxImportOutcome::Imported { handle, .. } =
            prepare_import(source.to_string_lossy().into_owned())
        else {
            panic!("UTF8 candidate")
        };
        assert!(doc_path(handle).is_none());
        let SaveOutcome::Saved { path, .. } = commit_project(handle) else {
            panic!("publication")
        };
        assert_eq!(fs::read(&path).unwrap(), raw.as_bytes());
        let block = doc_blocks(handle, 0, u32::MAX)
            .iter()
            .find(|b| b.kind == crate::api::doc::BlockKind::Action)
            .unwrap()
            .id;
        doc_apply(
            handle,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: "Changed. ".into(),
            },
            None,
        );
        let expected = doc_source(handle);
        assert!(matches!(
            block_on(doc_autosave(handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(fs::read(&source).unwrap(), raw.as_bytes());
        assert!(Path::new(&path).parent().unwrap().join("versions").is_dir());
        let versions = block_on(backups_list(handle));
        assert!(versions
            .iter()
            .any(|v| fs::read(&v.path).unwrap() == raw.as_bytes()));
        doc_close(handle);
        let reopened = block_on(library_open(path)).unwrap();
        assert_eq!(doc_source(reopened), expected);
        doc_close(reopened);
        assert_eq!(fs::read(&source).unwrap(), raw.as_bytes());
    }

    #[test]
    fn managed_metadata_survives_cache_loss_rename_active_duplicate_and_archive() {
        let it = Fixture::open("portable-metadata");
        let id = journal::script_id(&it.script);
        actor().run({
            let id = id.clone();
            move |state| state.storage_mut().unwrap().library.set_scroll(&id, 42)
        });
        let root = Paths::under(&it.root).default_library().to_path_buf();
        let original = project::resolve(&root, &it.script).unwrap();
        let mut meta = original.metadata.clone();
        meta.pinned_entities.push(PinnedEntity {
            kind: "character".into(),
            value: "ALICE".into(),
        });
        project::update(&original, &meta).unwrap();
        let before_journal = fs::read(it.journal_path()).unwrap();
        it.types("Unsaved. ");
        let undo = doc_undo(it.handle).unwrap();
        doc_redo(it.handle).unwrap();
        assert!(!undo.changed.is_empty());
        let expected = it.in_memory();
        let journal = fs::read(it.journal_path()).unwrap();
        assert!(matches!(
            block_on(library_rename(id.clone(), "Renamed / 🌍".into())),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(fs::read(it.journal_path()).unwrap(), journal);
        assert_eq!(it.on_disk(), SCRIPT);
        let duplicated = block_on(library_duplicate(id.clone())).unwrap();
        let duplicate = project::resolve(&root, Path::new(&duplicated.path)).unwrap();
        assert_ne!(duplicate.metadata.id, original.metadata.id);
        assert_eq!(fs::read_to_string(duplicate.script()).unwrap(), expected);
        assert_eq!(duplicate.metadata.pinned_entities, meta.pinned_entities);
        assert!(it.dirty());
        assert_eq!(it.in_memory(), expected);
        assert_ne!(before_journal, journal);
        assert!(
            !block_on(library_archive(id.clone(), true, None)),
            "open editor must resolve close first"
        );
        assert!(block_on(library_archive(id.clone(), true, Some(it.handle))));
        doc_close(it.handle);
        fs::remove_file(Paths::under(&it.root).library_index()).unwrap();
        install_storage(&it.root);
        let entries = block_on(library_list());
        let row = entries.iter().find(|e| e.id == id).unwrap();
        assert!(row.archived);
        assert_eq!(row.title, "Renamed / 🌍");
        let reread = project::read(it.script.parent().unwrap()).unwrap();
        assert_eq!(reread.metadata.pinned_entities, meta.pinned_entities);
        assert_eq!(reread.metadata.id, original.metadata.id);
        assert!(block_on(library_open(it.script.to_string_lossy().into_owned())).is_none());
        assert!(block_on(library_archive(id, false, None)));
        let h = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        doc_close(h);
    }

    #[test]
    fn managed_closed_contents_and_alias_exports_are_protected_but_origin_is_confirmable() {
        use std::os::unix::fs::symlink;
        let it = Fixture::open("export-guards");
        let other = it.beside("closed");
        let target = other.script.clone();
        drop(other);
        let alias = it.root.join("alias.fountain");
        symlink(&target, &alias).unwrap();
        let hard = it.root.join("hard.fountain");
        fs::hard_link(&target, &hard).unwrap();
        for path in [
            target.clone(),
            alias,
            hard,
            target.parent().unwrap().join("project.json"),
            target.parent().unwrap().join("versions/new.fountain"),
        ] {
            let result = block_on(doc_export_fountain(
                it.handle,
                path.to_string_lossy().into_owned(),
                true,
            ));
            assert_eq!(failure_of_outcome(&result), SaveFailure::LibraryDestination);
        }
        assert_eq!(fs::read_to_string(target).unwrap(), SCRIPT);
        let origin = it.root.join("origin.fountain");
        fs::write(&origin, "Original\n").unwrap();
        assert_eq!(
            failure_of_outcome(&block_on(doc_export_fountain(
                it.handle,
                origin.to_string_lossy().into_owned(),
                false
            ))),
            SaveFailure::AlreadyExists
        );
        it.types("Copy. ");
        let text = it.in_memory();
        assert!(matches!(
            block_on(doc_export_fountain(
                it.handle,
                origin.to_string_lossy().into_owned(),
                true
            )),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(fs::read_to_string(origin).unwrap(), text);
        assert!(it.dirty());
        assert_eq!(it.on_disk(), SCRIPT);
    }

    #[test]
    fn managed_selective_migration_is_exact_resumable_and_preserves_legacy_evidence() {
        let it = Fixture::open("migration");
        let paths = Paths::under(&it.root);
        let source = it.root.join("legacy.fountain");
        let raw = "\u{feff}Title: Legacy\r\n\r\nText.  \r\n";
        fs::write(&source, raw).unwrap();
        let mut legacy_library = Library::default();
        let legacy_key = legacy_library.add(&source);
        let mut legacy = legacy_library.get(&legacy_key).unwrap().clone();
        legacy.title = "Legacy label".into();
        legacy.scroll_row = 29;
        legacy.pinned_entities = vec![PinnedEntity {
            kind: "character".into(),
            value: "LEGACY".into(),
        }];
        let id = legacy.id.clone();
        actor().run(move |state| state.storage_mut().unwrap().legacy.push(legacy));
        let history = paths.backup_dir().join(&id);
        fs::create_dir_all(&history).unwrap();
        fs::write(history.join("1.fountain"), b"\xef\xbb\xbfOld.  \r\n").unwrap();
        fs::write(history.join("unknown.txt"), b"retained").unwrap();
        let first = block_on(library_migrate(id.clone()));
        assert!(first.complete, "{}", first.message);
        let imported = first.project.unwrap();
        assert_eq!(fs::read(&imported.path).unwrap(), raw.as_bytes());
        assert_eq!(imported.scroll_row, 29);
        assert_eq!(imported.title, "Legacy label");
        let project = project::read(Path::new(&imported.path).parent().unwrap()).unwrap();
        assert_eq!(project.metadata.pinned_entities[0].value, "LEGACY");
        assert_eq!(
            fs::read(project.versions().join("1.fountain")).unwrap(),
            b"\xef\xbb\xbfOld.  \r\n"
        );
        let retry = block_on(library_migrate(id.clone()));
        assert!(retry.complete);
        assert_eq!(retry.project.unwrap().project_id, imported.project_id);
        assert_eq!(fs::read(&source).unwrap(), raw.as_bytes());
        assert!(history.join("unknown.txt").exists());
        let bad = project.versions().join("2.fountain");
        fs::write(&bad, b"current collision").unwrap();
        fs::write(history.join("2.fountain"), b"different legacy").unwrap();
        assert!(block_on(library_migrate(id.clone())).complete);
        assert_eq!(fs::read(bad).unwrap(), b"current collision");
        assert_eq!(
            fs::read(project.versions().join("3.fountain")).unwrap(),
            b"different legacy"
        );
        assert!(block_on(library_migrate(id)).complete);
    }

    #[test]
    fn managed_legacy_recovery_cancel_live_owner_failure_and_retry_preserve_text() {
        let it = Fixture::open("legacy-recovery-migration");
        let external = it.root.join("legacy.fountain");
        fs::write(&external, SCRIPT).unwrap();
        let old = open_source(external.clone(), SCRIPT.into(), false);
        let block = doc_blocks(old, 0, 1)[0].id;
        doc_apply(
            old,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: "Recovered. ".into(),
            },
            None,
        );
        let expected = doc_source(old);
        let predecessor =
            actor().run(move |state| state.session(old.id).unwrap().journal_path().unwrap());
        assert!(matches!(
            block_on(recovery_accept(predecessor.to_string_lossy().into_owned())),
            RecoveryOutcome::Failed { .. }
        ));
        actor().run(move |state| {
            state.session_mut(old.id).unwrap().set_journal(None);
            state.close(old.id);
        });
        let old_bytes = fs::read(&predecessor).unwrap();
        let RecoveryOutcome::Recovered { handle: cancel } =
            block_on(recovery_accept(predecessor.to_string_lossy().into_owned()))
        else {
            panic!("candidate")
        };
        assert!(doc_path(cancel).is_none());
        doc_close(cancel);
        assert_eq!(fs::read(&predecessor).unwrap(), old_bytes);
        let RecoveryOutcome::Recovered { handle } =
            block_on(recovery_accept(predecessor.to_string_lossy().into_owned()))
        else {
            panic!("candidate")
        };
        assert_eq!(doc_source(handle), expected);
        let root = Paths::under(&it.root).default_library().to_path_buf();
        let candidate =
            actor().run(move |state| state.session(handle.id).unwrap().candidate.clone().unwrap());
        let mut metadata = candidate.metadata.clone();
        metadata.unknown.insert(
            "recovery_predecessor".into(),
            predecessor.to_string_lossy().into_owned().into(),
        );
        let published = project::create(&root, metadata, expected.as_bytes(), None).unwrap();
        // A live successor must refuse migration; candidate and predecessor remain recoverable.
        let directory = Paths::under(&it.root).journal_dir();
        let key = journal::script_id(&published.script());
        let live = Journal::create(&directory, &key, &published.script(), &expected).unwrap();
        assert!(matches!(commit_project(handle), SaveOutcome::Failed { .. }));
        assert_eq!(fs::read(&predecessor).unwrap(), old_bytes);
        assert_eq!(fs::read_to_string(&external).unwrap(), SCRIPT);
        drop(live); // Abandoned empty checkpoint is safe to reacquire, never a live journal.
        assert!(matches!(commit_project(handle), SaveOutcome::Saved { .. }));
        assert!(!predecessor.exists());
        assert_eq!(
            doc_path(handle).as_deref(),
            Some(published.script().to_str().unwrap())
        );
        assert_eq!(
            project::scan(&root).unwrap().len(),
            2,
            "retry did not create a duplicate"
        );
        doc_close(handle);
        let reopened = block_on(library_open(
            published.script().to_string_lossy().into_owned(),
        ))
        .unwrap();
        assert_eq!(doc_source(reopened), expected);
        doc_close(reopened);
        assert_eq!(fs::read_to_string(external).unwrap(), SCRIPT);
    }

    #[test]
    fn line_break_save_and_recovery_replay_keep_the_exact_outcome() {
        let source = "\u{feff}Title: Break\r\n\r\nFirst line.\r\n\r\n/* untouched */\r\n";
        let it = Fixture::open_source("line-break", source);
        let block = doc_blocks(it.handle, 0, 1)[0].id;
        let at = DocPosition {
            block,
            offset_utf16: 5,
        };
        let selection = DocSelection {
            anchor: at,
            focus: at,
        };
        assert!(matches!(
            doc_line_break(it.handle, selection),
            EditOutcome::Applied { .. }
        ));
        let edited = it.in_memory();
        assert!(edited.contains("First\r\n line."));
        assert!(edited.starts_with("\u{feff}Title: Break\r\n\r\n"));
        assert!(edited.ends_with("/* untouched */\r\n"));
        assert_eq!(it.journalled(), 1, "one patch, despite a grouped edit");
        assert_eq!(it.recovers_to(), edited);
        assert_eq!(it.on_disk(), source, "editing has not saved the file");

        doc_undo(it.handle).unwrap();
        assert_eq!(it.in_memory(), source);
        assert_eq!(it.recovers_to(), source);
        doc_redo(it.handle).unwrap();
        assert_eq!(it.recovers_to(), edited);

        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), edited);
        assert!(!it.dirty());
        assert_eq!(it.recovers_to(), edited);
        assert!(it.journal_agrees_with_the_file());
    }

    #[test]
    fn omission_save_reopen_restore_and_journal_replay_conserve_body_and_title() {
        use crate::api::doc::{doc_close, doc_omit_selection, doc_restore_omitted, BlockKind};
        let source =
            "\u{feff}Title: Omission\r\n\r\n@BOB\r\nBefore 😀 café */ after.\r\n\r\nLast.\r\n";
        let mut it = Fixture::open_source("omission", source);
        let body = doc_blocks(it.handle, 0, u32::MAX);
        let original_title = crate::api::doc::doc_title_page(it.handle);
        let at = DocSelection {
            anchor: DocPosition {
                block: body[1].id,
                offset_utf16: 7,
            },
            focus: DocPosition {
                block: body[1].id,
                offset_utf16: 17,
            },
        };
        let EditOutcome::Applied { result } = doc_omit_selection(it.handle, at) else {
            panic!("omit applies");
        };
        let comment = result.selection.unwrap();
        let omitted_source = it.in_memory();
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), omitted_source);
        assert_eq!(it.on_disk(), source);
        assert_eq!(doc_undo(it.handle).unwrap().selection, Some(at));
        assert_eq!(it.in_memory(), source);
        assert_eq!(it.recovers_to(), source);
        assert_eq!(doc_redo(it.handle).unwrap().selection, Some(comment));
        assert_eq!(it.recovers_to(), omitted_source);
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), omitted_source);
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(it.in_memory(), omitted_source);
        let blocks = doc_blocks(it.handle, 0, u32::MAX);
        let omitted = blocks
            .iter()
            .find(|block| block.kind == BlockKind::Opaque)
            .unwrap();
        let position = DocPosition {
            block: omitted.id,
            offset_utf16: 3,
        };
        let selected_comment = DocSelection {
            anchor: position,
            focus: position,
        };
        assert!(matches!(
            doc_restore_omitted(it.handle, selected_comment),
            EditOutcome::Applied { .. }
        ));
        let restored = it.in_memory();
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), restored);
        assert_eq!(crate::api::doc::doc_title_page(it.handle), original_title);
        let restored_body = doc_blocks(it.handle, 0, u32::MAX);
        assert_eq!(
            restored_body
                .iter()
                .map(|block| (&block.text, block.kind, block.forced, block.dual))
                .collect::<Vec<_>>(),
            body.iter()
                .map(|block| (&block.text, block.kind, block.forced, block.dual))
                .collect::<Vec<_>>()
        );
        assert_eq!(
            doc_undo(it.handle).unwrap().selection,
            Some(selected_comment)
        );
        assert_eq!(it.in_memory(), omitted_source);
        assert_eq!(it.recovers_to(), omitted_source);
        doc_redo(it.handle).unwrap();
        assert_eq!(it.recovers_to(), restored);
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), restored);
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(
            doc_blocks(it.handle, 0, u32::MAX)
                .iter()
                .map(|block| (&block.text, block.kind))
                .collect::<Vec<_>>(),
            body.iter()
                .map(|block| (&block.text, block.kind))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn omitted_unicode_is_offered_accepted_and_restored_after_checkpoint_and_redo() {
        use crate::api::doc::{doc_close, doc_omit_selection, doc_restore_omitted, BlockKind};

        for (source, selected, from, to, left_kind) in [
            (
                "\u{feff}Title: Recovery\r\n\r\n@BOB\r\nHello 😀 café friend.\r\n",
                1,
                9,
                13,
                BlockKind::Dialogue,
            ),
            (
                "\u{feff}Title: Recovery\r\n\r\nINT. ROOM - DAY\r\n\r\nOutside.\r\n",
                0,
                5,
                9,
                BlockKind::SceneHeading,
            ),
        ] {
            for checkpoint in [false, true] {
                let mut it = Fixture::open_source("omission-accepted-recovery", source);
                let body = doc_blocks(it.handle, 0, u32::MAX);
                let selection = DocSelection {
                    anchor: DocPosition {
                        block: body[selected].id,
                        offset_utf16: to,
                    },
                    focus: DocPosition {
                        block: body[selected].id,
                        offset_utf16: from,
                    },
                };
                let EditOutcome::Applied { result } = doc_omit_selection(it.handle, selection)
                else {
                    panic!("Unicode omission applies");
                };
                let comment = result.selection.unwrap();
                let omitted = it.in_memory();
                if checkpoint {
                    let live_identity = actor().run(move |state| {
                        let document = state.session(it.handle.id).unwrap().document();
                        (
                            document.blocks().to_vec(),
                            document.revision(),
                            document.can_undo(),
                            document.can_redo(),
                        )
                    });
                    assert!(matches!(
                        block_on(doc_save(it.handle)),
                        SaveOutcome::Saved { .. }
                    ));
                    assert_eq!(
                        actor().run(move |state| {
                            let document = state.session(it.handle.id).unwrap().document();
                            (
                                document.blocks().to_vec(),
                                document.revision(),
                                document.can_undo(),
                                document.can_redo(),
                            )
                        }),
                        live_identity,
                        "checkpoint translation must preserve live identities, provenance, pins and history"
                    );
                }
                assert!(matches!(
                    doc_restore_omitted(it.handle, comment),
                    EditOutcome::Applied { .. }
                ));
                doc_undo(it.handle).unwrap();
                doc_redo(it.handle).unwrap();
                doc_undo(it.handle).unwrap();
                assert_eq!(it.in_memory(), omitted);

                // Release the journal without discarding it and lose the session,
                // reproducing the state a new process admits through the real API.
                let old_handle = it.handle;
                let journal_path = actor().run(move |state| {
                    let session = state.session_mut(old_handle.id).unwrap();
                    let path = session.journal_mut().unwrap().path().to_path_buf();
                    session.set_journal(None);
                    state.close(old_handle.id);
                    path
                });
                let offer = block_on(recovery_pending())
                    .into_iter()
                    .find(|offer| Path::new(&offer.journal) == journal_path)
                    .expect("the omission is offered for recovery");
                assert!(offer.blocked.is_none());
                let RecoveryOutcome::Recovered { handle } =
                    block_on(recovery_accept(offer.journal))
                else {
                    panic!("omission history is accepted without losing its seams");
                };
                it.handle = handle;
                assert_eq!(it.in_memory(), omitted);
                assert!(doc_undo(handle).is_none());
                let recovered = doc_blocks(handle, 0, u32::MAX);
                assert_eq!(recovered[selected].kind, left_kind);
                assert_eq!(recovered.last().unwrap().kind, BlockKind::Action);
                let comment = recovered
                    .iter()
                    .find(|b| b.kind == BlockKind::Opaque)
                    .unwrap();
                let at = DocPosition {
                    block: comment.id,
                    offset_utf16: 0,
                };
                assert!(matches!(
                    doc_restore_omitted(
                        handle,
                        DocSelection {
                            anchor: at,
                            focus: at
                        }
                    ),
                    EditOutcome::Applied { .. }
                ));
                assert_eq!(it.in_memory(), source);
                assert!(matches!(
                    block_on(doc_save(handle)),
                    SaveOutcome::Saved { .. }
                ));
                assert_eq!(fs::read(&it.script).unwrap(), source.as_bytes());
                doc_close(handle);
                it.handle =
                    block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
                assert_eq!(it.in_memory(), source);
                assert_eq!(doc_blocks(it.handle, 0, u32::MAX)[selected].kind, left_kind);
            }
        }
    }

    #[test]
    fn a_late_omission_restore_refusal_does_not_append_a_partial_journal_outcome() {
        use crate::api::doc::{doc_restore_omitted, EditRejection};
        let source = "/*\nSlugline omission v99\n*/\n\n/*\n!Editable after restoration\n*/\n";
        let it = Fixture::open_source("omission-refused", source);
        let blocks = doc_blocks(it.handle, 0, u32::MAX);
        let selection = DocSelection {
            anchor: DocPosition {
                block: blocks[0].id,
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: blocks[1].id,
                offset_utf16: blocks[1].text.len() as u32,
            },
        };
        assert!(matches!(
            doc_restore_omitted(it.handle, selection),
            EditOutcome::Rejected {
                reason: EditRejection::CannotRestoreOmission,
                ..
            }
        ));
        assert_eq!(it.in_memory(), source);
        assert_eq!(it.recovers_to(), source);
        assert_eq!(it.journalled(), 0);
        assert!(!it.dirty());
        assert!(doc_undo(it.handle).is_none());
        assert!(doc_redo(it.handle).is_none());
    }

    #[test]
    fn whole_scene_omission_survives_checkpoint_recovery_and_grouped_restore() {
        use crate::api::doc::{doc_close, doc_omit_scene, doc_restore_omitted, BlockKind};
        let source = "Title: Scene witness\n\nINT. ROOM - DAY #12A#\n\nBOB\nFirst 😀.\n\nMARY ^\nSecond café.\n\n/* old /* nested */ comment */\n\nEXT. NEXT - NIGHT #13#\n\nUntouched.\n";
        let mut it = Fixture::open_source("omitted-scene", source);
        let before = doc_blocks(it.handle, 0, u32::MAX);
        let at = DocSelection {
            anchor: DocPosition {
                block: before[2].id,
                offset_utf16: 2,
            },
            focus: DocPosition {
                block: before[2].id,
                offset_utf16: 2,
            },
        };
        let EditOutcome::Applied { result } = doc_omit_scene(it.handle, at) else {
            panic!("scene omission applies");
        };
        let comment = result.selection.unwrap();
        let omitted_source = it.in_memory();
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), omitted_source);
        assert_eq!(doc_undo(it.handle).unwrap().selection, Some(at));
        assert_eq!(it.in_memory(), source);
        assert!(doc_undo(it.handle).is_none());
        assert_eq!(doc_redo(it.handle).unwrap().selection, Some(comment));
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), omitted_source);
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        let blocks = doc_blocks(it.handle, 0, u32::MAX);
        let position = DocPosition {
            block: blocks
                .iter()
                .find(|block| block.kind == BlockKind::Opaque)
                .unwrap()
                .id,
            offset_utf16: 0,
        };
        let selected = DocSelection {
            anchor: position,
            focus: position,
        };
        assert!(matches!(
            doc_restore_omitted(it.handle, selected),
            EditOutcome::Applied { .. }
        ));
        let restored = it.in_memory();
        let actual = doc_blocks(it.handle, 0, u32::MAX);
        assert_eq!(
            actual
                .iter()
                .map(|block| (&block.text, block.kind, block.dual))
                .collect::<Vec<_>>(),
            before
                .iter()
                .map(|block| (&block.text, block.kind, block.dual))
                .collect::<Vec<_>>(),
        );
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), restored);
        assert_eq!(doc_undo(it.handle).unwrap().selection, Some(selected));
        assert_eq!(it.recovers_to(), omitted_source);
        assert!(doc_undo(it.handle).is_none());
        doc_redo(it.handle).unwrap();
        assert_eq!(it.recovers_to(), restored);
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        let reopened = doc_blocks(it.handle, 0, u32::MAX);
        assert_eq!(
            reopened
                .iter()
                .map(|block| (&block.text, block.kind, block.dual))
                .collect::<Vec<_>>(),
            before
                .iter()
                .map(|block| (&block.text, block.kind, block.dual))
                .collect::<Vec<_>>(),
        );
    }

    #[test]
    fn clean_markers_checkpoint_a_replayable_base_without_changing_live_pins() {
        let source =
            "INT. HOUSE - DAY\n\nShe waits.\n\nMARY ^\nHello.\n\nCUT TO:\n\n!\n\nLast action.\n";
        let it = Fixture::open_source("clean-markers", source);
        let before = doc_blocks(it.handle, 0, u32::MAX);
        for block in &before {
            assert!(matches!(
                doc_apply(
                    it.handle,
                    EditCommand::SetKind {
                        block: block.id,
                        kind: block.kind,
                        section_level: block.section_level,
                        forced: true,
                    },
                    None,
                ),
                EditOutcome::Applied { .. }
            ));
        }
        let clean =
            "INT. HOUSE - DAY\n\nShe waits.\n\nMARY ^\nHello.\n\nCUT TO:\n\n!\n\nLast action.\n";
        assert_eq!(it.in_memory(), clean);
        let live = doc_blocks(it.handle, 0, u32::MAX);
        let identity = actor().run(move |state| {
            let session = state.session(it.handle.id).unwrap();
            (
                session.document() as *const model::Document as usize,
                session.document().revision(),
                session.document_generation(),
            )
        });
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), clean);
        assert_eq!(it.recovers_to(), clean);
        assert!(it.journal_agrees_with_the_file());
        assert_eq!(doc_blocks(it.handle, 0, u32::MAX), live);
        assert_eq!(
            actor().run(move |state| {
                let session = state.session(it.handle.id).unwrap();
                (
                    session.document() as *const model::Document as usize,
                    session.document().revision(),
                    session.document_generation(),
                )
            }),
            identity,
            "Save neither replaces the actor-owned Document nor changes its revision"
        );

        // The empty `!` still occupies its parsed ID: a patch for the final
        // Action must not target a different block after the checkpoint.
        let last = before.last().unwrap();
        assert!(matches!(
            doc_apply(
                it.handle,
                EditCommand::ReplaceText {
                    block: last.id,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "Recovered. ".to_owned(),
                },
                None,
            ),
            EditOutcome::Applied { .. }
        ));
        assert_eq!(
            it.recovers_to(),
            clean.replace("Last action.", "Recovered. Last action.")
        );
        assert_eq!(it.recovers_to(), it.in_memory());
        doc_undo(it.handle).unwrap();
        assert_eq!(it.recovers_to(), clean);
        doc_redo(it.handle).unwrap();
        assert_eq!(it.recovers_to(), it.in_memory());
    }

    #[test]
    fn a_new_script_starts_with_a_useful_valid_fountain_template() {
        let source = starter_source(Path::new("/scripts/The Long Road.fountain"));
        assert!(source.starts_with("Title: The Long Road\nCredit: Written by\nAuthor:"));
        let document = model::Document::parse(&source);
        assert!(!document.title_page().is_empty());
        assert_eq!(
            document.blocks()[0].kind(),
            slugline_document::BlockKind::SceneHeading
        );
    }

    #[test]
    fn phase_ten_imports_the_legacy_preferences_file_atomically() {
        let root = temp_root("legacy-preferences");
        let paths = Paths::under(&root);
        let expected = CorePreferences {
            appearance: prefs::APPEARANCE_DARK.to_owned(),
            editor_text_size: 19,
            ..CorePreferences::default()
        };
        expected.save(&paths.legacy_preferences()).unwrap();

        assert_eq!(load_preferences(&paths), expected);
        assert_eq!(CorePreferences::load(&paths.preferences()), expected);
        assert!(paths.legacy_preferences().exists());
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn preference_view_transports_both_heading_weights() {
        for bold_scene_headings in [false, true] {
            let preferences = CorePreferences {
                bold_scene_headings,
                ..CorePreferences::default()
            };
            assert_eq!(
                prefs_view(&preferences).bold_scene_headings,
                bold_scene_headings
            );
        }
    }

    #[test]
    fn preference_view_transports_first_page_numbering() {
        assert!(!prefs_view(&CorePreferences::default()).number_first_page);
        let preferences = CorePreferences {
            number_first_page: true,
            ..CorePreferences::default()
        };
        assert!(prefs_view(&preferences).number_first_page);
        assert!(preference_page_config(&preferences).number_first_page);
    }

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
            install_storage(&root);
            let script = seed_project(&root, label, source);
            let handle = block_on(library_open(script.to_string_lossy().into_owned()))
                .expect("the managed script opens");
            Fixture {
                _storage: storage,
                root,
                script,
                handle,
            }
        }

        fn beside(&self, label: &str) -> Sibling {
            let script = seed_project(&self.root, label, SCRIPT);
            let handle = block_on(library_open(script.to_string_lossy().into_owned()))
                .expect("the managed script opens");
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

        /// The file this session's journal covers. Exports leave it unchanged.
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

    /// Points the core's one `Storage` at a temporary root, with nothing open.
    /// What a fixture does before it opens a script, and what a test that is
    /// about the state directory itself needs on its own.
    ///
    /// The caller holds [`STORAGE`]: this replaces the storage every other test
    /// is using.
    fn seed_project(root: &Path, label: &str, source: &str) -> PathBuf {
        let paths = Paths::under(root);
        let library = project::root(paths.default_library(), true).unwrap();
        project::create(
            &library,
            Metadata::new(label.into()).unwrap(),
            source.as_bytes(),
            None,
        )
        .unwrap()
        .script()
    }

    fn install_storage(root: &Path) -> Paths {
        let paths = Paths::under(root);
        let library = Library::load(&paths.library_index());
        let storage_state = Storage {
            paths: paths.clone(),
            prefs: CorePreferences::default(),
            library,
            library_root: paths.default_library().to_path_buf(),
            library_error: None,
            legacy: Vec::new(),
            // No inotify: the watcher's own filtering is proved against real
            // events in `storage::watch`, and a watch descriptor per test would
            // be a slow way to find that out again. What these tests watch
            // instead is the register the watcher asks — which is the half the
            // save path owns.
            watcher: None,
            own_writes: OwnWrites::shared(),
            page_count_jobs: Default::default(),
            next_page_count_job: 0,
        };
        actor().run(move |state| state.set_storage(storage_state));
        paths
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

    /// What the next launch would be told to reopen: the index as it is on
    /// disk, read the way a new process reads it.
    fn session_on_disk(root: &Path) -> Vec<ScriptEntry> {
        Library::load(&Paths::under(root).library_index()).session()
    }

    /// What [`shutdown`] does, to one script. The real one ends every session
    /// in the process, and the tests running beside this one have theirs open.
    fn quit(handle: DocumentHandle) {
        actor().run(move |state| {
            state.park(handle.id);
            save_library(state);
        });
    }

    #[test]
    fn a_quit_with_a_script_open_comes_back_to_it_where_the_writer_was() {
        let it = Fixture::open("session-quit");
        doc_set_scroll(it.handle, 328);

        quit(it.handle);

        let session = session_on_disk(&it.root);
        assert_eq!(session.len(), 1, "the script was open when the app went");
        assert_eq!(session[0].path, it.script);
        assert_eq!(session[0].scroll_row, 328);
        assert!(
            block_on(recovery_pending()).is_empty(),
            "and it went cleanly: there is nothing to offer"
        );
    }

    #[test]
    fn a_script_the_writer_put_away_is_not_reopened() {
        let it = Fixture::open("session-put-away");
        doc_set_scroll(it.handle, 12);

        doc_close(it.handle);
        quit(it.handle);

        assert!(session_on_disk(&it.root).is_empty());
    }

    #[test]
    fn a_process_that_dies_comes_back_to_the_row_that_was_parked() {
        let it = Fixture::open("session-died");
        doc_set_scroll(it.handle, 328);
        assert_eq!(
            session_on_disk(&it.root)[0].scroll_row,
            0,
            "a row is not a file write"
        );

        block_on(session_park());

        let session = session_on_disk(&it.root);
        assert_eq!(session.len(), 1);
        assert_eq!(session[0].scroll_row, 328);
    }

    #[test]
    fn a_script_put_away_and_parked_is_not_reopened_by_a_process_that_dies() {
        let it = Fixture::open("session-put-away-died");

        doc_close(it.handle);
        block_on(session_park());

        assert!(session_on_disk(&it.root).is_empty());
    }

    #[test]
    fn export_copy_keeps_the_session_and_its_row_on_the_managed_file() {
        let it = Fixture::open("session-save-as");
        doc_set_scroll(it.handle, 40);
        let renamed = it.root.join("renamed.fountain");

        assert!(matches!(
            block_on(doc_export_fountain(
                it.handle,
                renamed.to_string_lossy().into_owned(),
                false
            )),
            SaveOutcome::Saved { .. }
        ));
        quit(it.handle);

        let session = session_on_disk(&it.root);
        assert_eq!(session.len(), 1, "only the managed file stays open");
        assert_eq!(session[0].path, it.script);
        assert_eq!(session[0].scroll_row, 40);
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
        assert_eq!(block_on(doc_autosave(it.handle)), SaveOutcome::Unchanged);
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

    // -----------------------------------------------------------------------
    // A session that could not be journalled says so
    // -----------------------------------------------------------------------

    /// Makes a journal directory that will not take a new file, the way one
    /// owned by another user or on a read-only mount does. What
    /// `Journal::create` gets back is an ordinary `io::Error`, which is also
    /// what a full disk gives it, so this one arrangement stands for both.
    ///
    /// Returns `false` when the question cannot be asked at all: root ignores
    /// the mode bits, and a test that carried on would pass without proving
    /// anything.
    fn refuse_new_journals(directory: &Path) -> bool {
        fs::create_dir_all(directory).expect("the journal directory is made");
        fs::set_permissions(directory, fs::Permissions::from_mode(0o555))
            .expect("the journal directory is made read-only");
        if fs::write(directory.join("probe"), "").is_ok() {
            println!(
                "SKIPPED: a read-only directory still took a file, so this is running \
                 as root. Run the suite unprivileged to exercise the unwritable-journal \
                 path."
            );
            allow_new_journals(directory);
            let _ = fs::remove_file(directory.join("probe"));
            return false;
        }
        true
    }

    fn allow_new_journals(directory: &Path) {
        fs::set_permissions(directory, fs::Permissions::from_mode(0o755))
            .expect("the journal directory is writable again");
    }

    /// Opening a script whose journal cannot be created is the failure that used
    /// to be completely silent: `Journal::create`'s error went into an `.ok()`,
    /// the session kept a `None` journal that looked exactly like a working one
    /// from the outside, and every keystroke from then on was unprotected
    /// without a word about it anywhere.
    ///
    /// The editor still opens — refusing the script would cost the writer more
    /// than the missing cover does — but it opens saying what it cannot do.
    #[test]
    fn opening_a_script_whose_journal_cannot_be_created_says_it_is_not_being_recorded() {
        let _storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
        let root = temp_root("journal-unwritable-open");
        let script = seed_project(&root, "heat", SCRIPT);
        fs::write(&script, SCRIPT).expect("the script is written");
        let paths = install_storage(&root);
        let journals = paths.journal_dir();
        if !refuse_new_journals(&journals) {
            let _ = fs::remove_dir_all(&root);
            return;
        }

        let handle = block_on(library_open(script.to_string_lossy().into_owned()))
            .expect("the script still opens: a journal is cover, not a precondition");

        let (recorded, broken) = doc_journal_state(handle);
        assert!(
            broken,
            "the session must say it is unprotected, not look like an ordinary one"
        );
        assert_eq!(recorded, 0, "and it is honest about holding nothing");

        // Typing still works, and does not quietly recover the claim.
        let block = doc_blocks(handle, 0, 1)[0].id;
        let _ = doc_apply(
            handle,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: "Typed anyway. ".to_owned(),
            },
            None,
        );
        assert_eq!(doc_source(handle), format!("Typed anyway. {SCRIPT}"));
        assert_eq!(
            doc_journal_state(handle),
            (0, true),
            "one edit later it is still unprotected and still says nothing is recorded"
        );
        assert!(
            !journals
                .join(format!("{}.log", journal::script_id(&script)))
                .exists(),
            "and nothing was written where the journal would have gone"
        );

        // The file itself is unaffected: this costs crash cover, not saving.
        let outcome = block_on(doc_save(handle));
        assert!(matches!(outcome, SaveOutcome::Saved { .. }), "{outcome:?}");
        assert_eq!(
            fs::read_to_string(&script).expect("the script reads"),
            format!("Typed anyway. {SCRIPT}")
        );

        actor().run(move |state| state.close(handle.id));
        allow_new_journals(&journals);
        let _ = fs::remove_dir_all(&root);
    }

    /// The same for a script created rather than opened. `library_create` writes
    /// the file first and then opens it through the same door, so the answer has
    /// to be the same one — and a brand new script is the case where an
    /// unrecorded session costs the most, because there is nothing on disk to
    /// fall back to but an empty template.
    #[test]
    fn creating_a_script_whose_journal_cannot_be_created_says_it_is_not_being_recorded() {
        let _storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
        let root = temp_root("journal-unwritable-create");
        let script = root.join("The Long Road.fountain");
        let paths = install_storage(&root);
        let journals = paths.journal_dir();
        if !refuse_new_journals(&journals) {
            let _ = fs::remove_dir_all(&root);
            return;
        }

        let handle =
            block_on(library_create("The Long Road".into())).expect("the script is still created");
        assert!(!script.exists(), "no external destination is created");
        assert!(
            Path::new(&doc_path(handle).unwrap()).is_file(),
            "the managed script is on disk"
        );
        assert_eq!(
            doc_journal_state(handle),
            (0, true),
            "a new script with nowhere to journal is unprotected, and says so"
        );

        actor().run(move |state| state.close(handle.id));
        allow_new_journals(&journals);
        let _ = fs::remove_dir_all(&root);
    }

    /// The journal directory becomes writable again — a disk that was full is
    /// emptied, permissions are fixed — and the writer reopens the script. That
    /// session is journalled: "unprotected" is a fact about a session, not a
    /// state the core gets stuck in.
    #[test]
    fn a_session_opened_after_the_journal_directory_recovers_is_protected_again() {
        let _storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
        let root = temp_root("journal-unwritable-recovers");
        let script = seed_project(&root, "heat", SCRIPT);
        fs::write(&script, SCRIPT).expect("the script is written");
        let paths = install_storage(&root);
        let journals = paths.journal_dir();
        if !refuse_new_journals(&journals) {
            let _ = fs::remove_dir_all(&root);
            return;
        }

        let unprotected = block_on(library_open(script.to_string_lossy().into_owned()))
            .expect("the script opens");
        assert_eq!(doc_journal_state(unprotected), (0, true));
        actor().run(move |state| state.close(unprotected.id));

        allow_new_journals(&journals);
        let handle = block_on(library_open(script.to_string_lossy().into_owned()))
            .expect("the script opens again");
        assert_eq!(
            doc_journal_state(handle),
            (0, false),
            "a session that got its journal is not carrying the last one's failure"
        );
        let block = doc_blocks(handle, 0, 1)[0].id;
        let _ = doc_apply(
            handle,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: "Recorded. ".to_owned(),
            },
            None,
        );
        assert_eq!(
            doc_journal_state(handle),
            (1, false),
            "and it is recording again"
        );

        actor().run(move |state| state.close(handle.id));
        let _ = fs::remove_dir_all(&root);
    }

    /// The backstop under all of the above: a session holding no journal reports
    /// the first edit as the moment it broke, rather than answering the way a
    /// successful append does. This is what makes it impossible to add a path
    /// that opens a session, forgets to journal it, and looks fine.
    #[test]
    fn an_edit_recorded_by_a_session_with_no_journal_reports_it_once() {
        let handle = crate::api::doc::doc_new();
        let (first, second, broken) = actor().run(move |state| {
            let session = state.session_mut(handle.id).expect("the session");
            let first = session.record(model::Patch::default());
            let second = session.record(model::Patch::default());
            (first, second, session.journal_broken())
        });
        assert!(first, "the first edit is where the writer has to be told");
        assert!(!second, "and told once, not once per keystroke");
        assert!(broken, "the session stays marked unprotected");
        actor().run(move |state| state.close(handle.id));
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
    // The save path checks the file it is replacing
    //
    // Every fixture here runs with `watcher: None` — a core that never got
    // inotify, which is the machine the audit is about. Nothing below is told
    // about the external write by an event; the save finds it itself.
    // -----------------------------------------------------------------------

    /// The finding, in one test: with no watcher running, an autosave used to
    /// replace another program's edit and say "Saved".
    #[test]
    fn a_save_does_not_replace_an_external_edit_without_being_asked() {
        let it = Fixture::open("disk-conflict");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));

        atomic::save_atomically(&it.script, "Somebody else wrote this.\n")
            .expect("their save works");
        it.types("More of ours. ");
        let ours = it.in_memory();

        let outcome = block_on(doc_save(it.handle));
        assert!(
            matches!(
                outcome,
                SaveOutcome::Failed {
                    failure: SaveFailure::ChangedOnDisk,
                    ..
                }
            ),
            "the save went ahead over an external edit: {outcome:?}"
        );
        assert_eq!(
            it.on_disk(),
            "Somebody else wrote this.\n",
            "their text was overwritten"
        );
        assert_eq!(it.in_memory(), ours, "and ours was not disturbed either");
        assert!(
            it.dirty(),
            "the refused save must not look like a clean one"
        );
    }

    /// An autosave is refused the same way and for the same reason — it is the
    /// one that fires without anybody asking for it, which is what made the
    /// silent overwrite silent.
    #[test]
    fn an_autosave_is_refused_over_an_external_edit_too() {
        let it = Fixture::open("disk-conflict-autosave");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));

        atomic::save_atomically(&it.script, "Theirs.\n").expect("their save works");
        it.types("More. ");
        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Failed {
                failure: SaveFailure::ChangedOnDisk,
                ..
            }
        ));
        assert_eq!(it.on_disk(), "Theirs.\n");
        assert!(
            !it.is_saving(),
            "a refused save must not leave the session armed for a checkpoint \
             that is never coming"
        );
    }

    /// The way out that keeps the writer's text: they were shown the file, they
    /// chose their own version, and the next save writes it. Without this the
    /// refusal above would be permanent, which is §1.2's P0 by another road.
    #[test]
    fn keeping_mine_lets_the_next_save_write() {
        let it = Fixture::open("disk-keep-mine");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        atomic::save_atomically(&it.script, "Theirs.\n").expect("their save works");
        it.types("More. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Failed {
                failure: SaveFailure::ChangedOnDisk,
                ..
            }
        ));

        assert!(block_on(doc_accept_disk_state(it.handle)));
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), it.in_memory());
        assert!(!it.dirty());
    }

    /// …and only the version they were shown. Somebody writing the file again
    /// between the decision and the save is a new external change, and asks
    /// again rather than being covered by the old answer.
    #[test]
    fn accepting_covers_the_version_that_was_shown_and_no_later_one() {
        let it = Fixture::open("disk-accept-once");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        atomic::save_atomically(&it.script, "Theirs.\n").expect("their save works");
        assert!(block_on(doc_accept_disk_state(it.handle)));

        atomic::save_atomically(&it.script, "Theirs, again.\n").expect("their second save works");
        it.types("More. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Failed {
                failure: SaveFailure::ChangedOnDisk,
                ..
            }
        ));
        assert_eq!(it.on_disk(), "Theirs, again.\n");
    }

    /// The check must be invisible to a session nobody else is touching. Our own
    /// saves produce a new inode and new timestamps every time — the same thing
    /// an external save produces — so a check that could not tell them apart
    /// would refuse the second save of every session.
    #[test]
    fn our_own_saves_are_never_refused_by_it() {
        let it = Fixture::open("disk-our-own");
        for round in 0..5 {
            it.types(&format!("Line {round}. "));
            let outcome = block_on(doc_save(it.handle));
            assert!(
                matches!(outcome, SaveOutcome::Saved { .. }),
                "save {round} was refused: {outcome:?}"
            );
        }
        assert_eq!(it.on_disk(), it.in_memory());
    }

    /// A file rewritten with the bytes it already had is not an edit anybody has
    /// to decide about. `touch`, a `git checkout` restoring the same text, an
    /// editor writing back what it read: refusing those would be a prompt with
    /// nothing behind it, and the writer would learn to dismiss the prompt.
    #[test]
    fn a_file_rewritten_with_the_same_bytes_is_not_a_conflict() {
        let it = Fixture::open("disk-restamped");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));

        let unchanged = it.on_disk();
        atomic::save_atomically(&it.script, &unchanged).expect("their identical save works");
        it.types("More. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), it.in_memory());
    }

    /// A script deleted under the writer is recreated by their next save. There
    /// is nothing there to preserve, and a refusal here would be one they could
    /// not resolve — the prompt that follows a refusal reads the file too.
    #[test]
    fn a_missing_managed_script_is_not_recreated() {
        let it = Fixture::open("disk-deleted");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));

        fs::remove_file(&it.script).expect("the file goes");
        it.types("More. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Failed { .. }
        ));
        assert!(!it.script.exists());
        assert!(it.dirty());
        assert!(it.journal_path().exists());
    }

    /// Save As names its own destination through a chooser that has already
    /// asked about replacing what is there (ADR 0029), so it is not refused by a
    /// record about the file the session is leaving.
    #[test]
    fn a_export_copy_elsewhere_is_not_refused_by_the_old_files_conflict() {
        let it = Fixture::open("disk-save-as");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        atomic::save_atomically(&it.script, "Theirs.\n").expect("their save works");

        let elsewhere = it.root.join("moved.fountain");
        assert!(matches!(
            block_on(doc_export_fountain(
                it.handle,
                elsewhere.to_string_lossy().into_owned(),
                false,
            )),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(
            fs::read_to_string(&elsewhere).expect("the new file reads"),
            it.in_memory()
        );
        assert_eq!(
            it.on_disk(),
            "Theirs.\n",
            "and the file it left is still theirs"
        );

        // And the session now protects its *new* file, not the one it left.
        it.types("More. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Failed {
                failure: SaveFailure::ChangedOnDisk,
                ..
            }
        ));
    }

    /// Taking theirs is a decision about the file, so the save that follows it
    /// is not refused for the conflict it just resolved.
    #[test]
    fn a_reload_settles_the_conflict_it_read() {
        let it = Fixture::open("disk-reload");
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        atomic::save_atomically(&it.script, "Theirs.\n").expect("their save works");

        assert!(block_on(doc_reload(it.handle, false)));
        assert_eq!(it.in_memory(), "Theirs.\n");
        it.types("Ours again. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), it.in_memory());
    }

    /// The external-change check reads the file to answer, so when it finds the
    /// file identical to the document it has learned what is there — and a save
    /// that follows is not refused over a stat nothing came of. Otherwise one
    /// `touch` of a clean script would refuse every save it ever made again.
    #[test]
    fn a_check_that_found_nothing_leaves_no_conflict_behind() {
        let it = Fixture::open("disk-checked");
        let same = it.on_disk();
        atomic::save_atomically(&it.script, &same).expect("their identical save works");

        assert_eq!(
            block_on(doc_external_change(it.handle)),
            Some((false, false)),
            "the file holds what the document holds"
        );
        it.types("Ours. ");
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
    }

    /// The degraded-safety half of the finding: a session whose file cannot be
    /// watched says so, for the whole session, rather than looking like one that
    /// is being watched. Every fixture is such a session — `install_storage`
    /// builds a core with no watcher at all.
    #[test]
    fn a_session_that_cannot_be_watched_says_so() {
        let it = Fixture::open("watch-unavailable");
        assert!(
            !doc_watch_state(it.handle),
            "a session with no watcher behind it reported that it was watched"
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
        fs::set_permissions(it.script.parent().unwrap(), read_only)
            .expect("the folder is made read-only");

        let outcome = block_on(doc_save(it.handle));
        fs::set_permissions(
            it.script.parent().unwrap(),
            fs::Permissions::from_mode(0o755),
        )
        .expect("the folder is writable again");
        assert!(matches!(outcome, SaveOutcome::Failed { .. }));
        assert!(it.would_be_reported());
        assert!(it.own_writes().is_empty());
    }

    /// Exports neither register an own-write echo nor detach the source watch.
    #[test]
    fn export_copy_does_not_register_writes_on_either_path() {
        let it = Fixture::open("own-save-as");
        let elsewhere = it.root.join("elsewhere.fountain");
        it.types("Moving. ");
        let outcome = block_on(doc_export_fountain(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
            false,
        ));
        assert!(matches!(outcome, SaveOutcome::Saved { .. }));

        let own = it.own_writes();
        assert!(!own.is_echo(&elsewhere), "exports are not watched");
        assert!(
            !own.is_echo(&it.script),
            "the managed script has not been saved"
        );
        assert_eq!(own.len(), 0);
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
    // Export isolation and the own-file-only compatibility Save As
    //
    // Exports preserve the binding and history (ADR 0029); the compatibility
    // `doc_save_as` no longer moves an editable session (ADR 0068).
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

    #[test]
    fn a_viewed_backup_copies_exact_bytes_and_preserves_unsaved_work() {
        const OLD: &str = "\u{feff}Title: Earlier\r\nAuthor: Zoë\r\n\r\nINT. ROOM - DAY\r\n\r\nOld *words*.  \r\n";
        let it = Fixture::open_source("backup-view-copy", OLD);
        let previous = block_on(backups_list(it.handle)).remove(0);
        it.types("Unsaved current words. ");
        let before = it.in_memory();
        let journal = fs::read(it.journal_path()).unwrap();
        let backups = block_on(backups_list(it.handle));
        let BackupReadOutcome::Read { source, .. } = block_on(backup_read(previous.path.clone()))
        else {
            panic!("the previous version must be readable");
        };
        assert_eq!(
            source, OLD,
            "reading does not parse or normalise the source"
        );
        // Retention is allowed to remove the backing file after it was viewed.
        fs::remove_file(&previous.path).unwrap();
        let copy = it.root.join("earlier-copy.fountain");
        let outcome = block_on(backup_copy(
            it.handle,
            source,
            copy.to_string_lossy().into_owned(),
        ));
        assert_eq!(exported(&outcome), copy.to_string_lossy());
        assert_eq!(fs::read_to_string(&copy).unwrap(), OLD);
        assert_eq!(it.in_memory(), before);
        assert_eq!(it.on_disk(), OLD);
        assert!(it.dirty());
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
        assert_eq!(fs::read(it.journal_path()).unwrap(), journal);
        assert_eq!(it.recovers_to(), before);
        assert_eq!(
            block_on(backups_list(it.handle)),
            backups
                .into_iter()
                .filter(|b| b.path != previous.path)
                .collect::<Vec<_>>(),
        );
        assert!(!it.is_saving());
        assert!(it.own_writes().is_empty());
    }

    #[test]
    fn a_backup_copy_refuses_existing_files_and_open_missing_scripts() {
        let it = Fixture::open("backup-copy-refusals");
        let other = it.beside("backup-copy-open");
        let backup = block_on(backups_list(it.handle)).remove(0);
        let occupied = it.root.join("occupied.fountain");
        fs::write(&occupied, "Keep this draft.").unwrap();
        for path in [&occupied, Path::new(&backup.path)] {
            let before = fs::read(path).unwrap();
            assert_eq!(
                failure_of_outcome(&block_on(backup_copy(
                    it.handle,
                    "Earlier.".to_owned(),
                    path.to_string_lossy().into_owned(),
                ))),
                if project::protected_destination(path) {
                    SaveFailure::LibraryDestination
                } else {
                    SaveFailure::AlreadyExists
                },
            );
            assert_eq!(fs::read(path).unwrap(), before);
        }
        fs::remove_file(&other.script).unwrap();
        assert_eq!(
            failure_of_outcome(&block_on(backup_copy(
                it.handle,
                "Earlier.".to_owned(),
                other.script.to_string_lossy().into_owned(),
            ))),
            SaveFailure::ScriptIsOpen,
        );
        assert!(!other.script.exists());
        assert_eq!(it.on_disk(), SCRIPT);
    }

    #[test]
    fn an_unavailable_backup_reports_failure_instead_of_an_empty_view() {
        let root = temp_root("backup-read-errors");
        let path = root.join("previous.fountain");
        for bytes in [None, Some(&b"\xff"[..])] {
            if let Some(bytes) = bytes {
                fs::write(&path, bytes).unwrap();
            }
            assert!(matches!(
                block_on(backup_read(path.to_string_lossy().into_owned())),
                BackupReadOutcome::Failed { message } if message.contains("previous.fountain")
            ));
        }
        fs::remove_dir_all(root).unwrap();
    }

    /// Export writes current unsaved text without changing the managed path.
    #[test]
    fn export_copy_preserves_the_active_path_and_dirty_state() {
        let it = Fixture::open("save-as-path");
        let elsewhere = it.root.join("moved.fountain");
        it.types("Moving. ");
        let moved = it.in_memory();

        let outcome = block_on(doc_export_fountain(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
            false,
        ));

        assert_eq!(exported(&outcome), elsewhere.to_string_lossy());
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
        assert_eq!(fs::read_to_string(&elsewhere).unwrap(), moved);
        assert_eq!(it.on_disk(), SCRIPT, "the file left behind is untouched");
        assert!(it.dirty(), "an export leaves unsaved library work dirty");
    }

    /// Journal, library membership and watch remain attached to the managed file.
    #[test]
    fn export_copy_preserves_the_journal_and_the_library_entry() {
        let it = Fixture::open("save-as-binding");
        let elsewhere = it.root.join("rebound.fountain");
        it.types("Rebinding. ");
        block_on(doc_export_fountain(
            it.handle,
            elsewhere.to_string_lossy().into_owned(),
            false,
        ));

        assert_eq!(
            it.journal_describes().as_deref(),
            Some(it.script.as_path()),
            "the journal still covers the managed file"
        );
        let id = journal::script_id(&it.script);
        assert!(
            it.library_has(&id),
            "the library retains the managed script's locator"
        );
        assert!(!it.own_writes().is_echo(&elsewhere));
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

    /// The pair of the test above, and the reason it exists: Save As reaches
    /// the same `save_atomically` through the same chooser, so it has to refuse
    /// an occupied destination for the same reason. The file the writer picked
    /// by mistake stays byte-identical until they say Replace.
    #[test]
    fn export_copy_refuses_to_overwrite_until_it_is_told_to() {
        let it = Fixture::open("save-as-overwrite");
        it.types("New words. ");
        let occupied = it.root.join("occupied.fountain");
        const THEIRS: &str = "Somebody else's script.\n";
        fs::write(&occupied, THEIRS).expect("the file is written");

        let refused = block_on(doc_export_fountain(
            it.handle,
            occupied.to_string_lossy().into_owned(),
            false,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::AlreadyExists);
        assert_eq!(
            fs::read_to_string(&occupied).unwrap(),
            THEIRS,
            "a refused Save As writes nothing"
        );
        // And it moved nothing either: a refusal is not half a Save As.
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
        assert!(it.dirty(), "the document was not saved anywhere");
        assert_eq!(
            it.journal_describes().as_deref(),
            Some(it.script.as_path()),
            "the journal still covers the file the session is bound to"
        );
        assert!(!it.is_saving(), "a refused Save As arms nothing");

        let confirmed = block_on(doc_export_fountain(
            it.handle,
            occupied.to_string_lossy().into_owned(),
            true,
        ));
        assert!(matches!(confirmed, SaveOutcome::Saved { .. }));
        assert_eq!(fs::read_to_string(&occupied).unwrap(), it.in_memory());
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());
    }

    /// Save As onto the file the session already lives in is a save, and asking
    /// "replace it?" about the writer's own script would be a question with one
    /// answer. The exception is exactly that one file — nothing else.
    #[test]
    fn save_as_onto_its_own_file_needs_no_confirmation() {
        let it = Fixture::open("save-as-itself");
        it.types("Onto itself. ");

        let outcome = block_on(doc_save_as(
            it.handle,
            it.script.to_string_lossy().into_owned(),
            false,
        ));

        assert!(matches!(outcome, SaveOutcome::Saved { .. }));
        assert_eq!(it.on_disk(), it.in_memory());
        assert!(!it.dirty());
    }

    /// The other refusal's pair. `overwrite` does not lift this one either: the
    /// other session's journal is based on the bytes this write would replace,
    /// so a crash after it would recover onto a file that no longer matches.
    #[test]
    fn save_as_never_writes_another_open_script() {
        let it = Fixture::open("save-as-open");
        let other = it.beside("save-as-also-open");
        it.types("Mine. ");

        let refused = block_on(doc_save_as(
            it.handle,
            other.script.to_string_lossy().into_owned(),
            true,
        ));
        assert_eq!(
            failure_of_outcome(&refused),
            SaveFailure::LibraryDestination
        );
        assert_eq!(other.on_disk(), SCRIPT);
        assert_eq!(other.in_memory(), SCRIPT);
        assert_eq!(doc_path(it.handle).as_deref(), it.script.to_str());

        // And spelled through a symlinked directory, which a comparison of the
        // paths as written would let through.
        let linked = it.root.join("link");
        std::os::unix::fs::symlink(other.script.parent().unwrap(), &linked)
            .expect("the symlink is made");
        let sideways = linked.join(
            other
                .script
                .file_name()
                .expect("the sibling has a file name"),
        );
        let refused = block_on(doc_save_as(
            it.handle,
            sideways.to_string_lossy().into_owned(),
            true,
        ));
        assert_eq!(
            failure_of_outcome(&refused),
            SaveFailure::LibraryDestination
        );
        assert_eq!(other.on_disk(), SCRIPT);
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
        std::os::unix::fs::symlink(other.script.parent().unwrap(), &linked)
            .expect("the symlink is made");
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

    /// §1.2 does not grade user text by which part of the document it is in.
    ///
    /// Before Phase 7 the title page was not typeable, so the journal's
    /// block-shaped records covered everything there was. Now it is, and a draft
    /// date typed thirty seconds before the power goes has to come back with the
    /// dialogue typed thirty seconds before that (ADR 0033).
    #[test]
    fn a_title_page_edit_survives_a_crash_like_any_other_edit() {
        let it = Fixture::open_source("journal-title", "Title: Big Fish\n\nThe house is quiet.\n");
        it.types("A line. ");
        crate::api::doc::doc_set_title_field(
            it.handle,
            "Draft date".to_owned(),
            "26 July 2026".to_owned(),
        );
        it.types("Another. ");

        assert_eq!(
            it.recovers_to(),
            it.in_memory(),
            "what the journal recovers is what the writer can see"
        );
        assert!(it.recovers_to().contains("Draft date: 26 July 2026"));

        // And undoing it takes it away again, in the journal as on screen.
        crate::api::doc::doc_undo(it.handle);
        crate::api::doc::doc_undo(it.handle);
        assert_eq!(it.recovers_to(), it.in_memory());
        assert!(!it.recovers_to().contains("Draft date"));
    }

    /// A native title page that repeats a key, in bytes no canonical save would
    /// write: a BOM, CRLF, a tab-indented value and doubled spaces (S4).
    const REPEATED_TITLE: &str = "\u{feff}Title:\r\n\t_**BIG FISH**_\r\n\tPart Two\r\nAuthor:  John August\r\nAuthor: Daniel Wallace\r\nRevision Colour: Blue\r\n\r\nThe house  is quiet.\r\n";

    /// The title form reads one value per key — the first, which is the entry
    /// `doc_set_title_field` reaches. A field sent what it already holds is not
    /// an edit (ADR 0033): no journal record, nothing to undo, nothing unsaved,
    /// and the bytes the file had on the next save.
    #[test]
    fn a_title_field_set_to_what_it_holds_records_nothing() {
        use crate::api::doc::{doc_set_title_field, doc_title_page};
        let it = Fixture::open_source("title-unchanged", REPEATED_TITLE);
        let page = doc_title_page(it.handle);
        assert_eq!(
            page.iter()
                .map(|entry| (entry.key.as_str(), entry.value.as_str()))
                .collect::<Vec<_>>(),
            [
                ("Title", "_**BIG FISH**_\nPart Two"),
                ("Author", "John August"),
                ("Author", "Daniel Wallace"),
                ("Revision Colour", "Blue"),
            ],
            "a repeated key is read as two entries, not merged into one"
        );

        let mut sent: Vec<&str> = Vec::new();
        for entry in &page {
            if sent.contains(&entry.key.as_str()) {
                continue;
            }
            sent.push(&entry.key);
            doc_set_title_field(it.handle, entry.key.clone(), entry.value.clone());
        }
        // And a field the file does not have, left empty.
        doc_set_title_field(it.handle, "Draft date".to_owned(), String::new());

        assert_eq!(
            it.journalled(),
            0,
            "nothing happened, so nothing is recorded"
        );
        assert!(!it.dirty());
        assert!(doc_undo(it.handle).is_none(), "there is nothing to undo");
        assert_eq!(doc_title_page(it.handle), page);
        assert_eq!(it.in_memory(), REPEATED_TITLE);
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert_eq!(it.on_disk(), REPEATED_TITLE);
    }

    /// Typing in that box changes the entry it showed and no other: the later
    /// entry under the same key is neither merged nor dropped, the body keeps
    /// the bytes the file had, and Undo is the file again.
    #[test]
    fn editing_a_repeated_title_key_changes_only_its_first_entry() {
        use crate::api::doc::{doc_close, doc_set_title_field, doc_title_page};
        let mut it = Fixture::open_source("title-repeated", REPEATED_TITLE);
        let mut expected = doc_title_page(it.handle);
        doc_set_title_field(it.handle, "Author".to_owned(), "J. August".to_owned());

        assert_eq!(expected[1].value, "John August");
        expected[1].value = "J. August".to_owned();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), it.in_memory());

        doc_undo(it.handle).unwrap();
        assert_eq!(it.in_memory(), REPEATED_TITLE);
        doc_redo(it.handle).unwrap();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.recovers_to(), it.in_memory());

        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        let saved = it.on_disk();
        assert!(
            saved.ends_with("\r\n\r\nThe house  is quiet.\r\n"),
            "the body is the bytes the file had"
        );
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.in_memory(), saved);
    }

    #[test]
    fn clearing_a_repeated_title_field_preserves_the_other_entries() {
        use crate::api::doc::{doc_close, doc_set_title_field, doc_title_page};
        let mut it = Fixture::open_source("title-clear-repeated", REPEATED_TITLE);
        let mut expected = doc_title_page(it.handle);
        expected.remove(1);
        doc_set_title_field(it.handle, "Author".to_owned(), String::new());
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.journalled(), 1);
        assert_eq!(it.recovers_to(), it.in_memory());
        doc_undo(it.handle).unwrap();
        assert_eq!(it.in_memory(), REPEATED_TITLE);
        doc_redo(it.handle).unwrap();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.recovers_to(), it.in_memory());
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        let saved = it.on_disk();
        assert!(saved.starts_with('\u{feff}'));
        assert!(saved.ends_with("\r\n\r\nThe house  is quiet.\r\n"));
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.in_memory(), saved);
    }

    #[test]
    fn later_title_entries_can_be_edited_and_removed_individually() {
        use crate::api::doc::{doc_close, doc_set_title_entry, doc_title_page};
        let source = REPEATED_TITLE.replace(
            "Revision Colour: Blue\r\n",
            "Author: Third author\r\nRevision Colour: Blue\r\nRevision Colour: Pink\r\n",
        );
        let mut it = Fixture::open_source("title-entry", &source);
        let original = doc_title_page(it.handle);
        let mut expected = original.clone();
        doc_set_title_entry(
            it.handle,
            "Author".to_owned(),
            1,
            "D. Wallace\nSecond line".to_owned(),
        );
        expected[2].value = "D. Wallace\nSecond line".to_owned();
        assert_eq!(doc_title_page(it.handle), expected);
        doc_set_title_entry(it.handle, "Author".to_owned(), 1, String::new());
        expected.remove(2);
        assert_eq!(doc_title_page(it.handle), expected);
        doc_set_title_entry(
            it.handle,
            "Revision Colour".to_owned(),
            1,
            "Green".to_owned(),
        );
        expected.last_mut().unwrap().value = "Green".to_owned();
        assert_eq!(doc_title_page(it.handle), expected);
        doc_set_title_entry(it.handle, "Revision Colour".to_owned(), 0, String::new());
        expected.remove(expected.len() - 2);
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.journalled(), 4);
        assert_eq!(it.recovers_to(), it.in_memory());

        for _ in 0..4 {
            doc_undo(it.handle).unwrap();
        }
        assert_eq!(it.in_memory(), source);
        for _ in 0..4 {
            doc_redo(it.handle).unwrap();
        }
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.recovers_to(), it.in_memory());
        assert!(matches!(
            block_on(doc_save(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        let saved = it.on_disk();
        assert!(saved.starts_with('\u{feff}'));
        assert!(saved.ends_with("\r\n\r\nThe house  is quiet.\r\n"));
        doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(doc_title_page(it.handle), expected);
        assert_eq!(it.in_memory(), saved);
    }

    #[test]
    fn unchanged_or_invalid_title_occurrences_record_nothing() {
        use crate::api::doc::{doc_set_title_entry, doc_title_page};
        let it = Fixture::open_source("title-entry-no-op", REPEATED_TITLE);
        let original = doc_title_page(it.handle);
        assert!(matches!(
            doc_set_title_entry(
                it.handle,
                "Author".to_owned(),
                1,
                "Daniel Wallace".to_owned()
            ),
            EditOutcome::Applied { .. }
        ));
        assert!(matches!(
            doc_set_title_entry(it.handle, "Author".to_owned(), 3, "Wrong entry".to_owned()),
            EditOutcome::Rejected { .. }
        ));
        assert_eq!(doc_title_page(it.handle), original);
        assert!(!it.dirty());
        assert_eq!(it.journalled(), 0);
        assert!(doc_undo(it.handle).is_none());
        assert_eq!(it.in_memory(), REPEATED_TITLE);
    }

    // -----------------------------------------------------------------------
    // Exporting a PDF (§Phase 7)
    // -----------------------------------------------------------------------

    fn letter() -> layout::PageSetup {
        layout::PageSetup {
            paper: layout::PaperSize::UsLetter,
            scene_numbers: layout::SceneNumbers::Off,
            bold_scene_headings: false,
            number_first_page: false,
            debug_lines_per_page: None,
        }
    }

    #[test]
    fn a_pdf_export_writes_a_pdf_and_moves_nothing() {
        const SOURCE: &str =
            "Title: Big Fish\nAuthor: Ed Bloom\n\nINT. HOUSE - DAY\n\nJohn enters.\n";
        let it = Fixture::open_source("export-pdf", SOURCE);
        it.types("More words. ");
        let before = it.recovers_to();
        let journalled = it.journalled();
        let dirty = it.dirty();
        let pdf = it.root.join("export.pdf");

        let outcome = block_on(doc_export_pdf(
            it.handle,
            letter(),
            pdf.to_string_lossy().into_owned(),
            false,
        ));
        let SaveOutcome::Saved { bytes, backup, .. } = outcome else {
            panic!("expected a saved PDF, got {outcome:?}");
        };
        assert!(backup.is_none(), "an export writes no backup");

        let written = fs::read(&pdf).expect("the PDF is readable");
        assert_eq!(written.len() as u32, bytes);
        assert!(written.starts_with(b"%PDF-1.7"));
        assert!(
            String::from_utf8_lossy(&written).contains("/Type /Catalog"),
            "it is a whole document, not a prefix of one"
        );

        // ADR 0029, unchanged: an export copies and moves nothing.
        assert_eq!(it.on_disk(), SOURCE, "the script's own file is untouched");
        assert_eq!(it.dirty(), dirty, "the dirty flag is not cleared by a copy");
        assert_eq!(
            it.journal_describes().as_deref(),
            Some(it.script.as_path()),
            "the journal still covers the file the session is bound to"
        );
        assert_eq!(it.journalled(), journalled);
        assert_eq!(it.recovers_to(), before);
        assert!(!it.is_saving(), "an export arms nothing");
        assert!(
            it.own_writes().is_empty(),
            "the PDF is not a file this session watches"
        );
    }

    #[test]
    fn a_pdf_export_refuses_the_same_two_destinations_a_fountain_export_does() {
        let it = Fixture::open("export-pdf-refusals");
        let occupied = it.root.join("occupied.pdf");
        fs::write(&occupied, "not really a pdf\n").expect("the file is written");

        let refused = block_on(doc_export_pdf(
            it.handle,
            letter(),
            occupied.to_string_lossy().into_owned(),
            false,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::AlreadyExists);
        assert_eq!(
            fs::read_to_string(&occupied).unwrap(),
            "not really a pdf\n",
            "a refused export writes nothing"
        );

        let confirmed = block_on(doc_export_pdf(
            it.handle,
            letter(),
            occupied.to_string_lossy().into_owned(),
            true,
        ));
        assert!(matches!(confirmed, SaveOutcome::Saved { .. }));
        assert!(fs::read(&occupied).unwrap().starts_with(b"%PDF"));

        // And an open script is refused however firmly the caller insists —
        // a chooser with the wrong filter would otherwise destroy a screenplay.
        let refused = block_on(doc_export_pdf(
            it.handle,
            letter(),
            it.script.to_string_lossy().into_owned(),
            true,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::ScriptIsOpen);
        assert_eq!(it.on_disk(), SCRIPT);
    }

    #[test]
    fn a_pdf_export_is_the_same_bytes_every_time_under_source_date_epoch() {
        // §Phase 7's determinism requirement, through the whole application
        // path rather than only through `render_pdf`'s own function.
        let it = Fixture::open_source(
            "export-pdf-determinism",
            "Title: Big Fish\n\nINT. HOUSE - DAY\n\nJohn enters, *quietly*.\n",
        );
        std::env::set_var("SOURCE_DATE_EPOCH", "1700000000");
        let mut written = Vec::new();
        for run in 0..2 {
            let pdf = it.root.join(format!("run-{run}.pdf"));
            let outcome = block_on(doc_export_pdf(
                it.handle,
                letter(),
                pdf.to_string_lossy().into_owned(),
                false,
            ));
            assert!(matches!(outcome, SaveOutcome::Saved { .. }));
            written.push(fs::read(&pdf).expect("the PDF is readable"));
        }
        std::env::remove_var("SOURCE_DATE_EPOCH");
        assert_eq!(written[0], written[1]);
        assert!(
            String::from_utf8_lossy(&written[0]).contains("D:20231114221320+00'00'"),
            "the timestamp is the one the environment named"
        );
    }

    #[test]
    fn a_pdf_export_uses_the_title_page_the_document_holds() {
        let it = Fixture::open_source(
            "export-pdf-title",
            "Title: The Long Way Round\nAuthor: A Writer\n\nAction.\n",
        );
        let pdf = it.root.join("titled.pdf");
        block_on(doc_export_pdf(
            it.handle,
            letter(),
            pdf.to_string_lossy().into_owned(),
            false,
        ));
        let written = String::from_utf8_lossy(&fs::read(&pdf).unwrap()).into_owned();

        // UTF-16BE with a byte-order mark, which is how a PDF text string says
        // anything a writer might actually type.
        assert!(
            written.contains("/Title <FEFF0054006800650020004C006F006E0067"),
            "the document's own title is what the file says it is"
        );
        assert!(written.contains("/Author <FEFF00410020005700720069007400650072>"));
    }

    #[test]
    fn a_closed_document_exports_no_pdf() {
        let it = Fixture::open("export-pdf-closed");
        let pdf = it.root.join("nothing.pdf");
        let handle = it.handle;
        crate::api::doc::doc_close(handle);

        let refused = block_on(doc_export_pdf(
            handle,
            letter(),
            pdf.to_string_lossy().into_owned(),
            false,
        ));
        assert_eq!(failure_of_outcome(&refused), SaveFailure::NoSuchDocument);
        assert!(!pdf.exists());
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

    const RECOVERY_CHILD_ROOT: &str = "SLUGLINE_BRIDGE_RECOVERY_CHILD_ROOT";
    const RECOVERY_CHILD_MODE: &str = "SLUGLINE_BRIDGE_RECOVERY_CHILD_MODE";
    const RECOVERY_CHILD_TEST: &str = "api::files::tests::recovery_process_child";
    const RECOVERY_MESSAGE: &str = "slugline-recovery-process: ";
    const RECOVERY_EDIT: &str = "Edited. ";
    const RECOVERY_DURING_SAVE: &str = "During save. ";

    /// Unlike the other fixtures, this root is explicitly under /tmp even when
    /// the invoking environment has a different TMPDIR.
    struct RecoveryProcessRoot {
        _storage: MutexGuard<'static, ()>,
        root: PathBuf,
        handles: Vec<DocumentHandle>,
    }

    impl RecoveryProcessRoot {
        fn new() -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
            let root = Path::new("/tmp").join(format!(
                "slugline-s1-recovery-{}-{}",
                std::process::id(),
                COUNTER.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&root).expect("an isolated /tmp directory");
            let fixture = Self {
                _storage: storage,
                root,
                handles: Vec::new(),
            };
            let script = seed_project(&fixture.root, "shared", SCRIPT);
            fs::write(
                fixture.root.join("managed-path"),
                script.to_string_lossy().as_bytes(),
            )
            .unwrap();
            install_storage(&fixture.root);
            fixture
        }

        fn script(&self) -> PathBuf {
            PathBuf::from(fs::read_to_string(self.root.join("managed-path")).unwrap())
        }

        fn journal(&self) -> PathBuf {
            Paths::under(&self.root)
                .journal_dir()
                .join(format!("{}.log", journal::script_id(&self.script())))
        }
    }

    impl Drop for RecoveryProcessRoot {
        fn drop(&mut self) {
            for handle in &self.handles {
                let handle = *handle;
                actor().run(move |state| state.close(handle.id));
            }
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    /// Installed immediately after spawn, before any fallible pipe setup, so
    /// assertion failures and handshake timeouts cannot leave an owner running.
    struct RecoveryChildOwner(std::process::Child);

    impl Drop for RecoveryChildOwner {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }

    struct RecoveryChild {
        owner: RecoveryChildOwner,
        input: std::process::ChildStdin,
        messages: Receiver<String>,
        reader: Option<thread::JoinHandle<()>>,
    }

    impl RecoveryChild {
        fn spawn(root: &Path, mode: &str) -> Self {
            use std::io::BufRead;
            use std::process::{Command, Stdio};

            let mut owner = RecoveryChildOwner(
                Command::new(std::env::current_exe().expect("the bridge test binary"))
                    .args(["--exact", RECOVERY_CHILD_TEST, "--nocapture"])
                    .env(RECOVERY_CHILD_ROOT, root)
                    .env(RECOVERY_CHILD_MODE, mode)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .spawn()
                    .expect("the recovery owner starts"),
            );
            let input = owner.0.stdin.take().expect("the child's command pipe");
            let stdout = owner.0.stdout.take().expect("the child's response pipe");
            let (send, messages) = mpsc::channel();
            let reader = thread::spawn(move || {
                for line in std::io::BufReader::new(stdout).lines() {
                    let Ok(line) = line else {
                        break;
                    };
                    // libtest may print its test name before the child's line.
                    if let Some((_, message)) = line.split_once(RECOVERY_MESSAGE) {
                        if send.send(message.to_owned()).is_err() {
                            break;
                        }
                    }
                }
            });
            Self {
                owner,
                input,
                messages,
                reader: Some(reader),
            }
        }

        fn wait_for(&self, expected: &str) {
            assert_eq!(
                self.messages
                    .recv_timeout(PATIENCE)
                    .expect("the child acknowledges the completed bridge operation"),
                expected
            );
        }

        fn command(&mut self, command: &str, expected: &str) {
            use std::io::Write;
            writeln!(self.input, "{command}").expect("the child receives its command");
            self.input.flush().expect("the command pipe is flushed");
            self.wait_for(expected);
        }

        fn kill(&mut self) {
            use std::os::unix::process::ExitStatusExt;
            self.owner.0.kill().expect("SIGKILL reaches the live owner");
            let status = self.owner.0.wait().expect("the owner is reaped");
            assert_eq!(status.signal(), Some(9), "no clean shutdown ran");
        }
    }

    impl Drop for RecoveryChild {
        fn drop(&mut self) {
            let _ = self.owner.0.kill();
            let _ = self.owner.0.wait();
            if let Some(reader) = self.reader.take() {
                let _ = reader.join();
            }
        }
    }

    fn recovery_child_message(message: &str) {
        use std::io::Write;
        println!("{RECOVERY_MESSAGE}{message}");
        std::io::stdout()
            .flush()
            .expect("the parent receives the acknowledgement");
    }

    fn recovery_child_types(handle: DocumentHandle, text: &str) {
        let block = doc_blocks(handle, 0, 1)[0].id;
        let _ = doc_apply(
            handle,
            EditCommand::ReplaceText {
                block,
                start_utf16: 0,
                end_utf16: 0,
                with: text.to_owned(),
            },
            None,
        );
    }

    /// Reentered by exact module-qualified name in a genuinely separate process.
    /// Every operation below uses the production bridge; only scheduling a save
    /// uses the same test-only gate as the ordinary save regression tests.
    #[test]
    fn recovery_process_child() {
        use std::io::BufRead;

        let Some(root) = std::env::var_os(RECOVERY_CHILD_ROOT) else {
            return;
        };
        let _storage = STORAGE.lock().unwrap_or_else(PoisonError::into_inner);
        let root = PathBuf::from(root);
        assert!(root.starts_with("/tmp"));
        install_storage(&root);
        let script = PathBuf::from(fs::read_to_string(root.join("managed-path")).unwrap());
        let mode = std::env::var(RECOVERY_CHILD_MODE).expect("the child's operation");
        let handle = match mode.as_str() {
            "open" => {
                assert!(block_on(recovery_pending()).is_empty());
                let handle = block_on(library_open(script.to_string_lossy().into_owned()))
                    .expect("the owner opens the script");
                assert_eq!(doc_journal_state(handle), (0, false));
                recovery_child_message("empty");
                handle
            }
            "accept" => {
                let offers = block_on(recovery_pending());
                assert_eq!(offers.len(), 1);
                assert!(offers[0].blocked.is_none());
                let RecoveryOutcome::Recovered { handle } =
                    block_on(recovery_accept(offers[0].journal.clone()))
                else {
                    panic!("the child must accept with durable successor protection");
                };
                assert_eq!(
                    doc_source(handle),
                    format!("{RECOVERY_DURING_SAVE}{RECOVERY_EDIT}{SCRIPT}")
                );
                assert!(doc_dirty(handle));
                assert_eq!(doc_journal_state(handle), (1, false));
                recovery_child_message("recovered");
                handle
            }
            other => panic!("unknown recovery child mode: {other}"),
        };

        for command in std::io::stdin().lock().lines() {
            match command
                .expect("the parent's command pipe remains readable")
                .as_str()
            {
                "edit" => {
                    assert!(block_on(doc_reload(handle, true)));
                    recovery_child_types(handle, RECOVERY_EDIT);
                    assert_eq!(doc_source(handle), format!("{RECOVERY_EDIT}{SCRIPT}"));
                    assert_eq!(doc_journal_state(handle), (1, false));
                    recovery_child_message("edited");
                }
                "save" => {
                    let gate = Gate::hold_the_first_write(&script);
                    let saving = Saving::explicit(handle);
                    gate.wait();
                    recovery_child_types(handle, RECOVERY_DURING_SAVE);
                    gate.release();
                    assert!(matches!(saving.outcome(), SaveOutcome::Saved { .. }));
                    stall::forget(&script);
                    assert_eq!(
                        fs::read_to_string(&script).unwrap(),
                        format!("{RECOVERY_EDIT}{SCRIPT}")
                    );
                    assert_eq!(
                        doc_source(handle),
                        format!("{RECOVERY_DURING_SAVE}{RECOVERY_EDIT}{SCRIPT}")
                    );
                    assert!(doc_dirty(handle));
                    assert_eq!(doc_journal_state(handle), (1, false));
                    recovery_child_message("rebuilt");
                }
                other => panic!("unknown recovery child command: {other}"),
            }
        }
        panic!("a recovery owner must be SIGKILLed, not shut down cleanly");
    }

    fn assert_live_recovery_is_untouchable(path: &Path) {
        let bytes = fs::read(path).expect("the live journal exists");
        assert!(
            block_on(recovery_pending()).is_empty(),
            "live edits are not an offer"
        );
        assert_eq!(
            fs::read(path).unwrap(),
            bytes,
            "startup scan preserves the journal"
        );
        assert!(
            matches!(
                block_on(recovery_accept(path.to_string_lossy().into_owned())),
                RecoveryOutcome::Failed { .. }
            ),
            "even a direct or stale offer cannot accept a live journal"
        );
        assert_eq!(
            fs::read(path).unwrap(),
            bytes,
            "accept cannot replace the journal"
        );
        assert!(!block_on(recovery_discard(
            path.to_string_lossy().into_owned()
        )));
        assert_eq!(
            fs::read(path).unwrap(),
            bytes,
            "discard cannot unlink the journal"
        );
    }

    #[test]
    fn recovery_respects_a_live_process_and_survives_two_sigkills() {
        use std::os::unix::fs::MetadataExt;

        let mut fixture = RecoveryProcessRoot::new();
        let script = fixture.script();
        let path = fixture.journal();
        let mut owner = RecoveryChild::spawn(&fixture.root, "open");
        owner.wait_for("empty");

        // The original defect: scanning a live, empty journal unlinked it.
        let empty = fs::read(&path).expect("the owner has an empty journal");
        assert!(journal::read(&path).unwrap().patches.is_empty());
        assert_live_recovery_is_untouchable(&path);
        assert_eq!(fs::read(&path).unwrap(), empty);

        assert!(
            block_on(library_open(script.to_string_lossy().into_owned())).is_none(),
            "another live owner prevents an independent managed session"
        );
        assert_eq!(fs::read(&path).unwrap(), empty);

        owner.command("edit", "edited");
        assert_live_recovery_is_untouchable(&path);
        let before = fs::metadata(&path).unwrap();
        owner.command("save", "rebuilt");
        let successor = fs::metadata(&path).unwrap();
        assert_ne!(
            (before.dev(), before.ino()),
            (successor.dev(), successor.ino()),
            "the actual save published an atomic rebuild_at successor"
        );
        assert_live_recovery_is_untouchable(&path);

        owner.kill();
        let offers = block_on(recovery_pending());
        assert_eq!(offers.len(), 1, "SIGKILL releases the kernel lock");
        assert_eq!(offers[0].journal, path.to_string_lossy().into_owned());
        assert!(offers[0].blocked.is_none());
        assert_eq!(offers[0].edits, 1);
        let stale_offer = offers[0].journal.clone();

        // Accept in another process, then try the old offer while its atomically
        // replaced successor is owned. A second crash must offer the same text.
        let mut recovered = RecoveryChild::spawn(&fixture.root, "accept");
        recovered.wait_for("recovered");
        assert_live_recovery_is_untouchable(Path::new(&stale_offer));
        recovered.kill();
        let offers = block_on(recovery_pending());
        assert_eq!(offers.len(), 1);
        assert!(offers[0].blocked.is_none());
        let RecoveryOutcome::Recovered { handle } =
            block_on(recovery_accept(offers[0].journal.clone()))
        else {
            panic!("the second crash must still recover with a working journal");
        };
        fixture.handles.push(handle);
        assert_eq!(
            doc_source(handle),
            format!("{RECOVERY_DURING_SAVE}{RECOVERY_EDIT}{SCRIPT}")
        );
        assert!(doc_dirty(handle));
        assert_eq!(doc_journal_state(handle), (1, false));
        assert_eq!(
            fs::read_to_string(script).unwrap(),
            format!("{RECOVERY_EDIT}{SCRIPT}"),
            "accepting recovery never saves the unsaved edit"
        );
    }

    #[test]
    fn autosave_backups_are_throttled_without_losing_the_saved_text() {
        let it = Fixture::open("autosave-backups");
        let initial = block_on(backups_list(it.handle));
        assert_eq!(initial.len(), 1);
        assert_eq!(fs::read_to_string(&initial[0].path).unwrap(), SCRIPT);

        it.types("First. ");
        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Saved { backup: None, .. }
        ));
        assert_eq!(it.on_disk(), "First. The house is quiet.\n");

        // Filename time is the policy's clock input, with no sleeping or timer.
        let initial_path = Path::new(&initial[0].path);
        fs::rename(initial_path, initial_path.with_file_name("1.fountain")).unwrap();
        it.types("Second. ");
        let SaveOutcome::Saved {
            backup: Some(snapshot),
            ..
        } = block_on(doc_autosave(it.handle))
        else {
            panic!("an aged, different snapshot must be written");
        };
        assert_eq!(
            fs::read_to_string(&snapshot.path).unwrap(),
            "Second. First. The house is quiet.\n"
        );
        it.types("Third. ");
        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Saved { backup: None, .. }
        ));
        assert_eq!(it.on_disk(), "Third. Second. First. The house is quiet.\n");
        assert_eq!(block_on(backups_list(it.handle)).len(), 2);
        assert!(!it.dirty());
        assert!(it.journal_agrees_with_the_file());
    }

    #[test]
    fn opening_snapshots_changed_disk_text_but_not_identical_text() {
        let mut it = Fixture::open("open-backups");
        let original = block_on(backups_list(it.handle))[0].clone();
        crate::api::doc::doc_close(it.handle);
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(block_on(backups_list(it.handle)), vec![original.clone()]);
        crate::api::doc::doc_close(it.handle);

        // Changed outside Slugline, less than ten minutes after the first open.
        fs::write(&it.script, "Changed elsewhere.\n").unwrap();
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        let versions = block_on(backups_list(it.handle));
        assert_eq!(versions.len(), 2);
        assert_eq!(
            fs::read_to_string(&versions[0].path).unwrap(),
            "Changed elsewhere.\n"
        );
        assert_eq!(fs::read_to_string(&original.path).unwrap(), SCRIPT);
        assert_eq!(it.in_memory(), "Changed elsewhere.\n");
        assert!(!it.dirty());
        // Opening an already-open handle cannot add a spurious version either.
        assert_eq!(
            block_on(library_open(it.script.to_string_lossy().into_owned())),
            Some(it.handle)
        );
        assert_eq!(block_on(backups_list(it.handle)), versions);
    }

    #[test]
    fn explicit_saves_snapshot_even_after_autosave_made_the_document_clean() {
        let it = Fixture::open("explicit-backups");
        it.types("Autosaved. ");
        assert!(matches!(
            block_on(doc_autosave(it.handle)),
            SaveOutcome::Saved { .. }
        ));
        assert!(!it.dirty());
        let mut paths = std::collections::HashSet::new();
        for _ in 0..3 {
            let SaveOutcome::Saved {
                backup: Some(snapshot),
                ..
            } = block_on(doc_save(it.handle))
            else {
                panic!("every explicit save must snapshot even unchanged text");
            };
            assert_eq!(fs::read_to_string(&snapshot.path).unwrap(), it.on_disk());
            assert!(paths.insert(snapshot.path), "each save has its own version");
        }
        let destination = it.root.join("exported.fountain");
        let before = block_on(backups_list(it.handle));
        let outcome = block_on(doc_export_fountain(
            it.handle,
            destination.to_string_lossy().into_owned(),
            false,
        ));
        assert!(matches!(outcome, SaveOutcome::Saved { backup: None, .. }));
        assert_eq!(fs::read_to_string(destination).unwrap(), it.in_memory());
        assert_eq!(block_on(backups_list(it.handle)), before);
    }

    #[test]
    fn backup_cache_failure_does_not_fail_open_autosave_or_explicit_save() {
        let mut it = Fixture::open("broken-backups");
        // A regular file where the backup root should be fails even under root.
        let blocked = it.script.parent().unwrap().join("versions");
        fs::rename(&blocked, it.root.join("retained-versions")).unwrap();
        fs::write(&blocked, "not a directory").unwrap();
        let setting = blocked.clone();
        actor().run(move |state| state.storage_mut().unwrap().prefs.backup_dir = Some(setting));
        crate::api::doc::doc_close(it.handle);
        fs::write(&it.script, "Opened without a backup.\n").unwrap();
        it.handle = block_on(library_open(it.script.to_string_lossy().into_owned())).unwrap();
        assert_eq!(it.in_memory(), "Opened without a backup.\n");

        for explicit in [false, true] {
            it.types("Saved without a backup. ");
            let outcome = if explicit {
                block_on(doc_save(it.handle))
            } else {
                block_on(doc_autosave(it.handle))
            };
            assert!(matches!(outcome, SaveOutcome::Saved { backup: None, .. }));
            assert_eq!(it.on_disk(), it.in_memory());
            assert!(!it.dirty());
            assert!(it.journal_agrees_with_the_file());
        }
        assert_eq!(fs::read_to_string(&blocked).unwrap(), "not a directory");
    }

    #[test]
    fn fdx_import_is_unsaved_isolated_and_recoverable_before_fountain_save() {
        let it = Fixture::open("fdx-import");
        let input = it.root.join("producer.fdx");
        let original = include_bytes!("../../../../testdata/fdx/fade-in-5.0.15.fdx");
        fs::write(&input, original).unwrap();
        let old_source = it.in_memory();
        let old_journal = it.journalled();
        let FdxImportOutcome::Imported { handle, .. } =
            block_on(doc_import_fdx(input.to_string_lossy().into_owned()))
        else {
            panic!("the independent producer's supported screenplay must import");
        };
        let candidate = Sibling {
            script: input.clone(),
            handle,
        };
        assert_eq!(it.in_memory(), old_source);
        assert_eq!(it.journalled(), old_journal);
        assert_eq!(it.on_disk(), SCRIPT);
        assert_eq!(doc_path(handle), None);
        assert!(doc_dirty(handle));
        assert!(doc_undo(handle).is_none(), "import is not an undoable edit");
        assert!(matches!(
            block_on(doc_save(handle)),
            SaveOutcome::Failed {
                failure: SaveFailure::NoPath,
                ..
            }
        ));
        let journal_path = actor().run(move |state| {
            state
                .session_mut(handle.id)
                .and_then(Session::journal_mut)
                .map(|journal| journal.path().to_path_buf())
                .unwrap()
        });
        let blocks = doc_blocks(handle, 0, u32::MAX);
        assert_eq!(
            blocks[0].text, "INT. IMPORT ROOM - DAY #12A#",
            "an existing production number survives import"
        );
        let dialogue = blocks
            .iter()
            .find(|block| block.kind == crate::api::doc::BlockKind::Dialogue)
            .unwrap();
        assert_eq!(
            slugline_fountain::emphasis::scan_row(&dialogue.text)
                .into_iter()
                .map(|run| run.text)
                .collect::<String>(),
            "I say hello."
        );
        let initial_recovery = journal::read(&journal_path).unwrap();
        let mut recovered = model::Document::blank();
        for patch in &initial_recovery.patches {
            recovered.replay(patch).unwrap();
        }
        assert_eq!(
            recovered.serialise(),
            candidate.in_memory(),
            "the initial import is recoverable before the first keystroke"
        );
        assert!(matches!(
            doc_apply(
                handle,
                EditCommand::ReplaceText {
                    block: dialogue.id,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "Again ".to_owned(),
                },
                None,
            ),
            EditOutcome::Applied { .. }
        ));
        let recovery = journal::read(&journal_path).unwrap();
        assert!(recovery.header.script.as_os_str().is_empty());
        let mut recovered = model::Document::blank();
        for patch in &recovery.patches {
            recovered.replay(patch).unwrap();
        }
        assert_eq!(recovered.serialise(), candidate.in_memory());
        assert!(matches!(
            block_on(doc_commit_project(handle)),
            SaveOutcome::Saved { .. }
        ));
        let saved = PathBuf::from(doc_path(handle).unwrap());
        assert!(!doc_dirty(handle));
        assert_eq!(fs::read(&input).unwrap(), original);
        let reopened = block_on(library_open(saved.to_string_lossy().into_owned())).unwrap();
        let reopened = Sibling {
            script: saved,
            handle: reopened,
        };
        assert_eq!(reopened.in_memory(), candidate.in_memory());
        assert_eq!(it.in_memory(), old_source);
    }

    #[test]
    fn failed_fdx_import_does_not_replace_or_dirty_the_current_session() {
        let it = Fixture::open("fdx-import-refusal");
        let input = it.root.join("malformed.fdx");
        let malformed = b"<FinalDraft><Content><Paragraph><Text>unfinished";
        fs::write(&input, malformed).unwrap();
        let before = (it.in_memory(), it.journalled(), doc_path(it.handle));
        assert!(matches!(
            block_on(doc_import_fdx(input.to_string_lossy().into_owned())),
            FdxImportOutcome::Failed { .. }
        ));
        assert_eq!(
            (it.in_memory(), it.journalled(), doc_path(it.handle)),
            before
        );
        assert!(!it.dirty());
        assert_eq!(it.on_disk(), SCRIPT);
        assert_eq!(fs::read(&input).unwrap(), malformed);
    }

    #[test]
    fn fdx_export_preserves_native_state_and_refuses_unapproved_destinations() {
        let it = Fixture::open("fdx-export-copy");
        it.types("Changed ");
        let before = (
            it.in_memory(),
            doc_path(it.handle),
            it.journalled(),
            it.journal_describes(),
        );
        let copy = it.root.join("copy.fdx");
        assert!(matches!(
            block_on(doc_export_fdx(
                it.handle,
                copy.to_string_lossy().into_owned(),
                false,
                None,
            )),
            FdxExportOutcome::Finished {
                outcome: SaveOutcome::Saved { .. },
                ..
            }
        ));
        let imported = fdx::read(&fs::read(&copy).unwrap()).unwrap();
        assert_eq!(
            imported.script.elements[0].text,
            "Changed The house is quiet."
        );
        assert_eq!(
            (
                it.in_memory(),
                doc_path(it.handle),
                it.journalled(),
                it.journal_describes(),
            ),
            before
        );
        assert!(it.dirty(), "export is not a save");
        assert_eq!(it.on_disk(), SCRIPT);
        assert!(!it.library_has(&journal::script_id(&copy)));
        let existing = fs::read(&copy).unwrap();
        assert!(matches!(
            block_on(doc_export_fdx(
                it.handle,
                copy.to_string_lossy().into_owned(),
                false,
                None,
            )),
            FdxExportOutcome::Finished {
                outcome: SaveOutcome::Failed {
                    failure: SaveFailure::AlreadyExists,
                    ..
                },
                ..
            }
        ));
        assert_eq!(fs::read(&copy).unwrap(), existing);
        assert!(matches!(
            block_on(doc_export_fdx(
                it.handle,
                it.script.to_string_lossy().into_owned(),
                true,
                None,
            )),
            FdxExportOutcome::Finished {
                outcome: SaveOutcome::Failed {
                    failure: SaveFailure::ScriptIsOpen,
                    ..
                },
                ..
            }
        ));
        assert_eq!(it.on_disk(), SCRIPT);
        doc_undo(it.handle).unwrap();
        assert_eq!(it.in_memory(), SCRIPT);
        assert!(!it.dirty(), "export did not disturb the saved revision");
    }

    #[test]
    fn fdx_conversion_warning_approval_cannot_authorize_a_later_revision() {
        let it = Fixture::open_source(
            "fdx-warning-revision",
            "# Part\n\n= A scene card\n\nINT. ROOM - DAY\n\nQuiet.\n",
        );
        let copy = it.root.join("revealed-outline.fdx");
        let FdxExportOutcome::NeedsConfirmation { revision, .. } = block_on(doc_export_fdx(
            it.handle,
            copy.to_string_lossy().into_owned(),
            false,
            None,
        )) else {
            panic!("revealing nonprinting content requires explicit approval");
        };
        assert!(!copy.exists());
        it.types("Changed ");
        let FdxExportOutcome::NeedsConfirmation {
            revision: current, ..
        } = block_on(doc_export_fdx(
            it.handle,
            copy.to_string_lossy().into_owned(),
            false,
            Some(revision),
        ))
        else {
            panic!("the old snapshot's approval must not authorize the new one");
        };
        assert_ne!(current, revision);
        assert!(!copy.exists());
        assert!(matches!(
            block_on(doc_export_fdx(
                it.handle,
                copy.to_string_lossy().into_owned(),
                false,
                Some(current),
            )),
            FdxExportOutcome::Finished {
                outcome: SaveOutcome::Saved { .. },
                ..
            }
        ));
        let imported = fdx::read(&fs::read(&copy).unwrap()).unwrap();
        assert_eq!(imported.script.elements[0].text, "Changed Part");
        assert_eq!(
            imported.script.elements[0].kind,
            slugline_fountain::BlockKind::Section { level: 1 }
        );
        assert!(it.dirty());
        assert_eq!(it.journalled(), 1);
    }

    #[test]
    fn initial_fdx_import_is_offered_and_accepted_after_a_crash_without_typing() {
        let it = Fixture::open("fdx-initial-recovery");
        let input = it.root.join("initial.fdx");
        fs::write(
            &input,
            include_bytes!("../../../../testdata/fdx/fade-in-5.0.15.fdx"),
        )
        .unwrap();
        let FdxImportOutcome::Imported { handle, .. } =
            block_on(doc_import_fdx(input.to_string_lossy().into_owned()))
        else {
            panic!("the supported producer imports");
        };
        let candidate = Sibling {
            script: input.clone(),
            handle,
        };
        let expected = candidate.in_memory();
        // Release the process-owned file without discarding it, as a crash does.
        let journal_path = actor().run(move |state| {
            let session = state.session_mut(handle.id).unwrap();
            let path = session.journal_mut().unwrap().path().to_path_buf();
            session.set_journal(None);
            path
        });
        let offer = block_on(recovery_pending())
            .into_iter()
            .find(|offer| Path::new(&offer.journal) == journal_path)
            .expect("an initial imported state is not an empty journal");
        assert!(offer.script.is_empty());
        assert!(offer.blocked.is_none());
        let RecoveryOutcome::Recovered { handle } = block_on(recovery_accept(offer.journal)) else {
            panic!("the initial full outcome replays onto the untitled blank base");
        };
        let recovered = Sibling {
            script: input,
            handle,
        };
        assert_eq!(recovered.in_memory(), expected);
        assert_eq!(doc_path(handle), None);
        assert!(doc_dirty(handle));
        assert!(doc_undo(handle).is_none());
        assert_eq!(it.in_memory(), SCRIPT);
        assert_eq!(candidate.on_disk(), recovered.on_disk());
    }

    #[test]
    fn empty_fdx_import_keeps_its_blank_recovery_base_and_saved_edit_identity() {
        let it = Fixture::open("fdx-empty-recovery");
        let input = it.root.join("empty.fdx");
        let original = b"<FinalDraft DocumentType=\"Script\"><Content/></FinalDraft>";
        fs::write(&input, original).unwrap();
        let FdxImportOutcome::Imported { handle, .. } =
            block_on(doc_import_fdx(input.to_string_lossy().into_owned()))
        else {
            panic!("an empty supported screenplay imports");
        };
        let candidate = Sibling {
            script: input.clone(),
            handle,
        };
        let block = doc_blocks(handle, 0, u32::MAX).into_iter().next().unwrap();
        assert_eq!(block.kind, crate::api::doc::BlockKind::Action);
        assert!(block.text.is_empty());
        let mut journal_path = actor().run(move |state| {
            state
                .session_mut(handle.id)
                .unwrap()
                .journal_mut()
                .unwrap()
                .path()
                .to_path_buf()
        });
        let initial = journal::read(&journal_path).unwrap();
        assert!(initial.header.script.as_os_str().is_empty());
        assert_eq!(
            initial.header.base,
            journal::checksum(&model::Document::blank().serialise())
        );
        let mut recovered = model::Document::blank();
        for patch in &initial.patches {
            recovered.replay(patch).unwrap();
        }
        assert_eq!(recovered.blocks().len(), 1);
        assert_eq!(recovered.blocks()[0].text(), "");
        assert_eq!(recovered.serialise(), candidate.in_memory());
        assert!(doc_undo(handle).is_none());

        assert!(matches!(
            block_on(doc_commit_project(handle)),
            SaveOutcome::Saved { .. }
        ));
        let saved = PathBuf::from(doc_path(handle).unwrap());
        journal_path = Paths::under(&it.root)
            .journal_dir()
            .join(format!("{}.log", journal::script_id(&saved)));
        let persisted = fs::read_to_string(&saved).unwrap();
        let checkpoint = journal::read(&journal_path).unwrap();
        assert_eq!(journal::verify(&checkpoint.header).unwrap(), persisted);
        let reopened = model::Document::parse(&persisted);
        assert_eq!(
            reopened.blocks().len(),
            1,
            "the caret block must not vanish"
        );
        assert_eq!(reopened.blocks()[0].id().0, block.id);
        assert_eq!(doc_blocks(handle, 0, u32::MAX), vec![block.clone()]);
        assert!(doc_undo(handle).is_none(), "Save adds no undo transaction");

        assert!(matches!(
            doc_apply(
                handle,
                EditCommand::ReplaceText {
                    block: block.id,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "First words — 日本 🎬.".to_owned(),
                },
                None,
            ),
            EditOutcome::Applied { .. }
        ));
        let expected = candidate.in_memory();
        doc_undo(handle).unwrap();
        assert_eq!(candidate.in_memory(), persisted);
        doc_redo(handle).unwrap();
        assert_eq!(candidate.in_memory(), expected);

        // Release, offer and accept through the production recovery path.
        actor().run(move |state| state.session_mut(handle.id).unwrap().set_journal(None));
        let offer = block_on(recovery_pending())
            .into_iter()
            .find(|offer| Path::new(&offer.journal) == journal_path)
            .expect("post-checkpoint edits produce a recovery offer");
        assert!(offer.blocked.is_none());
        let RecoveryOutcome::Recovered { handle } = block_on(recovery_accept(offer.journal)) else {
            panic!("the edit must replay against the persisted empty Action");
        };
        let recovered = Sibling {
            script: saved,
            handle,
        };
        assert_eq!(recovered.in_memory(), expected);
        assert_eq!(doc_blocks(handle, 0, u32::MAX)[0].id, block.id);
        assert_eq!(
            doc_blocks(handle, 0, u32::MAX)[0].text,
            "First words — 日本 🎬."
        );
        assert_eq!(fs::read(&input).unwrap(), original);
    }
}
