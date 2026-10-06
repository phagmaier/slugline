use slugline_fountain::{dialogue_lyric_marker_utf8, parse, serialise, BlockKind, Output};

#[test]
fn only_a_leading_unescaped_tilde_is_a_dialogue_lyric_marker() {
    for (line, expected) in [
        ("~Sung.", Some(0)),
        ("  ~Sung.", Some(2)),
        ("\t~Sung.", Some(1)),
        ("\u{2003}\t~Sung.", Some(4)),
        ("~", Some(0)),
        ("~~Two tildes.", Some(0)),
        ("", None),
        (" \t", None),
        ("Spoken ~literally.", None),
        ("\\~Escaped.", None),
        ("  \\~Escaped.", None),
        ("(~Parenthetical.)", None),
        ("*~Emphasized literal.*", None),
    ] {
        assert_eq!(dialogue_lyric_marker_utf8(line), expected, "{line:?}");
        if let Some(offset) = expected {
            assert_eq!(&line[offset..offset + 1], "~");
        }
    }
}

#[test]
fn sung_lines_keep_dialogue_topology_text_and_byte_exact_provenance() {
    let source = "\u{feff}SINGER\r\n  ~First.\r\nSpoken ~literal.\r\n\\~Escaped.\r\n(~quietly)\r\n~Last.\r\n\r\n~Standalone.\r\n";
    let script = parse(source);
    let elements: Vec<_> = script
        .elements
        .iter()
        .map(|element| element.as_ref())
        .collect();
    assert_eq!(
        script
            .elements
            .iter()
            .map(|element| (element.kind, element.text.as_str()))
            .collect::<Vec<_>>(),
        [
            (BlockKind::Character, "SINGER"),
            (
                BlockKind::Dialogue,
                "  ~First.\nSpoken ~literal.\n\\~Escaped.",
            ),
            (BlockKind::Parenthetical, "(~quietly)"),
            (BlockKind::Dialogue, "~Last."),
            (BlockKind::Lyric, "Standalone."),
        ]
    );
    assert_eq!(
        script.elements[1]
            .text
            .split('\n')
            .map(dialogue_lyric_marker_utf8)
            .collect::<Vec<_>>(),
        [Some(2), None, None]
    );

    let mut cursor = '\u{feff}'.len_utf8();
    let title_range = script.title_page.provenance.clone().expect("title range");
    assert_eq!(title_range.start, cursor);
    cursor = title_range.end;
    for element in &script.elements {
        let range = element.provenance.clone().expect("element range");
        assert_eq!(range.start, cursor);
        assert!(range.end >= range.start);
        cursor = range.end;
    }
    assert_eq!(cursor, source.len());
    assert_eq!(
        serialise(&Output {
            title_page: &script.title_page,
            elements: &elements,
            source: Some(source),
            bom: script.bom,
            line_ending: script.line_ending,
        }),
        source
    );
}
