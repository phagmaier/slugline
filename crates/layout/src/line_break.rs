use slugline_fountain::emphasis::{self, Emphasis, EmphasisRun, SourceRun};

/// One visual row of wrapped text, as boundaries in the source it came from.
///
/// The rendered row is one coordinate system and the source is another; this is
/// the second one. Offsets are UTF-8 byte offsets into the text handed to
/// [`line_spans`], and [`columns`](LineSpan::columns) is the row's width on the
/// printed grid: one visible Unicode scalar is one cell, paired markers and
/// escape slashes are zero cells, and tabs advance to four-column stops.
/// Source bytes and printed columns are intentionally different coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct LineSpan {
    /// Byte offset of the row's first scalar. Inclusive.
    pub start_utf8: usize,
    /// Byte offset one past the row's last scalar. Exclusive.
    ///
    /// Consumed boundary whitespace normally lies between adjacent spans.
    /// Hidden markers interleaved in that gap remain in the preceding span,
    /// without restoring consumed printed spaces. Boundaries never split a
    /// source scalar, including a tab whose expansion straddles a wrap.
    pub end_utf8: usize,
    /// Printed grid cells, after source projection and tab expansion.
    pub columns: usize,
    /// Byte offset of the `\n` that terminates this row, when there is one.
    ///
    /// The newline is outside the printable span, so a row whose trailing
    /// spaces a wrap consumed still reports the newline that ended its hard
    /// line.
    pub hard_break_utf8: Option<usize>,
}

/// Breaks Fountain source on printed ASCII spaces. Paired markers and escaping
/// slashes occupy no columns, but remain intact in the returned raw row text.
/// Internal spaces are preserved and chosen boundary spaces are consumed.
/// Long words split on printed cells; explicit newlines always start a row.
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

/// Wraps already resolved Fountain source metadata without interpreting it again.
pub fn line_spans_with_runs(text: &str, width: u16, runs: &[SourceRun]) -> Vec<LineSpan> {
    break_lines_projected(text, width, runs)
        .into_iter()
        .map(|line| line.span)
        .collect()
}

/// Returns raw output rows using source metadata already resolved by Fountain.
pub fn break_lines_with_runs(text: &str, width: u16, runs: &[SourceRun]) -> Vec<String> {
    break_lines_projected(text, width, runs)
        .into_iter()
        .map(|line| line.text)
        .collect()
}

pub(crate) struct WrappedLine {
    pub(crate) span: LineSpan,
    /// Original markers retained, tabs expanded, boundary spaces consumed.
    pub(crate) text: String,
    pub(crate) runs: Vec<EmphasisRun>,
    pub(crate) projected: bool,
}

/// Printed cells and their exact source geometry. Hidden prefixes belong to
/// the following cell; the first prefix begins at the hard-line boundary.
struct Cells {
    scalars: Vec<char>,
    starts: Vec<usize>,
    offsets: Vec<usize>,
    emphasis: Vec<Emphasis>,
}

pub(crate) fn break_lines_with_spans(text: &str, width: u16) -> Vec<WrappedLine> {
    let runs = emphasis::source_runs(text);
    break_lines_projected(text, width, &runs)
}

pub(crate) fn break_lines_projected(
    text: &str,
    width: u16,
    runs: &[SourceRun],
) -> Vec<WrappedLine> {
    let width = usize::from(width.max(1));
    let mut output = Vec::new();
    let mut hard_start = 0usize;
    loop {
        let newline = text[hard_start..].find('\n').map(|at| hard_start + at);
        let hard_end = newline.unwrap_or(text.len());
        wrap_hard_line(
            text,
            hard_start,
            hard_end,
            width,
            newline,
            runs,
            &mut output,
        );
        match newline {
            Some(offset) => hard_start = offset + 1,
            None => return output,
        }
    }
}

