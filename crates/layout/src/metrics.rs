//! The fixed screenplay grid from SPEC §5.2.
//!
//! Columns are relative to the 1.5-inch left edge of the text area. Physical
//! dimensions use micrometres so deriving a page's line count remains exact and
//! integer-only.
//!
//! §5.2 calls these "starting points, not gospel" and asks for them to be
//! calibrated against reference PDFs before Phase 7 exits. That was done, and
//! **nothing here changed**: the table is Final Draft's defaults, the two
//! open-source tools it was overlaid against disagree with each other by more
//! than either disagrees with this, and ADR 0034 has the measurements. The
//! indents are pinned out of a finished PDF by
//! `crates/render_pdf/tests/element_indents.rs`.

/// SPEC §5.2: fixed Courier grid at 10 characters per inch.
pub const CHARACTERS_PER_INCH: u16 = 10;
/// SPEC §5.2: fixed Courier grid at 6 lines per inch.
pub const LINES_PER_INCH: u16 = 6;
/// Exact conversion used to derive paper grids without floating point.
pub const MICROMETRES_PER_INCH: u32 = 25_400;

/// SPEC §5.2: US Letter is 8.5 inches wide.
pub const US_LETTER_WIDTH_UM: u32 = 215_900;
/// SPEC §5.2: US Letter is 11 inches high.
pub const US_LETTER_HEIGHT_UM: u32 = 279_400;
/// ISO 216: A4 is 210 mm wide.
pub const A4_WIDTH_UM: u32 = 210_000;
/// ISO 216: A4 is 297 mm high.
pub const A4_HEIGHT_UM: u32 = 297_000;

/// SPEC §5.2: one-inch top margin.
pub const TOP_MARGIN_UM: u32 = MICROMETRES_PER_INCH;
/// SPEC §5.2: one-inch bottom margin.
pub const BOTTOM_MARGIN_UM: u32 = MICROMETRES_PER_INCH;
/// SPEC §5.2: the text area begins 1.5 inches from page left.
pub const TEXT_LEFT_COLUMN_FROM_PAGE: u16 = 15;
/// SPEC §5.2: the text area's right edge is 7.5 inches from page left.
pub const TEXT_RIGHT_COLUMN_FROM_PAGE: u16 = 75;
/// SPEC §5.2: page numbers sit 0.5 inch above the text origin.
pub const PAGE_NUMBER_ROW: i16 = -3;
/// SPEC §5.2: page-number right edge is the text area's right edge.
pub const PAGE_NUMBER_RIGHT_COLUMN: i16 = 60;

/// SPEC §5.2: scene headings begin at the text area's left edge.
pub const SCENE_HEADING_INDENT: i16 = 0;
/// SPEC §5.2: scene headings are 60 characters wide.
pub const SCENE_HEADING_WIDTH: u16 = 60;
/// Scene headings have one blank line before them.
pub const SCENE_HEADING_BLANKS_BEFORE: u16 = 1;
/// A scene heading at page top needs no extra blank line.
pub const SCENE_HEADING_BLANKS_AT_PAGE_TOP: u16 = 0;

/// SPEC §5.2: action begins at the text area's left edge.
pub const ACTION_INDENT: i16 = 0;
/// SPEC §5.2: action is 60 characters wide.
pub const ACTION_WIDTH: u16 = 60;
/// SPEC §5.2: action has one blank line before it.
pub const ACTION_BLANKS_BEFORE: u16 = 1;

/// SPEC §5.2: character cues begin 2.2 inches into the text area.
pub const CHARACTER_INDENT: i16 = 22;
/// SPEC §5.2: character cues are 33 characters wide.
pub const CHARACTER_WIDTH: u16 = 33;
/// SPEC §5.2: character cues have one blank line before them.
pub const CHARACTER_BLANKS_BEFORE: u16 = 1;

/// SPEC §5.2: parentheticals begin 1.6 inches into the text area.
pub const PARENTHETICAL_INDENT: i16 = 16;
/// SPEC §5.2: parentheticals are 20 characters wide.
pub const PARENTHETICAL_WIDTH: u16 = 20;
/// SPEC §5.2: parentheticals follow without a blank line.
pub const PARENTHETICAL_BLANKS_BEFORE: u16 = 0;

/// SPEC §5.2: dialogue begins one inch into the text area.
pub const DIALOGUE_INDENT: i16 = 10;
/// SPEC §5.2: dialogue is 35 characters wide.
pub const DIALOGUE_WIDTH: u16 = 35;
/// SPEC §5.2: dialogue follows without a blank line.
pub const DIALOGUE_BLANKS_BEFORE: u16 = 0;

/// SPEC §5.2: transitions occupy the full 60-column text area.
pub const TRANSITION_WIDTH: u16 = 60;
/// SPEC §5.2: transitions have one blank line before them.
pub const TRANSITION_BLANKS_BEFORE: u16 = 1;
/// SPEC §5.2: centred text occupies the full 60-column text area.
pub const CENTERED_WIDTH: u16 = 60;
/// SPEC §5.2: centred text has one blank line before it.
pub const CENTERED_BLANKS_BEFORE: u16 = 1;
/// SPEC §5.2: lyrics use the dialogue indent.
pub const LYRIC_INDENT: i16 = 10;
/// SPEC §5.2: lyrics use the 35-column dialogue width.
pub const LYRIC_WIDTH: u16 = 35;
/// One blank before a lyric run, none between consecutive lyrics (ADR 0046).
pub const LYRIC_BLANKS_BEFORE: u16 = 1;

/// The title page's lower-left block — contact, copyright, notes.
///
/// §Phase 7 puts the draft date opposite it, and the two share the 60-column
/// text area. Splitting the width between them is what stops a long contact
/// address printing on top of the date: neither column can reach the other, and
/// the two blank columns between them are the gutter.
pub const TITLE_LOWER_LEFT_WIDTH: u16 = 36;
/// The title page's lower-right block, right-aligned to the text area's edge.
pub const TITLE_LOWER_RIGHT_WIDTH: u16 = 22;

/// SPEC §5.3: rules 2-7 may iterate no more than this many times.
pub const BREAK_RULE_ITERATION_CAP: u8 = 8;
/// SPEC §5.4: checkpoints are retained every four screenplay pages.
pub const CHECKPOINT_INTERVAL_PAGES: usize = 4;

/// Derives usable grid rows from physical height, margins, and six lines/inch.
pub const fn lines_for_height(height_um: u32) -> u16 {
    let text_height = height_um - TOP_MARGIN_UM - BOTTOM_MARGIN_UM;
    ((text_height * LINES_PER_INCH as u32) / MICROMETRES_PER_INCH) as u16
}

/// SPEC §5.2's 54-line US Letter text area, derived from physical dimensions.
pub const US_LETTER_LINES_PER_PAGE: u16 = lines_for_height(US_LETTER_HEIGHT_UM);
/// SPEC §5.2's instruction to derive, rather than hardcode, A4's grid.
pub const A4_LINES_PER_PAGE: u16 = lines_for_height(A4_HEIGHT_UM);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paper_line_counts_are_derived_from_dimensions() {
        assert_eq!(US_LETTER_LINES_PER_PAGE, 54);
        assert_eq!(A4_LINES_PER_PAGE, 58);
    }
}
