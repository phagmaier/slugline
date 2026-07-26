//! The canonical document: blocks with stable identities, edit commands, and
//! the history that inverts them.

use std::ops::Range;
use std::sync::Arc;

use slugline_fountain::{
    infer_kind, needs_blank_between, parse, serialise, BlockKind, Context as InferContext,
    ElementRef, LineEnding, Output, TitlePage,
};

use crate::edit::{
    DocPosition, DocSelection, EditCommand, EditError, EditResult, InvalidBlockReason, NewBlock,
};
use crate::find::{self, FindQuery, Match};
use crate::history::{CoalesceKey, History, Inverse, TextEditKind, Transaction};
use crate::recovery::{BlockSnapshot, Patch, ReplayError};
use crate::BlockId;

/// One element of the script, with an identity Flutter can hold on to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    id: BlockId,
    kind: BlockKind,
    /// User-visible text with emphasis markup retained inline (§3.1).
    text: String,
    /// The element type was pinned, by the user or by explicit syntax.
    forced: bool,
    /// Dual-dialogue right column marker.
    dual: bool,
    /// Byte range in the original source this block came from. `None` once the
    /// block has been edited, which is what sends it down the serialiser's
    /// canonical path instead of the verbatim one (§3.2).
    provenance: Option<Range<usize>>,
}

impl Block {
    pub fn id(&self) -> BlockId {
        self.id
    }

    pub fn kind(&self) -> BlockKind {
        self.kind
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn forced(&self) -> bool {
        self.forced
    }

    pub fn dual(&self) -> bool {
        self.dual
    }

    pub fn provenance(&self) -> Option<&Range<usize>> {
        self.provenance.as_ref()
    }
}

/// A parsed script, its edit history, and the bytes it was opened from.
#[derive(Debug, Clone, Default)]
pub struct Document {
    title_page: TitlePage,
    blocks: Vec<Block>,
    next_id: u64,
    /// Byte-for-byte original file content, retained for lossless
    /// round-tripping (§3.1).
    original_source: Option<Arc<str>>,
    bom: bool,
    line_ending: LineEnding,
    history: History,
    revision: u64,
    saved_revision: u64,
    next_revision: u64,
}

/// The immutable parts needed to serialise one document revision.
///
/// Long-running bridge jobs may own this without moving a [`Document`] off its
/// actor thread. History and revision bookkeeping are deliberately absent.
#[derive(Debug, Clone)]
pub struct SerialisationSnapshot {
    title_page: TitlePage,
    blocks: Vec<Block>,
    original_source: Option<Arc<str>>,
    bom: bool,
    line_ending: LineEnding,
}

impl SerialisationSnapshot {
    pub fn serialise(&self) -> String {
        serialise_parts(
            &self.title_page,
            &self.blocks,
            self.original_source.as_deref(),
            self.bom,
            self.line_ending,
        )
    }
}

impl Document {
    /// An empty document, as a new script starts.
    pub fn empty() -> Document {
        Document::default()
    }

    /// A new script: one empty Action block and no history.
    ///
    /// [`Document::empty`] has no blocks at all, which is the right answer for
    /// "nothing has been written" but the wrong one for an editor, which needs
    /// somewhere to put the caret before the first keystroke. The block is
    /// constructed rather than inserted so that the first thing a new script can
    /// undo is the user's own first edit.
    pub fn blank() -> Document {
        Document {
            blocks: vec![Block {
                id: BlockId(1),
                kind: BlockKind::Action,
                text: String::new(),
                forced: false,
                dual: false,
                provenance: None,
            }],
            next_id: 1,
            ..Document::default()
        }
    }

    /// Parses Fountain source. Total: every input produces a document.
    pub fn parse(source: &str) -> Document {
        let script = parse(source);
        let mut next_id = 0;
        let blocks = script
            .elements
            .into_iter()
            .map(|element| {
                next_id += 1;
                Block {
                    id: BlockId(next_id),
                    kind: element.kind,
                    text: element.text,
                    forced: element.forced,
                    dual: element.dual,
                    provenance: element.provenance,
                }
            })
            .collect();

        Document {
            title_page: script.title_page,
            blocks,
            next_id,
            original_source: Some(Arc::from(source)),
            bom: script.bom,
            line_ending: script.line_ending,
            history: History::default(),
            revision: 0,
            saved_revision: 0,
            next_revision: 0,
        }
    }

    /// Writes the document back to Fountain. Untouched blocks are emitted from
    /// the original bytes, so a document nobody edited serialises to exactly
    /// what it was opened from.
    pub fn serialise(&self) -> String {
        serialise_parts(
            &self.title_page,
            &self.blocks,
            self.original_source.as_deref(),
            self.bom,
            self.line_ending,
        )
    }

