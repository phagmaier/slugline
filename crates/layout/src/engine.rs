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
    /// Complete paired cue for continuation labels, before narrow wrapping.
    cue_text: Option<Arc<str>>,
    layout: ElementLayout,
}

#[derive(Debug, Clone)]
struct PreparedBlock {
    /// Position in the snapshot's block list.
    index: usize,
    id: BlockId,
    kind: BlockKind,
    lines: Arc<[PreparedLine]>,
    scene_number: Option<String>,
    cue_text: Option<Arc<str>>,
    layout: ElementLayout,
    context: SpeechContext,
}

#[derive(Debug, Clone)]
struct PreparedLine {
    content: String,
    is_lyric: bool,
    lyric_marker_utf8: Option<usize>,
}

#[derive(Debug, Clone)]
enum FlowElement {
    /// An explicit break, and the snapshot index of the block that asks for it.
    PageBreak(usize),
    Block(PreparedBlock),
    Speech(Speech),
    Pair(Speech, Speech),
}

impl FlowElement {
    /// Snapshot index of the element's first block.
    fn first_block(&self) -> usize {
        match self {
            FlowElement::PageBreak(index) => *index,
            FlowElement::Block(block) => block.index,
            FlowElement::Speech(speech) => speech.cue.index,
            FlowElement::Pair(left, _) => left.cue.index,
        }
    }
}

/// A page an element began: the paginator put that element's first row on the
/// page's first row, having put nothing there before it. Laying the script out
/// from that element on a fresh page reproduces the page and everything after
/// it, which is what makes it somewhere to resume from and somewhere to stop.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PageStart {
    /// Snapshot index of the element's first block.
    block_index: usize,
    /// Leading blocks the paginator had read by then — see [`blocks_read`].
    settled_blocks: usize,
}

/// Where one run of the paginator begins.
#[derive(Debug, Clone, Copy)]
struct RunStart {
    first_page_number: u32,
    /// Leading blocks the pages before this run had already read.
    settled_blocks: usize,
    /// Blocks in the whole snapshot: reading past the last element reads them all.
    total_blocks: usize,
}

/// What one run of the paginator produced.
#[derive(Debug)]
struct FlowRun {
    pages: Vec<Page>,
    /// One entry per page of `pages`.
    starts: Vec<Option<PageStart>>,
    /// Set when the run stopped early at a page the caller recognised. That
    /// page and those after it are not in `pages`.
    joined: Option<PageStart>,
}

/// Where an incremental run resumes.
#[derive(Debug, Clone, Copy)]
struct Restart {
    page_index: usize,
    page_number: u32,
    block_index: usize,
    settled_blocks: usize,
    changed_index: usize,
}

#[derive(Debug, Clone)]
struct Speech {
    cue: PreparedBlock,
    body: Vec<PreparedBlock>,
    read_until: usize,
}

/// Source-order pairing decisions, including the lookahead that rejected a pair.
#[derive(Debug, Clone, Copy, Default)]
struct SpeechContext {
    right_lane: Option<bool>,
    read_until: usize,
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

    /// Incremental pagination (ADR 0049). Every block's wrap is still
    /// validated, so a wrong caller hint costs a full pagination and nothing
    /// else. Pages before the changed block are kept only from a page the
    /// paginator recorded beginning before it had read that block, and pages
    /// after it only once the same rules, run over the same script a full
    /// pagination sees, arrive at a page that begins as it did before.
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
        let (mut prepared, missed) = self.prepare_blocks(&snapshot.blocks, &mut stats);
        let restart =
            changed_block.and_then(|changed| self.restart(config, snapshot, changed, &missed));
        let total_blocks = snapshot.blocks.len();

