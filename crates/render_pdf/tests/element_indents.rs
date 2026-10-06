//! §Phase 7's exit criterion, as far as a test can carry it.
//!
//! "A printed page overlaid on a reference-tool page matches on every element
//! indent." The overlay itself is §5.5's manual pass and is recorded in ADR
//! 0034; what a test can do is pin the numbers that overlay measured, so that
//! the next change to the renderer or the grid has to be a deliberate one.
//!
//! The measurement is taken the way the overlay was taken: out of the finished
//! PDF, by reading where the text operators put each line. Not out of
//! `layout::metrics` — that would be the renderer agreeing with itself.

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, DocumentInfo};

const SCRIPT: &str = "\
INT. LIBRARY - DAWN

George watches the rain against the window and says nothing at all.

NADIA
(quietly)
We agreed on the unopened post.

CUT TO:

> CENTERED <
";

/// Every `Tm ... Tj` on the first screenplay page, as `(x, y, text)` in points.
///
/// The content streams are uncompressed by design, so this is a scan rather
/// than a PDF parser.
fn placements(bytes: &[u8]) -> Vec<(f64, f64, String)> {
    let text = String::from_utf8_lossy(bytes);
    let mut found = Vec::new();
    for capture in text.split("1 0 0 1 ").skip(1) {
        let Some((position, rest)) = capture.split_once(" Tm <") else {
            continue;
        };
        let Some((glyphs, _)) = rest.split_once("> Tj") else {
            continue;
        };
        let mut numbers = position.split_whitespace();
        let (Some(x), Some(y)) = (numbers.next(), numbers.next()) else {
            continue;
        };
        let (Ok(x), Ok(y)) = (x.parse::<f64>(), y.parse::<f64>()) else {
            continue;
        };
        found.push((x, y, glyphs.to_owned()));
    }
    found
}

fn export(script: &str, config: &PageConfig) -> Vec<u8> {
    render(
        &paginate(&Document::parse(script), config),
        config,
        &DocumentInfo::default(),
    )
}

/// The page a placement is on, given that this fixture has exactly one.
fn page_one(bytes: &[u8]) -> Vec<(f64, f64, String)> {
    placements(bytes)
}

#[test]
fn every_element_starts_where_section_5_2_says_it_does() {
    // The x positions the overlay measured, in points from the paper's left
    // edge. An inch is 72 points and a column is 7.2.
    //
    // | Element        | Slugline | Final Draft | afterwriting | screenplain |
    // | scene heading  | 108.0    | 1.5"        | 108.0        | 108.0       |
    // | action         | 108.0    | 1.5"        | 108.0        | 108.0       |
    // | dialogue       | 180.0    | 2.5"        | 180.0        | 172.8       |
    // | parenthetical  | 223.2    | 3.1"        | 216.0        | 201.6       |
    // | character      | 266.4    | 3.7"        | 252.0        | 244.8       |
    //
    // The two open-source references disagree with each other as well as with
    // us, by exactly the tenth of an inch §5.2 warned about; we follow Final
    // Draft, whose defaults §5.2's table already is. ADR 0034 is the record.
    let bytes = export(SCRIPT, &PageConfig::us_letter());
    let placed = page_one(&bytes);
    let mut left: Vec<f64> = placed.iter().map(|(x, _, _)| *x).collect();
    left.sort_by(f64::total_cmp);
    left.dedup_by(|a, b| a == b);

    for wanted in [108.0, 180.0, 223.2, 266.4] {
        assert!(
            left.iter().any(|x| (x - wanted).abs() < 0.001),
            "nothing starts at {wanted} pt; the left edges are {left:?}"
        );
    }
    // 1.5 inches, and nothing further left than the text area except the page
    // number, which is right-aligned to it.
    assert!(
        left.iter().all(|x| *x >= 108.0 - 0.001),
        "something is left of the 1.5-inch margin: {left:?}"
    );
}

