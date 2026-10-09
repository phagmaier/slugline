//! Self-authored boundary cases and one unmodified independent producer fixture.
use quick_xml::{events::Event, Reader};
use slugline_fdx::{read, write};
use slugline_fountain::{
    emphasis, BlockKind, Element, Emphasis, Script, TitleEntry, TitleField, TitlePage,
};

fn wrap(content: &str) -> String {
    format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?><FinalDraft DocumentType=\"Script\"><Content>{content}</Content></FinalDraft>")
}
fn printable(text: &str) -> String {
    let rows: Vec<_> = text.split('\n').collect();
    emphasis::scan(&rows)
        .iter()
        .map(|runs| runs.iter().map(|r| r.text.as_str()).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n")
}
fn item(kind: BlockKind, text: &str, dual: bool) -> Element {
    Element {
        kind,
        text: text.into(),
        dual,
        forced: true,
        provenance: None,
    }
}
fn export(script: &Script) -> slugline_fdx::ExportedScript {
    write(
        &script.title_page,
        script.elements.iter().map(Element::as_ref),
    )
    .unwrap()
}
fn native_source(script: &Script) -> String {
    let elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
    slugline_fountain::serialise(&slugline_fountain::Output {
        title_page: &script.title_page,
        elements: &elements,
        source: None,
        bom: false,
        line_ending: script.line_ending,
    })
}

#[test]
fn typed_paragraphs_hard_lines_whitespace_unicode_and_escaping_are_conserved() {
    let source = wrap(
        r#"<Paragraph Type="Scene Heading" Number="12A"><Text>INT. CAFÉ - DAY</Text></Paragraph>
<Paragraph Type="Action"><Text>  雪 &amp; &lt;light&gt; **literal** _x_ \path
next line	 </Text><Text>tail</Text></Paragraph>
<Paragraph Type="Action" Alignment="Center"><Text>THE END</Text></Paragraph>
<Paragraph Type="Lyrics"><Text>sing ♪</Text></Paragraph>
<Paragraph Type="Character"><Text>ALICE</Text></Paragraph>
<Paragraph Type="Parenthetical"><Text>(softly)</Text></Paragraph>
<Paragraph Type="Dialogue"><Text>Hello.</Text><LineBreak/><Text>Again.</Text></Paragraph>
<Paragraph Type="Transition"><Text>CUT TO:</Text></Paragraph>"#,
    );
    let imported = read(source.as_bytes()).unwrap();
    assert!(imported.warnings.is_empty(), "{:?}", imported.warnings);
    let elements = &imported.script.elements;
    assert_eq!(
        elements.iter().map(|e| e.kind).collect::<Vec<_>>(),
        [
            BlockKind::SceneHeading,
            BlockKind::Action,
            BlockKind::Centered,
            BlockKind::Lyric,
            BlockKind::Character,
            BlockKind::Parenthetical,
            BlockKind::Dialogue,
            BlockKind::Transition
        ]
    );
    assert_eq!(elements[0].text, "INT. CAFÉ - DAY #12A#");
    assert_eq!(
        printable(&elements[1].text),
        "  雪 & <light> **literal** _x_ \\path\nnext line\t tail"
    );
    assert_eq!(printable(&elements[6].text), "Hello.\nAgain.");
    assert!(elements.iter().all(|e| e.provenance.is_none()));
}

#[test]
fn styles_coalesce_and_literal_markup_is_not_accidentally_paired() {
    let source = wrap(
        r#"<Paragraph Type="Action"><Text Style="Bold">One </Text><Text Style="Bold">two</Text><Text> *literal* _file_ \</Text><Text Style="Italic+Underline">three</Text></Paragraph>"#,
    );
    let imported = read(source.as_bytes()).unwrap();
    let markup = &imported.script.elements[0].text;
    assert_eq!(printable(markup), "One two *literal* _file_ \\three");
    let runs = emphasis::scan_row(markup);
    assert!(runs.iter().any(|r| r.text == "One two" && r.emphasis.bold));
    assert!(runs
        .iter()
        .any(|r| r.text == "three" && r.emphasis.italic && r.emphasis.underline));
    assert!(runs
        .iter()
        .any(|r| r.text.contains("*literal* _file_ ") && r.emphasis == Emphasis::PLAIN));
}

#[test]
fn unrepresentable_adjacent_style_boundaries_warn_without_losing_words() {
    let imported = read(wrap(r#"<Paragraph Type="Action"><Text Style="Italic">a</Text><Text Style="Bold">b</Text><Text Style="Italic">c</Text></Paragraph>"#).as_bytes()).unwrap();
    assert_eq!(printable(&imported.script.elements[0].text), "abc");
    assert!(!imported.warnings.is_empty());
    let imported = read(wrap(r#"<Paragraph Type="Action"><Text Style="Bold+Strikeout" AdornmentStyle="-1"> kept </Text></Paragraph>"#).as_bytes()).unwrap();
    assert_eq!(printable(&imported.script.elements[0].text), " kept ");
    assert!(imported.warnings.iter().any(|w| w.contains("Strikeout")));
    assert!(imported
        .warnings
        .iter()
        .any(|w| w.contains("AdornmentStyle")));
}

#[test]
fn genuine_dual_wrapper_is_linearized_without_inventing_orphan_partners() {
    let imported = read(wrap(r#"<Paragraph><DualDialogue><Paragraph Type="Character"><Text>A</Text></Paragraph><Paragraph Type="Dialogue"><Text>First</Text></Paragraph><Paragraph Type="Character"><Text>B</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(together)</Text></Paragraph><Paragraph Type="Dialogue"><Text>Second</Text></Paragraph></DualDialogue></Paragraph>"#).as_bytes()).unwrap();
    assert_eq!(imported.script.elements.len(), 5);
    assert!(!imported.script.elements[0].dual);
    assert!(imported.script.elements[2].dual);
    let orphan = read(wrap(r#"<Paragraph><DualDialogue><Paragraph Type="Character"><Text>LONE</Text></Paragraph><Paragraph Type="Dialogue"><Text>Still retained</Text></Paragraph></DualDialogue></Paragraph>"#).as_bytes()).unwrap();
    assert_eq!(orphan.script.elements.len(), 2);
    assert!(!orphan.script.elements[0].dual);
    assert!(!orphan.warnings.is_empty());
}

#[test]
fn writer_uses_independently_readable_disjoint_dual_shape_and_retains_orphans() {
    let script = Script {
        elements: vec![
            item(BlockKind::Character, "A", false),
            item(BlockKind::Dialogue, "first", false),
            item(BlockKind::Character, "B", true),
            item(BlockKind::Dialogue, "second", false),
            item(BlockKind::Character, "C", true),
            item(BlockKind::Dialogue, "orphan", false),
        ],
        ..Default::default()
    };
    let exported = export(&script);
    let mut reader = Reader::from_str(&exported.xml);
    reader.config_mut().enable_all_checks(true);
    let mut path = Vec::new();
    let mut wrappers = 0;
    let mut characters_inside = 0;
    let mut words = String::new();
    loop {
        match reader.read_event().unwrap() {
            Event::Start(start) => {
                let name = String::from_utf8(start.name().as_ref().to_vec()).unwrap();
                if name == "DualDialogue" {
                    assert_eq!(path.last().map(String::as_str), Some("Paragraph"));
                    wrappers += 1;
                }
                if name == "Paragraph" && path.last().map(String::as_str) == Some("DualDialogue") {
                    let attrs: Vec<_> = start.attributes().map(Result::unwrap).collect();
                    if attrs
                        .iter()
                        .any(|a| a.key.as_ref() == b"Type" && a.value.as_ref() == b"Character")
                    {
                        characters_inside += 1;
                    }
                }
                path.push(name);
            }
            Event::End(end) => {
                assert_eq!(path.pop().unwrap().as_bytes(), end.name().as_ref());
            }
            Event::Text(text) => {
                words.push_str(&text.decode().unwrap());
            }
            Event::Eof => break,
            _ => {}
        }
    }
    assert!(path.is_empty());
    assert_eq!(wrappers, 1);
    assert_eq!(characters_inside, 2);
    for word in ["first", "second", "orphan"] {
        assert!(words.contains(word));
    }
    assert!(exported.warnings.iter().any(|w| w.contains("Orphan")));
    assert_eq!(
        read(exported.xml.as_bytes()).unwrap().script.elements,
        script.elements
    );
}

#[test]
fn intervening_nonprinting_content_interrupts_dual_pairs_and_warns() {
    let script = Script {
        elements: vec![
            item(BlockKind::Character, "A", false),
            item(BlockKind::Dialogue, "first", false),
            item(BlockKind::Note, "Keep this *literal* note", false),
            item(BlockKind::Character, "B", true),
            item(BlockKind::Dialogue, "second", false),
        ],
        ..Default::default()
    };
    let exported = export(&script);
    assert!(!exported.xml.contains("<DualDialogue>"));
    assert!(exported.xml.contains("Keep this *literal* note"));
    assert!(exported.warnings.iter().any(|w| w.contains("Nonprinting")));
    assert_eq!(
        read(exported.xml.as_bytes()).unwrap().script.elements,
        script.elements
    );
}

#[test]
fn all_nonprinting_content_and_title_fields_self_import_exactly_with_honest_warnings() {
    let script = Script {
        title_page: TitlePage {
            entries: vec![
                TitleEntry {
                    field: TitleField::Title,
                    value: "A *Title* & more\nSubtitle".into(),
                },
                TitleEntry {
                    field: TitleField::Credit,
                    value: "Written by".into(),
                },
                TitleEntry {
                    field: TitleField::Author,
                    value: "Zoë".into(),
                },
                TitleEntry {
                    field: TitleField::Other("Revision colour".into()),
                    value: "Blue <green>".into(),
                },
            ],
            provenance: None,
        },
        elements: vec![
            item(BlockKind::Section { level: 2 }, "outline", false),
            item(BlockKind::Synopsis, "synopsis", false),
            item(BlockKind::Note, "notes\nhard line", false),
            item(BlockKind::Opaque, "/* omitted *literal* words */\n", false),
            item(BlockKind::PageBreak, "", false),
            item(
                BlockKind::Action,
                "visible [[inline note]] /* inline omission */",
                false,
            ),
        ],
        ..Default::default()
    };
    let exported = export(&script);
    assert!(exported.warnings.len() >= 5);
    for word in [
        "outline",
        "synopsis",
        "omitted",
        "inline note",
        "inline omission",
    ] {
        assert!(exported.xml.contains(word));
    }
    let imported = read(exported.xml.as_bytes()).unwrap();
    assert_eq!(imported.script.elements, script.elements);
    assert_eq!(imported.script.title_page, script.title_page);
}

#[test]
fn positional_title_grouping_preserves_unmatched_text() {
    let source = "<FinalDraft><Content/><TitlePage><Content><Paragraph Alignment=\"Center\"><Text>MY TITLE</Text></Paragraph><Paragraph Alignment=\"Center\"><Text>Written by</Text></Paragraph><Paragraph Alignment=\"Center\"><Text>Alex Writer</Text></Paragraph><Paragraph Alignment=\"Left\"><Text>Unmatched address\nsecond line</Text></Paragraph></Content></TitlePage></FinalDraft>";
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(
        imported.script.title_page.get(&TitleField::Title),
        Some("MY TITLE")
    );
    assert_eq!(
        imported.script.title_page.get(&TitleField::Credit),
        Some("Written by")
    );
    assert_eq!(
        imported.script.title_page.get(&TitleField::Author),
        Some("Alex Writer")
    );
    assert_eq!(
        imported.script.title_page.get(&TitleField::Notes),
        Some("Unmatched address\nsecond line")
    );
    assert!(!imported.warnings.is_empty());
}

#[test]
fn unknown_paragraphs_and_multiline_single_line_kinds_preserve_words_with_warnings() {
    let source = wrap("<Paragraph Type=\"Custom User Type\"><Text>Unknown words</Text></Paragraph><Paragraph Type=\"Character\"><Text>NAME\nMORE</Text></Paragraph><Paragraph Type=\"Action\" StartsNewPage=\"Yes\"><Text>After break</Text></Paragraph>");
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(
        imported
            .script
            .elements
            .iter()
            .map(|e| e.kind)
            .collect::<Vec<_>>(),
        [
            BlockKind::Action,
            BlockKind::Action,
            BlockKind::PageBreak,
            BlockKind::Action
        ]
    );
    assert_eq!(
        printable(&imported.script.elements[0].text),
        "Unknown words"
    );
    assert_eq!(printable(&imported.script.elements[1].text), "NAME\nMORE");
    assert!(imported.warnings.len() >= 2);
}

#[test]
fn unsupported_textual_structures_refuse_the_entire_operation() {
    for content in [
        "<Unknown><Text>Do not lose me</Text></Unknown>",
        "<Paragraph Type=\"Action\"><Text>before<Nested>hidden</Nested>after</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><ScriptNote><Text>private words</Text></ScriptNote></Paragraph>",
        "<Paragraph Type=\"Action\">raw words</Paragraph>",
        "<Unknown>unmapped text</Unknown>",
        "<Paragraph><DualDialogue/></Paragraph>",
    ] { assert!(read(wrap(content).as_bytes()).is_err(), "{content}"); }
}

#[test]
fn malformed_xml_and_custom_entities_do_not_become_empty_documents() {
    for source in [
        "", "<FinalDraft>", "<FinalDraft><Content></FinalDraft>",
        "<FinalDraft><Content/></FinalDraft><FinalDraft><Content/></FinalDraft>",
        "<!DOCTYPE FinalDraft SYSTEM 'https://example.invalid/fdx.dtd'><FinalDraft><Content/></FinalDraft>",
        "<!DOCTYPE FinalDraft [<!ENTITY injected 'words'>]><FinalDraft><Content/></FinalDraft>",
        "<FinalDraft><Content><Paragraph><Text>&unknown;</Text></Paragraph></Content></FinalDraft>",
        "<FinalDraft><Content><Paragraph Type='Action' Type='Dialogue'><Text>words</Text></Paragraph></Content></FinalDraft>",
        "<?xml version='1.1'?><FinalDraft><Content/></FinalDraft>",
        "<?xml version='1.0' standalone='maybe'?><FinalDraft><Content/></FinalDraft>",
        "<FinalDraft><Content><Paragraph><Text>&#0;</Text></Paragraph></Content></FinalDraft>",
    ] { assert!(read(source.as_bytes()).is_err(), "{source}"); }
}

#[test]
fn utf8_bom_utf16_both_byte_orders_and_declared_encoding_are_checked() {
    let utf8 = wrap("<Paragraph Type=\"Action\"><Text>雪 😀 café</Text></Paragraph>");
    let mut bom_utf8 = vec![0xef, 0xbb, 0xbf];
    bom_utf8.extend_from_slice(utf8.as_bytes());
    assert_eq!(
        printable(&read(&bom_utf8).unwrap().script.elements[0].text),
        "雪 😀 café"
    );
    let utf16 = utf8.replace("UTF-8", "UTF-16");
    for little in [true, false] {
        let mut bytes = if little {
            vec![0xff, 0xfe]
        } else {
            vec![0xfe, 0xff]
        };
        for word in utf16.encode_utf16() {
            bytes.extend_from_slice(&if little {
                word.to_le_bytes()
            } else {
                word.to_be_bytes()
            });
        }
        assert_eq!(
            printable(&read(&bytes).unwrap().script.elements[0].text),
            "雪 😀 café"
        );
        bytes.pop();
        assert!(read(&bytes).is_err());
    }
    assert!(read(utf8.replace("UTF-8", "windows-1252").as_bytes()).is_err());
    assert!(read(utf8.replace("UTF-8", "UTF-16").as_bytes()).is_err());
    assert!(read(&[0xff, 0xfe, 0x00, 0xd8]).is_err());
    assert!(read(&[0xff]).is_err());
}

#[test]
fn tampered_metadata_and_unrepresentable_export_are_refused() {
    let source = wrap(
        r#"<Paragraph Type="Action" SluglineKind="Action" SluglineRaw="hidden replacement"><Text>visible words</Text></Paragraph>"#,
    );
    assert!(read(source.as_bytes()).is_err());
    let source = wrap(
        r#"<Paragraph Type="Scene Heading" Number="bad#number"><Text>INT. ROOM</Text></Paragraph>"#,
    );
    assert!(read(source.as_bytes()).is_err());
    for e in [
        item(BlockKind::Action, "nul\0word", false),
        item(BlockKind::SceneHeading, "a\nb", false),
        item(BlockKind::PageBreak, "retained words", false),
        item(BlockKind::Dialogue, "words", true),
    ] {
        assert!(write(&TitlePage::default(), [e.as_ref()]).is_err());
    }
}

#[test]
fn imported_native_base_normalizes_spacers_and_dialogue_without_shifting_later_ids() {
    let source = wrap(
        r#"<Paragraph Type="General"/><Paragraph Type="Character"><Text>A</Text></Paragraph><Paragraph Type="Dialogue"><Text>first</Text></Paragraph><Paragraph Type="Dialogue"><Text>second</Text></Paragraph><Paragraph Type="General"/><Paragraph Type="Action"><Text>Later editable block</Text></Paragraph>"#,
    );
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(imported.script.elements.len(), 3);
    assert_eq!(imported.script.elements[1].text, "first\nsecond");
    assert_eq!(imported.script.elements[2].text, "Later editable block");
    let base = slugline_fountain::parse(&native_source(&imported.script));
    assert_eq!(base.elements.len(), imported.script.elements.len());
    for (stored, parsed) in imported.script.elements.iter().zip(&base.elements) {
        assert_eq!(
            (stored.kind, &stored.text, stored.dual),
            (parsed.kind, &parsed.text, parsed.dual)
        );
    }
    assert!(imported.warnings.iter().any(|w| w.contains("spacer")));
    assert!(imported.warnings.iter().any(|w| w.contains("coalesced")));
}

#[test]
fn empty_import_has_a_real_native_action_identity() {
    let imported = read(wrap("").as_bytes()).unwrap();
    assert_eq!(imported.script.elements.len(), 1);
    assert_eq!(imported.script.elements[0].kind, BlockKind::Action);
    assert!(imported.script.elements[0].text.is_empty());
    assert!(imported.script.elements[0].forced);
    let base = slugline_fountain::parse(&native_source(&imported.script));
    assert_eq!(base.elements.len(), 1);
    assert_eq!(base.elements[0].kind, BlockKind::Action);
}

#[test]
fn ordinary_paragraphs_do_not_embed_redundant_raw_source() {
    let script = Script {
        title_page: TitlePage {
            entries: vec![TitleEntry {
                field: TitleField::Title,
                value: "Title".into(),
            }],
            provenance: None,
        },
        elements: vec![item(
            BlockKind::Action,
            "plain **bold** and escaped \\*literal\\*",
            false,
        )],
        ..Default::default()
    };
    let exported = export(&script);
    assert!(!exported.xml.contains("SluglineRaw"));
    assert_eq!(
        printable(&read(exported.xml.as_bytes()).unwrap().script.elements[0].text),
        printable(&script.elements[0].text)
    );
}

#[test]
fn authored_notes_and_headers_are_retained_but_completion_caches_are_not_story_content() {
    let source = "<FinalDraft><Content><Paragraph Type=\"Scene Heading\" Number=\"1\"><SceneProperties Title=\"scene description\"/><Text>INT. ROOM</Text></Paragraph><Paragraph Type=\"Action\"><ScriptNote><Paragraph><Text>writer note</Text></Paragraph></ScriptNote><Text>/* literal omitted-looking text */</Text></Paragraph></Content><HeaderAndFooter><Header><Paragraph><DynamicLabel Type=\"Page #\"/><Text>custom header</Text></Paragraph></Header></HeaderAndFooter><SmartType><Characters><Character>Extra name</Character></Characters></SmartType></FinalDraft>";
    let imported = read(source.as_bytes()).unwrap();
    let body = imported
        .script
        .elements
        .iter()
        .find(|e| e.kind == BlockKind::Action)
        .unwrap();
    assert_eq!(printable(&body.text), "/* literal omitted-looking text */");
    assert!(
        !body.text.contains("/*"),
        "literal XML is not a Fountain boneyard"
    );
    for words in [
        "scene description",
        "writer note",
        "FDX Header: custom header",
    ] {
        assert!(imported
            .script
            .elements
            .iter()
            .any(|e| e.kind == BlockKind::Note && printable(&e.text) == words));
    }
    assert!(!imported
        .script
        .elements
        .iter()
        .any(|e| e.text.contains("Extra name")));
    assert!(imported.warnings.iter().any(|w| w.contains("SmartType")));
    assert!(!imported.warnings.is_empty());
    let reopened = slugline_fountain::parse(&native_source(&imported.script));
    assert!(reopened.elements.iter().any(|e| e.kind == BlockKind::Action
        && printable(&e.text) == "/* literal omitted-looking text */"));
}

#[test]
fn stale_style_number_and_partial_raw_metadata_refuse_without_losing_actual_words() {
    for content in [
        r#"<Paragraph Type="Action" SluglineKind="Action" SluglineRaw="**same words**"><Text>same words</Text></Paragraph>"#,
        r#"<Paragraph Type="Scene Heading" SluglineKind="SceneHeading" SluglineRaw="INT. ROOM #1#" Number="2"><Text>INT. ROOM</Text></Paragraph>"#,
        r#"<Paragraph Type="Action" SluglineRaw="ignored words"><Text>actual words</Text></Paragraph>"#,
        r#"<Paragraph Type="Action"><Text>literal [[words]] remain printable</Text></Paragraph>"#,
    ] {
        assert!(read(wrap(content).as_bytes()).is_err());
    }
}

#[test]
fn actual_fade_in_5_0_15_producer_fixture_preserves_body_title_styles_and_annotations() {
    // Parent generated this fixture with the isolated official demo. It is not
    // inferred from a FinalDraft root or copied from an external repository.
    let source = include_bytes!("../../../testdata/fdx/fade-in-5.0.15.fdx");
    let imported = read(source).unwrap();
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::SceneHeading && e.text == "INT. IMPORT ROOM - DAY #12A#"));
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Character && e.text == "BOB" && e.dual));
    let action = imported
        .script
        .elements
        .iter()
        .find(|e| printable(&e.text).starts_with("Action bold"))
        .unwrap();
    let runs = emphasis::scan_row(&action.text);
    assert!(runs.iter().any(|r| r.text == "bold" && r.emphasis.bold));
    assert!(runs.iter().any(|r| r.text == "italic" && r.emphasis.italic));
    assert!(runs
        .iter()
        .any(|r| r.text == "underline" && r.emphasis.underline));
    assert!(printable(&action.text).contains("literal * and Unicode café 😀."));
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Note && printable(&e.text) == "writer note"));
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Action && printable(&e.text) == "/* omitted text */"));
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Centered && e.text == "THE END"));
    assert!(imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::PageBreak));
    assert_eq!(
        printable(imported.script.title_page.get(&TitleField::Title).unwrap()),
        "Interchange Trial"
    );
    assert_eq!(
        imported.script.title_page.get(&TitleField::Author),
        Some("Agent Fixture")
    );
    assert!(!imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Note && e.text == "."));
    assert!(!imported
        .script
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Note && e.text == "THE NEXT DAY"));
    let native = slugline_fountain::parse(&native_source(&imported.script));
    assert_eq!(native.elements.len(), imported.script.elements.len());
    assert!(native
        .elements
        .iter()
        .any(|e| e.kind == BlockKind::Action && printable(&e.text) == "/* omitted text */"));
}

