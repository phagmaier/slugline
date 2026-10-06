//! The pagination half of the §6 bridge API (ADR 0020).
//!
//! `crates/layout` is the authoritative pagination implementation (§5), and
//! this is the only way anything outside Rust reaches it. Three rules govern
//! the module, and the first two are the reason it exists at all:
//!
//! 1. **Pagination runs off the actor thread, over an owned snapshot.** §2.3
//!    budgets the actor at 2 ms and a full pagination of 120 pages at 50 ms, so
//!    the shape here is [`crate::api::files`]'s save, verbatim: take a
//!    [`ScriptSnapshot`] and the generation on the actor, let go, paginate on
//!    the worker, come back to record what happened.
//! 2. **A result is committed only if it still describes the document it was
//!    computed from.** The document may have been typed into while the worker
//!    ran; that result is a correct pagination of a script that existed a
//!    moment ago and is not one of the script now, so it is handed back
//!    labelled [`PaginationOutcome::Stale`] and nothing is derived from it. A
//!    newer pagination can never be overwritten by an older one, because an
//!    older one never reaches the commit.
//! 3. **Nothing here is a text offset.** [`LayoutLineView`] is a position on the
//!    fixed monospace grid — a row and a column of characters — and
//!    `source_line` is a wrapped-line index within a block, not a place in its
//!    text. There is therefore no `*_utf16` in this file and there must not be
//!    one: §2.4's rule is about offsets into strings, and the only identity that
//!    crosses here is [`LayoutLineView::block`].
//!
//! ## What stops rapid saves paginating repeatedly
//!
//! Two things. A per-session lock, taken before the plan the way a save takes
//! [`crate::state::Session::save_lock`], so a second pagination of one document
//! waits rather than running beside the first with a cold engine. And a
//! committed result keyed by generation and page setup, so the pagination that
//! waited finds the answer already computed and returns it without running.
//! Ten saves of an unedited script therefore cost one pagination.
//!
//! ## What makes it incremental
//!
//! The engine and its per-block wrap cache live in the session (ADR 0022) and
//! are lent to the worker for the length of one run. The changed-block hint the
//! incremental path wants is derived here, by comparing a fingerprint per block
//! against the snapshot the engine last saw. The hint is advisory: a wrong one
//! costs a full pagination and cannot cost correctness.

use std::sync::PoisonError;

use slugline_document::{BlockId, BlockSnapshot};
use slugline_layout as paginator;
use slugline_layout::{LayoutEngine, PageConfig, ScriptSnapshot};

use crate::actor::actor;
use crate::api::doc::DocumentHandle;
use crate::state::Pagination;

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

/// The paper a pagination is measured against (§5.2).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaperSize {
    UsLetter,
    A4,
}

/// Which scene-number gutters the result should carry (§5.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SceneNumbers {
    Off,
    Left,
    Right,
    Both,
}

/// What to paginate for (§6's `PageConfig`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageSetup {
    pub paper: PaperSize,
    pub scene_numbers: SceneNumbers,
    pub bold_scene_headings: bool,
    /// Shrinks the page to this many rows. For tests and the debug surface
    /// only: it makes a page break happen in three blocks instead of fifty, so
    /// a break rule can be looked at without a fifty-page fixture. A real
    /// preview or export leaves it `None`, and the rows come from the paper.
    pub debug_lines_per_page: Option<u32>,
}

/// Why a positioned fragment exists. Mirrors `layout::LayoutLineKind`; the
/// duplication is deliberate, so that the engine's internal vocabulary can
/// change without changing the generated bindings (ADR 0020).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutLineKind {
    Content,
    Blank,
    PageNumber,
    SceneNumberLeft,
    SceneNumberRight,
    /// The `(MORE)` under a speech that a page break interrupted.
    More,
    /// The `CHARACTER (CONT'D)` that resumes it overleaf.
    Continued,
    Title,
}

/// A resolved printable run, shared with the PDF's emphasis interpretation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmphasisRunView {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
}

/// One printable fragment, placed on the grid.
///
/// `row` is relative to the top of the text area and `column` to its left edge.
/// Both may be negative: the page number sits above the text area and the scene
/// number gutters outside it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LayoutLineView {
    pub row: i32,
    pub column: i32,
    /// Raw text, already uppercased and wrapped, retained for source identity.
    pub content: String,
    /// Printable text and final output styles; no Fountain rescan is needed.
    pub runs: Vec<EmphasisRunView>,
    /// The block this came from, or `None` for generated furniture — a page
    /// number, a blank, a `(MORE)`. This is the identity a preview maps a click
    /// back to the editor with, and it is the same `BlockId` [`crate::api::doc`]
    /// speaks.
    pub block: Option<u64>,
    /// Which wrapped line of `block` this is, counting from zero. Absent
    /// wherever `block` is, and on furniture that belongs to a block without
    /// being any of its lines.
    pub source_line: Option<u32>,
    pub kind: LayoutLineKind,
}

