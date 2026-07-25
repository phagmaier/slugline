//! The canonical document: blocks with stable identities, edit commands, and
//! the history that inverts them.

use std::ops::Range;
use std::sync::Arc;

use slugline_fountain::{
    needs_blank_between, parse, serialise, BlockKind, ElementRef, LineEnding, Output, TitlePage,
};

use crate::edit::{
    DocPosition, DocSelection, EditCommand, EditError, EditResult, InvalidBlockReason, NewBlock,
};
use crate::history::{CoalesceKey, History, Inverse, TextEditKind, Transaction};
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

impl Document {
    /// An empty document, as a new script starts.
    pub fn empty() -> Document {
        Document::default()
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
        let elements: Vec<ElementRef<'_>> = self
            .blocks
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
            title_page: &self.title_page,
            elements: &elements,
            source: self.original_source.as_deref(),
            bom: self.bom,
            line_ending: self.line_ending,
        })
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

    /// Clears the dirty flag. Re-anchoring provenance to the newly written
    /// bytes belongs to `storage`, in Phase 4; until then a saved document goes
    /// on serialising from the source it was opened with, which is correct but
    /// keeps the old bytes alive.
    pub fn mark_saved(&mut self) {
        self.history.close();
        self.saved_revision = self.revision;
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
}
