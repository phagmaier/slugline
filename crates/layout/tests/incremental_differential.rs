//! The incremental path against the full one (ADR 0049).
//!
//! `LayoutEngine::repaginate` keeps pages from the pagination before it. Every
//! test here asks the one question that matters about that: is the result what
//! `paginate_snapshot` makes of the same script from nothing? The goldens
//! cannot ask it, because they only ever run the full path.
//!
//! The comparison is pages, the title page and the checkpoints — every row and
//! every page break, plus what the *next* incremental run will rely on. It is
//! never the page count alone: a break in the wrong place with the right count
//! is the defect. `stats` is left out because it describes the path taken, and
//! the two paths are meant to differ there.
//!
//! A test of reuse has to see reuse. `block_misses == 1` is true of a full
//! pagination after one edit too, so the tests below count runs that kept
//! pages — `reused_pages`, `reused_tail_pages` — and fail if there are none.

use std::fs;
use std::ops::Range;
use std::path::{Path, PathBuf};

use slugline_document::{BlockId, BlockKind, BlockSnapshot, Document};
use slugline_layout::{
    metrics, CacheStats, LayoutEngine, LayoutLineKind, Page, PageConfig, PaginatedScript,
    ScriptSnapshot,
};

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("layout crate is two levels below the workspace root")
        .to_owned()
}

fn snapshot_of(source: &str) -> ScriptSnapshot {
    ScriptSnapshot::from(&Document::parse(source))
}

/// Every file in `testdata/corpus/`, by name.
fn corpus() -> Vec<(String, ScriptSnapshot)> {
    let mut paths: Vec<_> = fs::read_dir(workspace_root().join("testdata/corpus"))
        .expect("corpus directory")
        .map(|entry| entry.expect("corpus entry").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "fountain")
        })
        .collect();
    paths.sort();
    assert!(paths.len() >= 10, "the complete corpus must be covered");
    paths
        .into_iter()
        .map(|path| {
            let source = fs::read_to_string(&path).expect("UTF-8 Fountain fixture");
            let name = path
                .file_stem()
                .and_then(|stem| stem.to_str())
                .expect("UTF-8 fixture stem")
                .to_owned();
            (name, snapshot_of(&source))
        })
        .collect()
}

fn reference() -> ScriptSnapshot {
    let path = workspace_root().join("testdata/reference-feature.fountain");
    snapshot_of(&fs::read_to_string(path).expect("reference feature"))
}

/// The script laid end to end until it has `at_least` blocks.
///
/// A corpus file is a page or two, and reuse starts at the fifth page. Tiled
/// and set on short pages, each file's elements meet a page boundary in a
/// different place on every pass, which is where the two paths can disagree.
fn tiled(snapshot: &ScriptSnapshot, at_least: usize) -> ScriptSnapshot {
    let mut blocks = Vec::new();
    while blocks.len() < at_least {
        for block in &snapshot.blocks {
            blocks.push(BlockSnapshot {
                id: BlockId(blocks.len() as u64 + 1),
                ..block.clone()
            });
        }
    }
    ScriptSnapshot {
        revision: snapshot.revision,
        title_page: snapshot.title_page.clone(),
        blocks,
    }
}

// ---------------------------------------------------------------------------
// Edits that leave the block list as it was
// ---------------------------------------------------------------------------

/// What a fingerprint could plausibly get wrong, one block at a time.
#[derive(Debug, Clone, Copy)]
enum Edit {
    /// Another letter in the same place: the wrap, and so the height, stays.
    SameHeight,
    /// A row or two more.
    Taller,
    /// Many rows more: taller than a short page.
    MuchTaller,
    /// Down to its first word, and so to one row.
    Shorter,
    /// Three hard lines.
    HardLines,
    /// The same text as another element, as retyping its first characters or
    /// `SetKind` would make it.
    Kind(BlockKind),
    /// The `^` of dual dialogue, on or off.
    Dual,
}

const FILLER: &str = " and then some more of the very same thing again and again ok";

impl Edit {
    /// Returns whether the block is any different for it.
    fn apply(self, block: &mut BlockSnapshot) -> bool {
        let before = block.clone();
        match self {
            Edit::SameHeight => {
                if let Some((at, letter)) = block
                    .text
                    .char_indices()
                    .find(|(_, character)| character.is_ascii_alphabetic())
                {
                    let swapped = match letter {
                        'z' => 'a',
                        'Z' => 'A',
                        other => (other as u8 + 1) as char,
                    };
                    block
                        .text
                        .replace_range(at..at + 1, swapped.encode_utf8(&mut [0; 4]));
                }
            }
            Edit::Taller => block.text.push_str(FILLER),
            Edit::MuchTaller => block.text.push_str(&FILLER.repeat(8)),
            Edit::Shorter => {
                block.text = block
                    .text
                    .split_whitespace()
                    .next()
                    .unwrap_or_default()
                    .to_owned();
            }
            Edit::HardLines => block.text = "one\ntwo\nthree".to_owned(),
            Edit::Kind(kind) => block.kind = kind,
            Edit::Dual => block.dual = !block.dual,
        }
        *block != before
    }
}

const TEXT_EDITS: [Edit; 5] = [
    Edit::SameHeight,
    Edit::Taller,
    Edit::MuchTaller,
    Edit::Shorter,
    Edit::HardLines,
];

