/// One visual row of wrapped text, as boundaries in the source it came from.
///
/// The rendered row is one coordinate system and the source is another; this is
/// the second one. Offsets are UTF-8 byte offsets into the text handed to
/// [`line_spans`], and [`columns`](LineSpan::columns) is the row's width on the
/// §5.2 grid, where one Unicode scalar is one cell and a tab is however many
/// cells its stop takes. Subtracting the two offsets is a column count only for
/// text that happens to be plain ASCII — `docs/LINE_BREAKING.md` is what says so.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineSpan {
    /// Byte offset of the row's first scalar. Inclusive.
    pub start_utf8: usize,
    /// Byte offset one past the row's last scalar. Exclusive.
    ///
    /// The whitespace a wrap consumed is the gap between one row's end and the
    /// next row's start, and a tab a wrap split lies inside that gap: no offset
    /// ever points into a source scalar.
    pub end_utf8: usize,
    /// Grid cells the row occupies, after tab expansion.
    pub columns: usize,
    /// Byte offset of the `\n` that terminates this row, when there is one.
    ///
    /// The newline is outside the printable span, so a row whose trailing
    /// spaces a wrap consumed still reports the newline that ended its hard
    /// line.
    pub hard_break_utf8: Option<usize>,
}

/// Breaks fixed-grid text on ASCII spaces. Runs of spaces inside a line are
/// preserved; spaces at a chosen wrap boundary are consumed. A word wider than
/// the column width is the only text split mid-word. Tabs expand to four-column
/// tab stops before wrapping, and explicit newlines always begin a new line.
pub fn break_lines(text: &str, width: u16) -> Vec<String> {
    break_lines_with_spans(text, width)
        .into_iter()
        .map(|line| line.text)
        .collect()
}

/// The same wrap as [`break_lines`], reported as source boundaries.
///
/// This is the canonical result `docs/LINE_BREAKING.md` defines, and it is what
/// the editor's `wrapText` is compared against block by block: two rendered
/// strings can agree while the offsets under them do not, and it is the offsets
/// a caret and a PDF's source mapping are made of. The two share one
/// implementation, so a row here is the row `break_lines` returns.
pub fn line_spans(text: &str, width: u16) -> Vec<LineSpan> {
    break_lines_with_spans(text, width)
        .into_iter()
        .map(|line| line.span)
        .collect()
}

pub(crate) struct WrappedLine {
    pub(crate) span: LineSpan,
    pub(crate) text: String,
}

/// One hard line expanded onto the grid: one entry per cell.
struct Cells {
    /// The scalar drawn in each cell. A tab contributes spaces.
    scalars: Vec<char>,
    /// The byte offset of the scalar each cell belongs to.
    offsets: Vec<usize>,
}

/// Returns row text and its source boundaries from a single wrapping pass.
pub(crate) fn break_lines_with_spans(text: &str, width: u16) -> Vec<WrappedLine> {
    let width = usize::from(width.max(1));
    let mut output = Vec::new();
    let mut hard_start = 0usize;
    loop {
        let newline = text[hard_start..].find('\n').map(|at| hard_start + at);
        let hard_end = newline.unwrap_or(text.len());
        wrap_hard_line(
            &text[hard_start..hard_end],
            hard_start,
            width,
            newline,
            &mut output,
        );
        match newline {
            Some(offset) => hard_start = offset + 1,
            None => return output,
        }
    }
}

fn expand(line: &str, base: usize) -> Cells {
    let mut scalars = Vec::with_capacity(line.len());
    let mut offsets = Vec::with_capacity(line.len());
    let mut column = 0usize;
    for (offset, character) in line.char_indices() {
        match character {
            '\t' => {
                let cells = 4 - column % 4;
                for _ in 0..cells {
                    scalars.push(' ');
                    offsets.push(base + offset);
                }
                column += cells;
            }
            // Not part of the shared input domain; the editor drops it too.
            '\r' => {}
            other => {
                scalars.push(other);
                offsets.push(base + offset);
                column += 1;
            }
        }
    }
    Cells { scalars, offsets }
}

