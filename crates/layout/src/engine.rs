use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use slugline_document::{
    split_scene_number, without_notes_and_boneyards, BlockId, BlockKind, Document, TitleField,
};
use slugline_fountain::{dialogue_lyric_marker_utf8, emphasis};

use crate::line_break::{break_lines, break_lines_with_spans};
use crate::metrics;
use crate::model::{
    CacheStats, LayoutLine, LayoutLineKind, Page, PageConfig, PaginatedScript,
    PaginationCheckpoint, ScriptSnapshot,
};

/// Stateless convenience API required by SPEC §5.1.
pub fn paginate(document: &Document, config: &PageConfig) -> PaginatedScript {
    let snapshot = ScriptSnapshot::from(document);
    LayoutEngine::new().paginate_snapshot(&snapshot, config)
}

/// Reusable line-layout cache and the prior pagination checkpoints.
#[derive(Debug, Default)]
pub struct LayoutEngine {
    cache: HashMap<BlockId, CachedBlock>,
    previous: Option<PreviousPagination>,
}

#[derive(Debug)]
struct PreviousPagination {
    config: PageConfig,
    block_order: Vec<BlockId>,
    output: PaginatedScript,
}

#[derive(Debug)]
struct CachedBlock {
    fingerprint: u64,
    lines: Arc<[PreparedLine]>,
    scene_number: Option<String>,
    layout: ElementLayout,
}

#[derive(Debug, Clone)]
struct PreparedBlock {
    id: BlockId,
    kind: BlockKind,
    lines: Arc<[PreparedLine]>,
    scene_number: Option<String>,
    layout: ElementLayout,
}

#[derive(Debug, Clone)]
struct PreparedLine {
    content: String,
    is_lyric: bool,
    lyric_marker_utf8: Option<usize>,
}

#[derive(Debug, Clone)]
enum FlowElement {
    PageBreak,
    Block(PreparedBlock),
    Speech(Speech),
}

#[derive(Debug, Clone)]
struct Speech {
    cue: PreparedBlock,
    body: Vec<PreparedBlock>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Alignment {
    Left,
    Right,
    Centre,
}

#[derive(Debug, Clone, Copy)]
struct ElementLayout {
    indent: i16,
    width: u16,
    blanks_before: u16,
    alignment: Alignment,
    uppercase: bool,
}

#[derive(Debug, Clone)]
struct VisualRow {
    fragments: Vec<LayoutLine>,
    role: RowRole,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RowRole {
    Other,
    Dialogue,
    Parenthetical,
}

impl LayoutEngine {
    pub fn new() -> Self {
        Self::default()
    }

    /// Paginate an actor-owned document by first taking the lightweight owned
    /// snapshot that can safely move to a worker thread.
    pub fn paginate(&mut self, document: &Document, config: &PageConfig) -> PaginatedScript {
        self.paginate_snapshot(&ScriptSnapshot::from(document), config)
    }

    /// Full pagination. Existing cached block wraps are reused, but no output
    /// pages are assumed to match the previous revision.
    pub fn paginate_snapshot(
        &mut self,
        snapshot: &ScriptSnapshot,
        config: &PageConfig,
    ) -> PaginatedScript {
        self.paginate_internal(snapshot, config, None)
    }

    /// Incremental pagination reuses the nearest prior checkpoint before the
    /// changed block. Wrapped layout is still validated for every block, making
    /// wrong caller hints harmless; unchanged prefix pages are retained only
    /// after the newly computed output proves they are byte-for-byte equal.
    pub fn repaginate(
        &mut self,
        snapshot: &ScriptSnapshot,
        config: &PageConfig,
        changed_block: BlockId,
    ) -> PaginatedScript {
        self.paginate_internal(snapshot, config, Some(changed_block))
    }