    /// Captures one revision's serialisation inputs for work off the owner
    /// thread. The original source is shared; only current block data is copied.
    pub fn serialisation_snapshot(&self) -> SerialisationSnapshot {
        SerialisationSnapshot {
            title_page: self.title_page.clone(),
            blocks: self.blocks.clone(),
            original_source: self.original_source.clone(),
            bom: self.bom,
            line_ending: self.line_ending,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.title_page.is_empty()
            && self.blocks.iter().all(|block| {
                block.text.is_empty()
                    && matches!(
                        block.kind,
                        BlockKind::Action
                            | BlockKind::Dialogue
                            | BlockKind::Parenthetical
                            | BlockKind::SceneHeading
                    )
            })
    }

    pub fn line_ending(&self) -> LineEnding {
        self.line_ending
    }

    pub fn title_page(&self) -> &TitlePage {
        &self.title_page
    }

    pub fn blocks(&self) -> &[Block] {
        &self.blocks
    }

    /// Whether the document has unsaved edits (§6, `doc_dirty`).
    pub fn is_dirty(&self) -> bool {
        self.revision != self.saved_revision
    }

    /// A monotonic counter that changes on every edit and nothing else.
    ///
    /// A save serialises the document off the actor thread (§2.3), so by the
    /// time it comes back to say it succeeded, the writer may have typed. This
    /// is what lets it say *which* document it wrote.
    pub fn revision(&self) -> u64 {
        self.revision
    }

    /// Clears the dirty flag as far as [`Document::revision`] said when the
    /// bytes were taken.
    ///
    /// An edit that landed while the file was being written stays unsaved, which
    /// is the honest answer: it is not in the file. Marking the whole document
    /// clean instead would silently drop it.
    pub fn mark_saved_at(&mut self, revision: u64) {
        self.history.close();
        self.saved_revision = revision.min(self.revision);
    }

    /// Clears the dirty flag.
    ///
    /// Re-anchoring provenance to the newly written bytes is **deliberately not
    /// done**, and Phase 4 shipped without it. A saved document goes on
    /// serialising from the source it was opened with: correct — the bytes it
    /// would write are the bytes it just wrote — at the cost of keeping the
    /// original source alive for the life of the session. Re-anchoring would
    /// buy back that memory and nothing else, so it is deferred until something
    /// measures it as a problem rather than scheduled to a phase.
    pub fn mark_saved(&mut self) {
        self.mark_saved_at(self.revision);
    }

    pub fn index_of(&self, id: BlockId) -> Option<usize> {
        self.blocks.iter().position(|block| block.id == id)
    }

    pub fn block(&self, id: BlockId) -> Option<&Block> {
        self.blocks.iter().find(|block| block.id == id)
    }

    pub fn can_undo(&self) -> bool {
        self.history.can_undo()
    }

    pub fn can_redo(&self) -> bool {
        self.history.can_redo()
    }

    /// Ends the open undo transaction. The caller owning the clock calls this
    /// when §3.4's 600 ms of quiet have passed, or on any event that should not
    /// be undone together with what preceded it.
    pub fn commit(&mut self) {
        self.history.close();
    }

    /// Applies a command, or returns an error having changed nothing.
    pub fn apply(&mut self, command: EditCommand) -> Result<EditResult, EditError> {
        let before = self.inferred_selection(&command);
        self.apply_with_selection(command, before)
    }

    /// Applies a command while recording the caller's exact pre-edit
    /// selection, so undo and redo can restore selection direction as well as
    /// document content.
    pub fn apply_with_selection(
        &mut self,
        command: EditCommand,
        before: Option<DocSelection>,
    ) -> Result<EditResult, EditError> {
        if let Some(selection) = before {
            self.check_selection(selection)?;
        }
        let revision = self.revision;
        let result = self.apply_command(command)?;
        if self.revision != revision {
            self.history
                .set_selections(self.revision, before, result.selection);
        }
        Ok(result)
    }

    /// Applies several commands as **one** undo transaction.
    ///
    /// Either every command applies or none of them does: a failure part-way
    /// through rolls the group back and reports the error, leaving the document
    /// and the history exactly as they were. That atomicity is what lets the
    /// bridge express a paste — delete the selection, split, insert, merge — as
    /// something the user undoes with one keystroke (§3.4).
    pub fn apply_all(
        &mut self,
        commands: Vec<EditCommand>,
        before: Option<DocSelection>,
    ) -> Result<EditResult, EditError> {
        self.apply_group(before, |group| {
            for command in commands {
                group.apply(command)?;
            }
            Ok(())
        })
    }

    /// The same, for a sequence that cannot be written down in advance.
    ///
    /// `plan` applies commands through the [`Grouped`] it is handed and sees
    /// each result as it goes, so it can name a block that an earlier command in
    /// the same transaction created — which is what a paste around a split
    /// needs.
    pub fn apply_group<F>(
        &mut self,
        before: Option<DocSelection>,
        plan: F,
    ) -> Result<EditResult, EditError>
    where
        F: FnOnce(&mut Grouped<'_>) -> Result<(), EditError>,
    {
        if let Some(selection) = before {
            self.check_selection(selection)?;
        }
        let start_revision = self.revision;
        self.history.begin_group();

        let mut group = Grouped {
            document: self,
            merged: Merged::default(),
        };
        let outcome = plan(&mut group);
        let merged = group.merged;
        self.history.end_group();

        if let Err(error) = outcome {
            if self.revision != start_revision {
                self.undo();
                // The caller is being told the command did nothing, so there is
                // nothing for a redo to put back.
                self.history.drop_last_redo();
            }
            return Err(error);
        }

        let result = merged.into_result();
        if self.revision != start_revision {
            self.history
                .set_selections(self.revision, before, result.selection);
        }
        Ok(result)
    }

    fn apply_command(&mut self, command: EditCommand) -> Result<EditResult, EditError> {
        let result = match command {
            EditCommand::ReplaceText { block, range, with } => {
                self.replace_text(block, range, &with)
            }
            EditCommand::SplitBlock { block, at } => self.split_block(block, at),
            EditCommand::MergeBlocks { first } => self.merge_blocks(first),
            EditCommand::SetKind {
                block,
                kind,
                forced,
            } => self.set_kind(block, kind, forced),
            EditCommand::InsertBlocks { after, blocks } => self.insert_blocks(after, blocks),
            EditCommand::DeleteRange { from, to } => self.delete_range(from, to),
            EditCommand::SetDual { block, dual } => self.set_dual(block, dual),
            EditCommand::SetTitlePage { field, value } => {
                if self.title_page.get(&field) == (!value.is_empty()).then_some(value.as_str()) {
                    return Ok(EditResult {
                        changed: Vec::new(),
                        removed: Vec::new(),
                        inserted: Vec::new(),
                        selection: self.caret_at_start(),
                    });
                }
                self.record(Inverse::TitlePage(Box::new(self.title_page.clone())), None);
                self.title_page.set(field, value);
                Ok(EditResult {
                    changed: Vec::new(),
                    removed: Vec::new(),
                    inserted: Vec::new(),
                    selection: self.caret_at_start(),
                })
            }
        }?;
        Ok(result)
    }

    /// Applies a patch the crash journal recorded (§Phase 4).
    ///
    /// Three things separate this from [`Document::apply`], and all three are
    /// deliberate:
    ///
    /// * **No history.** A recovered session cannot be undone into — the
    ///   transactions it would undo belong to a process that is gone. Recovery
    ///   hands the writer a document and an unbroken undo stack starting from
    ///   there.
    /// * **No inference.** A patch is an outcome, not an instruction; the kinds
    ///   in it are the kinds the writer was looking at when the machine died.
    ///   Re-inferring them would be second-guessing the record.
    /// * **No validity check.** The state in the patch was in a live document,
    ///   so it was already valid when it was recorded. What *is* checked is that
    ///   the patch fits this document at all — see [`ReplayError`].
    ///
    /// The document is left dirty, because it is: the file on disk is the one
    /// the journal was recorded against.
    pub fn replay(&mut self, patch: &Patch) -> Result<(), ReplayError> {
        // Everything is validated before anything is written. A half-applied
        // patch is a document nobody can reason about, and this runs against a
        // file the user is about to be shown.
        for id in &patch.removed {
            if self.index_of(*id).is_none() {
                return Err(ReplayError::UnknownBlock(*id));
            }
        }
        for snapshot in &patch.changed {
            if self.index_of(snapshot.id).is_none() && !patch.removed.contains(&snapshot.id) {
                return Err(ReplayError::UnknownBlock(snapshot.id));
            }
        }
        for (_, snapshot) in &patch.inserted {
            if self.index_of(snapshot.id).is_some() {
                return Err(ReplayError::DuplicateBlock(snapshot.id));
            }
        }

        self.blocks
            .retain(|block| !patch.removed.contains(&block.id));

        for snapshot in &patch.changed {
            let Some(index) = self.index_of(snapshot.id) else {
                // Changed and then removed by the same edit. The removal wins;
                // it is the later fact.
                continue;
            };
            let block = &mut self.blocks[index];
            block.kind = snapshot.kind;
            block.text.clone_from(&snapshot.text);
            block.forced = snapshot.forced;
            block.dual = snapshot.dual;
            // The bytes no longer match the file they were read from, so the
            // serialiser must take this block down its canonical path (§3.2).
            block.provenance = None;
        }

        for (index, snapshot) in &patch.inserted {
            let index = *index as usize;
            if index > self.blocks.len() {
                return Err(ReplayError::BadIndex(index as u32));
            }
            self.blocks.insert(
                index,
                Block {
                    id: snapshot.id,
                    kind: snapshot.kind,
                    text: snapshot.text.clone(),
                    forced: snapshot.forced,
                    dual: snapshot.dual,
                    provenance: None,
                },
            );
            // §3.1: an id is never reused. The journal's ids were minted by the
            // session that crashed, so the counter has to clear them all.
            self.next_id = self.next_id.max(snapshot.id.0);
        }

        self.next_revision += 1;
        self.revision = self.next_revision;
        Ok(())
    }

    /// The block with this id, as the journal would record it.
    pub fn snapshot(&self, id: BlockId) -> Option<BlockSnapshot> {
        self.block(id).map(|block| BlockSnapshot {
            id: block.id,
            kind: block.kind,
            text: block.text.clone(),
            forced: block.forced,
            dual: block.dual,
        })
    }

    pub fn undo(&mut self) -> Option<EditResult> {
        let transaction = self.history.take_undo()?;
        let revision = transaction.before_revision;
        let selection = transaction.before_selection;
        let (redo, result) = self.invert(transaction, selection);
        self.history.push_redo(redo);
        self.revision = revision;
        Some(result)
    }

    pub fn redo(&mut self) -> Option<EditResult> {
        let transaction = self.history.take_redo()?;
        let revision = transaction.after_revision;
        let selection = transaction.after_selection;
        let (undo, result) = self.invert(transaction, selection);
        self.history.push_done(undo);
        self.revision = revision;
        Some(result)
    }

    // ---- commands ----

    fn replace_text(
        &mut self,
        id: BlockId,
        range: Range<u32>,
        with: &str,
    ) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        if range.start > range.end {
            return Err(EditError::BadRange);
        }
        let block = &self.blocks[index];
        check_editable(block)?;
        check_offset(block, range.start)?;
        check_offset(block, range.end)?;

        if block.text[range.start as usize..range.end as usize] == *with {
            return Ok(EditResult {
                changed: Vec::new(),
                removed: Vec::new(),
                inserted: Vec::new(),
                selection: Some(DocSelection::caret(DocPosition::new(
                    id,
                    range.start + with.len() as u32,
                ))),
            });
        }

        let mut text = block.text.clone();
        text.replace_range(range.start as usize..range.end as usize, with);
        validate_block_state(Some(id), block.kind, &text, block.dual)?;
        let coalesce = match (range.is_empty(), with.is_empty()) {
            (true, false) => Some(CoalesceKey {
                block: id,
                kind: TextEditKind::Insert,
            }),
            (false, true) => Some(CoalesceKey {
                block: id,
                kind: TextEditKind::Delete,
            }),
            _ => None,
        };

        self.record(
            Inverse::Splice {
                at: index,
                remove: 1,
                insert: vec![block.clone()],
            },
            coalesce,
        );

        let block = &mut self.blocks[index];
        block.text = text;
        block.provenance = None;

        Ok(EditResult {
            changed: vec![id],
            removed: Vec::new(),
            inserted: Vec::new(),
            selection: Some(DocSelection::caret(DocPosition::new(
                id,
                range.start + with.len() as u32,
            ))),
        })
    }

    fn split_block(&mut self, id: BlockId, at: u32) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        check_editable(&self.blocks[index])?;
        check_offset(&self.blocks[index], at)?;

        let block = &self.blocks[index];
        let head = &block.text[..at as usize];
        let tail = &block.text[at as usize..];
        validate_block_state(Some(id), block.kind, head, block.dual)?;
        validate_block_state(None, block.kind, tail, false)?;

        self.record(
            Inverse::Splice {
                at: index,
                remove: 2,
                insert: vec![self.blocks[index].clone()],
            },
            None,
        );

        let new_id = self.fresh_id();
        let block = &mut self.blocks[index];
        let tail = block.text.split_off(at as usize);
        block.provenance = None;
        let kind = block.kind;
        let forced = block.forced;
        self.blocks.insert(
            index + 1,
            Block {
                id: new_id,
                kind,
                text: tail,
                forced,
                dual: false,
                provenance: None,
            },
        );

        Ok(EditResult {
            changed: vec![id],
            removed: Vec::new(),
            inserted: vec![new_id],
            selection: Some(DocSelection::caret(DocPosition::new(new_id, 0))),
        })
    }

    fn merge_blocks(&mut self, first: BlockId) -> Result<EditResult, EditError> {
        let index = self.index_of(first).ok_or(EditError::UnknownBlock(first))?;
        if index + 1 >= self.blocks.len() {
            return Err(EditError::NoBlockAfter(first));
        }
        check_editable(&self.blocks[index])?;
        check_editable(&self.blocks[index + 1])?;

        let mut text = self.blocks[index].text.clone();
        text.push_str(&self.blocks[index + 1].text);
        validate_block_state(
            Some(first),
            self.blocks[index].kind,
            &text,
            self.blocks[index].dual,
        )?;

        self.record(
            Inverse::Splice {
                at: index,
                remove: 1,
                insert: vec![self.blocks[index].clone(), self.blocks[index + 1].clone()],
            },
            None,
        );

        let removed = self.blocks.remove(index + 1);
        let block = &mut self.blocks[index];
        let junction = block.text.len() as u32;
        block.text = text;
        block.provenance = None;

        Ok(EditResult {
            changed: vec![first],
            removed: vec![removed.id],
            inserted: Vec::new(),
            selection: Some(DocSelection::caret(DocPosition::new(first, junction))),
        })
    }

    fn set_kind(
        &mut self,
        id: BlockId,
        kind: BlockKind,
        forced: bool,
    ) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        check_editable(&self.blocks[index])?;
        if self.blocks[index].kind == kind && self.blocks[index].forced == forced {
            return Ok(EditResult {
                changed: Vec::new(),
                removed: Vec::new(),
                inserted: Vec::new(),
                selection: self.caret_in(index),
            });
        }
        validate_block_state(
            Some(id),
            kind,
            &self.blocks[index].text,
            self.blocks[index].dual,
        )?;
        let old_kind = self.blocks[index].kind;
        let resettle = self.predecessor_needs_rewriting(index, Some(old_kind), Some(kind));
        let at = if resettle { index - 1 } else { index };

        self.record(
            Inverse::Splice {
                at,
                remove: index + 1 - at,
                insert: self.blocks[at..=index].to_vec(),
            },
            None,
        );

        if resettle {
            self.blocks[index - 1].provenance = None;
        }
        let block = &mut self.blocks[index];
        block.kind = kind;
        block.forced = forced;
        block.provenance = None;

        Ok(EditResult {
            changed: vec![id],
            removed: Vec::new(),
            inserted: Vec::new(),
            selection: self.caret_in(index),
        })
    }

    fn set_dual(&mut self, id: BlockId, dual: bool) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        check_editable(&self.blocks[index])?;

        if self.blocks[index].dual == dual {
            return Ok(EditResult {
                changed: Vec::new(),
                removed: Vec::new(),
                inserted: Vec::new(),
                selection: self.caret_in(index),
            });
        }
        validate_block_state(
            Some(id),
            self.blocks[index].kind,
            &self.blocks[index].text,
            dual,
        )?;

        self.record(
            Inverse::Splice {
                at: index,
                remove: 1,
                insert: vec![self.blocks[index].clone()],
            },
            None,
        );

        let block = &mut self.blocks[index];
        block.dual = dual;
        block.provenance = None;

