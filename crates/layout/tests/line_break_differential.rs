//! The Rust half of the corpus-wide line-breaking differential test.
//!
//! `docs/LINE_BREAKING.md` is one specification with two implementations:
//! `layout::line_spans` here and `wrapText` in `app/lib/editor/line_layout.dart`
//! (ADR 0018). Nothing in the process runs both, so this test writes down what
//! Rust answers for every block of the corpus at every interesting width, and
//! `app/test/editor/line_break_differential_test.dart` asserts that the editor
//! answers the same. The fixture is a build product of this file: it is
//! regenerated and compared on every `cargo test`, so a change to the wrap that
//! is not also a change to the committed fixture fails here, and a change to
//! the fixture that the editor does not agree with fails there.
//!
//! Update the fixture the way the layout goldens are updated:
//!
//! ```sh
//! UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential
//! ```
//!
//! Boundaries are the comparison, not rendered strings: two wraps can draw the
//! same rows over different source offsets, and offsets are what a caret, a
//! selection and a PDF's source mapping are made of. Page-level pagination is
//! deliberately absent — it is the paginator's business alone, and comparing it
//! here would make the editor's fluid layout look like a disagreement.

use std::collections::HashMap;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use slugline_document::{split_scene_number, without_notes_and_boneyards, Document};
use slugline_layout::{break_lines, display_text, line_spans};

/// Widths every generated case is wrapped at.
///
/// One and two are the degenerate ends of the contract; 20, 33, 35 and 60 are
/// §5.2's element widths, which is what the paginator actually asks for; the
/// small odd ones put wrap points inside tab expansions and space runs.
const WIDTHS: [u16; 11] = [1, 2, 3, 4, 5, 7, 10, 20, 33, 35, 60];

/// Widths every corpus block is wrapped at.
///
/// Three element widths and one narrow enough to wrap a corpus block half a
/// dozen times. The degenerate widths are asked of the generated cases instead,
/// where the text is short: a hundred-column paragraph at width one is a
/// hundred rows of fixture that repeat what `edge/one long word` already says.
const CORPUS_WIDTHS: [u16; 4] = [7, 20, 35, 60];

/// The reference feature is 120 pages of prose; it is carried at the two widths
/// a screenplay is actually set in rather than at all eleven, because its value
/// here is volume of real text, not another look at the degenerate widths.
const REFERENCE_WIDTHS: [u16; 2] = [35, 60];

/// Sweeps are long and exist to compare display casing scalar by scalar. Wrapping
/// them at every width would multiply the fixture without asking a new question.
const SWEEP_WIDTHS: [u16; 2] = [7, 60];

const FIXTURE: &str = "testdata/line-breaking.json";

struct Case {
    name: String,
    text: String,
    uppercase: bool,
    widths: &'static [u16],
}

#[test]
fn the_committed_fixture_is_the_wrap_this_crate_produces() {
    let generated = render(&cases());
    let path = workspace_root().join(FIXTURE);

    if std::env::var_os("UPDATE_LINE_BREAK_FIXTURES").is_some() {
        fs::write(&path, &generated).expect("write requested fixture update");
    }
    let committed =
        fs::read_to_string(&path).unwrap_or_else(|error| panic!("{}: {error}", path.display()));

    if committed != generated {
        panic!(
            "{FIXTURE} is not what layout::line_spans now produces.\n\
             If the wrap changed on purpose, the editor's wrapText has to change with it \
             (docs/LINE_BREAKING.md), then:\n    \
             UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential\n\
             and run `flutter test test/editor/line_break_differential_test.dart` before committing.\n\
             {}",
            first_difference(&committed, &generated)
        );
    }
}

#[test]
fn the_fixture_covers_the_whole_corpus_and_the_contract() {
    let cases = cases();
    for file in corpus_files() {
        let stem = stem(&file);
        assert!(
            cases
                .iter()
                .any(|case| case.name.starts_with(&format!("{stem}#"))),
            "{stem} contributed no block to the differential fixture"
        );
    }
    let named = |prefix: &str| {
        cases
            .iter()
            .filter(|case| case.name.starts_with(prefix))
            .count()
    };
    assert!(named("edge/") >= 80, "the generated edge cases are missing");
    assert!(named("sweep/") >= 4, "the casing sweeps are missing");
    assert!(
        named("reference-feature#") >= 500,
        "the reference feature is missing"
    );
    // Both castings of every case: a heading that upper-cases differently in
    // one language is a wrap divergence waiting to happen (Phase 6B).
    assert!(cases.iter().any(|case| case.uppercase));
    assert!(cases.iter().any(|case| !case.uppercase));
}

