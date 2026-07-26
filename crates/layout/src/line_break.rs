/// Breaks fixed-grid text on ASCII spaces. Runs of spaces inside a line are
/// preserved; spaces at a chosen wrap boundary are consumed. A word wider than
/// the column width is the only text split mid-word. Tabs expand to four-column
/// tab stops before wrapping, and explicit newlines always begin a new line.
pub fn break_lines(text: &str, width: u16) -> Vec<String> {
    let width = usize::from(width.max(1));
    let expanded = expand_tabs(text);
    let mut output = Vec::new();

    for hard_line in expanded.split('\n') {
        wrap_hard_line(hard_line, width, &mut output);
    }
    output
}

fn expand_tabs(text: &str) -> String {
    let mut expanded = String::with_capacity(text.len());
    let mut column = 0usize;
    for character in text.chars() {
        match character {
            '\t' => {
                let spaces = 4 - column % 4;
                expanded.extend(std::iter::repeat_n(' ', spaces));
                column += spaces;
            }
            '\n' => {
                expanded.push('\n');
                column = 0;
            }
            '\r' => {}
            other => {
                expanded.push(other);
                column += 1;
            }
        }
    }
    expanded
}

fn wrap_hard_line(line: &str, width: usize, output: &mut Vec<String>) {
    if line.is_empty() {
        output.push(String::new());
        return;
    }

    let characters: Vec<char> = line.chars().collect();
    let mut start = 0usize;
    while characters.len() - start > width {
        let window = &characters[start..start + width + 1];
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
                output.push(characters[start..start + offset].iter().collect());
                start += offset;
                while characters.get(start) == Some(&' ') {
                    start += 1;
                }
            }
            None => {
                output.push(characters[start..start + width].iter().collect());
                start += width;
            }
        }
    }
    if start < characters.len() {
        output.push(characters[start..].iter().collect());
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
    // editor's `wrapText` answers each of them the same way, and remediation
    // Phase 6C is what holds it there across the whole corpus.

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
}