        Ok(EditResult {
            changed: vec![id],
            removed: Vec::new(),
            inserted: Vec::new(),
            selection: self.caret_in(index),
        })
    }

    fn insert_blocks(
        &mut self,
        after: Option<BlockId>,
        blocks: Vec<NewBlock>,
    ) -> Result<EditResult, EditError> {
        let index = match after {
            Some(id) => self.index_of(id).ok_or(EditError::UnknownBlock(id))? + 1,
            None => 0,
        };
        let Some(first_new) = blocks.first().map(|block| block.kind) else {
            return Err(EditError::BadRange);
        };
        for block in &blocks {
            validate_block_state(None, block.kind, &block.text, block.dual)?;
        }

        let old_next = self.blocks.get(index).map(|block| block.kind);
        let resettle =
            index > 0 && self.predecessor_needs_rewriting(index, old_next, Some(first_new));
        let at = if resettle { index - 1 } else { index };

        self.record(
            Inverse::Splice {
                at,
                remove: index - at + blocks.len(),
                insert: self.blocks[at..index].to_vec(),
            },
            None,
        );

        if resettle {
            self.blocks[index - 1].provenance = None;
        }

        let inserted: Vec<Block> = blocks
            .into_iter()
            .map(|new| Block {
                id: self.fresh_id(),
                kind: new.kind,
                text: new.text,
                forced: new.forced,
                dual: new.dual,
                provenance: None,
            })
            .collect();
        let ids: Vec<BlockId> = inserted.iter().map(|block| block.id).collect();
        let last = *ids.last().expect("checked non-empty above");
        let caret = inserted
            .last()
            .map(|block| block.text.len() as u32)
            .unwrap_or_default();
        self.blocks.splice(index..index, inserted);

        Ok(EditResult {
            changed: Vec::new(),
            removed: Vec::new(),
            inserted: ids,
            selection: Some(DocSelection::caret(DocPosition::new(last, caret))),
        })
    }

    fn delete_range(
        &mut self,
        from: DocPosition,
        to: DocPosition,
    ) -> Result<EditResult, EditError> {
        let first = self
            .index_of(from.block)
            .ok_or(EditError::UnknownBlock(from.block))?;
        let last = self
            .index_of(to.block)
            .ok_or(EditError::UnknownBlock(to.block))?;
        let ((first, from), (last, to)) = if (first, from.offset) <= (last, to.offset) {
            ((first, from), (last, to))
        } else {
            ((last, to), (first, from))
        };
        for block in &self.blocks[first..=last] {
            check_editable(block)?;
        }
        check_offset(&self.blocks[first], from.offset)?;
        check_offset(&self.blocks[last], to.offset)?;

        if first == last && from.offset == to.offset {
            return Ok(EditResult {
                changed: Vec::new(),
                removed: Vec::new(),
                inserted: Vec::new(),
                selection: Some(DocSelection::caret(from)),
            });
        }

        let mut text = self.blocks[first].text[..from.offset as usize].to_string();
        text.push_str(&self.blocks[last].text[to.offset as usize..]);
        validate_block_state(
            Some(self.blocks[first].id),
            self.blocks[first].kind,
            &text,
            self.blocks[first].dual,
        )?;

        self.record(
            Inverse::Splice {
                at: first,
                remove: 1,
                insert: self.blocks[first..=last].to_vec(),
            },
            None,
        );

        let removed: Vec<BlockId> = self.blocks[first + 1..=last]
            .iter()
            .map(|block| block.id)
            .collect();
        // The surviving block keeps what was before the start of the range and
        // what was after its end; everything between them, blocks included,
        // goes.
        self.blocks.drain(first + 1..=last);

        let block = &mut self.blocks[first];
        block.text = text;
        block.provenance = None;
        let id = block.id;

        Ok(EditResult {
            changed: vec![id],
            removed,
            inserted: Vec::new(),
            selection: Some(DocSelection::caret(DocPosition::new(id, from.offset))),
        })
    }

    // ---- automatic classification (§4.2) ----

    /// Re-classifies the blocks an edit disturbed and folds what it changed into
    /// `result`.
    ///
    /// §4.2 sets the scope, and every clause of it is a guard here:
    ///
    /// * **one block either side of the edit.** That is exactly how far §4.1's
    ///   rules reach, and it is also where the caret is after an edit.
    /// * **never a forced block.** `forced` is the record that a human said what
    ///   this element is, whether by typing `.` or by pressing the shortcut, and
    ///   automatic behaviour does not get to argue with it.
    /// * **never a block the caret is not in and did not just leave.** `before`
    ///   is where the caret was; `result.selection` is where it is. Anything
    ///   outside the union of those two and the edit's own neighbourhood is text
    ///   the writer is not looking at, and changing how it reads under them is
    ///   the "text jumping around" §4.2 forbids.
    ///
    /// It only ever changes `kind`. No text is touched, no block is created or
    /// destroyed, and the caret does not move — so the patch grows by a few ids
    /// and nothing else. A change that the model would refuse is skipped rather
    /// than reported: inference is a convenience, and a convenience never fails
    /// an edit that has already applied.
    pub fn reinfer(&mut self, result: &mut EditResult, before: Option<DocSelection>) {
        let window = self.inference_window(result, before);
        if window.is_empty() {
            return;
        }
        // Ascending, so a block that has just been reclassified is the context
        // the one below it is judged against — deleting a cue's text settles the
        // cue before the dialogue under it is asked what it is.
        let reopened = self.history.reopen(self.revision);
        for index in window {
            if !self.reinfer_at(index) {
                continue;
            }
            let id = self.blocks[index].id;
            if !result.changed.contains(&id)
                && !result.inserted.contains(&id)
                && !result.removed.contains(&id)
            {
                result.changed.push(id);
            }
        }
        if reopened {
            self.history.close();
        }
    }

    /// The block indices §4.2 allows re-classifying after this edit.
    fn inference_window(&self, result: &EditResult, before: Option<DocSelection>) -> Vec<usize> {
        let mut window = Vec::new();
        for id in result.changed.iter().chain(&result.inserted) {
            if let Some(index) = self.index_of(*id) {
                window.push(index.saturating_sub(1));
                window.push(index);
                window.push(index + 1);
            }
        }
        for selection in [before, result.selection].into_iter().flatten() {
            for position in [selection.anchor, selection.focus] {
                if let Some(index) = self.index_of(position.block) {
                    window.push(index);
                }
            }
        }
        window.retain(|index| *index < self.blocks.len());
        window.sort_unstable();
        window.dedup();
        window
    }

    /// Re-classifies one block, and says whether its kind changed.
    fn reinfer_at(&mut self, index: usize) -> bool {
        let block = &self.blocks[index];
        // A dual cue is pinned by the `^` it is written with: re-classifying it
        // would leave the flag on a kind that cannot carry it.
        if block.forced || block.dual {
            return false;
        }
        let inferred = infer_kind(
            &block.text,
            InferContext {
                previous: index.checked_sub(1).map(|i| self.blocks[i].kind),
                current: block.kind,
                next: self.blocks.get(index + 1).map(|block| block.kind),
            },
        );
        let Some(kind) = inferred.filter(|kind| *kind != block.kind) else {
            return false;
        };
        if validate_block_state(Some(block.id), kind, &block.text, block.dual).is_err() {
            return false;
        }

        let old_kind = block.kind;
        let resettle = self.predecessor_needs_rewriting(index, Some(old_kind), Some(kind));
        let at = if resettle { index - 1 } else { index };
        self.record_alongside(Inverse::Splice {
            at,
            remove: index + 1 - at,
            insert: self.blocks[at..=index].to_vec(),
        });
        if resettle {
            self.blocks[index - 1].provenance = None;
        }
        let block = &mut self.blocks[index];
        block.kind = kind;
        block.provenance = None;
        true
    }

    // ---- find and replace ----

    /// Every match of `query`, in document order (§6's `find`).
    pub fn find(&self, query: &FindQuery) -> Vec<Match> {
        self.blocks
            .iter()
            .filter(|block| query.searches(block.kind))
            .flat_map(|block| {
                find::matches_in(&block.text, query)
                    .into_iter()
                    .map(move |range| Match {
                        block: block.id,
                        range,
                    })
            })
            .collect()
    }

    /// Replaces every match with `with`, as **one** undo transaction (§Phase 3).
    ///
    /// Within a block the matches are replaced back to front, so that the
    /// offsets of the ones not yet reached are still the offsets they were found
    /// at. Nothing is re-classified afterwards: this is a bulk text operation
    /// over blocks the writer is not looking at, which is precisely the case
    /// §4.2 says to leave alone. The serialiser still protects whatever the new
    /// text turned into, so the file remains readable either way.
    pub fn replace_all(
        &mut self,
        query: &FindQuery,
        with: &str,
        before: Option<DocSelection>,
    ) -> Result<EditResult, EditError> {
        let mut matches = self.find(query);
        if matches.is_empty() {
            return Ok(EditResult {
                changed: Vec::new(),
                removed: Vec::new(),
                inserted: Vec::new(),
                selection: before.or_else(|| self.caret_at_start()),
            });
        }
        matches.reverse();
        let with = with.to_owned();
        self.apply_group(before, |group| {
            for hit in matches {
                group.apply(EditCommand::ReplaceText {
                    block: hit.block,
                    range: hit.range,
                    with: with.clone(),
                })?;
            }
            Ok(())
        })
    }

    /// The character cue this block's text already names elsewhere in the
    /// script, if it does — §Phase 3's "typing an existing character name in an
    /// Action-position block suggests Character".
    ///
    /// A **suggestion**: it changes nothing, and it is deliberately not wired
    /// into [`Document::reinfer`]. Promoting a line to a cue because it matches a
    /// name would rewrite an all-capitals line of action the moment a character
    /// happened to share its wording. The editor shows this and Tab accepts it,
    /// so the writer is the one who decides.
    pub fn character_suggestion(&self, id: BlockId) -> Option<&str> {
        let block = self.block(id)?;
        let name = block.text.trim();
        // Action is also what makes this "an Action-position block": a block
        // inside a speech is dialogue or a parenthetical, never action.
        if block.kind != BlockKind::Action || block.forced || name.is_empty() || name.contains('\n')
        {
            return None;
        }
        self.blocks
            .iter()
            .filter(|other| other.kind == BlockKind::Character && other.id != id)
            .map(|other| other.text.trim())
            .find(|cue| cue.eq_ignore_ascii_case(name))
    }

    // ---- clipboard ----

    /// The Fountain text of everything between two positions.
    ///
    /// A selection inside one block is plain text — it has no element structure
    /// to carry. A selection spanning blocks is written as Fountain, and the
    /// blocks it covers *whole* keep their provenance, so copying an untouched
    /// scene and pasting it back reproduces the bytes it was written with rather
    /// than a canonical rendering of them (§3.2).
    pub fn extract(&self, from: DocPosition, to: DocPosition) -> Result<String, EditError> {
        let first = self
            .index_of(from.block)
            .ok_or(EditError::UnknownBlock(from.block))?;
        let last = self
            .index_of(to.block)
            .ok_or(EditError::UnknownBlock(to.block))?;
        let ((first, from), (last, to)) = if (first, from.offset) <= (last, to.offset) {
            ((first, from), (last, to))
        } else {
            ((last, to), (first, from))
        };
        check_offset(&self.blocks[first], from.offset)?;
        check_offset(&self.blocks[last], to.offset)?;

        if first == last {
            let text = &self.blocks[first].text;
            return Ok(text[from.offset as usize..to.offset as usize].to_owned());
        }

        let elements: Vec<ElementRef<'_>> = self.blocks[first..=last]
            .iter()
            .enumerate()
            .map(|(offset, block)| {
                let index = first + offset;
                let start = if index == first {
                    from.offset as usize
                } else {
                    0
                };
                let end = if index == last {
                    to.offset as usize
                } else {
                    block.text.len()
                };
                let whole = start == 0 && end == block.text.len();
                ElementRef {
                    kind: block.kind,
                    text: &block.text[start..end],
                    forced: block.forced,
                    dual: block.dual,
                    // A partially covered block is not the block the source
                    // holds, so it cannot be copied out of it verbatim.
                    provenance: whole.then(|| block.provenance.clone()).flatten(),
                }
            })
            .collect();

        Ok(serialise(&Output {
            title_page: &TitlePage::default(),
            elements: &elements,
            source: self.original_source.as_deref(),
            bom: false,
            line_ending: self.line_ending,
        }))
    }

    // ---- history ----

    /// Applies a transaction's inverses and returns the transaction that undoes
    /// *that*, so undo and redo are the same operation in opposite directions.
    fn invert(
        &mut self,
        transaction: Transaction,
        selection: Option<DocSelection>,
    ) -> (Transaction, EditResult) {
        let mut opposite = Transaction {
            inverses: Vec::new(),
            before_revision: transaction.before_revision,
            after_revision: transaction.after_revision,
            before_selection: transaction.before_selection,
            after_selection: transaction.after_selection,
            selection_initialized: true,
        };
        let mut changed = Vec::new();
        let mut removed = Vec::new();
        let mut inserted = Vec::new();

        for inverse in transaction.inverses.into_iter().rev() {
            match inverse {
                Inverse::Splice { at, remove, insert } => {
                    let at = at.min(self.blocks.len());
                    let end = (at + remove).min(self.blocks.len());
                    let displaced: Vec<Block> = self.blocks[at..end].to_vec();

                    let before: Vec<BlockId> = displaced.iter().map(|block| block.id).collect();
                    let after: Vec<BlockId> = insert.iter().map(|block| block.id).collect();
                    for id in &before {
                        if after.contains(id) {
                            changed.push(*id);
                        } else {
                            removed.push(*id);
                        }
                    }
                    for id in &after {
                        if !before.contains(id) {
                            inserted.push(*id);
                        }
                    }
                    opposite.inverses.push(Inverse::Splice {
                        at,
                        remove: insert.len(),
                        insert: displaced,
                    });
                    self.blocks.splice(at..end, insert);
                }
                Inverse::TitlePage(page) => {
                    opposite
                        .inverses
                        .push(Inverse::TitlePage(Box::new(self.title_page.clone())));
                    self.title_page = *page;
                }
            }
        }

        for ids in [&mut changed, &mut removed, &mut inserted] {
            ids.sort_unstable();
            ids.dedup();
        }
        (
            opposite,
            EditResult {
                changed,
                removed,
                inserted,
                selection,
            },
        )
    }

    // ---- helpers ----

    fn inferred_selection(&self, command: &EditCommand) -> Option<DocSelection> {
        match command {
            EditCommand::ReplaceText { block, range, .. } => Some(DocSelection {
                anchor: DocPosition::new(*block, range.start),
                focus: DocPosition::new(*block, range.end),
            }),
            EditCommand::SplitBlock { block, at } => {
                Some(DocSelection::caret(DocPosition::new(*block, *at)))
            }
            EditCommand::MergeBlocks { first } => self.block(*first).map(|block| {
                DocSelection::caret(DocPosition::new(*first, block.text.len() as u32))
            }),
            EditCommand::SetKind { block, .. } | EditCommand::SetDual { block, .. } => {
                self.block(*block).map(|candidate| {
                    DocSelection::caret(DocPosition::new(*block, candidate.text.len() as u32))
                })
            }
            EditCommand::InsertBlocks { after, .. } => after
                .and_then(|id| self.block(id))
                .map(|block| {
                    DocSelection::caret(DocPosition::new(block.id, block.text.len() as u32))
                })
                .or_else(|| self.caret_at_start()),
            EditCommand::DeleteRange { from, to } => Some(DocSelection {
                anchor: *from,
                focus: *to,
            }),
            EditCommand::SetTitlePage { .. } => self.caret_at_start(),
        }
    }

    fn check_selection(&self, selection: DocSelection) -> Result<(), EditError> {
        for position in [selection.anchor, selection.focus] {
            let block = self
                .block(position.block)
                .ok_or(EditError::UnknownBlock(position.block))?;
            check_offset(block, position.offset)?;
        }
        Ok(())
    }

    /// Whether the block before `index` has to be re-serialised because the
    /// blank line it carries — or does not carry — no longer matches the kind
    /// that will follow it.
    ///
    /// Asking precisely rather than always invalidating matters: dropping a
    /// neighbour's provenance would canonicalise a block the user never
    /// touched, which is exactly what §3.2 exists to avoid.
    fn predecessor_needs_rewriting(
        &self,
        index: usize,
        old_next: Option<BlockKind>,
        new_next: Option<BlockKind>,
    ) -> bool {
        let Some(previous) = index.checked_sub(1).map(|i| self.blocks[i].kind) else {
            return false;
        };
        let Some(new_next) = new_next else {
            return false;
        };
        let required = needs_blank_between(previous, new_next);
        match old_next {
            Some(old) => needs_blank_between(previous, old) != required,
            // At the end of the document the block's trailing bytes are
            // whatever the file had after it, which the serialiser can only
            // safely treat as a blank separator.
            None => !required,
        }
    }

    fn fresh_id(&mut self) -> BlockId {
        self.next_id += 1;
        BlockId(self.next_id)
    }

    fn record(&mut self, inverse: Inverse, coalesce: Option<CoalesceKey>) {
        let before_revision = self.revision;
        self.next_revision += 1;
        let after_revision = self.next_revision;
        self.history
            .record(inverse, coalesce, before_revision, after_revision);
        self.revision = after_revision;
    }

    /// Records into the transaction the last edit is in, rather than one of its
    /// own. See [`crate::history::History::record_alongside`].
    fn record_alongside(&mut self, inverse: Inverse) {
        let before_revision = self.revision;
        self.next_revision += 1;
        let after_revision = self.next_revision;
        self.history
            .record_alongside(inverse, before_revision, after_revision);
        self.revision = after_revision;
    }

    fn caret_in(&self, index: usize) -> Option<DocSelection> {
        self.blocks
            .get(index)
            .map(|block| DocSelection::caret(DocPosition::new(block.id, block.text.len() as u32)))
    }

    fn caret_at_start(&self) -> Option<DocSelection> {
        self.blocks
            .first()
            .map(|block| DocSelection::caret(DocPosition::new(block.id, 0)))
    }
}

