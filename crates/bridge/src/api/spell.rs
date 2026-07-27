//! Phase 9 spell-checking bridge.
//!
//! The actor owns configuration, overlays and caches, but never runs Hunspell
//! or touches a dictionary file. Each request takes an immutable block snapshot
//! and an `Arc` to the selected dictionary, lets the actor go, then validates
//! the exact cache key before committing the answer.

use std::collections::BTreeSet;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::{Arc, PoisonError};

use flutter_rust_bridge::frb;
use slugline_document::{BlockId, EntityKind};
use slugline_spell::{self as core, Dictionary, DictionaryInfo, Misspelling as CoreMisspelling};
use slugline_storage::{atomic, Paths, Preferences};

use crate::actor::actor;
use crate::api::doc::DocumentHandle;
use crate::offsets;
use crate::state::{AppState, CachedSpellBlock, IgnoredOccurrence, SpellingState};

const SUGGESTION_LIMIT: usize = 8;

#[cfg(test)]
fn spell_test_lock() -> std::sync::MutexGuard<'static, ()> {
    use std::sync::{Mutex, OnceLock};

    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
}

/// One installed language for the selector.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpellLanguage {
    pub code: String,
    pub label: String,
}

/// The complete UI state of spell checking.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpellStatus {
    pub enabled: bool,
    pub language: Option<String>,
    pub languages: Vec<SpellLanguage>,
    /// Always useful: selected language, disabled state, or why none can run.
    pub message: String,
}

/// One underline in a block, in the bridge's UTF-16 coordinates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Misspelling {
    pub block: u64,
    pub start_utf16: u32,
    pub end_utf16: u32,
    pub word: String,
}

/// One asynchronous block answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpellCheckResult {
    pub block: u64,
    /// False when the block changed while its snapshot was being checked, or
    /// the handle/block no longer exists. Dart discards the whole answer.
    pub current: bool,
    /// True when the expensive checker did not run because this exact block
    /// hash/configuration was already cached.
    pub cached: bool,
    pub misspellings: Vec<Misspelling>,
}

/// Result of an explicit dictionary/ignore command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SpellActionResult {
    Applied,
    NoSuchDocument,
    NoScriptPath,
    Failed { message: String },
}

/// Discovers and loads the startup selection. Called from `init` on its async
/// worker, before the state is handed to the actor.
pub(crate) fn initialise(paths: &Paths, preferences: &Preferences) -> SpellingState {
    initialise_from(
        core::discover(),
        paths.personal_dictionary(),
        preferences.spell_enabled,
        preferences.spell_language.as_deref(),
    )
}

fn initialise_from(
    dictionaries: Vec<DictionaryInfo>,
    personal_path: PathBuf,
    enabled: bool,
    requested: Option<&str>,
) -> SpellingState {
    let personal_words = core::read_word_list(&personal_path);
    let selected = requested
        .and_then(|wanted| {
            dictionaries
                .iter()
                .find(|dictionary| dictionary.language == wanted)
        })
        .or_else(|| {
            core::default_language(&dictionaries).and_then(|wanted| {
                dictionaries
                    .iter()
                    .find(|dictionary| dictionary.language == wanted)
            })
        });

    let (language, dictionary, message) = match selected {
        Some(info) => match Dictionary::load(info) {
            Ok(dictionary) => (
                Some(info.language.clone()),
                Some(Arc::new(dictionary)),
                format!("Checking with {}.", display_language(&info.language)),
            ),
            Err(error) => (
                Some(info.language.clone()),
                None,
                format!(
                    "The {} dictionary could not be loaded: {error}",
                    display_language(&info.language)
                ),
            ),
        },
        None => (
            None,
            None,
            format!(
                "No Hunspell dictionaries were found in {}.",
                core::SYSTEM_DICT_DIRS.join(", ")
            ),
        ),
    };

    SpellingState {
        dictionaries,
        dictionary,
        enabled,
        language,
        personal_words,
        personal_path: Some(personal_path),
        personal_lock: Arc::default(),
        revision: 1,
        message,
    }
}

#[frb(sync)]
pub fn spell_status() -> SpellStatus {
    actor().run(|state| status_view(state.spelling()))
}

