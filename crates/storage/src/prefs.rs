//! Application preferences.
//!
//! §Phase 4 asks for autosave and backup controls, §7 adds autocomplete, and
//! §Phase 8 persists the navigator's expanded state, and §Phase 9 adds spell
//! checking enablement and language. Phase 10 adds appearance, editor text size,
//! output defaults, the PDF face and distraction-free mode. §6's `prefs_get`
//! and `prefs_set` carry the general fields while the spell surface updates its
//! two fields.
//!
//! Reading is total. A preferences file that has been hand-edited into nonsense
//! yields the defaults rather than an error, because the alternative is an
//! application that will not start until the user finds and deletes a file
//! nobody told them about. Fields missing from the file take their default
//! individually, so a file written by an older version keeps working and a file
//! written by a newer one loses only what this version cannot use.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::atomic::{save_atomically, SaveError};
use crate::backup::Retention;

/// §Phase 4's defaults, named.
const AUTOSAVE_IDLE_MS: u64 = 2_000;
const AUTOSAVE_INTERVAL_MS: u64 = 30_000;
const EDITOR_TEXT_SIZE: u16 = 15;

pub const APPEARANCE_SYSTEM: &str = "system";
pub const APPEARANCE_LIGHT: &str = "light";
pub const APPEARANCE_DARK: &str = "dark";
pub const PAPER_US_LETTER: &str = "us_letter";
pub const PAPER_A4: &str = "a4";
pub const SCENE_NUMBERS_OFF: &str = "off";
pub const SCENE_NUMBERS_LEFT: &str = "left";
pub const SCENE_NUMBERS_RIGHT: &str = "right";
pub const SCENE_NUMBERS_BOTH: &str = "both";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Preferences {
    /// Autosave this long after the last keystroke. §Phase 4: "debounced after
    /// edit inactivity (default 2 s)".
    pub autosave_idle_ms: u64,
    /// And at least this often while typing continues. §Phase 4: "a hard
    /// interval (default 30 s)".
    pub autosave_interval_ms: u64,
    /// Zero turns autosave off entirely. Someone will want this, and the
    /// alternative to supporting it is their finding out that they cannot have
    /// it after losing a take.
    pub autosave_enabled: bool,
    /// §7: the completion popup can be disabled without disabling entity data.
    pub autocomplete_enabled: bool,
    /// §Phase 8: whether the navigator sidebar is expanded. The collapsed rail
    /// remains available, so this never makes the feature unreachable.
    pub navigator_visible: bool,
    /// §Phase 9: the checker can be disabled without unloading the script.
    pub spell_enabled: bool,
    /// An installed Hunspell locale such as `en_US`. `None` asks discovery for
    /// US English, then its first deterministic result.
    pub spell_language: Option<String>,
    /// `system`, `light`, or `dark`. Kept as readable text so the on-disk file
    /// remains hand-editable.
    pub appearance: String,
    /// Flutter logical pixels. This changes only the fluid editor.
    pub editor_text_size: u16,
    /// `us_letter` or `a4`.
    pub default_paper: String,
    /// `off`, `left`, `right`, or `both`.
    pub scene_numbers: String,
    /// Bold scene-heading content in the editor, preview and PDF.
    pub bold_scene_headings: bool,
    /// Print `1.` on the first page of the script. Off by default: the
    /// convention is that page 1 is counted and not marked.
    pub number_first_page: bool,
    /// A user-selected TrueType face. `None` means the vendored Courier Prime
    /// family and is the fidelity-safe default.
    pub pdf_font_path: Option<PathBuf>,
    /// Hides application chrome and asks the Linux window to go full-screen.
    pub distraction_free: bool,
    /// Whether the editor draws discrete paper pages rather than one continuous
    /// column. Display only: the editor stays fluid and unpaginated either way
    /// (ADR 0018), and the page boundaries it draws come from the paginator's
    /// snapshot, never from a second layout pass in the editor.
    ///
    /// On by default. A screenplay is written to a page count, so where the
    /// pages fall is not decoration — it is the thing being written to. The mode
    /// degrades to continuous on its own until the first pagination arrives, so
    /// defaulting to it costs no wait.
    pub page_view: bool,
    /// Where rolling backups go. `None` means the default under
    /// `$XDG_STATE_HOME`.
    pub backup_dir: Option<PathBuf>,
    /// Managed library. None selects the lazy platform default.
    pub library_dir: Option<PathBuf>,
    pub backup_keep_versions: u32,
    pub backup_keep_days: u32,
}

