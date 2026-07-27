//! §Phase 7's benchmark: a 120-page export in under a second.
//!
//! An assertion rather than a criterion run, for the same reason
//! `layout/tests/pagination_is_fast_enough.rs` is one: a number nobody looks at
//! is a number that drifts. `benches/export.rs` is the criterion version, for
//! when the question is "by how much has this changed".
//!
//! The budget covers the whole export — pagination *and* rendering — because
//! that is what a writer waits for between choosing a file and having one. The
//! best of five runs, so that a busy machine reports the renderer's time rather
//! than the scheduler's.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, DocumentInfo};

const BUDGET: Duration = Duration::from_millis(1000);

fn reference() -> Document {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("the crate is two levels below the workspace root")
        .join("testdata/reference-feature.fountain");
    Document::parse(&fs::read_to_string(path).expect("the reference feature"))
}

#[test]
fn a_feature_length_export_meets_the_phase_7_budget() {
    let document = reference();
    let config = PageConfig::us_letter();
    let info = DocumentInfo {
        title: "The Long Way Round".to_owned(),
        author: "Slugline Test Fixture".to_owned(),
        created_epoch_seconds: 1_700_000_000,
    };

    let mut pages = 0usize;
    let mut bytes = 0usize;
    let best = (0..5)
        .map(|_| {
            let started = Instant::now();
            let script = paginate(&document, &config);
            let pdf = render(&script, &config, &info);
            let elapsed = started.elapsed();
            pages = script.pages.len();
            bytes = pdf.len();
            std::hint::black_box(pdf);
            elapsed
        })
        .min()
        .expect("at least one timing run");

    // Printed, so that a regression says by how much rather than only that it
    // happened — the same reason the keystroke benchmark prints its table.
    println!(
        "export: {pages} pages, {} kB, {best:?} (budget {BUDGET:?})",
        bytes / 1024
    );
    assert!(
        pages >= 100,
        "the fixture is feature length, not {pages} pages"
    );
    assert!(best < BUDGET, "a {pages}-page export took {best:?}");
}

#[test]
fn subsetting_keeps_a_feature_length_export_to_a_sendable_size() {
    // §Phase 7 asks for "font subsetting to keep file size reasonable". The
    // faces are 305 kB between them and a screenplay uses about a hundred and
    // twenty characters of them, so the whole 120-page export should come to
    // less than embedding one face whole would have added.
    let config = PageConfig::us_letter();
    let pdf = render(
        &paginate(&reference(), &config),
        &config,
        &DocumentInfo::default(),
    );
    let faces = String::from_utf8_lossy(&pdf).matches("/FontFile2").count();
    println!(
        "export: {} kB with {faces} embedded face(s)",
        pdf.len() / 1024
    );
    assert!(faces >= 1, "at least one face is embedded");
    assert!(
        pdf.len() < 1_500_000,
        "a 120-page export is {} kB",
        pdf.len() / 1024
    );
}
