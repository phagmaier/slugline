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
