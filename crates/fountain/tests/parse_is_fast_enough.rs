//! Phase 1's budget: parsing the 120-page reference feature in under 100 ms.
//!
//! `cargo bench -p slugline_fountain` is where the number comes from; this is
//! the gate, so that a regression fails CI on the commit that caused it rather
//! than the next time somebody runs a benchmark. It measures the best of a few
//! runs, because the budget is about the code and a shared CI runner's worst
//! run is about the runner.
//!
//! The threshold is the spec's 100 ms even in a debug build, which is where
//! `cargo test` runs. That is not generosity: the release figure is ~0.44 ms,
//! and an unoptimised build is comfortably inside the budget too. If this test
//! ever fails, something has become algorithmically worse, not incrementally
//! slower.

use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use slugline_fountain::{parse, serialise, Element, Output};

const BUDGET: Duration = Duration::from_millis(100);

fn reference() -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|path| path.parent())
        .expect("workspace root")
        .join("testdata")
        .join("reference-feature.fountain");
    fs::read_to_string(path).expect("the reference feature is committed to testdata/")
}

fn best_of<T>(runs: usize, mut work: impl FnMut() -> T) -> Duration {
    (0..runs)
        .map(|_| {
            let started = Instant::now();
            let result = work();
            let elapsed = started.elapsed();
            drop(std::hint::black_box(result));
            elapsed
        })
        .min()
        .expect("at least one run")
}

#[test]
fn the_reference_feature_parses_within_the_budget() {
    let source = reference();
    assert!(
        source.len() > 100_000,
        "the reference feature should be a 120-page script, not {} bytes",
        source.len()
    );

    let elapsed = best_of(5, || parse(&source));
    println!("parse: {elapsed:?} (budget {BUDGET:?})");
    assert!(
        elapsed < BUDGET,
        "parsing the reference feature took {elapsed:?}, over the {BUDGET:?} budget"
    );
}

#[test]
fn the_reference_feature_saves_within_the_budget() {
    // Not a budget the spec names, but saving is on the same path as opening
    // and a quadratic serialiser would be just as bad a surprise.
    let source = reference();
    let script = parse(&source);
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();

    let elapsed = best_of(5, || {
        serialise(&Output {
            title_page: &script.title_page,
            elements: &elements,
            source: Some(&source),
            bom: script.bom,
            line_ending: script.line_ending,
        })
    });
    println!("serialise: {elapsed:?} (budget {BUDGET:?})");
    assert!(
        elapsed < BUDGET,
        "saving the reference feature took {elapsed:?}, over the {BUDGET:?} budget"
    );
}
