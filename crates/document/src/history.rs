//! Undo and redo.
//!
//! An inverse is not "the opposite command" but the state the affected slice of
//! the document had before the edit: a [`Inverse::Splice`] carries the original
//! blocks, ids and provenance included. That costs a clone of the blocks an
//! edit touched, and buys two things worth more than the bytes:
//!
//! * undoing an edit restores the block's **provenance**, so an
//!   edit-then-undo-then-save writes the original bytes back rather than a
//!   canonical re-rendering of them (§3.2);
//! * `BlockId`s survive undo, so Flutter's list keys and any selection anchored
//!   to a block still resolve afterwards.
//!
//! Time is deliberately absent. §3.4's 600 ms coalescing rule needs a clock,
//! and this crate has none — it is pure so that the parser, the model and the
//! pagination engine can be tested without one. The document coalesces
//! consecutive text edits *to the same block* into the open transaction and
//! exposes [`crate::Document::commit`]; the caller that owns the clock (the
//! bridge actor, Phase 2) decides when 600 ms have passed.

use slugline_fountain::TitlePage;

use crate::Block;

/// Undo depth caps from §3.4. Whichever is reached first drops the oldest
/// transaction.
const MAX_TRANSACTIONS: usize = 5_000;
const MAX_BYTES: usize = 64 * 1024 * 1024;

/// The state of one region of the document, before an edit touched it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Inverse {
    /// Replace `blocks[at..at + remove]` with `insert`.
    Splice {
        at: usize,
        remove: usize,
        insert: Vec<Block>,
    },
    TitlePage(Box<TitlePage>),
}

impl Inverse {
    fn bytes(&self) -> usize {
        match self {
            Inverse::Splice { insert, .. } => {
                insert.iter().map(|block| block.text.len() + 64).sum()
            }
            Inverse::TitlePage(page) => page
                .entries
                .iter()
                .map(|entry| entry.value.len() + 32)
                .sum(),
        }
    }
}

/// One undo step. Inverses are applied in reverse order.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct Transaction {
    pub(crate) inverses: Vec<Inverse>,
}

impl Transaction {
    fn bytes(&self) -> usize {
        self.inverses.iter().map(Inverse::bytes).sum()
    }
}

#[derive(Debug, Clone, Default)]
pub(crate) struct History {
    done: Vec<Transaction>,
    undone: Vec<Transaction>,
    open: Option<Transaction>,
    /// The block index the open transaction is coalescing text edits into.
    coalescing: Option<usize>,
}

impl History {
    /// Records an inverse into the open transaction, opening one if needed.
    ///
    /// `coalesce_at` is `Some(index)` for a text edit that may join the
    /// previous one when it targets the same block. The first inverse recorded
    /// for a block already restores that block's original state, so a run of
    /// keystrokes costs one clone, not one per keystroke.
    pub(crate) fn record(&mut self, inverse: Inverse, coalesce_at: Option<usize>) {
        match (coalesce_at, self.coalescing) {
            (Some(index), Some(open)) if index == open => return,
            (Some(_), _) => self.close(),
            (None, _) => self.close(),
        }
        self.coalescing = coalesce_at;
        self.open
            .get_or_insert_with(Transaction::default)
            .inverses
            .push(inverse);
        self.undone.clear();
        if coalesce_at.is_none() {
            self.close();
        }
    }

    /// Ends the open transaction, if any. Idempotent.
    pub(crate) fn close(&mut self) {
        self.coalescing = None;
        if let Some(transaction) = self.open.take() {
            if !transaction.inverses.is_empty() {
                self.done.push(transaction);
                self.trim();
            }
        }
    }

    pub(crate) fn take_undo(&mut self) -> Option<Transaction> {
        self.close();
        self.done.pop()
    }

    pub(crate) fn take_redo(&mut self) -> Option<Transaction> {
        self.close();
        self.undone.pop()
    }

    /// Pushes the transaction that would put back what an undo just removed.
    pub(crate) fn push_redo(&mut self, transaction: Transaction) {
        self.undone.push(transaction);
    }

    /// Pushes the transaction that would undo what a redo just applied.
    pub(crate) fn push_done(&mut self, transaction: Transaction) {
        self.done.push(transaction);
        self.trim();
    }

    pub(crate) fn can_undo(&self) -> bool {
        !self.done.is_empty() || self.open.as_ref().is_some_and(|t| !t.inverses.is_empty())
    }

    pub(crate) fn can_redo(&self) -> bool {
        !self.undone.is_empty()
    }

    pub(crate) fn clear(&mut self) {
        *self = History::default();
    }

    fn trim(&mut self) {
        while self.done.len() > MAX_TRANSACTIONS {
            self.done.remove(0);
        }
        let mut total: usize = self.done.iter().map(Transaction::bytes).sum();
        while total > MAX_BYTES && self.done.len() > 1 {
            total -= self.done.remove(0).bytes();
        }
    }
}
