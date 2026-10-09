use slugline_document::{
    BlockId, BlockKind, DocPosition, DocSelection, Document, EditCommand, EditError,
};

fn caret(block: BlockId, offset: u32) -> DocSelection {
    DocSelection::caret(DocPosition::new(block, offset))
}

fn semantics(document: &Document) -> Vec<(BlockKind, String, bool)> {
    document
        .blocks()
        .iter()
        .map(|block| (block.kind(), block.text().to_owned(), block.dual()))
        .collect()
}

fn omitted(document: &Document) -> BlockId {
    document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Opaque)
        .unwrap()
        .id()
}

#[test]
fn changed_saved_seam_whitespace_refuses_without_consuming_the_record() {
    let mut document = Document::parse(".INT. ROOM - DAY\n\nOutside.\n");
    let heading = document.blocks()[0].id();
    document
        .apply(EditCommand::OmitSelection {
            at: DocSelection {
                anchor: DocPosition::new(heading, 5),
                focus: DocPosition::new(heading, 9),
            },
        })
        .unwrap();
    let saved = document.serialise();
    assert!(saved.starts_with("INT. \n"));
    let changed = saved.replacen("INT. \n", "INT.\n", 1);
    let mut reopened = Document::parse(&changed);
    let before = reopened.blocks().to_vec();
    let comment = omitted(&reopened);
    assert_eq!(
        reopened.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(reopened.blocks(), before);
    assert_eq!(reopened.serialise(), changed);
    assert!(!reopened.can_undo());
}

#[test]
fn partial_unicode_selection_restores_the_original_element_and_one_step_history() {
    let source = "Title: Exact\n\nBOB\nBefore 😀 café after.\n\nUntouched.\n";
    let mut document = Document::parse(source);
    let original = document.blocks().to_vec();
    let dialogue = original[1].id();
    let start = "Before ".len() as u32;
    let end = "Before 😀 café".len() as u32;
    let at = DocSelection {
        anchor: DocPosition::new(dialogue, end),
        focus: DocPosition::new(dialogue, start),
    };
    let result = document
        .apply_with_selection(EditCommand::OmitSelection { at }, Some(at))
        .unwrap();
    assert_eq!(document.block(dialogue).unwrap().text(), "Before ");
    assert_eq!(document.blocks().last().unwrap(), original.last().unwrap());
    let comment = result.selection.unwrap();
    assert_eq!(
        document.block(comment.focus.block).unwrap().kind(),
        BlockKind::Opaque
    );
    let saved = document.serialise();
    assert_eq!(document.undo().unwrap().selection, Some(at));
    assert_eq!(document.serialise(), source);
    assert_eq!(document.blocks(), original);
    assert!(document.undo().is_none());
    let redo = document.redo().unwrap();
    assert_eq!(redo.selection, Some(comment));
    assert!(
        redo.changed.iter().all(|id| !redo.inserted.contains(id)),
        "redo must journal new remainders as insertions, never changes to absent ids"
    );
    assert_eq!(document.serialise(), saved);
    document
        .apply(EditCommand::RestoreOmitted { at: comment })
        .unwrap();
    assert_eq!(
        document.block(dialogue).unwrap().text(),
        "Before 😀 café after."
    );
    assert_eq!(
        document.block(dialogue).unwrap().kind(),
        BlockKind::Dialogue
    );
    let restored = document.serialise();
    assert_eq!(
        semantics(&Document::parse(&restored)),
        semantics(&Document::parse(source))
    );
    assert_eq!(document.undo().unwrap().selection, Some(comment));
    assert_eq!(document.serialise(), saved);
    document.redo().unwrap();
    assert_eq!(document.serialise(), restored);
}

#[test]
fn cross_block_partial_boundaries_survive_save_reopen_without_widening() {
    let source = "Title: Kept\n\nFirst prefix SELECT\n\n@BOB\n(softly)\nSELECT suffix\n\nEXT. ROAD - DAY\n\nOutside.\n";
    let mut document = Document::parse(source);
    let before = semantics(&document);
    let outside = document.blocks()[4..].to_vec();
    let first = document.blocks()[0].id();
    let last = document.blocks()[3].id();
    let at = DocSelection {
        anchor: DocPosition::new(first, "First prefix ".len() as u32),
        focus: DocPosition::new(last, "SELECT".len() as u32),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    assert_eq!(document.block(first).unwrap().text(), "First prefix ");
    assert_eq!(document.block(last).unwrap().text(), " suffix");
    assert_eq!(
        &document.blocks()[document.blocks().len() - outside.len()..],
        &outside
    );
    let saved = document.serialise();
    let mut reopened = Document::parse(&saved);
    assert_eq!(reopened.serialise(), saved);
    let id = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted { at: caret(id, 0) })
        .unwrap();
    assert_eq!(semantics(&reopened), before);
    assert_eq!(
        reopened
            .title_page()
            .get(&slugline_document::TitleField::Title),
        Some("Kept")
    );
    let twice = Document::parse(&reopened.serialise());
    assert_eq!(semantics(&twice), before);
    // These are actual editable screenplay blocks, not another opaque copy.
    let dialogue = reopened.blocks()[3].id();
    reopened
        .apply(EditCommand::ReplaceText {
            block: dialogue,
            range: 0..6,
            with: "NEW".into(),
        })
        .unwrap();
    assert_eq!(reopened.block(dialogue).unwrap().text(), "NEW suffix");
}

#[test]
fn scene_omission_uses_heading_boundaries_and_preserves_nested_boneyards() {
    let source = "Title: Untouched\n\nINT. ONE - DAY\n\n@A\nHello.\n\n/* outer /* inner */ old */\n\n# Between scenes\n\nEXT. TWO - NIGHT\n\nNext.\n";
    let mut document = Document::parse(source);
    let before = semantics(&document);
    let next = document.blocks()[5..].to_vec();
    let focus = document.blocks()[2].id();
    let at = caret(focus, 3);
    document
        .apply_with_selection(EditCommand::OmitScene { block: focus }, Some(at))
        .unwrap();
    assert_eq!(&document.blocks()[1..], &next);
    assert_eq!(document.undo().unwrap().selection, Some(at));
    assert_eq!(document.serialise(), source);
    document.redo().unwrap();
    let mut reopened = Document::parse(&document.serialise());
    let id = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted { at: caret(id, 0) })
        .unwrap();
    assert_eq!(semantics(&reopened), before);
    assert_eq!(semantics(&Document::parse(&reopened.serialise())), before);
}

