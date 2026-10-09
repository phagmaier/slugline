use slugline_document::{BlockId, BlockKind, BlockSnapshot};
use slugline_layout::{
    break_lines, LayoutEngine, LayoutLine, LayoutLineKind, PageConfig, PaginatedScript,
    ScriptSnapshot,
};

fn script(blocks: &[(BlockKind, &str, bool)]) -> ScriptSnapshot {
    ScriptSnapshot {
        revision: 0,
        title_page: Default::default(),
        blocks: blocks
            .iter()
            .enumerate()
            .map(|(index, &(kind, text, dual))| BlockSnapshot {
                id: BlockId(index as u64 + 1),
                kind,
                text: text.to_owned(),
                forced: false,
                dual,
            })
            .collect(),
    }
}

fn output(script: &ScriptSnapshot, capacity: u16) -> PaginatedScript {
    LayoutEngine::new().paginate_snapshot(
        script,
        &PageConfig::us_letter().with_line_capacity(capacity),
    )
}

fn rows(output: &PaginatedScript, index: usize) -> Vec<&LayoutLine> {
    output
        .pages
        .iter()
        .flat_map(|page| page.lines.iter())
        .filter(|line| {
            line.block == Some(BlockId(index as u64 + 1)) && line.kind == LayoutLineKind::Content
        })
        .collect()
}

fn assert_source_rows(output: &PaginatedScript, script: &ScriptSnapshot, index: usize, width: u16) {
    let expected = break_lines(&script.blocks[index].text, width);
    let actual = rows(output, index);
    assert_eq!(
        actual
            .iter()
            .map(|line| line.content.as_str())
            .collect::<Vec<_>>(),
        expected.iter().map(String::as_str).collect::<Vec<_>>()
    );
    assert_eq!(
        actual
            .iter()
            .map(|line| line.source_line)
            .collect::<Vec<_>>(),
        (0..expected.len())
            .map(|index| Some(index as u16))
            .collect::<Vec<_>>()
    );
}

fn assert_bounded(output: &PaginatedScript, capacity: u16) {
    for line in output
        .pages
        .iter()
        .flat_map(|page| page.lines.iter())
        .filter(|line| line.block.is_some())
    {
        assert!((0..capacity as i16).contains(&line.row), "{line:?}");
        let printed_width = line.resolved_runs.as_ref().map_or_else(
            || line.content.chars().count(),
            |runs| runs.iter().map(|run| run.text.chars().count()).sum(),
        );
        let right_edge = line.column + printed_width as i16;
        assert!(line.column >= 0 && right_edge <= 60, "{line:?}");
        assert!(
            right_edge <= 28 || line.column >= 32,
            "gutter overflow: {line:?}"
        );
    }
}

#[test]
fn paired_columns_align_cues_and_preserve_source_lyric_and_emphasis_metadata() {
    use BlockKind::*;
    let sung = format!("~**{}**\nSpoken.", "a".repeat(58));
    let snapshot = script(&[
        (Character, "MARTHA", false),
        (Parenthetical, "(singing)", false),
        (Dialogue, &sung, false),
        (Character, "DEREK", true),
        (Parenthetical, "(quietly)", false),
        (Dialogue, "**A reply.**", false),
    ]);
    let result = output(&snapshot, 54);
    for (index, column, row) in [
        (0, 8, 0),
        (1, 4, 1),
        (2, 0, 2),
        (3, 40, 0),
        (4, 36, 1),
        (5, 32, 2),
    ] {
        let lines = rows(&result, index);
        assert_eq!((lines[0].column, lines[0].row), (column, row));
        assert!(lines.iter().all(|line| line.column == column));
    }
    let sung_rows = rows(&result, 2);
    assert!(sung_rows[..3].iter().all(|line| line.is_lyric));
    assert_eq!(sung_rows[0].lyric_marker_utf8, Some(0));
    assert!(sung_rows[1..]
        .iter()
        .all(|line| line.lyric_marker_utf8.is_none()));
    assert!(!sung_rows.last().unwrap().is_lyric);
    assert_bounded(&result, 54);
}

