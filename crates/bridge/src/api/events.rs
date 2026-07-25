//! §2.3's single event channel, and §6's `CoreEvent`.
//!
//! Rust → Dart notifications go over one `StreamSink`. Dart subscribes once at
//! startup with [`core_events`]; everything in the core that has news pushes it
//! through [`emit`].
//!
//! There is a second stream in `handshake.rs`. It is not an application channel
//! and never becomes one: it is the Phase 0 proof that a `StreamSink` works at
//! all, in the same file as `echo` and `slice_utf16`, and it goes when that file
//! does. The application subscribes to this one and only this one.
//!
//! Nothing here polls. The stream is idle until something happens — a save, a
//! failed autosave, a file changing under an open document — which is what the
//! 0% idle CPU budget of §1.3 requires.

use std::sync::{Mutex, OnceLock};

use crate::api::files::SaveFailure;
use crate::frb_generated::StreamSink;

/// What the core tells Dart about, unasked.
///
/// §6 lists these variants phase by phase.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreEvent {
    /// A document became clean, or dirty. The title bar's asterisk.
    SaveStateChanged { handle: u64, dirty: bool },
    /// An autosave failed. §Phase 4 requires a save failure to be explicit and
    /// blocking — but an autosave is not a save the user asked for, so this is
    /// the quieter half of that rule: it reaches the status bar, not a modal,
    /// and it says exactly what went wrong.
    AutosaveFailed {
        handle: u64,
        failure: SaveFailure,
        message: String,
    },
    /// A file under an open document changed on disk. Dart asks
    /// `doc_external_change` what to do about it.
    FileChangedOnDisk { path: String },
    /// A rolling backup was written.
    BackupWritten { handle: u64, path: String },
    /// A successful edit changed the incrementally maintained §7 index.
    EntityIndexUpdated { handle: u64 },
    /// The journal stopped working for this document. The writer keeps typing;
    /// what they lose is the cover between one autosave and the next.
    JournalBroken { handle: u64 },
}

static EVENTS: OnceLock<Mutex<Option<StreamSink<CoreEvent>>>> = OnceLock::new();

fn sink() -> &'static Mutex<Option<StreamSink<CoreEvent>>> {
    EVENTS.get_or_init(|| Mutex::new(None))
}

/// Subscribe to the core event stream. A second subscription replaces the first,
/// which is what a Flutter hot restart does.
pub fn core_events(sink_in: StreamSink<CoreEvent>) {
    *sink().lock().expect("event sink mutex poisoned") = Some(sink_in);
}

/// Push an event at Dart.
///
/// Does nothing when nobody has subscribed. Dropping a notification is always
/// better than blocking the core on the UI — and this is called from the actor
/// thread, from FRB worker threads, and from `notify`'s watcher thread, none of
/// which may wait on Dart.
pub fn emit(event: CoreEvent) {
    if let Some(sink) = sink().lock().expect("event sink mutex poisoned").as_ref() {
        let _ = sink.add(event);
    }
}
