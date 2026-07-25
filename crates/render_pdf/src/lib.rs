//! PDF rendering.
//!
//! Layering rule (§2.5): may depend on `layout` only. It consumes a
//! `PaginatedScript` and writes bytes; it never re-derives layout.
//!
//! Phase 0 placeholder — the writer lands in Phase 7.

/// Point size of the screenplay body font (§5.1).
pub const BODY_FONT_POINTS: u32 = 12;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn body_font_is_twelve_point() {
        assert_eq!(BODY_FONT_POINTS, 12);
    }
}