#[test]
fn pairing_is_greedy_disjoint_and_allows_a_marked_first_cue() {
    use BlockKind::*;
    for first_mark in [false, true] {
        let snapshot = script(&[
            (Character, "A", first_mark),
            (Dialogue, "First.", false),
            (Character, "B", true),
            (Dialogue, "Second.", false),
            (Character, "C", true),
            (Dialogue, "Third.", false),
        ]);
        let result = output(&snapshot, 54);
        assert_eq!(
            (
                rows(&result, 0)[0].column,
                rows(&result, 2)[0].column,
                rows(&result, 4)[0].column
            ),
            (8, 40, 22)
        );
        assert_eq!(rows(&result, 0)[0].row, rows(&result, 2)[0].row);
        assert!(rows(&result, 4)[0].row > rows(&result, 2)[0].row);
        assert!(snapshot.blocks[4].dual);
        assert!(rows(&result, 4)
            .iter()
            .all(|line| !line.content.contains('^')));
    }
    let snapshot = script(&[
        (Character, "A", false),
        (Dialogue, "First.", false),
        (Character, "B", true),
        (Dialogue, "Second.", false),
        (Character, "C", true),
        (Dialogue, "Third.", false),
        (Character, "D", true),
        (Dialogue, "Fourth.", false),
    ]);
    let result = output(&snapshot, 54);
    assert_eq!(rows(&result, 4)[0].column, 8);
    assert_eq!(rows(&result, 6)[0].column, 40);
    assert_eq!(rows(&result, 4)[0].row, rows(&result, 6)[0].row);
}

#[test]
fn every_source_interruption_and_empty_speech_leaves_marked_cues_ordinary() {
    use BlockKind::*;
    for kind in [
        Action,
        PageBreak,
        Note,
        Section { level: 1 },
        Synopsis,
        Lyric,
        SceneHeading,
        Centered,
        Transition,
        Opaque,
    ] {
        let snapshot = script(&[
            (Character, "A", false),
            (Dialogue, "First.", false),
            (kind, "Interruption.", false),
            (Character, "B", true),
            (Dialogue, "Second.", false),
        ]);
        let result = output(&snapshot, 54);
        assert_eq!(rows(&result, 0)[0].column, 22, "{kind:?}");
        assert_eq!(rows(&result, 3)[0].column, 22, "{kind:?}");
    }
    for blocks in [
        vec![
            (Character, "A", false),
            (Character, "B", true),
            (Dialogue, "Reply.", false),
        ],
        vec![
            (Character, "A", false),
            (Dialogue, "First.", false),
            (Character, "B", true),
        ],
        vec![
            (Character, "A", false),
            (Note, "Hidden.", false),
            (Dialogue, "Detached.", false),
            (Character, "B", true),
            (Dialogue, "Reply.", false),
        ],
        vec![
            (Character, "A", false),
            (Dialogue, "First.", false),
            (Note, "Hidden.", false),
            (Dialogue, "Detached.", false),
            (Character, "B", true),
            (Dialogue, "Reply.", false),
        ],
    ] {
        let snapshot = script(&blocks);
        let result = output(&snapshot, 54);
        for (index, _) in snapshot
            .blocks
            .iter()
            .enumerate()
            .filter(|(_, block)| block.kind == Character)
        {
            assert_eq!(rows(&result, index)[0].column, 22);
        }
    }
}

#[test]
fn a_pair_that_fits_a_fresh_page_moves_together_and_aligns_at_the_top() {
    use BlockKind::*;
    let snapshot = script(&[
        (Action, "Before one.\nBefore two.\nBefore three.", false),
        (Character, "A", false),
        (Dialogue, "One.\nTwo.", false),
        (Character, "B", true),
        (Dialogue, "Three.\nFour.", false),
    ]);
    let result = output(&snapshot, 6);
    assert_eq!(result.pages.len(), 2);
    assert!(result.pages[0]
        .lines
        .iter()
        .all(|line| line.block != Some(BlockId(2)) && line.block != Some(BlockId(4))));
    assert_eq!(rows(&result, 1)[0].row, 0);
    assert_eq!(rows(&result, 3)[0].row, 0);
}

