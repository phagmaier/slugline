use std::sync::Arc;

use slugline_document::{BlockId, BlockSnapshot, Document, TitlePage};

use crate::metrics;

/// Physical page presets supported by the fixed grid.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum PageSize {
    #[default]
    UsLetter,
    A4,
}

impl PageSize {
    pub const fn width_um(self) -> u32 {
        match self {
            PageSize::UsLetter => metrics::US_LETTER_WIDTH_UM,
            PageSize::A4 => metrics::A4_WIDTH_UM,
        }
    }

    pub const fn height_um(self) -> u32 {
        match self {
            PageSize::UsLetter => metrics::US_LETTER_HEIGHT_UM,
            PageSize::A4 => metrics::A4_HEIGHT_UM,
        }
    }
}

/// Which scene-number gutters the renderer should receive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum SceneNumberGutters {
    #[default]
    None,
    Left,
    Right,
    Both,
}

impl SceneNumberGutters {
    pub(crate) const fn left(self) -> bool {
        matches!(self, SceneNumberGutters::Left | SceneNumberGutters::Both)
    }

    pub(crate) const fn right(self) -> bool {
        matches!(self, SceneNumberGutters::Right | SceneNumberGutters::Both)
    }
}

/// Pagination inputs. The optional override exists for small break-rule tests
/// and debug dumps; production presets always derive rows from paper height.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PageConfig {
    pub page_size: PageSize,
    pub scene_numbers: SceneNumberGutters,
    /// Output weight only; does not change the fixed-grid geometry.
    pub bold_scene_headings: bool,
    /// Whether page 1 prints its `1.`. Off by default: the convention leaves
    /// the first page unnumbered. The line sits in the top margin, so no row
    /// moves either way, and the page is still `number = Some(1)`.
    pub number_first_page: bool,
    line_capacity_override: Option<u16>,
}

impl Default for PageConfig {
    fn default() -> Self {
        Self::us_letter()
    }
}

impl PageConfig {
    pub const fn us_letter() -> Self {
        Self {
            page_size: PageSize::UsLetter,
            scene_numbers: SceneNumberGutters::None,
            bold_scene_headings: false,
            number_first_page: false,
            line_capacity_override: None,
        }
    }

    pub const fn a4() -> Self {
        Self {
            page_size: PageSize::A4,
            scene_numbers: SceneNumberGutters::None,
            bold_scene_headings: false,
            number_first_page: false,
            line_capacity_override: None,
        }
    }

    pub const fn with_scene_numbers(mut self, gutters: SceneNumberGutters) -> Self {
        self.scene_numbers = gutters;
        self
    }

    pub const fn with_bold_scene_headings(mut self, bold: bool) -> Self {
        self.bold_scene_headings = bold;
        self
    }

    pub const fn with_number_first_page(mut self, number: bool) -> Self {
        self.number_first_page = number;
        self
    }

    /// Builds a reduced page for deterministic rule tests and debug tooling.
    pub fn with_line_capacity(mut self, lines: u16) -> Self {
        self.line_capacity_override = Some(lines.max(4));
        self
    }

    pub const fn lines_per_page(&self) -> u16 {
        match self.line_capacity_override {
            Some(lines) => lines,
            None => metrics::lines_for_height(self.page_size.height_um()),
        }
    }
}

/// An immutable worker-thread input without document history or provenance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScriptSnapshot {
    pub revision: u64,
    pub title_page: TitlePage,
    pub blocks: Vec<BlockSnapshot>,
}

impl ScriptSnapshot {
    pub fn from_document(document: &Document) -> Self {
        Self {
            revision: document.revision(),
            title_page: document.title_page().clone(),
            blocks: document
                .blocks()
                .iter()
                .map(|block| BlockSnapshot {
                    id: block.id(),
                    kind: block.kind(),
                    text: block.text().to_owned(),
                    forced: block.forced(),
                    dual: block.dual(),
                })
                .collect(),
        }
    }
}

