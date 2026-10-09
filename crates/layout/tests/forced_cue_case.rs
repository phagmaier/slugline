use slugline_document::{BlockKind, Document, EditCommand};
use slugline_layout::{break_lines, LayoutEngine, LayoutLineKind, PageConfig, ScriptSnapshot};

#[test]
fn authored_case_survives_single_speech_continuations_without_mutating_source() {
    let body = (0..24)
        .map(|n| format!("Speech line {n}."))
        .collect::<Vec<_>>()
        .join("\n");
    let source = format!(".int. office - day\n\n@éßMcClane😀\n{body}\n");
    let document = Document::parse(&source);
    let snapshot = ScriptSnapshot::from(&document);
    let cue = snapshot
        .blocks
        .iter()
        .find(|b| b.kind == BlockKind::Character)
        .unwrap();
    assert!(cue.forced);
    assert_eq!(cue.text, "éßMcClane😀");
    let before = snapshot.clone();
    let result = LayoutEngine::new()
        .paginate_snapshot(&snapshot, &PageConfig::us_letter().with_line_capacity(8));
    assert!(result.pages.len() > 2);
    assert!(result.pages[0]
        .lines
        .iter()
        .any(|line| line.content == "INT. OFFICE - DAY"));
    let rows: Vec<_> = result
        .pages
        .iter()
        .flat_map(|p| p.lines.iter())
        .filter(|line| line.block == Some(cue.id))
        .collect();
    assert_eq!(rows[0].content, cue.text);
    assert_eq!(rows[0].source_line, Some(0));
    let continued: Vec<_> = rows
        .iter()
        .filter(|line| line.kind == LayoutLineKind::Continued)
        .collect();
    assert!(!continued.is_empty());
    assert!(continued
        .iter()
        .all(|line| line.content == "éßMcClane😀 (CONT'D)" && line.source_line.is_none()));
    assert_eq!(snapshot, before);
}

#[test]
fn dual_cue_wrapping_and_lane_continuations_preserve_each_authored_name() {
    let body = (0..24)
        .map(|n| format!("Speech line {n}."))
        .collect::<Vec<_>>()
        .join("\n");
    let source =
        format!("@McCLANEabcdefghijklm nopqr\n{body}\n\n@éßMcClane😀abcdefghijk ^\n{body}\n");
    let snapshot = ScriptSnapshot::from(&Document::parse(&source));
    let result = LayoutEngine::new()
        .paginate_snapshot(&snapshot, &PageConfig::us_letter().with_line_capacity(8));
    assert!(result.pages.len() > 2);
    for (index, column) in [(0, 8), (2, 40)] {
        let cue = &snapshot.blocks[index];
        assert!(cue.forced);
        let rows: Vec<_> = result
            .pages
            .iter()
            .flat_map(|p| p.lines.iter())
            .filter(|line| line.block == Some(cue.id) && line.kind == LayoutLineKind::Content)
            .collect();
        assert_eq!(
            rows.iter()
                .map(|line| line.content.as_str())
                .collect::<Vec<_>>(),
            break_lines(&cue.text, 20)
        );
        assert_eq!(
            rows.iter().map(|line| line.source_line).collect::<Vec<_>>(),
            (0..rows.len()).map(|n| Some(n as u16)).collect::<Vec<_>>()
        );
        assert!(rows.iter().all(|line| line.column == column));
        let continued: Vec<_> = result.pages[1]
            .lines
            .iter()
            .filter(|line| line.block == Some(cue.id) && line.kind == LayoutLineKind::Continued)
            .collect();
        assert_eq!(
            continued
                .iter()
                .map(|line| line.content.as_str())
                .collect::<Vec<_>>(),
            break_lines(&format!("{} (CONT'D)", cue.text), 20)
        );
        assert!(continued
            .iter()
            .all(|line| line.column == column && line.source_line.is_none()));
    }
}

#[test]
fn forcing_only_case_change_invalidates_one_wrap_and_matches_full_pagination() {
    let body = (0..24)
        .map(|n| format!("Speech line {n}."))
        .collect::<Vec<_>>()
        .join("\n");
    for dual in [false, true] {
        let source = format!(
            "Unrelated action.\n\n@McCLANE\n{body}\n\n@Partner{}\n{body}\n",
            if dual { " ^" } else { "" }
        );
        let mut snapshot = ScriptSnapshot::from(&Document::parse(&source));
        let cue_index = snapshot
            .blocks
            .iter()
            .position(|b| b.text == "McCLANE")
            .unwrap();
        let cue_id = snapshot.blocks[cue_index].id;
        let config = PageConfig::us_letter().with_line_capacity(8);
        let mut cached = LayoutEngine::new();
        cached.paginate_snapshot(&snapshot, &config);
        for forced in [false, true, false, true] {
            snapshot.blocks[cue_index].forced = forced;
            snapshot.revision += 1;
            let incremental = cached.repaginate(&snapshot, &config, cue_id);
            let full = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
            assert_eq!(incremental.pages, full.pages);
            assert_eq!(incremental.title_page, full.title_page);
            assert_eq!(incremental.checkpoints, full.checkpoints);
            assert_eq!(incremental.stats.block_misses, 1);
            assert_eq!(incremental.stats.block_hits, snapshot.blocks.len() - 1);
            let cue = incremental
                .pages
                .iter()
                .flat_map(|p| p.lines.iter())
                .find(|line| line.block == Some(cue_id) && line.kind == LayoutLineKind::Content)
                .unwrap();
            assert_eq!(cue.content, if forced { "McCLANE" } else { "MCCLANE" });
            assert_eq!(snapshot.blocks[cue_index].text, "McCLANE");
            assert_eq!(snapshot.blocks[cue_index].kind, BlockKind::Character);
        }
    }
}

