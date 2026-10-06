use slugline_document::{BlockKind, Document};
use slugline_layout::{break_lines, paginate, LayoutLineKind, PageConfig, SceneNumberGutters};

fn tiny(lines: u16) -> PageConfig {
    PageConfig::us_letter().with_line_capacity(lines)
}

#[test]
fn rule_1_explicit_page_break_always_starts_a_page() {
    let document = Document::parse("First paragraph.\n\n===\n\nSecond paragraph.\n");
    let output = paginate(&document, &tiny(8));
    assert_eq!(output.pages.len(), 2);
    assert!(output.pages[0]
        .lines
        .iter()
        .any(|line| line.content == "First paragraph."));
    assert!(output.pages[1]
        .lines
        .iter()
        .any(|line| line.content == "Second paragraph."));
}

#[test]
fn rule_2_scene_heading_carries_two_scene_lines() {
    let document = Document::parse(
        "Opening one.\nOpening two.\nOpening three.\n\nINT. ROOM - DAY\n\nScene one.\nScene two.\n",
    );
    let output = paginate(&document, &tiny(8));
    let scene = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::SceneHeading)
        .expect("scene heading")
        .id();
    let page = output
        .pages
        .iter()
        .find(|page| page.lines.iter().any(|line| line.block == Some(scene)))
        .expect("scene page");
    let scene_row = page
        .lines
        .iter()
        .find(|line| line.block == Some(scene) && line.source_line == Some(0))
        .expect("scene line")
        .row;
    let following_content = page
        .lines
        .iter()
        .filter(|line| line.row > scene_row && line.kind == LayoutLineKind::Content)
        .count();
    assert!(following_content >= 2);
}

#[test]
fn rule_3_character_cue_never_ends_a_page_alone() {
    let document = Document::parse(
        "Before one.\nBefore two.\nBefore three.\nBefore four.\n\nMARTHA\nA reply.\n",
    );
    let output = paginate(&document, &tiny(6));
    let cue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Character)
        .expect("cue")
        .id();
    let dialogue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue")
        .id();
    let page = output
        .pages
        .iter()
        .find(|page| page.lines.iter().any(|line| line.block == Some(cue)))
        .expect("cue page");
    assert!(page.lines.iter().any(|line| line.block == Some(dialogue)));
}

#[test]
fn rule_4_dialogue_split_leaves_two_lines_on_each_page() {
    let document = Document::parse(
        "MARTHA\nOne line of dialogue that deliberately wraps across many rows because it keeps going with enough words for a legal split on both sides of the page boundary and then carries onward.\n",
    );
    let dialogue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue")
        .id();
    let output = paginate(&document, &tiny(6));
    assert!(output.pages.len() >= 2);
    for page in output.pages.iter() {
        let count = page
            .lines
            .iter()
            .filter(|line| line.block == Some(dialogue) && line.source_line.is_some())
            .count();
        assert!(
            count >= 2,
            "split page carried only {count} dialogue line(s)"
        );
    }
}

#[test]
fn rule_4_short_dialogue_is_pushed_instead_of_illegally_split() {
    let document = Document::parse(
        "Before one.\nBefore two.\nBefore three.\n\nMARTHA\nFirst reply line.\nSecond reply line.\n",
    );
    let cue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Character)
        .expect("cue")
        .id();
    let dialogue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue")
        .id();
    let output = paginate(&document, &tiny(6));
    let speech_page = output
        .pages
        .iter()
        .find(|page| page.lines.iter().any(|line| line.block == Some(cue)))
        .expect("speech page");

    assert_eq!(
        speech_page
            .lines
            .iter()
            .filter(|line| line.block == Some(dialogue) && line.source_line.is_some())
            .count(),
        2
    );
    assert!(!output.pages.iter().any(|page| {
        page.lines
            .iter()
            .any(|line| matches!(line.kind, LayoutLineKind::More | LayoutLineKind::Continued))
    }));
}

#[test]
fn rule_5_split_dialogue_inserts_more_and_continued() {
    let document = Document::parse(
        "MARTHA\nOne line of dialogue that deliberately wraps across many rows because it keeps going with enough words for a legal split on both sides of the page boundary and then carries onward.\n",
    );
    let output = paginate(&document, &tiny(6));
    assert!(output.pages[0]
        .lines
        .iter()
        .any(|line| line.kind == LayoutLineKind::More && line.content == "(MORE)"));
    assert!(output.pages[1].lines.iter().any(|line| {
        line.kind == LayoutLineKind::Continued && line.content == "MARTHA (CONT'D)"
    }));
}

