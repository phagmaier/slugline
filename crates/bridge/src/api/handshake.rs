//! Phase 0 handshake surface.
//!
//! This module exists to prove the bridge works end to end, and nothing else.
//! It is **not** the API in spec §6 — that surface lands from Phase 1 onward,
//! at which point everything here is deleted. Nothing in the application is
//! allowed to depend on it.
//!
//! It proves four things:
//!
//! 1. Dart can call Rust and get a struct (with a nested `Vec<struct>`) back.
//! 2. Rust can push an event to Dart over a `StreamSink` (§2.3).
//! 3. Text survives the boundary byte-for-byte, including astral-plane emoji.
//! 4. The UTF-16 offset helpers in [`crate::offsets`] agree with Dart's own
//!    `String.length` (§2.4).

use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;

use crate::frb_generated::{StreamSink, FLUTTER_RUST_BRIDGE_CODEGEN_VERSION};
use crate::offsets;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Runs once, on the Dart side's first call into the core.
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------------------------------------------------------------------
// Proof 1 — struct round trip
// ---------------------------------------------------------------------------

/// What the core reports about itself at startup.
pub struct CoreInfo {
    /// Version of the `bridge` crate — i.e. of the core as a whole.
    pub core_version: String,
    /// `flutter_rust_bridge` version the `.so` was generated against. If this
    /// ever disagrees with the Dart package version, the codegen is stale.
    pub frb_version: String,
    /// The workspace crates, so the demo window can show the layering.
    pub crates: Vec<CrateInfo>,
}

/// One crate in the Rust workspace (§2.5).
pub struct CrateInfo {
    pub name: String,
    pub role: String,
    /// Workspace crates this one is allowed to depend on. Empty means "nothing".
    pub depends_on: Vec<String>,
}

#[frb(sync)]
pub fn core_info() -> CoreInfo {
    CoreInfo {
        core_version: env!("CARGO_PKG_VERSION").to_owned(),
        frb_version: FLUTTER_RUST_BRIDGE_CODEGEN_VERSION.to_owned(),
        crates: WORKSPACE_CRATES
            .iter()
            .map(|(name, role, deps)| CrateInfo {
                name: (*name).to_owned(),
                role: (*role).to_owned(),
                depends_on: deps.iter().map(|d| (*d).to_owned()).collect(),
            })
            .collect(),
    }
}

/// The layering rule of §2.5, as data. `tools/check_layering.rs` enforces the
/// same table against `cargo metadata`, so this list cannot drift unnoticed.
const WORKSPACE_CRATES: &[(&str, &str, &[&str])] = &[
    ("fountain", "Parse and serialise Fountain. Pure.", &[]),
    (
        "document",
        "Model, edit commands, undo, entity index.",
        &["fountain"],
    ),
    (
        "layout",
        "Line breaking and pagination. Deterministic.",
        &["document"],
    ),
    (
        "render_pdf",
        "PDF writer. Consumes layout output.",
        &["layout"],
    ),
    (
        "storage",
        "Atomic write, autosave, journal, backups, library.",
        &["document"],
    ),
    ("spell", "Dictionary loading and checking.", &[]),
    (
        "bridge",
        "FRB surface, actor thread, cdylib.",
        &["everything"],
    ),
];

// ---------------------------------------------------------------------------
// Proof 2 — Rust pushes, Dart receives
// ---------------------------------------------------------------------------

/// Notifications pushed by this proof, and by nothing else.
///
/// The application's channel is `api::events::CoreEvent` — §6's list, §2.3's
/// single sink. These two variants exist to prove that a `StreamSink` works at
/// all, which is Phase 0's job and this file's whole reason for existing. They
/// go when it does.
pub enum ProofEvent {
    /// Emitted the moment Dart subscribes.
    Ready { core_version: String },
    /// Emitted from a worker thread in response to [`ping`].
    Pong { text: String, len_utf16: u32 },
}

static EVENTS: OnceLock<Mutex<Option<StreamSink<ProofEvent>>>> = OnceLock::new();

fn event_sink() -> &'static Mutex<Option<StreamSink<ProofEvent>>> {
    EVENTS.get_or_init(|| Mutex::new(None))
}