        let (pages, checkpoints) = if let Some(restart) = restart {
            let old = &self
                .previous
                .as_ref()
                .expect("a restart comes from prior output")
                .output;
            // The prior output is already a fixed point, and the rule transform
            // is canonical and idempotent: one pass from the restart is what a
            // full pagination would settle on (§5.4).
            stats.break_rule_iterations = 1;
            stats.reused_pages = restart.page_index;
            // The restart's block begins an element now as it did then, so the
            // blocks before it can be dropped before speeches are grouped.
            let skip = prepared.partition_point(|block| block.index < restart.block_index);
            let flow = group_speeches(prepared.split_off(skip));
            let run = paginate_flow(
                &flow,
                config,
                true,
                RunStart {
                    first_page_number: restart.page_number,
                    settled_blocks: restart.settled_blocks,
                    total_blocks,
                },
                // Stop at a page the prior output also began with this element,
                // once the changed block is behind it: from there the script,
                // the page and its number are what they were.
                |page, block_index| {
                    let page_index = restart.page_index + page;
                    block_index > restart.changed_index
                        && page_index % metrics::CHECKPOINT_INTERVAL_PAGES == 0
                        && old
                            .checkpoints
                            .get(page_index / metrics::CHECKPOINT_INTERVAL_PAGES)
                            .is_some_and(|checkpoint| {
                                checkpoint.page_index == page_index
                                    && checkpoint.start_block
                                        == Some(snapshot.blocks[block_index].id)
                            })
                },
            );

            let mut pages = old.pages[..restart.page_index].to_vec();
            let mut checkpoints: Vec<_> = old
                .checkpoints
                .iter()
                .take_while(|checkpoint| checkpoint.page_index < restart.page_index)
                .cloned()
                .collect();
            checkpoints.extend(checkpoints_of(
                restart.page_index,
                &run.pages,
                &run.starts,
                snapshot,
            ));
            pages.extend(run.pages);
            if let Some(join) = run.joined {
                let join_page = pages.len();
                stats.reused_tail_pages = old.pages.len() - join_page;
                checkpoints.push(checkpoint(
                    join_page,
                    &old.pages[join_page],
                    Some(join),
                    snapshot,
                ));
                // The records further on stand. Each is how far the elements
                // up to its page had read, and no element reads more than a
                // few blocks past itself: by the next checkpoint that is all
                // script from the join onwards, which is as it was.
                checkpoints.extend(
                    old.checkpoints
                        .iter()
                        .filter(|checkpoint| checkpoint.page_index > join_page)
                        .cloned(),
                );
                pages.extend_from_slice(&old.pages[join_page..]);
            }
            (pages, checkpoints)
        } else {
            let flow = group_speeches(prepared);
            let start = RunStart {
                first_page_number: 1,
                settled_blocks: 0,
                total_blocks,
            };
            let run = |rules| paginate_flow(&flow, config, rules, start, |_, _| false);
            let mut prior = run(false);
            let mut converged = None;
            for iteration in 1..=metrics::BREAK_RULE_ITERATION_CAP {
                let candidate = run(true);
                stats.break_rule_iterations = iteration;
                if candidate.pages == prior.pages {
                    converged = Some(candidate);
                    break;
                }
                prior = candidate;
            }
            let run = converged.unwrap_or_else(|| {
                stats.fell_back_to_naive = true;
                run(false)
            });
            let checkpoints = checkpoints_of(0, &run.pages, &run.starts, snapshot).collect();
            (run.pages, checkpoints)
        };

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

