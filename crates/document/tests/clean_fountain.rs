//! X6: source syntax persists meaning, not redundant live element pins.
use slugline_document::{BlockKind, Document, EditCommand};

fn semantics(document: &Document) -> Vec<(BlockKind, String, bool)> {
    document
        .blocks()
        .iter()
        .map(|block| (block.kind(), block.text().to_owned(), block.dual()))
        .collect()
}

#[test]
fn edited_pins_write_clean_syntax_without_mutating_the_live_document() {
    let source = "INT. CAFÉ - DAY\n\nShe waits — 日本 🎬.\n\nMARY ^\nHello.\n\nCUT TO:\n";
    let mut document = Document::parse(source);
    let before = semantics(&document);
    let pins: Vec<_> = document
        .blocks()
        .iter()
        .map(|b| (b.id(), b.kind()))
        .collect();
    for (block, kind) in &pins {
        document
            .apply(EditCommand::SetKind {
                block: *block,
                kind: *kind,
                forced: true,
            })
            .unwrap();
    }
    let revision = document.revision();
    let expected = "INT. CAFÉ - DAY\n\nShe waits — 日本 🎬.\n\nMARY ^\nHello.\n\nCUT TO:\n";
    assert_eq!(document.serialise(), expected);
    assert_eq!(document.serialisation_snapshot().serialise(), expected);
    assert_eq!(
        document.revision(),
        revision,
        "serialisation is not an edit"
    );
    assert_eq!(semantics(&document), before);
    assert!(
        document.blocks().iter().all(|b| b.forced()),
        "live pins survive Save"
    );
    assert_eq!(semantics(&Document::parse(expected)), before);
}

#[test]
fn editing_one_explicit_cue_preserves_other_provenance_and_undo_restores_its_pin() {
    let source = "\u{feff}Title: Exact\r\n\r\n.INT. HOUSE - DAY  \r\n\r\n@MARY\r\nHello.\r\n\r\n!Untouched\t  \r\n";
    let mut document = Document::parse(source);
    let cue = document.blocks()[1].id();
    document
        .apply(EditCommand::ReplaceText {
            block: cue,
            range: 0..4,
            with: "ANNE".into(),
        })
        .unwrap();
    let edited = source.replace("@MARY\r\n", "ANNE\r\n");
    assert_eq!(document.serialise(), edited);
    assert!(document.block(cue).unwrap().forced());
    let reopened = Document::parse(&edited);
    assert_eq!(semantics(&reopened), semantics(&document));
    assert_eq!(reopened.serialise(), edited);
    document.undo().unwrap();
    assert_eq!(
        document.serialise(),
        source,
        "Undo restores original marked CRLF bytes"
    );
    assert!(document.block(cue).unwrap().forced());
    document.redo().unwrap();
    assert_eq!(document.serialise(), edited);
}

#[test]
fn authored_case_and_orphan_context_survive_edit_save_reload() {
    for (name, prefix) in [
        ("ÉLODIE", ""),
        ("McCLANE", "@"),
        ("mary", "@"),
        ("日本 🎬", "@"),
    ] {
        let mut document = Document::parse("@MARY\nHello.\n");
        let id = document.blocks()[0].id();
        document
            .apply(EditCommand::ReplaceText {
                block: id,
                range: 0..4,
                with: name.into(),
            })
            .unwrap();
        let saved = document.serialise();
        assert_eq!(saved, format!("{prefix}{name}\nHello.\n"));
        assert_eq!(semantics(&Document::parse(&saved)), semantics(&document));
        let dialogue = document.blocks()[1].id();
        document
            .apply(EditCommand::ReplaceText {
                block: dialogue,
                range: 0..6,
                with: String::new(),
            })
            .unwrap();
        let orphan = document.serialise();
        assert_eq!(orphan, format!("@{name}\n"));
        let reopened = Document::parse(&orphan);
        assert_eq!(reopened.blocks()[0].kind(), BlockKind::Character);
        assert_eq!(reopened.blocks()[0].text(), name);
    }
}