#[test]
fn literal_delimiters_are_conserved_in_the_record_but_unsafe_restore_refuses() {
    let text = "a */ dangling /* nested /* 😀 \\ \" tail";
    let mut document = Document::blank();
    let first = document.blocks()[0].id();
    document
        .apply(EditCommand::ReplaceText {
            block: first,
            range: 0..0,
            with: text.into(),
        })
        .unwrap();
    document.commit();
    let at = DocSelection {
        anchor: DocPosition::new(first, 0),
        focus: DocPosition::new(first, text.len() as u32),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let saved = document.serialise();
    let mut reopened = Document::parse(&saved);
    assert_eq!(reopened.blocks().len(), 1);
    assert_eq!(reopened.blocks()[0].kind(), BlockKind::Opaque);
    let id = omitted(&reopened);
    assert_eq!(
        reopened.apply(EditCommand::RestoreOmitted { at: caret(id, 0) }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(reopened.serialise(), saved);
    assert!(!reopened.can_undo());
}

#[test]
fn changed_same_kind_boundary_and_changed_kind_refuse_atomically() {
    let mut document = Document::parse("@BOB\nBefore OMIT after.\n");
    let id = document.blocks()[1].id();
    let at = DocSelection {
        anchor: DocPosition::new(id, 7),
        focus: DocPosition::new(id, 11),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let comment = omitted(&document);
    document
        .apply(EditCommand::ReplaceText {
            block: id,
            range: 0..6,
            with: "Changed".into(),
        })
        .unwrap();
    let before = document.serialise();
    let blocks = document.blocks().to_vec();
    assert_eq!(
        document.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(document.serialise(), before);
    assert_eq!(document.blocks(), blocks);
    document
        .apply(EditCommand::SetKind {
            block: id,
            kind: BlockKind::Action,
            forced: true,
        })
        .unwrap();
    let before = document.serialise();
    let blocks = document.blocks().to_vec();
    assert!(document
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        })
        .is_err());
    assert_eq!(document.serialise(), before);
    assert_eq!(document.blocks(), blocks);
    document.undo().unwrap();
    assert_eq!(document.block(id).unwrap().kind(), BlockKind::Dialogue);
}

#[test]
fn deleting_live_seam_whitespace_does_not_authorize_normalized_restoration() {
    let mut document = Document::parse(".INT. ROOM - DAY\n\nOutside.\n");
    let heading = document.blocks()[0].id();
    let at = DocSelection {
        anchor: DocPosition::new(heading, 5),
        focus: DocPosition::new(heading, 9),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let comment = omitted(&document);
    assert_eq!(document.block(heading).unwrap().text(), "INT. ");
    document
        .apply(EditCommand::ReplaceText {
            block: heading,
            range: 4..5,
            with: String::new(),
        })
        .unwrap();
    let blocks = document.blocks().to_vec();
    let source = document.serialise();
    assert_eq!(
        document.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission),
    );
    assert_eq!(document.blocks(), blocks);
    assert_eq!(document.serialise(), source);
    document.undo().unwrap();
    assert_eq!(document.block(heading).unwrap().text(), "INT. ");
}

#[test]
fn foreign_closed_nested_unclosed_and_empty_boneyards_restore_as_body_source() {
    for (source, expected) in [
        (
            "/*\n.INT. RESTORED - DAY\n\n@BOB\nHello.\n*/\n",
            vec![
                BlockKind::SceneHeading,
                BlockKind::Character,
                BlockKind::Dialogue,
            ],
        ),
        (
            "/*\nVisible.\n\n/* nested */\n*/\n",
            vec![BlockKind::Action, BlockKind::Opaque],
        ),
        (
            "/*\n!Title: body text\n\nUnclosed 😀",
            vec![BlockKind::Action, BlockKind::Action],
        ),
        ("/**/\n", vec![BlockKind::Action]),
    ] {
        let mut document = Document::parse(source);
        assert_eq!(document.serialise(), source);
        let id = omitted(&document);
        document
            .apply(EditCommand::RestoreOmitted { at: caret(id, 0) })
            .unwrap();
        assert_eq!(
            document
                .blocks()
                .iter()
                .map(|block| block.kind())
                .collect::<Vec<_>>(),
            expected,
            "{source}"
        );
        assert!(document.title_page().is_empty());
        document.undo().unwrap();
        assert_eq!(document.serialise(), source);
    }
}

#[test]
fn malformed_records_and_a_late_group_failure_leave_everything_unchanged() {
    let source =
        "/*\nSlugline omission v99\nblock dialogue 0 0 \"lost?\"\n*/\n\n/*\n!Real text\n*/\n";
    let mut document = Document::parse(source);
    let before = document.blocks().to_vec();
    let at = DocSelection {
        anchor: DocPosition::new(before[0].id(), 0),
        focus: DocPosition::new(before[1].id(), before[1].text().len() as u32),
    };
    // The right-hand ordinary comment restores first, then the version error
    // rolls the entire gesture back, including provenance and undo history.
    assert!(document.apply(EditCommand::RestoreOmitted { at }).is_err());
    assert_eq!(document.blocks(), before);
    assert_eq!(document.serialise(), source);
    assert!(!document.can_undo());
    assert!(!document.can_redo());
    assert_eq!(
        document.apply(EditCommand::ReplaceText {
            block: before[0].id(),
            range: 0..0,
            with: "x".into()
        }),
        Err(EditError::NotEditable(before[0].id()))
    );
}

#[test]
fn collapsed_separator_only_bad_unicode_and_partial_opaque_selections_do_not_edit() {
    let source = "😀First.\n\nSecond.\n\n/* old */\n";
    let mut document = Document::parse(source);
    let first = document.blocks()[0].id();
    let second = document.blocks()[1].id();
    let opaque = document.blocks()[2].id();
    for at in [
        caret(first, 0),
        DocSelection {
            anchor: DocPosition::new(first, document.block(first).unwrap().text().len() as u32),
            focus: DocPosition::new(second, 0),
        },
    ] {
        assert_eq!(
            document.apply(EditCommand::OmitSelection { at }),
            Err(EditError::BadRange)
        );
        assert_eq!(document.serialise(), source);
        assert!(!document.can_undo());
    }
    let bad = DocSelection {
        anchor: DocPosition::new(first, 1),
        focus: DocPosition::new(first, 4),
    };
    assert!(matches!(
        document.apply(EditCommand::OmitSelection { at: bad }),
        Err(EditError::BadOffset { .. })
    ));
    let partial = DocSelection {
        anchor: DocPosition::new(opaque, 2),
        focus: DocPosition::new(opaque, 5),
    };
    assert_eq!(
        document.apply(EditCommand::OmitSelection { at: partial }),
        Err(EditError::NotEditable(opaque))
    );
    assert_eq!(document.serialise(), source);
}

#[test]
fn restoring_an_unclosed_nested_comment_cannot_swallow_later_inserted_text() {
    let mut document = Document::parse("INT. ONE - DAY\n\n/* old /* nested */\n");
    let first = document.blocks()[0].id();
    document
        .apply(EditCommand::OmitScene { block: first })
        .unwrap();
    let comment = omitted(&document);
    document
        .apply(EditCommand::InsertBlocks {
            after: Some(comment),
            blocks: vec![slugline_document::NewBlock::new(
                BlockKind::Action,
                "New writing.",
            )],
        })
        .unwrap();
    let before = document.serialise();
    assert!(document
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        })
        .is_err());
    assert_eq!(document.serialise(), before);
    assert_eq!(document.blocks().last().unwrap().text(), "New writing.");
}

#[test]
fn partial_headings_cues_and_parentheticals_recover_trimmed_seams_and_speech_tail() {
    for (source, index, start, end) in [
        (".INT. ROOM - DAY\n\nOutside.\n", 0, 5, 9),
        ("@ALICE\nHello.\n\n@BOBBY ^\nWorld.\n", 2, 1, 3),
        ("@BOB\n(softly)\nLOUD WORDS\n(then)\nAgain.\n", 1, 2, 5),
    ] {
        let mut document = Document::parse(source);
        let original = semantics(&document);
        let id = document.blocks()[index].id();
        let selection = DocSelection {
            anchor: DocPosition::new(id, start),
            focus: DocPosition::new(id, end),
        };
        document
            .apply(EditCommand::OmitSelection { at: selection })
            .unwrap();
        let saved = document.serialise();
        let mut reopened = Document::parse(&saved);
        let comment = omitted(&reopened);
        reopened
            .apply(EditCommand::RestoreOmitted {
                at: caret(comment, 0),
            })
            .unwrap();
        assert_eq!(semantics(&reopened), original, "{source}");
        assert_eq!(
            semantics(&Document::parse(&reopened.serialise())),
            original,
            "{source}"
        );
    }
}

#[test]
fn omitting_a_whole_parenthetical_reconnects_unselected_speech_semantics_after_reopen() {
    let source = "BOB\n(softly)\nLOUD WORDS\n(then)\nAgain.\n";
    let mut document = Document::parse(source);
    let original = semantics(&document);
    let parenthetical = document.blocks()[1].id();
    let selected = DocSelection {
        anchor: DocPosition::new(parenthetical, 0),
        focus: DocPosition::new(
            parenthetical,
            document.block(parenthetical).unwrap().text().len() as u32,
        ),
    };
    document
        .apply(EditCommand::OmitSelection { at: selected })
        .unwrap();
    assert_eq!(document.blocks()[0].kind(), BlockKind::Character);
    assert_eq!(document.blocks()[2].kind(), BlockKind::Action);
    assert_eq!(
        semantics(&document),
        semantics(&Document::parse(&document.serialise()))
    );
    let mut reopened = Document::parse(&document.serialise());
    let comment = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0),
        })
        .unwrap();
    assert_eq!(semantics(&reopened), original);
    assert_eq!(semantics(&Document::parse(&reopened.serialise())), original);
}

