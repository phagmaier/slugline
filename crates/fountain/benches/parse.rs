//! Phase 1's performance gate: parsing the 120-page reference feature in under
//! 100 ms.
//!
//! Run with `cargo bench -p slugline_fountain`. The budget is asserted as a
//! test in `tests/parse_is_fast_enough.rs` so that CI fails on a regression
//! without having to run the full benchmark; this file is where the number
//! comes from when you want to know *how* fast, not just fast enough.

use std::fs;
use std::path::PathBuf;

use criterion::{criterion_group, criterion_main, Criterion};
use slugline_fountain::{parse, serialise, Element, Output};

fn reference() -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("workspace root")
        .join("testdata")
        .join("reference-feature.fountain");
    fs::read_to_string(path).expect("the reference feature is generated into testdata/")
}

fn benchmarks(c: &mut Criterion) {
    let source = reference();

    c.bench_function("parse reference feature", |b| {
        b.iter(|| parse(std::hint::black_box(&source)))
    });

    let script = parse(&source);
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
    c.bench_function("serialise reference feature (verbatim)", |b| {
        b.iter(|| {
            serialise(&Output {
                title_page: &script.title_page,
                elements: &elements,
                source: Some(&source),
                bom: script.bom,
                line_ending: script.line_ending,
            })
        })
    });

    let edited: Vec<_> = elements
        .iter()
        .map(|element| slugline_fountain::ElementRef {
            provenance: None,
            ..element.clone()
        })
        .collect();
    c.bench_function("serialise reference feature (canonical)", |b| {
        b.iter(|| {
            serialise(&Output {
                title_page: &script.title_page,
                elements: &edited,
                source: Some(&source),
                bom: script.bom,
                line_ending: script.line_ending,
            })
        })
    });
}

criterion_group!(benches, benchmarks);
criterion_main!(benches);