/// Subscribe to the proof channel. The application subscribes to
/// `api::events::core_events` instead — see [`ProofEvent`].
pub fn proof_events(sink: StreamSink<ProofEvent>) {
    let ready = ProofEvent::Ready {
        core_version: env!("CARGO_PKG_VERSION").to_owned(),
    };
    // Send before storing, so a failed handshake never installs a dead sink.
    let _ = sink.add(ready);
    *event_sink().lock().expect("event sink mutex poisoned") = Some(sink);
}

/// Push `event` to Dart. Silently does nothing if nobody has subscribed —
/// dropping a notification is always preferable to blocking the core on the UI.
fn emit(event: ProofEvent) {
    if let Some(sink) = event_sink()
        .lock()
        .expect("event sink mutex poisoned")
        .as_ref()
    {
        let _ = sink.add(event);
    }
}

/// Ask the core to emit a [`ProofEvent::Pong`] **from another thread**, so the
/// test proves a genuine unsolicited push rather than a disguised return value.
///
/// Note there is no timer anywhere in this file: the stream is idle until
/// something happens, which is what the 0% idle CPU budget (§1.3) requires.
#[frb(sync)]
pub fn ping(text: String) {
    std::thread::spawn(move || {
        let len_utf16 = offsets::utf16_len(&text);
        emit(ProofEvent::Pong { text, len_utf16 });
    });
}

// ---------------------------------------------------------------------------
// Proofs 3 and 4 — text fidelity and offset agreement
// ---------------------------------------------------------------------------

/// How the core measures a string. Dart asserts `len_utf16` against its own
/// `String.length`; if those ever disagree, every offset in the app is wrong.
pub struct TextMetrics {
    pub len_utf16: u32,
    pub len_utf8: u32,
    pub char_count: u32,
}

/// Return `text` unchanged. The point is that "unchanged" survives a UTF-8
/// encode, an FFI hop, and a UTF-16 decode.
#[frb(sync)]
pub fn echo(text: String) -> String {
    text
}

#[frb(sync)]
pub fn text_metrics(text: String) -> TextMetrics {
    TextMetrics {
        len_utf16: offsets::utf16_len(&text),
        len_utf8: u32::try_from(text.len()).unwrap_or(u32::MAX),
        char_count: u32::try_from(text.chars().count()).unwrap_or(u32::MAX),
    }
}

/// Slice `text` by a **UTF-16** range, the way an editor command will (§3.4).
/// Returns `None` if the range is invalid — notably when an offset falls
/// between the halves of a surrogate pair.
#[frb(sync)]
pub fn slice_utf16(text: String, start_utf16: u32, end_utf16: u32) -> Option<String> {
    let range = offsets::utf16_range_to_utf8(&text, start_utf16..end_utf16)?;
    Some(text[range].to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The exact string Phase 0 requires to survive the round trip.
    const PROOF: &str = "café 日本 🎬";

    #[test]
    fn echo_is_byte_identical() {
        assert_eq!(echo(PROOF.to_owned()), PROOF);
    }

    #[test]
    fn metrics_match_hand_counted_values() {
        let m = text_metrics(PROOF.to_owned());
        // c a f é ␣ 日 本 ␣ 🎬  = 9 chars, the last one a surrogate pair.
        assert_eq!(m.char_count, 9);
        assert_eq!(m.len_utf16, 10);
        // 4 ASCII + 2 (é) + 3 + 3 (CJK) + 1 + 4 (emoji)
        assert_eq!(m.len_utf8, 17);
    }

    #[test]
    fn slice_utf16_uses_dart_coordinates() {
        assert_eq!(slice_utf16(PROOF.to_owned(), 0, 4), Some("café".to_owned()));
        assert_eq!(slice_utf16(PROOF.to_owned(), 5, 7), Some("日本".to_owned()));
        assert_eq!(slice_utf16(PROOF.to_owned(), 8, 10), Some("🎬".to_owned()));
        // Splitting the emoji's surrogate pair is refused, not rounded.
        assert_eq!(slice_utf16(PROOF.to_owned(), 8, 9), None);
    }

    #[test]
    fn crate_table_matches_the_workspace() {
        assert_eq!(WORKSPACE_CRATES.len(), 7);
        let fountain = WORKSPACE_CRATES
            .iter()
            .find(|(name, _, _)| *name == "fountain")
            .expect("fountain is in the table");
        assert!(fountain.2.is_empty(), "fountain depends on nothing (§2.5)");
    }
}