/// Every kind that is laid out, and one that is not.
const KINDS: [BlockKind; 10] = [
    BlockKind::SceneHeading,
    BlockKind::Action,
    BlockKind::Character,
    BlockKind::Dialogue,
    BlockKind::Parenthetical,
    BlockKind::Transition,
    BlockKind::Centered,
    BlockKind::Lyric,
    BlockKind::PageBreak,
    BlockKind::Note,
];

fn every_edit() -> Vec<Edit> {
    let mut edits = TEXT_EDITS.to_vec();
    edits.push(Edit::Dual);
    edits.extend(KINDS.map(Edit::Kind));
    edits
}

// ---------------------------------------------------------------------------
// The comparison
// ---------------------------------------------------------------------------

fn full(snapshot: &ScriptSnapshot, config: &PageConfig) -> PaginatedScript {
    LayoutEngine::new().paginate_snapshot(snapshot, config)
}

fn page_text(page: Option<&Page>) -> String {
    let Some(page) = page else {
        return "    (no such page)\n".to_owned();
    };
    page.lines
        .iter()
        .map(|line| {
            format!(
                "    {:>3} {:>3} {:?} {:?}\n",
                line.row, line.column, line.kind, line.content
            )
        })
        .collect()
}

/// Panics unless `incremental` is what a full pagination produced.
#[track_caller]
fn assert_agrees(incremental: &PaginatedScript, full: &PaginatedScript, context: &str) {
    if incremental.pages != full.pages {
        let at = incremental
            .pages
            .iter()
            .zip(full.pages.iter())
            .position(|(left, right)| left != right)
            .unwrap_or(incremental.pages.len().min(full.pages.len()));
        panic!(
            "{context}\nincremental pagination disagrees with a full one at page index {at} \
             ({} pages against {}); {:?}\n  incremental:\n{}  full:\n{}",
            incremental.pages.len(),
            full.pages.len(),
            incremental.stats,
            page_text(incremental.pages.get(at)),
            page_text(full.pages.get(at)),
        );
    }
    assert_eq!(
        incremental.title_page, full.title_page,
        "{context}\ntitle pages disagree"
    );
    assert_eq!(
        incremental.checkpoints, full.checkpoints,
        "{context}\nthe pages agree but the checkpoints the next run will resume from do not"
    );
    assert_eq!(incremental.revision, full.revision, "{context}");
}

/// How many runs kept pages, so a sweep can show it was about reuse.
#[derive(Debug, Default)]
struct Reuse {
    runs: usize,
    /// Kept pages before the change.
    before: usize,
    /// Kept pages after it.
    after: usize,
    /// Kept both.
    both: usize,
}

impl Reuse {
    fn count(&mut self, stats: &CacheStats) {
        self.runs += 1;
        let before = stats.reused_pages > 0;
        let after = stats.reused_tail_pages > 0;
        self.before += usize::from(before);
        self.after += usize::from(after);
        self.both += usize::from(before && after);
    }

    fn add(&mut self, other: &Reuse) {
        self.runs += other.runs;
        self.before += other.before;
        self.after += other.after;
        self.both += other.both;
    }
}

/// An engine that has paginated `base`, edited one block at a time.
struct Subject<'a> {
    engine: LayoutEngine,
    config: &'a PageConfig,
    reuse: Reuse,
}

impl<'a> Subject<'a> {
    fn new(base: &ScriptSnapshot, config: &'a PageConfig) -> Self {
        let mut engine = LayoutEngine::new();
        engine.paginate_snapshot(base, config);
        Self {
            engine,
            config,
            reuse: Reuse::default(),
        }
    }

    /// Repaginates, and holds the result to `expected`.
    #[track_caller]
    fn check(
        &mut self,
        snapshot: &ScriptSnapshot,
        changed: BlockId,
        expected: &PaginatedScript,
        context: &str,
    ) -> PaginatedScript {
        let output = self.engine.repaginate(snapshot, self.config, changed);
        assert_agrees(&output, expected, context);
        self.reuse.count(&output.stats);
        output
    }

    /// Repaginates, and holds the result to a full pagination from nothing.
    #[track_caller]
    fn repaginate(
        &mut self,
        snapshot: &ScriptSnapshot,
        changed: BlockId,
        context: &str,
    ) -> PaginatedScript {
        let expected = full(snapshot, self.config);
        self.check(snapshot, changed, &expected, context)
    }
}

// ---------------------------------------------------------------------------
// The corpus
// ---------------------------------------------------------------------------

const SWEEP_BLOCKS: usize = 40;