#[test]
fn a_partial_inline_comment_cannot_capture_the_omission_or_unaffected_source() {
    let source = "Before /* old words */ after.\n\nUntouched.\n";
    let mut document = Document::parse(source);
    let id = document.blocks()[0].id();
    let text = document.block(id).unwrap().text();
    let start = text.find("old").unwrap() as u32;
    let end = start + 3;
    let at = DocSelection {
        anchor: DocPosition::new(id, start),
        focus: DocPosition::new(id, end),
    };
    assert_eq!(
        document.apply(EditCommand::OmitSelection { at }),
        Err(EditError::BadRange)
    );
    assert_eq!(document.serialise(), source);
    assert!(!document.can_undo());
    let at = DocSelection {
        anchor: DocPosition::new(id, "Before ".len() as u32),
        focus: DocPosition::new(id, "Before /* old words */".len() as u32),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let mut reopened = Document::parse(&document.serialise());
    assert_eq!(reopened.blocks().last().unwrap().text(), "Untouched.");
    let comment = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0),
        })
        .unwrap();
    assert_eq!(reopened.blocks()[0].text(), "Before /* old words */ after.");
    assert_eq!(reopened.blocks().last().unwrap().text(), "Untouched.");
}

#[test]
fn escaped_nested_delimiters_do_not_comment_out_unaffected_blocks_after_reopen() {
    let text = "stray */ and /* nested /* inner */ end */ 😀 \\\\ \\\"";
    let source = format!("!{text}\n\nOutside.\n");
    let mut document = Document::parse(&source);
    let selected = document.blocks()[0].id();
    let outside = document.blocks()[1].clone();
    let at = DocSelection {
        anchor: DocPosition::new(selected, 0),
        focus: DocPosition::new(selected, text.len() as u32),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    assert_eq!(document.blocks()[1], outside);
    let saved = document.serialise();
    let mut reopened = Document::parse(&saved);
    assert_eq!(reopened.blocks().len(), 2);
    assert_eq!(reopened.blocks()[0].kind(), BlockKind::Opaque);
    assert_eq!(reopened.blocks()[1].text(), "Outside.");
    let comment = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0),
        })
        .unwrap();
    assert_eq!(reopened.blocks()[0].text(), text);
    assert_eq!(reopened.blocks()[0].kind(), BlockKind::Action);
    assert_eq!(reopened.blocks()[1].text(), "Outside.");
}

