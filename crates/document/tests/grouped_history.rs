use slugline_document::{
    BlockId, BlockKind, DocPosition, DocSelection, Document, EditCommand, EditError, TitleField,
};

#[test]
fn rejected_groups_preserve_existing_undo_redo_and_source() {
    let source = "\u{feff}Title: Original\r\n\r\n!café — 日本 🎬.\r\n\r\n/* untouched\t */\r\n";
    for invalid_offset in [false, true] {
        let mut document = Document::parse(source);
        let action = document.blocks()[0].id();
        document
            .apply(EditCommand::SetTitlePage {
                field: TitleField::Title,
                value: "Kept".into(),
            })
            .unwrap();
        document.mark_saved();
        let before = DocSelection {
            anchor: DocPosition::new(action, 5),
            focus: DocPosition::new(action, 0),
        };
        let mut redo_states = Vec::new();
        for text in ["first ", "second "] {
            let patch = document
                .apply_with_selection(
                    EditCommand::ReplaceText {
                        block: action,
                        range: 0..0,
                        with: text.into(),
                    },
                    Some(before),
                )
                .unwrap();
            document.commit();
            redo_states.push((document.serialise(), document.blocks().to_vec(), patch));
        }
        document.undo().unwrap();
        document.undo().unwrap();
        let bytes = document.serialise();
        let blocks = document.blocks().to_vec();
        let title = document.title_page().clone();
        let revision = document.revision();
        assert!(!document.is_dirty());

        let error = if invalid_offset {
            EditError::BadOffset {
                block: action,
                offset: 4,
            }
        } else {
            EditError::UnknownBlock(BlockId(9_999))
        };
        assert_eq!(
            document.apply_group(Some(before), |group| {
                group.apply(EditCommand::SetKind {
                    block: action,
                    kind: BlockKind::SceneHeading,
                    forced: true,
                })?;
                group.apply(EditCommand::SplitBlock {
                    block: action,
                    at: 5,
                })?;
                group.apply(EditCommand::SetTitlePage {
                    field: TitleField::Title,
                    value: "Temporary".into(),
                })?;
                group.apply(EditCommand::ReplaceText {
                    block: if invalid_offset {
                        action
                    } else {
                        BlockId(9_999)
                    },
                    range: if invalid_offset { 4..4 } else { 0..0 },
                    with: "discarded".into(),
                })?;
                Ok(())
            }),
            Err(error)
        );
        assert_eq!(document.serialise(), bytes);
        assert_eq!(document.blocks(), blocks);
        assert_eq!(document.title_page(), &title);
        assert_eq!(document.revision(), revision);
        assert!(!document.is_dirty());
        assert!(document.can_undo());
        assert!(
            document.can_redo(),
            "a rejected group must retain Redo text"
        );
        for (bytes, blocks, patch) in redo_states {
            assert_eq!(document.redo().unwrap().selection, patch.selection);
            assert_eq!(document.serialise(), bytes);
            assert_eq!(document.blocks(), blocks);
        }
        assert!(!document.can_redo());
        for _ in 0..2 {
            assert_eq!(document.undo().unwrap().selection, Some(before));
        }
        document.undo().unwrap();
        assert_eq!(document.serialise(), source);
        assert!(!document.can_undo());
        assert_eq!(Document::parse(source).serialise(), source);
    }
}

#[test]
fn failed_and_noop_groups_preserve_pending_typing() {
    for fails in [false, true] {
        let source = "Original.\n";
        let mut document = Document::parse(source);
        let action = document.blocks()[0].id();
        document
            .apply(EditCommand::ReplaceText {
                block: action,
                range: 0..0,
                with: "a".into(),
            })
            .unwrap();
        let outcome = document.apply_all(
            vec![
                EditCommand::ReplaceText {
                    block: action,
                    range: 0..0,
                    with: if fails {
                        "temporary".into()
                    } else {
                        String::new()
                    },
                },
                EditCommand::ReplaceText {
                    block: if fails { BlockId(9_999) } else { action },
                    range: 0..0,
                    with: String::new(),
                },
            ],
            None,
        );
        assert_eq!(outcome.is_err(), fails);
        document
            .apply(EditCommand::ReplaceText {
                block: action,
                range: 1..1,
                with: "b".into(),
            })
            .unwrap();
        assert_eq!(document.blocks()[0].text(), "abOriginal.");
        document.undo().unwrap();
        assert_eq!(document.serialise(), source);
        assert!(!document.can_undo());
    }
}

#[test]
fn rejected_group_at_undo_limit_preserves_oldest_edit() {
    let mut document = Document::parse("Original.\n");
    let action = document.blocks()[0].id();
    for index in 0..5_000 {
        document
            .apply(EditCommand::SetTitlePage {
                field: TitleField::Title,
                value: index.to_string(),
            })
            .unwrap();
    }
    assert!(document
        .apply_all(
            vec![
                EditCommand::ReplaceText {
                    block: action,
                    range: 0..0,
                    with: "temporary".into(),
                },
                EditCommand::ReplaceText {
                    block: BlockId(9_999),
                    range: 0..0,
                    with: "refused".into(),
                },
            ],
            None,
        )
        .is_err());
    for _ in 0..5_000 {
        assert!(
            document.undo().is_some(),
            "all prior Undo steps must survive"
        );
    }
    assert_eq!(document.serialise(), "Original.\n");
    assert!(!document.can_undo());
}