#[test]
fn a_row_of_spans_is_a_row_of_break_lines() {
    // The fixture is spans; the paginator consumes strings. They come from one
    // wrap, and this is what says so for every text the fixture carries.
    for case in cases() {
        let display = display_text(&case.text, case.uppercase);
        for width in case.widths {
            let rows = break_lines(&display, *width);
            let spans = line_spans(&display, *width);
            assert_eq!(rows.len(), spans.len(), "{} at {width}", case.name);
            for (row, span) in rows.iter().zip(&spans) {
                assert_eq!(
                    row.chars().count(),
                    span.columns,
                    "{} at {width}",
                    case.name
                );
            }
        }
    }
}

fn cases() -> Vec<Case> {
    let mut cases = Vec::new();
    let mut seen = HashMap::new();

    let mut push = |name: String, text: String, uppercase: bool, widths: &'static [u16]| {
        // The corpus repeats itself — every cue in a feature, every blank
        // action line — and a case that wraps character for character like an
        // earlier one asks nothing new. Two castings of a text with no lower
        // case in it are one case for the same reason; the casing itself is
        // swept exhaustively below.
        let display = display_text(&text, uppercase);
        if seen.insert((display, widths), ()).is_some() {
            return;
        }
        cases.push(Case {
            name,
            text,
            uppercase,
            widths,
        });
    };

    for (label, text) in edge_cases() {
        for uppercase in [false, true] {
            push(
                format!("edge/{label}{}", suffix(uppercase)),
                text.to_owned(),
                uppercase,
                &WIDTHS,
            );
        }
    }

    for (label, text) in sweeps() {
        for uppercase in [false, true] {
            push(
                format!("sweep/{label}{}", suffix(uppercase)),
                text.clone(),
                uppercase,
                &SWEEP_WIDTHS,
            );
        }
    }

    for path in corpus_files() {
        let stem = stem(&path);
        let source = fs::read_to_string(&path).expect("UTF-8 Fountain fixture");
        for (index, block) in Document::parse(&source).blocks().iter().enumerate() {
            // What the editor wraps is the block as the writer typed it, notes
            // and all; what the paginator wraps is the prepared text. Both are
            // text handed to the same primitive, so both are carried.
            let text = block.text().to_owned();
            for uppercase in [false, true] {
                push(
                    format!("{stem}#{index}{}", suffix(uppercase)),
                    text.clone(),
                    uppercase,
                    &CORPUS_WIDTHS,
                );
            }
            let prepared = prepared(&text);
            if prepared != text {
                for uppercase in [false, true] {
                    push(
                        format!("{stem}#{index} prepared{}", suffix(uppercase)),
                        prepared.clone(),
                        uppercase,
                        &CORPUS_WIDTHS,
                    );
                }
            }
        }
    }

    let reference =
        fs::read_to_string(workspace_root().join("testdata/reference-feature.fountain"))
            .expect("the generated reference feature");
    for (index, block) in Document::parse(&reference).blocks().iter().enumerate() {
        push(
            format!("reference-feature#{index}"),
            block.text().to_owned(),
            false,
            &REFERENCE_WIDTHS,
        );
    }

    cases
}

fn suffix(uppercase: bool) -> &'static str {
    if uppercase {
        " upper"
    } else {
        ""
    }
}

/// A corpus block as the paginator sees it: §4.2's notes and boneyards removed
/// and a scene number split off the heading.
fn prepared(text: &str) -> String {
    let visible = without_notes_and_boneyards(text);
    split_scene_number(&visible).0.to_owned()
}