    fn paginate_internal(
        &mut self,
        snapshot: &ScriptSnapshot,
        config: &PageConfig,
        changed_block: Option<BlockId>,
    ) -> PaginatedScript {
        let mut stats = CacheStats::default();
        let live_ids: HashSet<BlockId> = snapshot.blocks.iter().map(|block| block.id).collect();
        self.cache.retain(|id, _| live_ids.contains(id));
        let incremental_start = changed_block.and_then(|changed| {
            let (visible_blocks, missed_blocks) = self.cache_state(snapshot);
            self.incremental_start(config, snapshot, changed, &missed_blocks)
                .map(|start| (start, visible_blocks, missed_blocks.len()))
        });

        let pages =
            if let Some(((page_index, page_number, block_index, changed_index), visible, misses)) =
                incremental_start
            {
                // The prior output is already a fixed point. The rule transform is
                // canonical and idempotent. Preserve the proved-unchanged prefix and
                // run only from its block-boundary checkpoint (§5.4).
                stats.break_rule_iterations = 1;
                stats.reused_pages = page_index;
                stats.block_misses = misses;
                stats.block_hits = visible - misses;
                let convergence = self.next_checkpoint(snapshot, page_index, changed_index);
                let end_block = convergence
                    .map(|(_, _, block)| block)
                    .unwrap_or(snapshot.blocks.len());
                let prepared = self.prepare_blocks(&snapshot.blocks[block_index..end_block], None);
                let flow = group_speeches(prepared);
                let candidate = paginate_flow(&flow, config, true, page_number);
                let converged = {
                    let previous = self.previous.as_ref().expect("checkpoint has prior output");
                    convergence.is_some_and(|(end_page, _, _)| {
                        candidate.len() == end_page - page_index
                            && candidate
                                .last()
                                .zip(previous.output.pages.get(end_page - 1))
                                .is_some_and(|(new, old)| same_page_end(new, old))
                    })
                };

                if converged {
                    let end_page = convergence.expect("checked convergence").0;
                    let previous = self.previous.as_ref().expect("checkpoint has prior output");
                    stats.reused_tail_pages = previous.output.pages.len() - end_page;
                    let mut pages = previous.output.pages[..page_index].to_vec();
                    pages.extend(candidate);
                    pages.extend_from_slice(&previous.output.pages[end_page..]);
                    pages
                } else {
                    let prepared = self.prepare_blocks(&snapshot.blocks[block_index..], None);
                    let flow = group_speeches(prepared);
                    let previous = self.previous.as_ref().expect("checkpoint has prior output");
                    let mut pages = previous.output.pages[..page_index].to_vec();
                    pages.extend(paginate_flow(&flow, config, true, page_number));
                    pages
                }
            } else {
                let prepared = self.prepare_blocks(&snapshot.blocks, Some(&mut stats));
                let flow = group_speeches(prepared);
                let naive = paginate_flow(&flow, config, false, 1);
                let mut prior_pages = naive;
                let mut converged = None;
                for iteration in 1..=metrics::BREAK_RULE_ITERATION_CAP {
                    let candidate = paginate_flow(&flow, config, true, 1);
                    stats.break_rule_iterations = iteration;
                    if candidate == prior_pages {
                        converged = Some(candidate);
                        break;
                    }
                    prior_pages = candidate;
                }
                converged.unwrap_or_else(|| {
                    stats.fell_back_to_naive = true;
                    paginate_flow(&flow, config, false, 1)
                })
            };

        let checkpoints = checkpoints(&pages, snapshot);
        let output = PaginatedScript {
            revision: snapshot.revision,
            title_page: layout_title_page(snapshot, config),
            pages: pages.into(),
            checkpoints,
            stats,
        };
        self.previous = Some(PreviousPagination {
            config: config.clone(),
            block_order: snapshot.blocks.iter().map(|block| block.id).collect(),
            output: output.clone(),
        });
        output
    }

    fn incremental_start(
        &self,
        config: &PageConfig,
        snapshot: &ScriptSnapshot,
        changed: BlockId,
        missed_blocks: &[BlockId],
    ) -> Option<(usize, u32, usize, usize)> {
        let Some(previous) = &self.previous else {
            return None;
        };
        if &previous.config != config || missed_blocks != [changed] {
            return None;
        }
        if !previous
            .block_order
            .iter()
            .copied()
            .eq(snapshot.blocks.iter().map(|block| block.id))
        {
            return None;
        }
        let changed_index = snapshot
            .blocks
            .iter()
            .position(|block| block.id == changed)?;
        let unchanged_order = previous
            .block_order
            .iter()
            .take(changed_index)
            .copied()
            .eq(snapshot
                .blocks
                .iter()
                .take(changed_index)
                .map(|block| block.id));
        if !unchanged_order {
            return None;
        }

        previous
            .output
            .checkpoints
            .iter()
            .filter(|checkpoint| {
                checkpoint.start_block_line == 0
                    && checkpoint.continued_character.is_none()
                    && checkpoint
                        .start_block
                        .and_then(|id| snapshot.blocks.iter().position(|block| block.id == id))
                        .is_some_and(|index| index <= changed_index)
            })
            .max_by_key(|checkpoint| checkpoint.page_index)
            .and_then(|checkpoint| {
                let start_block = checkpoint.start_block?;
                let block_index = snapshot
                    .blocks
                    .iter()
                    .position(|block| block.id == start_block)?;
                Some((
                    checkpoint.page_index,
                    checkpoint.page_number,
                    block_index,
                    changed_index,
                ))
            })
    }

    fn next_checkpoint(
        &self,
        snapshot: &ScriptSnapshot,
        start_page: usize,
        changed_index: usize,
    ) -> Option<(usize, u32, usize)> {
        self.previous
            .as_ref()?
            .output
            .checkpoints
            .iter()
            .filter(|checkpoint| {
                checkpoint.page_index > start_page
                    && checkpoint.start_block_line == 0
                    && checkpoint.continued_character.is_none()
            })
            .filter_map(|checkpoint| {
                let block = checkpoint.start_block?;
                let block_index = snapshot
                    .blocks
                    .iter()
                    .position(|candidate| candidate.id == block)?;
                (block_index > changed_index).then_some((
                    checkpoint.page_index,
                    checkpoint.page_number,
                    block_index,
                ))
            })
            .min_by_key(|(page, _, _)| *page)
    }

    fn cache_state(&self, snapshot: &ScriptSnapshot) -> (usize, Vec<BlockId>) {
        let mut visible = 0usize;
        let mut missed = Vec::new();
        for block in &snapshot.blocks {
            let Some(layout) = layout_for(block.kind) else {
                continue;
            };
            visible += 1;
            let fingerprint = fingerprint(block, layout.width);
            if self
                .cache
                .get(&block.id)
                .is_none_or(|cached| cached.fingerprint != fingerprint)
            {
                missed.push(block.id);
            }
        }
        (visible, missed)
    }