/// One page. The title page has no number and is not in [`PaginationView::pages`],
/// so `pages[0]` is always screenplay page 1.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageView {
    pub number: Option<u32>,
    pub lines: Vec<LayoutLineView>,
}

/// Cache and fixed-point diagnostics (ADR 0022).
///
/// Not decoration: this is how a test proves a run was *incremental* rather
/// than merely correct, which is a claim no assertion about the pages can make.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaginationStats {
    pub block_hits: u32,
    pub block_misses: u32,
    /// Pages before the change that were kept, having been proved equal.
    pub reused_pages: u32,
    /// Pages after it that were.
    pub reused_tail_pages: u32,
    pub break_rule_iterations: u32,
    /// The break-rule loop did not converge inside its cap and the naive fill
    /// was used. Always false in practice; §5.4 requires it to be reportable.
    pub fell_back_to_naive: bool,
    /// The block the engine was told had changed, if it was told anything. A
    /// full pagination was asked for when this is `None`.
    pub hinted_block: Option<u64>,
}

/// A complete pagination (§6's `PaginatedScript`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaginationView {
    /// The document revision this describes. Moves backwards on undo, which is
    /// why it is not what staleness is judged by — see `generation`.
    pub revision: u64,
    /// The monotonic document generation this describes. Two paginations of one
    /// handle with the same generation describe the same text.
    pub generation: u64,
    pub page_count: u32,
    pub title_page: Option<PageView>,
    pub pages: Vec<PageView>,
    pub stats: PaginationStats,
}

/// What a pagination request answered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PaginationOutcome {
    /// The pagination describes the document as it stands.
    Current { pagination: PaginationView },
    /// The document was edited while this was being computed. It is a correct
    /// pagination of the text that was there when it started, and it is handed
    /// back rather than swallowed — a debug view still wants to see it, and a
    /// caller that silently got nothing would be worse. Nothing durable may be
    /// derived from it: the library's page count, in particular, keeps its
    /// previous value rather than taking this one (ADR 0020).
    Stale { pagination: PaginationView },
    /// The handle names no open document.
    NoSuchDocument,
}

// ---------------------------------------------------------------------------
// The §6 surface
// ---------------------------------------------------------------------------

/// §6's `paginate`. Lays the document out on the page grid.
///
/// Async because it is the long job §2.3 has in mind: 50 ms for 120 pages
/// against the actor's 2 ms budget. Everything expensive happens between the
/// two actor visits, on the FRB worker thread this runs on.
pub async fn doc_paginate(handle: DocumentHandle, setup: PageSetup) -> PaginationOutcome {
    let Some((pagination, current)) = paginate(handle.id, &page_config(&setup)) else {
        return PaginationOutcome::NoSuchDocument;
    };
    let view = pagination_view(&pagination);
    if current {
        PaginationOutcome::Current { pagination: view }
    } else {
        PaginationOutcome::Stale { pagination: view }
    }
}

// ---------------------------------------------------------------------------
// The job
// ---------------------------------------------------------------------------

/// Paginates `handle`, and says whether the result still describes it.
///
/// The Rust-facing half of [`doc_paginate`], so that a caller inside the core —
/// the page count a save writes (ADR 0020) is the one that is coming — can have
/// the result without paying to convert every line of it into a view first.
///
/// `None` means there is no such document, either because the handle was never
/// open or because it was closed while the pagination ran.
pub(crate) fn paginate(handle: u64, config: &PageConfig) -> Option<(Pagination, bool)> {
    // Step zero, off the actor thread: wait for any pagination of this document
    // already in flight. The engine is lent to one worker at a time, and the
    // waiter is very often about to find the answer already computed.
    let lock = actor().run(move |state| state.session(handle).map(|s| s.pagination().lock()))?;
    // A poisoned lock means an earlier pagination panicked. It guards ordering,
    // not data — every field it protects was replaced or left untouched — so
    // refusing to paginate ever again would be the wrong answer.
    let _running = lock.lock().unwrap_or_else(PoisonError::into_inner);

    // Step one, on the actor thread: the snapshot and the engine, or the answer.
    let planned = actor().run({
        let config = config.clone();
        move |state| {
            let session = state.session_mut(handle)?;
            let generation = session.document_generation();
            if let Some(done) = session.pagination().ready(generation, &config) {
                return Some(Planned::Done(done.clone()));
            }
            let snapshot = ScriptSnapshot::from_document(session.document());
            let (engine, fingerprints) = session.pagination_mut().lend();
            Some(Planned::Run(Job {
                generation,
                snapshot,
                engine,
                fingerprints,
            }))
        }
    })?;
    let Job {
        generation,
        snapshot,
        mut engine,
        fingerprints: previous,
    } = match planned {
        Planned::Done(pagination) => return Some((pagination, true)),
        Planned::Run(job) => job,
    };

    // Step two, off the actor thread: the pagination itself (§2.3).
    let fingerprints = fingerprints(&snapshot);
    let hinted_block = changed_block(&previous, &fingerprints);
    let script = match hinted_block {
        Some(block) => engine.repaginate(&snapshot, config, block),
        None => engine.paginate_snapshot(&snapshot, config),
    };

    #[cfg(test)]
    stall::reached(handle);

    // Step three, back on the actor thread: record it, if it is still about this
    // document. The engine goes back either way — its checkpoints describe the
    // snapshot it saw, which is exactly what it validates the next one against.
    let pagination = Pagination {
        generation,
        config: config.clone(),
        script,
        hinted_block,
    };
    actor().run(move |state| {
        let session = state.session_mut(handle)?;
        session.pagination_mut().returned(engine, fingerprints);
        let current = session.document_generation() == pagination.generation;
        if current {
            session.pagination_mut().commit(pagination.clone());
        }
        Some((pagination, current))
    })
}

