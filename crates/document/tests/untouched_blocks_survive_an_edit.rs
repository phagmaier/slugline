//! Property: applying a random edit, serialising, and reparsing preserves all
//! untouched blocks exactly (Phase 1, Tests).
//!
//! This is the property §3.2 exists to provide, and the one that decides
//! whether "open a script, fix a typo, save" is safe. Everything outside the
//! edit must come back exactly as it went in, byte-level formatting included,
//! because those blocks keep their provenance and are copied rather than
//! rewritten.
//!
//! "Outside the edit" means outside the edited block *and its two neighbours*,
//! which is precisely §4.2's re-inference window. That is not slack in the
//! test: typing `=== ` at the start of a parenthetical genuinely makes it a
//! line of dialogue, and a line of dialogue genuinely joins the speech below
//! it. No text is lost when that happens — the boundary between two blocks
//! moves — and a parser that refused to notice would be the defect. What must
//! never move is a block the caret was nowhere near.
//!
//! Blocks are compared by kind and text: the ids are the same objects, so
//! comparing them would prove nothing about the file that was written.

use std::fs;
use std::path::PathBuf;

use proptest::prelude::*;
use slugline_document::{BlockKind, Document, EditCommand};

fn corpus() -> Vec<String> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("workspace root")
        .join("testdata")
        .join("corpus");
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .expect("testdata/corpus exists")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "fountain"))
        .collect();
    paths.sort();
    paths
        .iter()
        .map(|path| fs::read_to_string(path).expect("corpus files are UTF-8"))
        .collect()
}

/// Insertions are single-line: a blank line is a block separator, so text
/// containing one does not insert into a block, it splits it. That case is
/// covered by `SplitBlock`, which is a command rather than a typing accident.
fn insertion() -> impl Strategy<Value = String> {
    prop_oneof![
        Just(String::new()),
        Just("x".to_string()),
        Just("café 日本 🎬".to_string()),
        Just("INT. HOUSE - DAY".to_string()),
        Just("MARTHA".to_string()),
        Just("(beat)".to_string()),
        Just("=== ".to_string()),
        Just("a\nb".to_string()),
        Just("  indented".to_string()),
    ]
}

fn snapshot(document: &Document) -> Vec<(BlockKind, String)> {
    document
        .blocks
        .iter()
        .map(|block| (block.kind, block.text.clone()))
        .collect()
}

/// Asserts that every block outside the §4.2 re-inference window came back
/// unchanged. The window is the edited block and the one on either side of it;
/// what is inside it may split, merge, or change kind.
fn assert_bystanders_survived(
    before: &[(BlockKind, String)],
    after: &[(BlockKind, String)],
    index: usize,
    written: &str,
) -> Result<(), TestCaseError> {
    let leading = index.saturating_sub(1);
    let trailing = before.len().saturating_sub(index + 2);
    prop_assert!(
        leading + trailing <= after.len(),
        "blocks outside the edit disappeared:\n{written}"
    );
    prop_assert_eq!(
        &after[..leading],
        &before[..leading],
        "a block before the edit changed:\n{}",
        written
    );
    prop_assert_eq!(
        &after[after.len() - trailing..],
        &before[before.len() - trailing..],
        "a block after the edit changed:\n{}",
        written
    );
    Ok(())
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(512))]

    #[test]
    fn replacing_text_leaves_every_other_block_byte_identical(
        file in proptest::sample::select(corpus()),
        block in 0usize..64,
        start in 0usize..64,
        length in 0usize..16,
        with in insertion(),
    ) {
        let mut document = Document::parse(&file);
        prop_assume!(!document.blocks.is_empty());
        let index = block % document.blocks.len();
        // An Opaque block refuses every edit by design (§3.2), which is a
        // property of its own rather than a case for this one.
        prop_assume!(document.blocks[index].kind != BlockKind::Opaque);
        let id = document.blocks[index].id;

        // Offsets are clamped onto character boundaries: an offset that is not
        // one is rejected by `apply`, which is a different property.
        let text = document.blocks[index].text.clone();
        let start = (start % (text.len() + 1)).min(text.len());
        let start = (0..=start).rev().find(|at| text.is_char_boundary(*at)).unwrap_or(0);
        let end = (start + length).min(text.len());
        let end = (start..=end).rev().find(|at| text.is_char_boundary(*at)).unwrap_or(start);

        let before = snapshot(&document);
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: start as u32..end as u32,
                with,
            })
            .expect("the offsets were put on character boundaries");

        let written = document.serialise();
        let after = snapshot(&Document::parse(&written));
        assert_bystanders_survived(&before, &after, index, &written)?;
    }

    #[test]
    fn undoing_any_edit_restores_the_file_byte_for_byte(
        file in proptest::sample::select(corpus()),
        block in 0usize..64,
        with in insertion(),
        kind in prop_oneof![
            Just(BlockKind::Action),
            Just(BlockKind::SceneHeading),
            Just(BlockKind::Character),
            Just(BlockKind::Transition),
            Just(BlockKind::Lyric),
        ],
        which in 0usize..4,
    ) {
        let mut document = Document::parse(&file);
        prop_assume!(!document.blocks.is_empty());
        let index = block % document.blocks.len();
        prop_assume!(document.blocks[index].kind != BlockKind::Opaque);
        let id = document.blocks[index].id;
        let length = document.blocks[index].text.len();

        let command = match which {
            0 => EditCommand::ReplaceText { block: id, range: 0..0, with },
            1 => EditCommand::SetKind { block: id, kind, forced: true },
            2 => EditCommand::SplitBlock { block: id, at: 0 },
            _ => EditCommand::SplitBlock { block: id, at: length as u32 },
        };

        document.apply(command).expect("all of these are applicable");
        document.undo().expect("an applied edit is undoable");

        // Undo restores provenance as well as content, so the whole file is
        // written from the original bytes again — this is the property that
        // makes edit-then-undo-then-save a no-op rather than a reformat.
        prop_assert_eq!(document.serialise(), file);
    }
}