#[test]
fn centered_and_lyric_hard_lines_keep_their_explicit_kinds() {
    let imported = read(
        wrap(
            r#"<Paragraph Type="Action" Alignment="Center"><Text>first center
second center</Text></Paragraph><Paragraph Type="Lyrics"><Text>first lyric
second lyric</Text></Paragraph>"#,
        )
        .as_bytes(),
    )
    .unwrap();
    assert_eq!(
        imported
            .script
            .elements
            .iter()
            .map(|e| (e.kind, e.text.as_str()))
            .collect::<Vec<_>>(),
        [
            (BlockKind::Centered, "first center"),
            (BlockKind::Centered, "second center"),
            (BlockKind::Lyric, "first lyric"),
            (BlockKind::Lyric, "second lyric")
        ]
    );
    assert!(imported.warnings.iter().any(|w| w.contains("consecutive")));
}

#[test]
fn positional_title_and_author_paragraph_groups_are_not_dropped_at_layout_spacers() {
    let source = "<FinalDraft><Content/><TitlePage><Content><Paragraph/><Paragraph Alignment=\"Center\"><Text>Main title</Text></Paragraph><Paragraph/><Paragraph Alignment=\"Center\"><Text>Subtitle</Text></Paragraph><Paragraph Alignment=\"Center\"><Text>Written by</Text></Paragraph><Paragraph/><Paragraph Alignment=\"Center\"><Text>First author</Text></Paragraph><Paragraph Alignment=\"Center\"><Text>Second author</Text></Paragraph></Content></TitlePage></FinalDraft>";
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(
        imported.script.title_page.get(&TitleField::Title),
        Some("Main title\nSubtitle")
    );
    assert_eq!(
        imported.script.title_page.get(&TitleField::Author),
        Some("First author\nSecond author")
    );
}