#[test]
fn changed_cue_or_scene_neighbor_rejects_without_consuming_record() {
    for (source, selected, changed) in [
        ("BOB\nHello.\n\nOutside.\n", 1, 0),
        (
            "INT. ONE - DAY #12A#\n\nScene.\n\nEXT. TWO - DAY\n\nNext.\n",
            0,
            2,
        ),
    ] {
        let mut document = Document::parse(source);
        let id = document.blocks()[selected].id();
        let neighbor = document.blocks()[changed].id();
        if selected == 0 {
            document
                .apply(EditCommand::OmitScene { block: id })
                .unwrap();
        } else {
            let at = DocSelection {
                anchor: DocPosition::new(id, 0),
                focus: DocPosition::new(id, document.block(id).unwrap().text().len() as u32),
            };
            document.apply(EditCommand::OmitSelection { at }).unwrap();
        }
        document
            .apply(EditCommand::ReplaceText {
                block: neighbor,
                range: 0..0,
                with: "New ".into(),
            })
            .unwrap();
        let snapshot = document.blocks().to_vec();
        let source = document.serialise();
        let comment = omitted(&document);
        assert_eq!(
            document.apply(EditCommand::RestoreOmitted {
                at: caret(comment, 0)
            }),
            Err(EditError::CannotRestoreOmission)
        );
        assert_eq!(document.blocks(), snapshot);
        assert_eq!(document.serialise(), source);
    }
}

