//! Hunspell dictionary discovery, loading, tokenisation and checking.
//!
//! Layering rule (§2.5): this crate depends on nothing else in the workspace.
//! It checks strings, not documents; the bridge decides which block and which
//! accepted screenplay entities belong to a request.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::ops::Range;
use std::path::{Path, PathBuf};

/// The conventional system Hunspell locations on Linux, in preference order.
///
/// Distributions disagree on which of these owns dictionaries. Discovery is
/// deliberately read-only and silently skips absent directories.
pub const SYSTEM_DICT_DIRS: &[&str] = &[
    "/usr/share/hunspell",
    "/usr/share/myspell",
    "/usr/share/myspell/dicts",
    "/usr/local/share/hunspell",
];

/// Kept for callers and tests from the Phase 0 placeholder.
pub const SYSTEM_DICT_DIR: &str = SYSTEM_DICT_DIRS[0];

/// One installed Hunspell `.aff` + `.dic` pair.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DictionaryInfo {
    pub language: String,
    pub aff_path: PathBuf,
    pub dic_path: PathBuf,
}

/// A word that the selected dictionary did not accept.
///
/// Ranges are UTF-8 byte offsets. `spell` is a pure Rust layer; the bridge is
/// the only layer allowed to translate them to UTF-16.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Misspelling {
    pub word: String,
    pub range_utf8: Range<usize>,
}

/// A loaded, immutable dictionary.
///
/// Spellbook documents dictionary construction as the expensive operation and
/// checking as safe to share. The bridge therefore keeps this behind an `Arc`
/// and sends immutable snapshots to worker threads.
pub struct Dictionary {
    language: String,
    inner: spellbook::Dictionary,
}

impl fmt::Debug for Dictionary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Dictionary")
            .field("language", &self.language)
            .finish_non_exhaustive()
    }
}

impl Dictionary {
    /// Loads one discovered dictionary.
    pub fn load(info: &DictionaryInfo) -> Result<Dictionary, LoadError> {
        let aff = std::fs::read_to_string(&info.aff_path)
            .map_err(|error| LoadError::read(&info.aff_path, error))?;
        let dic = std::fs::read_to_string(&info.dic_path)
            .map_err(|error| LoadError::read(&info.dic_path, error))?;
        let inner = spellbook::Dictionary::new(&aff, &dic).map_err(|error| LoadError {
            path: info.dic_path.clone(),
            message: error.to_string(),
        })?;
        Ok(Dictionary {
            language: info.language.clone(),
            inner,
        })
    }

    pub fn language(&self) -> &str {
        &self.language
    }

    pub fn check(&self, word: &str) -> bool {
        self.inner.check(word)
    }

    /// Suggestions in Spellbook's deterministic order, capped for a context
    /// menu that cannot use an unbounded list.
    pub fn suggest(&self, word: &str, limit: usize) -> Vec<String> {
        let mut suggestions = Vec::new();
        self.inner.suggest(word, &mut suggestions);
        suggestions.truncate(limit);
        suggestions
    }

    /// Checks prose and returns misspellings in source order.
    ///
    /// `accepted` is already normalised with [`normalise_word_set`]. Keeping it
    /// outside the dictionary means personal/project/entity overlays remain
    /// cheap immutable request data and never require cloning the multi-megabyte
    /// Hunspell structure.
    pub fn check_text(&self, text: &str, accepted: &BTreeSet<String>) -> Vec<Misspelling> {
        words(text)
            .filter(|(_, word)| {
                !accepted.contains(&normalise_word(word)) && !self.inner.check(word)
            })
            .map(|(range_utf8, word)| Misspelling {
                word: word.to_owned(),
                range_utf8,
            })
            .collect()
    }
}

/// A dictionary could not be read or parsed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadError {
    pub path: PathBuf,
    pub message: String,
}

impl LoadError {
    fn read(path: &Path, error: std::io::Error) -> LoadError {
        LoadError {
            path: path.to_path_buf(),
            message: error.to_string(),
        }
    }
}

impl fmt::Display for LoadError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.path.display(), self.message)
    }
}