fn wrap_hard_line(
    line: &str,
    base: usize,
    width: usize,
    hard_break: Option<usize>,
    output: &mut Vec<WrappedLine>,
) {
    let hard_end = base + line.len();
    let cells = expand(line, base);
    if cells.scalars.is_empty() {
        // An empty hard line still occupies a row.
        output.push(WrappedLine {
            span: LineSpan {
                start_utf8: base,
                end_utf8: hard_end,
                columns: 0,
                hard_break_utf8: hard_break,
            },
            text: String::new(),
        });
        return;
    }

    let first = output.len();
    let mut start = 0usize;
    while cells.scalars.len() - start > width {
        let window = &cells.scalars[start..start + width + 1];
        let break_at = if window[width] == ' ' {
            Some(width)
        } else {
            window[..width]
                .iter()
                .rposition(|character| *character == ' ')
                .filter(|offset| window[..*offset].iter().any(|character| *character != ' '))
        };

        match break_at {
            Some(offset) => {
                output.push(row(&cells, start, start + offset, hard_end, None));
                start += offset;
                while cells.scalars.get(start) == Some(&' ') {
                    start += 1;
                }
            }
            None => {
                output.push(row(&cells, start, start + width, hard_end, None));
                start += width;
            }
        }
    }

    if start < cells.scalars.len() {
        output.push(row(
            &cells,
            start,
            cells.scalars.len(),
            hard_end,
            hard_break,
        ));
    } else if let Some(hard_break) = hard_break {
        // A consumed space run can exhaust the rest of a non-empty hard line.
        // It does not create a phantom row, but its newline still terminates
        // the preceding one.
        debug_assert!(output.len() > first);
        let last = output.len() - 1;
        output[last].span.hard_break_utf8 = Some(hard_break);
    }
}

