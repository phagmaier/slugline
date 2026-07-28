//! The one thing that has to happen before anything else does.
//!
//! This lived in `handshake.rs` until that module was retired at Phase 11. It
//! was never part of the Phase 0 proof — the rest of that file existed to
//! demonstrate that the bridge worked and was deleted once the §6 surface made
//! the demonstration redundant, but `init_app` is the application's own
//! lifecycle hook and outlives it.

use flutter_rust_bridge::frb;

/// Runs once, on the Dart side's first call into the core.
///
/// `#[frb(init)]` is what makes it automatic: flutter_rust_bridge emits the call
/// into its generated initialiser, so there is no Dart-side counterpart to
/// forget. What it sets up is FRB's default panic hook and logging, which is
/// what turns a Rust panic into a Dart exception rather than a dead isolate
/// (ADR 0039).
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
