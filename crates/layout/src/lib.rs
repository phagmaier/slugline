//! Deterministic line breaking and pagination on the screenplay grid.
//!
//! Layering rule (§2.5): this crate depends on `document` only. Pagination has
//! no I/O, clock, locale, or floating-point break decisions. [`ScriptSnapshot`]
//! is the owned value a worker thread receives after briefly visiting the
//! document actor.

mod engine;
mod line_break;
pub mod metrics;
mod model;

pub use engine::{paginate, LayoutEngine};
pub use line_break::break_lines;
pub use model::{
    CacheStats, LayoutLine, LayoutLineKind, Page, PageConfig, PageSize, PaginatedScript,
    PaginationCheckpoint, SceneNumberGutters, ScriptSnapshot,
};

/// Compatibility name retained for callers of the Phase 0 placeholder.
pub const LINES_PER_PAGE_US_LETTER: u16 = metrics::US_LETTER_LINES_PER_PAGE;