#[test]
fn a_transition_ends_at_the_text_area_and_a_centred_line_is_centred_in_it() {
    // Both open-source references right-align to 7.6 inches, which is their own
    // 61-column text width rather than the 1.0-inch right margin they declare.
    // §5.2 says 7.5, and 7.5 is where 1.5 + 6.0 lands.
    let config = PageConfig::us_letter();
    let bytes = export(SCRIPT, &config);
    let placed = page_one(&bytes);
    let script = paginate(&Document::parse(SCRIPT), &config);

    // Found by its text in the pagination, then looked for in the PDF at the
    // point that column is. Correlating the two is the whole assertion: a
    // transition the paginator right-aligned has to *print* right-aligned.
    let ends_at = |content: &str| {
        let line = script.pages[0]
            .lines
            .iter()
            .find(|line| line.content == content)
            .unwrap_or_else(|| panic!("{content:?} is on the page"));
        let columns = line.content.chars().count() as f64;
        let x = 108.0 + f64::from(line.column) * 7.2;
        assert!(
            placed.iter().any(|(at, _, _)| (at - x).abs() < 0.001),
            "{content:?} is at column {} but nothing is drawn at {x} pt",
            line.column
        );
        (x, x + columns * 7.2)
    };

    let (_, right) = ends_at("CUT TO:");
    assert!(
        (right - 540.0).abs() < 0.001,
        "a transition ends at 7.5 inches, not {right}"
    );

    let (left, right) = ends_at("CENTERED");
    assert!(
        ((left + right) / 2.0 - 324.0).abs() < 0.001,
        "centred text is centred on the text area's middle at 4.5 inches, not {}",
        (left + right) / 2.0
    );
}

/// Printed row extents in columns, measured from the finished PDF operators.
/// Each CID is four hex digits and advances one 7.2-point grid cell, regardless
/// of face. Page numbers sit above the text area's 720-point top edge.
fn printed_row_extents(bytes: &[u8]) -> Vec<(f64, f64)> {
    let mut placed = placements(bytes);
    placed.retain(|(_, y, _)| *y <= 720.0);
    placed.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.total_cmp(&b.0)));
    let mut rows: Vec<(f64, f64, f64)> = Vec::new();
    for (x, y, glyphs) in placed {
        let left = (x - 108.0) / 7.2;
        let right = left + (glyphs.len() / 4) as f64;
        if let Some(row) = rows.last_mut().filter(|row| row.0 == y) {
            row.1 = row.1.min(left);
            row.2 = row.2.max(right);
        } else {
            rows.push((y, left, right));
        }
    }
    rows.into_iter()
        .map(|(_, left, right)| (left, right))
        .collect()
}

#[test]
fn emphasised_centred_lines_and_titles_print_at_the_text_area_centre() {
    for script in [
        "> THE **END** <\n",
        "Title: _**BRICK & STEEL**_\n\n",
        "> ***THE _END_*** <\n",
        "> ESCAPED \\*STAR\\* <\n",
        "> UNPAIRED *STAR <\n",
        "Title: ESCAPED \\_TITLE\\_\n\n",
        "Title: UNPAIRED **TITLE\n\n",
    ] {
        let rows = printed_row_extents(&export(script, &PageConfig::us_letter()));
        assert_eq!(rows.len(), 1, "{script:?}");
        let (left, right) = rows[0];
        let centre = (left + right) / 2.0;
        assert!(
            (centre - 30.0).abs() <= 0.5 + 1e-9,
            "{script:?} prints centred at column {centre}, not within half a column of 30"
        );
    }
}

