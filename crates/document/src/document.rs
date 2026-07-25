//! The canonical document: blocks with stable identities, edit commands, and
//! the history that inverts them.

use std::ops::Range;
use std::sync::Arc;

use slugline_fountain::{
    needs_blank_between, parse, serialise, BlockKind, ElementRef, LineEnding, Output, TitlePage,
};

use crate::edit::{DocPosition, DocSelection, EditCommand, EditError, EditResult, NewBlock};
use crate::history::{History, Inverse, Transaction};
use crate::BlockId;

/// One element of the script, with an identity Flutter can hold on to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    pub id: BlockId,
    pub kind: BlockKind,
    /// User-visible text with emphasis markup retained inline (§3.1).
    pub text: String,
    /// The element type was pinned, by the user or by explicit syntax.
    pub forced: bool,
    /// Dual-dialogue right column marker.
    pub dual: bool,
    /// Byte range in the original source this block came from. `None` once the
    /// block has been edited, which is what sends it down the serialiser's
    /// canonical path instead of the verbatim one (§3.2).
    pub provenance: Option<Range<usize>>,
}

/// A parsed script, its edit history, and the bytes it was opened from.
#[derive(Debug, Clone, Default)]
pub struct Document {
    pub title_page: TitlePage,
    pub blocks: Vec<Block>,
    next_id: u64,
    /// Byte-for-byte original file content, retained for lossless
    /// round-tripping (§3.1).
    original_source: Option<Arc<str>>,
    bom: bool,
    line_ending: LineEnding,
    history: History,
    dirty: bool,
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
            dirty: false,
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
        self.blocks.is_empty() && self.title_page.is_empty()
    }

    pub fn line_ending(&self) -> LineEnding {
        self.line_ending
    }

    /// Whether the document has unsaved edits (§6, `doc_dirty`).
    pub fn is_dirty(&self) -> bool {
        self.dirty
    }

    /// Clears the dirty flag. Re-anchoring provenance to the newly written
    /// bytes belongs to `storage`, in Phase 4; until then a saved document goes
    /// on serialising from the source it was opened with, which is correct but
    /// keeps the old bytes alive.
    pub fn mark_saved(&mut self) {
        self.dirty = false;
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
                self.history
                    .record(Inverse::TitlePage(Box::new(self.title_page.clone())), None);
                self.title_page.set(field, value);
                Ok(EditResult {
                    changed: Vec::new(),
                    removed: Vec::new(),
                    inserted: Vec::new(),
                    selection: self.caret_at_start(),
                })
            }
        }?;
        self.dirty = true;
        Ok(result)
    }

    pub fn undo(&mut self) -> Option<EditResult> {
        let transaction = self.history.take_undo()?;
        let (redo, result) = self.invert(transaction);
        self.history.push_redo(redo);
        self.dirty = true;
        Some(result)
    }

    pub fn redo(&mut self) -> Option<EditResult> {
        let transaction = self.history.take_redo()?;
        let (undo, result) = self.invert(transaction);
        self.history.push_done(undo);
        self.dirty = true;
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

        self.history.record(
            Inverse::Splice {
                at: index,
                remove: 1,
                insert: vec![block.clone()],
            },
            Some(index),
        );

        let block = &mut self.blocks[index];
        block
            .text
            .replace_range(range.start as usize..range.end as usize, with);
        block.provenance = None;

        Ok(EditResult {
            changed: vec![id],
            removed: Vec::new(),
            inserted: Vec::new(),
            selection: DocSelection::caret(DocPosition::new(id, range.start + with.len() as u32)),
        })
    }

    fn split_block(&mut self, id: BlockId, at: u32) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        check_editable(&self.blocks[index])?;
        check_offset(&self.blocks[index], at)?;

        self.history.record(
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
            selection: DocSelection::caret(DocPosition::new(new_id, 0)),
        })
    }

    fn merge_blocks(&mut self, first: BlockId) -> Result<EditResult, EditError> {
        let index = self.index_of(first).ok_or(EditError::UnknownBlock(first))?;
        if index + 1 >= self.blocks.len() {
            return Err(EditError::NoBlockAfter(first));
        }
        check_editable(&self.blocks[index])?;
        check_editable(&self.blocks[index + 1])?;

        self.history.record(
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
        block.text.push_str(&removed.text);
        block.provenance = None;

        Ok(EditResult {
            changed: vec![first],
            removed: vec![removed.id],
            inserted: Vec::new(),
            selection: DocSelection::caret(DocPosition::new(first, junction)),
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
        if kind == BlockKind::Opaque {
            return Err(EditError::NotEditable(id));
        }
        let old_kind = self.blocks[index].kind;
        let resettle = self.predecessor_needs_rewriting(index, Some(old_kind), Some(kind));
        let at = if resettle { index - 1 } else { index };

        self.history.record(
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

        self.history.record(
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
        // A newly inserted block has no provenance, so it cannot be Opaque
        // without breaking §3.2's guarantee about what Opaque means.
        if let Some(after) = after.filter(|_| blocks.iter().any(|b| b.kind == BlockKind::Opaque)) {
            return Err(EditError::NotEditable(after));
        }

        let old_next = self.blocks.get(index).map(|block| block.kind);
        let resettle =
            index > 0 && self.predecessor_needs_rewriting(index, old_next, Some(first_new));
        let at = if resettle { index - 1 } else { index };

        self.history.record(
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
            selection: DocSelection::caret(DocPosition::new(last, caret)),
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

        self.history.record(
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
        let tail = self.blocks[last].text[to.offset as usize..].to_string();
        self.blocks.drain(first + 1..=last);

        let block = &mut self.blocks[first];
        block.text.truncate(from.offset as usize);
        block.text.push_str(&tail);
        block.provenance = None;
        let id = block.id;

        Ok(EditResult {
            changed: vec![id],
            removed,
            inserted: Vec::new(),
            selection: DocSelection::caret(DocPosition::new(id, from.offset)),
        })
    }

    // ---- history ----

    /// Applies a transaction's inverses and returns the transaction that undoes
    /// *that*, so undo and redo are the same operation in opposite directions.
    fn invert(&mut self, transaction: Transaction) -> (Transaction, EditResult) {
        let mut opposite = Transaction::default();
        let mut changed = Vec::new();
        let mut removed = Vec::new();
        let mut inserted = Vec::new();
        let mut caret = None;

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
                    caret = insert
                        .last()
                        .map(|block| DocPosition::new(block.id, block.text.len() as u32))
                        .or(caret);

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

        let selection = caret
            .map(DocSelection::caret)
            .unwrap_or_else(|| self.caret_at_start());
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

    fn caret_in(&self, index: usize) -> DocSelection {
        match self.blocks.get(index) {
            Some(block) => DocSelection::caret(DocPosition::new(block.id, block.text.len() as u32)),
            None => self.caret_at_start(),
        }
    }

    fn caret_at_start(&self) -> DocSelection {
        let block = self
            .blocks
            .first()
            .map(|block| block.id)
            .unwrap_or(BlockId(0));
        DocSelection::caret(DocPosition::new(block, 0))
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
}
