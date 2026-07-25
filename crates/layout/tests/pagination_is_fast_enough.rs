use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use slugline_document::Document;
use slugline_layout::{LayoutEngine, PageConfig, ScriptSnapshot};

const FULL_BUDGET: Duration = Duration::from_millis(50);
const INCREMENTAL_BUDGET: Duration = Duration::from_millis(5);

fn reference() -> ScriptSnapshot {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("workspace root")
        .join("testdata/reference-feature.fountain");
    let source = fs::read_to_string(path).expect("reference feature");
    ScriptSnapshot::from(&Document::parse(&source))
}

fn best_of(runs: usize, mut work: impl FnMut()) -> Duration {
    (0..runs)
        .map(|_| {
            let started = Instant::now();
            work();
            started.elapsed()
        })
        .min()
        .expect("at least one timing run")
}

#[test]
fn full_and_incremental_pagination_meet_the_phase_6_budgets() {
    let snapshot = reference();
    let config = PageConfig::us_letter();
    let full = best_of(5, || {
        let output = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
        std::hint::black_box(output);
    });
    assert!(full < FULL_BUDGET, "full pagination took {full:?}");

    let mut engine = LayoutEngine::new();
    engine.paginate_snapshot(&snapshot, &config);
    let changed_index = snapshot.blocks.len() * 3 / 4;
    let changed_id = snapshot.blocks[changed_index].id;
    let mut first = snapshot.clone();
    let first_character_bytes = first.blocks[changed_index]
        .text
        .chars()
        .next()
        .expect("reference block has text")
        .len_utf8();
    first.blocks[changed_index]
        .text
        .replace_range(..first_character_bytes, "x");
    first.revision += 1;
    let mut second = snapshot.clone();
    second.blocks[changed_index]
        .text
        .replace_range(..first_character_bytes, "y");
    second.revision += 2;
    let mut alternate = false;
    let mut last_stats = slugline_layout::CacheStats::default();
    let incremental = best_of(10, || {
        let changed = if alternate { &first } else { &second };
        alternate = !alternate;
        let output = engine.repaginate(changed, &config, changed_id);
        last_stats = output.stats;
        std::hint::black_box(output);
    });
    println!("full: {full:?}; incremental: {incremental:?}; {last_stats:?}");
    assert!(
        incremental < INCREMENTAL_BUDGET,
        "incremental pagination took {incremental:?}"
    );
}