#[test]
fn asymmetric_continuations_do_not_repeat_a_completed_lane() {
    use BlockKind::*;
    let long = (0..12)
        .map(|index| format!("Left {index}."))
        .collect::<Vec<_>>()
        .join("\n");
    let snapshot = script(&[
        (Character, "A", false),
        (Dialogue, &long, false),
        (Character, "B", true),
        (Dialogue, "Right one.\nRight two.", false),
    ]);
    let result = output(&snapshot, 6);
    assert_eq!(result.pages.len(), 3);
    assert_source_rows(&result, &snapshot, 1, 28);
    assert_source_rows(&result, &snapshot, 3, 28);
    for page in &result.pages[1..] {
        assert!(!page
            .lines
            .iter()
            .any(|line| line.block == Some(BlockId(3)) || line.block == Some(BlockId(4))));
        assert!(page
            .lines
            .iter()
            .any(|line| line.kind == LayoutLineKind::Continued
                && line.column == 8
                && line.row == 0));
    }
    assert_eq!(
        result
            .pages
            .iter()
            .flat_map(|page| page.lines.iter())
            .filter(|line| line.kind == LayoutLineKind::More)
            .count(),
        2
    );
    assert_bounded(&result, 6);
}

#[test]
fn an_overheight_pair_uses_remaining_space_only_when_both_lanes_can_start() {
    use BlockKind::*;
    let long = "One.\nTwo.\nThree.\nFour.\nFive.\nSix.\nSeven.\nEight.\nNine.";
    for (before, expected_page, expected_row) in [
        ("Before.\nAgain.", 0, 3),
        ("Before.\nAgain.\nMore.\nLast.", 1, 0),
    ] {
        let snapshot = script(&[
            (Action, before, false),
            (Character, "A", false),
            (Dialogue, long, false),
            (Character, "B", true),
            (Dialogue, "One.\nTwo.\nThree.\nFour.\nFive.\nSix.", false),
        ]);
        let result = output(&snapshot, 8);
        for id in [BlockId(2), BlockId(4)] {
            let (page, line) = result
                .pages
                .iter()
                .enumerate()
                .find_map(|(index, page)| {
                    page.lines
                        .iter()
                        .find(|line| line.block == Some(id) && line.kind == LayoutLineKind::Content)
                        .map(|line| (index, line))
                })
                .unwrap();
            assert_eq!((page, line.row), (expected_page, expected_row));
        }
        assert_source_rows(&result, &snapshot, 2, 28);
        assert_source_rows(&result, &snapshot, 4, 28);
    }
}

#[test]
fn legal_lane_splits_protect_parentheticals_and_leave_two_dialogue_rows() {
    use BlockKind::*;
    let snapshot = script(&[
        (Character, "A", false),
        (Dialogue, "One.\nTwo.\nThree.", false),
        (Parenthetical, "(first direction\nsecond direction)", false),
        (Dialogue, "Four.\nFive.\nSix.\nSeven.\nEight.\nNine.", false),
        (Character, "B", true),
        (Dialogue, "Right.", false),
    ]);
    let result = output(&snapshot, 7);
    assert_source_rows(&result, &snapshot, 2, 20);
    for page in result.pages.iter() {
        let left: Vec<_> = page
            .lines
            .iter()
            .filter(|line| {
                matches!(line.block, Some(BlockId(2) | BlockId(3) | BlockId(4)))
                    && line.kind == LayoutLineKind::Content
            })
            .collect();
        if !left.is_empty() {
            assert_ne!(left.last().unwrap().block, Some(BlockId(3)));
            assert!(
                left.iter()
                    .filter(|line| line.block != Some(BlockId(3)))
                    .count()
                    >= 2
            );
        }
    }
    let parenthetical_pages: Vec<_> = result
        .pages
        .iter()
        .enumerate()
        .filter(|(_, page)| page.lines.iter().any(|line| line.block == Some(BlockId(3))))
        .map(|(index, _)| index)
        .collect();
    assert_eq!(parenthetical_pages.len(), 1);
    assert_bounded(&result, 7);
}

#[test]
fn tiny_pages_preserve_overheight_prefixes_and_unsplittable_parentheticals() {
    use BlockKind::*;
    let cue = "ABCDEFGHIJKLMNOPQRST".repeat(7);
    let parenthetical = format!("({})", "direction ".repeat(22));
    let snapshot = script(&[
        (Character, &cue, false),
        (Parenthetical, &parenthetical, false),
        (Dialogue, "Last left.", false),
        (Character, "B", true),
        (
            Dialogue,
            "One.\nTwo.\nThree.\nFour.\nFive.\nSix.\nSeven.",
            false,
        ),
    ]);
    for capacity in [4, 5, 8] {
        let result = output(&snapshot, capacity);
        for (index, width) in [(0, 20), (1, 20), (2, 28), (3, 20), (4, 28)] {
            assert_source_rows(&result, &snapshot, index, width);
        }
        assert_bounded(&result, capacity);
        assert!(!result.stats.fell_back_to_naive);
    }
}