/// Every edit to every block of every corpus file, on pages `capacity` rows
/// long: short enough that there is a checkpoint every few blocks rather than
/// every hundred, and that most blocks sit beside a page break.
fn sweep_the_corpus(capacity: u16) {
    let config = PageConfig::us_letter().with_line_capacity(capacity);
    let mut reuse = Reuse::default();
    for (name, snapshot) in corpus() {
        let base = tiled(&snapshot, SWEEP_BLOCKS);
        let untouched = full(&base, &config);
        let mut subject = Subject::new(&base, &config);
        let mut script = base.clone();
        for index in 0..base.blocks.len() {
            for edit in every_edit() {
                let changed = base.blocks[index].id;
                if !edit.apply(&mut script.blocks[index]) {
                    continue;
                }
                script.revision = base.revision + 1;
                let context = format!(
                    "{name}, {capacity} rows a page, block {index} ({:?}), {edit:?}",
                    base.blocks[index].kind
                );
                subject.repaginate(&script, changed, &context);
                // And back again: an incremental run on top of an incremental
                // run, against a result already in hand.
                script.blocks[index] = base.blocks[index].clone();
                script.revision = base.revision;
                subject.check(&script, changed, &untouched, &format!("{context}, undone"));
            }
        }
        reuse.add(&subject.reuse);
    }
    println!("{capacity} rows a page: {reuse:?}");
    assert!(reuse.runs > 10_000, "{reuse:?}");
    assert!(reuse.before * 3 > reuse.runs, "{reuse:?}");
    assert!(reuse.after * 3 > reuse.runs, "{reuse:?}");
    assert!(reuse.both * 8 > reuse.runs, "{reuse:?}");
}

#[test]
fn every_single_block_edit_of_the_corpus_agrees_on_five_row_pages() {
    sweep_the_corpus(5);
}

#[test]
fn every_single_block_edit_of_the_corpus_agrees_on_eight_row_pages() {
    sweep_the_corpus(8);
}

/// xorshift64*: the walk below has to be the same walk on every machine.
struct Random(u64);

impl Random {
    fn below(&mut self, bound: usize) -> usize {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        (self.0.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 33) as usize % bound
    }
}

#[test]
fn a_run_of_edits_to_the_corpus_agrees_at_every_step() {
    // Nothing is undone here, so each step starts from pages and checkpoints
    // an earlier incremental run left, and the script drifts a long way from
    // anything the corpus holds. Inserting, removing and moving a block are in
    // the walk because they are full paginations that incremental runs follow.
    const STEPS: usize = 160;
    let mut random = Random(0x5106_11E5);
    let mut reuse = Reuse::default();
    let mut structural = 0usize;
    for (name, snapshot) in corpus() {
        let mut script = tiled(&snapshot, SWEEP_BLOCKS);
        let mut next_id = script.blocks.len() as u64 + 1;
        let config = PageConfig::us_letter().with_line_capacity(4 + random.below(8) as u16);
        let mut subject = Subject::new(&script, &config);
        for step in 0..STEPS {
            let index = random.below(script.blocks.len());
            let mut changed = script.blocks[index].id;
            let choice = random.below(20);
            let what = match choice {
                0 => {
                    let mut copy = script.blocks[random.below(script.blocks.len())].clone();
                    copy.id = BlockId(next_id);
                    next_id += 1;
                    changed = copy.id;
                    script.blocks.insert(index, copy);
                    "insert".to_owned()
                }
                1 if script.blocks.len() > SWEEP_BLOCKS / 2 => {
                    script.blocks.remove(index);
                    changed = script.blocks[index.min(script.blocks.len() - 1)].id;
                    "remove".to_owned()
                }
                2 if index + 1 < script.blocks.len() => {
                    script.blocks.swap(index, index + 1);
                    "move".to_owned()
                }
                _ => {
                    let edits = every_edit();
                    let mut edit = edits[random.below(edits.len())];
                    if script.blocks[index].text.len() > 400 {
                        edit = Edit::Shorter;
                    }
                    edit.apply(&mut script.blocks[index]);
                    format!("{edit:?}")
                }
            };
            structural += usize::from(choice <= 2);
            script.revision += 1;
            subject.repaginate(
                &script,
                changed,
                &format!(
                    "{name}, {} rows a page, step {step}: {what} at block {index}",
                    config.lines_per_page()
                ),
            );
        }
        reuse.add(&subject.reuse);
    }
    println!("{reuse:?}, {structural} structural");
    assert!(structural > 50, "{structural}");
    assert!(reuse.before * 3 > reuse.runs, "{reuse:?}");
    assert!(reuse.after * 3 > reuse.runs, "{reuse:?}");
}

// ---------------------------------------------------------------------------
// The reference feature, on real paper
// ---------------------------------------------------------------------------

/// Blocks with a row on `page`, in the order they appear.
fn blocks_on(page: &Page) -> Vec<BlockId> {
    let mut blocks = Vec::new();
    for line in page.lines.iter() {
        if let Some(block) = line.block {
            if line.kind == LayoutLineKind::Content && !blocks.contains(&block) {
                blocks.push(block);
            }
        }
    }
    blocks
}