/// Enables/disables checking or selects an installed language.
///
/// Dictionary parsing happens here, off the actor. A failed selection leaves
/// the previously working dictionary selected and reports failure.
pub async fn spell_configure(enabled: bool, language: Option<String>) -> SpellActionResult {
    let selection = actor().run({
        let language = language.clone();
        move |state| {
            let spelling = state.spelling();
            let wanted = language
                .as_deref()
                .or(spelling.language.as_deref())
                .or_else(|| core::default_language(&spelling.dictionaries));
            wanted.and_then(|wanted| {
                spelling
                    .dictionaries
                    .iter()
                    .find(|dictionary| dictionary.language == wanted)
                    .cloned()
            })
        }
    });

    let loaded = match selection {
        Some(info) => match Dictionary::load(&info) {
            Ok(dictionary) => Some((info.language, Arc::new(dictionary))),
            Err(error) => {
                return SpellActionResult::Failed {
                    message: error.to_string(),
                };
            }
        },
        None if enabled => {
            return SpellActionResult::Failed {
                message: format!(
                    "No Hunspell dictionaries were found in {}.",
                    core::SYSTEM_DICT_DIRS.join(", ")
                ),
            };
        }
        None => None,
    };

    actor().run(move |state| {
        let selected_language = loaded
            .as_ref()
            .map(|(language, _)| language.clone())
            .or_else(|| state.spelling().language.clone());
        {
            let spelling = state.spelling_mut();
            spelling.enabled = enabled;
            if let Some((language, dictionary)) = loaded {
                spelling.replace_dictionary(
                    Some(language.clone()),
                    Some(dictionary),
                    format!("Checking with {}.", display_language(&language)),
                );
            } else {
                spelling.revision = spelling.revision.wrapping_add(1);
            }
        }
        if let Some(storage) = state.storage_mut() {
            storage.prefs.spell_enabled = enabled;
            storage.prefs.spell_language = selected_language;
            let path = storage.paths.preferences();
            if let Err(error) = storage.prefs.save(&path) {
                return SpellActionResult::Failed {
                    message: error.to_string(),
                };
            }
        }
        SpellActionResult::Applied
    })
}

/// §6's async `spell_check_block`.
pub async fn spell_check_block(handle: DocumentHandle, block: u64) -> SpellCheckResult {
    ensure_project_loaded(handle).await;

    let Some(plan) = actor().run(move |state| plan(state, handle.id, BlockId(block))) else {
        return stale(block);
    };
    if !plan.enabled {
        return SpellCheckResult {
            block,
            current: true,
            cached: true,
            misspellings: Vec::new(),
        };
    }
    let Some(dictionary) = plan.dictionary else {
        return SpellCheckResult {
            block,
            current: true,
            cached: true,
            misspellings: Vec::new(),
        };
    };

    let (misspellings, cached) = match plan.cached {
        Some(misspellings) => (misspellings, true),
        None => (dictionary.check_text(&plan.text, &plan.accepted), false),
    };

    let current = actor().run({
        let misspellings = misspellings.clone();
        let text = plan.text.clone();
        move |state| {
            if cache_key(state, handle.id, BlockId(block)) != Some(plan.key) {
                return false;
            }
            let Some(session) = state.session_mut(handle.id) else {
                return false;
            };
            session.spelling_mut().cache.insert(
                BlockId(block),
                CachedSpellBlock {
                    key: plan.key,
                    misspellings,
                },
            );
            session
                .document()
                .block(BlockId(block))
                .is_some_and(|candidate| candidate.text() == text)
        }
    });
    if !current {
        return stale(block);
    }

    let ignored = actor().run(move |state| {
        state
            .session(handle.id)
            .map(|session| session.spelling().ignored_once.clone())
            .unwrap_or_default()
    });
    SpellCheckResult {
        block,
        current: true,
        cached,
        misspellings: misspelling_views(
            block,
            &plan.text,
            plan.text_fingerprint,
            misspellings,
            &ignored,
        ),
    }
}

pub async fn spell_suggest(word: String) -> Vec<String> {
    let dictionary = actor().run(|state| {
        state
            .spelling()
            .enabled
            .then(|| state.spelling().dictionary.clone())
            .flatten()
    });
    dictionary
        .map(|dictionary| dictionary.suggest(&word, SUGGESTION_LIMIT))
        .unwrap_or_default()
}

/// Ignores only the exact occurrence under the context menu.
#[frb(sync)]
pub fn spell_ignore_once(
    handle: DocumentHandle,
    block: u64,
    start_utf16: u32,
    end_utf16: u32,
    word: String,
) -> SpellActionResult {
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return SpellActionResult::NoSuchDocument;
        };
        let Some(candidate) = session.document().block(BlockId(block)) else {
            return SpellActionResult::NoSuchDocument;
        };
        let Some(range) = offsets::utf16_range_to_utf8(candidate.text(), start_utf16..end_utf16)
        else {
            return SpellActionResult::Failed {
                message: "the misspelling range is no longer valid".to_owned(),
            };
        };
        if candidate.text().get(range.clone()) != Some(word.as_str()) {
            return SpellActionResult::Failed {
                message: "the word changed before it could be ignored".to_owned(),
            };
        }
        let text_fingerprint = fingerprint(candidate.text());
        session
            .spelling_mut()
            .ignored_once
            .insert(IgnoredOccurrence {
                block: BlockId(block),
                text_fingerprint,
                start_utf8: range.start,
                end_utf8: range.end,
                word,
            });
        SpellActionResult::Applied
    })
}