fn serialise_parts(
    title_page: &TitlePage,
    blocks: &[Block],
    source: Option<&str>,
    bom: bool,
    line_ending: LineEnding,
) -> String {
    let elements: Vec<ElementRef<'_>> = blocks
        .iter()
        .map(|block| ElementRef {
            kind: block.kind,
            text: &block.text,
            forced: block.forced,
            dual: block.dual,
            provenance: block.provenance.clone(),
        })
        .collect();

    serialise(&Output {
        title_page,
        elements: &elements,
        source,
        bom,
        line_ending,
    })
}

/// Reads Fountain source as blocks that have not been inserted anywhere yet —
/// what a paste needs (§Phase 2, "Copy, cut, paste (as Fountain-aware blocks)").
///
/// `Opaque` is not a state a *new* block may be in: §3.2 defines it as content
/// that always has provenance, and a pasted block has none. Such a block becomes
/// Action carrying the same text, which the serialiser then protects with `!`.
/// The bytes survive; only the invisibility of a pasted boneyard comment does
/// not.
pub fn parse_blocks(source: &str) -> Vec<NewBlock> {
    parse(source)
        .elements
        .into_iter()
        .map(|element| NewBlock {
            kind: match element.kind {
                BlockKind::Opaque => BlockKind::Action,
                kind => kind,
            },
            text: element.text,
            forced: element.forced,
            dual: element.dual,
        })
        .collect()
}

/// A transaction in progress (see [`Document::apply_group`]).
///
/// Commands go through here rather than through [`Document::apply`] so that the
/// whole run lands in one undo step, and so that a failure rolls back the run
/// rather than the one command that failed.
pub struct Grouped<'a> {
    document: &'a mut Document,
    merged: Merged,
}

impl Grouped<'_> {
    /// Applies one command and returns what it did — including the ids of any
    /// blocks it created, which the rest of the plan may then name.
    pub fn apply(&mut self, command: EditCommand) -> Result<EditResult, EditError> {
        let result = self.document.apply_command(command)?;
        self.merged.absorb(result.clone());
        Ok(result)
    }

    /// The document as it stands part-way through the transaction.
    pub fn document(&self) -> &Document {
        self.document
    }
}

/// The patch a run of commands adds up to, with ids that were created and then
/// destroyed inside the run cancelling out.
#[derive(Debug, Default)]
struct Merged {
    changed: Vec<BlockId>,
    removed: Vec<BlockId>,
    inserted: Vec<BlockId>,
    selection: Option<DocSelection>,
}

impl Merged {
    fn absorb(&mut self, result: EditResult) {
        for id in result.removed {
            if let Some(at) = self.inserted.iter().position(|&other| other == id) {
                // Created and destroyed within the group: the caller never saw
                // it, so it is not part of the patch at all.
                self.inserted.remove(at);
                continue;
            }
            self.changed.retain(|&other| other != id);
            push_unique(&mut self.removed, id);
        }
        for id in result.changed {
            if self.inserted.contains(&id) {
                continue;
            }
            push_unique(&mut self.changed, id);
        }
        for id in result.inserted {
            self.removed.retain(|&other| other != id);
            push_unique(&mut self.inserted, id);
        }
        if result.selection.is_some() {
            self.selection = result.selection;
        }
    }

    fn into_result(self) -> EditResult {
        EditResult {
            changed: self.changed,
            removed: self.removed,
            inserted: self.inserted,
            selection: self.selection,
        }
    }
}

fn push_unique(ids: &mut Vec<BlockId>, id: BlockId) {
    if !ids.contains(&id) {
        ids.push(id);
    }
}

/// Opaque blocks are verbatim by definition (§3.2) and refuse every edit.
fn check_editable(block: &Block) -> Result<(), EditError> {
    if block.kind == BlockKind::Opaque {
        Err(EditError::NotEditable(block.id))
    } else {
        Ok(())
    }
}

fn check_offset(block: &Block, offset: u32) -> Result<(), EditError> {
    let offset_usize = offset as usize;
    if offset_usize <= block.text.len() && block.text.is_char_boundary(offset_usize) {
        Ok(())
    } else {
        Err(EditError::BadOffset {
            block: block.id,
            offset,
        })
    }
}