#[test]
fn cdata_and_numeric_entities_preserve_literals_and_exact_text_boundaries() {
    let source = wrap(
        r#"<Paragraph Type="Action"><Text><![CDATA[<literal> & *not emphasis* \path]]>&#10;&#x96EA;&#9;last&#32;</Text></Paragraph>"#,
    );
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(
        printable(&imported.script.elements[0].text),
        "<literal> & *not emphasis* \\path\n雪\tlast "
    );
    assert!(read(
        wrap("<Paragraph Type='Action'><Text>illegal ]]&gt; outside CDATA</Text></Paragraph>")
            .as_bytes()
    )
    .is_ok());
    assert!(read(
        wrap("<Paragraph Type='Action'><Text>illegal ]]> outside CDATA</Text></Paragraph>")
            .as_bytes()
    )
    .is_err());
}

#[test]
fn illegal_xml_scalars_refuse_import_and_export_instead_of_stripping_words() {
    for scalar in [
        '\0', '\u{1}', '\u{b}', '\u{c}', '\u{1f}', '\u{fffe}', '\u{ffff}',
    ] {
        let words = format!("before {scalar} after");
        let source = wrap(&format!(
            "<Paragraph Type=\"Action\"><Text>{words}</Text></Paragraph>"
        ));
        assert!(read(source.as_bytes()).is_err());
        assert!(source.contains(&words));
        let e = item(BlockKind::Action, &words, false);
        assert!(write(&TitlePage::default(), [e.as_ref()]).is_err());
        assert_eq!(e.text, words);
    }
    assert!(
        read(wrap("<Paragraph Type='Action'><Text>&#1;</Text></Paragraph>").as_bytes()).is_err()
    );
    assert!(read(
        wrap("<Paragraph Type='Action' Number='&#0;'><Text>retained words</Text></Paragraph>")
            .as_bytes()
    )
    .is_err());
}

