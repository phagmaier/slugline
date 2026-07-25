//! The serialiser.
//!
//! Two paths, and which one a block takes is the whole of §3.2:
//!
//! * **Verbatim** — the block still has its provenance range, so its original
//!   bytes are copied back out. Line endings, trailing spaces, tabs, the
//!   writer's own spacing: all of it survives because none of it is touched.
//! * **Canonical** — the block was edited, so it is written from the model.
//!   Element markers are re-added where a plain reading of the text would come
//!   back as a different kind, which is what keeps an edit to one block from
//!   changing the meaning of another.
//!
//! Because the parser's provenance ranges tile the source, a document nobody
//! has edited takes the verbatim path for every block and the output is the
//! input, byte for byte.

use std::ops::Range;

use crate::parse::looks_like_title_key;
use crate::syntax;
use crate::{BlockKind, ElementRef, LineEnding, TitlePage};

/// Everything the serialiser needs. `document` builds one of these from its own
/// blocks without copying their text.
pub struct Output<'a> {
    pub title_page: &'a TitlePage,
    pub elements: &'a [ElementRef<'a>],
    /// The bytes the document was parsed from. Provenance ranges index into
    /// this; without it every block takes the canonical path.
    pub source: Option<&'a str>,
    pub bom: bool,
    pub line_ending: LineEnding,
}

/// Writes a document back to Fountain.
///
/// Total: no input produces a panic. An out-of-range or misaligned provenance
/// range falls back to the canonical path rather than slicing blindly.
pub fn serialise(out: &Output<'_>) -> String {
    let nl = out.line_ending.as_str();
    // The body is assembled on its own and the BOM prefixed at the end: a BOM
    // is not a line, and letting it into the buffer would make every
    // "are we at the start of a line?" question answer wrongly for the first
    // block.
    let mut result = String::new();

    let mut owes_title_separator = false;
    match verbatim(out.source, &out.title_page.provenance) {
        Some(text) => result.push_str(text),
        None => {
            canonical_title_page(&mut result, out.title_page, nl);
            owes_title_separator = !result.is_empty();
        }
    }

    // An edited block with no text left has no Fountain representation: a blank
    // line is a separator, so writing one would split its neighbours apart
    // instead. Dropping it here — rather than emitting an empty line — is what
    // keeps a cue whose dialogue was just deleted from silently becoming
    // action. Nothing is lost; the block has no text to lose.
    let elements: Vec<&ElementRef<'_>> = out.elements.iter().filter(|e| !vanishes(e)).collect();

    for (index, element) in elements.iter().enumerate() {
        let previous = index.checked_sub(1).map(|i| elements[i].kind);
        let next = elements.get(index + 1).map(|e| e.kind);

        // The blank line that ends a title page is written only once something
        // follows it, so a document that is nothing but a title page still ends
        // with exactly one newline.
        if index == 0 && owes_title_separator {
            result.push_str(nl);
        }

        match verbatim(out.source, &element.provenance) {
            Some(text) => {
                // A verbatim block carries the blank lines that followed it, so
                // it needs no separator of its own. The guard is for the block
                // after an edited one at the end of a file that had no final
                // newline.
                if !result.is_empty() && !ends_with_terminator(&result) {
                    result.push_str(nl);
                }
                result.push_str(text);
            }
            None => {
                separate(&mut result, previous, element.kind, nl);
                canonical(&mut result, element, index == 0, out.title_page, next, nl);
                // The next block may be verbatim, in which case nobody else
                // will write the blank line between them.
                if next.is_some_and(|next| needs_blank_between(element.kind, next)) {
                    result.push_str(nl);
                }
            }
        }
    }

    if out.bom {
        return format!("\u{feff}{result}");
    }
    result
}

/// Whether a block would write nothing at all.
///
/// Only ever true for an edited block: the parser cannot produce an empty
/// Action, Dialogue, Parenthetical or Opaque block, because the blank line that
/// would hold one is a separator.
fn vanishes(element: &ElementRef<'_>) -> bool {
    element.provenance.is_none()
        && element.text.is_empty()
        && matches!(
            element.kind,
            BlockKind::Action
                | BlockKind::Dialogue
                | BlockKind::Parenthetical
                | BlockKind::Opaque
                // A lone `.` is not a forced heading — it is the shortest line
                // that could be one, and Fountain reads it as action.
                | BlockKind::SceneHeading
        )
}