#[test]
fn rule_6_parenthetical_carries_a_dialogue_line() {
    let document = Document::parse(
        "Before one.\nBefore two.\nBefore three.\n\nMARTHA\n(quietly, but with a parenthetical long enough to wrap)\nThis follows it.\n",
    );
    let parenthetical = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Parenthetical)
        .expect("parenthetical")
        .id();
    let dialogue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue")
        .id();
    let output = paginate(&document, &tiny(7));
    let page = output
        .pages
        .iter()
        .find(|page| {
            page.lines
                .iter()
                .any(|line| line.block == Some(parenthetical))
        })
        .expect("parenthetical page");
    assert!(page.lines.iter().any(|line| line.block == Some(dialogue)));
    let pages_with_parenthetical = output
        .pages
        .iter()
        .filter(|page| {
            page.lines
                .iter()
                .any(|line| line.block == Some(parenthetical))
        })
        .count();
    assert_eq!(pages_with_parenthetical, 1);
}

#[test]
fn rule_7_action_never_leaves_a_one_line_orphan() {
    let document = Document::parse(
        "Line one.\nLine two.\nLine three.\nLine four.\nLine five.\nLine six.\nLine seven.\n",
    );
    let action = document.blocks()[0].id();
    let output = paginate(&document, &tiny(6));
    let counts: Vec<_> = output
        .pages
        .iter()
        .map(|page| {
            page.lines
                .iter()
                .filter(|line| line.block == Some(action) && line.source_line.is_some())
                .count()
        })
        .filter(|count| *count > 0)
        .collect();
    assert_eq!(counts, [5, 2]);
}

#[test]
fn scene_numbers_can_be_emitted_in_both_gutters() {
    let document = Document::parse("INT. ROOM - DAY #7#\n\nAction one.\nAction two.\n");
    let output = paginate(
        &document,
        &PageConfig::us_letter().with_scene_numbers(SceneNumberGutters::Both),
    );
    assert!(output.pages[0]
        .lines
        .iter()
        .any(|line| line.kind == LayoutLineKind::SceneNumberLeft));
    assert!(output.pages[0]
        .lines
        .iter()
        .any(|line| line.kind == LayoutLineKind::SceneNumberRight));
}

#[test]
fn pathological_scene_boundaries_converge_within_the_cap() {
    let source: String = (0..100)
        .map(|index| format!("INT. ROOM {index} - DAY\n\nBeat {index}.\n\n"))
        .collect();
    let output = paginate(&Document::parse(&source), &tiny(6));
    assert!(output.stats.break_rule_iterations <= 8);
    assert!(!output.stats.fell_back_to_naive);
}

#[test]
fn content_fragments_preserve_block_and_wrapped_line_identity() {
    let document = Document::parse(
        "An action paragraph deliberately long enough to wrap onto several visual rows while retaining one source block identity.\n\nMARTHA\nA dialogue paragraph deliberately long enough to wrap across a page boundary while retaining its source identity throughout every fragment.\n",
    );
    let output = paginate(&document, &tiny(6));

    for block in document.blocks() {
        let source_lines: Vec<_> = output
            .pages
            .iter()
            .flat_map(|page| page.lines.iter())
            .filter(|line| line.block == Some(block.id()) && line.kind == LayoutLineKind::Content)
            .map(|line| line.source_line.expect("content has a wrapped-line index"))
            .collect();
        assert!(
            !source_lines.is_empty(),
            "visible block has output fragments"
        );
        assert_eq!(
            source_lines,
            (0..source_lines.len() as u16).collect::<Vec<_>>(),
            "wrapped-line identity remains ordered for block {:?}",
            block.id()
        );
    }
}

#[test]
fn fresh_engines_produce_identical_page_and_fragment_ordering() {
    let document = Document::parse(
        "INT. ROOM - DAY #4#\n\nAction one.\nAction two.\n\nMARTHA\nA reply long enough to cross a deliberately tiny page boundary and exercise generated continuation furniture deterministically.\n",
    );
    let config = tiny(6).with_scene_numbers(SceneNumberGutters::Both);
    let expected = paginate(&document, &config);

    for _ in 0..20 {
        assert_eq!(paginate(&document, &config), expected);
    }
}