#[test]
fn the_reference_feature_agrees_around_every_checkpoint() {
    // The corpus sweep is short pages. This is 54 and 58 rows, where a full
    // pagination is too slow to run after every possible edit, so it goes
    // where the incremental path makes its two decisions: the blocks a
    // checkpoint page begins with, and the last block of the page before it.
    let base = reference();
    for config in [PageConfig::us_letter(), PageConfig::a4()] {
        let untouched = full(&base, &config);
        assert!(
            untouched.pages.len() > 100,
            "the reference must cross many checkpoints"
        );
        let mut sites = Vec::new();
        for page_index in (metrics::CHECKPOINT_INTERVAL_PAGES..untouched.pages.len())
            .step_by(metrics::CHECKPOINT_INTERVAL_PAGES)
        {
            let opening = blocks_on(&untouched.pages[page_index]);
            let closing = blocks_on(&untouched.pages[page_index - 1]);
            sites.extend(opening.iter().take(2).copied());
            sites.extend(closing.last().copied());
        }

        // The oracle keeps its wraps between runs and never a page:
        // `paginate_snapshot` assumes nothing about the pages before it.
        let mut oracle = LayoutEngine::new();
        let mut subject = Subject::new(&base, &config);
        let mut script = base.clone();
        for (number, id) in sites.into_iter().enumerate() {
            let index = base
                .blocks
                .iter()
                .position(|block| block.id == id)
                .expect("a laid-out block is in the script");
            let edit = [Edit::Shorter, Edit::Taller][number % 2];
            if !edit.apply(&mut script.blocks[index]) {
                continue;
            }
            script.revision = base.revision + 1;
            let context = format!(
                "reference feature, {:?}, block {index} ({:?}), {edit:?}",
                config.page_size, base.blocks[index].kind
            );
            let expected = oracle.paginate_snapshot(&script, &config);
            subject.check(&script, id, &expected, &context);
            script.blocks[index] = base.blocks[index].clone();
            script.revision = base.revision;
            subject.check(&script, id, &untouched, &format!("{context}, undone"));
        }
        println!("{:?}: {:?}", config.page_size, subject.reuse);
        assert!(subject.reuse.runs > 100, "{:?}", subject.reuse);
        assert!(
            subject.reuse.before * 10 > subject.reuse.runs * 9,
            "{:?}",
            subject.reuse
        );
        assert!(
            subject.reuse.after * 2 > subject.reuse.runs,
            "{:?}",
            subject.reuse
        );
    }
}

// ---------------------------------------------------------------------------
// Named cases, on US Letter
// ---------------------------------------------------------------------------

/// One-row action blocks to a US Letter page: a row each and a blank between.
const PAGE: usize = 27;

/// Fountain source, a paragraph at a time.
#[derive(Default)]
struct Script {
    source: String,
    actions: usize,
}

impl Script {
    /// One-row action blocks, numbered through the whole script.
    fn actions(mut self, count: usize) -> Self {
        for _ in 0..count {
            self.actions += 1;
            self.source
                .push_str(&format!("Action line {}.\n\n", self.actions));
        }
        self
    }

    fn paragraph(mut self, text: &str) -> Self {
        self.source.push_str(text);
        self.source.push_str("\n\n");
        self
    }

    fn page_break(self) -> Self {
        self.paragraph("===")
    }

    /// Enough script after the part under test to end on the twelfth page,
    /// then a forced break and two pages more. The break makes the thirteenth
    /// page — a checkpoint — begin with the same block whatever moved before
    /// it, so an incremental run has somewhere to stop.
    fn closing(self) -> ScriptSnapshot {
        let script = self.actions(92).page_break().actions(40);
        snapshot_of(&script.source)
    }
}

/// Text that wraps to exactly `rows` rows in a column `width` wide: one
/// unbreakable word to a row, the first of them beginning with `label`.
fn tall(label: &str, rows: usize, width: u16) -> String {
    let width = usize::from(width);
    let first = format!("{label}{}", "x".repeat(width - label.len()));
    std::iter::once(first)
        .chain(std::iter::repeat_n("x".repeat(width), rows - 1))
        .collect::<Vec<_>>()
        .join(" ")
}

fn block(snapshot: &ScriptSnapshot, label: &str) -> usize {
    snapshot
        .blocks
        .iter()
        .position(|block| block.text.starts_with(label))
        .unwrap_or_else(|| panic!("no block begins {label:?}"))
}

/// The pages a block's rows are on.
fn pages_of(output: &PaginatedScript, snapshot: &ScriptSnapshot, index: usize) -> Range<usize> {
    let id = snapshot.blocks[index].id;
    let on: Vec<usize> = output
        .pages
        .iter()
        .enumerate()
        .filter(|(_, page)| blocks_on(page).contains(&id))
        .map(|(page_index, _)| page_index)
        .collect();
    *on.first().expect("the block is laid out")..on.last().expect("checked") + 1
}

fn rows_of(output: &PaginatedScript, snapshot: &ScriptSnapshot, index: usize) -> usize {
    let id = snapshot.blocks[index].id;
    output
        .pages
        .iter()
        .flat_map(|page| page.lines.iter())
        .filter(|line| line.block == Some(id) && line.kind == LayoutLineKind::Content)
        .count()
}

/// One named case: a script, paginated, and an engine ready to be told of edits.
struct Case {
    config: PageConfig,
    script: ScriptSnapshot,
    before: PaginatedScript,
    engine: LayoutEngine,
}

impl Case {
    fn new(script: ScriptSnapshot) -> Self {
        let config = PageConfig::us_letter();
        let mut engine = LayoutEngine::new();
        let before = engine.paginate_snapshot(&script, &config);
        assert_eq!(
            before.pages.len(),
            14,
            "twelve pages, a break, and two more"
        );
        Self {
            config,
            script,
            before,
            engine,
        }
    }

    /// Edits one block and repaginates, holding the result to a full pagination.
    #[track_caller]
    fn edit(&mut self, index: usize, edit: impl FnOnce(&mut BlockSnapshot)) -> PaginatedScript {
        edit(&mut self.script.blocks[index]);
        self.script.revision += 1;
        let changed = self.script.blocks[index].id;
        let output = self.engine.repaginate(&self.script, &self.config, changed);
        assert_agrees(&output, &full(&self.script, &self.config), "");
        output
    }
}