#[frb(sync)]
pub fn spell_ignore_all(handle: DocumentHandle, word: String) -> SpellActionResult {
    let word = core::normalise_word(&word);
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return SpellActionResult::NoSuchDocument;
        };
        if !word.is_empty() && session.spelling_mut().ignored_all.insert(word) {
            session.spelling_mut().bump();
        }
        SpellActionResult::Applied
    })
}

pub async fn spell_add_personal(word: String) -> SpellActionResult {
    let word = core::normalise_word(&word);
    if word.is_empty() {
        return SpellActionResult::Failed {
            message: "a dictionary word cannot be empty".to_owned(),
        };
    }
    let Some((lock, path)) = actor().run(|state| {
        let spelling = state.spelling();
        spelling
            .personal_path
            .clone()
            .map(|path| (Arc::clone(&spelling.personal_lock), path))
    }) else {
        return SpellActionResult::Failed {
            message: "the configuration directory is unavailable".to_owned(),
        };
    };
    let _writing = lock.lock().unwrap_or_else(PoisonError::into_inner);
    let mut words = actor().run(|state| state.spelling().personal_words.clone());
    words.insert(word);
    if let Err(error) = write_words(&path, &words) {
        return SpellActionResult::Failed {
            message: error.to_string(),
        };
    }
    actor().run(move |state| {
        state.spelling_mut().personal_words = words;
        state.spelling_mut().revision = state.spelling().revision.wrapping_add(1);
    });
    SpellActionResult::Applied
}

pub async fn spell_add_project(handle: DocumentHandle, word: String) -> SpellActionResult {
    ensure_project_loaded(handle).await;
    let word = core::normalise_word(&word);
    if word.is_empty() {
        return SpellActionResult::Failed {
            message: "a dictionary word cannot be empty".to_owned(),
        };
    }
    let Some((lock, path)) = actor().run(move |state| {
        let session = state.session(handle.id)?;
        let script = session.path()?;
        Some((
            Arc::clone(&session.spelling().project_lock),
            core::project_dictionary_path(script),
        ))
    }) else {
        return if actor().run(move |state| state.session(handle.id).is_some()) {
            SpellActionResult::NoScriptPath
        } else {
            SpellActionResult::NoSuchDocument
        };
    };
    let _writing = lock.lock().unwrap_or_else(PoisonError::into_inner);
    let mut words = actor().run(move |state| {
        state
            .session(handle.id)
            .map(|session| session.spelling().project_words.clone())
            .unwrap_or_default()
    });
    words.insert(word);
    if let Err(error) = write_words(&path, &words) {
        return SpellActionResult::Failed {
            message: error.to_string(),
        };
    }
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return SpellActionResult::NoSuchDocument;
        };
        if session.path().map(core::project_dictionary_path).as_ref() != Some(&path) {
            return SpellActionResult::NoScriptPath;
        }
        session.spelling_mut().project_words = words;
        session.spelling_mut().bump();
        SpellActionResult::Applied
    })
}

async fn ensure_project_loaded(handle: DocumentHandle) {
    let pending = actor().run(move |state| {
        let session = state.session(handle.id)?;
        let script = session.path()?.to_path_buf();
        let sidecar = core::project_dictionary_path(&script);
        (session.spelling().project_loaded_for.as_ref() != Some(&sidecar)).then_some(sidecar)
    });
    let Some(path) = pending else { return };
    let words = core::read_word_list(&path);
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return;
        };
        if session.path().map(core::project_dictionary_path).as_ref() == Some(&path) {
            session.spelling_mut().project_words = words;
            session.spelling_mut().project_loaded_for = Some(path);
            session.spelling_mut().bump();
        }
    });
}

struct CheckPlan {
    enabled: bool,
    dictionary: Option<Arc<Dictionary>>,
    text: String,
    text_fingerprint: u64,
    accepted: BTreeSet<String>,
    key: u64,
    cached: Option<Vec<CoreMisspelling>>,
}