impl std::error::Error for LoadError {}

/// Finds every `.aff` file with a sibling `.dic`, deduplicated by language.
///
/// Earlier directories win. This makes `/usr/share/hunspell` authoritative
/// when a compatibility symlink exposes the same locale through `myspell`.
pub fn discover() -> Vec<DictionaryInfo> {
    discover_in(SYSTEM_DICT_DIRS.iter().map(Path::new))
}

pub fn discover_in<'a>(directories: impl IntoIterator<Item = &'a Path>) -> Vec<DictionaryInfo> {
    let mut found = BTreeMap::<String, DictionaryInfo>::new();
    for directory in directories {
        let Ok(entries) = std::fs::read_dir(directory) else {
            continue;
        };
        let mut affs = entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("aff"))
            .collect::<Vec<_>>();
        affs.sort();
        for aff_path in affs {
            let Some(language) = aff_path
                .file_stem()
                .and_then(|value| value.to_str())
                .map(str::to_owned)
            else {
                continue;
            };
            let dic_path = aff_path.with_extension("dic");
            if !dic_path.is_file() {
                continue;
            }
            found.entry(language.clone()).or_insert(DictionaryInfo {
                language,
                aff_path,
                dic_path,
            });
        }
    }
    found.into_values().collect()
}

/// The default locale: US English when installed, then the first deterministic
/// discovery result.
pub fn default_language(dictionaries: &[DictionaryInfo]) -> Option<&str> {
    dictionaries
        .iter()
        .find(|dictionary| dictionary.language.eq_ignore_ascii_case("en_US"))
        .or_else(|| dictionaries.first())
        .map(|dictionary| dictionary.language.as_str())
}

/// Case-insensitive accepted-word matching, shared by personal, project,
/// session-ignore, and screenplay-entity sets.
pub fn normalise_word(word: &str) -> String {
    word.trim().to_lowercase()
}

pub fn normalise_word_set<'a>(words: impl IntoIterator<Item = &'a str>) -> BTreeSet<String> {
    words
        .into_iter()
        .map(normalise_word)
        .filter(|word| !word.is_empty())
        .collect()
}

/// Splits names and locations into the exact word units the checker sees.
pub fn words_in<'a>(text: &'a str) -> impl Iterator<Item = &'a str> + 'a {
    words(text).map(|(_, word)| word)
}

/// Reads a personal/project word list. Missing, unreadable and hand-damaged
/// files are empty/partial dictionaries, never a reason the script cannot open.
pub fn read_word_list(path: &Path) -> BTreeSet<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|contents| {
            contents
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty() && !line.starts_with('#'))
                .filter(|line| !line.chars().any(char::is_whitespace))
                .map(normalise_word)
                .collect()
        })
        .unwrap_or_default()
}

/// Stable, human-readable contents for a personal/project dictionary.
pub fn write_word_list(words: &BTreeSet<String>) -> String {
    let mut text = words.iter().cloned().collect::<Vec<_>>().join("\n");
    if !text.is_empty() {
        text.push('\n');
    }
    text
}

/// `script.fountain` → `script.fountain.dic`.
///
/// Keeping the complete script filename makes the association visible and
/// avoids colliding with a user's ordinary `script.dic`.
pub fn project_dictionary_path(script: &Path) -> PathBuf {
    let mut name = script
        .file_name()
        .map(|name| name.to_os_string())
        .unwrap_or_default();
    name.push(".dic");
    script.with_file_name(name)
}

fn words(text: &str) -> impl Iterator<Item = (Range<usize>, &str)> {
    let mut spans = Vec::new();
    let mut start = None;
    let chars = text.char_indices().collect::<Vec<_>>();
    for (index, &(byte, character)) in chars.iter().enumerate() {
        if is_word_character(character)
            || (is_joiner(character)
                && start.is_some()
                && chars
                    .get(index + 1)
                    .is_some_and(|(_, next)| is_word_character(*next)))
        {
            start.get_or_insert(byte);
        } else if let Some(from) = start.take() {
            spans.push((from..byte, &text[from..byte]));
        }
    }
    if let Some(from) = start {
        spans.push((from..text.len(), &text[from..]));
    }
    spans.into_iter()
}