/// Two blocks are written adjacent only where the parser reads them as one
/// speech; everything else is separated by a blank line.
pub fn needs_blank_between(previous: BlockKind, next: BlockKind) -> bool {
    !(previous.opens_dialogue() && next.continues_dialogue())
}

fn verbatim<'a>(source: Option<&'a str>, provenance: &Option<Range<usize>>) -> Option<&'a str> {
    source?.get(provenance.clone()?)
}

/// Brings the output to the start of a line, and to a blank line if the two
/// kinds must not be read as one speech. Never adds a separator that is already
/// there, so a canonical block after a verbatim one does not gain a blank line.
fn separate(result: &mut String, previous: Option<BlockKind>, kind: BlockKind, nl: &str) {
    if result.is_empty() {
        return;
    }
    if !ends_with_terminator(result) {
        result.push_str(nl);
    }
    if previous.is_some_and(|previous| needs_blank_between(previous, kind))
        && !ends_with_blank_line(result)
    {
        result.push_str(nl);
    }
}

/// Whether the output is at the start of a line.
///
/// Asked of the terminator rather than of *this document's* terminator: a file
/// may mix them, and verbatim bytes are whatever the file had. A CRLF document
/// whose second line ended with a bare LF is still at the start of a line.
fn ends_with_terminator(text: &str) -> bool {
    text.ends_with('\n')
}

/// Whether the output ends with a blank line — a terminator, and before it
/// either another terminator or nothing at all.
fn ends_with_blank_line(text: &str) -> bool {
    match text.strip_suffix('\n') {
        Some(rest) => {
            let rest = rest.strip_suffix('\r').unwrap_or(rest);
            rest.is_empty() || rest.ends_with('\n')
        }
        None => false,
    }
}

fn canonical_title_page(result: &mut String, page: &TitlePage, nl: &str) {
    if page.is_empty() {
        return;
    }
    for entry in page.in_canonical_order() {
        let mut values = entry.value.split('\n');
        let first = values.next().unwrap_or_default();
        result.push_str(entry.field.key());
        result.push(':');
        if !first.is_empty() {
            result.push(' ');
            result.push_str(first);
        }
        result.push_str(nl);
        for line in values {
            result.push_str("   ");
            result.push_str(line);
            result.push_str(nl);
        }
    }
}

fn canonical(
    result: &mut String,
    element: &ElementRef<'_>,
    at_top: bool,
    title_page: &TitlePage,
    next: Option<BlockKind>,
    nl: &str,
) {
    let text = element.text;
    match element.kind {
        BlockKind::SceneHeading => {
            let forced = element.forced || !syntax::is_scene_heading(text);
            // `..` is Fountain's escape for a line that starts with a dot, not
            // a heading, so a forced heading whose own text starts with one is
            // written with a space after the marker. The parser trims there, so
            // the space is not part of the text on the way back.
            let marker = if forced && text.starts_with('.') {
                ". "
            } else {
                "."
            };
            push_line(result, &prefixed(marker, forced, text), nl);
        }
        BlockKind::Character => {
            let cue = if element.dual {
                format!("{text} ^")
            } else {
                text.to_string()
            };
            // A cue is only read back as a cue if a non-blank line follows it,
            // so a cue whose dialogue was deleted has to say so with `@`. And a
            // character called INT. is a scene heading unless it says
            // otherwise — the heading rule is checked first.
            let forced = element.forced
                || syntax::character_of(&cue).is_none()
                || syntax::is_scene_heading(&cue)
                || syntax::marker_of(&cue).is_some()
                || !next.is_some_and(BlockKind::continues_dialogue);
            push_line(result, &prefixed("@", forced, &cue), nl);
        }
        BlockKind::Transition => {
            // `=== TO:` is a transition by §4.1 and a synopsis by its first
            // character; `INT. TO:` is a transition and a scene heading. The
            // parser resolves both the other way, so the marker settles it.
            let forced = element.forced
                || !syntax::is_transition(text)
                || syntax::marker_of(text).is_some()
                || syntax::is_scene_heading(text);
            push_line(result, &prefixed(">", forced, text), nl);
        }
        BlockKind::Action => {
            for (index, line) in text.split('\n').enumerate() {
                let first = index == 0;
                let ambiguous = if first {
                    element.forced
                        || opens_another_element(line, text.contains('\n'))
                        || (at_top && title_page.is_empty() && looks_like_title_key(line))
                } else {
                    syntax::marker_of(line.trim_start()).is_some()
                };
                push_line(result, &prefixed("!", ambiguous, line), nl);
            }
        }
        BlockKind::Centered => push_line(result, &format!("> {text} <"), nl),
        BlockKind::Lyric => push_line(result, &format!("~{text}"), nl),
        BlockKind::Section { level } => {
            let hashes = "#".repeat(level.clamp(1, 6) as usize);
            let line = if text.is_empty() {
                hashes
            } else {
                format!("{hashes} {text}")
            };
            push_line(result, &line, nl);
        }
        BlockKind::Synopsis => {
            let line = if text.is_empty() {
                "=".to_string()
            } else {
                format!("= {text}")
            };
            push_line(result, &line, nl);
        }
        BlockKind::Note => push_lines(result, &format!("[[{text}]]"), nl),
        BlockKind::PageBreak => push_line(result, "===", nl),
        // Dialogue, Parenthetical and Opaque are written as they stand.
        // Dialogue and a parenthetical have no marker of their own in Fountain:
        // they are defined by the cue above them, which the separator rules put
        // in place.
        BlockKind::Dialogue | BlockKind::Parenthetical | BlockKind::Opaque => {
            push_lines(result, text, nl)
        }
    }
}

