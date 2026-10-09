//! `element_change_preserves_text` — §13's named invariant: changing an
//! element's type never alters its characters.
//!
//! Requirement §5 is a promise about the writer's words: pressing the shortcut
//! for "this is a scene heading" must change how the line is treated and
//! nothing else. The place that promise is easiest to break is the serialiser,
//! which re-adds `.`, `@`, `>` and `!` markers — a marker that ends up inside
//! `text` rather than beside it is exactly this bug, and it survives a save.
//!
//! So the test goes further than the model: it changes the kind, writes the
//! file, reads it back, and checks the characters again.

use slugline_document::{BlockKind, Document, EditCommand};

const KINDS: [BlockKind; 12] = [
    BlockKind::SceneHeading,
    BlockKind::Action,
    BlockKind::Character,
    BlockKind::Dialogue,
    BlockKind::Parenthetical,
    BlockKind::Transition,
    BlockKind::Centered,
    BlockKind::Lyric,
    BlockKind::Section { level: 2 },
    BlockKind::Synopsis,
    BlockKind::Note,
    BlockKind::PageBreak,
];

const SCRIPT: &str = concat!(
    "Title: Element Switching\n\n",
    "INT. HOUSE - DAY\n\n",
    "John enters, carrying a *heavy* box.\n\n",
    "JOHN\n(quietly)\nHello — café 日本 🎬.\n\n",
    "CUT TO:\n\n",
    "> THE END <\n\n",
    "~Fly me to the moon\n\n",
    "# Act Two\n\n",
    "= A synopsis.\n\n",
    "[[ a note ]]\n\n",
    "===\n",
);

#[test]
fn changing_a_block_to_every_other_kind_never_alters_its_text() {
    let original = Document::parse(SCRIPT);

    for index in 0..original.blocks().len() {
        for kind in KINDS {
            // A page break carries no text, so switching *to* it is the one
            // case where there is nothing to preserve on the way back.
            if kind == BlockKind::PageBreak {
                continue;
            }
            let mut document = Document::parse(SCRIPT);
            let block = &document.blocks()[index];
            let (id, text, was) = (block.id(), block.text().to_string(), block.kind());
            // Likewise switching *away* from a page break: there are no
            // characters to preserve, and a block with none is dropped on save.
            if text.is_empty() {
                continue;
            }

            document
                .apply(EditCommand::SetKind {
                    block: id,
                    kind,
                    forced: true,
                })
                .unwrap_or_else(|e| panic!("{was:?} -> {kind:?}: {e}"));

            let after = document.block(id).expect("the block is still there");
            assert_eq!(
                after.text(),
                text,
                "{was:?} -> {kind:?} altered the text in the model"
            );
            assert_eq!(after.kind(), kind);

            // And the same again through a save and a reopen, which is where a
            // marker leaks into the text if the serialiser gets it wrong.
            let written = document.serialise();
            let reopened = Document::parse(&written);
            // The characters themselves. This is the invariant: whatever else a
            // type change does, the writer's text is still in the file.
            //
            // Every element marker except `!` swallows the whitespace beside
            // it — `# Act One` is a section called "Act One", not " Act One" —
            // so a block whose text is padded loses that padding when it takes
            // a marker on. Words, markup and markers-inside-text are what this
            // invariant is about; a leading space on a line that has just been
            // told it is a scene heading is not text the writer can see.
            let expected = if trims_its_whitespace(kind) {
                text.trim()
            } else {
                text.as_str()
            };
            assert!(
                reopened
                    .blocks()
                    .iter()
                    .any(|block| block.text().contains(expected)),
                "{was:?} -> {kind:?} lost the text {expected:?} on save:\n{written}"
            );

            // Dialogue and a parenthetical have no marker of their own in
            // Fountain: they are defined by the cue above them, and two
            // adjacent dialogue lines are one speech. Where the format cannot
            // express the classification, a save keeps the words and loses the
            // label — that is the format's answer, not this code's. Where it
            // can, the label has to survive too.
            let parenthesised = text.trim().starts_with('(') && text.trim().ends_with(')');
            let after_cue = follows_a_cue(&original, index);
            let representable = match kind {
                BlockKind::Dialogue => {
                    !parenthesised
                        && after_cue
                        && original.blocks()[index - 1].kind() != BlockKind::Dialogue
                }
                BlockKind::Parenthetical => parenthesised && after_cue,
                _ => true,
            };
            if representable {
                let matching = reopened
                    .blocks()
                    .iter()
                    .find(|candidate| candidate.text() == expected)
                    .unwrap_or_else(|| {
                        panic!("{was:?} -> {kind:?} split the text {text:?} on save:\n{written}")
                    });
                assert_eq!(
                    matching.kind(),
                    kind,
                    "{was:?} -> {kind:?} did not survive a save:\n{written}"
                );
            }
        }
    }
}

/// Whether this kind's marker takes the whitespace around the text with it.
/// `!` is the exception: forcing an action is the one case where the writer's
/// own indentation is the point.
fn trims_its_whitespace(kind: BlockKind) -> bool {
    matches!(
        kind,
        BlockKind::SceneHeading
            | BlockKind::Character
            | BlockKind::Transition
            | BlockKind::Centered
            | BlockKind::Lyric
            | BlockKind::Section { .. }
            | BlockKind::Synopsis
    )
}

/// Whether the block before `index` is one the parser would read a speech out
/// of. Nothing in Fountain marks dialogue: the cue above it does.
fn follows_a_cue(document: &Document, index: usize) -> bool {
    index
        .checked_sub(1)
        .is_some_and(|before| document.blocks()[before].kind().opens_dialogue())
}

#[test]
fn changing_a_page_break_to_a_kind_that_carries_text_keeps_it_empty() {
    let mut document = Document::parse("Action.\n\n===\n");
    let id = document.blocks()[1].id();
    document
        .apply(EditCommand::SetKind {
            block: id,
            kind: BlockKind::Action,
            forced: true,
        })
        .unwrap();
    assert_eq!(document.block(id).expect("still there").text(), "");
}

#[test]
fn setting_forced_does_not_touch_the_text_either() {
    let mut document = Document::parse("INT. HOUSE - DAY\n");
    let id = document.blocks()[0].id();
    document
        .apply(EditCommand::SetKind {
            block: id,
            kind: BlockKind::SceneHeading,
            forced: true,
        })
        .unwrap();

    assert_eq!(
        document.block(id).expect("still there").text(),
        "INT. HOUSE - DAY"
    );
    assert_eq!(document.serialise(), ".INT. HOUSE - DAY\n");
    let reopened = Document::parse(&document.serialise());
    assert_eq!(reopened.blocks()[0].text(), "INT. HOUSE - DAY");
    assert!(reopened.blocks()[0].forced());
}
