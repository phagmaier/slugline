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

use crate::{Block, BlockId, DocSelection};

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
                insert.iter().map(|block| block.text().len() + 64).sum()
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
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Transaction {
    pub(crate) inverses: Vec<Inverse>,
    pub(crate) before_revision: u64,
    pub(crate) after_revision: u64,
    pub(crate) before_selection: Option<DocSelection>,
    pub(crate) after_selection: Option<DocSelection>,
    pub(crate) selection_initialized: bool,
}

impl Transaction {
    fn new(before_revision: u64, after_revision: u64) -> Transaction {
        Transaction {
            inverses: Vec::new(),
            before_revision,
            after_revision,
            before_selection: None,
            after_selection: None,
            selection_initialized: false,
        }
    }

    fn bytes(&self) -> usize {
        self.inverses.iter().map(Inverse::bytes).sum()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TextEditKind {
    Insert,
    Delete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct CoalesceKey {
    pub(crate) block: BlockId,
    pub(crate) kind: TextEditKind,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct History {
    done: Vec<Transaction>,
    undone: Vec<Transaction>,
    open: Option<Transaction>,
    /// The block identity and operation the open transaction is coalescing.
    coalescing: Option<CoalesceKey>,
    /// While set, [`History::close`] does nothing, so a run of commands lands in
    /// one transaction and one undo takes all of it back.
    grouped: bool,
}

impl History {
    /// Records an inverse into the open transaction, opening one if needed.
    ///
    /// `coalesce` is present only for a pure insertion or pure deletion. The
    /// first inverse recorded for that operation already restores the block's
    /// original state, so a run of keystrokes costs one clone.
    pub(crate) fn record(
        &mut self,
        inverse: Inverse,
        coalesce: Option<CoalesceKey>,
        before_revision: u64,
        after_revision: u64,
    ) {
        match (coalesce, self.coalescing) {
            (Some(key), Some(open)) if key == open => {
                self.open
                    .as_mut()
                    .expect("a coalescing transaction is open")
                    .after_revision = after_revision;
                return;
            }
            (Some(_), _) => self.close(),
            (None, _) => self.close(),
        }
        self.coalescing = coalesce;
        let transaction = self
            .open
            .get_or_insert_with(|| Transaction::new(before_revision, after_revision));
        // A grouped transaction stays open across several commands, so the
        // revision it ends at is the one the last command produced.
        transaction.after_revision = after_revision;
        transaction.inverses.push(inverse);
        self.undone.clear();
        if coalesce.is_none() {
            self.close();
        }
    }

    /// Reopens the transaction that produced `revision`, so that a change the
    /// document makes on the user's behalf lands in the same undo step as the
    /// keystroke that caused it. Answers whether it reopened anything, because
    /// the caller must close what it opens.
    ///
    /// A transaction that is still open needs nothing done to it: it is a run of
    /// typing that has to stay open, and [`History::record_alongside`] appends to
    /// it without disturbing what it is coalescing.
    pub(crate) fn reopen(&mut self, revision: u64) -> bool {
        if self.open.is_some() || self.grouped {
            return false;
        }
        if self
            .done
            .last()
            .is_some_and(|transaction| transaction.after_revision == revision)
        {
            self.open = self.done.pop();
            return true;
        }
        false
    }

    /// Records an inverse into the open transaction without touching what it is
    /// coalescing and without closing it.
    ///
    /// This is for automatic re-classification (§4.2): a kind change the document
    /// made because of a keystroke, which has to be undone with that keystroke
    /// and must not end the run of typing it belongs to. A run's first inverse
    /// already carries the whole block — kind, `forced` and provenance included —
    /// so when the re-classified block is the one being typed into, this adds
    /// nothing that is not already recoverable; it is the *neighbours* that need
    /// an inverse of their own.
    pub(crate) fn record_alongside(
        &mut self,
        inverse: Inverse,
        before_revision: u64,
        after_revision: u64,
    ) {
        let transaction = self
            .open
            .get_or_insert_with(|| Transaction::new(before_revision, after_revision));
        transaction.after_revision = after_revision;
        transaction.inverses.push(inverse);
        self.undone.clear();
    }

    /// Ends the open transaction, if any. Idempotent, and a no-op inside a
    /// group — the group decides when the transaction ends.
    pub(crate) fn close(&mut self) {
        self.coalescing = None;
        if self.grouped {
            return;
        }
        if let Some(transaction) = self.open.take() {
            if !transaction.inverses.is_empty() {
                self.done.push(transaction);
                self.trim();
            }
        }
    }

    /// Starts a group: everything recorded until [`History::end_group`] becomes
    /// a single undo step. Whatever was open before is closed first, so a group
    /// never swallows the keystrokes that preceded it.
    pub(crate) fn begin_group(&mut self) {
        self.close();
        self.grouped = true;
    }

    pub(crate) fn end_group(&mut self) {
        self.grouped = false;
        self.close();
    }

    /// Drops the transaction an undo just pushed onto the redo stack. Used when
    /// the undo was a rollback of a group that failed half-way: the caller was
    /// told the command did nothing, so there is nothing to redo.
    pub(crate) fn drop_last_redo(&mut self) {
        self.undone.pop();
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
        self.trim();
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

    /// Attaches the UI selection to the transaction that produced `revision`.
    /// A coalesced typing run keeps the first pre-edit selection and updates the
    /// post-edit selection after every keystroke.
    pub(crate) fn set_selections(
        &mut self,
        revision: u64,
        before: Option<DocSelection>,
        after: Option<DocSelection>,
    ) {
        let transaction = self
            .open
            .as_mut()
            .filter(|transaction| transaction.after_revision == revision)
            .or_else(|| {
                self.done
                    .last_mut()
                    .filter(|transaction| transaction.after_revision == revision)
            });
        if let Some(transaction) = transaction {
            if !transaction.selection_initialized {
                transaction.before_selection = before;
                transaction.selection_initialized = true;
            }
            transaction.after_selection = after;
        }
    }

    fn trim(&mut self) {
        self.trim_to(MAX_TRANSACTIONS, MAX_BYTES);
    }

    fn trim_to(&mut self, max_transactions: usize, max_bytes: usize) {
        let mut count = self.done.len() + self.undone.len();
        let mut total: usize = self
            .done
            .iter()
            .chain(&self.undone)
            .map(Transaction::bytes)
            .sum();
        // Keep the newest/nearest transaction even if that one edit exceeds
        // the byte budget. Dropping it would make a successful edit impossible
        // to undo; the limit is therefore soft for one transaction only.
        while (count > max_transactions || total > max_bytes) && count > 1 {
            // Index zero is furthest from the current state in both stacks.
            let remove_done = match (self.done.first(), self.undone.first()) {
                (Some(done), Some(undone)) => done.after_revision <= undone.after_revision,
                (Some(_), None) => true,
                (None, Some(_)) => false,
                (None, None) => break,
            };
            let removed = if remove_done {
                self.done.remove(0)
            } else {
                self.undone.remove(0)
            };
            count -= 1;
            total = total.saturating_sub(removed.bytes());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use slugline_fountain::{TitleEntry, TitleField};

    fn transaction(bytes: usize) -> Transaction {
        Transaction {
            inverses: vec![Inverse::TitlePage(Box::new(TitlePage {
                entries: vec![TitleEntry {
                    field: TitleField::Title,
                    value: "x".repeat(bytes),
                }],
                provenance: None,
            }))],
            before_revision: 0,
            after_revision: 1,
            before_selection: None,
            after_selection: None,
            selection_initialized: false,
        }
    }

    #[test]
    fn byte_limit_covers_both_stacks_but_keeps_one_undoable_edit() {
        let mut history = History::default();
        history.done.push(transaction(40));
        history.undone.push(transaction(40));
        history.trim_to(10, 100);
        assert_eq!(history.done.len() + history.undone.len(), 1);

        history.done.clear();
        history.undone.clear();
        history.done.push(transaction(100));
        history.trim_to(10, 100);
        assert_eq!(history.done.len(), 1);
    }
}
