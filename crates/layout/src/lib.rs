//! Line breaking and pagination.
//!
//! Layering rule (§2.5): may depend on `document` only. No I/O, no clock, no
//! locale, no floating point in break decisions — pagination must be
//! bit-identical on every machine.
//!
//! Phase 0 placeholder — the engine in §5 lands in Phase 5.

/// Text lines per page on US Letter with 1" top and bottom margins at 6 lpi (§5.2).
pub const LINES_PER_PAGE_US_LETTER: u32 = 54;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn us_letter_grid_is_fifty_four_lines() {
        assert_eq!(LINES_PER_PAGE_US_LETTER, 54);
    }
}
