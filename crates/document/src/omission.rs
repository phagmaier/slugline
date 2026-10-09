use slugline_fountain::omission::{
    boneyard_is_closed, decode_omission, encode_omission, omission_boundary_is_safe,
    restore_boneyard_source, visible_remainder_forced, visible_remainder_kind, Omission,
};
use slugline_fountain::{parse, Element};

use super::*;

fn element(block: &Block, text: &str) -> Element {
    Element {
        kind: block.kind,
        text: text.to_owned(),
        forced: block.forced,
        dual: block.dual,
        provenance: None,
    }
}

impl Document {
    pub(super) fn omit_scene(&mut self, block: BlockId) -> Result<EditResult, EditError> {
        let index = self.index_of(block).ok_or(EditError::UnknownBlock(block))?;
        if self.blocks[index].kind == BlockKind::Opaque {
            return Err(EditError::NotEditable(block));
        }
        let first = (0..=index)
            .rev()
            .find(|&i| self.blocks[i].kind == BlockKind::SceneHeading)
            .ok_or(EditError::BadRange)?;
        let last = self.blocks[first + 1..]
            .iter()
            .position(|block| block.kind == BlockKind::SceneHeading)
            .map_or(self.blocks.len() - 1, |offset| first + offset);
        self.omit_range(
            DocSelection {
                anchor: DocPosition::new(self.blocks[first].id, 0),
                focus: DocPosition::new(self.blocks[last].id, self.blocks[last].text.len() as u32),
            },
            true,
        )
    }

    pub(super) fn omit_selection(&mut self, at: DocSelection) -> Result<EditResult, EditError> {
        self.omit_range(at, false)
    }