    fn prepare_blocks(
        &mut self,
        blocks: &[slugline_document::BlockSnapshot],
        stats: Option<&mut CacheStats>,
    ) -> Vec<PreparedBlock> {
        let mut hits = 0usize;
        let mut misses = 0usize;
        let prepared = blocks
            .iter()
            .enumerate()
            .filter_map(|(index, block)| {
                let mut layout = layout_for(block.kind)?;
                if block.kind == BlockKind::Lyric
                    && index > 0
                    && blocks[index - 1].kind == BlockKind::Lyric
                {
                    layout.blanks_before = 0;
                }
                let fingerprint = fingerprint(block, layout.width);
                let cached = self.cache.get(&block.id).filter(|cached| {
                    cached.fingerprint == fingerprint
                        && cached.layout.width == layout.width
                        && cached.layout.indent == layout.indent
                });
                if let Some(cached) = cached {
                    hits += 1;
                    return Some(PreparedBlock {
                        id: block.id,
                        kind: block.kind,
                        lines: Arc::clone(&cached.lines),
                        scene_number: cached.scene_number.clone(),
                        layout,
                    });
                }

                misses += 1;
                let visible = without_notes_and_boneyards(&block.text);
                let (text, scene_number) = if block.kind == BlockKind::SceneHeading {
                    let (heading, number) = split_scene_number(&visible);
                    (heading, number.map(str::to_owned))
                } else {
                    (visible.as_ref(), None)
                };
                let display = display_text(text, layout.uppercase);
                let lines = prepare_lines(&display, layout.width, block.kind);
                self.cache.insert(
                    block.id,
                    CachedBlock {
                        fingerprint,
                        lines: Arc::clone(&lines),
                        scene_number: scene_number.clone(),
                        layout,
                    },
                );
                Some(PreparedBlock {
                    id: block.id,
                    kind: block.kind,
                    lines,
                    scene_number,
                    layout,
                })
            })
            .collect();
        if let Some(stats) = stats {
            stats.block_hits += hits;
            stats.block_misses += misses;
        }
        prepared
    }
}

fn prepare_lines(text: &str, width: u16, kind: BlockKind) -> Arc<[PreparedLine]> {
    if kind != BlockKind::Dialogue {
        return break_lines_with_spans(text, width)
            .into_iter()
            .map(|line| PreparedLine {
                content: line.text,
                is_lyric: false,
                lyric_marker_utf8: None,
            })
            .collect();
    }
    let mut hard_lines = text.split('\n');
    let mut marker = dialogue_lyric_marker_utf8(hard_lines.next().unwrap_or_default());
    break_lines_with_spans(text, width)
        .into_iter()
        .map(|line| {
            let lyric_marker_utf8 = marker
                .filter(|&offset| line.span.start_utf8 <= offset && offset < line.span.end_utf8)
                .map(|_| {
                    // The semantic marker is the first non-whitespace scalar
                    // of its hard line. Once source boundaries locate its row,
                    // the first tilde in that row is precisely that marker,
                    // even after tabs expand or indentation wraps before it.
                    line.text.find('~').expect("wrapped lyric marker")
                });
            let prepared = PreparedLine {
                content: line.text,
                is_lyric: marker.is_some(),
                lyric_marker_utf8,
            };
            if let Some(newline) = line.span.hard_break_utf8 {
                let hard_start = newline + 1;
                marker = dialogue_lyric_marker_utf8(hard_lines.next().unwrap_or_default())
                    .map(|offset| hard_start + offset);
            }
            prepared
        })
        .collect()
}

fn same_page_end(new: &Page, old: &Page) -> bool {
    let last_source = |page: &Page| {
        page.lines
            .iter()
            .rev()
            .find(|line| line.row >= 0 && line.block.is_some() && line.source_line.is_some())
            .map(|line| (line.row, line.block, line.source_line))
    };
    let last_row = |page: &Page| {
        page.lines
            .iter()
            .filter(|line| line.row >= 0)
            .map(|line| line.row)
            .max()
    };
    last_source(new) == last_source(old) && last_row(new) == last_row(old)
}

fn layout_for(kind: BlockKind) -> Option<ElementLayout> {
    let layout = match kind {
        BlockKind::SceneHeading => ElementLayout {
            indent: metrics::SCENE_HEADING_INDENT,
            width: metrics::SCENE_HEADING_WIDTH,
            blanks_before: metrics::SCENE_HEADING_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: true,
        },
        BlockKind::Action => ElementLayout {
            indent: metrics::ACTION_INDENT,
            width: metrics::ACTION_WIDTH,
            blanks_before: metrics::ACTION_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: false,
        },
        BlockKind::Character => ElementLayout {
            indent: metrics::CHARACTER_INDENT,
            width: metrics::CHARACTER_WIDTH,
            blanks_before: metrics::CHARACTER_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: true,
        },
        BlockKind::Dialogue => ElementLayout {
            indent: metrics::DIALOGUE_INDENT,
            width: metrics::DIALOGUE_WIDTH,
            blanks_before: metrics::DIALOGUE_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: false,
        },
        BlockKind::Parenthetical => ElementLayout {
            indent: metrics::PARENTHETICAL_INDENT,
            width: metrics::PARENTHETICAL_WIDTH,
            blanks_before: metrics::PARENTHETICAL_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: false,
        },
        BlockKind::Transition => ElementLayout {
            indent: 0,
            width: metrics::TRANSITION_WIDTH,
            blanks_before: metrics::TRANSITION_BLANKS_BEFORE,
            alignment: Alignment::Right,
            uppercase: true,
        },
        BlockKind::Centered => ElementLayout {
            indent: 0,
            width: metrics::CENTERED_WIDTH,
            blanks_before: metrics::CENTERED_BLANKS_BEFORE,
            alignment: Alignment::Centre,
            uppercase: false,
        },
        BlockKind::Lyric => ElementLayout {
            indent: metrics::LYRIC_INDENT,
            width: metrics::LYRIC_WIDTH,
            blanks_before: metrics::LYRIC_BLANKS_BEFORE,
            alignment: Alignment::Left,
            uppercase: false,
        },
        BlockKind::PageBreak => {
            return Some(ElementLayout {
                indent: 0,
                width: 1,
                blanks_before: 0,
                alignment: Alignment::Left,
                uppercase: false,
            })
        }
        BlockKind::Section { .. } | BlockKind::Synopsis | BlockKind::Note | BlockKind::Opaque => {
            return None
        }
    };
    Some(layout)
}

/// Upper-cases for display, one scalar at a time.
///
/// A scalar is transformed only when its upper case is exactly one scalar of
/// the same UTF-16 width, so that every display boundary still maps one-to-one
/// to a source boundary (`docs/LINE_BREAKING.md`). `é` becomes `É`; `ß` stays
/// `ß` rather than becoming `SS`, which would move every editor caret column
/// after it. Refusing per scalar rather than per block is what keeps
/// `INT. STRAßE - TAG` in capitals instead of showing the whole heading as
/// typed. Dart's `String.toUpperCase` already behaves this way, and the
/// editor's `displayText` holds it to it.
pub fn display_text(text: &str, uppercase: bool) -> String {
    if !uppercase {
        return text.to_owned();
    }
    let mut upper = String::with_capacity(text.len());
    for character in text.chars() {
        let mut mapped = character.to_uppercase();
        match (mapped.next(), mapped.next()) {
            (Some(one), None) if one.len_utf16() == character.len_utf16() => upper.push(one),
            _ => upper.push(character),
        }
    }
    upper
}

fn fingerprint(block: &slugline_document::BlockSnapshot, width: u16) -> u64 {
    // FNV-1a is sufficient for invalidation and stable across Rust versions.
    let mut hash = 0xcbf29ce484222325u64;
    for byte in block.text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    let kind: u64 = match block.kind {
        BlockKind::SceneHeading => 1,
        BlockKind::Action => 2,
        BlockKind::Character => 3,
        BlockKind::Dialogue => 4,
        BlockKind::Parenthetical => 5,
        BlockKind::Transition => 6,
        BlockKind::Centered => 7,
        BlockKind::Lyric => 8,
        BlockKind::Section { level } => 10 + u64::from(level),
        BlockKind::Synopsis => 20,
        BlockKind::Note => 21,
        BlockKind::PageBreak => 22,
        BlockKind::Opaque => 23,
    };
    for byte in kind
        .to_le_bytes()
        .into_iter()
        .chain([u8::from(block.dual)])
        .chain(width.to_le_bytes())
    {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn group_speeches(blocks: Vec<PreparedBlock>) -> Vec<FlowElement> {
    let mut flow = Vec::new();
    let mut blocks = blocks.into_iter().peekable();
    while let Some(block) = blocks.next() {
        if block.kind == BlockKind::PageBreak {
            flow.push(FlowElement::PageBreak);
            continue;
        }
        if block.kind != BlockKind::Character {
            flow.push(FlowElement::Block(block));
            continue;
        }

        let mut body = Vec::new();
        while blocks
            .peek()
            .is_some_and(|next| matches!(next.kind, BlockKind::Dialogue | BlockKind::Parenthetical))
        {
            body.push(blocks.next().expect("peeked speech body"));
        }
        flow.push(FlowElement::Speech(Speech { cue: block, body }));
    }
    flow
}

fn paginate_flow(
    flow: &[FlowElement],
    config: &PageConfig,
    rules: bool,
    first_page_number: u32,
) -> Vec<Page> {
    let mut paginator = Paginator::new(config, first_page_number);
    for (index, element) in flow.iter().enumerate() {
        match element {
            FlowElement::PageBreak => paginator.explicit_break(),
            FlowElement::Block(block) if rules && block.kind == BlockKind::SceneHeading => {
                let following = following_scene_rows(&flow[index + 1..]);
                paginator.place_scene_heading(block, following);
            }
            FlowElement::Block(block) if rules && block.kind == BlockKind::Action => {
                paginator.place_action(block);
            }
            FlowElement::Block(block) if rules && block.kind == BlockKind::Parenthetical => {
                paginator.place_parenthetical(block);
            }
            FlowElement::Block(block) => paginator.place_generic(block),
            FlowElement::Speech(speech) if rules => paginator.place_speech(speech),
            FlowElement::Speech(speech) => paginator.place_speech_naively(speech),
        }
    }
    paginator.finish()
}

fn following_scene_rows(flow: &[FlowElement]) -> u16 {
    let mut content = 0u16;
    let mut rows = 0u16;
    for element in flow {
        match element {
            FlowElement::PageBreak
            | FlowElement::Block(PreparedBlock {
                kind: BlockKind::SceneHeading,
                ..
            }) => break,
            FlowElement::Block(block) => {
                rows = rows.saturating_add(block.layout.blanks_before);
                let take = (2 - content).min(block.lines.len() as u16);
                rows = rows.saturating_add(take);
                content += take;
            }
            FlowElement::Speech(speech) => {
                rows = rows.saturating_add(speech.cue.layout.blanks_before);
                let available = speech.cue.lines.len()
                    + speech
                        .body
                        .iter()
                        .map(|block| block.lines.len())
                        .sum::<usize>();
                let take = (2 - content).min(available as u16);
                rows = rows.saturating_add(take);
                content += take;
            }
        }
        if content >= 2 {
            break;
        }
    }
    rows
}

struct Paginator<'a> {
    config: &'a PageConfig,
    capacity: u16,
    pages: Vec<Page>,
    current: Vec<LayoutLine>,
    used: u16,
    next_number: u32,
}

impl<'a> Paginator<'a> {
    fn new(config: &'a PageConfig, first_page_number: u32) -> Self {
        Self {
            config,
            capacity: config.lines_per_page(),
            pages: Vec::new(),
            current: Vec::new(),
            used: 0,
            next_number: first_page_number,
        }
    }

    fn remaining(&self) -> u16 {
        self.capacity - self.used
    }

    fn explicit_break(&mut self) {
        self.push_page(true);
    }

    fn finish(mut self) -> Vec<Page> {
        self.push_page(false);
        self.pages
    }

    fn push_page(&mut self, force: bool) {
        if self.used == 0 && !force {
            return;
        }
        let number = self.next_number;
        // Page 1 is counted but, by convention, not marked. An incremental run
        // restarts from a checkpoint's own number, so this is the same answer
        // whichever path reaches the first page.
        if number > 1 || self.config.number_first_page {
            let page_number = format!("{number}.");
            self.current.push(LayoutLine {
                row: metrics::PAGE_NUMBER_ROW,
                column: metrics::PAGE_NUMBER_RIGHT_COLUMN - char_count(&page_number) as i16,
                content: page_number,
                block: None,
                source_line: None,
                kind: LayoutLineKind::PageNumber,
                is_scene_heading: false,
                is_lyric: false,
                lyric_marker_utf8: None,
            });
        }
        self.current.sort_by_key(|line| (line.row, line.column));
        self.pages.push(Page {
            number: Some(number),
            lines: std::mem::take(&mut self.current).into(),
        });
        self.used = 0;
        self.next_number += 1;
    }

    fn add_blank(&mut self, count: u16) {
        for _ in 0..count {
            if self.used == self.capacity {
                self.push_page(false);
            }
            self.current.push(LayoutLine {
                row: self.used as i16,
                column: 0,
                content: String::new(),
                block: None,
                source_line: None,
                kind: LayoutLineKind::Blank,
                is_scene_heading: false,
                is_lyric: false,
                lyric_marker_utf8: None,
            });
            self.used += 1;
        }
    }

    fn add_row(&mut self, mut row: VisualRow) {
        if self.used == self.capacity {
            self.push_page(false);
        }
        row.fragments.retain(|fragment| match fragment.kind {
            LayoutLineKind::SceneNumberLeft => self.config.scene_numbers.left(),
            LayoutLineKind::SceneNumberRight => self.config.scene_numbers.right(),
            _ => true,
        });
        for fragment in &mut row.fragments {
            fragment.row = self.used as i16;
        }
        self.current.extend(row.fragments);
        self.used += 1;
    }

    fn top_aware_spacing(&self, block: &PreparedBlock) -> u16 {
        if self.used == 0 {
            if block.kind == BlockKind::SceneHeading {
                metrics::SCENE_HEADING_BLANKS_AT_PAGE_TOP
            } else {
                0
            }
        } else {
            block.layout.blanks_before
        }
    }

    fn place_scene_heading(&mut self, block: &PreparedBlock, following_rows: u16) {
        let spacing = self.top_aware_spacing(block);
        let needed = spacing
            .saturating_add(block.lines.len() as u16)
            .saturating_add(following_rows);
        if self.used > 0 && self.remaining() < needed {
            self.push_page(false);
        }
        self.place_generic(block);
    }

    fn place_parenthetical(&mut self, block: &PreparedBlock) {
        let spacing = self.top_aware_spacing(block);
        let needed = spacing + block.lines.len() as u16 + 1;
        if self.used > 0 && self.remaining() < needed {
            self.push_page(false);
        }
        self.place_atomic(block);
    }

    fn place_generic(&mut self, block: &PreparedBlock) {
        let spacing = self.top_aware_spacing(block);
        if self.used > 0 && spacing + block.lines.len() as u16 > self.remaining() {
            self.push_page(false);
        }
        let spacing = self.top_aware_spacing(block);
        self.add_blank(spacing);
        for row in block_rows(block) {
            self.add_row(row);
        }
    }

    fn place_atomic(&mut self, block: &PreparedBlock) {
        let spacing = self.top_aware_spacing(block);
        if self.used > 0 && spacing + block.lines.len() as u16 > self.remaining() {
            self.push_page(false);
        }
        self.place_generic(block);
    }

    fn place_action(&mut self, block: &PreparedBlock) {
        let rows = block_rows(block);
        let spacing = self.top_aware_spacing(block);
        let available = self.remaining().saturating_sub(spacing) as usize;
        if self.used > 0
            && rows.len() <= self.capacity as usize
            && (available < 2 || rows.len().saturating_sub(available) == 1)
        {
            self.push_page(false);
        }
        self.add_blank(self.top_aware_spacing(block));

        let mut index = 0usize;
        while index < rows.len() {
            let available = self.remaining() as usize;
            if available == 0 {
                self.push_page(false);
                continue;
            }
            let left = rows.len() - index;
            let mut take = left.min(available);
            if left > take {
                if take < 2 && self.used > 0 {
                    self.push_page(false);
                    continue;
                }
                if left - take == 1 && take > 2 {
                    take -= 1;
                }
            }
            for row in &rows[index..index + take] {
                self.add_row(row.clone());
            }
            index += take;
            if index < rows.len() {
                self.push_page(false);
            }
        }
    }

    fn place_speech_naively(&mut self, speech: &Speech) {
        self.place_generic(&speech.cue);
        for block in &speech.body {
            let rows = block_rows(block);
            for row in rows {
                self.add_row(row);
            }
        }
    }

    fn place_speech(&mut self, speech: &Speech) {
        let cue_rows = block_rows(&speech.cue);
        let body_rows: Vec<VisualRow> = speech.body.iter().flat_map(block_rows).collect();
        let spacing = self.top_aware_spacing(&speech.cue);
        let total = spacing + cue_rows.len() as u16 + body_rows.len() as u16;
        if total <= self.remaining() {
            self.add_blank(spacing);
            for row in cue_rows.into_iter().chain(body_rows) {
                self.add_row(row);
            }
            return;
        }

        let cue_text = speech
            .cue
            .lines
            .first()
            .map_or("", |line| line.content.as_str());
        let continued = continued_cue(cue_text);
        let mut body_index = 0usize;
        let mut first_page = true;

        while body_index < body_rows.len() || first_page {
            let prefix = if first_page {
                cue_rows.clone()
            } else {
                vec![generated_row(
                    metrics::CHARACTER_INDENT,
                    continued.clone(),
                    speech.cue.id,
                    LayoutLineKind::Continued,
                )]
            };
            let spacing = if first_page {
                self.top_aware_spacing(&speech.cue)
            } else {
                0
            };
            let remaining_body = body_rows.len() - body_index;
            if spacing as usize + prefix.len() + remaining_body <= self.remaining() as usize {
                self.add_blank(spacing);
                for row in prefix {
                    self.add_row(row);
                }
                for row in &body_rows[body_index..] {
                    self.add_row(row.clone());
                }
                break;
            }

            let overhead = spacing as usize + prefix.len() + 1;
            let available_body = (self.remaining() as usize).saturating_sub(overhead);
            let split = legal_dialogue_split(&body_rows, body_index, available_body);
            if let Some(end) = split {
                self.add_blank(spacing);
                for row in prefix {
                    self.add_row(row);
                }
                for row in &body_rows[body_index..end] {
                    self.add_row(row.clone());
                }
                self.add_row(generated_row(
                    metrics::CHARACTER_INDENT,
                    "(MORE)".to_owned(),
                    speech.cue.id,
                    LayoutLineKind::More,
                ));
                self.push_page(false);
                body_index = end;
                first_page = false;
                continue;
            }

            if self.used > 0 {
                self.push_page(false);
                continue;
            }

            // Pathological over-height cues/parentheticals have no legal break.
            // The fixed-point contract requires progress, so the naive boundary
            // is the deterministic fallback for this one segment.
            for row in prefix {
                if self.remaining() == 0 {
                    self.push_page(false);
                }
                self.add_row(row);
            }
            let take = remaining_body.min(self.remaining() as usize).max(1);
            for row in &body_rows[body_index..body_index + take.min(remaining_body)] {
                self.add_row(row.clone());
            }
            body_index += take.min(remaining_body);
            if body_index < body_rows.len() {
                self.push_page(false);
                first_page = false;
            } else {
                break;
            }
        }
    }
}

fn block_rows(block: &PreparedBlock) -> Vec<VisualRow> {
    // Body emphasis pairs across all of a block's wrapped rows, just as it
    // does in the renderer. Left-aligned and plain-text blocks need no scan.
    let printed_widths = if block.layout.alignment != Alignment::Left
        && block
            .lines
            .iter()
            .any(|line| line.content.contains(['*', '_', '\\']))
    {
        let rows: Vec<&str> = block
            .lines
            .iter()
            .map(|line| line.content.as_str())
            .collect();
        Some(emphasis::printed_widths(&rows))
    } else {
        None
    };
    block
        .lines
        .iter()
        .enumerate()
        .map(|(index, line)| {
            let content = &line.content;
            let width = || {
                printed_widths
                    .as_ref()
                    .map_or_else(|| char_count(content), |widths| widths[index])
                    as i16
            };
            let column = match block.layout.alignment {
                Alignment::Left => block.layout.indent,
                Alignment::Right => {
                    block.layout.indent + i16_from_u16(block.layout.width) - width()
                }
                Alignment::Centre => {
                    block.layout.indent + (i16_from_u16(block.layout.width) - width()) / 2
                }
            };
            let role = match block.kind {
                BlockKind::Dialogue => RowRole::Dialogue,
                BlockKind::Parenthetical => RowRole::Parenthetical,
                _ => RowRole::Other,
            };
            let mut fragments = vec![LayoutLine {
                row: 0,
                column,
                content: content.clone(),
                block: Some(block.id),
                source_line: Some(index as u16),
                kind: LayoutLineKind::Content,
                is_scene_heading: block.kind == BlockKind::SceneHeading,
                is_lyric: line.is_lyric,
                lyric_marker_utf8: line.lyric_marker_utf8,
            }];
            if index == 0 && block.kind == BlockKind::SceneHeading {
                if let Some(number) = &block.scene_number {
                    // Scene numbers occupy the gutters, never the 60-column body.
                    fragments.push(LayoutLine {
                        row: 0,
                        column: -2 - char_count(number) as i16,
                        content: number.clone(),
                        block: Some(block.id),
                        source_line: None,
                        kind: LayoutLineKind::SceneNumberLeft,
                        is_scene_heading: false,
                        is_lyric: false,
                        lyric_marker_utf8: None,
                    });
                    fragments.push(LayoutLine {
                        row: 0,
                        column: 62,
                        content: number.clone(),
                        block: Some(block.id),
                        source_line: None,
                        kind: LayoutLineKind::SceneNumberRight,
                        is_scene_heading: false,
                        is_lyric: false,
                        lyric_marker_utf8: None,
                    });
                }
            }
            VisualRow { fragments, role }
        })
        .collect()
}

fn legal_dialogue_split(rows: &[VisualRow], start: usize, available: usize) -> Option<usize> {
    if available == 0 || start >= rows.len() {
        return None;
    }
    let maximum = (start + available).min(rows.len().saturating_sub(1));
    (start + 1..=maximum).rev().find(|&end| {
        rows[end - 1].role == RowRole::Dialogue
            && rows[end].role == RowRole::Dialogue
            && dialogue_count(&rows[start..end]) >= 2
            && dialogue_count(&rows[end..]) >= 2
    })
}

fn dialogue_count(rows: &[VisualRow]) -> usize {
    rows.iter()
        .filter(|row| row.role == RowRole::Dialogue)
        .count()
}

fn generated_row(column: i16, content: String, block: BlockId, kind: LayoutLineKind) -> VisualRow {
    VisualRow {
        fragments: vec![LayoutLine {
            row: 0,
            column,
            content,
            block: Some(block),
            source_line: None,
            kind,
            is_scene_heading: false,
            is_lyric: false,
            lyric_marker_utf8: None,
        }],
        role: RowRole::Other,
    }
}

fn continued_cue(cue: &str) -> String {
    if cue.ends_with("(CONT'D)") {
        cue.to_owned()
    } else {
        format!("{cue} (CONT'D)")
    }
}

fn checkpoints(pages: &[Page], snapshot: &ScriptSnapshot) -> Vec<PaginationCheckpoint> {
    pages
        .iter()
        .enumerate()
        .filter(|(index, _)| index % metrics::CHECKPOINT_INTERVAL_PAGES == 0)
        .map(|(page_index, page)| {
            let first_source = page
                .lines
                .iter()
                .find(|line| line.row >= 0 && line.block.is_some() && line.source_line.is_some());
            let continued_character = page
                .lines
                .iter()
                .find(|line| line.kind == LayoutLineKind::Continued)
                .map(|line| line.content.clone());
            let start_block = first_source
                .and_then(|line| line.block)
                .or_else(|| snapshot.blocks.first().map(|block| block.id));
            PaginationCheckpoint {
                page_index,
                page_number: page.number.unwrap_or((page_index + 1) as u32),
                start_block,
                start_block_line: first_source
                    .and_then(|line| line.source_line)
                    .unwrap_or_default(),
                continued_character,
            }
        })
        .collect()
}

fn layout_title_page(snapshot: &ScriptSnapshot, config: &PageConfig) -> Option<Page> {
    if snapshot.title_page.is_empty() {
        return None;
    }
    let capacity = config.lines_per_page();
    let mut main = Vec::new();
    let mut lower_left = Vec::new();
    let mut lower_right = Vec::new();

    for entry in snapshot.title_page.in_canonical_order() {
        match entry.field {
            TitleField::Title
            | TitleField::Credit
            | TitleField::Author
            | TitleField::Authors
            | TitleField::Source => {
                if !main.is_empty() {
                    main.push(String::new());
                }
                main.extend(break_lines(&entry.value, metrics::ACTION_WIDTH));
            }
            TitleField::DraftDate => {
                lower_right.extend(break_lines(&entry.value, metrics::TITLE_LOWER_RIGHT_WIDTH));
            }
            TitleField::Contact | TitleField::Copyright | TitleField::Notes => {
                if !lower_left.is_empty() {
                    lower_left.push(String::new());
                }
                lower_left.extend(break_lines(&entry.value, metrics::TITLE_LOWER_LEFT_WIDTH));
            }
            TitleField::Other(ref key) => {
                let line = format!("{}: {}", key, entry.value);
                lower_left.extend(break_lines(&line, metrics::TITLE_LOWER_LEFT_WIDTH));
            }
        }
    }

    let mut lines = Vec::new();
    let main_start = capacity / 3;
    for (offset, content) in main.into_iter().enumerate() {
        lines.push(LayoutLine {
            row: i16_from_u16(main_start) + offset as i16,
            column: (i16_from_u16(metrics::ACTION_WIDTH)
                - emphasis::printed_width(&content) as i16)
                / 2,
            content,
            block: None,
            source_line: None,
            kind: LayoutLineKind::Title,
            is_scene_heading: false,
            is_lyric: false,
            lyric_marker_utf8: None,
        });
    }
    let lower_count = lower_left.len().max(lower_right.len()) as u16;
    let lower_start = capacity.saturating_sub(lower_count + 2);
    for (offset, content) in lower_left.into_iter().enumerate() {
        lines.push(LayoutLine {
            row: i16_from_u16(lower_start) + offset as i16,
            column: 0,
            content,
            block: None,
            source_line: None,
            kind: LayoutLineKind::Title,
            is_scene_heading: false,
            is_lyric: false,
            lyric_marker_utf8: None,
        });
    }
    for (offset, content) in lower_right.into_iter().enumerate() {
        lines.push(LayoutLine {
            row: i16_from_u16(lower_start) + offset as i16,
            column: i16_from_u16(metrics::ACTION_WIDTH) - emphasis::printed_width(&content) as i16,
            content,
            block: None,
            source_line: None,
            kind: LayoutLineKind::Title,
            is_scene_heading: false,
            is_lyric: false,
            lyric_marker_utf8: None,
        });
    }
    lines.sort_by_key(|line| (line.row, line.column));
    Some(Page {
        number: None,
        lines: lines.into(),
    })
}

fn char_count(text: &str) -> usize {
    text.chars().count()
}

fn i16_from_u16(value: u16) -> i16 {
    i16::try_from(value).expect("screenplay grid dimensions fit i16")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SceneNumberGutters;

    #[test]
    fn scene_numbers_are_optional_gutter_fragments() {
        let document =
            Document::parse("INT. LAB - DAY #12A#\n\nTwo lines of action live here.\nAnd here.\n");
        let hidden = paginate(&document, &PageConfig::us_letter());
        assert!(!hidden.pages[0].lines.iter().any(|line| matches!(
            line.kind,
            LayoutLineKind::SceneNumberLeft | LayoutLineKind::SceneNumberRight
        )));

        let shown = paginate(
            &document,
            &PageConfig::us_letter().with_scene_numbers(SceneNumberGutters::Both),
        );
        let numbers: Vec<_> = shown.pages[0]
            .lines
            .iter()
            .filter(|line| {
                matches!(
                    line.kind,
                    LayoutLineKind::SceneNumberLeft | LayoutLineKind::SceneNumberRight
                )
            })
            .map(|line| (line.column, line.content.as_str()))
            .collect();
        assert_eq!(numbers, [(-5, "12A"), (62, "12A")]);
    }

    #[test]
    fn uppercase_display_is_refused_per_scalar_when_it_would_change_offsets() {
        // `ß` upper-cases to `SS`, one scalar becoming two. Transforming it
        // would give the paginator a column count the editor's caret arithmetic
        // cannot reproduce, so it alone is left as written and the rest of the
        // heading is still capitals.
        assert_eq!(display_text("straße", true), "STRAßE");
        assert_eq!(display_text("int. straße - tag", true), "INT. STRAßE - TAG");
        assert_eq!(display_text("café", true), "CAFÉ");
        assert_eq!(display_text("straße", false), "straße");
        // A ligature expands the same way and is refused the same way.
        assert_eq!(display_text("ﬁn", true), "ﬁN");
    }

    #[test]
    fn every_latin_letter_with_a_capital_gets_one() {
        // A heading is shown in capitals, and that is not negotiable. Over the
        // whole Latin range — ASCII, the accented Latin-1 letters, and Latin
        // Extended-A and B — the only letters `display_text` leaves alone are
        // the three whose capital is more than one scalar. Everything a script
        // is written in is capitalised, including `é`, `ñ`, and `ø`.
        let mut declined = Vec::new();
        for scalar in 0..=0x024Fu32 {
            let Some(character) = char::from_u32(scalar) else {
                continue;
            };
            let source = character.to_string();
            if character.to_uppercase().collect::<String>() == source {
                continue; // No capital exists, or it is already one.
            }
            if display_text(&source, true) == source {
                declined.push(character);
            }
        }
        assert_eq!(declined, ['ß', 'ŉ', 'ǰ']);
    }

    #[test]
    fn the_title_page_lower_columns_cannot_reach_each_other() {
        // A long contact block opposite a draft date: before the widths were
        // split, the address printed straight through the date.
        let document = Document::parse(
            "Title: Heat\n\
             Draft date: 24 July 2026\n\
             Contact: A very long address indeed, on one line, with no break in it at all\n\
             \nAction.\n",
        );
        let output = paginate(&document, &PageConfig::us_letter());
        let title = output.title_page.expect("there is a title page");

        for line in title.lines.iter() {
            let end = line.column + char_count(&line.content) as i16;
            if line.column < i16_from_u16(metrics::TITLE_LOWER_LEFT_WIDTH) {
                assert!(
                    end <= i16_from_u16(metrics::TITLE_LOWER_LEFT_WIDTH),
                    "{:?} runs into the gutter",
                    line.content
                );
            } else {
                assert!(
                    line.column
                        >= i16_from_u16(metrics::ACTION_WIDTH - metrics::TITLE_LOWER_RIGHT_WIDTH),
                    "{:?} starts inside the left column",
                    line.content
                );
            }
        }
        assert!(
            title
                .lines
                .iter()
                .any(|line| line.content.contains("24 July 2026")),
            "the date is still on the page"
        );
    }

    #[test]
    fn title_page_is_separate_from_screenplay_page_one() {
        let document =
            Document::parse("Title: Test\nAuthor: Writer\n\nINT. ROOM - DAY\n\nAction.\n");
        let output = paginate(&document, &PageConfig::us_letter());
        assert_eq!(
            output.title_page.as_ref().and_then(|page| page.number),
            None
        );
        assert_eq!(output.pages[0].number, Some(1));
    }
}