/// Paginates an already-owned snapshot taken by a successful save.
///
/// Unlike [`paginate`], the snapshot is intentionally allowed to be older than
/// the live document: it describes the bytes that reached disk. The caller
/// separately guards the library write so an older save cannot replace a newer
/// count. The per-session engine is still lent and returned when the document
/// remains open, preserving ADR 0022's incremental cache.
pub(crate) fn paginate_snapshot(
    handle: u64,
    generation: u64,
    snapshot: ScriptSnapshot,
    config: &PageConfig,
) -> Pagination {
    let lock = actor().run(move |state| state.session(handle).map(|s| s.pagination().lock()));
    let _running = lock
        .as_ref()
        .map(|lock| lock.lock().unwrap_or_else(PoisonError::into_inner));

    let planned_snapshot = snapshot.clone();
    let planned = actor().run({
        let config = config.clone();
        move |state| {
            let session = state.session_mut(handle)?;
            if let Some(done) = session.pagination().ready(generation, &config) {
                return Some(Planned::Done(done.clone()));
            }
            let (engine, fingerprints) = session.pagination_mut().lend();
            Some(Planned::Run(Job {
                generation,
                snapshot: planned_snapshot,
                engine,
                fingerprints,
            }))
        }
    });

    let Job {
        generation,
        snapshot,
        mut engine,
        fingerprints: previous,
    } = match planned {
        Some(Planned::Done(pagination)) => return pagination,
        Some(Planned::Run(job)) => job,
        None => Job {
            generation,
            snapshot,
            engine: LayoutEngine::default(),
            fingerprints: Vec::new(),
        },
    };

    let fingerprints = fingerprints(&snapshot);
    let hinted_block = changed_block(&previous, &fingerprints);
    let script = match hinted_block {
        Some(block) => engine.repaginate(&snapshot, config, block),
        None => engine.paginate_snapshot(&snapshot, config),
    };

    #[cfg(test)]
    stall::reached(handle);

    let pagination = Pagination {
        generation,
        config: config.clone(),
        script,
        hinted_block,
    };
    actor().run({
        let pagination = pagination.clone();
        move |state| {
            if let Some(session) = state.session_mut(handle) {
                session.pagination_mut().returned(engine, fingerprints);
                if session.document_generation() == pagination.generation {
                    session.pagination_mut().commit(pagination);
                }
            }
        }
    });
    pagination
}

enum Planned {
    /// Already paginated at this generation and setup. Nothing to run.
    Done(Pagination),
    Run(Job),
}

/// What one pagination needs, owned, so the actor can be let go of.
struct Job {
    generation: u64,
    snapshot: ScriptSnapshot,
    engine: LayoutEngine,
    /// The snapshot the engine last paginated, one fingerprint per block.
    fingerprints: Vec<(BlockId, u64)>,
}

// ---------------------------------------------------------------------------
// The changed-block hint
// ---------------------------------------------------------------------------

/// A fingerprint per block, in document order.
fn fingerprints(snapshot: &ScriptSnapshot) -> Vec<(BlockId, u64)> {
    snapshot
        .blocks
        .iter()
        .map(|block| (block.id, fingerprint(block)))
        .collect()
}

