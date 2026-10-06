use slugline_document::{BlockId, BlockKind, Document};
use slugline_layout::{
    paginate, LayoutEngine, LayoutLine, LayoutLineKind, PageConfig, PaginatedScript,
    SceneNumberGutters, ScriptSnapshot,
};

fn rows_for(output: &PaginatedScript, block: BlockId) -> Vec<&LayoutLine> {
    output
        .pages
        .iter()
        .flat_map(|page| page.lines.iter())
        .filter(|line| line.block == Some(block) && line.kind == LayoutLineKind::Content)
        .collect()
}

fn dialogue_id(document: &Document) -> BlockId {
    document
        .blocks()
        .iter()
        .find(|block| block.kind() == BlockKind::Dialogue)
        .expect("dialogue")
        .id()
}

#[test]
fn sung_rows_keep_raw_text_and_reset_at_a_hard_newline() {
    let sung = format!("~{}~tail", "a".repeat(34));
    let text = format!("{sung}\nSpoken ~literal.\n\\~escaped.\n\u{2003}~Next.");
    let document = Document::parse(&format!("SINGER\n{text}\n"));
    let dialogue = dialogue_id(&document);
    assert_eq!(document.block(dialogue).expect("dialogue").text(), text);
    let output = paginate(&document, &PageConfig::us_letter());
    let rows = rows_for(&output, dialogue);
    assert_eq!(rows.len(), 5);
    assert_eq!(rows[0].content, format!("~{}", "a".repeat(34)));
    assert_eq!(rows[1].content, "~tail");
    assert_eq!(rows[2].content, "Spoken ~literal.");
    assert_eq!(rows[3].content, "\\~escaped.");
    assert_eq!(rows[4].content, "\u{2003}~Next.");
    assert_eq!(
        rows.iter()
            .map(|line| (line.source_line, line.is_lyric, line.lyric_marker_utf8))
            .collect::<Vec<_>>(),
        [
            (Some(0), true, Some(0)),
            (Some(1), true, None),
            (Some(2), false, None),
            (Some(3), false, None),
            (Some(4), true, Some(3)),
        ]
    );
    assert!(rows.iter().all(|line| line.column == 10));
    assert_eq!(document.block(dialogue).expect("dialogue").text(), text);
}

#[test]
fn a_tilde_at_a_soft_wrap_start_does_not_start_a_sung_line() {
    let text = format!("{}~literal", "x".repeat(35));
    let document = Document::parse(&format!("SINGER\n{text}\n"));
    let output = paginate(&document, &PageConfig::us_letter());
    let rows = rows_for(&output, dialogue_id(&document));
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[1].content, "~literal");
    assert!(rows
        .iter()
        .all(|line| !line.is_lyric && line.lyric_marker_utf8.is_none()));
}

#[test]
fn expanded_tabs_and_wrapped_indentation_locate_only_the_actual_marker() {
    for (prefix, expected_first, sung_rows, expected_marker_row, expected_marker) in [
        ("\t".to_owned(), "    ~song".to_owned(), 1, 0, 4),
        ("\t\t".to_owned(), "        ~song".to_owned(), 1, 0, 8),
        ("\u{2003}".to_owned(), "\u{2003}~song".to_owned(), 1, 0, 3),
        (" ".repeat(34), format!("{}~", " ".repeat(34)), 2, 0, 34),
        (" ".repeat(35), " ".repeat(35), 2, 1, 0),
        ("\t".repeat(9), " ".repeat(35), 2, 1, 0),
        (format!("{}\t", " ".repeat(33)), " ".repeat(35), 2, 1, 0),
    ] {
        let document = Document::parse(&format!("SINGER\n{prefix}~song\nSpoken.\n"));
        let output = paginate(&document, &PageConfig::us_letter());
        let rows = rows_for(&output, dialogue_id(&document));
        assert_eq!(rows[0].content, expected_first, "{prefix:?}");
        assert_eq!(rows.len(), sung_rows + 1, "{prefix:?}");
        for (index, line) in rows[..rows.len() - 1].iter().enumerate() {
            assert!(line.is_lyric, "{prefix:?}, row {index}");
            assert_eq!(
                line.lyric_marker_utf8,
                (index == expected_marker_row).then_some(expected_marker),
                "{prefix:?}, row {index}"
            );
        }
        let last = rows.last().expect("spoken row");
        assert_eq!(last.content, "Spoken.");
        assert!(!last.is_lyric);
        assert_eq!(last.lyric_marker_utf8, None);
    }
}

#[test]
fn consumed_trailing_whitespace_still_ends_the_sung_hard_line() {
    let document = Document::parse(&format!("SINGER\n~song{}\nSpoken.\n", " ".repeat(80)));
    let output = paginate(&document, &PageConfig::us_letter());
    let rows = rows_for(&output, dialogue_id(&document));
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].content, format!("~song{}", " ".repeat(30)));
    assert!(rows[0].is_lyric);
    assert_eq!(rows[0].lyric_marker_utf8, Some(0));
    assert_eq!(rows[1].content, "Spoken.");
    assert!(!rows[1].is_lyric);
    assert_eq!(rows[1].lyric_marker_utf8, None);
}

