use std::fs;
use std::path::PathBuf;

use criterion::{criterion_group, criterion_main, Criterion};
use slugline_document::Document;
use slugline_layout::{LayoutEngine, PageConfig, ScriptSnapshot};

fn reference() -> ScriptSnapshot {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("workspace root")
        .join("testdata/reference-feature.fountain");
    ScriptSnapshot::from(&Document::parse(
        &fs::read_to_string(path).expect("reference feature"),
    ))
}

fn benchmarks(c: &mut Criterion) {
    let snapshot = reference();
    let config = PageConfig::us_letter();
    c.bench_function("paginate reference feature (full)", |b| {
        b.iter(|| LayoutEngine::new().paginate_snapshot(&snapshot, &config))
    });

    let changed_index = snapshot.blocks.len() * 3 / 4;
    let changed_id = snapshot.blocks[changed_index].id;
    let first_character_bytes = snapshot.blocks[changed_index]
        .text
        .chars()
        .next()
        .expect("reference block has text")
        .len_utf8();
    let mut first = snapshot.clone();
    first.blocks[changed_index]
        .text
        .replace_range(..first_character_bytes, "x");
    first.revision += 1;
    let mut second = snapshot.clone();
    second.blocks[changed_index]
        .text
        .replace_range(..first_character_bytes, "y");
    second.revision += 2;
    let mut engine = LayoutEngine::new();
    engine.paginate_snapshot(&snapshot, &config);
    let mut alternate = false;
    c.bench_function("paginate reference feature (incremental)", |b| {
        b.iter(|| {
            let changed = if alternate { &first } else { &second };
            alternate = !alternate;
            engine.repaginate(changed, &config, changed_id)
        })
    });
}

criterion_group!(benches, benchmarks);
criterion_main!(benches);
