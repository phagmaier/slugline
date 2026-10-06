//! The parser.
//!
//! Two passes, as §4 requires: segmentation into chunks of adjacent non-blank
//! lines, then classification within a chunk with the neighbouring lines in
//! view. It never fails and never panics (§4.2) — an input it cannot classify
//! becomes Action or [`BlockKind::Opaque`], both of which round-trip.
//!
//! The one invariant everything else rests on: **the provenance ranges of the
//! title page and the elements tile the whole source, in order, with no gaps
//! and no overlaps**, starting after the BOM. Byte-exact round-tripping is then
//! a consequence rather than a feature — serialising an untouched document is
//! copying the source back out in pieces.

use std::ops::Range;

use crate::lines::{detect_line_ending, split_lines, Line};
use crate::syntax::{self, Marker};
use crate::{BlockKind, Element, Script, TitleEntry, TitleField, TitlePage};

/// A block under construction, addressed by line index rather than byte range;
/// the ranges are assigned once all blocks are known, so that each block can
/// absorb the blank lines that follow it.
struct Pending {
    kind: BlockKind,
    text: String,
    forced: bool,
    dual: bool,
    first_line: usize,
    last_line: usize,
}

/// Parses Fountain source into a [`Script`].
///
/// Total: every input is a valid document. Malformed input produces Action and
/// Opaque blocks, never an error and never a panic.
pub fn parse(source: &str) -> Script {
    let bom = source.starts_with('\u{feff}');
    let body_start = if bom { '\u{feff}'.len_utf8() } else { 0 };
    let line_ending = detect_line_ending(source);
    let lines = split_lines(source, body_start);
    let spans = protected_spans(source, body_start);

    let (mut title_page, mut cursor) = parse_title_page(source, &lines, &spans);

    let mut pending: Vec<Pending> = Vec::new();
    while cursor < lines.len() {
        if is_separator(&lines[cursor], source, &spans) {
            cursor += 1;
            continue;
        }
        let chunk_start = cursor;
        while cursor < lines.len() && !is_separator(&lines[cursor], source, &spans) {
            cursor += 1;
        }
        classify_chunk(source, &lines, &spans, chunk_start..cursor, &mut pending);
    }

    // Assign the tiling provenance ranges. Each block runs from the start of
    // its first line to the start of the next block's first line, so the blank
    // lines between two blocks belong to the earlier one.
    let first_block_start = pending
        .first()
        .map(|p| lines[p.first_line].start)
        .unwrap_or(source.len());
    title_page.provenance = Some(body_start..first_block_start);

    let starts: Vec<usize> = pending.iter().map(|p| lines[p.first_line].start).collect();
    let elements = pending
        .into_iter()
        .enumerate()
        .map(|(index, block)| {
            let start = starts[index];
            let end = starts.get(index + 1).copied().unwrap_or(source.len());
            Element {
                kind: block.kind,
                text: finish_text(block.kind, block.text),
                forced: block.forced,
                dual: block.dual,
                provenance: Some(start..end),
            }
        })
        .collect();

    Script {
        title_page,
        elements,
        bom,
        line_ending,
    }
}

/// Notes and boneyard comments may contain blank lines, which must not split a
/// block. This finds their byte ranges up front so segmentation can ask whether
/// a blank line is really a separator.
///
/// Tolerance differs between the two on purpose (§4.2). An unclosed `/*` runs
/// to the end of the file, which is what every Fountain implementation does. An
/// unclosed `[[` is *not* a note: while the user is typing one, treating the
/// rest of the script as a comment would make every block below the caret
/// change kind between keystrokes.
fn protected_spans(source: &str, from: usize) -> Vec<Range<usize>> {
    let bytes = source.as_bytes();
    let notes = syntax::matched_spans(bytes, b"[[", b"]]");
    let boneyards = syntax::matched_spans(bytes, b"/*", b"*/");
    let mut spans = Vec::new();
    let mut index = from;

    while index + 1 < bytes.len() {
        if &bytes[index..index + 2] == b"/*" {
            let end = span_at(&boneyards, index).map_or(bytes.len(), |span| span.end);
            spans.push(index..end);
            index = end;
        } else if &bytes[index..index + 2] == b"[[" {
            match span_at(&notes, index) {
                Some(span) => {
                    spans.push(span.clone());
                    index = span.end;
                }
                None => index += 2,
            }
        } else {
            index += 1;
        }
    }

    spans
}