#[test]
fn long_continued_cues_wrap_inside_their_lane() {
    use BlockKind::*;
    let long =
        "One.\nTwo.\nThree.\nFour.\nFive.\nSix.\nSeven.\nEight.\nNine.\nTen.\nEleven.\nTwelve.";
    let snapshot = script(&[
        (Character, "ABCDEFGHIJKLMNOPQRST", false),
        (Dialogue, long, false),
        (Character, "UVWXYZABCDEFGHIJKLMN", true),
        (Dialogue, long, false),
    ]);
    let result = output(&snapshot, 7);
    assert!(result.pages.len() >= 2);
    let continued: Vec<_> = result.pages[1]
        .lines
        .iter()
        .filter(|line| line.kind == LayoutLineKind::Continued)
        .collect();
    assert_eq!(continued.len(), 4);
    for column in [8, 40] {
        assert_eq!(
            continued
                .iter()
                .filter(|line| line.column == column)
                .map(|line| line.row)
                .collect::<Vec<_>>(),
            [0, 1]
        );
    }
    assert_source_rows(&result, &snapshot, 1, 28);
    assert_source_rows(&result, &snapshot, 3, 28);
    assert_bounded(&result, 7);
}

#[test]
fn continued_cues_keep_the_full_name_when_the_original_cue_wrapped() {
    use BlockKind::*;
    let body = (0..15)
        .map(|n| format!("Line {n}."))
        .collect::<Vec<_>>()
        .join("\n");
    let snapshot = script(&[
        (Character, "ABCDEFGHIJKLMNOPQRST UVWXY", false),
        (Dialogue, &body, false),
        (Character, "ZYXWVUTSRQPONMLKJIHGFEDCBA", true),
        (Dialogue, &body, false),
    ]);
    let result = output(&snapshot, 8);
    for (index, column) in [(0, 8), (2, 40)] {
        let continued: Vec<_> = result.pages[1]
            .lines
            .iter()
            .filter(|line| line.kind == LayoutLineKind::Continued && line.column == column)
            .map(|line| line.content.as_str())
            .collect();
        let expected = break_lines(&format!("{} (CONT'D)", snapshot.blocks[index].text), 20);
        assert_eq!(continued, expected);
    }
    assert_bounded(&result, 8);
}

#[test]
fn contextual_membership_invalidates_both_wraps_but_reuses_unrelated_blocks() {
    use BlockKind::*;
    let text = "x".repeat(62);
    let mut snapshot = script(&[
        (Action, "Unrelated.", false),
        (Character, "A", false),
        (Dialogue, &text, false),
        (Character, "B", true),
        (Dialogue, &text, false),
    ]);
    let config = PageConfig::us_letter();
    let mut engine = LayoutEngine::new();
    let paired = engine.paginate_snapshot(&snapshot, &config);
    assert_eq!(rows(&paired, 2).len(), 3);
    assert_eq!(rows(&paired, 4).len(), 3);
    for paired in [false, true] {
        snapshot.blocks[3].dual = paired;
        snapshot.revision += 1;
        let actual = engine.repaginate(&snapshot, &config, snapshot.blocks[3].id);
        let expected = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
        assert_eq!(actual.pages, expected.pages);
        assert_eq!(actual.checkpoints, expected.checkpoints);
        assert_eq!((actual.stats.block_misses, actual.stats.block_hits), (4, 1));
        assert_source_rows(&actual, &snapshot, 2, if paired { 28 } else { 35 });
        assert_source_rows(&actual, &snapshot, 4, if paired { 28 } else { 35 });
    }
    snapshot.blocks[2].text.push('y');
    snapshot.revision += 1;
    let actual = engine.repaginate(&snapshot, &config, snapshot.blocks[2].id);
    assert_eq!((actual.stats.block_misses, actual.stats.block_hits), (1, 4));
}
