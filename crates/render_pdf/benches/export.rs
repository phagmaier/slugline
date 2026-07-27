//! §Phase 7: a 120-page export in under a second.
//!
//! The number in the exit criterion is wall-clock for the whole export, so this
//! measures pagination and rendering together — the two halves a user waits for
//! between choosing a file and having one.

use criterion::{criterion_group, criterion_main, Criterion};
use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, DocumentInfo};

fn feature_length() -> String {
    let mut source = String::from("Title: The Benchmark\nAuthor: Nobody\n\n");
    for scene in 0..120 {
        source.push_str(&format!("INT. LOCATION {scene} - DAY\n\n"));
        source.push_str("Someone crosses the room and looks out of the window at the rain.\n\n");
        source
            .push_str("JOHN\n(quietly)\nWe have been here before, and we will be here again.\n\n");
        source.push_str("She does not answer. The *rain* goes on.\n\n");
    }
    source
}

fn export(criterion: &mut Criterion) {
    let document = Document::parse(&feature_length());
    let config = PageConfig::us_letter();
    let info = DocumentInfo {
        title: "The Benchmark".to_owned(),
        author: "Nobody".to_owned(),
        created_epoch_seconds: 1_700_000_000,
    };

    criterion.bench_function("export_120_pages", |bencher| {
        bencher.iter(|| render(&paginate(&document, &config), &config, &info))
    });
}

criterion_group!(benches, export);
criterion_main!(benches);