fn expand(text: &str, base: usize, end: usize, runs: &[SourceRun]) -> Cells {
    let mut cells = Cells {
        scalars: Vec::with_capacity(end - base),
        starts: Vec::with_capacity(end - base),
        offsets: Vec::with_capacity(end - base),
        emphasis: if runs.is_empty() {
            Vec::new()
        } else {
            Vec::with_capacity(end - base)
        },
    };
    let mut column = 0usize;
    let mut pending = base;
    let mut run_index = runs.partition_point(|run| run.end_utf8 <= base);
    for (relative, character) in text[base..end].char_indices() {
        let offset = base + relative;
        while run_index < runs.len() && runs[run_index].end_utf8 <= offset {
            run_index += 1;
        }
        let run = runs.get(run_index).filter(|run| run.start_utf8 <= offset);
        if run.is_some_and(|run| run.hidden) || character == '\r' {
            continue;
        }
        let count = if character == '\t' { 4 - column % 4 } else { 1 };
        for cell in 0..count {
            cells
                .scalars
                .push(if character == '\t' { ' ' } else { character });
            cells.starts.push(if cell == 0 { pending } else { offset });
            cells.offsets.push(offset);
            if !runs.is_empty() {
                cells
                    .emphasis
                    .push(run.map_or(Emphasis::PLAIN, |run| run.emphasis));
            }
        }
        column += count;
        pending = offset + character.len_utf8();
    }
    cells
}

fn wrap_hard_line(
    text: &str,
    base: usize,
    hard_end: usize,
    width: usize,
    hard_break: Option<usize>,
    runs: &[SourceRun],
    output: &mut Vec<WrappedLine>,
) {
    let cells = expand(text, base, hard_end, runs);
    if cells.scalars.is_empty() {
        output.push(WrappedLine {
            span: LineSpan {
                start_utf8: base,
                end_utf8: hard_end,
                columns: 0,
                hard_break_utf8: hard_break,
            },
            text: text[base..hard_end].replace('\r', ""),
            runs: Vec::new(),
            projected: !runs.is_empty(),
        });
        return;
    }
    let first = output.len();
    let mut start = 0;
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
        let to = start + break_at.unwrap_or(width);
        let mut next = to;
        if break_at.is_some() {
            while cells.scalars.get(next) == Some(&' ') {
                next += 1;
            }
        }
        let mut end = cells.starts.get(to).copied().unwrap_or(hard_end);
        let gap_end = cells.starts.get(next).copied().unwrap_or(hard_end);
        let gap_start = end;
        for hidden in runs
            .iter()
            .filter(|run| run.hidden && run.start_utf8 < gap_end && run.end_utf8 > gap_start)
        {
            end = end.max(hidden.end_utf8.min(gap_end));
        }
        output.push(row(text, &cells, start, to, end, None, runs));
        start = next;
    }
    if start < cells.scalars.len() {
        output.push(row(
            text,
            &cells,
            start,
            cells.scalars.len(),
            hard_end,
            hard_break,
            runs,
        ));
    } else if let Some(newline) = hard_break {
        debug_assert!(output.len() > first);
        output.last_mut().expect("wrapped row").span.hard_break_utf8 = Some(newline);
    }
}

