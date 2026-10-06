//! Fountain's inline emphasis markup: `*italic*`, `**bold**`,
//! `***bold italic***` and `_underline_`.
//!
//! This is a separate module from [`crate::syntax`] on purpose. `syntax` answers
//! "what does this *line* mean", and it is the one place allowed to answer it
//! (ADR 0011). Emphasis is a different question entirely — it is about
//! characters inside a line and has no bearing on what element the line is — so
//! it neither reads nor adds to the recognition rules.
//!
//! ## Who calls this, and why it takes rows rather than a row
//!
//! PDF and preview share styled output through `render_pdf::emphasis_runs`;
//! the paginator uses the same interpretation for alignment (ADR 0044/0045).
//! Wrapping and editor display still count the literal markers (ADR 0019).
//! Output callers receive a paragraph already broken into rows, and an emphasis
//! run may well open on one and close on another:
//!
//! ```text
//!     *This is a long italic line that the
//!     paginator wrapped in the middle.*
//! ```
//!
//! [`scan`] takes the whole paragraph's rows together for that reason. It is
//! also what lets the second rule below be enforced, because whether a marker
//! has a partner is not a question a single row can answer.
//!
//! ## The recognition rules
//!
//! 1. A run of one, two or three `*` means italic, bold, or both; `_` means
//!    underline. A run of more than three asterisks is the surplus printed,
//!    followed by three that are markers.
//! 2. **A marker only means anything if it has a partner.** An opener needs a
//!    non-space character after it, a closer needs one before it, and the two
//!    must pair up within the paragraph. Everything unpaired is an ordinary
//!    character — which is what keeps `2 * 3` arithmetic and
//!    `tools/make_reference.py` a file name rather than the start of an
//!    underline that runs to the end of the scene.
//! 3. `\*` and `\_` are the literal characters, and the backslash is not
//!    printed.
//!
//! A row boundary counts as a space at both ends: a marker at the start of a row
//! may open but not close, and one at the end may close but not open.

/// Which faces are active over a run.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct Emphasis {
    pub italic: bool,
    pub bold: bool,
    pub underline: bool,
}

impl Emphasis {
    pub const PLAIN: Emphasis = Emphasis {
        italic: false,
        bold: false,
        underline: false,
    };
}

/// One stretch of a row that is drawn in a single face.
///
/// `text` is the printable characters, with every marker that turned out to be
/// one — and every escaping backslash — removed. A row's runs are drawn one
/// after another from wherever the paginator put the row, without gaps for
/// removed markers (ADR 0032). Alignment uses printed width (ADR 0044).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmphasisRun {
    pub text: String,
    pub emphasis: Emphasis,
}

/// Splits a paragraph's rows into the runs they are drawn in.
///
/// One `Vec` out per row in, in order. Runs are never empty and never cross a
/// row boundary.
pub fn scan(rows: &[&str]) -> Vec<Vec<EmphasisRun>> {
    let tokens = tokenise(rows);
    let paired = pair(&tokens);
    emit(rows.len(), &tokens, &paired)
}

/// [`scan`] for a caller that has one row and knows it is the whole paragraph.
pub fn scan_row(row: &str) -> Vec<EmphasisRun> {
    scan(&[row]).pop().unwrap_or_default()
}

/// Printed grid-cell widths of a paragraph's rows, using the same pairing and
/// escaping rules as [`scan`], without allocating styled runs or printed text.
pub fn printed_widths(rows: &[&str]) -> Vec<usize> {
    let mut widths = vec![0; rows.len()];
    measure(rows, &mut widths);
    widths
}

/// Printed width of a row known to be the whole paragraph, like [`scan_row`].
pub fn printed_width(row: &str) -> usize {
    let mut width = [0];
    measure(&[row], &mut width);
    width[0]
}

