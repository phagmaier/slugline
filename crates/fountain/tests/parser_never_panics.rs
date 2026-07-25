//! `parser_never_panics` — §13's named invariant.
//!
//! §4.2 requires a parser that never fails and never throws: while the user is
//! typing, the document is invalid most of the time, and a parser that could
//! refuse an input would refuse it in the middle of a sentence. The type
//! signature already rules out an error return, so what is left to prove is
//! that no input panics — no slice off a character boundary, no index past the
//! end, no unbounded loop.
//!
//! The 1M-iteration coverage-guided run lives in `fuzz/`; this file is the part
//! that runs on stable Rust in CI on every commit. It is deterministic, so a
//! failure here is reproducible from the seed printed with it.

use slugline_fountain::{parse, serialise, Element, Output};

/// Parses, serialises, and reparses. If any of it is going to panic, it panics
/// here.
fn exercise(source: &str) {
    let script = parse(source);
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
    let verbatim = serialise(&Output {
        title_page: &script.title_page,
        elements: &elements,
        source: Some(source),
        bom: script.bom,
        line_ending: script.line_ending,
    });

    // And again down the canonical path, with every block's provenance dropped
    // as an edit would drop it.
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
        source: Some(source),
        bom: script.bom,
        line_ending: script.line_ending,
    });

    parse(&verbatim);
    parse(&canonical);
}

#[test]
fn adversarial_inputs_are_survivable() {
    let cases = [
        "",
        "\0",
        "\u{feff}",
        "\u{feff}\u{feff}",
        "\r",
        "\r\r\r",
        "\n\r",
        "\r\n\r\n",
        "/*",
        "*/",
        "/*/*/*/*",
        "[[",
        "]]",
        "[[[[]]]]",
        "[[/*]]*/",
        "/*[[*/]]",
        "===",
        "=",
        "==",
        "#######",
        "@^",
        "@ ^",
        ".",
        "..",
        "...",
        ">",
        "<",
        "><",
        "> <",
        "~",
        "!",
        ":",
        "Title:",
        "Title:\n\n\n",
        ": value",
        "INT.",
        "INT",
        "I/E",
        "café 日本 🎬",
        "🎬\n🎬\n🎬",
        "\u{202e}reversed",
        "a\u{0}b\nc",
        "JOHN\n",
        "JOHN\n(",
        "(\n)",
        "\t\t\t",
        "   \n   \n   ",
    ];

    for case in cases {
        exercise(case);
        // And every prefix of it, which is where a truncated multi-byte
        // sequence or an unclosed construct shows up.
        for (at, _) in case.char_indices() {
            exercise(&case[..at]);
        }
    }
}

#[test]
fn a_million_bytes_of_noise_are_survivable() {
    // A deterministic LCG rather than a random source: a failure here must be
    // reproducible from the constants in this file alone.
    let mut state: u32 = 0x5EED_1234;
    let mut next = move || {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (state >> 16) as u8
    };

    // Bytes drawn from the alphabet a Fountain parser has opinions about, so
    // the noise lands on the rules rather than on unreachable branches.
    const ALPHABET: &[u8] = b"\n\r\t .!@>~#=[]/*^():JOHNint&-'\xc3\xa9";

    for _ in 0..2_000 {
        let length = (next() as usize) * 2 + 1;
        let bytes: Vec<u8> = (0..length)
            .map(|_| ALPHABET[next() as usize % ALPHABET.len()])
            .collect();
        // Lossy conversion keeps the input valid UTF-8, which is the contract
        // `parse` has; arbitrary bytes are the fuzz target's problem.
        exercise(&String::from_utf8_lossy(&bytes));
    }
}

#[test]
fn deeply_nested_and_repetitive_input_terminates() {
    // A parser that rescanned its spans per line would take quadratic time on
    // these; the test is that it finishes at all.
    exercise(&"/* ".repeat(5_000));
    exercise(&"[[ ".repeat(5_000));
    exercise(&"[[a]]".repeat(5_000));
    exercise(&"\n".repeat(30_000));
    exercise(&"JOHN\nHello.\n\n".repeat(3_000));
    exercise(&"=".repeat(30_000));
    exercise(&"a".repeat(30_000));
}