#[test]
fn xml10_crlf_and_cr_hard_lines_normalize_without_losing_whitespace_or_words() {
    let source = wrap("<Paragraph Type='Action'><Text> first\r\nsecond\rlast </Text></Paragraph>");
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(
        printable(&imported.script.elements[0].text),
        " first\nsecond\nlast "
    );
    assert!(source.contains("\r\n"));
    let source =
        wrap("<Paragraph Type='Action'><Text><![CDATA[first\r\nsecond]]></Text></Paragraph>");
    assert_eq!(
        printable(&read(source.as_bytes()).unwrap().script.elements[0].text),
        "first\nsecond"
    );
}

#[test]
fn default_page_number_punctuation_and_completion_cache_are_not_authored_notes() {
    let source = "<FinalDraft><Content><Paragraph Type='Action'><Text>Only story words</Text></Paragraph></Content><HeaderAndFooter><Header><Paragraph><DynamicLabel Type='Page #'/><Text>.</Text></Paragraph></Header><Footer><Paragraph/></Footer></HeaderAndFooter><SmartType><Text>cached words</Text><Content><Paragraph><Text>more cached words</Text></Paragraph></Content></SmartType></FinalDraft>";
    let imported = read(source.as_bytes()).unwrap();
    assert_eq!(imported.script.elements.len(), 1);
    assert_eq!(
        printable(&imported.script.elements[0].text),
        "Only story words"
    );
    assert!(imported.warnings.iter().any(|w| w.contains("SmartType")));
    assert!(imported.warnings.iter().any(|w| w.contains("page-number")));
}

