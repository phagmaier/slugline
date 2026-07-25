//! `roundtrip_is_byte_exact` — §13's named invariant: an unedited file resaves
//! identically.
//!
//! Every file in `testdata/corpus/` plus the 120-page reference feature is
//! parsed and written straight back out; the result must equal the input byte
//! for byte, including line endings, trailing whitespace, tabs and a BOM. The
//! corpus is chosen by §4.3 to make that hard in a different way in each file.

use std::fs;
use std::path::PathBuf;

use slugline_fountain::{parse, serialise, BlockKind, Element, Output, TitleField};

/// Every fixture: the corpus files and the reference feature.
fn fixtures() -> Vec<(String, String)> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("crates/fountain has a workspace root above it")
        .join("testdata");

    let mut paths: Vec<PathBuf> = fs::read_dir(root.join("corpus"))
        .expect("testdata/corpus exists")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "fountain"))
        .collect();
    paths.push(root.join("reference-feature.fountain"));
    paths.sort();

    assert!(
        paths.len() >= 11,
        "§4.3 requires at least eleven fixtures, found {}",
        paths.len()
    );

    paths
        .into_iter()
        .map(|path| {
            let name = path
                .file_name()
                .expect("fixtures are files")
                .to_string_lossy()
                .into_owned();
            let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("{name}: {e}"));
            (name, text)
        })
        .collect()
}

fn resave(source: &str) -> String {
    let script = parse(source);
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
    serialise(&Output {
        title_page: &script.title_page,
        elements: &elements,
        source: Some(source),
        bom: script.bom,
        line_ending: script.line_ending,
    })
}

#[test]
fn every_fixture_resaves_byte_for_byte() {
    for (name, source) in fixtures() {
        let written = resave(&source);
        assert_eq!(
            written.as_bytes(),
            source.as_bytes(),
            "{name} did not survive a round trip"
        );
    }
}

#[test]
fn every_prefix_of_every_fixture_resaves_byte_for_byte() {
    // Truncation is where a parser's edge cases live: an unterminated note, a
    // cue with its dialogue cut off, a file that stops mid-character.
    for (name, source) in fixtures() {
        // Roughly four hundred cuts per file, wherever the file is small enough
        // to take them one character apart.
        let step = (source.len() / 400).max(1);
        for (at, _) in source.char_indices().step_by(step) {
            let prefix = &source[..at];
            assert_eq!(
                resave(prefix).as_bytes(),
                prefix.as_bytes(),
                "{name} truncated at {at} did not survive a round trip"
            );
        }
    }
}

#[test]
fn provenance_tiles_every_fixture() {
    // The property byte-exactness is a consequence of: the title page and the
    // blocks between them account for every byte after the BOM, in order.
    for (name, source) in fixtures() {
        let script = parse(&source);
        let mut cursor = if script.bom { '\u{feff}'.len_utf8() } else { 0 };
        let title = script
            .title_page
            .provenance
            .clone()
            .unwrap_or_else(|| panic!("{name}: parsed title page has no provenance"));
        assert_eq!(title.start, cursor, "{name}: gap before the title page");
        cursor = title.end;

        for element in &script.elements {
            let range = element
                .provenance
                .clone()
                .unwrap_or_else(|| panic!("{name}: parsed block has no provenance"));
            assert_eq!(range.start, cursor, "{name}: gap before {:?}", element.kind);
            assert!(range.start <= range.end, "{name}: inverted range");
            cursor = range.end;
        }
        assert_eq!(
            cursor,
            source.len(),
            "{name}: tiling stopped short of the end"
        );
    }
}

#[test]
fn the_corpus_covers_every_element_kind() {
    let mut seen = Vec::new();
    for (_, source) in fixtures() {
        for element in parse(&source).elements {
            let kind = match element.kind {
                // Section levels differ but the kind is one kind.
                BlockKind::Section { .. } => BlockKind::Section { level: 1 },
                other => other,
            };
            if !seen.contains(&kind) {
                seen.push(kind);
            }
        }
    }

    for kind in [
        BlockKind::SceneHeading,
        BlockKind::Action,
        BlockKind::Character,
        BlockKind::Dialogue,
        BlockKind::Parenthetical,
        BlockKind::Transition,
        BlockKind::Centered,
        BlockKind::Lyric,
        BlockKind::Section { level: 1 },
        BlockKind::Synopsis,
        BlockKind::Note,
        BlockKind::PageBreak,
        BlockKind::Opaque,
    ] {
        assert!(seen.contains(&kind), "no corpus file contains a {kind:?}");
    }
}

#[test]
fn the_corpus_covers_the_awkward_encodings() {
    let fixtures = fixtures();
    let by_name = |name: &str| {
        fixtures
            .iter()
            .find(|(file, _)| file == name)
            .map(|(_, text)| text.clone())
            .unwrap_or_else(|| panic!("{name} is missing from the corpus"))
    };

    assert!(
        parse(&by_name("07-bom.fountain")).bom,
        "the BOM fixture has no BOM"
    );
    assert_eq!(
        parse(&by_name("06-crlf.fountain")).line_ending,
        slugline_fountain::LineEnding::CrLf
    );
    assert!(
        !by_name("10-malformed.fountain").ends_with('\n'),
        "the truncated fixture must not end with a newline"
    );
    assert!(
        by_name("09-whitespace.fountain").contains("  \n"),
        "the whitespace fixture must contain trailing spaces"
    );
    assert!(
        by_name("09-whitespace.fountain").contains('\t'),
        "the whitespace fixture must contain a tab"
    );

    let title = parse(&by_name("05-title-page.fountain")).title_page;
    assert_eq!(
        title.get(&TitleField::Title),
        Some("_**BRASS TACKS**_\nPart Two"),
        "multi-line title values must survive"
    );
    assert!(title
        .get(&TitleField::Other("Revision Colour".into()))
        .is_some());
}