/// Everything about a block that can move a line, as one number.
///
/// `DefaultHasher` rather than the engine's FNV-1a, and for the opposite
/// reason: the engine's fingerprints key a cache that must behave identically
/// on every toolchain (ADR 0022), and these never leave the process that
/// computed them — they are compared only against others made moments earlier
/// by the same binary. A collision costs a full pagination instead of an
/// incremental one, and cannot cost a wrong page.
fn fingerprint(block: &BlockSnapshot) -> u64 {
    use std::hash::{Hash, Hasher};

    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    block.kind.hash(&mut hasher);
    block.text.hash(&mut hasher);
    block.forced.hash(&mut hasher);
    block.dual.hash(&mut hasher);
    hasher.finish()
}

/// The one block that changed, if exactly one did.
///
/// This mirrors the condition the engine itself checks before reusing a
/// checkpoint: it reuses one only when the block order is unchanged and exactly
/// the hinted block missed its cache (ADR 0022). Answering `None` for anything
/// else — a first pagination, an insertion, a deletion, two blocks edited at
/// once — asks for the full path the engine would have fallen back to anyway,
/// and asks for it without the engine having to prepare the incremental one
/// first.
fn changed_block(previous: &[(BlockId, u64)], current: &[(BlockId, u64)]) -> Option<BlockId> {
    if previous.len() != current.len() {
        return None;
    }
    let mut differing = previous.iter().zip(current).filter(|(was, now)| was != now);
    let (_, changed) = differing.next()?;
    differing.next().is_none().then_some(changed.0)
}

// ---------------------------------------------------------------------------
// Conversion
// ---------------------------------------------------------------------------

pub(crate) fn page_config(setup: &PageSetup) -> PageConfig {
    let config = match setup.paper {
        PaperSize::UsLetter => PageConfig::us_letter(),
        PaperSize::A4 => PageConfig::a4(),
    }
    .with_scene_numbers(match setup.scene_numbers {
        SceneNumbers::Off => paginator::SceneNumberGutters::None,
        SceneNumbers::Left => paginator::SceneNumberGutters::Left,
        SceneNumbers::Right => paginator::SceneNumberGutters::Right,
        SceneNumbers::Both => paginator::SceneNumberGutters::Both,
    })
    .with_bold_scene_headings(setup.bold_scene_headings);
    match setup.debug_lines_per_page {
        Some(lines) => config.with_line_capacity(lines.min(u16::MAX as u32) as u16),
        None => config,
    }
}

fn pagination_view(pagination: &Pagination) -> PaginationView {
    let script = &pagination.script;
    let mut runs = slugline_render_pdf::emphasis_runs(script, &pagination.config).into_iter();
    let title_page = script
        .title_page
        .as_ref()
        .map(|page| page_view(page, runs.next().expect("title-page runs")));
    let pages = script
        .pages
        .iter()
        .zip(runs)
        .map(|(page, rows)| page_view(page, rows))
        .collect();
    PaginationView {
        revision: script.revision,
        generation: pagination.generation,
        page_count: clamp_u32(script.pages.len()),
        title_page,
        pages,
        stats: PaginationStats {
            block_hits: clamp_u32(script.stats.block_hits),
            block_misses: clamp_u32(script.stats.block_misses),
            reused_pages: clamp_u32(script.stats.reused_pages),
            reused_tail_pages: clamp_u32(script.stats.reused_tail_pages),
            break_rule_iterations: u32::from(script.stats.break_rule_iterations),
            fell_back_to_naive: script.stats.fell_back_to_naive,
            hinted_block: pagination.hinted_block.map(|block| block.0),
        },
    }
}

fn page_view(
    page: &paginator::Page,
    runs: Vec<Vec<slugline_fountain::emphasis::EmphasisRun>>,
) -> PageView {
    PageView {
        number: page.number,
        lines: page
            .lines
            .iter()
            .zip(runs)
            .map(|(line, runs)| line_view(line, runs))
            .collect(),
    }
}

fn line_view(
    line: &paginator::LayoutLine,
    runs: Vec<slugline_fountain::emphasis::EmphasisRun>,
) -> LayoutLineView {
    LayoutLineView {
        row: i32::from(line.row),
        column: i32::from(line.column),
        content: line.content.clone(),
        runs: runs
            .into_iter()
            .map(|run| EmphasisRunView {
                text: run.text,
                bold: run.emphasis.bold,
                italic: run.emphasis.italic,
                underline: run.emphasis.underline,
            })
            .collect(),
        block: line.block.map(|block| block.0),
        source_line: line.source_line.map(u32::from),
        kind: match line.kind {
            paginator::LayoutLineKind::Content => LayoutLineKind::Content,
            paginator::LayoutLineKind::Blank => LayoutLineKind::Blank,
            paginator::LayoutLineKind::PageNumber => LayoutLineKind::PageNumber,
            paginator::LayoutLineKind::SceneNumberLeft => LayoutLineKind::SceneNumberLeft,
            paginator::LayoutLineKind::SceneNumberRight => LayoutLineKind::SceneNumberRight,
            paginator::LayoutLineKind::More => LayoutLineKind::More,
            paginator::LayoutLineKind::Continued => LayoutLineKind::Continued,
            paginator::LayoutLineKind::Title => LayoutLineKind::Title,
        },
    }
}

