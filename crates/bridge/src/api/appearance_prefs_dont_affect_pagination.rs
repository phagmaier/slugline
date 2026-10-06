use slugline_document::Document;
use slugline_layout::paginate;
use slugline_storage::prefs::Preferences;

use super::files::preference_page_config;

/// Phase 10's hard boundary: display preferences are not pagination inputs.
///
/// This is deliberately a dedicated test rather than an assertion hidden in a
/// settings round-trip. It compares the rendered pagination view byte-for-byte
/// after changing each appearance-only preference.
#[test]
fn appearance_preferences_leave_pagination_byte_identical() {
    let document = Document::parse(
        "Title: The Quiet Grid\nAuthor: Ada Writer\n\n\
         INT. EDITING ROOM - NIGHT #12#\n\n\
         A screenplay page stays put while its editor changes clothes.\n",
    );
    let baseline_preferences = Preferences::default();
    let baseline = paginate(&document, &preference_page_config(&baseline_preferences)).debug_dump();

    let variants = [
        Preferences {
            appearance: "light".to_owned(),
            ..baseline_preferences.clone()
        },
        Preferences {
            appearance: "dark".to_owned(),
            ..baseline_preferences.clone()
        },
        Preferences {
            editor_text_size: 24,
            ..baseline_preferences.clone()
        },
        Preferences {
            navigator_visible: false,
            ..baseline_preferences.clone()
        },
        Preferences {
            pdf_font_path: Some("/usr/share/fonts/example.ttf".into()),
            ..baseline_preferences.clone()
        },
        Preferences {
            distraction_free: true,
            ..baseline_preferences.clone()
        },
        Preferences {
            page_view: false,
            ..baseline_preferences.clone()
        },
    ];

    for preferences in variants {
        let actual = paginate(&document, &preference_page_config(&preferences)).debug_dump();
        assert_eq!(actual.as_bytes(), baseline.as_bytes());
    }
}

#[test]
fn heading_weight_is_an_output_preference_without_a_geometry_change() {
    let document = Document::parse("INT. *ROOM* - DAY\n\nAction.\n");
    let regular = Preferences::default();
    let bold = Preferences {
        bold_scene_headings: true,
        ..regular.clone()
    };
    let regular_config = preference_page_config(&regular);
    let bold_config = preference_page_config(&bold);
    assert!(!regular_config.bold_scene_headings);
    assert!(bold_config.bold_scene_headings);
    assert_eq!(
        paginate(&document, &regular_config).pages,
        paginate(&document, &bold_config).pages,
    );
}

/// Numbering page 1 is the same kind of thing as paper size and scene numbers:
/// a choice about what is printed, stored with the output defaults. It is not
/// in the appearance list above because it does change the pagination dump —
/// by exactly one line in the top margin, and by no row of script.
#[test]
fn first_page_numbering_is_an_output_preference_that_moves_no_row() {
    let document = Document::parse(
        "Title: The Quiet Grid\n\nINT. EDITING ROOM - NIGHT\n\nAction.\n\n===\n\nMore action.\n",
    );
    let unnumbered = Preferences::default();
    let numbered = Preferences {
        number_first_page: true,
        ..unnumbered.clone()
    };
    let unnumbered_config = preference_page_config(&unnumbered);
    let numbered_config = preference_page_config(&numbered);
    assert!(!unnumbered_config.number_first_page);
    assert!(numbered_config.number_first_page);

    let plain = paginate(&document, &unnumbered_config).debug_dump();
    let marked = paginate(&document, &numbered_config).debug_dump();
    let first_page_number = "   -3 -> ( 58, \"1.\")\n";
    assert_eq!(plain.matches(first_page_number).count(), 0);
    assert_eq!(marked.matches(first_page_number).count(), 1);
    assert_eq!(marked.replace(first_page_number, ""), plain);
    assert!(plain.contains("   -3 -> ( 58, \"2.\")\n"));
}
