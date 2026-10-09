use std::fs;
use std::path::PathBuf;

use slugline_document::Document;
use slugline_layout::{LayoutEngine, PageConfig, ScriptSnapshot};

fn reference() -> Document {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("workspace root")
        .join("testdata/reference-feature.fountain");
    Document::parse(&fs::read_to_string(path).expect("reference feature"))
}

#[test]
fn one_edit_invalidates_one_block_and_reuses_a_checkpoint_prefix() {
    let document = reference();
    let mut snapshot = ScriptSnapshot::from(&document);
    let mut engine = LayoutEngine::new();
    let initial = engine.paginate_snapshot(&snapshot, &PageConfig::us_letter());
    assert!(initial.pages.len() > 16, "reference must cross checkpoints");

    let changed = snapshot.blocks.len() * 3 / 4;
    let changed_id = snapshot.blocks[changed].id;
    snapshot.blocks[changed].text.push_str(" changed");
    snapshot.revision += 1;
    let updated = engine.repaginate(&snapshot, &PageConfig::us_letter(), changed_id);

    assert_eq!(updated.stats.block_misses, 1);
    assert_eq!(
        updated.stats.block_hits + updated.stats.block_misses,
        initial.stats.block_misses
    );
    assert!(updated.stats.reused_pages >= 8);
    assert_eq!(
        initial.pages[..updated.stats.reused_pages],
        updated.pages[..updated.stats.reused_pages]
    );
}

#[test]
fn reference_pagination_is_identical_one_hundred_times() {
    let document = reference();
    let snapshot = ScriptSnapshot::from(&document);
    let mut engine = LayoutEngine::new();
    let expected = engine
        .paginate_snapshot(&snapshot, &PageConfig::us_letter())
        .debug_dump();
    for _ in 0..100 {
        assert_eq!(
            engine
                .paginate_snapshot(&snapshot, &PageConfig::us_letter())
                .debug_dump(),
            expected
        );
    }
}

#[test]
fn cached_omit_restore_undo_redo_never_reuses_printed_omitted_material() {
    use slugline_document::{BlockKind, DocPosition, DocSelection, EditCommand};
    let mut source = String::new();
    for index in 0..20 {
        source.push_str(&format!(
            "INT. ROOM {index} - DAY\n\n{}\n\n",
            "Visible words. ".repeat(180)
        ));
    }
    let mut document = Document::parse(&source);
    let scene = document
        .blocks()
        .iter()
        .filter(|block| block.kind() == BlockKind::SceneHeading)
        .nth(15)
        .unwrap()
        .id();
    let config = PageConfig::us_letter();
    let mut engine = LayoutEngine::new();
    engine.paginate_snapshot(&ScriptSnapshot::from(&document), &config);
    let omitted = document
        .apply(EditCommand::OmitScene { block: scene })
        .unwrap();
    let comment = omitted.selection.unwrap().focus.block;
    for step in 0..6 {
        let result = match step {
            0 => omitted.clone(),
            1 => document
                .apply(EditCommand::RestoreOmitted {
                    at: DocSelection::caret(DocPosition::new(comment, 0)),
                })
                .unwrap(),
            2 | 3 => document.undo().unwrap(),
            4 | 5 => document.redo().unwrap(),
            _ => unreachable!(),
        };
        let snapshot = ScriptSnapshot::from(&document);
        let hint = result.selection.unwrap().focus.block;
        let cached = engine.repaginate(&snapshot, &config, hint);
        let fresh = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
        assert_eq!(cached.pages, fresh.pages, "step {step}");
        let printed = cached
            .pages
            .iter()
            .flat_map(|page| page.lines.iter())
            .map(|line| line.content.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        assert_eq!(
            printed.contains("ROOM 15"),
            matches!(step, 1 | 3 | 5),
            "step {step}"
        );
        assert!(!printed.contains("Slugline omission"));
    }
}