fn is_word_character(character: char) -> bool {
    character.is_alphabetic() || is_combining_mark(character)
}

fn is_joiner(character: char) -> bool {
    matches!(character, '\'' | '\u{2019}' | '-')
}

// The combining-mark blocks used by Unicode scripts. `char::is_alphabetic`
// intentionally excludes these, but a decomposed "e + ◌́" is still one word.
fn is_combining_mark(character: char) -> bool {
    matches!(
        character as u32,
        0x0300..=0x036f
            | 0x1ab0..=0x1aff
            | 0x1dc0..=0x1dff
            | 0x20d0..=0x20ff
            | 0xfe20..=0xfe2f
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    const AFF: &str = "SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\n";
    const DIC: &str = "5\nhello\nworld\ncafé\nmother\nlaw\n";

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> TempDir {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "slugline-spell-{label}-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            TempDir(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn fixture(directory: &Path, language: &str) -> DictionaryInfo {
        let aff_path = directory.join(format!("{language}.aff"));
        let dic_path = directory.join(format!("{language}.dic"));
        fs::write(&aff_path, AFF).unwrap();
        fs::write(&dic_path, DIC).unwrap();
        DictionaryInfo {
            language: language.to_owned(),
            aff_path,
            dic_path,
        }
    }

    #[test]
    fn system_dictionary_dirs_are_absolute() {
        assert!(SYSTEM_DICT_DIRS
            .iter()
            .all(|directory| directory.starts_with('/')));
    }

    #[test]
    fn discovery_requires_a_pair_and_is_deterministic() {
        let first = TempDir::new("discover-first");
        let second = TempDir::new("discover-second");
        fixture(&first.0, "en_US");
        fixture(&first.0, "de_DE");
        fixture(&second.0, "en_US");
        fs::write(second.0.join("orphan.aff"), AFF).unwrap();

        let found = discover_in([first.0.as_path(), second.0.as_path()]);
        assert_eq!(
            found
                .iter()
                .map(|dictionary| dictionary.language.as_str())
                .collect::<Vec<_>>(),
            ["de_DE", "en_US"]
        );
        assert!(found[1].aff_path.starts_with(&first.0));
    }

    #[test]
    fn checking_reports_utf8_ranges_and_respects_accepted_words() {
        let directory = TempDir::new("check");
        let dictionary = Dictionary::load(&fixture(&directory.0, "en_US")).unwrap();
        let accepted = normalise_word_set(["Slugline"]);
        assert_eq!(
            dictionary.check_text("hello Slugline café wurld", &accepted),
            [Misspelling {
                word: "wurld".to_owned(),
                range_utf8: 21..26,
            }]
        );
    }

    #[test]
    fn tokenisation_keeps_internal_apostrophes_hyphens_and_combining_marks() {
        let words = words_in("mother-in-law isn't e\u{301}lan -- 'quoted'").collect::<Vec<_>>();
        assert_eq!(words, ["mother-in-law", "isn't", "e\u{301}lan", "quoted"]);
    }

    #[test]
    fn word_lists_are_total_sorted_and_human_readable() {
        let directory = TempDir::new("words");
        let path = directory.0.join("personal.dic");
        fs::write(&path, "# comment\nZulu\nbad phrase\n\nalpha\n").unwrap();
        let words = read_word_list(&path);
        assert_eq!(
            words.iter().map(String::as_str).collect::<Vec<_>>(),
            ["alpha", "zulu"]
        );
        assert_eq!(write_word_list(&words), "alpha\nzulu\n");
        assert!(read_word_list(&directory.0.join("missing")).is_empty());
    }

    #[test]
    fn project_dictionary_is_an_unambiguous_sidecar() {
        assert_eq!(
            project_dictionary_path(Path::new("/scripts/draft.fountain")),
            Path::new("/scripts/draft.fountain.dic")
        );
    }
}
