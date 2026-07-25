//! Edit commands, their results, and document coordinates.
//!
//! **Offsets here are UTF-8 byte offsets into a block's text**, not the UTF-16
//! offsets of §3.4. That is not a deviation from the spec so much as a division
//! of it: §2.4 puts every UTF-16 conversion in `bridge/src/offsets.rs` and
//! nowhere else, so the bridge owns the `*_utf16` form of these commands and
//! hands `document` the converted one. See ADR 0008.

use std::fmt;
use std::ops::Range;

use slugline_fountain::{BlockKind, TitleField};

use crate::BlockId;

/// A caret position: a block, and a UTF-8 byte offset into that block's text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocPosition {
    pub block: BlockId,
    pub offset: u32,
}

impl DocPosition {
    pub fn new(block: BlockId, offset: u32) -> DocPosition {
        DocPosition { block, offset }
    }
}

/// A selection, which may be empty (a caret) and may run in either direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocSelection {
    pub anchor: DocPosition,
    pub focus: DocPosition,
}

impl DocSelection {
    pub fn caret(at: DocPosition) -> DocSelection {
        DocSelection {
            anchor: at,
            focus: at,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.anchor == self.focus
    }
}

/// A block to be inserted, before the document has given it an identity.
///
/// §3.4 writes this as `Vec<Block>`; ids are assigned by the document so that
/// the "never reused after deletion" rule of §3.1 stays enforceable in one
/// place.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewBlock {
    pub kind: BlockKind,
    pub text: String,
    pub forced: bool,
    pub dual: bool,
}

impl NewBlock {
    pub fn new(kind: BlockKind, text: impl Into<String>) -> NewBlock {
        NewBlock {
            kind,
            text: text.into(),
            forced: false,
            dual: false,
        }
    }
}

/// Every mutation of a document (§3.4). This is what undo records.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditCommand {
    ReplaceText {
        block: BlockId,
        range: Range<u32>,
        with: String,
    },
    SplitBlock {
        block: BlockId,
        at: u32,
    },
    /// Merges `first` with the block that follows it.
    MergeBlocks {
        first: BlockId,
    },
    SetKind {
        block: BlockId,
        kind: BlockKind,
        forced: bool,
    },
    InsertBlocks {
        after: Option<BlockId>,
        blocks: Vec<NewBlock>,
    },
    DeleteRange {
        from: DocPosition,
        to: DocPosition,
    },
    SetDual {
        block: BlockId,
        dual: bool,
    },
    SetTitlePage {
        field: TitleField,
        value: String,
    },
}

impl EditCommand {
    /// Structural commands always start and end their own undo transaction
    /// (§3.4); only `ReplaceText` coalesces.
    pub fn is_structural(&self) -> bool {
        !matches!(self, EditCommand::ReplaceText { .. })
    }
}

/// What an edit did, as a patch. Flutter applies this rather than refetching
/// the document (§6).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditResult {
    pub changed: Vec<BlockId>,
    pub removed: Vec<BlockId>,
    pub inserted: Vec<BlockId>,
    pub selection: DocSelection,
}

/// A command that could not be applied. The document is untouched when one of
/// these comes back — a rejected edit never half-happens.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditError {
    /// No block with this id, or it was deleted.
    UnknownBlock(BlockId),
    /// Past the end of the block's text, or inside a character.
    BadOffset { block: BlockId, offset: u32 },
    /// The command needs a block after this one and there is none.
    NoBlockAfter(BlockId),
    /// `from` and `to` are in the same document but the range is not coherent.
    BadRange,
    /// The block is Opaque. §3.2 defines an Opaque block as one that always has
    /// provenance and therefore always round-trips exactly — editing one would
    /// take that away, and an edit that removes the `*/` from a boneyard
    /// comment turns the rest of the script into a comment.
    NotEditable(BlockId),
}

impl fmt::Display for EditError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EditError::UnknownBlock(id) => write!(f, "no block with id {}", id.0),
            EditError::BadOffset { block, offset } => write!(
                f,
                "offset {offset} is not a character boundary in block {}",
                block.0
            ),
            EditError::NoBlockAfter(id) => write!(f, "block {} has no block after it", id.0),
            EditError::BadRange => write!(f, "the range is not coherent"),
            EditError::NotEditable(id) => {
                write!(f, "block {} is opaque and round-trips verbatim", id.0)
            }
        }
    }
}

impl std::error::Error for EditError {}
