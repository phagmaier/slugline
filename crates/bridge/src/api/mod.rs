/// The §6 document surface: read blocks, apply edits, undo, clipboard.
pub mod doc;
/// The single Rust → Dart notification channel (§2.3).
pub mod events;
/// Everything that touches the disk: lifecycle, library, save, recovery,
/// backups, preferences (§Phase 4).
pub mod files;
pub mod handshake;