fn validate_block_state(
    block: Option<BlockId>,
    kind: BlockKind,
    text: &str,
    dual: bool,
) -> Result<(), EditError> {
    let reason = if kind == BlockKind::Opaque {
        Some(InvalidBlockReason::Opaque)
    } else if kind == BlockKind::PageBreak && !text.is_empty() {
        Some(InvalidBlockReason::PageBreakHasText)
    } else if dual && kind != BlockKind::Character {
        Some(InvalidBlockReason::DualNonCharacter)
    } else if matches!(kind, BlockKind::Section { level } if !(1..=6).contains(&level)) {
        Some(InvalidBlockReason::InvalidSectionLevel)
    } else if kind == BlockKind::Character && !dual && text.ends_with('^') {
        Some(InvalidBlockReason::CharacterEndsWithDualMarker)
    } else if !kind.is_multiline() && (text.contains('\n') || text.contains('\r')) {
        Some(InvalidBlockReason::MultilineSingleLineKind)
    } else if text.split('\n').any(|line| line.ends_with('\r')) {
        Some(InvalidBlockReason::CarriageReturn)
    } else {
        None
    };

    match reason {
        Some(reason) => Err(EditError::InvalidBlock { block, reason }),
        None => Ok(()),
    }
}

impl Document {
    /// Drops the undo history. Only a reload from disk may call this: §10
    /// forbids silently discarding edits, and an unreachable history is a
    /// discarded edit.
    pub fn clear_history(&mut self) {
        self.history.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::edit::NewBlock;
    use slugline_fountain::TitleField;

    const SCRIPT: &str = "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\n(quietly)\nHello.\n";

    fn doc() -> Document {
        Document::parse(SCRIPT)
    }

    #[test]
    fn parsing_assigns_ids_and_keeps_the_bytes() {
        let doc = doc();
        // Scene heading, action, cue, parenthetical, dialogue.
        assert_eq!(doc.blocks.len(), 5);
        assert_eq!(doc.blocks[0].kind, BlockKind::SceneHeading);
        assert_eq!(doc.blocks[3].kind, BlockKind::Parenthetical);
        assert_eq!(doc.serialise(), SCRIPT);
        assert!(!doc.is_dirty());
        let ids: Vec<u64> = doc.blocks.iter().map(|block| block.id.0).collect();
        assert_eq!(ids, [1, 2, 3, 4, 5]);
    }

    #[test]
    fn a_serialisation_snapshot_keeps_the_revision_it_captured() {
        let mut document = doc();
        let snapshot = document.serialisation_snapshot();
        let id = document.blocks[1].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..4,
                with: "Mary".into(),
            })
            .unwrap();