fn span_at(spans: &[Range<usize>], position: usize) -> Option<&Range<usize>> {
    spans
        .binary_search_by_key(&position, |span| span.start)
        .ok()
        .map(|index| &spans[index])
}

/// Whether `position` is inside a span rather than at its edge. A line that
/// *starts* a note is still a line the segmenter may act on; the lines it
/// continues onto are not.
///
/// Spans come out of [`protected_spans`] sorted and disjoint, so this is a
/// binary search rather than a scan: a script that is mostly boneyard would
/// otherwise make segmentation quadratic in its own comments.
fn inside_span(spans: &[Range<usize>], position: usize) -> bool {
    candidate(spans, position).is_some_and(|span| span.start < position && position < span.end)
}

/// A protected span is a standalone element only if its closing line contains
/// no further visible text. Otherwise the entire line remains Action.
fn span_stands_alone(source: &str, spans: &[Range<usize>], position: usize) -> bool {
    let Some(span) = candidate(spans, position).filter(|span| span.start == position) else {
        return false;
    };
    source[span.end..]
        .split('\n')
        .next()
        .unwrap_or_default()
        .trim()
        .is_empty()
}

/// The last span that begins at or before `position` — the only one that can
/// contain it.
fn candidate(spans: &[Range<usize>], position: usize) -> Option<&Range<usize>> {
    let at = spans.partition_point(|span| span.start <= position);
    at.checked_sub(1).map(|index| &spans[index])
}

fn is_separator(line: &Line, source: &str, spans: &[Range<usize>]) -> bool {
    line.is_blank(source) && !inside_span(spans, line.start)
}

/// Title page: `Key: value` pairs at the very top of the file, terminated by a
/// blank line (§4.1). Returns the page and the line index where the body
/// starts.
fn parse_title_page(source: &str, lines: &[Line], spans: &[Range<usize>]) -> (TitlePage, usize) {
    let mut page = TitlePage::default();
    let Some(first) = lines.first() else {
        return (page, 0);
    };
    if !looks_like_title_key(first.content(source)) {
        return (page, 0);
    }

    let mut index = 0;
    while index < lines.len() && !is_separator(&lines[index], source, spans) {
        let content = lines[index].content(source);
        if content.starts_with([' ', '\t']) {
            // An indented line continues the previous value even if it happens
            // to contain a colon — "Contact:\n   me@example.com" is one value.
            if let Some(entry) = page.entries.last_mut() {
                if !entry.value.is_empty() {
                    entry.value.push('\n');
                }
                entry.value.push_str(content.trim());
            }
        } else if let Some((key, value)) = key_value(content) {
            page.entries.push(TitleEntry {
                field: TitleField::from_key(key),
                value: value.trim().to_string(),
            });
        } else {
            break;
        }
        index += 1;
    }

    (page, index)
}

/// Splits `Key: value`, rejecting anything that is not plausibly a key.
///
/// The character set matters: a scene heading like `INT. HOUSE: THE KITCHEN`
/// contains a colon, and only the `.` in its key half keeps it from being read
/// as a title page when it opens a file.
/// Whether a line at the very top of a file opens a title page.
///
/// An unknown key with nothing after the colon is almost certainly not one:
/// scripts that open with `FADE IN:` are common, and swallowing that line into
/// the title page would make it vanish from the editor. The serialiser asks the
/// same question in reverse, so that an Action block which happens to look like
/// a key gets a `!` when it is written at the top of a file.
pub(crate) fn looks_like_title_key(line: &str) -> bool {
    match key_value(line) {
        Some((key, value)) => {
            !(value.trim().is_empty() && matches!(TitleField::from_key(key), TitleField::Other(_)))
        }
        None => false,
    }
}

