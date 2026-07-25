//! Line segmentation.
//!
//! A [`Line`] keeps two ends: `content_end` stops before the terminator, and
//! `end` includes it. Classification uses the first, provenance uses the
//! second, which is how a CRLF file survives a round trip without the parser
//! ever thinking about `\r` again.

/// One source line. Byte offsets into the whole source, BOM included, so a
/// range taken from a `Line` can be handed straight back to `&source[..]`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Line {
    pub start: usize,
    pub content_end: usize,
    pub end: usize,
}

impl Line {
    pub fn content<'a>(&self, source: &'a str) -> &'a str {
        &source[self.start..self.content_end]
    }

    /// A line is blank when it is empty or entirely whitespace. Fountain's
    /// convention of "two spaces means an intentional blank line in Action" is
    /// deliberately not modelled — see ADR 0007. The bytes still round-trip.
    pub fn is_blank(&self, source: &str) -> bool {
        self.content(source).trim().is_empty()
    }
}

/// Splits `source[from..]` into lines, keeping the terminators.
///
/// Both LF and CRLF terminate a line. A lone CR does not: it stays inside the
/// line's content, because a file that uses bare CR endings is far rarer than a
/// file that contains a stray CR, and guessing wrong on the second would split
/// a block the user never split.
pub fn split_lines(source: &str, from: usize) -> Vec<Line> {
    let mut lines = Vec::new();
    let bytes = source.as_bytes();
    let mut start = from;

    while start < bytes.len() {
        match bytes[start..].iter().position(|&b| b == b'\n') {
            Some(offset) => {
                let newline = start + offset;
                let content_end = if newline > start && bytes[newline - 1] == b'\r' {
                    newline - 1
                } else {
                    newline
                };
                lines.push(Line {
                    start,
                    content_end,
                    end: newline + 1,
                });
                start = newline + 1;
            }
            None => {
                lines.push(Line {
                    start,
                    content_end: bytes.len(),
                    end: bytes.len(),
                });
                start = bytes.len();
            }
        }
    }

    lines
}

/// The dominant line ending, decided by the first terminator in the file.
pub fn detect_line_ending(source: &str) -> crate::LineEnding {
    match source.find('\n') {
        Some(0) => crate::LineEnding::Lf,
        Some(index) if source.as_bytes()[index - 1] == b'\r' => crate::LineEnding::CrLf,
        _ => crate::LineEnding::Lf,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::LineEnding;

    #[test]
    fn lines_tile_the_source_without_gaps() {
        for source in ["", "a", "a\n", "a\nb", "a\r\nb\r\n", "\n\n\n", "a\n\nb"] {
            let lines = split_lines(source, 0);
            let mut cursor = 0;
            for line in &lines {
                assert_eq!(line.start, cursor, "gap before {line:?} in {source:?}");
                assert!(line.content_end <= line.end);
                cursor = line.end;
            }
            assert_eq!(cursor, source.len(), "lines stopped short of {source:?}");
        }
    }

    #[test]
    fn crlf_is_stripped_from_content_but_kept_in_the_range() {
        let source = "INT. HOUSE - DAY\r\n";
        let lines = split_lines(source, 0);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].content(source), "INT. HOUSE - DAY");
        assert_eq!(lines[0].end, source.len());
    }

    #[test]
    fn a_final_line_without_a_terminator_is_still_a_line() {
        let source = "no newline at eof";
        let lines = split_lines(source, 0);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].content(source), source);
    }

    #[test]
    fn a_lone_cr_stays_in_the_content() {
        let source = "a\rb\n";
        let lines = split_lines(source, 0);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].content(source), "a\rb");
    }

    #[test]
    fn line_ending_comes_from_the_first_terminator() {
        assert_eq!(detect_line_ending("a\r\nb\n"), LineEnding::CrLf);
        assert_eq!(detect_line_ending("a\nb\r\n"), LineEnding::Lf);
        assert_eq!(detect_line_ending("no terminator"), LineEnding::Lf);
        assert_eq!(detect_line_ending("\n"), LineEnding::Lf);
    }

    #[test]
    fn blank_covers_whitespace_only_lines() {
        let source = "   \t \nx\n";
        let lines = split_lines(source, 0);
        assert!(lines[0].is_blank(source));
        assert!(!lines[1].is_blank(source));
    }
}