fn plan(state: &AppState, handle: u64, block: BlockId) -> Option<CheckPlan> {
    let spelling = state.spelling();
    let session = state.session(handle)?;
    let text = session.document().block(block)?.text().to_owned();
    let text_fingerprint = fingerprint(&text);
    let accepted = accepted_words(state, handle)?;
    let key = key_for(
        &text,
        &accepted,
        spelling.revision,
        session.spelling().revision,
    );
    let cached = session
        .spelling()
        .cache
        .get(&block)
        .filter(|cached| cached.key == key)
        .map(|cached| cached.misspellings.clone());
    Some(CheckPlan {
        enabled: spelling.enabled,
        dictionary: spelling.dictionary.clone(),
        text,
        text_fingerprint,
        accepted,
        key,
        cached,
    })
}

fn cache_key(state: &AppState, handle: u64, block: BlockId) -> Option<u64> {
    let spelling = state.spelling();
    let session = state.session(handle)?;
    let text = session.document().block(block)?.text();
    let accepted = accepted_words(state, handle)?;
    Some(key_for(
        text,
        &accepted,
        spelling.revision,
        session.spelling().revision,
    ))
}

fn accepted_words(state: &AppState, handle: u64) -> Option<BTreeSet<String>> {
    let session = state.session(handle)?;
    let mut accepted = state.spelling().personal_words.clone();
    accepted.extend(session.spelling().project_words.iter().cloned());
    accepted.extend(session.spelling().ignored_all.iter().cloned());
    for kind in [EntityKind::Character, EntityKind::Location] {
        for entity in session.entities().complete(kind, "", &[]) {
            accepted.extend(core::words_in(&entity.value).map(core::normalise_word));
        }
    }
    Some(accepted)
}

fn key_for(
    text: &str,
    accepted: &BTreeSet<String>,
    global_revision: u64,
    session_revision: u64,
) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    text.hash(&mut hasher);
    accepted.hash(&mut hasher);
    global_revision.hash(&mut hasher);
    session_revision.hash(&mut hasher);
    hasher.finish()
}

fn fingerprint(text: &str) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    text.hash(&mut hasher);
    hasher.finish()
}

fn misspelling_views(
    block: u64,
    text: &str,
    text_fingerprint: u64,
    misspellings: Vec<CoreMisspelling>,
    ignored: &std::collections::HashSet<IgnoredOccurrence>,
) -> Vec<Misspelling> {
    misspellings
        .into_iter()
        .filter(|misspelling| {
            !ignored.contains(&IgnoredOccurrence {
                block: BlockId(block),
                text_fingerprint,
                start_utf8: misspelling.range_utf8.start,
                end_utf8: misspelling.range_utf8.end,
                word: misspelling.word.clone(),
            })
        })
        .filter_map(|misspelling| {
            let range = offsets::utf8_range_to_utf16(text, misspelling.range_utf8)?;
            Some(Misspelling {
                block,
                start_utf16: range.start,
                end_utf16: range.end,
                word: misspelling.word,
            })
        })
        .collect()
}

fn stale(block: u64) -> SpellCheckResult {
    SpellCheckResult {
        block,
        current: false,
        cached: false,
        misspellings: Vec::new(),
    }
}

fn status_view(spelling: &SpellingState) -> SpellStatus {
    SpellStatus {
        enabled: spelling.enabled,
        language: spelling.language.clone(),
        languages: spelling
            .dictionaries
            .iter()
            .map(|dictionary| SpellLanguage {
                code: dictionary.language.clone(),
                label: display_language(&dictionary.language),
            })
            .collect(),
        message: if spelling.enabled {
            spelling.message.clone()
        } else {
            "Spell checking is off.".to_owned()
        },
    }
}

fn display_language(code: &str) -> String {
    match code {
        "en_US" => "English (United States)".to_owned(),
        "en_GB" => "English (United Kingdom)".to_owned(),
        "en_CA" => "English (Canada)".to_owned(),
        "en_AU" => "English (Australia)".to_owned(),
        _ => code.replace('_', " – "),
    }
}