fn key_value(line: &str) -> Option<(&str, &str)> {
    let (key, value) = line.split_once(':')?;
    let plausible = !key.trim().is_empty()
        && key
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, ' ' | '\t' | '-' | '_'));
    plausible.then_some((key, value))
}

/// Classifies one chunk of adjacent non-blank lines into blocks.
fn classify_chunk(
    source: &str,
    lines: &[Line],
    spans: &[Range<usize>],
    chunk: Range<usize>,
    out: &mut Vec<Pending>,
) {
    let base = out.len();
    let mut index = chunk.start;

    while index < chunk.end {
        let line = lines[index];
        let raw = line.content(source);
        let leading = raw.len() - raw.trim_start().len();
        let head = raw.trim_start();
        let trimmed = raw.trim();
        let previous = (out.len() > base).then(|| out[out.len() - 1].kind);

        // A line that continues a note or a boneyard comment always belongs to
        // the block that opened it, whatever it looks like.
        if inside_span(spans, line.start) && out.len() > base {
            append(out, index, raw);
            index += 1;
            continue;
        }

        // Dialogue context (§4.1): a line directly after a cue, a parenthetical
        // or another dialogue line is part of that speech. This is checked
        // before markers so that a line of dialogue beginning with `=` or `>`
        // stays dialogue instead of becoming a synopsis.
        if let Some(previous) = previous.filter(|kind| kind.opens_dialogue()) {
            if syntax::is_parenthetical(trimmed) {
                out.push(new_block(
                    BlockKind::Parenthetical,
                    trimmed,
                    false,
                    false,
                    index,
                ));
            } else if previous == BlockKind::Dialogue {
                append(out, index, raw);
            } else {
                out.push(new_block(BlockKind::Dialogue, raw, false, false, index));
            }
            index += 1;
            continue;
        }

        // Boneyard and standalone notes. Both may span lines; the span table
        // above guarantees the chunk already contains all of them.
        if let Some(kind) = syntax::protected_kind(head) {
            let position = line.start + leading;
            if span_stands_alone(source, spans, position) {
                out.push(new_block(kind, head, false, false, index));
                index += 1;
                continue;
            }
        }

        // Explicit markers.
        if let Some((marker, text)) = syntax::marker_of(head) {
            if marker == Marker::Action && previous == Some(BlockKind::Action) {
                // A `!` on the second line of an action paragraph is how the
                // serialiser protects a line that would otherwise be misread.
                // Merging keeps the block structure stable across a round trip.
                append(out, index, text);
            } else if marker == Marker::Character {
                let (name, dual) = match text.strip_suffix('^') {
                    Some(name) => (name.trim_end(), true),
                    None => (text, false),
                };
                out.push(new_block(BlockKind::Character, name, true, dual, index));
            } else {
                out.push(new_block(
                    marker.kind(),
                    text,
                    marker.forces(),
                    false,
                    index,
                ));
            }
            index += 1;
            continue;
        }

        // Rules that depend on a blank line before the line (§4.1). Only the
        // first line of a chunk has one.
        if index == chunk.start {
            if syntax::is_scene_heading(trimmed) {
                out.push(new_block(
                    BlockKind::SceneHeading,
                    trimmed,
                    false,
                    false,
                    index,
                ));
                index += 1;
                continue;
            }
            let last = index + 1 == chunk.end;
            if last && syntax::is_transition(trimmed) {
                out.push(new_block(
                    BlockKind::Transition,
                    trimmed,
                    false,
                    false,
                    index,
                ));
                index += 1;
                continue;
            }
            // A cue must be followed by a non-blank line, or it is just action
            // in capitals.
            if !last {
                if let Some((name, dual)) = syntax::character_of(trimmed) {
                    out.push(new_block(BlockKind::Character, name, false, dual, index));
                    index += 1;
                    continue;
                }
            }
        }

        // Anything else is action, and adjacent action lines are one paragraph.
        if previous == Some(BlockKind::Action) {
            append(out, index, raw);
        } else {
            out.push(new_block(BlockKind::Action, raw, false, false, index));
        }
        index += 1;
    }
}

