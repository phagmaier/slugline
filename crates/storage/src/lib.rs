//! File I/O: atomic writes, autosave, crash journal, backups, library index.
//!
//! Layering rule (§2.5): may depend on `document` only.
//!
//! This crate is where §1.2's "losing user text is a P0 bug, always" is cashed
//! out. Nothing here is clever, and that is the design: every operation is
//! either the exact sequence §Phase 4 specifies ([`atomic::save_atomically`]) or
//! a plain append to a file that is read back tolerantly ([`journal`]).
//!
//! Three rules hold across all of it:
//!
//! 1. **A write either happened or did not.** No file this crate writes is ever
//!    left half-written, including the ones it writes about itself — the library
//!    index and the preferences go through the same atomic save the user's own
//!    script does.
//! 2. **A read never fails on bad input.** A corrupt journal, a truncated index,
//!    a preferences file someone hand-edited badly: each yields what could be
//!    read and says so. These files are read at startup and at recovery, which
//!    are the two moments when refusing to run is most expensive.
//! 3. **Only the script is data.** Everything else — the index, the session, the
//!    backups' bookkeeping — is a cache this crate can rebuild, and deleting any
//!    of it must cost nothing but convenience (§Phase 4).

pub mod atomic;
pub mod backup;
pub mod journal;
pub mod library;
pub mod paths;
pub mod prefs;
pub mod watch;

#[cfg(test)]
mod testing;

pub use atomic::{save_atomically, SaveError};
pub use journal::{Journal, JournalError, Recovery};
pub use paths::Paths;
pub use prefs::Preferences;
