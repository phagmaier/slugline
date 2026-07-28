/// The §6 document surface: read blocks, apply edits, undo, clipboard.
pub mod doc;
/// The single Rust → Dart notification channel (§2.3).
pub mod events;
/// Everything that touches the disk: lifecycle, library, save, recovery,
/// backups, preferences (§Phase 4).
pub mod files;
/// Pagination: the §6 surface over `crates/layout`, as an async snapshot job
/// (ADR 0020).
pub mod layout;
/// `init_app`, and nothing else. Phase 0's `handshake` module was retired at
/// Phase 11; this is the one function in it the application actually needed.
pub mod lifecycle;
/// Dictionary discovery, background block checks and explicit dictionary
/// actions (§Phase 9).
pub mod spell;

#[cfg(test)]
mod appearance_prefs_dont_affect_pagination;