fn new_block(kind: BlockKind, text: &str, forced: bool, dual: bool, line: usize) -> Pending {
    Pending {
        kind,
        text: text.to_string(),
        forced,
        dual,
        first_line: line,
        last_line: line,
    }
}

fn append(out: &mut [Pending], line: usize, text: &str) {
    if let Some(block) = out.last_mut() {
        block.text.push('\n');
        block.text.push_str(text);
        block.last_line = line;
    }
}

/// Strips the outer delimiters of a note once all of its lines are in.
/// Boneyard text keeps its `/* */`: an Opaque block is defined by round-tripping
/// verbatim, so its text is its source.
fn finish_text(kind: BlockKind, text: String) -> String {
    if kind != BlockKind::Note {
        return text;
    }
    let inner = text
        .strip_prefix("[[")
        .unwrap_or(&text)
        .trim_end()
        .strip_suffix("]]")
        .map(str::to_string);
    inner.unwrap_or(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(source: &str) -> Vec<BlockKind> {
        parse(source).elements.iter().map(|e| e.kind).collect()
    }

    fn texts(source: &str) -> Vec<String> {
        parse(source)
            .elements
            .iter()
            .map(|e| e.text.clone())
            .collect()
    }

    /// The invariant everything else depends on.
    fn assert_tiles(source: &str) {
        let script = parse(source);
        let mut cursor = if script.bom { '\u{feff}'.len_utf8() } else { 0 };
        let title = script.title_page.provenance.clone().unwrap();
        assert_eq!(title.start, cursor, "title page starts late in {source:?}");
        cursor = title.end;
        for element in &script.elements {
            let range = element.provenance.clone().unwrap();
            assert_eq!(range.start, cursor, "gap before {element:?} in {source:?}");
            assert!(range.start <= range.end);
            cursor = range.end;
        }
        assert_eq!(cursor, source.len(), "tiling stopped short of {source:?}");
    }

    #[test]
    fn a_minimal_scene() {
        let source = "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\nHello.\n";
        assert_eq!(
            kinds(source),
            [
                BlockKind::SceneHeading,
                BlockKind::Action,
                BlockKind::Character,
                BlockKind::Dialogue
            ]
        );
        assert_eq!(texts(source)[3], "Hello.");
        assert_tiles(source);
    }

    #[test]
    fn dialogue_runs_until_a_blank_line() {
        let source = "JOHN\n(quietly)\nOne.\nTwo.\n\nAction.\n";
        assert_eq!(
            kinds(source),
            [
                BlockKind::Character,
                BlockKind::Parenthetical,
                BlockKind::Dialogue,
                BlockKind::Action
            ]
        );
        assert_eq!(texts(source)[2], "One.\nTwo.");
        assert_tiles(source);
    }

    #[test]
    fn a_cue_with_nothing_after_it_is_action() {
        assert_eq!(kinds("JOHN\n"), [BlockKind::Action]);
        assert_eq!(kinds("@JOHN\n"), [BlockKind::Character]);
    }

    #[test]
    fn caps_after_a_cue_stay_dialogue() {
        // MARY is not preceded by a blank line, so §4.1 makes it dialogue.
        let source = "JOHN\nHello.\nMARY\nHi.\n";
        assert_eq!(kinds(source), [BlockKind::Character, BlockKind::Dialogue]);
        assert_eq!(texts(source)[1], "Hello.\nMARY\nHi.");
    }

    #[test]
    fn dual_dialogue_marks_the_cue() {
        let script = parse("JOHN\nHi.\n\nMARY ^\nHi back.\n");
        assert!(!script.elements[0].dual);
        assert!(script.elements[2].dual);
        assert_eq!(script.elements[2].text, "MARY");
    }

    #[test]
    fn forced_prefixes_set_forced_and_leave_the_text() {
        let script = parse(
            ".SNOWY EXTERIOR\n\n@mccLANE\nYippee.\n\n>BURN TO PINK:\n\n!INT. NOT A HEADING\n",
        );
        let kinds: Vec<_> = script.elements.iter().map(|e| e.kind).collect();
        assert_eq!(
            kinds,
            [
                BlockKind::SceneHeading,
                BlockKind::Character,
                BlockKind::Dialogue,
                BlockKind::Transition,
                BlockKind::Action
            ]
        );
        assert!(script
            .elements
            .iter()
            .all(|e| e.forced || e.kind == BlockKind::Dialogue));
        assert_eq!(script.elements[0].text, "SNOWY EXTERIOR");
        assert_eq!(script.elements[1].text, "mccLANE");
        assert_eq!(script.elements[4].text, "INT. NOT A HEADING");
    }

    #[test]
    fn sections_synopses_lyrics_and_page_breaks() {
        let source = "# Act One\n\n## Sequence\n\n= A synopsis.\n\n~Fly me to the moon\n\n===\n";
        assert_eq!(
            kinds(source),
            [
                BlockKind::Section { level: 1 },
                BlockKind::Section { level: 2 },
                BlockKind::Synopsis,
                BlockKind::Lyric,
                BlockKind::PageBreak
            ]
        );
        assert_eq!(texts(source)[0], "Act One");
        assert_eq!(texts(source)[4], "");
        assert_tiles(source);
    }

    #[test]
    fn centered_text_drops_its_markers() {
        let script = parse("> THE END <\n");
        assert_eq!(script.elements[0].kind, BlockKind::Centered);
        assert_eq!(script.elements[0].text, "THE END");
    }

    #[test]
    fn a_transition_needs_a_blank_line_on_both_sides() {
        assert_eq!(
            kinds("Action.\n\nCUT TO:\n\nINT. HOUSE - DAY\n")[1],
            BlockKind::Transition
        );
    }

    #[test]
    fn notes_and_boneyard_may_span_blank_lines() {
        let source =
            "[[ a note\n\nstill the note ]]\n\n/* boneyard\n\nstill boneyard */\n\nAction.\n";
        assert_eq!(
            kinds(source),
            [BlockKind::Note, BlockKind::Opaque, BlockKind::Action]
        );
        assert_eq!(texts(source)[0], " a note\n\nstill the note ");
        assert!(texts(source)[1].starts_with("/*"));
        assert_tiles(source);
    }

    #[test]
    fn nested_notes_and_boneyards_match_at_their_outer_delimiter() {
        let source = concat!(
            "[[ outer [[ inner ]] outer ]]\n\n",
            "/* outer /* inner */ outer */\n",
        );
        assert_eq!(kinds(source), [BlockKind::Note, BlockKind::Opaque]);
        assert_eq!(texts(source)[0], " outer [[ inner ]] outer ");
        assert_eq!(texts(source)[1], "/* outer /* inner */ outer */");
        assert_tiles(source);
    }

    #[test]
    fn protected_spans_with_visible_text_after_the_close_are_action() {
        let source = concat!(
            "[[ note\nstill note ]] VISIBLE\n\n",
            "/* hidden\nstill hidden */ VISIBLE\n",
        );
        assert_eq!(kinds(source), [BlockKind::Action, BlockKind::Action]);
        assert_eq!(texts(source)[0], "[[ note\nstill note ]] VISIBLE");
        assert_eq!(texts(source)[1], "/* hidden\nstill hidden */ VISIBLE");
        assert_tiles(source);
    }

    #[test]
    fn an_unclosed_note_is_ordinary_text() {
        let source = "[[ unfinished\n\nINT. HOUSE - DAY\n";
        assert_eq!(kinds(source), [BlockKind::Action, BlockKind::SceneHeading]);
        assert_tiles(source);
    }

    #[test]
    fn an_unclosed_note_does_not_suppress_a_later_note() {
        let source = "[[ unfinished\n\n[[ existing ]]\n";
        assert_eq!(kinds(source), [BlockKind::Action, BlockKind::Note]);
        assert_eq!(texts(source)[1], " existing ");
        assert_tiles(source);
    }

    #[test]
    fn an_unclosed_boneyard_runs_to_the_end() {
        let source = "Action.\n\n/* forever\n\nINT. HOUSE - DAY\n";
        assert_eq!(kinds(source), [BlockKind::Action, BlockKind::Opaque]);
        assert_tiles(source);
    }

    #[test]
    fn title_page_with_multi_line_values_and_unknown_keys() {
        let source = "Title:\n   _**BIG FISH**_\n   Part Two\nCredit: Written by\nRevision Colour: Blue\n\nINT. HOUSE - DAY\n";
        let script = parse(source);
        assert_eq!(
            script.title_page.get(&TitleField::Title),
            Some("_**BIG FISH**_\nPart Two")
        );
        assert_eq!(
            script.title_page.get(&TitleField::Credit),
            Some("Written by")
        );
        assert_eq!(
            script
                .title_page
                .get(&TitleField::Other("Revision Colour".into())),
            Some("Blue")
        );
        assert_eq!(script.elements.len(), 1);
        assert_tiles(source);
    }

    #[test]
    fn an_unindented_non_key_terminates_the_title_page() {
        let source = "Title: Big Fish\nThis is body action.\n\nINT. HOUSE - DAY\n";
        let script = parse(source);
        assert_eq!(script.title_page.get(&TitleField::Title), Some("Big Fish"));
        assert_eq!(
            script
                .elements
                .iter()
                .map(|element| (element.kind, element.text.as_str()))
                .collect::<Vec<_>>(),
            [
                (BlockKind::Action, "This is body action."),
                (BlockKind::SceneHeading, "INT. HOUSE - DAY"),
            ]
        );
        assert_tiles(source);
    }

    #[test]
    fn a_scene_heading_containing_a_colon_is_not_a_title_page() {
        let source = "INT. HOUSE: THE KITCHEN - DAY\n\nAction.\n";
        let script = parse(source);
        assert!(script.title_page.is_empty());
        assert_eq!(script.elements[0].kind, BlockKind::SceneHeading);
    }

    #[test]
    fn a_bom_is_recorded_and_excluded_from_the_ranges() {
        let source = "\u{feff}INT. HOUSE - DAY\n";
        let script = parse(source);
        assert!(script.bom);
        assert_eq!(script.elements.len(), 1);
        assert_tiles(source);
    }

    #[test]
    fn crlf_and_trailing_whitespace_survive_in_the_ranges() {
        let source = "INT. HOUSE - DAY\r\n\r\nAction.  \r\n";
        let script = parse(source);
        assert_eq!(script.line_ending, crate::LineEnding::CrLf);
        assert_eq!(script.elements[0].text, "INT. HOUSE - DAY");
        assert_eq!(script.elements[1].text, "Action.  ");
        assert_tiles(source);
    }

    #[test]
    fn degenerate_inputs_still_tile() {
        for source in [
            "",
            "\n",
            "\n\n\n",
            "   \n\t\n",
            "\u{feff}",
            "Title: x\n",
            "Title: x\n\n",
            "a",
            "===",
            "/*",
            "[[",
            "@",
            ".",
            ">",
            "#",
            "~",
            "!",
            "^",
            "café 日本 🎬\n",
        ] {
            assert_tiles(source);
        }
    }
}