/// One row, from the half-open cell range that fits on it.
fn row(
    cells: &Cells,
    from: usize,
    to: usize,
    hard_end: usize,
    hard_break: Option<usize>,
) -> WrappedLine {
    // A row always begins on a scalar: a break lands either on a non-space cell
    // or after a whole run of spaces, and every cell of a tab is a space.
    debug_assert!(from == 0 || cells.offsets[from - 1] != cells.offsets[from]);
    WrappedLine {
        span: LineSpan {
            start_utf8: cells.offsets[from],
            // A row ends before the scalar of the next cell, so a tab straddling
            // the boundary stays outside both rows' source slices.
            end_utf8: if to < cells.offsets.len() {
                cells.offsets[to]
            } else {
                hard_end
            },
            columns: to - from,
            hard_break_utf8: hard_break,
        },
        text: cells.scalars[from..to].iter().collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_at_spaces_before_splitting_a_word() {
        assert_eq!(break_lines("one two three", 7), ["one two", "three"]);
        assert_eq!(break_lines("abcdefgh", 3), ["abc", "def", "gh"]);
    }

    #[test]
    fn preserves_internal_spaces_and_hard_lines() {
        assert_eq!(
            break_lines("one  two\n\nthree", 20),
            ["one  two", "", "three"]
        );
        assert_eq!(break_lines("abc ", 3), ["abc"]);
    }

    #[test]
    fn tabs_expand_to_deterministic_stops() {
        assert_eq!(break_lines("a\tb", 20), ["a   b"]);
    }

    // The cases below are the shared contract in `docs/LINE_BREAKING.md`. The
    // editor's `wrapText` answers each of them the same way, and
    // `tests/line_break_differential.rs` is what holds it there across the
    // whole corpus.

    #[test]
    fn one_scalar_is_one_column_including_astral_planes() {
        // Nine ASCII characters and a clapperboard fill a ten-column line. A
        // UTF-16 count would have wrapped the emoji onto the next line, which is
        // the divergence this pins.
        assert_eq!(break_lines("aaaaaaaaa🎬bbb", 10), ["aaaaaaaaa🎬", "bbb"]);
        assert_eq!(break_lines("🎬🎬🎬", 2), ["🎬🎬", "🎬"]);
        // A combining sequence counts one column per scalar, not per grapheme.
        assert_eq!(break_lines("e\u{301}xy", 2), ["e\u{301}", "xy"]);
    }

    #[test]
    fn a_whole_space_run_is_consumed_at_a_wrap_point() {
        // The space that sits exactly at the width is a fitted column and stays
        // on the line; the rest of the run is the consumed gap.
        assert_eq!(break_lines("one    two", 4), ["one ", "two"]);
        assert_eq!(break_lines("one   twothree", 4), ["one ", "twot", "hree"]);
        // Spaces before the chosen boundary stay visible.
        assert_eq!(break_lines("a  b cd", 5), ["a  b", "cd"]);
    }

    #[test]
    fn a_leading_space_run_is_not_a_wrap_opportunity() {
        // There is nothing to put on a line broken before column 3, so the word
        // is split at the width instead.
        assert_eq!(break_lines("   abcdef", 3), ["   ", "abc", "def"]);
    }

    #[test]
    fn trailing_spaces_never_make_a_phantom_line() {
        assert_eq!(break_lines("abc ", 3), ["abc"]);
        assert_eq!(break_lines("abc  ", 3), ["abc"]);
        assert_eq!(break_lines("abc     ", 3), ["abc"]);
        // Within the width they are part of the line, not a break opportunity.
        assert_eq!(break_lines("ab ", 4), ["ab "]);
        assert_eq!(break_lines("ab  ", 4), ["ab  "]);
    }

    #[test]
    fn tab_stops_are_four_columns_from_the_start_of_a_hard_line() {
        assert_eq!(break_lines("\tx", 20), ["    x"]);
        assert_eq!(break_lines("a\tx", 20), ["a   x"]);
        assert_eq!(break_lines("abc\tx", 20), ["abc x"]);
        assert_eq!(break_lines("abcd\tx", 20), ["abcd    x"]);
        // A hard newline resets the column; a soft wrap does not.
        assert_eq!(break_lines("abcd\n\tx", 20), ["abcd", "    x"]);
        // The second tab straddles the width: its first cell is fitted display
        // whitespace and the rest of it is consumed.
        assert_eq!(break_lines("ab\tcd\tef", 8), ["ab  cd ", "ef"]);
    }

    #[test]
    fn a_wrap_inside_a_tab_expansion_consumes_it() {
        // The first line is the tab's fitted cells, the rest of the expansion is
        // the consumed gap, and no line begins inside the tab.
        assert_eq!(break_lines("\t\tabc", 3), ["   ", "abc"]);
    }

    #[test]
    fn hard_lines_are_kept_including_empty_ones() {
        assert_eq!(break_lines("", 10), [""]);
        assert_eq!(break_lines("\n", 10), ["", ""]);
        assert_eq!(break_lines("one\n", 10), ["one", ""]);
        assert_eq!(break_lines("\ntwo", 10), ["", "two"]);
        assert_eq!(break_lines("one\n\n\ntwo", 10), ["one", "", "", "two"]);
        // A hard line that a wrap-space exhausts still does not gain a row.
        assert_eq!(break_lines("abc \ndef", 3), ["abc", "def"]);
    }

    #[test]
    fn a_width_below_one_is_one_column() {
        assert_eq!(break_lines("abc", 0), ["a", "b", "c"]);
    }

    // The source boundaries under those rows. The editor asserts every case
    // below on its own side, and `tests/line_break_differential.rs` is what
    // holds the two together over the whole corpus.

    fn ranges(text: &str, width: u16) -> Vec<(usize, usize)> {
        line_spans(text, width)
            .into_iter()
            .map(|span| (span.start_utf8, span.end_utf8))
            .collect()
    }

    fn hard_breaks(text: &str, width: u16) -> Vec<Option<usize>> {
        line_spans(text, width)
            .into_iter()
            .map(|span| span.hard_break_utf8)
            .collect()
    }

    #[test]
    fn a_consumed_space_run_is_the_gap_between_two_rows() {
        // The space that fitted stays on the row; the other three are the gap.
        assert_eq!(ranges("one    two", 4), [(0, 4), (7, 10)]);
        assert_eq!(line_spans("one    two", 4)[0].columns, 4);
    }

    #[test]
    fn a_row_split_inside_a_tab_points_at_neither_half_of_it() {
        // Three cells of the first tab are drawn and both tabs land in the gap:
        // an indivisible source character cannot be half on a row.
        assert_eq!(ranges("\t\tabc", 3), [(0, 0), (2, 5)]);
        assert_eq!(line_spans("\t\tabc", 3)[0].columns, 3);
    }

    #[test]
    fn a_column_is_not_a_byte_offset() {
        // One tab, one column-and-a-bit; one emoji, four bytes and one column.
        let tabbed = line_spans("a\tbc", 20);
        assert_eq!((tabbed[0].start_utf8, tabbed[0].end_utf8), (0, 4));
        assert_eq!(tabbed[0].columns, 6);
        let astral = line_spans("a🎬b", 20);
        assert_eq!((astral[0].start_utf8, astral[0].end_utf8), (0, 6));
        assert_eq!(astral[0].columns, 3);
    }

    #[test]
    fn a_newline_terminates_the_row_it_ends_and_is_on_no_row() {
        assert_eq!(ranges("One.\nTwo.", 60), [(0, 4), (5, 9)]);
        assert_eq!(hard_breaks("One.\nTwo.", 60), [Some(4), None]);
        assert_eq!(ranges("One.\n", 60), [(0, 4), (5, 5)]);
        assert_eq!(hard_breaks("", 60), [None]);
        // A row whose trailing spaces the wrap consumed still reports it.
        assert_eq!(ranges("abc \ndef", 3), [(0, 3), (5, 8)]);
        assert_eq!(hard_breaks("abc \ndef", 3), [Some(4), None]);
    }

    #[test]
    fn every_row_of_break_lines_has_a_span() {
        for text in [
            "",
            "\n",
            "one two three",
            "one    two\n\tindented\n",
            "a🎬b ﬁnca straße",
            "   ",
        ] {
            for width in [1u16, 3, 7, 60] {
                let rows = break_lines(text, width);
                let spans = line_spans(text, width);
                assert_eq!(rows.len(), spans.len(), "{text:?} at {width}");
                for (row, span) in rows.iter().zip(&spans) {
                    assert_eq!(row.chars().count(), span.columns, "{text:?} at {width}");
                }
            }
        }
    }
}