    fn omit_range(&mut self, at: DocSelection, whole_scene: bool) -> Result<EditResult, EditError> {
        self.check_selection(at)?;
        if at.is_empty() && !whole_scene {
            return Err(EditError::BadRange);
        }
        let a = self
            .index_of(at.anchor.block)
            .ok_or(EditError::UnknownBlock(at.anchor.block))?;
        let b = self
            .index_of(at.focus.block)
            .ok_or(EditError::UnknownBlock(at.focus.block))?;
        let (mut first, mut from, mut last, mut to) =
            if (a, at.anchor.offset) <= (b, at.focus.offset) {
                (a, at.anchor.offset as usize, b, at.focus.offset as usize)
            } else {
                (b, at.focus.offset as usize, a, at.anchor.offset as usize)
            };
        // An end at the next block's start does not select that block.
        if !whole_scene && last > first && to == 0 {
            last -= 1;
            to = self.blocks[last].text.len();
        }
        if first == last && from == to && !whole_scene {
            return Err(EditError::BadRange);
        }
        if !whole_scene && first < last && from == self.blocks[first].text.len() {
            first += 1;
            from = 0;
        }
        let mut fragments = Vec::with_capacity(last - first + 1);
        for (index, block) in self.blocks[first..=last].iter().enumerate() {
            let start = if index == 0 { from } else { 0 };
            let end = if first + index == last {
                to
            } else {
                block.text.len()
            };
            if block.kind == BlockKind::Opaque
                && (!whole_scene || start != 0 || end != block.text.len())
            {
                return Err(EditError::NotEditable(block.id));
            }
            fragments.push(element(block, &block.text[start..end]));
        }
        let left =
            (from > 0).then(|| element(&self.blocks[first], &self.blocks[first].text[..from]));
        let right = (to < self.blocks[last].text.len())
            .then(|| element(&self.blocks[last], &self.blocks[last].text[to..]));
        for boundary in [&left, &right].into_iter().flatten() {
            validate_block_state(None, boundary.kind, &boundary.text, boundary.dual)?;
            if boundary.kind != BlockKind::Action
                && boundary.kind != BlockKind::Note
                && boundary.text.trim().is_empty()
            {
                return Err(EditError::BadRange);
            }
            if !omission_boundary_is_safe(boundary.kind, &boundary.text) {
                return Err(EditError::BadRange);
            }
        }
        let before = first
            .checked_sub(1)
            .map(|index| element(&self.blocks[index], &self.blocks[index].text));
        let mut preceding = Vec::new();
        if before
            .as_ref()
            .is_some_and(|element| element.kind.continues_dialogue())
        {
            let mut prior = first - 1;
            while prior > 0 {
                prior -= 1;
                let block = &self.blocks[prior];
                preceding.push(element(block, &block.text));
                if !block.kind.continues_dialogue() {
                    break;
                }
            }
        }
        let following: Vec<_> = self.blocks[last + 1..]
            .iter()
            .take_while(|block| block.kind.continues_dialogue())
            .map(|block| element(block, &block.text))
            .collect();
        let after = self
            .blocks
            .get(last + 1 + following.len())
            .map(|block| element(block, &block.text));
        let omission = Omission {
            elements: fragments,
            left,
            right,
            before,
            following,
            after,
            preceding,
        };
        let mut replacement = Vec::with_capacity(3);
        if let Some(left) = &omission.left {
            let mut block = self.blocks[first].clone();
            block.text.clone_from(&left.text);
            block.provenance = None;
            replacement.push(block);
        }
        let omitted = Block {
            id: self.fresh_id(),
            kind: BlockKind::Opaque,
            text: encode_omission(&omission),
            forced: false,
            dual: false,
            provenance: None,
        };
        let caret = DocSelection::caret(DocPosition::new(omitted.id, 0));
        replacement.push(omitted);
        if let Some(right) = &omission.right {
            let mut block = self.blocks[last].clone();
            if first == last && omission.left.is_some() {
                block.id = self.fresh_id();
            }
            block.text.clone_from(&right.text);
            block.provenance = None;
            replacement.push(block);
        }
        let left_kind = omission.left.as_ref().map(|element| {
            (
                self.blocks[first].id,
                visible_remainder_kind(element, false),
                visible_remainder_forced(element, false),
                element.kind,
                element.forced,
            )
        });
        let right_kind = omission.right.as_ref().map(|element| {
            (
                replacement.last().unwrap().id,
                visible_remainder_kind(element, true),
                visible_remainder_forced(element, true),
                element.kind,
                element.forced,
            )
        });
        let orphan_cue = omission
            .before
            .as_ref()
            .filter(|element| omission.left.is_none() && element.kind == BlockKind::Character)
            .map(|element| {
                (
                    self.blocks[first - 1].id,
                    visible_remainder_forced(element, false),
                    element.forced,
                )
            });
        let following_start = first + replacement.len();
        // The public mutation boundary groups this splice and every SetKind,
        // recording the caller's actual directed selection only once.
        let mut merged = Merged::default();
        merged.absorb(self.omission_splice(first, last + 1, replacement, Some(caret)));
        for (block, kind, forced, original, original_forced) in
            left_kind.into_iter().chain(right_kind)
        {
            if kind != original || forced != original_forced {
                merged.absorb(self.apply_command(EditCommand::SetKind {
                    block,
                    kind,
                    forced,
                })?);
            }
        }
        if let Some((block, forced, original_forced)) = orphan_cue {
            if forced != original_forced {
                merged.absorb(self.apply_command(EditCommand::SetKind {
                    block,
                    kind: BlockKind::Character,
                    forced,
                })?);
            }
        }
        for offset in 0..omission.following.len() {
            let block = self.blocks[following_start + offset].id;
            merged.absorb(self.apply_command(EditCommand::SetKind {
                block,
                kind: BlockKind::Action,
                forced: true,
            })?);
        }
        merged.selection = Some(caret);
        Ok(merged.into_result())
    }