#[test]
fn damaged_record_text_refuses_after_reopen_and_undo_stays_empty() {
    let mut document = Document::parse(
        "Title: Kept\n\nINT. ROOM - DAY #12A#\n\nPayload 😀.\n\nEXT. NEXT - DAY\n\nOutside.\n",
    );
    let heading = document.blocks()[0].id();
    document
        .apply(EditCommand::OmitScene { block: heading })
        .unwrap();
    let saved = document.serialise();
    let damaged = saved.replacen("Payload", "Changed", 1);
    let mut reopened = Document::parse(&damaged);
    let comment = omitted(&reopened);
    assert_eq!(
        reopened.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(reopened.serialise(), damaged);
    assert!(!reopened.can_undo());
}

#[test]
fn partial_cafe_live_and_saved_semantics_agree() {
    let mut document = Document::parse("JOHN\nHello café friend.\n");
    let id = document.blocks()[1].id();
    let at = DocSelection {
        anchor: DocPosition::new(id, "Hello ".len() as u32),
        focus: DocPosition::new(id, "Hello café".len() as u32),
    };
    document
        .apply_with_selection(EditCommand::OmitSelection { at }, Some(at))
        .unwrap();
    let saved = document.serialise();
    assert_eq!(
        semantics(&document),
        semantics(&Document::parse(&saved)),
        "live semantics differ from saved source: {saved}"
    );
}

#[test]
fn unsafe_nested_note_seams_refuse_without_swallowing_the_record_or_later_source() {
    for source in [
        "[[outer [[inner]] end]]\n\nUnchanged.\n",
        "Before [[inner]] after.\n\nUnchanged.\n",
    ] {
        let mut document = Document::parse(source);
        let original = document.blocks().to_vec();
        let text = original[0].text();
        let start = text.find("inner").unwrap() as u32;
        let at = DocSelection {
            anchor: DocPosition::new(original[0].id(), start),
            focus: DocPosition::new(original[0].id(), start + 5),
        };
        assert_eq!(
            document.apply(EditCommand::OmitSelection { at }),
            Err(EditError::BadRange)
        );
        assert_eq!(document.blocks(), original);
        assert_eq!(document.serialise(), source);
        assert!(!document.can_undo());
    }
}

#[test]
fn omitted_speech_and_note_remainders_have_their_saved_kinds_in_the_live_document() {
    for (source, index, start, end) in [
        ("JOHN\nHello café friend.\n", 1, 6, 11),
        ("BOB\n(softly)\nLOUD WORDS\n(then)\nAgain.\n", 1, 2, 5),
        ("BOB\n(softly) tomorrow.\n", 1, 8, 17),
        ("[[outer SELECT end]]\n\nUnchanged.\n", 0, 5, 13),
    ] {
        let mut document = Document::parse(source);
        let original = document.blocks().to_vec();
        let at = DocSelection {
            anchor: DocPosition::new(original[index].id(), end),
            focus: DocPosition::new(original[index].id(), start),
        };
        let result = document
            .apply_with_selection(EditCommand::OmitSelection { at }, Some(at))
            .unwrap();
        let saved = document.serialise();
        assert_eq!(
            semantics(&document),
            semantics(&Document::parse(&saved)),
            "{source}"
        );
        let comment = result.selection.unwrap();
        document
            .apply(EditCommand::RestoreOmitted { at: comment })
            .unwrap();
        assert_eq!(
            semantics(&document),
            semantics(&Document::parse(source)),
            "{source}"
        );
        document.undo().unwrap();
        assert_eq!(document.serialise(), saved);
        assert_eq!(document.undo().unwrap().selection, Some(at));
        assert_eq!(document.blocks(), original);
        assert_eq!(document.serialise(), source);
        assert!(document.undo().is_none());
    }
}

#[test]
fn plain_partial_notes_recover_their_original_marker_trimmed_seam_spaces() {
    let source = "[[alpha REMOVE omega]]\n\nUnchanged.\n";
    let mut document = Document::parse(source);
    let original = semantics(&document);
    let note = document.blocks()[0].id();
    document
        .apply(EditCommand::OmitSelection {
            at: DocSelection {
                anchor: DocPosition::new(note, 6),
                focus: DocPosition::new(note, 12),
            },
        })
        .unwrap();
    let mut reopened = Document::parse(&document.serialise());
    let comment = omitted(&reopened);
    reopened
        .apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0),
        })
        .unwrap();
    assert_eq!(semantics(&reopened), original);
    assert_eq!(semantics(&Document::parse(&reopened.serialise())), original);
}

