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
}
