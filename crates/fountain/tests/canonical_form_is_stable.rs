//! Property: for a generated random document, `parse(serialise(d))` has the
//! same block kinds and text as `d` (Phase 1, Tests).
//!
//! This is the half of round-tripping that provenance does *not* cover. An
//! untouched file comes back byte for byte because its bytes are copied; a
//! document that has been edited comes back through the canonical writer, and
//! the only thing keeping an edit to one block from changing the meaning of
//! another is that writer's decision about markers and blank lines. So every
//! block here is given no provenance, which is what an edit to all of them
//! would leave.
//!
//! The generator produces **representable** documents: ones the parser could
//! itself have produced. That restriction is not a way of dodging the hard
//! cases — the hard cases are all still in here — but Fountain genuinely cannot
//! express some element sequences (dialogue with no cue above it, two adjacent
//! dialogue blocks, an empty action paragraph), and a property that generated
//! them would be asserting something false about the format rather than
//! something true about this code.

use proptest::prelude::*;
use slugline_fountain::{
    parse, serialise, BlockKind, Element, ElementRef, LineEnding, Output, TitleEntry, TitleField,
    TitlePage,
};

/// Words chosen to land on the parser's edges: element markers, all-caps cues,
/// emphasis markup, non-ASCII, and an astral-plane emoji.
const WORDS: &[&str] = &[
    "Martha", "waits", "the", "kettle", "INT.", "EXT.", "CUT", "TO:", "V.O.", "MARTHA", "DEREK",
    "café", "日本", "🎬", "**bold**", "*italic*", "_under_", "===", "#", "=", "~", "!", "@", "..",
    "...", "-", "'", "&", "%", "(beat)", "TO", "FADE", "IN:",
];

fn phrase() -> impl Strategy<Value = String> {
    proptest::collection::vec(proptest::sample::select(WORDS), 1..6)
        .prop_map(|words| words.join(" "))
        .prop_map(|text| text.trim().to_string())
        .prop_filter("non-empty", |text| !text.is_empty())
}

/// One or more lines that stay inside a single block: none of them blank, so
/// none of them a separator.
fn lines() -> impl Strategy<Value = Vec<String>> {
    proptest::collection::vec(phrase(), 1..4)
}

fn block(kind: BlockKind, text: String, forced: bool, dual: bool) -> Element {
    Element {
        kind,
        text,
        forced,
        dual,
        provenance: None,
    }
}

/// A unit is a run of blocks the parser would produce together — a speech is a
/// cue, an optional parenthetical and its dialogue, and nothing may come
/// between them.
fn unit() -> impl Strategy<Value = Vec<Element>> {
    prop_oneof![
        (phrase(), any::<bool>()).prop_map(|(text, forced)| vec![block(
            BlockKind::SceneHeading,
            text,
            forced,
            false
        )]),
        (lines(), any::<bool>()).prop_map(|(lines, forced)| {
            vec![block(BlockKind::Action, lines.join("\n"), forced, false)]
        }),
        // A speech: cue, maybe a parenthetical, then dialogue.
        (
            phrase(),
            any::<bool>(),
            any::<bool>(),
            proptest::option::of(phrase()),
            lines(),
        )
            .prop_map(|(cue, forced, dual, aside, dialogue)| {
                let cue = cue.trim_end_matches('^').trim_end().to_string();
                let mut blocks = vec![block(
                    BlockKind::Character,
                    if cue.is_empty() { "MARTHA".into() } else { cue },
                    forced,
                    dual,
                )];
                if let Some(aside) = aside {
                    let inner = aside.replace(['(', ')'], "");
                    blocks.push(block(
                        BlockKind::Parenthetical,
                        format!("({inner})"),
                        false,
                        false,
                    ));
                }
                // A dialogue line wrapped in parentheses would come back as a
                // parenthetical, which is the parser being right, not wrong.
                let spoken: Vec<String> = dialogue
                    .into_iter()
                    .map(|line| {
                        if line.starts_with('(') && line.ends_with(')') {
                            format!("{line}.")
                        } else {
                            line
                        }
                    })
                    .collect();
                blocks.push(block(BlockKind::Dialogue, spoken.join("\n"), false, false));
                blocks
            }),
        // A transition ending in `<` would be written as `>text <`, which is
        // centred text.
        (phrase(), any::<bool>()).prop_map(|(text, forced)| {
            let text = text.trim_end_matches('<').trim_end().to_string();
            let text = if text.is_empty() {
                "CUT TO:".into()
            } else {
                text
            };
            vec![block(BlockKind::Transition, text, forced, false)]
        }),
        phrase().prop_map(|text| vec![block(BlockKind::Centered, text, false, false)]),
        phrase().prop_map(|text| vec![block(BlockKind::Lyric, text, false, false)]),
        (1u8..=6, phrase()).prop_map(|(level, text)| vec![block(
            BlockKind::Section { level },
            text,
            false,
            false
        )]),
        phrase().prop_map(|text| vec![block(BlockKind::Synopsis, text, false, false)]),
        lines().prop_map(|lines| {
            let text = lines.join("\n").replace("[[", "").replace("]]", "");
            vec![block(BlockKind::Note, text, false, false)]
        }),
        Just(vec![block(
            BlockKind::PageBreak,
            String::new(),
            false,
            false
        )]),
        phrase().prop_map(|text| {
            let inner = text.replace("*/", "").replace("/*", "");
            vec![block(
                BlockKind::Opaque,
                format!("/* {inner} */"),
                false,
                false,
            )]
        }),
    ]
}