fn row(
    source: &str,
    cells: &Cells,
    from: usize,
    to: usize,
    end: usize,
    hard_break: Option<usize>,
    source_runs: &[SourceRun],
) -> WrappedLine {
    let start = cells.starts[from];
    let mut text = String::new();
    let mut runs: Vec<EmphasisRun> = Vec::new();
    let mut cell = from;
    let mut run_index = source_runs.partition_point(|run| run.end_utf8 <= start);
    for (relative, character) in source[start..end].char_indices() {
        let offset = start + relative;
        while run_index < source_runs.len() && source_runs[run_index].end_utf8 <= offset {
            run_index += 1;
        }
        let hidden = source_runs
            .get(run_index)
            .is_some_and(|run| run.start_utf8 <= offset && run.hidden);
        if hidden {
            text.push(character);
        }
        while cell < to && cells.offsets[cell] == offset {
            let character = cells.scalars[cell];
            let face = cells.emphasis.get(cell).copied().unwrap_or(Emphasis::PLAIN);
            text.push(character);
            if !source_runs.is_empty() {
                match runs.last_mut() {
                    Some(last) if last.emphasis == face => last.text.push(character),
                    _ => runs.push(EmphasisRun {
                        text: character.to_string(),
                        emphasis: face,
                    }),
                }
            }
            cell += 1;
        }
    }
    // A tab split by a wrap has printable cells but no complete source scalar
    // in the row's span. Its selected expansion still belongs to this row.
    while cell < to {
        let character = cells.scalars[cell];
        let face = cells.emphasis.get(cell).copied().unwrap_or(Emphasis::PLAIN);
        text.push(character);
        if !source_runs.is_empty() {
            match runs.last_mut() {
                Some(last) if last.emphasis == face => last.text.push(character),
                _ => runs.push(EmphasisRun {
                    text: character.to_string(),
                    emphasis: face,
                }),
            }
        }
        cell += 1;
    }
    WrappedLine {
        span: LineSpan {
            start_utf8: start,
            end_utf8: end,
            columns: to - from,
            hard_break_utf8: hard_break,
        },
        text,
        runs,
        projected: !source_runs.is_empty(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn printed(rows: &[WrappedLine]) -> Vec<String> {
        rows.iter()
            .map(|line| {
                if line.projected {
                    line.runs.iter().map(|run| run.text.as_str()).collect()
                } else {
                    line.text.clone()
                }
            })
            .collect()
    }

    #[test]
    fn paired_markup_wraps_by_printed_width_without_changing_raw_source() {
        let rows = break_lines_with_spans("ab**cd**ef", 2);
        assert_eq!(printed(&rows), ["ab", "cd", "ef"]);
        assert_eq!(
            rows.iter()
                .map(|line| line.text.as_str())
                .collect::<String>(),
            "ab**cd**ef"
        );
        assert_eq!(
            rows.iter()
                .map(|line| (line.span.start_utf8, line.span.end_utf8))
                .collect::<Vec<_>>(),
            [(0, 2), (2, 6), (6, 10)]
        );
        assert!(rows[1].runs.iter().all(|run| run.emphasis.bold));
        assert!(rows[2]
            .runs
            .iter()
            .all(|run| run.emphasis == Emphasis::PLAIN));
    }

    #[test]
    fn consumed_space_gaps_do_not_lose_hidden_markers() {
        let rows = break_lines_with_spans("*a*  *b*", 1);
        assert_eq!(printed(&rows), ["a", "b"]);
        assert_eq!(
            rows.iter()
                .map(|line| line.text.as_str())
                .collect::<Vec<_>>(),
            ["*a*", "*b*"]
        );
        assert_eq!(
            rows.iter()
                .map(|line| (line.span.start_utf8, line.span.end_utf8))
                .collect::<Vec<_>>(),
            [(0, 3), (5, 8)]
        );
        assert!(rows
            .iter()
            .flat_map(|line| &line.runs)
            .all(|run| run.emphasis.italic));
    }

    #[test]
    fn escapes_unpaired_markers_unicode_and_tabs_use_resolved_printed_cells() {
        let rows = break_lines_with_spans(r"\*é🎬\*", 2);
        assert_eq!(printed(&rows), ["*é", "🎬*"]);
        assert_eq!(
            rows.iter()
                .map(|line| line.text.as_str())
                .collect::<String>(),
            r"\*é🎬\*"
        );
        assert_eq!(printed(&break_lines_with_spans("**a**\tb", 20)), ["a   b"]);
        assert_eq!(printed(&break_lines_with_spans("**a", 2)), ["**", "a"]);
        for width in [1, 2, 20, 28, 33, 35, 60] {
            let rows = break_lines_with_spans("**é🎬中 wrapped dialogue**", width);
            assert!(rows
                .iter()
                .all(|line| line.span.columns <= usize::from(width)));
            assert!(rows
                .iter()
                .flat_map(|line| &line.runs)
                .all(|run| run.emphasis.bold));
        }
    }

    #[test]
    fn hard_lines_and_marker_only_sung_rows_keep_source_and_resolved_styles() {
        let rows = break_lines_with_spans("**ab\ncd**", 1);
        assert_eq!(printed(&rows), ["a", "b", "c", "d"]);
        assert_eq!(rows[1].span.hard_break_utf8, Some(4));
        assert!(rows
            .iter()
            .flat_map(|line| &line.runs)
            .all(|run| run.emphasis.bold));
        let text = "~\n~**é🎬**\nplain";
        let projection = emphasis::dialogue_source_runs(text);
        let rows = break_lines_projected(text, 1, &projection);
        assert_eq!(printed(&rows), ["", "é", "🎬", "p", "l", "a", "i", "n"]);
        assert_eq!(rows[0].text, "~");
        assert_eq!(rows[0].span.columns, 0);
        assert_eq!(rows[0].span.hard_break_utf8, Some(1));
        assert!(rows[1].runs[0].emphasis.bold && rows[1].runs[0].emphasis.italic);
        assert_eq!(rows[3].runs[0].emphasis, Emphasis::PLAIN);
    }

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