#[test]
fn sung_dialogue_remains_one_speech_across_more_and_continued() {
    let text = format!("~{}", "a".repeat(35 * 7 - 1));
    let document = Document::parse(&format!("SINGER\n{text}\n"));
    let cue = document.blocks()[0].id();
    let dialogue = dialogue_id(&document);
    assert_eq!(document.blocks().len(), 2);
    let output = paginate(&document, &PageConfig::us_letter().with_line_capacity(6));
    assert_eq!(output.pages.len(), 2);
    let rows = rows_for(&output, dialogue);
    assert_eq!(rows.len(), 7);
    assert!(rows.iter().all(|line| line.is_lyric));
    assert_eq!(rows[0].lyric_marker_utf8, Some(0));
    assert!(rows[1..]
        .iter()
        .all(|line| line.lyric_marker_utf8.is_none()));
    assert_eq!(
        rows.iter().map(|line| line.source_line).collect::<Vec<_>>(),
        (0..7).map(Some).collect::<Vec<_>>()
    );
    let counts: Vec<_> = output
        .pages
        .iter()
        .map(|page| {
            page.lines
                .iter()
                .filter(|line| line.block == Some(dialogue))
                .count()
        })
        .collect();
    assert_eq!(counts, [4, 3]);
    assert!(output.pages[0].lines.iter().any(|line| {
        line.kind == LayoutLineKind::More && line.block == Some(cue) && line.content == "(MORE)"
    }));
    assert!(output.pages[1].lines.iter().any(|line| {
        line.kind == LayoutLineKind::Continued
            && line.block == Some(cue)
            && line.content == "SINGER (CONT'D)"
    }));
    assert!(output
        .pages
        .iter()
        .flat_map(|page| page.lines.iter())
        .filter(|line| line.kind != LayoutLineKind::Content)
        .all(|line| !line.is_lyric && line.lyric_marker_utf8.is_none()));
}

#[test]
fn non_dialogue_tildes_and_standalone_lyrics_keep_their_existing_layout() {
    let document = Document::parse(
        "Title: ~Title\n\n.~ROOM #7#\n\n!~Action.\n\n@~SINGER\n(~quietly)\nSpoken ~literally.\n\n~Standalone.\n",
    );
    let output = paginate(
        &document,
        &PageConfig::us_letter().with_scene_numbers(SceneNumberGutters::Both),
    );
    let lines: Vec<_> = output
        .pages
        .iter()
        .chain(output.title_page.iter())
        .flat_map(|page| page.lines.iter())
        .collect();
    for content in [
        "~Title",
        "~ROOM",
        "~Action.",
        "~SINGER",
        "(~quietly)",
        "Spoken ~literally.",
        "Standalone.",
    ] {
        assert!(
            lines.iter().any(|line| line.content == content),
            "{content}"
        );
    }
    assert!(lines
        .iter()
        .all(|line| !line.is_lyric && line.lyric_marker_utf8.is_none()));
}

#[test]
fn cached_full_and_incremental_pagination_retain_sung_row_metadata() {
    let mut source = String::new();
    for index in 0..24 {
        if index > 0 {
            source.push_str("\n===\n\n");
        }
        source.push_str(&format!("SINGER\n~{}~tail\nSpoken.\n", "a".repeat(34)));
    }
    let document = Document::parse(&source);
    let mut snapshot = ScriptSnapshot::from(&document);
    let config = PageConfig::us_letter().with_line_capacity(6);
    let mut engine = LayoutEngine::new();
    let initial = engine.paginate_snapshot(&snapshot, &config);
    assert_eq!(initial.pages.len(), 24);
    let cached = engine.paginate_snapshot(&snapshot, &config);
    assert_eq!(cached.pages, initial.pages);
    assert_eq!(cached.stats.block_misses, 0);
    assert!(cached.stats.block_hits > 0);

    let changed = snapshot
        .blocks
        .iter_mut()
        .filter(|block| block.kind == BlockKind::Dialogue)
        .nth(12)
        .expect("changed speech");
    changed.text = format!(" ~{}~tail\nSpoken.", "a".repeat(33));
    let changed_id = changed.id;
    snapshot.revision += 1;
    let incremental = engine.repaginate(&snapshot, &config, changed_id);
    assert_eq!(incremental.stats.block_misses, 1);
    assert!(incremental.stats.reused_pages >= 8);
    assert!(incremental.stats.reused_tail_pages >= 8);
    let changed_rows = rows_for(&incremental, changed_id);
    assert_eq!(changed_rows[0].lyric_marker_utf8, Some(1));
    assert!(changed_rows[0].is_lyric);
    assert_eq!(changed_rows[1].content, "~tail");
    assert!(changed_rows[1].is_lyric);
    assert_eq!(changed_rows[1].lyric_marker_utf8, None);
    assert!(!changed_rows[2].is_lyric);

    let fresh = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
    assert_eq!(incremental.pages, fresh.pages);
    let recached = engine.paginate_snapshot(&snapshot, &config);
    assert_eq!(recached.pages, fresh.pages);
    assert_eq!(recached.stats.block_misses, 0);
}