/// Whether a line, read as the first line of a block, would come back as
/// something other than Action.
fn opens_another_element(line: &str, has_more_lines: bool) -> bool {
    let head = line.trim_start();
    let trimmed = line.trim();
    syntax::marker_of(head).is_some()
        || syntax::is_scene_heading(trimmed)
        || (!has_more_lines && syntax::is_transition(trimmed))
        || (has_more_lines && syntax::character_of(trimmed).is_some())
}

fn prefixed(marker: &str, apply: bool, text: &str) -> String {
    if apply {
        format!("{marker}{text}")
    } else {
        text.to_string()
    }
}

fn push_line(result: &mut String, line: &str, nl: &str) {
    result.push_str(line);
    result.push_str(nl);
}

fn push_lines(result: &mut String, text: &str, nl: &str) {
    for line in text.split('\n') {
        push_line(result, line, nl);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{parse, Element};

    /// Serialises a script whose blocks have all lost their provenance, which
    /// is what an edit to every block would leave behind.
    fn canonical_text(source: &str) -> String {
        let script = parse(source);
        let elements: Vec<ElementRef<'_>> = script
            .elements
            .iter()
            .map(|element| ElementRef {
                provenance: None,
                ..element.as_ref()
            })
            .collect();
        serialise(&Output {
            title_page: &TitlePage {
                entries: script.title_page.entries.clone(),
                provenance: None,
            },
            elements: &elements,
            source: Some(source),
            bom: script.bom,
            line_ending: script.line_ending,
        })
    }

    /// The property the canonical path owes the parser: re-reading what it
    /// wrote gives back the same kinds, the same text, and the same flags.
    fn assert_stable(source: &str) {
        let original = parse(source);
        let written = canonical_text(source);
        let reparsed = parse(&written);

        let before: Vec<(BlockKind, &str, bool, bool)> = original
            .elements
            .iter()
            .map(|e| (e.kind, e.text.as_str(), e.forced, e.dual))
            .collect();
        let after: Vec<(BlockKind, &str, bool, bool)> = reparsed
            .elements
            .iter()
            .map(|e| (e.kind, e.text.as_str(), e.forced, e.dual))
            .collect();
        assert_eq!(
            before, after,
            "unstable canonical form for {source:?}\n{written}"
        );
        // Entry order is allowed to change once — the canonical form reorders
        // the title page by design — but not the keys or the values.
        assert_eq!(
            original.title_page.in_canonical_order(),
            reparsed.title_page.in_canonical_order(),
            "unstable title page for {source:?}"
        );
    }

    #[test]
    fn an_untouched_document_is_copied_back_out() {
        let source = "Title: Big Fish\n\nINT. HOUSE - DAY\r\n\r\nAction with trailing space.  \n\nJOHN\n(quietly)\nHello.\n\n\n";
        let script = parse(source);
        let elements: Vec<ElementRef<'_>> = script.elements.iter().map(Element::as_ref).collect();
        let written = serialise(&Output {
            title_page: &script.title_page,
            elements: &elements,
            source: Some(source),
            bom: script.bom,
            line_ending: script.line_ending,
        });
        assert_eq!(written, source);
    }

    #[test]
    fn canonical_output_ends_with_exactly_one_newline() {
        for source in [
            "INT. HOUSE - DAY\n\nAction.\n\n\n\n",
            "Action with no final newline",
            "JOHN\nHello.\n",
        ] {
            let written = canonical_text(source);
            assert!(written.ends_with('\n'), "{source:?} -> {written:?}");
            assert!(!written.ends_with("\n\n"), "{source:?} -> {written:?}");
        }
    }

    #[test]
    fn markers_are_re_added_where_the_text_would_be_misread() {
        // Action that reads as a scene heading, a cue, a transition, a section.
        assert_eq!(canonical_text("!INT. HOUSE - DAY\n"), "!INT. HOUSE - DAY\n");
        assert_eq!(canonical_text("!CUT TO:\n"), "!CUT TO:\n");
        assert_eq!(canonical_text("!# not a section\n"), "!# not a section\n");
        // A cue with no dialogue under it.
        assert_eq!(canonical_text("@JOHN\n"), "@JOHN\n");
        // A scene heading that does not start with INT/EXT.
        assert_eq!(canonical_text(".SNOWY EXTERIOR\n"), ".SNOWY EXTERIOR\n");
        // Nothing gained where the text speaks for itself.
        assert_eq!(canonical_text("INT. HOUSE - DAY\n"), "INT. HOUSE - DAY\n");
    }

    #[test]
    fn a_second_action_line_that_looks_like_a_marker_is_protected() {
        let written = canonical_text("Action.\n!# still action\n");
        assert_eq!(written, "Action.\n!# still action\n");
        assert_stable("Action.\n!# still action\n");
    }

    #[test]
    fn an_action_opening_a_file_is_protected_from_the_title_page_rule() {
        assert_stable("Revision: Blue\n");
        assert_eq!(canonical_text("!Revision: Blue\n"), "!Revision: Blue\n");
    }

    #[test]
    fn dual_dialogue_survives_the_canonical_form() {
        assert_stable("JOHN\nHi.\n\nMARY ^\nHi back.\n");
    }

    #[test]
    fn crlf_documents_stay_crlf_when_rewritten() {
        let written = canonical_text("INT. HOUSE - DAY\r\n\r\nAction.\r\n");
        assert_eq!(written, "INT. HOUSE - DAY\r\n\r\nAction.\r\n");
    }

    #[test]
    fn the_title_page_is_written_in_canonical_order() {
        let written = canonical_text("Contact: me\nTitle: Big Fish\n\nAction.\n");
        assert!(
            written.starts_with("Title: Big Fish\nContact: me\n\n"),
            "{written}"
        );
        assert_stable("Contact: me\nTitle: Big Fish\n\nAction.\n");
    }

    #[test]
    fn multi_line_title_values_round_trip_through_the_canonical_form() {
        assert_stable("Title:\n   Big Fish\n   Part Two\n\nAction.\n");
    }

    #[test]
    fn every_element_type_survives_the_canonical_form() {
        assert_stable(concat!(
            "Title: Everything\n\n",
            "# Act One\n\n",
            "= A synopsis.\n\n",
            "INT. HOUSE - DAY\n\n",
            "Action happens.\n\n",
            "JOHN\n(quietly)\nHello.\n\n",
            "MARY ^\nHi.\n\n",
            "~Fly me to the moon\n\n",
            "> THE END <\n\n",
            "CUT TO:\n\n",
            "[[ a note ]]\n\n",
            "/* boneyard */\n\n",
            "===\n\n",
            ".FORCED HEADING\n\n",
            "@mccLANE\nYippee.\n",
        ));
    }
}
