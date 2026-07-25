//! File I/O: atomic writes, autosave, crash journal, backups, library index.
//!
//! Layering rule (§2.5): may depend on `document` only.
//!
//! Phase 0 placeholder — atomic save and the journal land in Phase 4.

/// Suffix used for the temporary file in the write-then-rename dance.
pub const TEMP_SUFFIX: &str = ".tmp";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temp_suffix_is_hidden_from_the_library_scan() {
        assert!(TEMP_SUFFIX.starts_with('.'));
    }
}
