//! Spell checking.
//!
//! Layering rule (§2.5): depends on nothing else in the workspace. It checks
//! words, not documents; the caller decides which words to hand it.
//!
//! Phase 0 placeholder — checking lands in Phase 9.

/// Where system Hunspell dictionaries live on Linux.
pub const SYSTEM_DICT_DIR: &str = "/usr/share/hunspell";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_dict_dir_is_absolute() {
        assert!(SYSTEM_DICT_DIR.starts_with('/'));
    }
}