        assert_eq!(snapshot.serialise(), SCRIPT);
        assert_ne!(snapshot.serialise(), document.serialise());
    }

    #[test]
    fn replacing_text_drops_only_that_block_from_the_verbatim_path() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        doc.apply(EditCommand::ReplaceText {
            block: id,
            range: 0..4,
            with: "Mary".into(),
        })
        .unwrap();

        assert!(doc.blocks[1].provenance.is_none());
        assert!(doc.blocks[0].provenance.is_some());
        assert!(doc.blocks[3].provenance.is_some());
        assert!(doc.is_dirty());
        assert_eq!(
            doc.serialise(),
            "INT. HOUSE - DAY\n\nMary enters.\n\nJOHN\n(quietly)\nHello.\n"
        );
    }

    #[test]
    fn an_edit_that_cannot_apply_changes_nothing() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        let before = doc.serialise();

        assert_eq!(
            doc.apply(EditCommand::ReplaceText {
                block: BlockId(999),
                range: 0..0,
                with: "x".into(),
            }),
            Err(EditError::UnknownBlock(BlockId(999)))
        );
        assert_eq!(
            doc.apply(EditCommand::ReplaceText {
                block: id,
                range: 0..9_000,
                with: "x".into(),
            }),
            Err(EditError::BadOffset {
                block: id,
                offset: 9_000
            })
        );
        assert!(matches!(
            doc.apply(EditCommand::MergeBlocks {
                first: doc.blocks[4].id
            }),
            Err(EditError::NoBlockAfter(_))
        ));

        assert_eq!(doc.serialise(), before);
        assert!(!doc.is_dirty());
        assert!(!doc.can_undo());
    }

    #[test]
    fn an_offset_inside_a_character_is_refused() {
        let mut doc = Document::parse("café\n");
        let id = doc.blocks[0].id;
        // 'é' is two bytes: offset 4 is inside it.
        assert!(doc
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 4..4,
                with: "x".into(),
            })
            .is_err());
        assert_eq!(doc.serialise(), "café\n");
    }

    #[test]
    fn splitting_and_merging_are_inverses() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        let result = doc
            .apply(EditCommand::SplitBlock { block: id, at: 5 })
            .unwrap();

        assert_eq!(doc.blocks.len(), 6);
        assert_eq!(doc.blocks[1].text, "John ");
        assert_eq!(doc.blocks[2].text, "enters.");
        assert_eq!(result.inserted.len(), 1);
        assert_eq!(
            doc.serialise(),
            "INT. HOUSE - DAY\n\nJohn \n\nenters.\n\nJOHN\n(quietly)\nHello.\n"
        );

        doc.apply(EditCommand::MergeBlocks { first: id }).unwrap();
        assert_eq!(doc.blocks.len(), 5);
        assert_eq!(doc.blocks[1].text, "John enters.");
    }

    #[test]
    fn deleting_across_blocks_keeps_the_ends() {
        let mut doc = doc();
        let from = DocPosition::new(doc.blocks[1].id, 4);
        let to = DocPosition::new(doc.blocks[4].id, 2);
        let result = doc.apply(EditCommand::DeleteRange { from, to }).unwrap();

        assert_eq!(doc.blocks.len(), 2);
        assert_eq!(doc.blocks[1].text, "Johnllo.");
        assert_eq!(result.removed.len(), 3);
    }

    #[test]
    fn deleting_a_range_backwards_normalises_it() {
        let mut doc = doc();
        let from = DocPosition::new(doc.blocks[1].id, 4);
        let to = DocPosition::new(doc.blocks[4].id, 2);
        doc.apply(EditCommand::DeleteRange { from: to, to: from })
            .unwrap();
        assert_eq!(doc.blocks[1].text, "Johnllo.");
    }

    #[test]
    fn inserting_blocks_assigns_fresh_ids() {
        let mut doc = doc();
        let after = doc.blocks[0].id;
        let result = doc
            .apply(EditCommand::InsertBlocks {
                after: Some(after),
                blocks: vec![NewBlock::new(BlockKind::Action, "A new line.")],
            })
            .unwrap();

        assert_eq!(doc.blocks.len(), 6);
        assert_eq!(doc.blocks[1].text, "A new line.");
        assert_eq!(result.inserted.len(), 1);
        assert!(!result.inserted.contains(&after));
        assert_eq!(
            doc.serialise(),
            "INT. HOUSE - DAY\n\nA new line.\n\nJohn enters.\n\nJOHN\n(quietly)\nHello.\n"
        );
    }

    #[test]
    fn inserting_at_the_front_needs_no_predecessor() {
        let mut doc = doc();
        doc.apply(EditCommand::InsertBlocks {
            after: None,
            blocks: vec![NewBlock::new(BlockKind::Section { level: 1 }, "Act One")],
        })
        .unwrap();
        assert_eq!(doc.serialise(), format!("# Act One\n\n{SCRIPT}"));
    }

    #[test]
    fn a_parenthetical_inserted_after_dialogue_stays_adjacent() {
        // The dialogue block's own bytes end with a blank line, so the block
        // before an inserted parenthetical has to be rewritten or the
        // parenthetical comes back as action.
        let mut doc = Document::parse("JOHN\nHello.\n\nAction.\n");
        let after = doc.blocks[1].id;
        doc.apply(EditCommand::InsertBlocks {
            after: Some(after),
            blocks: vec![NewBlock::new(BlockKind::Parenthetical, "(beat)")],
        })
        .unwrap();

        let written = doc.serialise();
        assert_eq!(written, "JOHN\nHello.\n(beat)\n\nAction.\n");
        assert_eq!(
            Document::parse(&written).blocks[2].kind,
            BlockKind::Parenthetical
        );
    }

    #[test]
    fn changing_kind_never_alters_text() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        let text = doc.blocks[1].text.clone();
        doc.apply(EditCommand::SetKind {
            block: id,
            kind: BlockKind::Transition,
            forced: true,
        })
        .unwrap();

        assert_eq!(doc.blocks[1].text, text);
        assert!(doc.blocks[1].forced);
        assert_eq!(doc.blocks[1].kind, BlockKind::Transition);
        // And it survives a round trip, forced marker and all.
        let reparsed = Document::parse(&doc.serialise());
        assert_eq!(reparsed.blocks[1].kind, BlockKind::Transition);
        assert_eq!(reparsed.blocks[1].text, text);
    }

    #[test]
    fn undo_restores_text_ids_and_provenance() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        doc.apply(EditCommand::ReplaceText {
            block: id,
            range: 0..4,
            with: "Mary".into(),
        })
        .unwrap();

        let result = doc.undo().expect("something to undo");
        assert_eq!(result.changed, vec![id]);
        assert_eq!(doc.blocks[1].text, "John enters.");
        assert!(doc.blocks[1].provenance.is_some());
        assert_eq!(doc.serialise(), SCRIPT);

        doc.redo().expect("something to redo");
        assert_eq!(doc.blocks[1].text, "Mary enters.");
        assert!(doc.undo().is_some());
        assert_eq!(doc.serialise(), SCRIPT);
    }

    #[test]
    fn undo_restores_deleted_blocks_with_their_original_ids() {
        let mut doc = doc();
        let ids: Vec<BlockId> = doc.blocks.iter().map(|block| block.id).collect();
        doc.apply(EditCommand::DeleteRange {
            from: DocPosition::new(ids[1], 0),
            to: DocPosition::new(ids[4], 6),
        })
        .unwrap();
        assert_eq!(doc.blocks.len(), 2);

        doc.undo().unwrap();
        let after: Vec<BlockId> = doc.blocks.iter().map(|block| block.id).collect();
        assert_eq!(after, ids);
        assert_eq!(doc.serialise(), SCRIPT);
    }

    #[test]
    fn consecutive_typing_in_one_block_is_one_transaction() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        for offset in 0..5u32 {
            doc.apply(EditCommand::ReplaceText {
                block: id,
                range: offset..offset,
                with: "x".into(),
            })
            .unwrap();
        }
        assert_eq!(doc.blocks[1].text, "xxxxxJohn enters.");

        doc.undo().unwrap();
        assert_eq!(doc.blocks[1].text, "John enters.");
        assert!(!doc.can_undo());
    }

    #[test]
    fn typing_in_another_block_starts_a_new_transaction() {
        let mut doc = doc();
        let first = doc.blocks[1].id;
        let second = doc.blocks[4].id;
        doc.apply(EditCommand::ReplaceText {
            block: first,
            range: 0..0,
            with: "x".into(),
        })
        .unwrap();
        doc.apply(EditCommand::ReplaceText {
            block: second,
            range: 0..0,
            with: "y".into(),
        })
        .unwrap();

        doc.undo().unwrap();
        assert_eq!(doc.blocks[4].text, "Hello.");
        assert_eq!(doc.blocks[1].text, "xJohn enters.");
        doc.undo().unwrap();
        assert_eq!(doc.blocks[1].text, "John enters.");
    }

    #[test]
    fn a_structural_command_is_its_own_transaction() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        doc.apply(EditCommand::ReplaceText {
            block: id,
            range: 0..0,
            with: "x".into(),
        })
        .unwrap();
        doc.apply(EditCommand::SplitBlock { block: id, at: 1 })
            .unwrap();

        doc.undo().unwrap();
        assert_eq!(doc.blocks.len(), 5);
        assert_eq!(doc.blocks[1].text, "xJohn enters.");
        doc.undo().unwrap();
        assert_eq!(doc.blocks[1].text, "John enters.");
    }

    #[test]
    fn commit_ends_a_run_of_typing() {
        let mut doc = doc();
        let id = doc.blocks[1].id;
        doc.apply(EditCommand::ReplaceText {
            block: id,
            range: 0..0,
            with: "x".into(),
        })
        .unwrap();
        doc.commit();
        doc.apply(EditCommand::ReplaceText {
            block: id,
            range: 0..0,
            with: "y".into(),
        })
        .unwrap();

        doc.undo().unwrap();
        assert_eq!(doc.blocks[1].text, "xJohn enters.");
        doc.undo().unwrap();
        assert_eq!(doc.blocks[1].text, "John enters.");
    }

    #[test]
    fn the_title_page_is_edited_and_undone_like_anything_else() {
        let mut doc = Document::parse("Title: Big Fish\n\nAction.\n");
        doc.apply(EditCommand::SetTitlePage {
            field: TitleField::Credit,
            value: "Written by".into(),
        })
        .unwrap();
        assert_eq!(
            doc.serialise(),
            "Title: Big Fish\nCredit: Written by\n\nAction.\n"
        );

        doc.undo().unwrap();
        assert_eq!(doc.serialise(), "Title: Big Fish\n\nAction.\n");
    }

    #[test]
    fn an_empty_document_serialises_to_nothing() {
        let doc = Document::empty();
        assert!(doc.is_empty());
        assert_eq!(doc.serialise(), "");
    }

    #[test]
    fn dual_dialogue_is_set_and_undone() {
        let mut doc = Document::parse("JOHN\nHi.\n\nMARY\nHi back.\n");
        let id = doc.blocks[2].id;
        doc.apply(EditCommand::SetDual {
            block: id,
            dual: true,
        })
        .unwrap();
        assert_eq!(doc.serialise(), "JOHN\nHi.\n\nMARY ^\nHi back.\n");
        doc.undo().unwrap();
        assert_eq!(doc.serialise(), "JOHN\nHi.\n\nMARY\nHi back.\n");
    }

    #[test]
    fn every_invalid_new_block_state_is_rejected_atomically() {
        let cases = [
            (
                BlockKind::Opaque,
                "verbatim",
                false,
                InvalidBlockReason::Opaque,
            ),
            (
                BlockKind::PageBreak,
                "not empty",
                false,
                InvalidBlockReason::PageBreakHasText,
            ),
            (
                BlockKind::Action,
                "text",
                true,
                InvalidBlockReason::DualNonCharacter,
            ),
            (
                BlockKind::Section { level: 0 },
                "Act",
                false,
                InvalidBlockReason::InvalidSectionLevel,
            ),
            (
                BlockKind::Section { level: 7 },
                "Act",
                false,
                InvalidBlockReason::InvalidSectionLevel,
            ),
            (
                BlockKind::Character,
                "MARY^",
                false,
                InvalidBlockReason::CharacterEndsWithDualMarker,
            ),
            (
                BlockKind::SceneHeading,
                "INT. HOUSE\nDAY",
                false,
                InvalidBlockReason::MultilineSingleLineKind,
            ),
            (
                BlockKind::Action,
                "carriage\r\nreturn",
                false,
                InvalidBlockReason::CarriageReturn,
            ),
        ];

        for (kind, text, dual, reason) in cases {
            let mut document = doc();
            let before = document.serialise();
            let mut block = NewBlock::new(kind, text);
            block.dual = dual;

            assert_eq!(
                document.apply(EditCommand::InsertBlocks {
                    after: None,
                    blocks: vec![block],
                }),
                Err(EditError::InvalidBlock {
                    block: None,
                    reason,
                })
            );
            assert_eq!(document.serialise(), before);
            assert!(!document.is_dirty());
            assert!(!document.can_undo());
        }
    }

    #[test]
    fn invalid_resulting_states_are_rejected_before_history() {
        let mut replace = Document::parse("INT. HOUSE - DAY\n");
        let id = replace.blocks[0].id;
        assert_invalid_atomically(
            &mut replace,
            EditCommand::ReplaceText {
                block: id,
                range: 3..3,
                with: "\n".into(),
            },
            InvalidBlockReason::MultilineSingleLineKind,
        );

        let mut set_kind = Document::parse("Action.\n");
        let id = set_kind.blocks[0].id;
        assert_invalid_atomically(
            &mut set_kind,
            EditCommand::SetKind {
                block: id,
                kind: BlockKind::PageBreak,
                forced: false,
            },
            InvalidBlockReason::PageBreakHasText,
        );

        let mut set_dual = Document::parse("Action.\n");
        let id = set_dual.blocks[0].id;
        assert_invalid_atomically(
            &mut set_dual,
            EditCommand::SetDual {
                block: id,
                dual: true,
            },
            InvalidBlockReason::DualNonCharacter,
        );

        let mut merge = Document::parse("@MARY\n\n!^\n");
        let id = merge.blocks[0].id;
        assert_invalid_atomically(
            &mut merge,
            EditCommand::MergeBlocks { first: id },
            InvalidBlockReason::CharacterEndsWithDualMarker,
        );

        let mut delete = Document::parse("@MARY X\n\n!^\n");
        let first = delete.blocks[0].id;
        let second = delete.blocks[1].id;
        assert_invalid_atomically(
            &mut delete,
            EditCommand::DeleteRange {
                from: DocPosition::new(first, 4),
                to: DocPosition::new(second, 0),
            },
            InvalidBlockReason::CharacterEndsWithDualMarker,
        );

        let mut split = Document::parse("@MARY^^\n");
        assert_eq!(split.blocks[0].text, "MARY^");
        assert!(split.blocks[0].dual);
        let id = split.blocks[0].id;
        assert_invalid_atomically(
            &mut split,
            EditCommand::SplitBlock { block: id, at: 0 },
            InvalidBlockReason::CharacterEndsWithDualMarker,
        );
    }

    fn assert_invalid_atomically(
        document: &mut Document,
        command: EditCommand,
        reason: InvalidBlockReason,
    ) {
        let before = document.serialise();
        assert!(matches!(
            document.apply(command),
            Err(EditError::InvalidBlock {
                reason: actual,
                ..
            }) if actual == reason
        ));
        assert_eq!(document.serialise(), before);
        assert!(!document.is_dirty());
        assert!(!document.can_undo());
    }

    #[test]
    fn no_op_commands_preserve_provenance_history_and_dirty_state() {
        let mut document = Document::parse("Title: Big Fish\n\nAction.\n");
        let id = document.blocks[0].id;
        let block_provenance = document.blocks[0].provenance.clone();
        let title_provenance = document.title_page.provenance.clone();

        let results = [
            document
                .apply(EditCommand::ReplaceText {
                    block: id,
                    range: 0..7,
                    with: "Action.".into(),
                })
                .unwrap(),
            document
                .apply(EditCommand::DeleteRange {
                    from: DocPosition::new(id, 3),
                    to: DocPosition::new(id, 3),
                })
                .unwrap(),
            document
                .apply(EditCommand::SetKind {
                    block: id,
                    kind: BlockKind::Action,
                    forced: false,
                })
                .unwrap(),
            document
                .apply(EditCommand::SetDual {
                    block: id,
                    dual: false,
                })
                .unwrap(),
            document
                .apply(EditCommand::SetTitlePage {
                    field: TitleField::Title,
                    value: "Big Fish".into(),
                })
                .unwrap(),
        ];

        assert!(results.iter().all(|result| result.changed.is_empty()));
        assert_eq!(document.blocks[0].provenance, block_provenance);
        assert_eq!(document.title_page.provenance, title_provenance);
        assert!(!document.is_dirty());
        assert!(!document.can_undo());
    }

    #[test]
    fn insertion_and_deletion_do_not_coalesce_together() {
        let mut document = Document::parse("abc\n");
        let id = document.blocks[0].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..0,
                with: "x".into(),
            })
            .unwrap();
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..1,
                with: String::new(),
            })
            .unwrap();

        assert_eq!(document.blocks[0].text, "abc");
        assert!(document.is_dirty());
        document.undo().unwrap();
        assert_eq!(document.blocks[0].text, "xabc");
        document.undo().unwrap();
        assert_eq!(document.blocks[0].text, "abc");
        assert!(!document.is_dirty());
    }

    #[test]
    fn replacements_never_coalesce() {
        let mut document = Document::parse("abc\n");
        let id = document.blocks[0].id;
        for with in ["x", "y"] {
            document
                .apply(EditCommand::ReplaceText {
                    block: id,
                    range: 0..1,
                    with: with.into(),
                })
                .unwrap();
        }

        document.undo().unwrap();
        assert_eq!(document.blocks[0].text, "xbc");
        document.undo().unwrap();
        assert_eq!(document.blocks[0].text, "abc");
    }

    #[test]
    fn undoing_to_the_initial_revision_clears_dirty() {
        let mut document = Document::parse("abc\n");
        let id = document.blocks[0].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..0,
                with: "x".into(),
            })
            .unwrap();
        assert!(document.is_dirty());

        document.undo().unwrap();
        assert!(!document.is_dirty());
    }

    #[test]
    fn undo_and_redo_track_a_saved_revision() {
        let mut document = Document::parse("abc\n");
        let id = document.blocks[0].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..0,
                with: "x".into(),
            })
            .unwrap();
        document.mark_saved();
        assert!(!document.is_dirty());

        document.undo().unwrap();
        assert!(document.is_dirty());
        document.redo().unwrap();
        assert!(!document.is_dirty());

        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 1..1,
                with: "y".into(),
            })
            .unwrap();
        assert!(document.is_dirty());
        document.undo().unwrap();
        assert!(!document.is_dirty());
    }

    #[test]
    fn a_nested_note_remains_editable() {
        let mut document = Document::parse("[[ outer [[ inner ]] outer ]]\n");
        let id = document.blocks[0].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 1..6,
                with: "changed".into(),
            })
            .unwrap();

        let written = document.serialise();
        assert_eq!(written, "[[ changed [[ inner ]] outer ]]\n");
        assert_eq!(Document::parse(&written).blocks[0].kind, BlockKind::Note);
    }

    #[test]
    fn undo_and_redo_restore_exact_selections() {
        let mut document = Document::parse("abcdef\n");
        let id = document.blocks[0].id;
        let before = DocSelection {
            anchor: DocPosition::new(id, 4),
            focus: DocPosition::new(id, 1),
        };
        let applied = document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: id,
                    range: 1..4,
                    with: "X".into(),
                },
                Some(before),
            )
            .unwrap();

        assert_eq!(document.undo().unwrap().selection, Some(before));
        assert_eq!(document.redo().unwrap().selection, applied.selection);
    }

    #[test]
    fn a_blockless_document_has_no_fake_selection() {
        let mut document = Document::empty();
        let applied = document
            .apply(EditCommand::SetTitlePage {
                field: TitleField::Title,
                value: "Big Fish".into(),
            })
            .unwrap();
        assert_eq!(applied.selection, None);
        assert_eq!(document.undo().unwrap().selection, None);
        assert_eq!(document.redo().unwrap().selection, None);
    }

    #[test]
    fn an_emptied_vanishing_block_is_semantically_empty() {
        let mut document = Document::parse("x\n");
        let id = document.blocks[0].id;
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..1,
                with: String::new(),
            })
            .unwrap();
        assert!(document.is_empty());
        assert_eq!(document.serialise(), "");

        let page_break = Document::parse("===\n");
        assert!(!page_break.is_empty());
    }

    #[test]
    fn tolerant_note_edits_accept_temporarily_unbalanced_delimiters() {
        let mut document = Document::parse("[[note]]\n");
        let id = document.blocks[0].id;
        for bracket in ["[", "["] {
            let offset = document.block(id).unwrap().text.len() as u32;
            document
                .apply(EditCommand::ReplaceText {
                    block: id,
                    range: offset..offset,
                    with: bracket.into(),
                })
                .unwrap();
        }
        assert_eq!(document.block(id).unwrap().text, "note[[");
        let reopened = Document::parse(&document.serialise());
        assert_eq!(reopened.blocks[0].kind, BlockKind::Action);
        assert_eq!(reopened.blocks[0].text, "note[[");
    }

    #[test]
    fn a_group_of_commands_is_one_undo_step() {
        let mut document = doc();
        let action = document.blocks[1].id;
        document
            .apply_all(
                vec![
                    EditCommand::SplitBlock {
                        block: action,
                        at: 5,
                    },
                    EditCommand::InsertBlocks {
                        after: Some(action),
                        blocks: vec![NewBlock::new(BlockKind::Action, "Inserted.")],
                    },
                ],
                None,
            )
            .unwrap();
        assert_eq!(document.blocks.len(), 7);

        document.undo().unwrap();
        assert_eq!(document.blocks.len(), 5);
        assert_eq!(document.serialise(), SCRIPT);
        assert!(!document.can_undo());

        document.redo().unwrap();
        assert_eq!(document.blocks.len(), 7);
    }

    #[test]
    fn a_new_script_has_one_empty_block_and_nothing_to_undo() {
        let document = Document::blank();
        assert_eq!(document.blocks.len(), 1);
        assert_eq!(document.blocks[0].kind, BlockKind::Action);
        assert!(document.blocks[0].text.is_empty());
        assert!(!document.can_undo());
        assert!(!document.is_dirty());
        assert!(document.is_empty());
        assert_eq!(document.serialise(), "");
    }

    #[test]
    fn a_plan_can_name_a_block_an_earlier_command_created() {
        let mut document = doc();
        let action = document.blocks[1].id;
        let result = document
            .apply_group(None, |group| {
                let split = group.apply(EditCommand::SplitBlock {
                    block: action,
                    at: 5,
                })?;
                let tail = split.inserted[0];
                group.apply(EditCommand::ReplaceText {
                    block: tail,
                    range: 0..0,
                    with: "still ".into(),
                })?;
                Ok(())
            })
            .unwrap();

        assert_eq!(document.blocks[2].text, "still enters.");
        assert_eq!(result.inserted, vec![document.blocks[2].id]);
        assert_eq!(result.changed, vec![action]);

        document.undo().unwrap();
        assert_eq!(document.serialise(), SCRIPT);
    }

    #[test]
    fn a_group_reports_only_the_blocks_that_outlived_it() {
        let mut document = doc();
        let action = document.blocks[1].id;
        let result = document
            .apply_all(
                vec![
                    // Split, then merge the halves straight back together: the
                    // block the split created never existed as far as the caller
                    // is concerned.
                    EditCommand::SplitBlock {
                        block: action,
                        at: 5,
                    },
                    EditCommand::MergeBlocks { first: action },
                ],
                None,
            )
            .unwrap();

        assert_eq!(result.changed, vec![action]);
        assert!(result.inserted.is_empty());
        assert!(result.removed.is_empty());
    }

    #[test]
    fn a_group_that_fails_part_way_changes_nothing() {
        let mut document = doc();
        let action = document.blocks[1].id;
        let before = document.serialise();

        assert_eq!(
            document.apply_all(
                vec![
                    EditCommand::ReplaceText {
                        block: action,
                        range: 0..0,
                        with: "x".into(),
                    },
                    EditCommand::ReplaceText {
                        block: BlockId(9_999),
                        range: 0..0,
                        with: "y".into(),
                    },
                ],
                None,
            ),
            Err(EditError::UnknownBlock(BlockId(9_999)))
        );

        assert_eq!(document.serialise(), before);
        assert!(!document.is_dirty());
        assert!(!document.can_undo());
        assert!(!document.can_redo());
    }

    #[test]
    fn a_group_does_not_swallow_the_keystrokes_before_it() {
        let mut document = doc();
        let action = document.blocks[1].id;
        document
            .apply(EditCommand::ReplaceText {
                block: action,
                range: 0..0,
                with: "x".into(),
            })
            .unwrap();
        document
            .apply_all(
                vec![EditCommand::SplitBlock {
                    block: action,
                    at: 1,
                }],
                None,
            )
            .unwrap();

        document.undo().unwrap();
        assert_eq!(document.blocks[1].text, "xJohn enters.");
        document.undo().unwrap();
        assert_eq!(document.blocks[1].text, "John enters.");
    }

    #[test]
    fn extracting_inside_one_block_is_plain_text() {
        let document = doc();
        let id = document.blocks[1].id;
        let text = document
            .extract(DocPosition::new(id, 0), DocPosition::new(id, 4))
            .unwrap();
        assert_eq!(text, "John");
    }

    #[test]
    fn extracting_across_blocks_is_fountain_and_normalises_direction() {
        let document = doc();
        let from = DocPosition::new(document.blocks[0].id, 0);
        let to = DocPosition::new(document.blocks[4].id, 5);
        let forwards = document.extract(from, to).unwrap();
        assert_eq!(
            forwards,
            "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\n(quietly)\nHello\n"
        );
        assert_eq!(document.extract(to, from).unwrap(), forwards);

        // And what comes out is what goes back in.
        let blocks = parse_blocks(&forwards);
        let kinds: Vec<BlockKind> = blocks.iter().map(|block| block.kind).collect();
        assert_eq!(
            kinds,
            [
                BlockKind::SceneHeading,
                BlockKind::Action,
                BlockKind::Character,
                BlockKind::Parenthetical,
                BlockKind::Dialogue,
            ]
        );
    }

    #[test]
    fn a_partly_covered_block_is_not_copied_verbatim() {
        // The action block's own bytes contain "John enters."; taking half of it
        // has to re-serialise rather than slice the source.
        let document = doc();
        let text = document
            .extract(
                DocPosition::new(document.blocks[1].id, 5),
                DocPosition::new(document.blocks[2].id, 4),
            )
            .unwrap();
        assert_eq!(text, "enters.\n\nJOHN\n");
    }

    #[test]
    fn pasted_opaque_content_keeps_its_bytes_as_action() {
        let blocks = parse_blocks("/* hidden */\n");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].kind, BlockKind::Action);
        assert_eq!(blocks[0].text, "/* hidden */");

        // And it inserts, which an Opaque block would not.
        let mut document = doc();
        document
            .apply(EditCommand::InsertBlocks {
                after: None,
                blocks,
            })
            .unwrap();
        assert!(document.serialise().starts_with("!/* hidden */\n"));
    }

    #[test]
    fn coalescing_does_not_overwrite_an_explicit_absent_selection() {
        let mut document = Document::parse("abc\n");
        let id = document.blocks[0].id;
        document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: id,
                    range: 0..0,
                    with: "x".into(),
                },
                None,
            )
            .unwrap();
        document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: id,
                    range: 1..1,
                    with: "y".into(),
                },
                Some(DocSelection::caret(DocPosition::new(id, 1))),
            )
            .unwrap();
        assert_eq!(document.undo().unwrap().selection, None);
    }

    // --- automatic classification (§4.2) ---------------------------------

    /// Types `text` into the block at `index`, one keystroke at a time, with
    /// re-classification after each — what the bridge does for every key.
    fn type_into(document: &mut Document, index: usize, text: &str) {
        let id = document.blocks[index].id;
        for character in text.chars() {
            let offset = document
                .block(id)
                .expect("the block is still there")
                .text
                .len() as u32;
            let before = Some(DocSelection::caret(DocPosition::new(id, offset)));
            let mut result = document
                .apply_with_selection(
                    EditCommand::ReplaceText {
                        block: id,
                        range: offset..offset,
                        with: character.to_string(),
                    },
                    before,
                )
                .expect("the keystroke applies");
            document.reinfer(&mut result, before);
        }
    }

    #[test]
    fn typing_a_slug_line_into_an_action_block_promotes_it() {
        let mut document = Document::blank();
        type_into(&mut document, 0, "INT. HOUSE - DAY");

        assert_eq!(document.blocks[0].kind, BlockKind::SceneHeading);
        assert!(!document.blocks[0].forced, "inference never forces");
        // And the file says so without needing a marker to protect it.
        assert_eq!(document.serialise(), "INT. HOUSE - DAY\n");
    }

    #[test]
    fn a_promotion_is_undone_with_the_typing_that_caused_it() {
        let mut document = Document::parse("Some action.\n\nMore action.\n");
        let id = document.blocks[1].id;
        type_into(&mut document, 1, "");
        // Select all of it and retype, then keep typing a slug line.
        let mut result = document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..12,
                with: String::new(),
            })
            .unwrap();
        document.reinfer(&mut result, None);
        type_into(&mut document, 1, "INT. HOUSE");
        assert_eq!(document.blocks[1].kind, BlockKind::SceneHeading);

        // One undo takes back the run of typing *and* the kind it produced.
        document.undo().expect("something to undo");
        assert_eq!(document.blocks[1].text, "");
        assert_eq!(document.blocks[1].kind, BlockKind::Action);
        document.undo().expect("the deletion");
        assert_eq!(document.blocks[1].text, "More action.");
        assert_eq!(document.blocks[1].kind, BlockKind::Action);
        assert_eq!(document.serialise(), "Some action.\n\nMore action.\n");
    }

    #[test]
    fn typing_after_a_promotion_still_coalesces() {
        let mut document = Document::blank();
        type_into(&mut document, 0, "INT. HOUSE - DAY");
        // The promotion fired at "INT."; everything after it has to have stayed
        // in the same transaction, or undo would step one character at a time.
        document.undo().expect("something to undo");
        assert_eq!(document.blocks[0].text, "");
        assert!(!document.can_undo(), "one keystroke run, one undo step");
    }

    #[test]
    fn a_forced_block_is_never_reclassified() {
        let mut document = Document::parse("!INT. NOT A HEADING\n");
        assert!(document.blocks[0].forced);
        type_into(&mut document, 0, ".");
        assert_eq!(document.blocks[0].kind, BlockKind::Action);
        assert_eq!(document.blocks[0].text, "INT. NOT A HEADING.");
        assert_eq!(document.serialise(), "!INT. NOT A HEADING.\n");
    }

    #[test]
    fn setting_a_kind_explicitly_survives_the_next_keystroke() {
        // §Phase 3: an element-type shortcut straight after an automatic change
        // reverts it and pins the writer's choice.
        let mut document = Document::blank();
        type_into(&mut document, 0, "INT. HOUSE");
        assert_eq!(document.blocks[0].kind, BlockKind::SceneHeading);

        let id = document.blocks[0].id;
        document
            .apply(EditCommand::SetKind {
                block: id,
                kind: BlockKind::Action,
                forced: true,
            })
            .unwrap();
        type_into(&mut document, 0, " - DAY");

        assert_eq!(document.blocks[0].kind, BlockKind::Action);
        assert_eq!(document.blocks[0].text, "INT. HOUSE - DAY");
        assert_eq!(document.serialise(), "!INT. HOUSE - DAY\n");
    }

    #[test]
    fn unmaking_a_cue_reclassifies_the_speech_under_it() {
        // The cascade §4.2's window exists for: block N stops being a cue, and
        // block N+1 is no longer in a speech. Both settle in one pass, in order.
        let mut document = Document::parse("JOHN\nHello.\n");
        assert_eq!(document.blocks[0].kind, BlockKind::Character);
        assert_eq!(document.blocks[1].kind, BlockKind::Dialogue);

        // Lower-case letters take a line out of §4.1's cue character set.
        type_into(&mut document, 0, "ny");

        assert_eq!(document.blocks[0].kind, BlockKind::Action);
        assert_eq!(document.blocks[1].kind, BlockKind::Action);
        assert_eq!(document.serialise(), "JOHNny\n\nHello.\n");
        // …and reopening the file agrees.
        let reopened = Document::parse(&document.serialise());
        assert_eq!(reopened.blocks[0].kind, BlockKind::Action);
        assert_eq!(reopened.blocks[1].kind, BlockKind::Action);
    }

    #[test]
    fn an_emptied_cue_is_still_a_cue() {
        // Inference has nothing to read in an empty block, so the kind that put
        // it there stands — which is also what the file says, because an empty
        // cue is written `@` and read back as one.
        let mut document = Document::parse("JOHN\nHello.\n");
        let cue = document.blocks[0].id;
        let before = Some(DocSelection::caret(DocPosition::new(cue, 0)));
        let mut result = document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: cue,
                    range: 0..4,
                    with: String::new(),
                },
                before,
            )
            .unwrap();
        document.reinfer(&mut result, before);

        assert_eq!(document.blocks[0].kind, BlockKind::Character);
        assert_eq!(document.blocks[1].kind, BlockKind::Dialogue);
        assert_eq!(document.serialise(), "@\nHello.\n");
        assert_eq!(
            Document::parse(&document.serialise()).blocks[1].kind,
            BlockKind::Dialogue
        );
    }

    #[test]
    fn a_cue_appears_once_something_speaks_under_it() {
        // Two action paragraphs. Making the first look like a cue is not enough;
        // the second has to be dialogue, which only the writer can say.
        let mut document = Document::parse("JOHN\n\nHello.\n");
        assert_eq!(document.blocks[0].kind, BlockKind::Action);

        let second = document.blocks[1].id;
        let mut result = document
            .apply(EditCommand::SetKind {
                block: second,
                kind: BlockKind::Dialogue,
                forced: true,
            })
            .unwrap();
        document.reinfer(&mut result, None);

        assert_eq!(document.blocks[0].kind, BlockKind::Character);
        assert_eq!(document.serialise(), "JOHN\nHello.\n");
    }

    #[test]
    fn reclassification_never_touches_a_marked_element() {
        for source in [
            "~A lyric line\n",
            "# Act One\n",
            "= A synopsis\n",
            "> Centred <\n",
        ] {
            let mut document = Document::parse(source);
            let kind = document.blocks[0].kind;
            type_into(&mut document, 0, " INT. HOUSE - DAY");
            assert_eq!(
                document.blocks[0].kind, kind,
                "{source:?} carries its marker in its kind"
            );
        }
    }

    #[test]
    fn reclassification_leaves_a_distant_block_alone() {
        let mut document = Document::parse("JOHN\nHello.\n\nAction.\n\nMore action.\n");
        let far = document.blocks[3].id;
        let kinds_before: Vec<BlockKind> = document.blocks.iter().map(|b| b.kind).collect();

        // An edit three blocks away must not reach the dialogue at the top.
        let before = Some(DocSelection::caret(DocPosition::new(far, 0)));
        let mut result = document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: far,
                    range: 0..0,
                    with: "X".into(),
                },
                before,
            )
            .unwrap();
        document.reinfer(&mut result, before);

        let kinds_after: Vec<BlockKind> = document.blocks.iter().map(|b| b.kind).collect();
        assert_eq!(kinds_before, kinds_after);
    }

    #[test]
    fn a_dual_cue_is_left_alone() {
        let mut document = Document::parse("JOHN\nHi.\n\nMARY ^\nHi back.\n");
        assert!(document.blocks[2].dual);
        assert!(!document.blocks[2].forced);
        type_into(&mut document, 2, " ANNE");
        assert_eq!(document.blocks[2].kind, BlockKind::Character);
        assert!(document.blocks[2].dual);
    }

    #[test]
    fn reclassification_agrees_with_reopening_the_file() {
        let mut document = Document::blank();
        type_into(&mut document, 0, "INT. HOUSE - DAY");
        let written = document.serialise();
        let reopened = Document::parse(&written);
        let mine: Vec<BlockKind> = document.blocks.iter().map(|b| b.kind).collect();
        let theirs: Vec<BlockKind> = reopened.blocks.iter().map(|b| b.kind).collect();
        assert_eq!(mine, theirs, "{written:?} reads back differently");
    }

    // --- find and replace ------------------------------------------------

    fn query(text: &str) -> FindQuery {
        FindQuery {
            text: text.to_owned(),
            ..FindQuery::default()
        }
    }

    #[test]
    fn find_reports_every_hit_in_document_order() {
        let document = Document::parse("INT. HOUSE - DAY\n\nJohn enters the house.\n");
        let hits = document.find(&query("house"));
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].block, document.blocks[0].id);
        assert_eq!(hits[0].range, 5..10);
        assert_eq!(hits[1].block, document.blocks[1].id);
    }

    #[test]
    fn find_can_be_restricted_to_element_types() {
        let document = Document::parse("Hello there.\n\nJOHN\nHello.\n");
        let dialogue_only = FindQuery {
            kinds: vec![BlockKind::Dialogue],
            ..query("hello")
        };
        let hits = document.find(&dialogue_only);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].block, document.blocks[2].id);
    }

    #[test]
    fn replace_all_is_one_undo_transaction() {
        let source = "INT. HOUSE - DAY\n\nJohn enters the house.\n";
        let mut document = Document::parse(source);
        let result = document
            .replace_all(&query("house"), "cabin", None)
            .unwrap();

        assert_eq!(result.changed.len(), 2);
        assert_eq!(document.blocks[0].text, "INT. cabin - DAY");
        assert_eq!(document.blocks[1].text, "John enters the cabin.");

        document.undo().expect("one step takes all of it back");
        assert_eq!(document.serialise(), source);
        assert!(!document.can_undo());
    }

    #[test]
    fn replace_all_handles_several_hits_in_one_block() {
        let mut document = Document::parse("aa bb aa bb aa\n");
        document.replace_all(&query("aa"), "X", None).unwrap();
        assert_eq!(document.blocks[0].text, "X bb X bb X");
    }

    #[test]
    fn replacing_with_something_longer_keeps_the_later_hits() {
        let mut document = Document::parse("cat cat cat\n");
        document
            .replace_all(&query("cat"), "elephant", None)
            .unwrap();
        assert_eq!(document.blocks[0].text, "elephant elephant elephant");
    }

    #[test]
    fn replace_all_with_no_hits_changes_nothing() {
        let mut document = Document::parse("Action.\n");
        let result = document
            .replace_all(&query("nothing here"), "x", None)
            .unwrap();
        assert!(result.changed.is_empty());
        assert!(!document.is_dirty());
        assert!(!document.can_undo());
    }

    #[test]
    fn replace_all_skips_a_block_it_cannot_edit() {
        // An Opaque block round-trips verbatim, so it is not searched and not
        // touched — and the replacement in the block beside it still happens.
        let mut document = Document::parse("/* cat */\n\nThe cat sat.\n");
        assert_eq!(document.blocks[0].kind, BlockKind::Opaque);
        let hits = document.find(&query("cat"));
        assert_eq!(hits.len(), 2, "the boneyard text is still findable");

        // Restricted to what can be edited, the replacement applies.
        let editable = FindQuery {
            kinds: vec![BlockKind::Action],
            ..query("cat")
        };
        document.replace_all(&editable, "dog", None).unwrap();
        assert_eq!(document.blocks[1].text, "The dog sat.");
        assert!(document.serialise().starts_with("/* cat */\n"));
    }

    // --- suggestions -----------------------------------------------------

    #[test]
    fn an_existing_cue_is_suggested_for_a_matching_action_line() {
        let document = Document::parse("JOHN\nHello.\n\nJOHN\n");
        let last = document.blocks[2].id;
        assert_eq!(document.blocks[2].kind, BlockKind::Action);
        assert_eq!(document.character_suggestion(last), Some("JOHN"));
    }

    #[test]
    fn nothing_is_suggested_without_a_name_to_match() {
        let document = Document::parse("JOHN\nHello.\n\nMARY\n");
        assert_eq!(document.character_suggestion(document.blocks[2].id), None);
        // Nor for the cue itself, nor for a block in a speech.
        assert_eq!(document.character_suggestion(document.blocks[0].id), None);
        assert_eq!(document.character_suggestion(document.blocks[1].id), None);
        assert_eq!(document.character_suggestion(BlockId(999)), None);
    }

    #[test]
    fn a_suggestion_is_never_taken_on_the_writers_behalf() {
        let mut document = Document::parse("JOHN\nHello.\n\nJOHN\n");
        let last = document.blocks[2].id;
        let before = Some(DocSelection::caret(DocPosition::new(last, 4)));
        let mut result = document
            .apply_with_selection(
                EditCommand::ReplaceText {
                    block: last,
                    range: 4..4,
                    with: String::new(),
                },
                before,
            )
            .unwrap();
        document.reinfer(&mut result, before);
        assert_eq!(document.blocks[2].kind, BlockKind::Action);
    }
}