#[test]
fn emphasised_transitions_and_draft_dates_print_to_column_sixty() {
    for script in [
        "> **FADE OUT:**\n",
        "> _**CUT TO:**_\n",
        "> CUT TO \\*BLACK\\*:\n",
        "> UNPAIRED **CUT TO:\n",
        "Draft date: **OCTOBER** 2026\n\n",
        "Draft date: \\_OCTOBER\\_ 2026\n\n",
    ] {
        let rows = printed_row_extents(&export(script, &PageConfig::us_letter()));
        assert_eq!(rows.len(), 1, "{script:?}");
        let (_, right) = rows[0];
        assert!(
            (right - 60.0).abs() < 1e-9,
            "{script:?} prints to column {right}, not 60"
        );
    }
}

#[test]
fn alignment_pairs_emphasis_across_wrapped_body_rows() {
    let text = format!("**{}END**", "WORD ".repeat(14));
    for centred in [true, false] {
        let script = if centred {
            format!("> {text} <\n")
        } else {
            format!("> {text}\n")
        };
        let rows = printed_row_extents(&export(&script, &PageConfig::us_letter()));
        assert_eq!(rows.len(), 2, "the fixture wraps by raw width");
        for (left, right) in rows {
            if centred {
                assert!(((left + right) / 2.0 - 30.0).abs() <= 0.5 + 1e-9);
            } else {
                assert!((right - 60.0).abs() < 1e-9, "wrapped row ends at {right}");
            }
        }
    }
}

#[test]
fn baselines_are_six_to_the_inch_from_a_one_inch_margin() {
    // The half of the exit criterion the references all agree on, and the half
    // that matters most: a page of ours laid over a page of theirs has its
    // lines on the same rules.
    let bytes = export(SCRIPT, &PageConfig::us_letter());
    let mut baselines: Vec<f64> = page_one(&bytes).iter().map(|(_, y, _)| *y).collect();
    baselines.sort_by(f64::total_cmp);
    baselines.dedup_by(|a, b| a == b);
    assert!(baselines.len() > 5, "there are several rows on the page");

    // The first row's baseline sits an ascender below the one-inch margin, and
    // every other row is a whole number of twelve-point rows from it.
    let top = *baselines.last().expect("at least one row");
    for baseline in &baselines {
        let rows = (top - baseline) / 12.0;
        assert!(
            (rows - rows.round()).abs() < 1e-9,
            "{baseline} is {rows} rows from the top row, not a whole number"
        );
    }
    // Page 1 carries no number unless the setup asks, so the topmost line is
    // the first row of script, an ascender below the one-inch margin.
    let ascender = 1600.0 / 2048.0 * 12.0;
    assert!(
        (top - (792.0 - 72.0 - ascender)).abs() < 0.001,
        "the topmost line is the first row of script, one inch from the paper's top"
    );
    // Asked for, the page number is three rows above the text area — half an
    // inch (§5.2) — and nothing else on the page has moved.
    let numbered = export(
        SCRIPT,
        &PageConfig::us_letter().with_number_first_page(true),
    );
    let mut numbered_baselines: Vec<f64> = page_one(&numbered).iter().map(|(_, y, _)| *y).collect();
    numbered_baselines.sort_by(f64::total_cmp);
    numbered_baselines.dedup_by(|a, b| a == b);
    let number = numbered_baselines.pop().expect("at least one row");
    assert!(
        (number - (792.0 - 72.0 + 36.0 - ascender)).abs() < 0.001,
        "the topmost line is the page number, half an inch from the paper's top"
    );
    assert_eq!(numbered_baselines, baselines);
}

#[test]
fn a4_keeps_the_same_character_grid() {
    // §5.2: "A4 uses the same character grid with a reduced line count per
    // page". The indents are the grid, so they do not move.
    let letter = export(SCRIPT, &PageConfig::us_letter());
    let a4 = export(SCRIPT, &PageConfig::a4());
    let lefts = |bytes: &[u8]| {
        let mut left: Vec<f64> = page_one(bytes).iter().map(|(x, _, _)| *x).collect();
        left.sort_by(f64::total_cmp);
        left.dedup_by(|a, b| a == b);
        left
    };
    assert_eq!(lefts(&letter), lefts(&a4));
}
