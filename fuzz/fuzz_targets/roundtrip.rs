//! Fuzz target: any input, parsed and written straight back, is unchanged.
//!
//!     cargo +nightly fuzz run roundtrip -- -runs=1000000
//!
//! This is `roundtrip_is_byte_exact` (§13) with the corpus replaced by whatever
//! the fuzzer can think of. The corpus proves the cases we thought of; this
//! looks for the ones we did not.

#![no_main]

use libfuzzer_sys::fuzz_target;
use slugline_fountain::{parse, serialise, Element, Output};

fuzz_target!(|data: &[u8]| {
    let source = String::from_utf8_lossy(data);
    let script = parse(&source);
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();

    let written = serialise(&Output {
        title_page: &script.title_page,
        elements: &elements,
        source: Some(&source),
        bom: script.bom,
        line_ending: script.line_ending,
    });
    assert_eq!(written, source, "an unedited document did not resave exactly");

    // And the canonical path, as an edit to every block would leave it. It has
    // no byte-exactness to offer, but it must terminate and must not panic.
    let edited: Vec<_> = elements
        .iter()
        .map(|element| slugline_fountain::ElementRef {
            provenance: None,
            ..element.clone()
        })
        .collect();
    let canonical = serialise(&Output {
        title_page: &slugline_fountain::TitlePage {
            entries: script.title_page.entries.clone(),
            provenance: None,
        },
        elements: &edited,
        source: None,
        bom: script.bom,
        line_ending: script.line_ending,
    });
    parse(&canonical);
});