#[test]
fn edited_paragraph_type_cannot_hide_visible_cue_text_as_a_note() {
    let script = slugline_fountain::parse("[[private words]]\n");
    let xml = export(&script).xml.replacen(
        "<Paragraph Type=\"Action\"",
        "<Paragraph Type=\"Character\"",
        1,
    );
    assert!(read(xml.as_bytes()).is_err());
}

#[test]
fn removed_external_page_break_cannot_be_reintroduced_by_stale_metadata() {
    let script = slugline_fountain::parse("===\n\n!Visible words\n");
    let xml = export(&script)
        .xml
        .replacen("StartsNewPage=\"Yes\"", "StartsNewPage=\"No\"", 1);
    assert!(read(xml.as_bytes()).is_err());
}

#[test]
fn repeated_external_title_fields_keep_all_words_in_one_editable_native_field() {
    let source = "<FinalDraft><Content><Paragraph Type='Action'><Text>Story.</Text></Paragraph></Content><TitlePage><Content><Paragraph Alignment='Center'><Text>Title</Text></Paragraph><Paragraph Alignment='Left'><Text>Copyright words</Text></Paragraph><Paragraph Alignment='Left'><Text>Draft\ninformation</Text></Paragraph><Paragraph Alignment='Left'><Text>contact@example.invalid</Text></Paragraph></Content></TitlePage></FinalDraft>";
    let imported = read(source.as_bytes()).unwrap();
    let notes = "Copyright words\nDraft\ninformation\ncontact@example.invalid";
    assert_eq!(
        imported.script.title_page.get(&TitleField::Notes),
        Some(notes)
    );
    let reopened = slugline_fountain::parse(&native_source(&imported.script));
    assert_eq!(reopened.title_page.get(&TitleField::Notes), Some(notes));
}

#[test]
fn title_emphasis_does_not_pair_markers_across_hard_lines_during_export() {
    let original = slugline_fountain::parse("Title: **Across\n    lines**\n\nStory.\n");
    let exported = export(&original);
    let imported = read(exported.xml.as_bytes()).unwrap();
    let native_title_rows = |script: &Script| {
        script
            .title_page
            .get(&TitleField::Title)
            .unwrap()
            .split('\n')
            .map(emphasis::scan_row)
            .collect::<Vec<_>>()
    };
    assert_eq!(
        native_title_rows(&imported.script),
        native_title_rows(&original)
    );
}

#[test]
fn paired_scene_properties_tags_retain_authored_card_title_words() {
    let source = wrap("<Paragraph Type='Scene Heading'><SceneProperties Title='scene card words'></SceneProperties><Text>INT. ROOM - DAY</Text></Paragraph>");
    let imported = read(source.as_bytes()).unwrap();
    assert!(imported.script.elements.iter().any(|element| {
        element.kind == BlockKind::Note && printable(&element.text) == "scene card words"
    }));
    assert!(imported.script.elements.iter().any(|element| {
        element.kind == BlockKind::SceneHeading && element.text == "INT. ROOM - DAY"
    }));
}
