//! What the crash journal records, and what replaying it means.
//!
//! §Phase 4's journal "records committed edit commands between saves". It
//! records their **effect** rather than the commands themselves, and the
//! difference is worth stating because it is the whole reason recovery is
//! simple.
//!
//! A command is an instruction — "split block 12 at offset 9" — and replaying
//! one means re-running every rule that decided what it did: the Enter/Tab table
//! of `workflow.rs`, `Document::reinfer`, the validity checks in `edit.rs`. Get
//! any of them a version out of step with the session that crashed and the
//! recovered script is quietly not the one the writer was looking at. A
//! [`Patch`] is an outcome — "block 12 now reads this, and block 40 appeared
//! after it saying that" — and replaying one is list surgery with no rules in
//! it at all. Losing user text is a P0 defect (§1.2); the recovery path is the
//! last place to want cleverness.
//!
//! It is also small. One patch is the blocks one edit touched, which for a
//! keystroke is one paragraph, so the journal can be written after **every**
//! edit rather than every transaction — which is what makes §Phase 4's exit
//! criterion ("never lost a keystroke beyond the last one") reachable at all.

use slugline_fountain::BlockKind;

use crate::BlockId;

/// One block, exactly as it stood after the edit that touched it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockSnapshot {
    pub id: BlockId,
    pub kind: BlockKind,
    pub text: String,
    pub forced: bool,
    pub dual: bool,
}

/// What one edit did to the block list.
///
/// Applied in the order the fields are declared — remove, update, insert — which
/// is the same order §6 requires of Dart when it applies an `EditResult`. The
/// indices in [`Patch::inserted`] are positions **after** the edit, so they are
/// only meaningful once the removals have happened.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Patch {
    pub removed: Vec<BlockId>,
    pub changed: Vec<BlockSnapshot>,
    /// `(index after the edit, block)`, in ascending index order.
    pub inserted: Vec<(u32, BlockSnapshot)>,
}

impl Patch {
    /// Whether this patch would change anything.
    pub fn is_empty(&self) -> bool {
        self.removed.is_empty() && self.changed.is_empty() && self.inserted.is_empty()
    }
}

/// Why a recorded patch could not be replayed onto a document.
///
/// Every one of these means the journal and the file it is being replayed onto
/// disagree — the file was edited by something else between the crash and the
/// recovery, or the journal belongs to a different script. Recovery must stop
/// and say so rather than apply half a session (§10).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReplayError {
    /// The patch changes or removes a block the document does not have.
    UnknownBlock(BlockId),
    /// The patch inserts a block whose id is already taken.
    DuplicateBlock(BlockId),
    /// An insertion index is past the end of the block list.
    BadIndex(u32),
}

impl std::fmt::Display for ReplayError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReplayError::UnknownBlock(id) => {
                write!(f, "the journal changes block {}, which is not here", id.0)
            }
            ReplayError::DuplicateBlock(id) => {
                write!(
                    f,
                    "the journal inserts block {}, which already exists",
                    id.0
                )
            }
            ReplayError::BadIndex(index) => {
                write!(f, "the journal inserts at index {index}, past the end")
            }
        }
    }
}

impl std::error::Error for ReplayError {}
