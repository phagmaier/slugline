use slugline_document::Document;
use slugline_layout::{
    metrics, paginate, LayoutEngine, LayoutLine, LayoutLineKind, Page, PageConfig, ScriptSnapshot,
};

/// One-row action blocks, a blank between each: 27 to a US Letter page.
fn action_script(blocks: usize) -> Document {
    let source = (1..=blocks)
        .map(|line| format!("Action line {line}."))
        .collect::<Vec<_>>()
        .join("\n\n");
    Document::parse(&(source + "\n"))
}

fn three_pages() -> Document {
    action_script(70)
}

fn page_number_lines(page: &Page) -> Vec<&LayoutLine> {
    page.lines
        .iter()
        .filter(|line| line.kind == LayoutLineKind::PageNumber)
        .collect()
}

fn printed_number(page: &Page) -> Option<&str> {
    match page_number_lines(page)[..] {
        [] => None,
        [line] => Some(line.content.as_str()),
        ref lines => panic!("a page carries at most one number, found {lines:?}"),
    }
}

#[test]
fn page_one_is_counted_but_unnumbered_unless_the_setup_asks() {
    let document = three_pages();
    for preset in [PageConfig::us_letter(), PageConfig::a4()] {
        assert!(!preset.number_first_page, "presets leave page 1 unnumbered");
        let plain = paginate(&document, &preset);
        let numbered = paginate(&document, &preset.clone().with_number_first_page(true));
        assert!(plain.pages.len() >= 3, "the fixture must cross two breaks");

        assert_eq!(printed_number(&plain.pages[0]), None);
        assert_eq!(printed_number(&numbered.pages[0]), Some("1."));
        let first = page_number_lines(&numbered.pages[0])[0];
        assert_eq!(first.row, metrics::PAGE_NUMBER_ROW);
        assert_eq!(first.column, metrics::PAGE_NUMBER_RIGHT_COLUMN - 2);

        // The option decides one line. The count, every later number and every
        // row of script are the same pagination either way.
        for output in [&plain, &numbered] {
            assert_eq!(output.pages[0].number, Some(1));
            assert_eq!(printed_number(&output.pages[1]), Some("2."));
            assert_eq!(printed_number(&output.pages[2]), Some("3."));
        }
        assert_eq!(plain.pages.len(), numbered.pages.len());
        assert_eq!(plain.pages[1..], numbered.pages[1..]);
        assert_eq!(plain.checkpoints, numbered.checkpoints);
        let without_number: Vec<_> = numbered.pages[0]
            .lines
            .iter()
            .filter(|line| line.kind != LayoutLineKind::PageNumber)
            .cloned()
            .collect();
        assert_eq!(plain.pages[0].lines.to_vec(), without_number);
    }
}

#[test]
fn a_one_page_script_prints_no_page_number_at_all() {
    let document = Document::parse("INT. ROOM - DAY\n\nA short scene.\n");
    let output = paginate(&document, &PageConfig::us_letter());
    assert_eq!(output.pages.len(), 1);
    assert!(output
        .debug_dump()
        .starts_with("PAGE 1\n    0 -> (  0, \"INT. ROOM - DAY\")"));
}

#[test]
fn an_explicit_break_does_not_restart_the_exemption() {
    let document = Document::parse("First.\n\n===\n\nSecond.\n\n===\n\nThird.\n");
    let output = paginate(&document, &PageConfig::us_letter());
    let printed: Vec<_> = output.pages.iter().map(printed_number).collect();
    assert_eq!(printed, [None, Some("2."), Some("3.")]);
}

#[test]
fn an_incremental_edit_on_page_one_agrees_with_a_full_pagination() {
    // Long enough to hold a second checkpoint, so the run that restarts at
    // page 1 can be told from a full one by the tail it reuses.
    let document = action_script(27 * (metrics::CHECKPOINT_INTERVAL_PAGES + 2));
    for config in [
        PageConfig::us_letter(),
        PageConfig::us_letter().with_number_first_page(true),
    ] {
        let mut snapshot = ScriptSnapshot::from(&document);
        let mut engine = LayoutEngine::new();
        engine.paginate_snapshot(&snapshot, &config);

        let changed = snapshot.blocks[1].id;
        snapshot.blocks[1].text.push_str(" Changed.");
        snapshot.revision += 1;
        let incremental = engine.repaginate(&snapshot, &config, changed);
        let full = LayoutEngine::new().paginate_snapshot(&snapshot, &config);

        assert_eq!(
            incremental.stats.reused_pages, 0,
            "page 1 was laid out again"
        );
        assert!(
            incremental.stats.reused_tail_pages > 0,
            "by the incremental path, not a full pagination"
        );
        assert_eq!(incremental.pages, full.pages);
        assert_eq!(
            printed_number(&incremental.pages[0]),
            config.number_first_page.then_some("1.")
        );
    }
}

#[test]
fn changing_the_option_never_reuses_the_other_setting_s_pages() {
    let document = three_pages();
    let mut snapshot = ScriptSnapshot::from(&document);
    let mut engine = LayoutEngine::new();
    engine.paginate_snapshot(&snapshot, &PageConfig::us_letter());

    // The last block, so that page 1 would be a reused prefix if a prior
    // output for the other setting were ever trusted.
    let last = snapshot.blocks.len() - 1;
    let changed = snapshot.blocks[last].id;
    snapshot.blocks[last].text.push_str(" Changed.");
    snapshot.revision += 1;
    let numbered = PageConfig::us_letter().with_number_first_page(true);
    let output = engine.repaginate(&snapshot, &numbered, changed);

    assert_eq!(output.stats.reused_pages, 0);
    assert_eq!(printed_number(&output.pages[0]), Some("1."));
}
