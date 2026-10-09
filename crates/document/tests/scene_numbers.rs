//! Whole-script scene-number edits preserve identity, source and undo boundaries.
use slugline_document::{BlockKind, DocPosition, DocSelection, Document, EditCommand, NewBlock};

const SCRIPT: &str = concat!(
    "Title: Numbering\r\nAuthor: A Writer\r\n\r\n",
    "INT. CAFÉ 🎬 - DAY #12A#\r\n\r\n",
    "!Leave #88# in this action.\r\n\r\n",
    "ALICE\r\nHello.\r\n\r\nBOB ^\r\nGoodbye.\r\n\r\n",
    ".The unusual place # old #\r\n\r\n",
    "/* EXT. NOT A SCENE #99# */\r\n\r\n",
    "EXT. STREET - NIGHT\r\n\r\n[[Private #7#]]\r\n",
);

#[test]
fn whole_script_numbering_and_removal_are_single_reversible_edits() {
    let mut document = Document::parse(SCRIPT);
    let original = document.blocks().to_vec();
    let title = document.title_page().clone();
    let scenes: Vec<_> = original
        .iter()
        .filter(|b| b.kind() == BlockKind::SceneHeading)
        .collect();
    assert_eq!(scenes.len(), 3);
    let before = DocSelection {
        anchor: DocPosition::new(scenes[1].id(), 4),
        focus: DocPosition::new(scenes[0].id(), "INT. CAFÉ 🎬".len() as u32),
    };
    let patch = document.number_scenes(Some(before)).unwrap();
    assert_eq!(
        patch.changed,
        scenes.iter().map(|b| b.id()).collect::<Vec<_>>()
    );
    assert!(patch.removed.is_empty() && patch.inserted.is_empty());
    assert_eq!(patch.selection, Some(before));
    for (index, scene) in scenes.iter().enumerate() {
        let actual = document.block(scene.id()).unwrap();
        assert_eq!(
            slugline_document::split_scene_number(actual.text()).1,
            Some((index + 1).to_string().as_str())
        );
        assert_eq!(
            (actual.kind(), actual.forced(), actual.dual()),
            (scene.kind(), scene.forced(), scene.dual())
        );
        assert!(actual.provenance().is_none());
    }
    for block in original
        .iter()
        .filter(|b| b.kind() != BlockKind::SceneHeading)
    {
        assert_eq!(document.block(block.id()), Some(block));
    }
    assert_eq!(document.title_page(), &title);
    let numbered = document.serialise();
    let reopened = Document::parse(&numbered);
    assert_eq!(
        reopened
            .blocks()
            .iter()
            .filter(|b| b.kind() == BlockKind::SceneHeading)
            .map(|b| slugline_document::split_scene_number(b.text()).1.unwrap())
            .collect::<Vec<_>>(),
        ["1", "2", "3"]
    );
    assert_eq!(document.undo().unwrap().selection, Some(before));
    assert_eq!(
        document.serialise(),
        SCRIPT,
        "undo restores original CRLF provenance"
    );
    assert!(!document.is_dirty());
    assert!(document.undo().is_none(), "all headings were one step");
    assert_eq!(document.redo().unwrap().selection, Some(before));
    assert_eq!(document.serialise(), numbered);
    document.mark_saved();
    let removed = document.remove_scene_numbers(Some(before)).unwrap();
    assert_eq!(removed.changed.len(), 3);
    for scene in &scenes {
        assert!(
            slugline_document::split_scene_number(document.block(scene.id()).unwrap().text())
                .1
                .is_none()
        );
    }
    assert_eq!(document.undo().unwrap().selection, Some(before));
    assert_eq!(document.serialise(), numbered);
    assert!(!document.is_dirty());
    document.redo().unwrap();
    assert!(document.is_dirty());
}