#[test]
fn authored_continued_extensions_keep_case_without_a_duplicate_suffix() {
    let body = (0..24)
        .map(|n| format!("Speech line {n}."))
        .collect::<Vec<_>>()
        .join("\n");
    for dual in [false, true] {
        let source = format!(
            "@McCLANE (cont'd)\n{body}\n\n@Partner (Cont'D){}\n{body}\n",
            if dual { " ^" } else { "" }
        );
        let snapshot = ScriptSnapshot::from(&Document::parse(&source));
        let result = LayoutEngine::new()
            .paginate_snapshot(&snapshot, &PageConfig::us_letter().with_line_capacity(8));
        for cue in snapshot
            .blocks
            .iter()
            .filter(|b| b.kind == BlockKind::Character)
        {
            let continued: Vec<_> = result
                .pages
                .iter()
                .flat_map(|p| p.lines.iter())
                .filter(|line| line.block == Some(cue.id) && line.kind == LayoutLineKind::Continued)
                .collect();
            assert!(!continued.is_empty());
            assert!(continued.iter().all(|line| line.content == cue.text));
        }
    }
}

#[test]
fn case_selection_keeps_x4_original_utf8_projection_for_styled_unicode_cues() {
    let document = Document::parse("@**ıéßMcClane😀e\u{301}**\nHello.\n");
    let mut snapshot = ScriptSnapshot::from(&document);
    let cue = snapshot.blocks[0].clone();
    let config = PageConfig::us_letter();
    let mut spans = Vec::new();
    for forced in [false, true] {
        snapshot.blocks[0].forced = forced;
        let output = LayoutEngine::new().paginate_snapshot(&snapshot, &config);
        let line = output
            .pages
            .iter()
            .flat_map(|page| page.lines.iter())
            .find(|line| line.block == Some(cue.id) && line.kind == LayoutLineKind::Content)
            .unwrap();
        let span = line.source_span.unwrap();
        assert_eq!(span.start_utf8, 0);
        assert_eq!(span.end_utf8, cue.text.len());
        assert_eq!(
            cue.text.get(span.start_utf8..span.end_utf8),
            Some(cue.text.as_str())
        );
        spans.push(span);
        let runs = line.resolved_runs.as_ref().unwrap();
        assert!(runs.iter().all(|run| run.emphasis.bold));
        assert_eq!(
            runs.iter().map(|run| run.text.as_str()).collect::<String>(),
            if forced {
                "ıéßMcClane😀e\u{301}"
            } else {
                "IÉßMCCLANE😀E\u{301}"
            }
        );
    }
    assert_eq!(spans[0], spans[1]);
    assert_eq!(document.serialise(), "@**ıéßMcClane😀e\u{301}**\nHello.\n");
}

#[test]
fn edited_forced_extension_keeps_its_rendering_through_save_and_reopen() {
    let mut document = Document::parse("@MARY\nHello.\n");
    let id = document.blocks()[0].id();
    document
        .apply(EditCommand::ReplaceText {
            block: id,
            range: 0..4,
            with: "ÉLODIE (on the phone)".to_owned(),
        })
        .unwrap();
    let written = document.serialise();
    let reopened = Document::parse(&written);
    let printed = |document: &Document| {
        LayoutEngine::new()
            .paginate_snapshot(&ScriptSnapshot::from(document), &PageConfig::us_letter())
            .pages[0]
            .lines
            .iter()
            .find(|line| line.block == Some(id) && line.kind == LayoutLineKind::Content)
            .unwrap()
            .content
            .clone()
    };
    assert_eq!(printed(&document), "ÉLODIE (on the phone)");
    assert_eq!(
        printed(&reopened),
        printed(&document),
        "saved syntax must retain authored cue case"
    );
    assert_eq!(written, "@ÉLODIE (on the phone)\nHello.\n");
    assert!(document.blocks()[0].forced());
}