/// The run kept exactly these many pages before the change and after it.
#[track_caller]
fn assert_kept(output: &PaginatedScript, before: usize, after: usize) {
    assert_eq!(
        (output.stats.reused_pages, output.stats.reused_tail_pages),
        (before, after),
        "pages kept before and after the change"
    );
}

#[test]
fn an_edit_that_changes_a_blocks_height_moves_the_rows_after_it() {
    let mut case = Case::new(Script::default().actions(8 * PAGE).closing());
    // Two blocks in the middle of the tenth page, nowhere near a checkpoint.
    let edited = block(&case.script, "Action line 256.");
    let below = block(&case.script, "Action line 270.");
    assert_eq!(pages_of(&case.before, &case.script, edited), 9..10);
    assert_eq!(pages_of(&case.before, &case.script, below), 9..10);

    let output = case.edit(edited, |block| {
        block.text = tall("Taller", 4, metrics::ACTION_WIDTH)
    });

    assert_eq!(rows_of(&case.before, &case.script, edited), 1);
    assert_eq!(rows_of(&output, &case.script, edited), 4);
    assert_eq!(
        pages_of(&output, &case.script, below),
        10..11,
        "pushed over the break"
    );
    // Resumed at the ninth page, stopped at the forced break.
    assert_kept(&output, 8, 2);
}

#[test]
fn an_edit_within_a_blocks_height_changes_one_page() {
    let mut case = Case::new(Script::default().actions(8 * PAGE).closing());
    let edited = block(&case.script, "Action line 256.");

    let output = case.edit(edited, |block| block.text = "Action line 256!".to_owned());

    assert_eq!(rows_of(&output, &case.script, edited), 1);
    let differing: Vec<usize> = (0..output.pages.len())
        .filter(|&page| output.pages[page] != case.before.pages[page])
        .collect();
    assert_eq!(differing, [9]);
    // Nothing moved, so the very next checkpoint begins as it did.
    assert_kept(&output, 8, 2);
}

/// Seven pages, then a ninth-page neighbourhood built by `foot`: the eighth
/// page's last rows and whatever begins the ninth, a checkpoint page.
fn around_a_checkpoint(eighth_page_actions: usize, foot: impl FnOnce(Script) -> Script) -> Case {
    let script = Script::default().actions(7 * PAGE + eighth_page_actions);
    Case::new(foot(script).closing())
}

#[test]
fn growing_a_block_pushes_a_scene_heading_across_a_page_boundary() {
    // 25 one-row blocks leave five rows: a blank, the heading, a blank and the
    // two rows that have to stay with it. Exactly enough.
    let mut case = around_a_checkpoint(25, |script| {
        script.paragraph("INT. KITCHEN - NIGHT").paragraph(&tall(
            "Under the heading",
            2,
            metrics::ACTION_WIDTH,
        ))
    });
    let heading = block(&case.script, "INT. KITCHEN - NIGHT");
    let above = block(&case.script, "Action line 200.");
    assert_eq!(pages_of(&case.before, &case.script, heading), 7..8);
    assert_eq!(pages_of(&case.before, &case.script, above), 7..8);

    let output = case.edit(above, |block| {
        block.text = tall("Grown", 2, metrics::ACTION_WIDTH)
    });

    assert_eq!(pages_of(&output, &case.script, heading), 8..9);
    assert_kept(&output, 4, 2);
}

#[test]
fn an_insert_that_pushes_a_scene_heading_is_a_full_pagination() {
    // The same push, by a new block rather than a longer one. The engine has
    // no incremental path for a changed block list, and this holds it to
    // saying so rather than reusing a page.
    let mut case = around_a_checkpoint(25, |script| {
        script.paragraph("INT. KITCHEN - NIGHT").paragraph(&tall(
            "Under the heading",
            2,
            metrics::ACTION_WIDTH,
        ))
    });
    let heading_id = case.script.blocks[block(&case.script, "INT. KITCHEN - NIGHT")].id;
    let at = block(&case.script, "Action line 200.");
    let inserted = BlockSnapshot {
        id: BlockId(1_000_000),
        text: "A new line.".to_owned(),
        ..case.script.blocks[at].clone()
    };
    case.script.blocks.insert(at, inserted);

    let output = case.edit(at, |_| {});

    let heading = case
        .script
        .blocks
        .iter()
        .position(|block| block.id == heading_id)
        .expect("the heading is still there");
    assert_eq!(pages_of(&output, &case.script, heading), 8..9);
    assert_kept(&output, 0, 0);
}