fn clamp_u32(value: usize) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

/// A seam for the staleness tests, and nothing else.
///
/// [`paginate`] spans two threads, and the property ADR 0020 turns on — that a
/// result about a document that has moved on is never committed — is only
/// observable if the worker can be held between computing the pages and
/// recording them. This is that hold, keyed by handle so tests running side by
/// side cannot stall each other. The same shape as `api::files::stall`, and
/// like it, `#[cfg(test)]` throughout: the shipped library has neither the map
/// nor the call site.
#[cfg(test)]
pub(crate) mod stall {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, PoisonError};

    type Hold = Arc<dyn Fn() + Send + Sync>;

    static HOLDS: Mutex<Option<HashMap<u64, Hold>>> = Mutex::new(None);

    fn holds() -> impl std::ops::DerefMut<Target = Option<HashMap<u64, Hold>>> {
        HOLDS.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Runs `hold` on the paginating thread, after the pages exist and before
    /// anything is recorded.
    pub fn before_recording(handle: u64, hold: impl Fn() + Send + Sync + 'static) {
        holds()
            .get_or_insert_with(HashMap::new)
            .insert(handle, Arc::new(hold));
    }

    pub fn forget(handle: u64) {
        if let Some(holds) = holds().as_mut() {
            holds.remove(&handle);
        }
    }

    pub fn reached(handle: u64) {
        // Cloned out and the map unlocked before the hold runs: a hold blocks,
        // and blocking with the map locked would stall every other test too.
        let hold = holds()
            .as_ref()
            .and_then(|holds| holds.get(&handle))
            .map(Arc::clone);
        if let Some(hold) = hold {
            hold();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::future::Future;
    use std::sync::{Arc, Mutex};
    use std::task::{Context, Poll, Waker};
    use std::thread::ThreadId;

    use crate::api::doc::{doc_apply, doc_blocks, doc_close, doc_new, doc_parse, EditOutcome};

    const SCRIPT: &str = "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\n(quietly)\nHello.\n";

    /// `doc_paginate` has no `.await` in it — it visits the actor, which blocks,
    /// and paginates in between — so a single poll drives it to completion. The
    /// panic is what would notice if that ever stopped being true.
    fn block_on<F: Future>(future: F) -> F::Output {
        let mut future = Box::pin(future);
        match future
            .as_mut()
            .poll(&mut Context::from_waker(Waker::noop()))
        {
            Poll::Ready(value) => value,
            Poll::Pending => panic!("a bridge future yielded, and this crate has no runtime"),
        }
    }

    /// A document that closes itself, so a panicking assertion does not leave a
    /// session behind for the next test to trip over.
    struct Doc(DocumentHandle);

    impl Doc {
        fn parse(source: &str) -> Doc {
            Doc(doc_parse(source.to_owned()))
        }

        fn blank() -> Doc {
            Doc(doc_new())
        }

        fn handle(&self) -> DocumentHandle {
            self.0
        }

        fn id(&self, index: usize) -> u64 {
            doc_blocks(self.0, 0, u32::MAX)[index].id
        }

        /// Types one letter at the front of a block, the way a keystroke does.
        fn type_into(&self, block: u64) {
            let outcome = doc_apply(
                self.0,
                crate::api::doc::EditCommand::ReplaceText {
                    block,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "X".to_owned(),
                },
                None,
            );
            assert!(
                matches!(outcome, EditOutcome::Applied { .. }),
                "the edit applies"
            );
        }

        fn paginate(&self) -> PaginationOutcome {
            block_on(doc_paginate(self.0, letter()))
        }

        fn current(&self) -> PaginationView {
            match self.paginate() {
                PaginationOutcome::Current { pagination } => pagination,
                other => panic!("expected a current pagination, got {other:?}"),
            }
        }

        /// How many paginations have actually run for this document.
        fn runs(&self) -> u64 {
            let handle = self.0.id;
            actor()
                .run(move |state| state.session(handle).map(|s| s.pagination().runs()))
                .expect("the document is open")
        }

        fn generation(&self) -> u64 {
            let handle = self.0.id;
            actor()
                .run(move |state| state.session(handle).map(|s| s.document_generation()))
                .expect("the document is open")
        }

        /// Whether a pagination of `generation` is committed for this document.
        fn committed_at(&self, generation: u64) -> bool {
            let handle = self.0.id;
            let config = page_config(&letter());
            actor().run(move |state| {
                state
                    .session(handle)
                    .is_some_and(|s| s.pagination().ready(generation, &config).is_some())
            })
        }
    }

    impl Drop for Doc {
        fn drop(&mut self) {
            stall::forget(self.0.id);
            doc_close(self.0);
        }
    }

    fn letter() -> PageSetup {
        PageSetup {
            paper: PaperSize::UsLetter,
            scene_numbers: SceneNumbers::Off,
            bold_scene_headings: false,
            debug_lines_per_page: None,
        }
    }

    #[test]
    fn preview_runs_use_the_explicit_cached_setup_and_preserve_raw_geometry() {
        let doc = Doc::parse("Title: Cover\n\nINT. *ROOM* - DAY #12#\n\nHe reads **loudly**.\n");
        let preview = |bold_scene_headings| match block_on(doc_paginate(
            doc.handle(),
            PageSetup {
                scene_numbers: SceneNumbers::Both,
                bold_scene_headings,
                ..letter()
            },
        )) {
            PaginationOutcome::Current { pagination } => pagination,
            other => panic!("expected current preview, got {other:?}"),
        };
        let regular = preview(false);
        let weighted = preview(true);
        assert_eq!(regular.page_count, weighted.page_count);
        let lines = |view: &PaginationView| {
            view.title_page
                .iter()
                .chain(view.pages.iter())
                .flat_map(|page| page.lines.iter())
                .map(|line| {
                    (
                        line.row,
                        line.column,
                        line.content.clone(),
                        line.block,
                        line.source_line,
                        line.kind,
                    )
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(lines(&regular), lines(&weighted));
        for (bold, view) in [(false, &regular), (true, &weighted)] {
            let heading = view.pages[0]
                .lines
                .iter()
                .find(|line| line.content == "INT. *ROOM* - DAY")
                .expect("raw heading retains its markers");
            assert_eq!(
                heading.runs,
                vec![
                    EmphasisRunView {
                        text: "INT. ".to_owned(),
                        bold,
                        italic: false,
                        underline: false,
                    },
                    EmphasisRunView {
                        text: "ROOM".to_owned(),
                        bold,
                        italic: true,
                        underline: false,
                    },
                    EmphasisRunView {
                        text: " - DAY".to_owned(),
                        bold,
                        italic: false,
                        underline: false,
                    },
                ]
            );
            for line in view
                .title_page
                .iter()
                .chain(view.pages.iter())
                .flat_map(|page| page.lines.iter())
            {
                if line.content.is_empty() {
                    assert!(line.runs.is_empty());
                } else {
                    assert!(!line.runs.is_empty());
                }
                if line.kind != LayoutLineKind::Content {
                    assert!(line.runs.iter().all(|run| !run.bold));
                }
            }
            assert!(view.pages[0]
                .lines
                .iter()
                .flat_map(|line| &line.runs)
                .any(|run| run.text == "loudly" && run.bold && !run.italic));
        }
        assert_eq!(
            doc.runs(),
            2,
            "each output setup gets its own cached result"
        );
        let again = preview(false);
        assert_eq!(lines(&again), lines(&regular));
        assert_eq!(again.pages[0].lines, regular.pages[0].lines);
    }

    /// Enough action for pages to accumulate and checkpoints to be taken every
    /// fourth one.
    fn long_script(blocks: usize) -> String {
        (0..blocks)
            .map(|index| format!("John crosses the room for the {index}th time.\n\n"))
            .collect()
    }

    // -----------------------------------------------------------------------
    // The documents §Phase 6D names: normal, empty, long, tolerated-malformed
    // -----------------------------------------------------------------------

    #[test]
    fn a_script_paginates_onto_numbered_pages_that_name_their_blocks() {
        let doc = Doc::parse(SCRIPT);
        let pagination = doc.current();

        assert_eq!(pagination.page_count, 1);
        assert_eq!(pagination.pages[0].number, Some(1));
        assert!(
            pagination.title_page.is_none(),
            "this script has no title page"
        );

        // Every content fragment names the block it came from, and the ids are
        // the ones `api::doc` speaks — that is the identity a preview maps a
        // click back to the editor with.
        let blocks: Vec<u64> = doc_blocks(doc.handle(), 0, u32::MAX)
            .into_iter()
            .map(|block| block.id)
            .collect();
        let placed: Vec<u64> = pagination.pages[0]
            .lines
            .iter()
            .filter(|line| line.kind == LayoutLineKind::Content)
            .filter_map(|line| line.block)
            .collect();
        assert!(!placed.is_empty(), "something was placed");
        assert!(
            placed.iter().all(|id| blocks.contains(id)),
            "every placed line names a block of this document"
        );
        assert!(
            pagination.pages[0]
                .lines
                .iter()
                .any(|line| line.content.contains("INT. HOUSE - DAY")),
            "the scene heading is on the page"
        );
    }

    #[test]
    fn an_empty_document_paginates_to_one_empty_page() {
        let doc = Doc::blank();
        let pagination = doc.current();

        assert_eq!(pagination.page_count, 1);
        assert_eq!(pagination.pages[0].number, Some(1));
        assert!(
            pagination.pages[0]
                .lines
                .iter()
                .filter(|line| line.kind == LayoutLineKind::Content)
                .all(|line| line.content.is_empty()),
            "nothing was typed, so the page holds its number and one empty line"
        );
    }

    #[test]
    fn a_long_script_paginates_onto_pages_numbered_in_order() {
        let doc = Doc::parse(&long_script(400));
        let pagination = doc.current();

        assert!(
            pagination.page_count > 4,
            "400 blocks fill more than four pages, not {}",
            pagination.page_count
        );
        let numbers: Vec<Option<u32>> = pagination.pages.iter().map(|page| page.number).collect();
        let expected: Vec<Option<u32>> = (1..=pagination.page_count).map(Some).collect();
        assert_eq!(numbers, expected, "pages are numbered 1..n, in order");
        assert!(
            !pagination.stats.fell_back_to_naive,
            "the break rules converged"
        );
    }

    #[test]
    fn text_the_editor_does_not_model_paginates_rather_than_failing() {
        // A boneyard, an unclosed emphasis run, a lone forcing character, a tab,
        // and an astral-plane glyph: everything the parser is required to
        // tolerate rather than reject (§3.2). None of it may stop a pagination.
        let doc = Doc::parse(
            "/* a note the editor keeps verbatim */\n\n\
             INT. HOUSE - DAY\n\n\
             *unclosed emphasis and\ta tab and 🎬\n\n\
             !\n\n\
             JOHN\nHello.\n",
        );
        let pagination = doc.current();

        assert!(pagination.page_count >= 1);
        assert!(
            pagination
                .pages
                .iter()
                .any(|page| page.lines.iter().any(|line| line.content.contains('🎬'))),
            "the astral-plane glyph survived onto the page"
        );
    }

    #[test]
    fn a_title_page_is_a_page_of_its_own_rather_than_page_one() {
        let doc = Doc::parse("Title: Heat\nCredit: Written by\nAuthor: Michael Mann\n\nINT. HOUSE - DAY\n\nJohn enters.\n");
        let pagination = doc.current();

        let title = pagination.title_page.expect("there is a title page");
        assert_eq!(title.number, None, "the title page is not numbered");
        assert!(title.lines.iter().any(|line| line.content.contains("Heat")));
        assert_eq!(
            pagination.pages[0].number,
            Some(1),
            "the first screenplay page is still page 1"
        );
    }

    // -----------------------------------------------------------------------
    // The job: off the actor, bounded, incremental, and guarded by revision
    // -----------------------------------------------------------------------

    #[test]
    fn pagination_does_not_run_on_the_actor_thread() {
        let doc = Doc::parse(&long_script(200));
        let actor_thread = actor().run(|_| std::thread::current().id());
        let paginating: Arc<Mutex<Option<ThreadId>>> = Arc::new(Mutex::new(None));

        stall::before_recording(doc.handle().id, {
            let paginating = Arc::clone(&paginating);
            move || {
                *paginating.lock().expect("the mutex holds") = Some(std::thread::current().id());
            }
        });
        doc.current();

        let paginating = paginating
            .lock()
            .expect("the mutex holds")
            .expect("the hold ran");
        assert_ne!(
            paginating, actor_thread,
            "§2.3: the pagination happens between the two actor visits, not inside one"
        );
    }

    #[test]
    fn paginating_an_unchanged_document_again_does_not_run_it_again() {
        let doc = Doc::parse(&long_script(100));
        let first = doc.current();
        assert_eq!(doc.runs(), 1);

        // Ten saves of an unedited script cost one pagination (ADR 0020).
        for _ in 0..10 {
            let again = doc.current();
            assert_eq!(again, first, "the same answer, not a recomputed one");
        }
        assert_eq!(doc.runs(), 1, "nothing ran again");
    }

    #[test]
    fn a_different_page_setup_is_a_different_answer() {
        let doc = Doc::parse(&long_script(100));
        let us_letter = doc.current();
        let a4 = match block_on(doc_paginate(
            doc.handle(),
            PageSetup {
                paper: PaperSize::A4,
                ..letter()
            },
        )) {
            PaginationOutcome::Current { pagination } => pagination,
            other => panic!("expected a current pagination, got {other:?}"),
        };

        assert_eq!(
            doc.runs(),
            2,
            "a committed US Letter pagination is not an A4 one"
        );
        assert_ne!(us_letter.pages, a4.pages, "A4 is a taller page (§5.2)");
    }

    #[test]
    fn an_edit_makes_the_next_pagination_reuse_a_checkpoint_prefix() {
        let doc = Doc::parse(&long_script(400));
        let first = doc.current();
        assert_eq!(
            first.stats.hinted_block, None,
            "the first pagination is a full one"
        );
        assert_eq!(first.stats.reused_pages, 0);

        // One block, late in the script, so there are checkpointed pages before
        // it to reuse — the incremental path of ADR 0022, running in the
        // application rather than in the layout crate's own tests.
        let edited = doc.id(380);
        doc.type_into(edited);
        let second = doc.current();

        assert_eq!(doc.runs(), 2);
        assert_eq!(
            second.stats.hinted_block,
            Some(edited),
            "the changed block is derived from the snapshot, not guessed"
        );
        assert_eq!(
            second.stats.block_misses, 1,
            "exactly one block was re-wrapped"
        );
        assert!(
            second.stats.reused_pages > 0,
            "a checkpointed prefix was kept, not repaginated"
        );
        assert_eq!(
            second.pages[..second.stats.reused_pages as usize],
            first.pages[..second.stats.reused_pages as usize],
            "the reused pages are the pages that were there before"
        );
    }

    #[test]
    fn an_insertion_paginates_fully_rather_than_hinting_at_the_wrong_block() {
        let doc = Doc::parse(&long_script(200));
        doc.current();

        // Splitting a block changes the block order, which no checkpoint
        // survives. The hint is withheld rather than being wrong.
        let split = doc.id(100);
        let outcome = doc_apply(
            doc.handle(),
            crate::api::doc::EditCommand::SplitBlock {
                block: split,
                at_utf16: 4,
            },
            None,
        );
        assert!(matches!(outcome, EditOutcome::Applied { .. }));

        let second = doc.current();
        assert_eq!(second.stats.hinted_block, None);
        assert_eq!(second.stats.reused_pages, 0);
    }

    #[test]
    fn a_result_about_a_document_that_moved_on_is_stale_and_is_not_committed() {
        let doc = Doc::parse(&long_script(50));
        let handle = doc.handle();
        let typed = doc.id(3);
        let before = doc.generation();

        // The edit lands after the pages exist and before anything is recorded:
        // the one window in which a result can be about a document that no
        // longer is.
        stall::before_recording(handle.id, move || {
            let outcome = doc_apply(
                handle,
                crate::api::doc::EditCommand::ReplaceText {
                    block: typed,
                    start_utf16: 0,
                    end_utf16: 0,
                    with: "X".to_owned(),
                },
                None,
            );
            assert!(matches!(outcome, EditOutcome::Applied { .. }));
        });

        let outcome = doc.paginate();
        stall::forget(handle.id);

        let PaginationOutcome::Stale { pagination } = outcome else {
            panic!("expected a stale pagination, got {outcome:?}");
        };
        assert_eq!(
            pagination.generation, before,
            "it describes the older document"
        );
        assert!(pagination.page_count >= 1, "it is still a real pagination");
        assert!(
            !doc.committed_at(before),
            "a stale result is dropped, never committed"
        );
        assert!(
            !doc.committed_at(doc.generation()),
            "and it is certainly not committed as the current one"
        );

        // The engine came back all the same, so the next pagination is not cold.
        let after = doc.current();
        assert_eq!(after.generation, doc.generation());
        assert!(doc.committed_at(doc.generation()));
    }

    #[test]
    fn a_closed_document_has_no_pagination() {
        let handle = doc_parse(SCRIPT.to_owned());
        doc_close(handle);
        assert_eq!(
            block_on(doc_paginate(handle, letter())),
            PaginationOutcome::NoSuchDocument
        );
    }

    /// The editor status bar and the PDF export path must agree on page count,
    /// because both derive it from `PaginatedScript.pages.len()`. The test
    /// paginates the same fixture through `doc_paginate` (the editor's §6
    /// endpoint) and through `layout::paginate` (what `doc_export_pdf` calls
    /// internally), asserting the two counts are identical and also match the
    /// length of `PaginationView.pages` — the list the preview and PDF renderer
    /// actually iterate.
    #[test]
    fn editor_and_export_page_counts_agree() {
        let doc = Doc::parse(&long_script(100));
        let config = page_config(&letter());

        let editor = doc.current();
        let editor_count = editor.page_count;

        let (pagination, current) =
            paginate(doc.handle().id, &config).expect("the document is open");
        assert!(current, "the export pagination is current");

        let export_count = pagination.script.pages.len() as u32;

        assert_eq!(
            editor_count, export_count,
            "the editor status bar and the PDF export agree on page count"
        );
        assert_eq!(
            editor_count,
            editor.pages.len() as u32,
            "page_count matches pages.len() in PaginationView"
        );
    }
}