/// The contract, case by case. Every rule in `docs/LINE_BREAKING.md` that can be
/// asked of one block of text is asked here, at all eleven widths.
fn edge_cases() -> Vec<(&'static str, &'static str)> {
    vec![
        ("empty", ""),
        ("one space", " "),
        ("space run", "     "),
        ("newline alone", "\n"),
        ("two newlines", "\n\n"),
        ("trailing newline", "one\n"),
        ("leading newline", "\ntwo"),
        ("consecutive newlines", "one\n\n\ntwo"),
        ("newline after a wrap space", "abc \ndef"),
        ("newline at a width boundary", "abc\n"),
        ("hard lines wrapped independently", "aaaa bbbb\ncccc dddd"),
        ("words", "one two three"),
        ("one long word", "abcdefgh"),
        (
            "a word longer than any width",
            "supercalifragilisticexpialidocious",
        ),
        ("internal space run", "one  two\n\nthree"),
        ("one trailing space", "abc "),
        ("two trailing spaces", "abc  "),
        ("five trailing spaces", "abc     "),
        ("space run at the boundary", "one    two"),
        ("space run then a long word", "one   twothree"),
        ("spaces before the boundary", "a  b cd"),
        ("leading space run", "   abcdef"),
        ("leading and trailing spaces", "  leading and trailing  "),
        ("spaces around a newline", "word  \n  word"),
        ("tab alone", "\t"),
        ("tab at column zero", "\tx"),
        ("tab at column one", "a\tx"),
        ("tab at column three", "abc\tx"),
        ("tab at column four", "abcd\tx"),
        ("tab after a hard line", "abcd\n\tx"),
        ("two tabs", "\t\tabc"),
        ("tabs straddling a boundary", "ab\tcd\tef"),
        ("adjacent tabs mid line", "a\t\tb"),
        ("tab then space", "\t \t x"),
        ("trailing tab", "x\t"),
        ("tabs and spaces near a newline", "\t One \n Two\t"),
        ("a tab in every column", "a\tb\tc\td"),
        ("astral scalar at the width", "aaaaaaaaa\u{1F3AC}bbb"),
        ("astral scalars alone", "\u{1F3AC}\u{1F3AC}\u{1F3AC}"),
        ("astral scalar in a word", "a\u{1F3AC}b"),
        (
            "astral scalars with spaces",
            "\u{1F3AC} emoji \u{1F3AC} in \u{1F3AC} text",
        ),
        ("combining sequence", "e\u{301}xy"),
        ("two combining marks", "e\u{301}\u{302}f"),
        ("accents", "café au lait"),
        ("a scalar that refuses capitals", "straße"),
        ("a heading with one", "int. straße - tag"),
        ("a ligature", "int. ﬁnca - day"),
        ("the three refusals", "ß ŉ ǰ"),
        ("CJK", "日本語のテキストです"),
        ("CJK with a cue", "@ジョン"),
        ("emphasis markers", "*bold* _under_ **both**"),
        ("nested emphasis", "***all*** of it"),
        ("markers around a wrap", "_*nested markers across a wrap*_"),
        ("a scene number", "INT. HOUSE - DAY #1A#"),
        ("a note", "Action [[with a note]] in it"),
        ("a boneyard", "Action /* struck out */ still here"),
        ("dual dialogue cue", "JOHN ^"),
        ("a parenthetical", "(quietly, to himself, at some length)"),
        ("a transition", "smash cut to:"),
        (
            "sixty columns exactly",
            &"abcde fghij klmno pqrst uvwxy zabcd efghi jklmn opqrs tuvwx yz"[..60],
        ),
        ("a carriage return", "one\r\ntwo"),
    ]
}

/// Long runs of scalars, to compare display casing across a whole Unicode
/// block rather than at the handful of letters a corpus happens to contain.
///
/// Phase 6B left the contract's uppercase rule resting on Dart's `toUpperCase`
/// and Rust's `char::to_uppercase` agreeing scalar for scalar. These are what
/// would notice if a Unicode table update moved one of them.
fn sweeps() -> Vec<(&'static str, String)> {
    let printable = |from: u32, to: u32| -> String {
        (from..=to)
            .filter_map(char::from_u32)
            .filter(|character| !character.is_whitespace() && !character.is_control())
            .collect()
    };
    vec![
        ("latin and punctuation", printable(0x21, 0x024F)),
        ("greek and cyrillic", printable(0x0370, 0x04FF)),
        ("astral", printable(0x1F600, 0x1F64F)),
    ]
}