#[test]
fn dual_dialogue_whose_partner_moves_agrees_with_a_full_pagination() {
    // A six-row paired unit (including its leading blank) fits below 24
    // one-row actions. Growing the left lane moves both partners together.
    let mut case = around_a_checkpoint(24, |script| {
        script
            .paragraph(&format!("MARTHA\n{}", "You missed the turning."))
            .paragraph(&format!(
                "DEREK ^\n(not looking)\n{}",
                tall("Partner", 3, metrics::DUAL_DIALOGUE_WIDTH)
            ))
    });
    let first = block(&case.script, "You missed the turning.");
    let partner = block(&case.script, "DEREK");
    assert!(
        case.script.blocks[partner].dual,
        "the partner carries the ^"
    );
    assert_eq!(pages_of(&case.before, &case.script, partner), 7..8);

    let output = case.edit(first, |block| {
        block.text = tall("Longer", 6, metrics::DUAL_DIALOGUE_WIDTH)
    });
    assert_eq!(pages_of(&output, &case.script, partner), 8..9);
    assert_eq!(pages_of(&output, &case.script, partner + 2), 8..9);
    assert_kept(&output, 4, 2);

    // Removing the mark restores both ordinary widths and columns. The
    // contextual cache misses deliberately require a full pagination.
    let output = case.edit(partner, |block| block.dual = false);
    assert_eq!(pages_of(&output, &case.script, partner), 8..9);
    assert_kept(&output, 0, 0);
    let output = case.edit(partner, |block| block.dual = true);
    assert_eq!(pages_of(&output, &case.script, partner), 8..9);
    assert_kept(&output, 0, 0);
    let output = case.edit(first, |block| {
        block.text = "You missed the turning.".to_owned()
    });
    assert_eq!(pages_of(&output, &case.script, partner), 7..8);
    assert_kept(&output, 4, 2);
    let output = case.edit(partner + 2, |block| {
        block.text = tall("Partner", 80, metrics::DUAL_DIALOGUE_WIDTH);
    });
    assert!(pages_of(&output, &case.script, partner + 2).len() >= 2);
}

#[test]
fn paired_membership_and_rejected_partner_lookahead_agree_across_checkpoints() {
    use BlockKind::*;
    let unit = ScriptSnapshot {
        revision: 0,
        title_page: Default::default(),
        blocks: [
            (Action, "Opening.", false),
            (Character, "MARTHA", false),
            (
                Dialogue,
                "A reply with enough words to wrap in either dialogue width.",
                false,
            ),
            (Character, "DEREK", true),
            (Parenthetical, "(not looking)", false),
            (Dialogue, "One.\nTwo.\nThree.\nFour.\nFive.\nSix.", false),
            (Character, "ALICE", false),
            (Dialogue, "An ordinary reply.", false),
            (Character, "BOB", true),
            (Note, "A hidden interruption.", false),
            (Character, "CAROL", false),
            (Dialogue, "Another reply.", false),
            (Character, "DAN", true),
            (Dialogue, "Last reply.", false),
            (PageBreak, "", false),
        ]
        .into_iter()
        .enumerate()
        .map(|(index, (kind, text, dual))| BlockSnapshot {
            id: BlockId(index as u64 + 1),
            kind,
            text: text.to_owned(),
            forced: false,
            dual,
        })
        .collect(),
    };
    let base = tiled(&unit, 180);
    for capacity in [4, 6, 9, 54] {
        let config = PageConfig::us_letter().with_line_capacity(capacity);
        let mut engine = LayoutEngine::new();
        let untouched = engine.paginate_snapshot(&base, &config);
        let mut snapshot = base.clone();
        for index in 0..base.blocks.len() {
            for edit in [
                Edit::Dual,
                Edit::Shorter,
                Edit::MuchTaller,
                Edit::HardLines,
                Edit::Kind(BlockKind::Dialogue),
                Edit::Kind(BlockKind::Character),
                Edit::Kind(BlockKind::Note),
                Edit::Kind(BlockKind::Action),
            ] {
                if !edit.apply(&mut snapshot.blocks[index]) {
                    continue;
                }
                snapshot.revision += 1;
                let context = format!(
                    "paired/rejected candidate, capacity {capacity}, block {index}, {edit:?}"
                );
                let changed = snapshot.blocks[index].id;
                let actual = engine.repaginate(&snapshot, &config, changed);
                assert_agrees(&actual, &full(&snapshot, &config), &context);
                snapshot.blocks[index] = base.blocks[index].clone();
                snapshot.revision += 1;
                let actual = engine.repaginate(&snapshot, &config, changed);
                let mut expected = untouched.clone();
                expected.revision = snapshot.revision;
                assert_agrees(&actual, &expected, &format!("{context}, undone"));
            }
        }
        // Source-order surgery can change both partners without touching text.
        for at in (1..base.blocks.len() - 1).step_by(11) {
            let mut moved = base.clone();
            moved.blocks.swap(at, at + 1);
            moved.revision += 1;
            let actual = engine.repaginate(&moved, &config, moved.blocks[at].id);
            assert_agrees(&actual, &full(&moved, &config), "partner moved");
            let mut removed = base.clone();
            removed.blocks.remove(at);
            removed.revision += 1;
            let actual = engine.repaginate(&removed, &config, removed.blocks[at].id);
            assert_agrees(
                &actual,
                &full(&removed, &config),
                "interruption/partner removed",
            );
        }
    }
}

// --- What the engine got wrong before ADR 0049 ------------------------------
//
// Each of these failed against the engine as it was: the incremental result
// had a page break a full pagination puts somewhere else.