fn title_page() -> impl Strategy<Value = TitlePage> {
    let field = prop_oneof![
        Just(TitleField::Title),
        Just(TitleField::Credit),
        Just(TitleField::Author),
        Just(TitleField::DraftDate),
        Just(TitleField::Contact),
        Just(TitleField::Other("Revision Colour".to_string())),
    ];
    proptest::collection::vec((field, proptest::collection::vec(phrase(), 1..3)), 0..4).prop_map(
        |entries| TitlePage {
            entries: entries
                .into_iter()
                .map(|(field, value)| TitleEntry {
                    field,
                    value: value.join("\n"),
                })
                .collect(),
            provenance: None,
        },
    )
}

fn document() -> impl Strategy<Value = (TitlePage, Vec<Element>)> {
    (
        title_page(),
        proptest::collection::vec(unit(), 0..8).prop_map(|units| units.concat()),
    )
}

fn write(title: &TitlePage, elements: &[Element], line_ending: LineEnding) -> String {
    let refs: Vec<ElementRef<'_>> = elements.iter().map(Element::as_ref).collect();
    serialise(&Output {
        title_page: title,
        elements: &refs,
        source: None,
        bom: false,
        line_ending,
    })
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(512))]

    #[test]
    fn parsing_the_canonical_form_gives_back_the_same_blocks(
        (title, elements) in document(),
    ) {
        let written = write(&title, &elements, LineEnding::Lf);
        let reparsed = parse(&written);

        let before: Vec<(BlockKind, &str, bool)> = elements
            .iter()
            .map(|element| (element.kind, element.text.as_str(), element.dual))
            .collect();
        let after: Vec<(BlockKind, &str, bool)> = reparsed
            .elements
            .iter()
            .map(|element| (element.kind, element.text.as_str(), element.dual))
            .collect();
        prop_assert_eq!(&before, &after, "written as:\n{}", written);

        prop_assert_eq!(
            title.in_canonical_order(),
            reparsed.title_page.in_canonical_order(),
            "written as:\n{}", written
        );
    }

    #[test]
    fn the_canonical_form_is_a_fixed_point(
        (title, elements) in document(),
    ) {
        // Writing what was just read must not drift: two passes give the same
        // bytes as one. A serialiser that adds a marker on every trip would
        // pass the test above and fail this one.
        let once = write(&title, &elements, LineEnding::Lf);
        let script = parse(&once);
        let twice = write(&script.title_page, &script.elements, LineEnding::Lf);
        prop_assert_eq!(&once, &twice);
    }

    #[test]
    fn a_crlf_document_stays_crlf(
        (title, elements) in document(),
    ) {
        let written = write(&title, &elements, LineEnding::CrLf);
        prop_assert!(!written.contains("\r\r"));
        for line in written.split("\r\n") {
            prop_assert!(!line.contains('\n'), "a bare LF survived in {:?}", written);
        }
    }

    #[test]
    fn the_canonical_form_ends_with_exactly_one_newline(
        (title, elements) in document(),
    ) {
        let written = write(&title, &elements, LineEnding::Lf);
        if !written.is_empty() {
            prop_assert!(written.ends_with('\n'), "{:?}", written);
            prop_assert!(!written.ends_with("\n\n"), "{:?}", written);
        }
    }
}