impl Default for Preferences {
    fn default() -> Preferences {
        let retention = Retention::default();
        Preferences {
            autosave_idle_ms: AUTOSAVE_IDLE_MS,
            autosave_interval_ms: AUTOSAVE_INTERVAL_MS,
            autosave_enabled: true,
            autocomplete_enabled: true,
            navigator_visible: true,
            spell_enabled: true,
            spell_language: None,
            appearance: APPEARANCE_SYSTEM.to_owned(),
            editor_text_size: EDITOR_TEXT_SIZE,
            default_paper: PAPER_US_LETTER.to_owned(),
            scene_numbers: SCENE_NUMBERS_OFF.to_owned(),
            bold_scene_headings: false,
            number_first_page: false,
            pdf_font_path: None,
            distraction_free: false,
            page_view: true,
            backup_dir: None,
            library_dir: None,
            backup_keep_versions: retention.keep_versions,
            backup_keep_days: retention.keep_days,
        }
    }
}

impl Preferences {
    /// Reads the file, or the defaults if it is absent or unreadable.
    pub fn load(path: &Path) -> Preferences {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .map(Preferences::sanitised)
            .unwrap_or_default()
    }

    /// Bounds hand-edited values before a timer or a painter sees them.
    pub fn sanitised(mut self) -> Preferences {
        if !matches!(
            self.appearance.as_str(),
            APPEARANCE_SYSTEM | APPEARANCE_LIGHT | APPEARANCE_DARK
        ) {
            self.appearance = APPEARANCE_SYSTEM.to_owned();
        }
        self.editor_text_size = self.editor_text_size.clamp(12, 24);
        if !matches!(self.default_paper.as_str(), PAPER_US_LETTER | PAPER_A4) {
            self.default_paper = PAPER_US_LETTER.to_owned();
        }
        if !matches!(
            self.scene_numbers.as_str(),
            SCENE_NUMBERS_OFF | SCENE_NUMBERS_LEFT | SCENE_NUMBERS_RIGHT | SCENE_NUMBERS_BOTH
        ) {
            self.scene_numbers = SCENE_NUMBERS_OFF.to_owned();
        }
        self.autosave_idle_ms = self.autosave_idle_ms.clamp(250, 60_000);
        self.autosave_interval_ms = self.autosave_interval_ms.clamp(1_000, 3_600_000);
        self.backup_keep_versions = self.backup_keep_versions.clamp(1, 100);
        self.backup_keep_days = self.backup_keep_days.clamp(1, 3_650);
        self.backup_dir = nonempty_path(self.backup_dir);
        self.library_dir = nonempty_path(self.library_dir);
        self.pdf_font_path = nonempty_path(self.pdf_font_path);
        self
    }

    /// Writes the file, atomically. Preferences are not user text, but a
    /// truncated one would still be a bad morning.
    pub fn save(&self, path: &Path) -> Result<(), SaveError> {
        if let Some(parent) = path.parent() {
            if let Err(error) = std::fs::create_dir_all(parent) {
                return Err(SaveError::Io {
                    path: parent.to_path_buf(),
                    message: error.to_string(),
                });
            }
        }
        let text = serde_json::to_string_pretty(self)
            .map(|mut text| {
                text.push('\n');
                text
            })
            .map_err(|error| SaveError::Io {
                path: path.to_path_buf(),
                message: error.to_string(),
            })?;
        save_atomically(path, &text)
    }

    pub fn retention(&self) -> Retention {
        Retention {
            keep_versions: self.backup_keep_versions,
            keep_days: self.backup_keep_days,
        }
    }
}