#[test]
fn shortening_the_paragraph_a_checkpoint_page_begins_with_brings_it_back() {
    // 26 one-row blocks leave three rows. A three-row paragraph would put two
    // of them here and strand the third, so it goes over whole and the ninth
    // page begins with it. Two rows fit where three did not.
    let mut case = around_a_checkpoint(26, |script| {
        script.paragraph(&tall("Opening", 3, metrics::ACTION_WIDTH))
    });
    let opening = block(&case.script, "Opening");
    assert_eq!(pages_of(&case.before, &case.script, opening), 8..9);

    let output = case.edit(opening, |block| {
        block.text = tall("Opening", 2, metrics::ACTION_WIDTH)
    });

    assert_eq!(pages_of(&output, &case.script, opening), 7..8);
    // The ninth page is not somewhere to resume: its own first block changed.
    assert_kept(&output, 4, 2);
}

#[test]
fn lengthening_the_paragraph_a_checkpoint_page_begins_with_splits_it() {
    // The same paragraph a row longer: two rows here and two over the break is
    // a split the rules allow, where two and one was not.
    let mut case = around_a_checkpoint(26, |script| {
        script.paragraph(&tall("Opening", 3, metrics::ACTION_WIDTH))
    });
    let opening = block(&case.script, "Opening");

    let output = case.edit(opening, |block| {
        block.text = tall("Opening", 4, metrics::ACTION_WIDTH)
    });

    assert_eq!(pages_of(&output, &case.script, opening), 7..9);
    assert_kept(&output, 4, 2);
}

#[test]
fn cutting_a_speech_a_checkpoint_page_begins_with_brings_it_back() {
    // Three rows left, and a speech of a cue and three rows of dialogue: too
    // long to fit and too short to split. The edit is to the dialogue, which
    // is not the block the page begins with — the cue is.
    let mut case = around_a_checkpoint(26, |script| {
        script.paragraph(&format!(
            "MARTHA\n{}",
            tall("Speech", 3, metrics::DIALOGUE_WIDTH)
        ))
    });
    let cue = block(&case.script, "MARTHA");
    let dialogue = block(&case.script, "Speech");
    assert_eq!(pages_of(&case.before, &case.script, cue), 8..9);

    let output = case.edit(dialogue, |block| block.text = "Speech.".to_owned());

    assert_eq!(pages_of(&output, &case.script, cue), 7..8);
    assert_eq!(pages_of(&output, &case.script, dialogue), 7..8);
    assert_kept(&output, 4, 2);
}

#[test]
fn a_longer_paragraph_under_a_heading_brings_the_heading_back() {
    // Five rows left. The heading keeps two rows of what follows with it, and
    // two one-row paragraphs cost a blank each: six rows, so it goes over. Make
    // the first paragraph two rows and the heading needs five.
    let mut case = around_a_checkpoint(25, |script| {
        script
            .paragraph("INT. KITCHEN - NIGHT")
            .paragraph("Under the heading.")
    });
    let heading = block(&case.script, "INT. KITCHEN - NIGHT");
    let under = block(&case.script, "Under the heading.");
    assert_eq!(pages_of(&case.before, &case.script, heading), 8..9);

    let output = case.edit(under, |block| {
        block.text = tall("Under", 2, metrics::ACTION_WIDTH)
    });

    assert_eq!(pages_of(&output, &case.script, heading), 7..8);
    assert_eq!(pages_of(&output, &case.script, under), 7..8);
    assert_kept(&output, 4, 2);
}

#[test]
fn a_paragraph_that_becomes_a_heading_at_the_foot_of_a_page_goes_over() {
    // The last block of the eighth page, retyped as a scene heading. A heading
    // may not be left at the foot of a page with nothing under it. What is
    // under it is on the next page — past where the old engine stopped
    // reading before it declared the two layouts the same.
    let mut case = around_a_checkpoint(PAGE, |script| script);
    let last = block(&case.script, "Action line 216.");
    assert_eq!(pages_of(&case.before, &case.script, last), 7..8);
    assert_eq!(pages_of(&case.before, &case.script, last + 1), 8..9);

    let output = case.edit(last, |block| {
        block.text = "INT. HALLWAY - DAY".to_owned();
        block.kind = BlockKind::SceneHeading;
    });

    assert_eq!(pages_of(&output, &case.script, last), 8..9);
    assert_kept(&output, 4, 2);
}

#[test]
fn a_line_that_becomes_a_lyric_takes_the_next_lyric_onto_its_page() {
    // One row left under the last paragraph of the eighth page, and a lyric
    // wants a blank before it: over it goes. Make that paragraph a lyric too
    // and the blank is not wanted (ADR 0046), so the one row is enough.
    let mut case = around_a_checkpoint(PAGE, |script| script.paragraph("~Fly me to the moon"));
    let last = block(&case.script, "Action line 216.");
    let lyric = block(&case.script, "Fly me to the moon");
    assert_eq!(pages_of(&case.before, &case.script, lyric), 8..9);

    let output = case.edit(last, |block| block.kind = BlockKind::Lyric);

    assert_eq!(pages_of(&output, &case.script, lyric), 7..8);
    assert_kept(&output, 4, 2);
}