impl From<&Document> for ScriptSnapshot {
    fn from(document: &Document) -> Self {
        Self::from_document(document)
    }
}

/// Why a positioned fragment exists.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LayoutLineKind {
    Content,
    Blank,
    PageNumber,
    SceneNumberLeft,
    SceneNumberRight,
    More,
    Continued,
    Title,
}

/// One printable fragment. Rows are relative to the top of the text area and
/// columns to its left edge; gutters and the page number may be negative.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct LayoutLine {
    pub row: i16,
    pub column: i16,
    pub content: String,
    pub block: Option<BlockId>,
    /// Wrapped line within `block`; absent for generated furniture.
    pub source_line: Option<u16>,
    pub kind: LayoutLineKind,
    /// True only for content rows originating in a scene-heading block.
    pub is_scene_heading: bool,
    /// True for every wrapped row of a sung hard line within Dialogue.
    pub is_lyric: bool,
    /// UTF-8 byte offset of that hard line's leading `~` in raw `content`.
    /// Only the wrapped row containing the marker has an offset.
    pub lyric_marker_utf8: Option<usize>,
}

/// One title or screenplay page. Screenplay pages have `number = Some(1..)`;
/// the title page has no number and lives separately on [`PaginatedScript`].
/// `number` is the page's place in the count, not a promise that it is
/// printed: only a [`LayoutLineKind::PageNumber`] line says that, and page 1
/// carries one only under [`PageConfig::number_first_page`].
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Page {
    pub number: Option<u32>,
    pub lines: Arc<[LayoutLine]>,
}

/// Restart information retained every N pages for incremental repagination.
///
/// The paginator records it as it lays the page out; it is not worked out from
/// the page's lines afterwards (ADR 0049).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaginationCheckpoint {
    pub page_index: usize,
    pub page_number: u32,
    /// First block of the element that began this page: its first row is the
    /// page's first row, and nothing was put on the page before it. `None`
    /// when the page opens part-way through an element — a split paragraph, a
    /// continued speech — or holds no rows at all, and so cannot be laid out
    /// without the page before it.
    pub start_block: Option<BlockId>,
    /// How many leading blocks of the snapshot the paginator had read when
    /// that element began the page: the element itself and anything its
    /// placement looked ahead to. A change at or beyond this index cannot
    /// have moved an earlier page, or the decision to begin this one.
    /// Meaningful only beside `start_block`.
    pub settled_blocks: usize,
}

/// Cache and fixed-point diagnostics used by tests and debug tooling.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CacheStats {
    pub block_hits: usize,
    pub block_misses: usize,
    pub reused_pages: usize,
    pub reused_tail_pages: usize,
    pub break_rule_iterations: u8,
    pub fell_back_to_naive: bool,
}

/// Complete deterministic output. A title page is intentionally outside
/// `pages`, so `pages[0]` is always screenplay page 1.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaginatedScript {
    pub revision: u64,
    pub title_page: Option<Page>,
    pub pages: Arc<[Page]>,
    pub checkpoints: Vec<PaginationCheckpoint>,
    pub stats: CacheStats,
}

impl PaginatedScript {
    /// Stable text form used by committed golden tests and the Phase 6 debug
    /// dump view. Content uses Rust string escaping so whitespace is visible.
    pub fn debug_dump(&self) -> String {
        use std::fmt::Write;

        let mut out = String::new();
        if let Some(title) = &self.title_page {
            out.push_str("TITLE PAGE\n");
            dump_page_lines(&mut out, title);
        }
        for page in self.pages.iter() {
            let _ = writeln!(out, "PAGE {}", page.number.unwrap_or_default());
            dump_page_lines(&mut out, page);
        }
        out
    }
}

fn dump_page_lines(out: &mut String, page: &Page) {
    use std::fmt::Write;

    for line in page.lines.iter() {
        let _ = writeln!(
            out,
            "  {:>3} -> ({:>3}, {:?})",
            line.row, line.column, line.content
        );
    }
}
