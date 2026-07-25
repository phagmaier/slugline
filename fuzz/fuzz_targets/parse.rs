//! Fuzz target: the parser must not panic on any input (§13).
//!
//! Takes arbitrary *bytes* rather than a `&str`, because that is what a file on
//! disk is. Invalid UTF-8 is the caller's problem — `storage` decides what to do
//! with a file that is not text — so the bytes are converted lossily here and
//! the parser is handed what it is contracted to take.
//!
//!     cargo +nightly fuzz run parse -- -runs=1000000
//!
//! The stable-Rust half of this lives in
//! `crates/fountain/tests/parser_never_panics.rs`, which CI runs on every
//! commit.

#![no_main]

use libfuzzer_sys::fuzz_target;
use slugline_fountain::parse;

fuzz_target!(|data: &[u8]| {
    let source = String::from_utf8_lossy(data);
    let script = parse(&source);

    // The invariant the rest of the correctness story rests on: the provenance
    // ranges tile the source exactly, in order, after the BOM. If fuzzing can
    // break the tiling it can break byte-exact round-tripping, which §1.2 calls
    // a P0.
    let mut cursor = if script.bom { '\u{feff}'.len_utf8() } else { 0 };
    let title = script
        .title_page
        .provenance
        .clone()
        .expect("a parsed title page always has provenance");
    assert_eq!(title.start, cursor);
    cursor = title.end;

    for element in &script.elements {
        let range = element
            .provenance
            .clone()
            .expect("a parsed block always has provenance");
        assert_eq!(range.start, cursor, "gap before {:?}", element.kind);
        assert!(range.start <= range.end);
        cursor = range.end;
    }
    assert_eq!(cursor, source.len(), "tiling stopped short of the end");
});