#[test]
fn a_heading_that_begins_the_last_page_has_read_to_the_end_of_the_script() {
    // Three rows left, and a heading wants four: a blank, itself, a blank and
    // the one line under it. So it begins the ninth page, and the script ends
    // a line later — which is where a writer is typing. That there was nothing
    // more to keep with the heading is something the paginator read, and the
    // line under it becoming a heading itself changes it: two rows will do.
    let script = Script::default()
        .actions(7 * PAGE + 26)
        .paragraph("INT. KITCHEN - NIGHT")
        .paragraph("The last line of the script.");
    let config = PageConfig::us_letter();
    let mut script = snapshot_of(&script.source);
    let mut engine = LayoutEngine::new();
    let before = engine.paginate_snapshot(&script, &config);
    let heading = block(&script, "INT. KITCHEN - NIGHT");
    let last = block(&script, "The last line of the script.");
    assert_eq!(pages_of(&before, &script, heading), 8..9);
    assert_eq!(before.pages.len(), 9);

    script.blocks[last].text = "EXT. STREET - LATER".to_owned();
    script.blocks[last].kind = BlockKind::SceneHeading;
    script.revision += 1;
    let output = engine.repaginate(&script, &config, script.blocks[last].id);

    assert_agrees(&output, &full(&script, &config), "");
    assert_eq!(pages_of(&output, &script, heading), 7..8);
    assert_eq!(pages_of(&output, &script, last), 8..9);
    assert_kept(&output, 4, 0);
}

#[test]
fn an_empty_forced_page_is_not_somewhere_to_resume() {
    // Two breaks in a row leave the ninth page blank. It has no first block,
    // and the old engine filled that in with the first block of the script —
    // then laid the whole script out again from the ninth page.
    let script = Script::default()
        .actions(7 * PAGE + 5)
        .page_break()
        .page_break()
        .actions(70)
        .page_break()
        .actions(40);
    let mut case = Case::new(snapshot_of(&script.source));
    assert!(blocks_on(&case.before.pages[8]).is_empty());
    let edited = block(&case.script, "Action line 240.");
    assert_eq!(pages_of(&case.before, &case.script, edited), 10..11);

    let output = case.edit(edited, |block| block.text.push_str(" Changed."));

    assert_eq!(output.pages.len(), 14);
    assert_kept(&output, 4, 2);
}

#[test]
fn an_oversized_action_after_a_full_page_begins_a_resumable_page() {
    // A paragraph taller than a page, arriving at a page that is exactly full,
    // begins the next page without a leading blank. A later edit can resume
    // there, but editing the paragraph itself must resume from before it.
    let hard_lines: Vec<String> = (1..=60).map(|line| format!("Tall line {line}.")).collect();
    let script = Script::default()
        .actions(7 * PAGE + 26)
        .paragraph(&tall("Fills the page", 2, metrics::ACTION_WIDTH))
        .paragraph(&hard_lines.join("\n"))
        .actions(60)
        .page_break()
        .actions(40);
    let mut case = Case::new(snapshot_of(&script.source));
    let giant = block(&case.script, "Tall line 1.");
    assert_eq!(pages_of(&case.before, &case.script, giant), 8..10);
    assert_eq!(
        case.before.pages[8]
            .lines
            .iter()
            .find(|line| line.row == 0)
            .map(|line| line.kind),
        Some(LayoutLineKind::Content)
    );
    assert_eq!(
        case.before
            .checkpoints
            .iter()
            .find(|checkpoint| checkpoint.page_index == 8)
            .expect("the ninth page has a checkpoint")
            .start_block,
        Some(case.script.blocks[giant].id)
    );
    let edited = block(&case.script, "Action line 250.");
    assert_eq!(pages_of(&case.before, &case.script, edited), 10..11);

    let output = case.edit(edited, |block| block.text.push_str(" Changed."));

    assert_kept(&output, 8, 2);

    let output = case.edit(giant, |block| block.text.push_str(" Changed."));
    assert_kept(&output, 4, 2);
}

// --- Hints ------------------------------------------------------------------

#[test]
fn a_wrong_hint_costs_a_full_pagination_and_nothing_else() {
    let mut case = Case::new(Script::default().actions(8 * PAGE).closing());
    let edited = block(&case.script, "Action line 256.");
    let elsewhere = block(&case.script, "Action line 30.");

    // Told of a block that did not change, while another did.
    case.script.blocks[edited].text = tall("Taller", 4, metrics::ACTION_WIDTH);
    let output = case.edit(elsewhere, |_| {});
    assert_kept(&output, 0, 0);

    // Told of one block when two changed.
    case.script.blocks[elsewhere].text.push_str(" Changed.");
    let output = case.edit(edited, |block| block.text.push_str(" Again."));
    assert_kept(&output, 0, 0);

    // Told of a block that is not in the script.
    case.script.blocks[edited].text.push_str(" And again.");
    case.script.revision += 1;
    let output = case
        .engine
        .repaginate(&case.script, &case.config, BlockId(u64::MAX));
    assert_agrees(&output, &full(&case.script, &case.config), "");
    assert_kept(&output, 0, 0);

    // Told the truth, about another page setup.
    case.config = PageConfig::a4();
    let output = case.edit(edited, |block| block.text.push_str(" Once more."));
    assert_kept(&output, 0, 0);

    // And after all of that, the truth is still worth pages.
    let output = case.edit(edited, |block| block.text.push_str(" Last."));
    assert!(output.stats.reused_pages > 0, "{:?}", output.stats);
    assert!(output.stats.reused_tail_pages > 0, "{:?}", output.stats);
}
