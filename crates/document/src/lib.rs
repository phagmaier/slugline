//! Canonical document model: blocks, edit commands, undo/redo.
//!
//! Layering rule (§2.5): may depend on `fountain` only.
//!
//! This crate owns identity and history; `fountain` owns syntax.
//! [`Document::parse`] is the only thing that gives a block its provenance and
//! [`Document::serialise`] the only thing that reads it back — everything
//! between them is edits, and every edit that touches a block's bytes drops its
//! provenance, which is what moves that block from the serialiser's verbatim
//! path to its canonical one (§3.2).
//!
//! ```
//! use slugline_document::{Document, EditCommand};
//!
//! let source = "INT. HOUSE - DAY\n\nJohn enters.\n";
//! let mut doc = Document::parse(source);
//! assert_eq!(doc.serialise(), source);
//!
//! let id = doc.blocks()[1].id();
//! doc.apply(EditCommand::ReplaceText { block: id, range: 0..4, with: "Mary".into() }).unwrap();
//! assert_eq!(doc.serialise(), "INT. HOUSE - DAY\n\nMary enters.\n");
//!
//! doc.undo();
//! // Undo restores provenance as well as text, so the original bytes come back.
//! assert_eq!(doc.serialise(), source);
//! ```

mod document;
mod edit;
mod entities;
mod find;
mod history;
mod recovery;
mod workflow;

pub use document::{parse_blocks, Block, Document, Grouped};
pub use edit::{
    DocPosition, DocSelection, EditCommand, EditError, EditResult, InvalidBlockReason, NewBlock,
};
pub use entities::{normalize_character, Completion, EntityIndex, EntityKind};
pub use find::{FindQuery, Match};
pub use recovery::{BlockSnapshot, Patch, ReplayError};
pub use workflow::{enter_makes_a_cue, kind_after_enter, kind_after_tab, kind_before_tab};

// Re-exported so a caller does not have to depend on `fountain` directly to
// name a block's kind or a title-page field.
pub use slugline_fountain::{BlockKind, LineEnding, TitleField, TitlePage};

/// Stable for the lifetime of a loaded document. Never reused after deletion.
///
/// Flutter uses this as its list key and as the anchor for selections (§3.1),
/// which is why undo puts the original ids back rather than minting new ones.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BlockId(pub u64);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_ids_compare_by_value() {
        assert_eq!(BlockId(7), BlockId(7));
        assert_ne!(BlockId(7), BlockId(8));
    }

    #[test]
    fn can_reach_the_fountain_crate() {
        assert_eq!(slugline_fountain::FORMAT_NAME, "fountain");
    }
}