fn render(cases: &[Case]) -> String {
    let mut out = String::new();
    out.push_str(
        "{\n  \"note\": \"Generated by crates/layout/tests/line_break_differential.rs. \
         Do not edit by hand; see docs/LINE_BREAKING.md.\",\n  \
         \"offsets\": \"Unicode scalar indices into display.\",\n  \"cases\": [\n",
    );
    for (index, case) in cases.iter().enumerate() {
        let display = display_text(&case.text, case.uppercase);
        let scalars = scalar_indices(&display);

        out.push_str("    {\"name\":");
        json_string(&case.name, &mut out);
        out.push_str(",\"uppercase\":");
        out.push_str(if case.uppercase { "true" } else { "false" });
        out.push_str(",\"text\":");
        json_string(&case.text, &mut out);
        if display != case.text {
            out.push_str(",\"display\":");
            json_string(&display, &mut out);
        }
        out.push_str(",\"runs\":[");
        for (position, width) in case.widths.iter().enumerate() {
            if position > 0 {
                out.push(',');
            }
            let _ = write!(out, "{{\"width\":{width},\"lines\":[");
            for (row, span) in line_spans(&display, *width).iter().enumerate() {
                if row > 0 {
                    out.push(',');
                }
                let scalar = |offset: usize| {
                    *scalars
                        .get(&offset)
                        .unwrap_or_else(|| panic!("{offset} is not a scalar boundary"))
                };
                let _ = write!(
                    out,
                    "[{},{},{},",
                    scalar(span.start_utf8),
                    scalar(span.end_utf8),
                    span.columns
                );
                match span.hard_break_utf8 {
                    Some(offset) => {
                        let _ = write!(out, "{}]", scalar(offset));
                    }
                    None => out.push_str("null]"),
                }
            }
            out.push_str("]}");
        }
        out.push_str("]}");
        if index + 1 < cases.len() {
            out.push(',');
        }
        out.push('\n');
    }
    out.push_str("  ]\n}\n");
    out
}

/// Byte offset to scalar index, for every boundary in the string.
///
/// The fixture is read by Dart, which counts UTF-16 code units, so neither
/// side's native offsets can be the ones on the wire. Scalar indices are the
/// unit `docs/LINE_BREAKING.md` defines a column in, and both sides can reach
/// them from their own.
fn scalar_indices(text: &str) -> HashMap<usize, usize> {
    let mut map: HashMap<usize, usize> = text
        .char_indices()
        .enumerate()
        .map(|(scalar, (offset, _))| (offset, scalar))
        .collect();
    map.insert(text.len(), text.chars().count());
    map
}

fn json_string(value: &str, out: &mut String) {
    out.push('"');
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if (control as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", control as u32);
            }
            other => out.push(other),
        }
    }
    out.push('"');
}

fn first_difference(committed: &str, generated: &str) -> String {
    for (number, (left, right)) in committed.lines().zip(generated.lines()).enumerate() {
        if left != right {
            // A case is one long line, so print the window around the change
            // rather than its first 160 columns.
            let at = left
                .char_indices()
                .zip(right.chars())
                .find(|((_, left), right)| left != right)
                .map_or(left.len().min(right.len()), |((offset, _), _)| offset);
            return format!(
                "First difference at line {}, column {at}:\n  committed: {}\n  generated: {}",
                number + 1,
                window(left, at),
                window(right, at)
            );
        }
    }
    format!(
        "The committed fixture has {} lines and this one has {}.",
        committed.lines().count(),
        generated.lines().count()
    )
}

/// Eighty columns either side of `at`, on character boundaries.
fn window(line: &str, at: usize) -> String {
    let start = line
        .char_indices()
        .map(|(offset, _)| offset)
        .find(|offset| *offset + 80 >= at)
        .unwrap_or(0)
        .min(at);
    let end = line
        .char_indices()
        .map(|(offset, _)| offset)
        .chain(std::iter::once(line.len()))
        .find(|offset| *offset >= at + 80)
        .unwrap_or(line.len());
    format!(
        "{}{}{}",
        if start > 0 { "…" } else { "" },
        &line[start..end],
        if end < line.len() { "…" } else { "" }
    )
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("layout crate is two levels below the workspace root")
        .to_owned()
}

fn corpus_files() -> Vec<PathBuf> {
    let mut paths: Vec<_> = fs::read_dir(workspace_root().join("testdata/corpus"))
        .expect("corpus directory")
        .map(|entry| entry.expect("corpus entry").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "fountain")
        })
        .collect();
    paths.sort();
    paths
}

fn stem(path: &Path) -> String {
    path.file_stem()
        .and_then(|stem| stem.to_str())
        .expect("UTF-8 fixture stem")
        .to_owned()
}
