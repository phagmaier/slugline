//! §Phase 7's text-extraction test: `pdftotext` output matches expected content
//! and reading order.
//!
//! "Selectable and searchable in `evince`, `okular`, Firefox and Chrome" is the
//! requirement, and none of those four can be driven from `cargo test`. What
//! *can* be is the thing all four of them do underneath: map each glyph back to
//! the character it was drawn for, and read the page in order. `pdftotext` is
//! poppler, which is what `evince` and `okular` use, so this test is the same
//! question those two answer — and the mechanism it exercises, the `/ToUnicode`
//! CMap, is the one Firefox and Chrome use too. The manual check in the four
//! viewers is §5.5's calibration pass, recorded in `docs/DECISIONS.md`.
//!
//! Without `pdftotext` on the path there is nothing to compare against, so the
//! test says so and stops. CI installs `poppler-utils` and therefore runs it for
//! real; a developer without it gets a printed line rather than a false green.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, DocumentInfo};

const SCRIPT: &str = "\
Title: The Long Way Round
Credit: Written by
Author: Ada Lovelace
Draft date: 26 July 2026

FADE IN:

INT. LIBRARY - DAWN

George watches the rain. Some of this is *italic*, some is **bold**, and
some is _underlined_ — and none of the markers should come out.

NADIA
(quietly)
We agreed on the unopened post.

TOMÁS
Café, straße, and a clapperboard.

CUT TO:
";

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("the crate is two levels below the workspace root")
        .to_owned()
}

/// Writes a PDF to a scratch path and returns what `pdftotext` reads back.
///
/// `None` when poppler is not installed.
fn extract(bytes: &[u8], arguments: &[&str]) -> Option<String> {
    let mut child = Command::new("pdftotext")
        .args(arguments)
        .args(["-", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    child
        .stdin
        .as_mut()
        .expect("the child has a stdin")
        .write_all(bytes)
        .expect("the PDF is written to pdftotext");
    let output = child.wait_with_output().expect("pdftotext finishes");
    assert!(output.status.success(), "pdftotext refused the file");
    Some(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn export(source: &str) -> Vec<u8> {
    let config = PageConfig::us_letter();
    let document = Document::parse(source);
    render(
        &paginate(&document, &config),
        &config,
        &DocumentInfo {
            title: "The Long Way Round".to_owned(),
            author: "Ada Lovelace".to_owned(),
            created_epoch_seconds: 1_700_000_000,
        },
    )
}

/// Says why the test did nothing, rather than passing quietly.
fn require_pdftotext(text: Option<String>) -> Option<String> {
    if text.is_none() {
        println!(
            "SKIPPED: pdftotext is not installed. Install poppler-utils to run \
             this test; CI does."
        );
    }
    text
}

#[test]
fn the_text_comes_out_in_reading_order_with_no_markup_in_it() {
    let Some(text) = require_pdftotext(extract(&export(SCRIPT), &[])) else {
        return;
    };

    // Reading order: each of these appears after the one before it.
    let expected = [
        "The Long Way Round",
        "Written by",
        "Ada Lovelace",
        "FADE IN:",
        "INT. LIBRARY - DAWN",
        "George watches the rain.",
        "NADIA",
        "(quietly)",
        "We agreed on the unopened post.",
        "TOMÁS",
        "CUT TO:",
    ];
    let mut at = 0usize;
    for wanted in expected {
        let found = text[at..]
            .find(wanted)
            .unwrap_or_else(|| panic!("{wanted:?} is missing or out of order in:\n{text}"));
        at += found + wanted.len();
    }

    // The emphasis markers were a typeface, not characters.
    assert!(text.contains("italic"), "the emphasised words are there");
    assert!(text.contains("bold"));
    assert!(text.contains("underlined"));
    assert!(!text.contains('*'), "no asterisk survived into the text");
    assert!(
        !text.contains("_underlined_"),
        "no underscore survived either"
    );

    // Non-ASCII round-trips through the `/ToUnicode` CMap.
    assert!(text.contains("TOMÁS"));
    assert!(text.contains("Café, straße"));
}

#[test]
fn the_title_page_is_the_first_page_and_the_screenplay_starts_at_page_one() {
    let bytes = export(SCRIPT);
    let Some(first) = require_pdftotext(extract(&bytes, &["-f", "1", "-l", "1"])) else {
        return;
    };
    let second = extract(&bytes, &["-f", "2", "-l", "2"]).expect("poppler is here");

    assert!(first.contains("The Long Way Round"));
    assert!(
        !first.contains("FADE IN:"),
        "the title page carries no screenplay"
    );
    assert!(
        !first.contains("1."),
        "and no page number: it is not page one"
    );
    assert!(second.contains("1."), "the screenplay's first page is 1.");
    assert!(second.contains("FADE IN:"));
}

#[test]
fn the_reference_feature_extracts_to_every_scene_it_has() {
    // The 120-page fixture, so that reading order is proved over a real script
    // rather than a page of one.
    let source = fs::read_to_string(workspace_root().join("testdata/reference-feature.fountain"))
        .expect("the reference feature");
    let Some(text) = require_pdftotext(extract(&export(&source), &[])) else {
        return;
    };

    let headings = source
        .lines()
        .filter(|line| line.starts_with("INT. ") || line.starts_with("EXT. "))
        .count();
    let extracted = text
        .lines()
        .filter(|line| {
            line.trim_start().starts_with("INT. ") || line.trim_start().starts_with("EXT. ")
        })
        .count();
    assert_eq!(
        extracted, headings,
        "every scene heading in the script is selectable in the PDF"
    );
}
