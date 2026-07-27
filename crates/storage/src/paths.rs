//! Where everything lives on disk.
//!
//! ADR 0006 settled the XDG directories: `$XDG_CONFIG_HOME/slugline`,
//! `$XDG_DATA_HOME/slugline`, `$XDG_STATE_HOME/slugline`. This module is the one
//! place that turns those into file names, so that "where is the journal?" has
//! exactly one answer and a test can point the whole crate at a temporary
//! directory by constructing one of these instead of setting environment
//! variables.
//!
//! The three roots are kept apart because they mean different things to a user
//! backing up a home directory: **config** is what they chose, **data** is what
//! they own, **state** is what the application can rebuild. The library index
//! sits in data and the journal in state, which is why §Phase 4 can say the
//! index "is a *cache*, and the app must work correctly if it is deleted".

use std::path::{Path, PathBuf};

use directories::ProjectDirs;

/// The three XDG roots, and the files under them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    config: PathBuf,
    data: PathBuf,
    state: PathBuf,
}

impl Paths {
    /// The real directories for this user, or `None` when there is no home
    /// directory to derive them from.
    ///
    /// Nothing is created here. A directory is made when something is first
    /// written into it, so that a session that saves nothing leaves no trace.
    pub fn discover() -> Option<Paths> {
        let dirs = ProjectDirs::from("com", "phagmaier", "slugline")?;
        Some(Paths {
            config: dirs.config_dir().to_path_buf(),
            data: dirs.data_dir().to_path_buf(),
            // `directories` returns `None` for the state directory on platforms
            // that have no XDG equivalent. Linux is the only platform (§1.2), so
            // this is `Some`; falling back to data keeps the type honest anyway.
            state: dirs
                .state_dir()
                .unwrap_or_else(|| dirs.data_dir())
                .to_path_buf(),
        })
    }

    /// Explicit roots. The bridge's `init(config_dir, state_dir)` takes this
    /// path, and so does every test.
    pub fn at(
        config: impl Into<PathBuf>,
        data: impl Into<PathBuf>,
        state: impl Into<PathBuf>,
    ) -> Paths {
        Paths {
            config: config.into(),
            data: data.into(),
            state: state.into(),
        }
    }

    /// All three roots under one directory. What a test wants, and what an
    /// installation with `XDG_*_HOME` unset ends up close to.
    pub fn under(root: impl AsRef<Path>) -> Paths {
        let root = root.as_ref();
        Paths::at(root.join("config"), root.join("data"), root.join("state"))
    }

    pub fn config_dir(&self) -> &Path {
        &self.config
    }

    pub fn data_dir(&self) -> &Path {
        &self.data
    }

    pub fn state_dir(&self) -> &Path {
        &self.state
    }

    /// `$XDG_STATE_HOME/slugline/journal/` — §Phase 4 names this exactly.
    pub fn journal_dir(&self) -> PathBuf {
        self.state.join("journal")
    }

    /// `$XDG_STATE_HOME/slugline/backups/` — the default; a preference can move
    /// it (§Phase 4, "a configurable location").
    pub fn backup_dir(&self) -> PathBuf {
        self.state.join("backups")
    }

    /// The library index. A cache: deleting it must cost nothing but the recent
    /// list.
    pub fn library_index(&self) -> PathBuf {
        self.data.join("library.json")
    }

    pub fn preferences(&self) -> PathBuf {
        self.config.join("prefs.json")
    }

    /// Phase 4 used this longer name before Phase 10 fixed the public path in
    /// the specification. It is read only as a one-time compatibility source.
    pub fn legacy_preferences(&self) -> PathBuf {
        self.config.join("preferences.json")
    }

    /// `$XDG_CONFIG_HOME/slugline/personal.dic` — §Phase 9's words accepted in
    /// every project.
    pub fn personal_dictionary(&self) -> PathBuf {
        self.config.join("personal.dic")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_file_sits_under_the_root_it_belongs_to() {
        let paths = Paths::under("/tmp/slugline-test");
        assert!(paths.journal_dir().starts_with("/tmp/slugline-test/state"));
        assert!(paths.backup_dir().starts_with("/tmp/slugline-test/state"));
        assert!(paths.library_index().starts_with("/tmp/slugline-test/data"));
        assert!(paths.preferences().starts_with("/tmp/slugline-test/config"));
        assert!(paths
            .personal_dictionary()
            .starts_with("/tmp/slugline-test/config"));
    }

    #[test]
    fn discovery_does_not_create_anything() {
        // Whatever the environment says, asking must not have side effects: a
        // read of the paths happens at startup, before the user has chosen to
        // save anything.
        if let Some(paths) = Paths::discover() {
            assert!(paths.config_dir().is_absolute());
            assert!(paths.state_dir().is_absolute());
        }
    }
}
