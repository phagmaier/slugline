//! A temporary directory, for this crate's tests.
//!
//! Twenty-five lines instead of a `tempfile` dependency. §1.2 asks for a written
//! justification for every crate, and "we needed `mkdir` and `rm -r`" is not one
//! — `DEPENDENCIES.md` already turns down `cargo-deny` on the same grounds.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    /// A fresh empty directory named after `label`, removed when this is
    /// dropped.
    pub fn new(label: &str) -> TempDir {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("slugline-{label}-{}-{unique}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("a temporary directory");
        TempDir { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// The names in the directory, sorted. Tests assert on this to prove that a
    /// failed write left nothing behind.
    pub fn entries(&self) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(&self.path)
            .into_iter()
            .flatten()
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        // A test that made a directory unwritable has to be able to fail without
        // taking the whole run down with it, so this is best effort.
        let _ = fs::remove_dir_all(&self.path);
    }
}