fn nonempty_path(path: Option<PathBuf>) -> Option<PathBuf> {
    path.filter(|path| !path.as_os_str().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;

    #[test]
    fn the_defaults_are_the_ones_the_spec_names() {
        let prefs = Preferences::default();
        assert_eq!(prefs.autosave_idle_ms, 2_000);
        assert_eq!(prefs.autosave_interval_ms, 30_000);
        assert!(prefs.navigator_visible);
        assert!(prefs.spell_enabled);
        assert!(prefs.spell_language.is_none());
        assert_eq!(prefs.appearance, "system");
        assert_eq!(prefs.editor_text_size, 15);
        assert_eq!(prefs.default_paper, "us_letter");
        assert_eq!(prefs.scene_numbers, "off");
        assert!(!prefs.bold_scene_headings);
        assert!(!prefs.number_first_page);
        assert!(prefs.pdf_font_path.is_none());
        assert!(!prefs.distraction_free);
        assert!(prefs.page_view, "page view is the default");
        assert_eq!(prefs.backup_keep_versions, 10);
        assert_eq!(prefs.backup_keep_days, 7);
    }

    #[test]
    fn preferences_survive_a_round_trip() {
        let dir = TempDir::new("prefs-round-trip");
        let path = dir.path().join("preferences.json");
        let prefs = Preferences {
            autosave_idle_ms: 500,
            navigator_visible: false,
            appearance: APPEARANCE_LIGHT.to_owned(),
            editor_text_size: 18,
            default_paper: PAPER_A4.to_owned(),
            scene_numbers: SCENE_NUMBERS_BOTH.to_owned(),
            bold_scene_headings: true,
            number_first_page: true,
            page_view: false,
            pdf_font_path: Some(PathBuf::from("/usr/share/fonts/mono.ttf")),
            backup_dir: Some(PathBuf::from("/mnt/usb/backups")),
            ..Preferences::default()
        };
        prefs.save(&path).unwrap();
        assert_eq!(Preferences::load(&path), prefs);
    }

    #[test]
    fn a_missing_file_is_the_defaults() {
        let dir = TempDir::new("prefs-missing");
        assert_eq!(
            Preferences::load(&dir.path().join("nothing.json")),
            Preferences::default()
        );
    }

    #[test]
    fn a_file_full_of_nonsense_is_the_defaults_rather_than_a_failure_to_start() {
        let dir = TempDir::new("prefs-nonsense");
        let path = dir.path().join("preferences.json");
        std::fs::write(&path, "{{{ not json").unwrap();
        assert_eq!(Preferences::load(&path), Preferences::default());
    }

    #[test]
    fn a_file_from_another_version_keeps_the_fields_it_shares() {
        let dir = TempDir::new("prefs-partial");
        let path = dir.path().join("preferences.json");
        std::fs::write(
            &path,
            r#"{"autosave_idle_ms":750,"something_from_the_future":true}"#,
        )
        .unwrap();
        let prefs = Preferences::load(&path);
        assert_eq!(prefs.autosave_idle_ms, 750);
        assert_eq!(prefs.autosave_interval_ms, 30_000, "the rest are defaults");
        assert!(
            !prefs.bold_scene_headings,
            "older files keep regular headings"
        );
        assert!(
            !prefs.number_first_page,
            "older files take the unnumbered first page"
        );
    }

    #[test]
    fn unsafe_hand_edited_values_are_bounded_individually() {
        let dir = TempDir::new("prefs-bounds");
        let path = dir.path().join("prefs.json");
        std::fs::write(
            &path,
            r#"{
                "appearance":"sepia",
                "editor_text_size":600,
                "default_paper":"legal",
                "scene_numbers":"sometimes",
                "autosave_idle_ms":0,
                "autosave_interval_ms":0,
                "backup_keep_versions":0,
                "backup_keep_days":99999
            }"#,
        )
        .unwrap();
        let prefs = Preferences::load(&path);
        assert_eq!(prefs.appearance, APPEARANCE_SYSTEM);
        assert_eq!(prefs.editor_text_size, 24);
        assert_eq!(prefs.default_paper, PAPER_US_LETTER);
        assert_eq!(prefs.scene_numbers, SCENE_NUMBERS_OFF);
        assert_eq!(prefs.autosave_idle_ms, 250);
        assert_eq!(prefs.autosave_interval_ms, 1_000);
        assert_eq!(prefs.backup_keep_versions, 1);
        assert_eq!(prefs.backup_keep_days, 3_650);
    }
}
