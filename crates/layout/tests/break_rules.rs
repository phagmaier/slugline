use slugline_document::{BlockKind, Document};
use slugline_layout::{paginate, LayoutLineKind, PageConfig, SceneNumberGutters};

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