fn write_words(path: &Path, words: &BTreeSet<String>) -> Result<(), atomic::SaveError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|error| atomic::SaveError::Io {
            path: parent.to_path_buf(),
            message: error.to_string(),
        })?;
    }
    atomic::save_atomically(path, core::write_word_list(words))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actor::actor;
    use std::fs;
    use std::future::Future;
    use std::pin::pin;
    use std::task::{Context, Poll, Wake, Waker};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "slugline-bridge-spell-{label}-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn fixture(directory: &Path) -> DictionaryInfo {
        let aff_path = directory.join("en_US.aff");
        let dic_path = directory.join("en_US.dic");
        fs::write(&aff_path, "SET UTF-8\nTRY abcdefghijklmnopqrstuvwxyz\n").unwrap();
        fs::write(&dic_path, "4\nhello\nworld\nwalk\nstreet\n").unwrap();
        DictionaryInfo {
            language: "en_US".to_owned(),
            aff_path,
            dic_path,
        }
    }

    struct TestWake(std::thread::Thread);

    impl Wake for TestWake {
        fn wake(self: Arc<Self>) {
            self.0.unpark();
        }
    }

    fn block_on<T>(future: impl Future<Output = T>) -> T {
        let waker = Waker::from(Arc::new(TestWake(std::thread::current())));
        let mut context = Context::from_waker(&waker);
        let mut future = pin!(future);
        loop {
            match future.as_mut().poll(&mut context) {
                Poll::Ready(value) => return value,
                Poll::Pending => std::thread::yield_now(),
            }
        }
    }

    #[test]
    fn no_installed_dictionary_has_a_clear_message() {
        let directory = temp_dir("none");
        let state = initialise_from(Vec::new(), directory.join("personal.dic"), true, None);
        assert!(state.dictionary.is_none());
        assert!(state.message.contains("No Hunspell dictionaries"));
        let _ = fs::remove_dir_all(directory);
    }

    #[test]
    fn screenplay_entities_are_accepted_as_words() {
        let directory = temp_dir("entities");
        let mut state = AppState::default();
        *state.spelling_mut() = initialise_from(
            vec![fixture(&directory)],
            directory.join("personal.dic"),
            true,
            None,
        );
        let handle = state.open(slugline_document::Document::parse(
            "INT. ZORB PLAZA - DAY\n\nMCKENNA\nHello wurld.\n",
        ));
        let accepted = accepted_words(&state, handle).unwrap();
        assert!(accepted.contains("zorb"));
        assert!(accepted.contains("plaza"));
        assert!(accepted.contains("mckenna"));
        let _ = fs::remove_dir_all(directory);
    }

    #[test]
    fn cache_key_changes_with_text_or_an_overlay() {
        let accepted = BTreeSet::from(["name".to_owned()]);
        let key = key_for("hello", &accepted, 1, 1);
        assert_ne!(key, key_for("hello!", &accepted, 1, 1));
        assert_ne!(key, key_for("hello", &accepted, 2, 1));
        assert_ne!(
            key,
            key_for("hello", &BTreeSet::from(["other".to_owned()]), 1, 1)
        );
    }

    #[test]
    fn block_checks_are_cached_and_entity_words_are_not_underlined() {
        let _serial = spell_test_lock();
        let directory = temp_dir("check-block");
        let spelling = initialise_from(
            vec![fixture(&directory)],
            directory.join("personal.dic"),
            true,
            None,
        );
        let (handle, dialogue) = actor().run(move |state| {
            *state.spelling_mut() = spelling;
            let handle = state.open(slugline_document::Document::parse(
                "INT. ZORB PLAZA - DAY\n\nMCKENNA\nZorb Mckenna says wurld.\n",
            ));
            let dialogue = state
                .session(handle)
                .unwrap()
                .document()
                .blocks()
                .last()
                .unwrap()
                .id()
                .0;
            (DocumentHandle { id: handle }, dialogue)
        });

        let first = block_on(spell_check_block(handle, dialogue));
        assert!(first.current);
        assert!(!first.cached);
        assert_eq!(
            first
                .misspellings
                .iter()
                .map(|misspelling| misspelling.word.as_str())
                .collect::<Vec<_>>(),
            ["says", "wurld"],
            "character and location words are automatically accepted"
        );

        let second = block_on(spell_check_block(handle, dialogue));
        assert!(
            second.cached,
            "the exact block hash/configuration is reused"
        );

        let typo = second
            .misspellings
            .iter()
            .find(|misspelling| misspelling.word == "wurld")
            .unwrap()
            .clone();
        assert_eq!(
            spell_ignore_once(
                handle,
                typo.block,
                typo.start_utf16,
                typo.end_utf16,
                typo.word,
            ),
            SpellActionResult::Applied
        );
        assert_eq!(
            block_on(spell_check_block(handle, dialogue))
                .misspellings
                .iter()
                .map(|misspelling| misspelling.word.as_str())
                .collect::<Vec<_>>(),
            ["says"]
        );

        actor().run(move |state| state.close(handle.id));
        let _ = fs::remove_dir_all(directory);
    }
}

#[cfg(test)]
#[path = "spellcheck_never_modifies.rs"]
mod spellcheck_never_modifies;
