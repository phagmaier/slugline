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
    let elements: Vec<(usize, &ElementRef<'_>)> = out
        .elements
        .iter()
        .enumerate()
        .filter(|(_, element)| !vanishes(element))
        .collect();

    for (index, &(original_index, element)) in elements.iter().enumerate() {
        let previous = index.checked_sub(1).map(|i| elements[i].1.kind);
        let next = elements.get(index + 1).map(|(_, element)| element.kind);

        // The blank line that ends a title page is written only once something
        // follows it, so a document that is nothing but a title page still ends
        // with exactly one newline.
        if index == 0 && owes_title_separator {
            result.push_str(nl);
        }

        // Filtering an edited-away dialogue block can orphan an untouched cue.
        // Rewriting that cue adds `@`, rather than letting it reopen as Action.
        let removed_dialogue_context = out
            .elements
            .get(original_index + 1)
            .is_some_and(|element| element.kind.continues_dialogue() && vanishes(element));
        let orphaned_character = element.kind == BlockKind::Character
            && !element.forced
            && removed_dialogue_context
            && !next.is_some_and(BlockKind::continues_dialogue);
        if orphaned_character {
            if let Some(text) = verbatim(out.source, &element.provenance) {
                if !result.is_empty() && !ends_with_terminator(&result) {
                    result.push_str(nl);
                }
                push_forced_character_verbatim(&mut result, text);
                if next.is_some_and(|next| needs_blank_between(element.kind, next))
                    && !ends_with_blank_line(&result)
                {
                    result.push_str(nl);
                }
                continue;
            }
        }
        let original = (!orphaned_character)
            .then(|| verbatim(out.source, &element.provenance))
            .flatten();
        match original {
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
    let eaten_at_top = |line: &str| swallowed_by_title_page(at_top, title_page, line);
    match element.kind {
        BlockKind::SceneHeading => {
            let forced = element.forced || !syntax::is_scene_heading(text) || eaten_at_top(text);
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
                || !next.is_some_and(BlockKind::continues_dialogue)
                || eaten_at_top(&cue);
            push_line(result, &prefixed("@", forced, &cue), nl);
        }
        BlockKind::Transition => {
            // `=== TO:` is a transition by §4.1 and a synopsis by its first
            // character; `INT. TO:` is a transition and a scene heading. The
            // parser resolves both the other way, so the marker settles it.
            let forced = element.forced
                || !syntax::is_transition(text)
                || syntax::marker_of(text).is_some()
                || syntax::is_scene_heading(text)
                || eaten_at_top(text);
            push_line(result, &prefixed(">", forced, text), nl);
        }
        BlockKind::Action => {
            let protected_starts = syntax::standalone_protected_starts(text);
            let mut offset = 0;
            for (index, line) in text.split('\n').enumerate() {
                let first = index == 0;
                let leading = line.len() - line.trim_start().len();
                let opens_protected = protected_starts.binary_search(&(offset + leading)).is_ok();
                let ambiguous = if first {
                    element.forced
                        || opens_another_element(line, text.contains('\n'))
                        || opens_protected
                        || eaten_at_top(line)
                } else {
                    syntax::marker_of(line.trim_start()).is_some() || opens_protected
                };
                push_line(result, &prefixed("!", ambiguous, line), nl);
                offset += line.len();
                if offset < text.len() {
                    offset += 1;
                }
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
        BlockKind::Note if syntax::note_text_is_balanced(text) => {
            push_lines(result, &format!("[[{text}]]"), nl);
        }
        BlockKind::Note => {
            // While a nested note delimiter is incomplete, wrapping it would
            // expose the writer's own delimiters as user text on reopen. Keep
            // the user's text exact as forced Action until it is balanced.
            for line in text.split('\n') {
                push_line(result, &format!("!{line}"), nl);
            }
        }
        BlockKind::PageBreak => {
            push_line(result, "===", nl);
            // PageBreak normally has no text. If an invalid raw ElementRef does
            // carry some, preserve it as forced Action rather than dropping it.
            if !text.is_empty() {
                for line in text.split('\n') {
                    push_line(result, &format!("!{line}"), nl);
                }
            }
        }
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

/// Whether writing `line` without a marker here would let the title-page parser
/// eat it.
///
/// The title page is read only at the very top of a file, and only when the
/// first line looks like a key — so this is the one reason a block needs a
/// marker that has nothing to do with what the block *is*. `parse_title_page`
/// then goes on consuming until a blank line, so a swallowed block usually takes
/// its neighbour's first line with it.
///
/// Stated once and asked by every kind that can be written bare, rather than
/// left to each kind's own rules to imply. Three of the four imply it today:
/// `is_scene_heading` and `character_of` both reject the `Key: value` shape, so
/// only `Transition` reaches it — `IN: TO:` is a transition by §4.1 and a title
/// key by `looks_like_title_key`, and the parser resolves it the other way
/// (F16). Relying on that coincidence would make a future loosening of either
/// recognition rule reopen the hole silently, and losing a block on reopen is
/// exactly what ADR 0007's round-trip guarantee exists to prevent.
fn swallowed_by_title_page(at_top: bool, title_page: &TitlePage, line: &str) -> bool {
    at_top && title_page.is_empty() && looks_like_title_key(line)
}

fn prefixed(marker: &str, apply: bool, text: &str) -> String {
    if apply {
        format!("{marker}{text}")
    } else {
        text.to_string()
    }
}

fn push_forced_character_verbatim(result: &mut String, text: &str) {
    let marker_at = text
        .char_indices()
        .find_map(|(index, c)| (!c.is_whitespace()).then_some(index))
        .unwrap_or(0);
    result.push_str(&text[..marker_at]);
    result.push('@');
    result.push_str(&text[marker_at..]);
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
    use crate::{parse, Element, TitleEntry, TitleField};

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

    /// Writes elements built by hand, which is what `SetKind` in the editor
    /// produces: a block whose kind the writer chose and whose text was never
    /// marked. No Fountain source parses to one of these, so `canonical_text`
    /// cannot reach them.
    fn write_built(title: &TitlePage, built: &[(BlockKind, &str)]) -> String {
        let elements: Vec<Element> = built
            .iter()
            .map(|(kind, text)| Element {
                kind: *kind,
                text: (*text).to_owned(),
                forced: false,
                dual: false,
                provenance: None,
            })
            .collect();
        let refs: Vec<ElementRef<'_>> = elements.iter().map(Element::as_ref).collect();
        serialise(&Output {
            title_page: title,
            elements: &refs,
            source: None,
            bom: false,
            line_ending: LineEnding::Lf,
        })
    }

    fn kinds_and_text(source: &str) -> Vec<(BlockKind, String)> {
        parse(source)
            .elements
            .iter()
            .map(|element| (element.kind, element.text.clone()))
            .collect()
    }

    /// F16. `IN: TO:` is a transition by §4.1 and a title-page key by
    /// `looks_like_title_key`, and at the top of a file the parser resolves it
    /// the other way — so written bare the block did not come back at all.
    #[test]
    fn a_block_that_would_be_read_as_a_title_key_is_marked_at_the_top() {
        let empty = TitlePage::default();
        let written = write_built(&empty, &[(BlockKind::Transition, "IN: TO:")]);
        assert_eq!(written, ">IN: TO:\n");
        assert_eq!(
            kinds_and_text(&written),
            [(BlockKind::Transition, "IN: TO:".to_owned())]
        );
        assert!(parse(&written).title_page.is_empty());

        // The same text below the top needs nothing: the title page has ended.
        let below = write_built(
            &empty,
            &[
                (BlockKind::Action, "She waits."),
                (BlockKind::Transition, "IN: TO:"),
            ],
        );
        assert_eq!(below, "She waits.\n\nIN: TO:\n");
        assert_eq!(kinds_and_text(&below)[1].1, "IN: TO:");

        // Nor when there is a title page, because then the blank line after it
        // has already closed it.
        let after_title = write_built(
            &TitlePage {
                entries: vec![TitleEntry {
                    field: TitleField::Title,
                    value: "Heat".to_owned(),
                }],
                provenance: None,
            },
            &[(BlockKind::Transition, "IN: TO:")],
        );
        assert!(after_title.ends_with("IN: TO:\n"));
        assert_eq!(kinds_and_text(&after_title)[0].1, "IN: TO:");
    }

    /// The other three kinds that can be written bare. Their own recognition
    /// rules already keep them out of the title page, and this says so out
    /// loud: if `character_of` or `is_scene_heading` is ever loosened to accept
    /// a `Key: value` line, the shared check in `swallowed_by_title_page` is
    /// what has to catch it, and this test is where that shows up.
    #[test]
    fn no_kind_written_bare_at_the_top_is_eaten_by_the_title_page() {
        let empty = TitlePage::default();
        let cases: [&[(BlockKind, &str)]; 4] = [
            &[(BlockKind::Transition, "IN: TO:")],
            &[
                (BlockKind::Character, "MARY: HELLO"),
                (BlockKind::Dialogue, "Hi."),
            ],
            &[(BlockKind::SceneHeading, "INT: HOUSE")],
            &[(BlockKind::Action, "Note: something")],
        ];
        for built in cases {
            let written = write_built(&empty, built);
            let back = kinds_and_text(&written);
            assert!(
                parse(&written).title_page.is_empty(),
                "{built:?} became a title page: {written:?}"
            );
            assert_eq!(
                back.len(),
                built.len(),
                "{built:?} did not come back whole: {written:?} -> {back:?}"
            );
            for (index, (kind, text)) in built.iter().enumerate() {
                assert_eq!((back[index].0, back[index].1.as_str()), (*kind, *text));
            }
        }
    }

    #[test]
    fn a_second_action_line_that_looks_like_a_marker_is_protected() {
        let written = canonical_text("Action.\n!# still action\n");
        assert_eq!(written, "Action.\n!# still action\n");
        assert_stable("Action.\n!# still action\n");
    }

    #[test]
    fn action_lines_that_open_protected_spans_are_forced() {
        for protected in ["[[not a note]]", "/* not boneyard */"] {
            let first = format!("!{protected}\n");
            assert_eq!(canonical_text(&first), first);
            assert_stable(&first);

            let later = format!("Action.\n!  {protected}\n");
            assert_eq!(canonical_text(&later), later);
            assert_stable(&later);
        }

        for natural_action in [
            "[[note]] visible\n",
            "[[unfinished\n",
            "/* hidden */ visible\n",
        ] {
            assert_eq!(canonical_text(natural_action), natural_action);
            assert_stable(natural_action);
        }

        assert_eq!(canonical_text("!/* unclosed\n"), "!/* unclosed\n");
        assert_stable("!/* unclosed\n");
    }

    fn remove_dialogue(source: &str) -> String {
        let script = parse(source);
        let elements: Vec<ElementRef<'_>> = script
            .elements
            .iter()
            .map(|element| {
                if element.kind == BlockKind::Dialogue {
                    ElementRef {
                        text: "",
                        provenance: None,
                        ..element.as_ref()
                    }
                } else {
                    element.as_ref()
                }
            })
            .collect();
        serialise(&Output {
            title_page: &script.title_page,
            elements: &elements,
            source: Some(source),
            bom: script.bom,
            line_ending: script.line_ending,
        })
    }

    #[test]
    fn a_verbatim_character_orphaned_by_vanished_dialogue_is_forced() {
        let at_eof = remove_dialogue("JOHN\nHello.\n");
        assert_eq!(at_eof, "@JOHN\n");
        assert_eq!(parse(&at_eof).elements[0].kind, BlockKind::Character);

        let before_action = remove_dialogue("JOHN\nHello.\n\nAction.\n");
        assert_eq!(before_action, "@JOHN\n\nAction.\n");
        assert_eq!(
            parse(&before_action)
                .elements
                .iter()
                .map(|element| element.kind)
                .collect::<Vec<_>>(),
            [BlockKind::Character, BlockKind::Action]
        );
    }

    #[test]
    fn an_already_forced_orphaned_character_stays_verbatim() {
        let written = remove_dialogue("@JOHN  \r\nHello.\r\n");
        assert_eq!(written, "@JOHN  \r\n");
    }

    #[test]
    fn forcing_an_orphaned_character_only_adds_the_marker() {
        let written = remove_dialogue("Action.\n\n  JOHN  \r\nHello.\r\n");
        assert_eq!(written, "Action.\n\n  @JOHN  \r\n");
    }

    #[test]
    fn a_page_break_defensively_preserves_invalid_text() {
        let page_break = ElementRef {
            kind: BlockKind::PageBreak,
            text: "keep this\n[[and this]]",
            forced: false,
            dual: false,
            provenance: None,
        };
        let written = serialise(&Output {
            title_page: &TitlePage::default(),
            elements: &[page_break],
            source: None,
            bom: false,
            line_ending: LineEnding::Lf,
        });
        assert_eq!(written, "===\n!keep this\n![[and this]]\n");
        let reparsed = parse(&written);
        assert_eq!(reparsed.elements[0].kind, BlockKind::PageBreak);
        assert_eq!(reparsed.elements[1].kind, BlockKind::Action);
        assert_eq!(reparsed.elements[1].text, "keep this\n[[and this]]");

        assert_eq!(canonical_text("===\n"), "===\n");
    }

    #[test]
    fn an_unbalanced_note_preserves_user_text_as_action() {
        let note = ElementRef {
            kind: BlockKind::Note,
            text: "note[[",
            forced: false,
            dual: false,
            provenance: None,
        };
        let written = serialise(&Output {
            title_page: &TitlePage::default(),
            elements: &[note],
            source: None,
            bom: false,
            line_ending: LineEnding::Lf,
        });
        assert_eq!(written, "!note[[\n");
        let reparsed = parse(&written);
        assert_eq!(reparsed.elements[0].kind, BlockKind::Action);
        assert_eq!(reparsed.elements[0].text, "note[[");
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