    /// Where an incremental run may resume, or `None` when the prior output
    /// says nothing reliable about this snapshot and only a full pagination
    /// will do: another page setup, another block list, or anything but
    /// exactly the hinted block having changed.
    fn restart(
        &self,
        config: &PageConfig,
        snapshot: &ScriptSnapshot,
        changed: BlockId,
        missed: &[BlockId],
    ) -> Option<Restart> {
        let previous = self.previous.as_ref()?;
        // A naive layout is not what the rules produce: none of its pages is
        // somewhere a ruled run could resume or stop.
        if &previous.config != config
            || missed != [changed]
            || previous.output.stats.fell_back_to_naive
        {
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

        // The latest page that began before the paginator had read the changed
        // block. A page whose own first element is the one edited is not such a
        // page: whether that element starts a page at all is the question.
        let resumable = previous
            .output
            .checkpoints
            .iter()
            .rev()
            .filter(|checkpoint| checkpoint.settled_blocks <= changed_index)
            .find_map(|checkpoint| {
                let start = checkpoint.start_block?;
                let block_index = snapshot.blocks.iter().position(|block| block.id == start)?;
                Some(Restart {
                    page_index: checkpoint.page_index,
                    page_number: checkpoint.page_number,
                    block_index,
                    settled_blocks: checkpoint.settled_blocks,
                    changed_index,
                })
            });
        // The top of the script is always somewhere to start.
        Some(resumable.unwrap_or(Restart {
            page_index: 0,
            page_number: 1,
            block_index: 0,
            settled_blocks: 0,
            changed_index,
        }))
    }

    /// Wraps every visible block, reusing a cached wrap only where the block's
    /// fingerprint still matches. Returns the blocks whose wrap was not reused.
    fn prepare_blocks(
        &mut self,
        blocks: &[slugline_document::BlockSnapshot],
        stats: &mut CacheStats,
    ) -> (Vec<PreparedBlock>, Vec<BlockId>) {
        let mut missed = Vec::new();
        let contexts = speech_contexts(blocks);
        let prepared: Vec<PreparedBlock> = blocks
            .iter()
            .enumerate()
            .filter_map(|(index, block)| {
                let mut layout = layout_for(block.kind)?;
                let context = contexts[index];
                if let Some(right) = context.right_lane {
                    match block.kind {
                        BlockKind::Character => {
                            layout.width = metrics::DUAL_CHARACTER_WIDTH;
                            layout.indent = if right {
                                metrics::DUAL_CHARACTER_RIGHT_ORIGIN
                            } else {
                                metrics::DUAL_CHARACTER_LEFT_ORIGIN
                            };
                        }
                        BlockKind::Dialogue => {
                            layout.width = metrics::DUAL_DIALOGUE_WIDTH;
                            layout.indent = if right {
                                metrics::DUAL_DIALOGUE_RIGHT_ORIGIN
                            } else {
                                metrics::DUAL_DIALOGUE_LEFT_ORIGIN
                            };
                        }
                        BlockKind::Parenthetical => {
                            layout.width = metrics::DUAL_PARENTHETICAL_WIDTH;
                            layout.indent = if right {
                                metrics::DUAL_PARENTHETICAL_RIGHT_ORIGIN
                            } else {
                                metrics::DUAL_PARENTHETICAL_LEFT_ORIGIN
                            };
                        }
                        _ => unreachable!("only speech blocks belong to a pair"),
                    }
                }
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
                    return Some(PreparedBlock {
                        index,
                        id: block.id,
                        kind: block.kind,
                        lines: Arc::clone(&cached.lines),
                        scene_number: cached.scene_number.clone(),
                        cue_text: cached.cue_text.clone(),
                        layout,
                        context,
                    });
                }

                missed.push(block.id);
                let visible = without_notes_and_boneyards(&block.text);
                let (text, scene_number) = if block.kind == BlockKind::SceneHeading {
                    let (heading, number) = split_scene_number(&visible);
                    (heading, number.map(str::to_owned))
                } else {
                    (visible.as_ref(), None)
                };
                let display = display_text(text, layout.uppercase);
                let lines = prepare_lines(&display, layout.width, block.kind);
                let cue_text = (block.kind == BlockKind::Character && context.right_lane.is_some())
                    .then(|| Arc::<str>::from(display));
                self.cache.insert(
                    block.id,
                    CachedBlock {
                        fingerprint,
                        lines: Arc::clone(&lines),
                        scene_number: scene_number.clone(),
                        cue_text: cue_text.clone(),
                        layout,
                    },
                );
                Some(PreparedBlock {
                    index,
                    id: block.id,
                    kind: block.kind,
                    lines,
                    scene_number,
                    cue_text,
                    layout,
                    context,
                })
            })
            .collect();
        stats.block_misses += missed.len();
        stats.block_hits += prepared.len() - missed.len();
        (prepared, missed)
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

/// Resolve membership before wrapping: a marker changes both speeches' widths.
/// Hidden blocks remain in this pass, because they interrupt source adjacency.
fn speech_contexts(blocks: &[slugline_document::BlockSnapshot]) -> Vec<SpeechContext> {
    let mut contexts = vec![SpeechContext::default(); blocks.len()];
    let body_end = |cue: usize| {
        let mut end = cue + 1;
        while end < blocks.len()
            && matches!(
                blocks[end].kind,
                BlockKind::Dialogue | BlockKind::Parenthetical
            )
        {
            end += 1;
        }
        end
    };
    let mut index = 0;
    while index < blocks.len() {
        if blocks[index].kind != BlockKind::Character {
            index += 1;
            continue;
        }
        let end = body_end(index);
        let mut read_until = (end + 1).min(blocks.len());
        if end > index + 1
            && end < blocks.len()
            && blocks[end].kind == BlockKind::Character
            && blocks[end].dual
        {
            // Even an empty candidate partner required reading its next block.
            let partner_end = body_end(end);
            read_until = (partner_end + 1).min(blocks.len());
            if partner_end > end + 1 {
                for context in &mut contexts[index..end] {
                    context.right_lane = Some(false);
                }
                for context in &mut contexts[end..partner_end] {
                    context.right_lane = Some(true);
                }
                contexts[index].read_until = read_until;
                contexts[end].read_until = read_until;
                index = partner_end;
                continue;
            }
        }
        contexts[index].read_until = read_until;
        index = end;
    }
    contexts
}

fn group_speeches(blocks: Vec<PreparedBlock>) -> Vec<FlowElement> {
    let mut flow = Vec::new();
    let mut blocks = blocks.into_iter().peekable();
    while let Some(block) = blocks.next() {
        if block.kind == BlockKind::PageBreak {
            flow.push(FlowElement::PageBreak(block.index));
            continue;
        }
        if block.kind != BlockKind::Character {
            flow.push(FlowElement::Block(block));
            continue;
        }

        let right_lane = block.context.right_lane == Some(true);
        let read_until = block.context.read_until;
        let mut end = block.index + 1;
        let mut body = Vec::new();
        while blocks.peek().is_some_and(|next| {
            next.index == end && matches!(next.kind, BlockKind::Dialogue | BlockKind::Parenthetical)
        }) {
            body.push(blocks.next().expect("peeked speech body"));
            end += 1;
        }
        let speech = Speech {
            cue: block,
            body,
            read_until,
        };
        if right_lane {
            let Some(FlowElement::Speech(left)) = flow.pop() else {
                unreachable!("paired right cue follows its source-adjacent left speech");
            };
            flow.push(FlowElement::Pair(left, speech));
        } else {
            flow.push(FlowElement::Speech(speech));
        }
    }
    flow
}

/// Lays `flow` out from a fresh page.
///
/// `joins` is asked, each time an element begins a page after the first, for
/// the page's index within this run and the element's first block. Answering
/// `true` ends the run there, leaving that page and the rest to the caller.
fn paginate_flow(
    flow: &[FlowElement],
    config: &PageConfig,
    rules: bool,
    start: RunStart,
    mut joins: impl FnMut(usize, usize) -> bool,
) -> FlowRun {
    let mut paginator = Paginator::new(config, start);
    for (index, element) in flow.iter().enumerate() {
        // A scene heading is the one element placed by what follows it, so it
        // is the one whose placement reads past itself.
        let (following, examined) = match element {
            FlowElement::Block(block) if rules && block.kind == BlockKind::SceneHeading => {
                following_scene_rows(&flow[index + 1..])
            }
            _ => (0, 0),
        };
        paginator.begin(
            element.first_block(),
            blocks_read(flow, index + examined, start.total_blocks),
        );
        match element {
            FlowElement::PageBreak(_) => paginator.explicit_break(),
            FlowElement::Block(block) if rules && block.kind == BlockKind::SceneHeading => {
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
            FlowElement::Pair(left, right) => paginator.place_pair(left, right, rules),
        }
        if let Some(page) = paginator.opened.filter(|&page| page > 0) {
            if joins(page, element.first_block()) {
                return paginator.join(page);
            }
        }
    }
    paginator.finish()
}

/// How many leading blocks of the snapshot decide what `flow[index]` is.
///
/// This is the paginator's account of its own reading, and a restart is only
/// as sound as it is complete (ADR 0049): **a rule that looks at anything
/// beyond the element it is placing must be counted here.** A block or a break
/// is decided by the blocks up to itself. Speech contexts account for the end
/// of the body and every candidate partner, including a rejected empty one.
/// Past the last element there is nothing left that was not read, hidden blocks included.
fn blocks_read(flow: &[FlowElement], index: usize, total_blocks: usize) -> usize {
    match flow.get(index) {
        None => total_blocks,
        Some(FlowElement::Speech(speech)) => speech.read_until,
        Some(FlowElement::Pair(_, right)) => right.read_until,
        Some(element) => element.first_block() + 1,
    }
}

/// Rows a scene heading keeps with it, and how many of the elements after it
/// were read to count them. Running out of script counts one more than there
/// are, because finding nothing further is itself something read.
fn following_scene_rows(flow: &[FlowElement]) -> (u16, usize) {
    let mut content = 0u16;
    let mut rows = 0u16;
    for (index, element) in flow.iter().enumerate() {
        match element {
            FlowElement::PageBreak(_)
            | FlowElement::Block(PreparedBlock {
                kind: BlockKind::SceneHeading,
                ..
            }) => return (rows, index + 1),
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
            FlowElement::Pair(left, right) => {
                rows = rows.saturating_add(left.cue.layout.blanks_before);
                let height = |speech: &Speech| {
                    speech.cue.lines.len()
                        + speech
                            .body
                            .iter()
                            .map(|block| block.lines.len())
                            .sum::<usize>()
                };
                let take = (2 - content).min(height(left).max(height(right)) as u16);
                rows = rows.saturating_add(take);
                content += take;
            }
        }
        if content >= 2 {
            return (rows, index + 1);
        }
    }
    (rows, flow.len() + 1)
}

struct Paginator<'a> {
    config: &'a PageConfig,
    capacity: u16,
    pages: Vec<Page>,
    /// One entry per finished page, alongside `pages`.
    starts: Vec<Option<PageStart>>,
    current: Vec<LayoutLine>,
    /// The element that began the page being filled, if one did.
    start: Option<PageStart>,
    used: u16,
    next_number: u32,
    /// First block of the element being placed.
    element: usize,
    /// Leading blocks read so far, the element being placed and whatever its
    /// placement looked ahead to among them.
    read: usize,
    /// Whether that element has put a line of its own down yet.
    begun: bool,
    /// The page that element began, if it began one.
    opened: Option<usize>,
}

impl<'a> Paginator<'a> {
    fn new(config: &'a PageConfig, start: RunStart) -> Self {
        Self {
            config,
            capacity: config.lines_per_page(),
            pages: Vec::new(),
            starts: Vec::new(),
            current: Vec::new(),
            start: None,
            used: 0,
            next_number: start.first_page_number,
            element: 0,
            read: start.settled_blocks,
            begun: false,
            opened: None,
        }
    }

    /// Announces the element about to be placed, and how far placing it reads.
    fn begin(&mut self, first_block: usize, read: usize) {
        self.element = first_block;
        self.read = self.read.max(read);
        self.begun = false;
        self.opened = None;
    }

    fn remaining(&self) -> u16 {
        self.capacity - self.used
    }

    fn explicit_break(&mut self) {
        self.push_page(true);
    }

    fn finish(mut self) -> FlowRun {
        self.push_page(false);
        FlowRun {
            pages: self.pages,
            starts: self.starts,
            joined: None,
        }
    }

    /// Ends the run at `page`, which the element just placed began.
    fn join(mut self, page: usize) -> FlowRun {
        self.pages.truncate(page);
        self.starts.truncate(page);
        FlowRun {
            pages: self.pages,
            starts: self.starts,
            joined: Some(PageStart {
                block_index: self.element,
                settled_blocks: self.read,
            }),
        }
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
        self.starts.push(self.start.take());
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
        // An element's first line on a page's first row: the page holds nothing
        // an earlier element put there and nothing this one put before it. A
        // page that opens on this element's blank has a row in it already, and
        // is not one the element would begin if it were laid out afresh.
        if !self.begun && self.used == 0 {
            self.start = Some(PageStart {
                block_index: self.element,
                settled_blocks: self.read,
            });
            self.opened = Some(self.pages.len());
        }
        self.begun = true;
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

    fn place_pair(&mut self, left: &Speech, right: &Speech, rules: bool) {
        let mut lanes = [PairLane::new(left), PairLane::new(right)];
        let height = lanes
            .iter()
            .map(PairLane::remaining_rows)
            .max()
            .unwrap_or(0);
        let spacing = self.top_aware_spacing(&left.cue) as usize;
        // A pair that fits a fresh page is atomic, regardless of whether each
        // speech separately could have made a legal split on this page.
        if self.used > 0
            && height <= self.capacity as usize
            && spacing + height > self.remaining() as usize
        {
            self.push_page(false);
        }
        let mut first = true;
        while lanes.iter().any(|lane| lane.remaining_rows() > 0) {
            let spacing = if first {
                self.top_aware_spacing(&left.cue)
            } else {
                0
            };
            let available = self.remaining().saturating_sub(spacing) as usize;
            let mut plans = lanes.each_ref().map(|lane| lane.plan(available, rules));
            if plans.iter().any(Option::is_none) && self.used > 0 {
                self.push_page(false);
                continue;
            }
            // No legal start even on a fresh page: drain only the pending
            // prefix and body rows that fit. In raw mode, do not manufacture
            // another prefix at every page (an overheight cue would starve
            // its body). A partially consumed prefix remains pending.
            for (lane, plan) in lanes.iter_mut().zip(&mut plans) {
                if plan.is_none() {
                    lane.raw = true;
                    *plan = Some(lane.raw_plan(available));
                }
            }
            let plans = plans.map(|plan| plan.expect("fresh-page fallback makes progress"));
            self.add_blank(spacing);
            let height = plans.iter().map(PairPlan::height).max().unwrap_or(0);
            for offset in 0..height {
                let mut row = lanes[0].take_row(offset, plans[0]);
                if let Some(right) = lanes[1].take_row(offset, plans[1]) {
                    if let Some(left) = &mut row {
                        left.fragments.extend(right.fragments);
                    } else {
                        row = Some(right);
                    }
                }
                self.add_row(row.expect("the taller lane supplies every paired row"));
            }
            for (lane, plan) in lanes.iter_mut().zip(plans) {
                if plan.more {
                    lane.continue_on_next_page();
                }
            }
            first = false;
            if lanes.iter().any(|lane| lane.remaining_rows() > 0) {
                self.push_page(false);
            }
        }
    }
}

/// One lane owns its rows so emitting segments does not clone source text.
struct PairLane<'a> {
    prefix: std::vec::IntoIter<VisualRow>,
    body: std::vec::IntoIter<VisualRow>,
    cue: BlockId,
    column: i16,
    cue_text: &'a str,
    continued: Option<Vec<String>>,
    raw: bool,
}

#[derive(Clone, Copy)]
struct PairPlan {
    prefix: usize,
    body: usize,
    more: bool,
}

impl PairPlan {
    fn height(&self) -> usize {
        self.prefix + self.body + usize::from(self.more)
    }
}

impl<'a> PairLane<'a> {
    fn new(speech: &'a Speech) -> Self {
        let cue = speech
            .cue
            .cue_text
            .as_deref()
            .expect("paired cue keeps its complete display text");
        Self {
            prefix: block_rows(&speech.cue).into_iter(),
            body: speech
                .body
                .iter()
                .flat_map(block_rows)
                .collect::<Vec<_>>()
                .into_iter(),
            cue: speech.cue.id,
            column: speech.cue.layout.indent,
            cue_text: cue,
            continued: None,
            raw: false,
        }
    }

    fn remaining_rows(&self) -> usize {
        self.prefix.len() + self.body.len()
    }

    fn raw_plan(&self, available: usize) -> PairPlan {
        let prefix = self.prefix.len().min(available);
        PairPlan {
            prefix,
            body: self.body.len().min(available - prefix),
            more: false,
        }
    }

    fn plan(&self, available: usize, rules: bool) -> Option<PairPlan> {
        if !rules || self.raw {
            return Some(self.raw_plan(available));
        }
        if self.remaining_rows() <= available {
            return Some(PairPlan {
                prefix: self.prefix.len(),
                body: self.body.len(),
                more: false,
            });
        }
        let body_space = available.saturating_sub(self.prefix.len() + 1);
        legal_dialogue_split(self.body.as_slice(), 0, body_space).map(|body| PairPlan {
            prefix: self.prefix.len(),
            body,
            more: true,
        })
    }

    fn take_row(&mut self, offset: usize, plan: PairPlan) -> Option<VisualRow> {
        if offset < plan.prefix {
            self.prefix.next()
        } else if offset < plan.prefix + plan.body {
            self.body.next()
        } else if offset == plan.prefix + plan.body && plan.more {
            Some(generated_row(
                self.column,
                "(MORE)".to_owned(),
                self.cue,
                LayoutLineKind::More,
            ))
        } else {
            None
        }
    }

    fn continue_on_next_page(&mut self) {
        debug_assert_eq!(self.prefix.len(), 0);
        let continued = self.continued.get_or_insert_with(|| {
            break_lines(&continued_cue(self.cue_text), metrics::DUAL_CHARACTER_WIDTH)
        });
        self.prefix = continued
            .iter()
            .map(|text| {
                generated_row(
                    self.column,
                    text.clone(),
                    self.cue,
                    LayoutLineKind::Continued,
                )
            })
            .collect::<Vec<_>>()
            .into_iter();
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

/// The checkpoints among `pages`, whose first page is `first_page` of the script.
fn checkpoints_of<'a>(
    first_page: usize,
    pages: &'a [Page],
    starts: &'a [Option<PageStart>],
    snapshot: &'a ScriptSnapshot,
) -> impl Iterator<Item = PaginationCheckpoint> + 'a {
    pages
        .iter()
        .zip(starts)
        .enumerate()
        .map(move |(offset, entry)| (first_page + offset, entry))
        .filter(|(page_index, _)| page_index % metrics::CHECKPOINT_INTERVAL_PAGES == 0)
        .map(|(page_index, (page, start))| checkpoint(page_index, page, *start, snapshot))
}

fn checkpoint(
    page_index: usize,
    page: &Page,
    start: Option<PageStart>,
    snapshot: &ScriptSnapshot,
) -> PaginationCheckpoint {
    PaginationCheckpoint {
        page_index,
        page_number: page.number.unwrap_or((page_index + 1) as u32),
        start_block: start.map(|start| snapshot.blocks[start.block_index].id),
        settled_blocks: start.map_or(0, |start| start.settled_blocks),
    }
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