    pub(super) fn restore_omitted(&mut self, at: DocSelection) -> Result<EditResult, EditError> {
        self.check_selection(at)?;
        let a = self
            .index_of(at.anchor.block)
            .ok_or(EditError::UnknownBlock(at.anchor.block))?;
        let b = self
            .index_of(at.focus.block)
            .ok_or(EditError::UnknownBlock(at.focus.block))?;
        let (first, start, last, end) = if (a, at.anchor.offset) <= (b, at.focus.offset) {
            (a, at.anchor.offset, b, at.focus.offset)
        } else {
            (b, at.focus.offset, a, at.anchor.offset)
        };
        let ids: Vec<_> = self.blocks[first..=last]
            .iter()
            .enumerate()
            .filter(|(offset, block)| {
                block.kind == BlockKind::Opaque
                    && (at.is_empty()
                        || (first + offset != last || end != 0)
                            && (*offset != 0 || start as usize != block.text.len()))
            })
            .map(|(_, block)| block.id)
            .collect();
        if ids.is_empty() {
            return Err(EditError::BadRange);
        }
        let mut merged = Merged::default();
        for id in ids.into_iter().rev() {
            let result = self.restore_boneyard(id).map_err(|error| match error {
                EditError::BadRange | EditError::InvalidBlock { .. } => {
                    EditError::CannotRestoreOmission
                }
                error => error,
            })?;
            merged.absorb(result);
        }
        Ok(merged.into_result())
    }

