//! Preferences, as far as Phase 4 needs them.
//!
//! §Phase 4 asks for three things to be configurable — the autosave debounce,
//! the autosave interval, and where backups go — and §6 has `prefs_get` and
//! `prefs_set` for them. This is that file and no more: a preference with no
//! consumer is scaffolding, which §1.4 rules out.
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
    /// Where rolling backups go. `None` means the default under
    /// `$XDG_STATE_HOME`.
    pub backup_dir: Option<PathBuf>,
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
            backup_dir: None,
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
            .unwrap_or_default()
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;

    #[test]
    fn the_defaults_are_the_ones_the_spec_names() {
        let prefs = Preferences::default();
        assert_eq!(prefs.autosave_idle_ms, 2_000);
        assert_eq!(prefs.autosave_interval_ms, 30_000);
        assert_eq!(prefs.backup_keep_versions, 10);
        assert_eq!(prefs.backup_keep_days, 7);
    }

    #[test]
    fn preferences_survive_a_round_trip() {
        let dir = TempDir::new("prefs-round-trip");
        let path = dir.path().join("preferences.json");
        let prefs = Preferences {
            autosave_idle_ms: 500,
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
    }
}