#[test]
fn orphaned_cue_case_and_witness_follow_the_final_serialization_policy() {
    let mut document = Document::parse("MARY (on radio)\nHello.\n");
    let cue = document.blocks()[0].id();
    let body = document.blocks()[1].id();
    let at = DocSelection {
        anchor: DocPosition::new(body, 0),
        focus: DocPosition::new(body, 6),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let reopened = Document::parse(&document.serialise());
    assert_eq!(
        document.block(cue).unwrap().forced(),
        reopened.blocks()[0].forced(),
        "necessary orphan @ changes extension rendering"
    );
    let mut restored = Document::parse(&document.serialise());
    let restored_comment = omitted(&restored);
    restored
        .apply(EditCommand::RestoreOmitted {
            at: caret(restored_comment, 0),
        })
        .unwrap();
    assert!(!restored.blocks()[0].forced());
    assert_eq!(restored.serialise(), "MARY (on radio)\nHello.\n");
    let comment = omitted(&document);
    document
        .apply(EditCommand::SetKind {
            block: cue,
            kind: BlockKind::Character,
            forced: false,
        })
        .unwrap();
    let blocks = document.blocks().to_vec();
    let revision = document.revision();
    assert_eq!(
        document.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(document.blocks(), blocks);
    assert_eq!(document.revision(), revision);
}

#[test]
fn refused_multi_restore_preserves_existing_redo_text_and_history() {
    let source = "/*\nSlugline omission v99\nblock dialogue 0 0 \"lost?\"\n*/\n\n/* !Real text */\n\nOutside.\n";
    let mut document = Document::parse(source);
    let outside = document.blocks().last().unwrap().id();
    document
        .apply(EditCommand::ReplaceText {
            block: outside,
            range: 8..8,
            with: " Saved in redo.".into(),
        })
        .unwrap();
    document.commit();
    let edited = document.serialise();
    document.undo().unwrap();
    let blocks = document.blocks().to_vec();
    let at = DocSelection {
        anchor: DocPosition::new(blocks[0].id(), 0),
        focus: DocPosition::new(blocks[1].id(), blocks[1].text().len() as u32),
    };
    assert_eq!(
        document.apply(EditCommand::RestoreOmitted { at }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(document.blocks(), blocks);
    assert!(
        document.can_redo(),
        "refusal must not discard user text in redo"
    );
    document.redo().unwrap();
    assert_eq!(document.serialise(), edited);
}

#[test]
fn damaged_record_header_does_not_become_printable_foreign_comment_text() {
    let mut document = Document::parse("JOHN\nHello café friend.\n");
    let id = document.blocks()[1].id();
    let at = DocSelection {
        anchor: DocPosition::new(id, 6),
        focus: DocPosition::new(id, 11),
    };
    document.apply(EditCommand::OmitSelection { at }).unwrap();
    let damaged = document
        .serialise()
        .replace("Slugline omission v2", "xlugline omission v2");
    let mut reopened = Document::parse(&damaged);
    let comment = omitted(&reopened);
    let blocks = reopened.blocks().to_vec();
    assert_eq!(
        reopened.apply(EditCommand::RestoreOmitted {
            at: caret(comment, 0)
        }),
        Err(EditError::CannotRestoreOmission)
    );
    assert_eq!(reopened.blocks(), blocks);
    assert_eq!(reopened.serialise(), damaged);
    assert!(!reopened.can_undo());
}