#[test]
fn whitespace_and_unrecognised_hashes_are_not_heading_rewrites() {
    let mut document = Document::blank();
    document
        .apply(EditCommand::InsertBlocks {
            after: None,
            blocks: vec![
                NewBlock {
                    kind: BlockKind::SceneHeading,
                    text: "  INT. LAB\t  #12A# \t".into(),
                    forced: true,
                    dual: false,
                },
                NewBlock {
                    kind: BlockKind::SceneHeading,
                    text: "EXT. ROAD ##\t ".into(),
                    forced: true,
                    dual: false,
                },
                NewBlock {
                    kind: BlockKind::SceneHeading,
                    text: "INT. ROOM # DAY".into(),
                    forced: true,
                    dual: false,
                },
            ],
        })
        .unwrap();
    document.clear_history();
    document.mark_saved();
    let ids: Vec<_> = document
        .blocks()
        .iter()
        .filter(|b| b.kind() == BlockKind::SceneHeading)
        .map(|b| b.id())
        .collect();
    document.number_scenes(None).unwrap();
    assert_eq!(
        document.block(ids[0]).unwrap().text(),
        "  INT. LAB\t  #1# \t"
    );
    assert_eq!(
        document.block(ids[1]).unwrap().text(),
        "EXT. ROAD ## #2#\t "
    );
    assert_eq!(
        document.block(ids[2]).unwrap().text(),
        "INT. ROOM # DAY #3#"
    );
    document.remove_scene_numbers(None).unwrap();
    assert_eq!(document.block(ids[0]).unwrap().text(), "  INT. LAB\t  \t");
    assert_eq!(document.block(ids[1]).unwrap().text(), "EXT. ROAD ##\t ");
    assert_eq!(document.block(ids[2]).unwrap().text(), "INT. ROOM # DAY");
}

#[test]
fn caret_suffix_mapping_and_reverse_selection_are_recorded_for_redo() {
    let mut document = Document::parse("INT. CAFÉ 🎬 - DAY #123456#\n\nEXT. ROAD - NIGHT #AB#\n");
    let first = &document.blocks()[0];
    let second = &document.blocks()[1];
    let before = DocSelection {
        anchor: DocPosition::new(second.id(), second.text().len() as u32),
        focus: DocPosition::new(first.id(), first.text().find("3456").unwrap() as u32),
    };
    let first_id = first.id();
    let result = document.number_scenes(Some(before)).unwrap();
    let after = result.selection.unwrap();
    assert_eq!(
        after.anchor.offset as usize,
        document.block(after.anchor.block).unwrap().text().len()
    );
    assert_eq!(
        after.focus,
        DocPosition::new(first_id, "INT. CAFÉ 🎬 - DAY ".len() as u32)
    );
    assert_eq!(document.undo().unwrap().selection, Some(before));
    assert_eq!(document.redo().unwrap().selection, Some(after));
    let result = document.remove_scene_numbers(Some(after)).unwrap();
    let removed = result.selection;
    assert_eq!(document.undo().unwrap().selection, Some(after));
    assert_eq!(document.redo().unwrap().selection, removed);
}

#[test]
fn noop_commands_leave_clean_history_and_redo_intact() {
    for source in [
        "INT. LAB - DAY #1#\n\nEXT. ROAD - NIGHT #2#\n",
        "Action #1#.\n",
    ] {
        let mut document = Document::parse(source);
        let revision = document.revision();
        let result = document.number_scenes(None).unwrap();
        assert!(result.changed.is_empty());
        assert_eq!(document.revision(), revision);
        assert!(!document.is_dirty());
        assert!(!document.can_undo());
        assert_eq!(document.serialise(), source);
    }
    let mut document = Document::parse("INT. LAB - DAY\n\nAction #9#.\n");
    assert!(document
        .remove_scene_numbers(None)
        .unwrap()
        .changed
        .is_empty());
    assert!(!document.is_dirty() && !document.can_undo());
    document.number_scenes(None).unwrap();
    document.undo().unwrap();
    document.remove_scene_numbers(None).unwrap();
    assert!(document.can_redo(), "a no-op must not erase redo");
}

#[test]
fn numbering_does_not_join_adjacent_typing_and_invalid_selection_is_atomic() {
    let mut document = Document::parse("INT. CAFÉ 🎬 - DAY\n\nEXT. ROAD - NIGHT\n");
    let id = document.blocks()[0].id();
    document
        .apply(EditCommand::ReplaceText {
            block: id,
            range: 0..0,
            with: "A ".into(),
        })
        .unwrap();
    let typed = document.serialise();
    document.number_scenes(None).unwrap();
    let numbered = document.serialise();
    document
        .apply(EditCommand::ReplaceText {
            block: id,
            range: 0..0,
            with: "B ".into(),
        })
        .unwrap();
    document.undo().unwrap();
    assert_eq!(document.serialise(), numbered);
    document.undo().unwrap();
    assert_eq!(document.serialise(), typed);
    document.undo().unwrap();
    assert_eq!(
        document.serialise(),
        "INT. CAFÉ 🎬 - DAY\n\nEXT. ROAD - NIGHT\n"
    );
    let invalid = DocSelection::caret(DocPosition::new(id, "INT. CAFÉ ".len() as u32 + 1));
    assert!(document.number_scenes(Some(invalid)).is_err());
    assert!(!document.is_dirty() && !document.can_undo());
}