    fn restore_boneyard(&mut self, id: BlockId) -> Result<EditResult, EditError> {
        let index = self.index_of(id).ok_or(EditError::UnknownBlock(id))?;
        let block = &self.blocks[index];
        let record = decode_omission(&block.text).map_err(|_| EditError::BadRange)?;
        let recorded = record.is_some();
        let (elements, left, right, before, following, after, preceding) = match record {
            Some(record) => (
                record.elements,
                record.left,
                record.right,
                record.before,
                record.following,
                record.after,
                record.preceding,
            ),
            None => {
                let source =
                    restore_boneyard_source(&block.text).ok_or(EditError::NotEditable(id))?;
                // A comment's contents are body source, not a replacement title page.
                let mut source_body = String::from("\n");
                source_body.push_str(&source);
                (
                    parse(&source_body).elements,
                    None,
                    None,
                    None,
                    Vec::new(),
                    None,
                    Vec::new(),
                )
            }
        };
        for element in &elements {
            if element.kind == BlockKind::Opaque {
                let parsed = parse(&element.text);
                if element.dual
                    || !matches!(parsed.elements.as_slice(),
                    [boneyard] if boneyard.kind == BlockKind::Opaque && boneyard.text == element.text)
                {
                    return Err(EditError::BadRange);
                }
            }
        }
        let mut first = index;
        let mut end = index + 1;
        let mut restored: Vec<Block> = elements
            .into_iter()
            .map(|element| Block {
                id: BlockId(0),
                kind: element.kind,
                text: element.text,
                forced: element.forced,
                dual: element.dual,
                provenance: None,
            })
            .collect();
        if recorded {
            let seam_first = index
                .checked_sub(usize::from(left.is_some()))
                .ok_or(EditError::BadRange)?;
            let neighbor = seam_first.checked_sub(1).map(|i| &self.blocks[i]);
            let mut visible_before = before.clone();
            if left.is_none() {
                if let Some(expected) = visible_before
                    .as_mut()
                    .filter(|e| e.kind == BlockKind::Character)
                {
                    expected.forced = visible_remainder_forced(expected, false);
                }
            }
            if !matches_witness(neighbor, visible_before.as_ref()) {
                return Err(EditError::BadRange);
            }
            for (offset, expected) in preceding.iter().enumerate() {
                let prior = seam_first
                    .checked_sub(offset + 2)
                    .and_then(|i| self.blocks.get(i));
                if !matches_witness(prior, Some(expected)) {
                    return Err(EditError::BadRange);
                }
            }
            let seam_end = end + usize::from(right.is_some()) + following.len();
            if !matches_witness(self.blocks.get(seam_end), after.as_ref()) {
                return Err(EditError::BadRange);
            }
        }
        if let Some(expected) = left {
            let neighbor = index
                .checked_sub(1)
                .map(|i| &self.blocks[i])
                .ok_or(EditError::BadRange)?;
            let head = restored.first_mut().ok_or(EditError::BadRange)?;
            if !compatible_remainder(neighbor, &expected, false)
                || head.kind != expected.kind
                || head.forced != expected.forced
                || head.dual != expected.dual
            {
                return Err(EditError::BadRange);
            }
            head.text.insert_str(0, boundary_text(neighbor, &expected));
            head.id = neighbor.id;
            first -= 1;
        }
        if let Some(expected) = right {
            let neighbor = self.blocks.get(end).ok_or(EditError::BadRange)?;
            let tail = restored.last_mut().ok_or(EditError::BadRange)?;
            if !compatible_remainder(neighbor, &expected, true)
                || tail.kind != expected.kind
                || tail.forced != expected.forced
                || tail.dual != expected.dual
            {
                return Err(EditError::BadRange);
            }
            tail.text.push_str(boundary_text(neighbor, &expected));
            if tail.id == BlockId(0) {
                tail.id = neighbor.id;
            }
            end += 1;
        }
        if let Some(expected) = before {
            // A removed speech body makes its old cue require @ on disk.
            // Reconnect the original live flag only after its witness matched.
            if first == index && expected.kind == BlockKind::Character {
                let neighbor = first
                    .checked_sub(1)
                    .map(|i| &self.blocks[i])
                    .ok_or(EditError::BadRange)?;
                let mut cue = neighbor.clone();
                cue.forced = expected.forced;
                cue.provenance = None;
                restored.insert(0, cue);
                first -= 1;
            }
        }
        for expected in following {
            if !expected.kind.continues_dialogue() {
                return Err(EditError::BadRange);
            }
            let neighbor = self.blocks.get(end).ok_or(EditError::BadRange)?;
            if !compatible_remainder(neighbor, &expected, true) {
                return Err(EditError::BadRange);
            }
            let mut tail = neighbor.clone();
            if tail.text == expected.text
                && (tail.kind != expected.kind || tail.forced != expected.forced)
            {
                tail.kind = expected.kind;
                tail.forced = expected.forced;
                tail.dual = expected.dual;
                tail.provenance = None;
            }
            restored.push(tail);
            end += 1;
        }
        // An orphan Dialogue has no Fountain representation. Refuse an ambiguous
        // changed seam instead of restoring text that a save would reclassify.
        let mut previous = first.checked_sub(1).map(|i| self.blocks[i].kind);
        for block in &restored {
            if block.kind.continues_dialogue()
                && !previous
                    .is_some_and(|kind| kind == BlockKind::Character || kind.continues_dialogue())
            {
                return Err(EditError::BadRange);
            }
            previous = Some(block.kind);
        }
        // Never let restoring an old unclosed nested comment swallow newer text.
        for (offset, block) in restored.iter().enumerate() {
            let unclosed = if block.kind == BlockKind::Opaque {
                !boneyard_is_closed(&block.text)
            } else {
                !omission_boundary_is_safe(block.kind, &block.text)
            };
            if unclosed
                && (block.kind != BlockKind::Opaque
                    || offset + 1 != restored.len()
                    || end != self.blocks.len())
            {
                return Err(EditError::BadRange);
            }
            if block.kind != BlockKind::Opaque {
                validate_block_state(None, block.kind, &block.text, block.dual)?;
            }
        }
        if restored.is_empty() && first == 0 && end == self.blocks.len() {
            restored.push(Block {
                id: BlockId(0),
                kind: BlockKind::Action,
                text: String::new(),
                forced: false,
                dual: false,
                provenance: None,
            });
        }
        if recorded {
            // Partial kinds are not independently valid screenplay source.
            // Check the reassembled speech with the real serializer/parser
            // before consuming its only lossless record.
            let mut context = first;
            if restored
                .first()
                .is_some_and(|block| block.kind.continues_dialogue())
            {
                while context > 0 && self.blocks[context - 1].kind.continues_dialogue() {
                    context -= 1;
                }
                if context > 0 && self.blocks[context - 1].kind == BlockKind::Character {
                    context -= 1;
                }
            }
            let elements: Vec<_> = self.blocks[context..first]
                .iter()
                .chain(restored.iter())
                .map(|block| ElementRef {
                    kind: block.kind,
                    text: &block.text,
                    forced: block.forced,
                    dual: block.dual,
                    provenance: None,
                })
                .collect();
            let source = serialise(&Output {
                title_page: &TitlePage::default(),
                elements: &elements,
                source: None,
                bom: false,
                line_ending: self.line_ending,
            });
            let parsed = parse(&source);
            if parsed.elements.len() != elements.len()
                || parsed
                    .elements
                    .iter()
                    .zip(&elements)
                    .any(|(actual, expected)| {
                        actual.kind != expected.kind
                            || actual.text != expected.text
                            || actual.dual != expected.dual
                    })
            {
                return Err(EditError::BadRange);
            }
        }
        for block in &mut restored {
            if block.id == BlockId(0) {
                block.id = self.fresh_id();
            }
        }
        let selection = restored
            .first()
            .map(|block| DocSelection::caret(DocPosition::new(block.id, 0)))
            .or_else(|| {
                self.blocks
                    .get(end)
                    .map(|block| DocSelection::caret(DocPosition::new(block.id, 0)))
            })
            .or_else(|| {
                first
                    .checked_sub(1)
                    .map(|i| DocSelection::caret(DocPosition::new(self.blocks[i].id, 0)))
            });
        Ok(self.omission_splice(first, end, restored, selection))
    }