fn measure(rows: &[&str], widths: &mut [usize]) {
    if !rows.iter().any(|row| row.contains(['*', '_', '\\'])) {
        for (row, width) in rows.iter().zip(widths) {
            *width = row.chars().count();
        }
        return;
    }
    let tokens = tokenise(rows);
    let paired = pair(&tokens);
    for (index, token) in tokens.iter().enumerate() {
        widths[token.row] += match token.kind {
            Kind::Text(_) => 1,
            Kind::Marker { .. } if paired[index] => 0,
            Kind::Marker { marker, .. } => marker.width(),
        };
    }
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Marker {
    Italic,
    Bold,
    BoldItalic,
    Underline,
}

impl Marker {
    fn of(character: char, run: usize) -> Marker {
        match (character, run) {
            ('*', 1) => Marker::Italic,
            ('*', 2) => Marker::Bold,
            ('*', _) => Marker::BoldItalic,
            _ => Marker::Underline,
        }
    }

    fn width(self) -> usize {
        match self {
            Marker::Italic | Marker::Underline => 1,
            Marker::Bold => 2,
            Marker::BoldItalic => 3,
        }
    }

    fn character(self) -> char {
        match self {
            Marker::Underline => '_',
            _ => '*',
        }
    }

    fn apply(self, state: &mut Emphasis, on: bool) {
        match self {
            Marker::Italic => state.italic = on,
            Marker::Bold => state.bold = on,
            Marker::BoldItalic => {
                state.italic = on;
                state.bold = on;
            }
            Marker::Underline => state.underline = on,
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum Kind {
    /// A character to print as it stands. A backslash-escaped marker arrives
    /// here too: by the time the character is a token, nothing about it is a
    /// marker any more.
    Text(char),
    Marker {
        marker: Marker,
        opens: bool,
        closes: bool,
    },
}

#[derive(Debug, Clone, Copy)]
struct Token {
    row: usize,
    kind: Kind,
}

fn tokenise(rows: &[&str]) -> Vec<Token> {
    let mut tokens = Vec::new();
    for (row, text) in rows.iter().enumerate() {
        let scalars: Vec<char> = text.chars().collect();
        let mut index = 0usize;
        while index < scalars.len() {
            let character = scalars[index];
            match character {
                '\\' if matches!(scalars.get(index + 1), Some('*' | '_' | '\\')) => {
                    tokens.push(Token {
                        row,
                        kind: Kind::Text(scalars[index + 1]),
                    });
                    index += 2;
                }
                '*' | '_' => {
                    let run = if character == '*' {
                        scalars[index..]
                            .iter()
                            .take_while(|next| **next == '*')
                            .count()
                    } else {
                        1
                    };
                    if run > 3 {
                        // The surplus is printed, and printed first, so that the
                        // three markers still sit against the text they apply to.
                        for _ in 0..run - 3 {
                            tokens.push(Token {
                                row,
                                kind: Kind::Text('*'),
                            });
                        }
                        index += run - 3;
                        continue;
                    }
                    let marker = Marker::of(character, run);
                    let before = index.checked_sub(1).map(|at| scalars[at]);
                    let after = scalars.get(index + run).copied();
                    tokens.push(Token {
                        row,
                        kind: Kind::Marker {
                            marker,
                            opens: after.is_some_and(|character| character != ' '),
                            closes: before.is_some_and(|character| character != ' '),
                        },
                    });
                    index += run;
                }
                _ => {
                    tokens.push(Token {
                        row,
                        kind: Kind::Text(character),
                    });
                    index += 1;
                }
            }
        }
    }
    tokens
}

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------

/// Which markers turned out to have a partner. Indexed by token.
///
/// A stack per paragraph rather than per kind, searched from the top for the
/// nearest opener of the same kind, so that `*a **b** c*` nests and
/// `*a _b* c_` — which overlaps rather than nesting — still pairs both.
fn pair(tokens: &[Token]) -> Vec<bool> {
    let mut paired = vec![false; tokens.len()];
    let mut open: Vec<(Marker, usize)> = Vec::new();
    for (index, token) in tokens.iter().enumerate() {
        let Kind::Marker {
            marker,
            opens,
            closes,
        } = token.kind
        else {
            continue;
        };
        // Closing is tried first: inside an open run, a marker that could be
        // read either way ends it.
        let matching = open.iter().rposition(|(open, _)| *open == marker);
        match matching {
            Some(at) if closes => {
                let (_, opener) = open.remove(at);
                paired[opener] = true;
                paired[index] = true;
            }
            _ if opens && matching.is_none() => open.push((marker, index)),
            _ => {}
        }
    }
    // Whatever is still open never found a partner, and `paired` already says
    // so — this is the rule that keeps a lone underscore a lone underscore.
    paired
}

// ---------------------------------------------------------------------------
// Emission
// ---------------------------------------------------------------------------

fn emit(rows: usize, tokens: &[Token], paired: &[bool]) -> Vec<Vec<EmphasisRun>> {
    let mut output = vec![Vec::new(); rows];
    let mut state = Emphasis::PLAIN;
    let mut pending = String::new();
    let mut pending_row = 0usize;
    let mut pending_emphasis = state;

    macro_rules! flush {
        () => {
            if !pending.is_empty() {
                output[pending_row].push(EmphasisRun {
                    text: std::mem::take(&mut pending),
                    emphasis: pending_emphasis,
                });
            }
        };
    }

    for (index, token) in tokens.iter().enumerate() {
        match token.kind {
            Kind::Marker { marker, .. } if paired[index] => {
                flush!();
                let on = !match marker {
                    Marker::Italic => state.italic,
                    Marker::Bold => state.bold,
                    Marker::BoldItalic => state.italic && state.bold,
                    Marker::Underline => state.underline,
                };
                marker.apply(&mut state, on);
                pending_emphasis = state;
            }
            // Unpaired: ordinary characters, as many as it was written with.
            Kind::Marker { marker, .. } => {
                if pending.is_empty() || token.row != pending_row {
                    flush!();
                    pending_row = token.row;
                    pending_emphasis = state;
                }
                for _ in 0..marker.width() {
                    pending.push(marker.character());
                }
            }
            Kind::Text(character) => {
                if pending.is_empty() || token.row != pending_row {
                    flush!();
                    pending_row = token.row;
                    pending_emphasis = state;
                }
                pending.push(character);
            }
        }
    }
    flush!();
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn printed_width_keeps_literals_and_removes_only_paired_markers_and_escapes() {
        for (text, width) in [
            ("", 0),
            ("é中😀", 3),
            ("_**BRICK & STEEL**_", 13),
            ("***THE _END_***", 7),
            ("UNPAIRED **TITLE", 16),
            (r"\*STAR\* \\ \q", 11),
            ("****END****", 5),
        ] {
            assert_eq!(printed_width(text), width, "{text:?}");
        }
        assert_eq!(printed_widths(&[]), Vec::<usize>::new());
        assert_eq!(printed_widths(&["**THE", "", "END**"]), [3, 0, 3]);
        assert_eq!(printed_widths(&["**THE", "END"]), [5, 3]);
    }

    /// The runs as `(text, faces)`, with faces spelled `biu`.
    fn describe(runs: Vec<EmphasisRun>) -> Vec<(String, String)> {
        runs.into_iter()
            .map(|run| {
                let mut faces = String::new();
                if run.emphasis.bold {
                    faces.push('b');
                }
                if run.emphasis.italic {
                    faces.push('i');
                }
                if run.emphasis.underline {
                    faces.push('u');
                }
                if faces.is_empty() {
                    faces.push('-');
                }
                (run.text, faces)
            })
            .collect()
    }

    fn one(row: &str) -> Vec<(String, String)> {
        describe(scan_row(row))
    }

    fn many(rows: &[&str]) -> Vec<Vec<(String, String)>> {
        scan(rows).into_iter().map(describe).collect()
    }

    fn run(text: &str, faces: &str) -> (String, String) {
        (text.to_owned(), faces.to_owned())
    }

    #[test]
    fn unmarked_text_is_one_plain_run() {
        assert_eq!(
            one("He crosses the room."),
            [run("He crosses the room.", "-")]
        );
        assert_eq!(one(""), []);
    }

    #[test]
    fn the_four_faces_are_recognised() {
        assert_eq!(one("*a*"), [run("a", "i")]);
        assert_eq!(one("**a**"), [run("a", "b")]);
        assert_eq!(one("***a***"), [run("a", "bi")]);
        assert_eq!(one("_a_"), [run("a", "u")]);
    }

    #[test]
    fn faces_combine_however_they_are_nested() {
        assert_eq!(one("_**a**_"), [run("a", "bu")]);
        assert_eq!(one("**_a_**"), [run("a", "bu")]);
        // Overlapping rather than nesting. Both pairs are still pairs.
        assert_eq!(
            one("*a _b* c_"),
            [run("a ", "i"), run("b", "iu"), run(" c", "u")]
        );
    }

    #[test]
    fn the_markers_are_not_printed_and_leave_no_gap() {
        // ADR 0032: the paginator counted the markers while deciding where the
        // row broke, and the renderer draws what is left of the row from where
        // the row starts. A gap where a marker used to be is not a screenplay.
        assert_eq!(one("*one* two"), [run("one", "i"), run(" two", "-")]);
        assert_eq!(
            one("plain **bold** and *italic* end"),
            [
                run("plain ", "-"),
                run("bold", "b"),
                run(" and ", "-"),
                run("italic", "i"),
                run(" end", "-"),
            ]
        );
    }

    #[test]
    fn an_unpaired_marker_is_an_ordinary_character() {
        // The rule that matters most in practice. Every one of these appears in
        // real scripts and none of them is emphasis.
        assert_eq!(one("2 * 3"), [run("2 * 3", "-")]);
        assert_eq!(one("Note *"), [run("Note *", "-")]);
        assert_eq!(
            one("Generated by tools/make_reference.py"),
            [run("Generated by tools/make_reference.py", "-")],
            "a snake_case file name is a file name"
        );
        assert_eq!(
            one("He opens *emphasis and never closes it."),
            [run("He opens *emphasis and never closes it.", "-")]
        );
        // A paired one in the same row still works.
        assert_eq!(
            one("_read_me_ first"),
            [run("read", "u"), run("me_ first", "-")]
        );
    }

    #[test]
    fn a_backslash_escapes_a_marker_and_is_not_printed() {
        assert_eq!(one(r"5\*4"), [run("5*4", "-")]);
        assert_eq!(one(r"back\\slash"), [run(r"back\slash", "-")]);
        assert_eq!(one(r"\*not italic\*"), [run("*not italic*", "-")]);
    }

    #[test]
    fn a_run_the_paginator_wrapped_spans_the_rows_it_wrapped_onto() {
        assert_eq!(
            many(&["*This is a long italic line", "that was wrapped.*"]),
            [
                vec![run("This is a long italic line", "i")],
                vec![run("that was wrapped.", "i")],
            ]
        );
    }

    #[test]
    fn a_marker_with_no_partner_on_any_row_is_still_a_character() {
        assert_eq!(
            many(&["*This opens and", "nothing closes it."]),
            [
                vec![run("*This opens and", "-")],
                vec![run("nothing closes it.", "-")],
            ]
        );
    }

    #[test]
    fn a_row_boundary_is_neither_a_space_nor_a_character() {
        // Opening at the very end of a row would leave the run with nothing to
        // apply to, and closing at the very start of one has nothing behind it,
        // so neither of these pairs up.
        assert_eq!(
            many(&["trailing *", "* leading"]),
            [vec![run("trailing *", "-")], vec![run("* leading", "-")]]
        );
    }

    #[test]
    fn four_asterisks_are_a_character_and_three_markers() {
        assert_eq!(one("****a***"), [run("*", "-"), run("a", "bi")]);
    }

    #[test]
    fn every_ordinary_character_survives_and_no_run_is_empty() {
        // A blunt property over awkward inputs: whatever the scanner decides,
        // the concatenated runs are what gets drawn, and nothing is lost from
        // them except markers that paired up and escaping backslashes.
        for rows in [
            &["" as &str] as &[&str],
            &["*"],
            &["**"],
            &["***"],
            &["****"],
            &["*****"],
            &["_"],
            &["__"],
            &["*_*_"],
            &["a*b*c"],
            &["*a**b*"],
            &["***a*b***"],
            &[r"\*"],
            &[r"\\"],
            &[r"\"],
            &["* *"],
            &["*  *"],
            &["_a *b_ c*"],
            &["*one", "two*", "three"],
            &["_", "_"],
        ] {
            let scanned = scan(rows);
            assert_eq!(scanned.len(), rows.len(), "{rows:?} lost a row");
            for (row, runs) in rows.iter().zip(&scanned) {
                let printed: String = runs.iter().map(|run| run.text.as_str()).collect();
                let ordinary = |text: &str| -> String {
                    text.chars()
                        .filter(|c| !matches!(c, '*' | '_' | '\\'))
                        .collect()
                };
                assert_eq!(
                    ordinary(&printed),
                    ordinary(row),
                    "{rows:?} changed {row:?}"
                );
                assert!(
                    runs.iter().all(|run| !run.text.is_empty()),
                    "{rows:?} has an empty run"
                );
                assert!(
                    printed.chars().count() <= row.chars().count(),
                    "{rows:?} printed more than it was given"
                );
            }
        }
    }
}
