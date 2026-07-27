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
    ];

    for preferences in variants {
        let actual = paginate(&document, &preference_page_config(&preferences)).debug_dump();
        assert_eq!(actual.as_bytes(), baseline.as_bytes());
    }
}
