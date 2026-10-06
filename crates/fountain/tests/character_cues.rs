use slugline_fountain::{infer_kind, parse, serialise, BlockKind, Context, Element, Output};

#[test]
fn punctuation_and_lowercase_extensions_are_unforced_cues() {
    for cue in [
        "COP #1",
        "MOM (on the phone)",
        "MR. & MRS. SMITH",
        "HANS/GRETEL",
        "JOHN, JR.",
        "JOSÉ (on the rádio)",
        "MOM (V.O.)(cont'd)",
        "MOM (on the phone (quietly))",
        "DR. WHO?",
    ] {
        for dual in [false, true] {
            let suffix = if dual { " ^" } else { "" };
            let source = format!("\u{feff}  {cue}{suffix}\r\nHello.\r\n\r\nAction.\r\n");
            let script = parse(&source);
            let actual: Vec<_> = script
                .elements
                .iter()
                .map(|element| (element.kind, element.text.as_str(), element.dual))
                .collect();
            assert_eq!(
                actual,
                [
                    (BlockKind::Character, cue, dual),
                    (BlockKind::Dialogue, "Hello.", false),
                    (BlockKind::Action, "Action.", false),
                ],
                "{source:?}"
            );
            assert!(!script.elements[0].forced);

            let mut cursor = '\u{feff}'.len_utf8();
            let title_range = script.title_page.provenance.clone().unwrap();
            assert_eq!(title_range.start, cursor);
            cursor = title_range.end;
            for element in &script.elements {
                let range = element.provenance.clone().unwrap();
                assert_eq!(range.start, cursor);
                assert!(range.start <= range.end);
                cursor = range.end;
            }
            assert_eq!(cursor, source.len());

            let mut elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
            let output = |elements: &[slugline_fountain::ElementRef<'_>]| {
                serialise(&Output {
                    title_page: &script.title_page,
                    elements,
                    source: Some(&source),
                    bom: script.bom,
                    line_ending: script.line_ending,
                })
            };
            assert_eq!(output(&elements), source);
            for element in &mut elements {
                element.provenance = None;
            }
            let canonical = output(&elements);
            let back = parse(&canonical);
            let reparsed: Vec<_> = back
                .elements
                .iter()
                .map(|element| (element.kind, element.text.as_str(), element.dual))
                .collect();
            assert_eq!(reparsed, actual, "{canonical:?}");
            assert!(!back.elements[0].forced);

            if !dual {
                assert_eq!(
                    infer_kind(
                        cue,
                        Context {
                            previous: None,
                            current: BlockKind::Action,
                            next: Some(BlockKind::Dialogue),
                        }
                    ),
                    Some(BlockKind::Character),
                    "{cue:?}"
                );
            }
        }
    }
}

#[test]
fn extensions_do_not_hide_lowercase_or_supply_the_character_name() {
    for line in [
        "Mom (on the phone)",
        "MOM (on the phone) Jr.",
        "MOM (on the phone",
        "MOM on the phone)",
        "(on the phone)",
        "123 (V.O.)",
        "日本 (V.O.)",
    ] {
        let source = format!("{line}\nHello.\n");
        let script = parse(&source);
        let actual: Vec<_> = script
            .elements
            .iter()
            .map(|element| (element.kind, element.text.as_str()))
            .collect();
        assert_eq!(actual, [(BlockKind::Action, source.trim_end())]);
    }
}

#[test]
fn cue_context_preserves_scene_and_transition_precedence() {
    let script = parse("INT. HOUSE - DAY\nAction.\n\nCUT TO:\n\nCUT TO:\nHello.\n");
    assert_eq!(
        script.elements.iter().map(|e| e.kind).collect::<Vec<_>>(),
        [
            BlockKind::SceneHeading,
            BlockKind::Action,
            BlockKind::Transition,
            BlockKind::Character,
            BlockKind::Dialogue,
        ]
    );
    for (index, element) in script.elements.iter().enumerate() {
        assert_eq!(
            infer_kind(
                &element.text,
                Context {
                    previous: index.checked_sub(1).map(|i| script.elements[i].kind),
                    current: element.kind,
                    next: script.elements.get(index + 1).map(|e| e.kind),
                }
            ),
            Some(element.kind)
        );
    }
}

#[test]
fn cue_shaped_action_stays_action_after_canonicalisation() {
    for cue in ["COP #1", "MOM (on the phone)", "JOHN, JR."] {
        let source = format!("!{cue}\nHello.\n");
        let script = parse(&source);
        let mut elements: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
        for element in &mut elements {
            element.provenance = None;
            element.forced = false;
        }
        let written = serialise(&Output {
            title_page: &script.title_page,
            elements: &elements,
            source: None,
            bom: false,
            line_ending: script.line_ending,
        });
        let back = parse(&written);
        assert_eq!(
            back.elements
                .iter()
                .map(|element| (element.kind, element.text.as_str()))
                .collect::<Vec<_>>(),
            [(BlockKind::Action, format!("{cue}\nHello.").as_str())]
        );
        assert_eq!(
            parse(&format!("{cue}\n")).elements[0].kind,
            BlockKind::Action
        );
        assert_eq!(
            parse(&format!("Action.\n{cue}\nHello.\n")).elements[0].text,
            format!("Action.\n{cue}\nHello.")
        );
    }
}