    fn omission_splice(
        &mut self,
        first: usize,
        end: usize,
        replacement: Vec<Block>,
        selection: Option<DocSelection>,
    ) -> EditResult {
        let old_ids: Vec<_> = self.blocks[first..end]
            .iter()
            .map(|block| block.id)
            .collect();
        let new_ids: Vec<_> = replacement.iter().map(|block| block.id).collect();
        let mut changed: Vec<_> = new_ids
            .iter()
            .filter(|id| old_ids.contains(id))
            .copied()
            .collect();
        let resettle = first > 0
            && self.predecessor_needs_rewriting(
                first,
                self.blocks.get(first).map(|block| block.kind),
                replacement.first().map(|block| block.kind),
            );
        let at = if resettle { first - 1 } else { first };
        self.record(
            Inverse::Splice {
                at,
                remove: replacement.len() + first - at,
                insert: self.blocks[at..end].to_vec(),
            },
            None,
        );
        if resettle {
            self.blocks[first - 1].provenance = None;
            changed.push(self.blocks[first - 1].id);
        }
        self.blocks.splice(first..end, replacement);
        EditResult {
            changed,
            removed: old_ids
                .iter()
                .filter(|id| !new_ids.contains(id))
                .copied()
                .collect(),
            inserted: new_ids
                .iter()
                .filter(|id| !old_ids.contains(id))
                .copied()
                .collect(),
            selection,
        }
    }
}

fn compatible_remainder(block: &Block, expected: &Element, after_boneyard: bool) -> bool {
    let kind = visible_remainder_kind(expected, after_boneyard);
    let forced = visible_remainder_forced(expected, after_boneyard);
    block.kind == kind
        && block.dual == expected.dual
        && boundary_text(block, expected) == expected.text
        && (block.forced == forced || redundant_pin_difference(block, expected))
}

fn compatible_boundary(block: &Block, expected: &Element) -> bool {
    let same_kind = block.kind == expected.kind
        || (block.provenance.is_some()
            && ((expected.kind.continues_dialogue()
                && (block.kind == BlockKind::Action || block.kind.continues_dialogue()))
                || (expected.kind == BlockKind::Note && block.kind == BlockKind::Action)));
    same_kind && block.dual == expected.dual
        && boundary_text(block, expected) == expected.text
        // Canonical Fountain keeps only necessary markers (ADR 0059).
        // A reopened seam may therefore lose a redundant live forced pin.
        && (block.forced == expected.forced || redundant_pin_difference(block, expected))
}

fn redundant_pin_difference(block: &Block, expected: &Element) -> bool {
    block.provenance.is_some()
        && !(expected.kind == BlockKind::Character
            && slugline_fountain::case::changes_when_uppercased(&expected.text))
}

fn matches_witness(block: Option<&Block>, expected: Option<&Element>) -> bool {
    match (block, expected) {
        (Some(block), Some(expected)) => compatible_boundary(block, expected),
        (None, None) => true,
        _ => false,
    }
}

fn boundary_text<'a>(block: &'a Block, expected: &'a Element) -> &'a str {
    // Fountain trims single-line element markers. The record retains the exact
    // remainder so a reopen cannot eat a space at a partial selection seam.
    if (!expected.kind.is_multiline() || expected.kind == BlockKind::Note)
        && block.text == expected.text.trim()
    {
        &expected.text
    } else {
        &block.text
    }
}