#[test]
fn nonprinting_blocks_do_not_reach_output() {
    let document = Document::parse(
        "# Section\n\n= Synopsis\n\n[[ Note ]]\n\n/* boneyard */\n\nVisible [[ private ]] action /* old */ remains.\n",
    );
    let output = paginate(&document, &PageConfig::us_letter());
    let dump = output.debug_dump();
    assert!(!dump.contains("Section"));
    assert!(!dump.contains("Synopsis"));
    assert!(!dump.contains("Note"));
    assert!(!dump.contains("boneyard"));
    assert!(!dump.contains("private"));
    assert!(!dump.contains("old"));
    assert!(dump.contains("Visible  action  remains."));
}

#[test]
fn one_action_block_fills_exactly_one_us_letter_page() {
    let lines: String = (1..=54).map(|i| format!("Line {i}.\n")).collect();
    let document = Document::parse(&lines);
    let output = paginate(&document, &PageConfig::us_letter());
    assert_eq!(output.pages.len(), 1);
    let action = document.blocks()[0].id();
    let content: Vec<_> = output.pages[0]
        .lines
        .iter()
        .filter(|line| line.block == Some(action) && line.kind == LayoutLineKind::Content)
        .collect();
    assert_eq!(content.len(), 54);
}

#[test]
fn one_more_action_line_overflows_to_page_two() {
    let lines: String = (1..=55).map(|i| format!("Line {i}.\n")).collect();
    let document = Document::parse(&lines);
    let output = paginate(&document, &PageConfig::us_letter());
    assert_eq!(
        output.pages.len(),
        2,
        "55 action rows do not fit on one page"
    );
    let action = document.blocks()[0].id();
    for page in output.pages.iter() {
        let count = page
            .lines
            .iter()
            .filter(|line| line.block == Some(action) && line.kind == LayoutLineKind::Content)
            .count();
        assert!(
            count >= 2,
            "action orphan rule left {count} fragment(s) on a page"
        );
    }
}

#[test]
fn dialogue_wraps_at_thirty_five_character_width() {
    let text = "A dialogue line deliberately long enough to wrap multiple times across the thirty-five character dialogue width.";
    let expected = break_lines(text, 35);
    let document = Document::parse(&format!("MARTHA\n{text}\n"));
    let output = paginate(&document, &PageConfig::us_letter());
    let dialogue = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue block")
        .id();
    let wrapped: Vec<_> = output.pages[0]
        .lines
        .iter()
        .filter(|line| line.block == Some(dialogue) && line.kind == LayoutLineKind::Content)
        .collect();
    assert_eq!(wrapped.len(), expected.len());
    assert!(
        wrapped.len() > 1,
        "dialogue text is short enough to not wrap"
    );
}

#[test]
fn scene_heading_identity_is_content_only_and_weight_never_changes_geometry() {
    let heading = format!("INT. {} - DAY #12#", "VERY LONG ROOM NAME ".repeat(5));
    let document = Document::parse(&format!(
        "Title: Cover\n\n{heading}\n\nAction follows.\n\nJOHN\nHello.\n"
    ));
    let scene = document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::SceneHeading)
        .expect("heading")
        .id();
    for preset in [PageConfig::us_letter(), PageConfig::a4()] {
        assert!(!preset.bold_scene_headings, "presets keep headings regular");
        let regular = preset.with_scene_numbers(SceneNumberGutters::Both);
        let bold = regular.clone().with_bold_scene_headings(true);
        let plain = paginate(&document, &regular);
        let weighted = paginate(&document, &bold);
        assert_eq!(plain.title_page, weighted.title_page);
        assert_eq!(plain.pages, weighted.pages);
        assert_eq!(plain.checkpoints, weighted.checkpoints);
        assert_eq!(plain.debug_dump(), weighted.debug_dump());
        let mut heading_rows = 0;
        for line in plain
            .title_page
            .iter()
            .chain(plain.pages.iter())
            .flat_map(|page| page.lines.iter())
        {
            let heading_content = line.kind == LayoutLineKind::Content && line.block == Some(scene);
            assert_eq!(line.is_scene_heading, heading_content);
            if heading_content {
                heading_rows += 1;
            }
        }
        assert!(
            heading_rows > 1,
            "every wrapped heading row retains its kind"
        );
    }
}
