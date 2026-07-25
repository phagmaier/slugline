//! Find and replace (§6's `find` and `replace_all`).
//!
//! Plain substring search, not a regular expression: §1.4's non-goals do not
//! include one, and nothing in §5 or §9 asks for one. What it does have to be is
//! honest about text — a case-insensitive match is compared character by
//! character rather than by lower-casing both sides, because lower-casing can
//! change a string's length and every offset here is an offset into the text the
//! user can see. The price is that a character whose lower case is two
//! characters (`İ`) matches only itself; the alternative price was a match range
//! that lands in the middle of one.
//!
//! Offsets are UTF-8 byte offsets, like everything else in this crate (ADR
//! 0008). The bridge converts them.

use std::ops::Range;

use slugline_fountain::BlockKind;

use crate::BlockId;

/// What to look for (§6).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FindQuery {
    pub text: String,
    pub case_sensitive: bool,
    /// Both ends of the match must sit against a non-word character.
    pub whole_word: bool,
    /// When non-empty, only blocks of these kinds are searched — §Phase 3's
    /// optional "restrict search to element types (dialogue only, etc.)".
    pub kinds: Vec<BlockKind>,
}

impl FindQuery {
    /// A query that cannot match anything, so callers do not have to special-case
    /// an empty search box.
    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }

    pub fn searches(&self, kind: BlockKind) -> bool {
        self.kinds.is_empty() || self.kinds.contains(&kind)
    }
}

/// One hit: a byte range within one block's text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Match {
    pub block: BlockId,
    pub range: Range<u32>,
}

/// Every non-overlapping match of `query` in `text`, in order.
///
/// A match is found at a `char` boundary and ends at one, so a range from here
/// is always safe to hand to `ReplaceText`.
pub(crate) fn matches_in(text: &str, query: &FindQuery) -> Vec<Range<u32>> {
    if query.is_empty() {
        return Vec::new();
    }
    let mut found = Vec::new();
    let mut start = 0;
    while start <= text.len() {
        match match_length_at(&text[start..], &query.text, query.case_sensitive) {
            Some(length) if whole_word(text, start, start + length, query.whole_word) => {
                found.push(start as u32..(start + length) as u32);
                // An empty needle is impossible here, so this always advances.
                start += length;
            }
            _ => match text[start..].chars().next() {
                Some(character) => start += character.len_utf8(),
                None => break,
            },
        }
    }
    found
}

/// The byte length of a match of `needle` at the front of `haystack`.
///
/// Compared character by character in both strings at once, which is what makes
/// a case-insensitive match report a length in the *haystack's* bytes rather
/// than in the folded string's.
fn match_length_at(haystack: &str, needle: &str, case_sensitive: bool) -> Option<usize> {
    let mut consumed = 0;
    let mut wanted = needle.chars();
    let mut found = haystack.chars();
    loop {
        let Some(want) = wanted.next() else {
            return Some(consumed);
        };
        let have = found.next()?;
        let same = if case_sensitive {
            have == want
        } else {
            have.to_lowercase().eq(want.to_lowercase())
        };
        if !same {
            return None;
        }
        consumed += have.len_utf8();
    }
}

/// Whether the characters either side of `start..end` allow a whole-word match.
fn whole_word(text: &str, start: usize, end: usize, required: bool) -> bool {
    if !required {
        return true;
    }
    let before = text[..start].chars().next_back();
    let after = text[end..].chars().next();
    !before.is_some_and(is_word) && !after.is_some_and(is_word)
}

/// A word character, for the whole-word toggle. Underscore counts because it
/// reads as part of a word; an apostrophe does not, so searching for `dont`
/// whole-word does not match inside `don't`.
fn is_word(character: char) -> bool {
    character.is_alphanumeric() || character == '_'
}

#[cfg(test)]
mod tests {
    use super::*;

    fn query(text: &str) -> FindQuery {
        FindQuery {
            text: text.to_owned(),
            ..FindQuery::default()
        }
    }

    fn found(text: &str, query: &FindQuery) -> Vec<String> {
        matches_in(text, query)
            .into_iter()
            .map(|range| text[range.start as usize..range.end as usize].to_owned())
            .collect()
    }

    #[test]
    fn matches_do_not_overlap() {
        assert_eq!(
            matches_in("aaaa", &query("aa")),
            [0u32..2, 2..4],
            "the second match starts after the first ends"
        );
    }

    #[test]
    fn case_insensitive_by_default_and_exact_when_asked() {
        assert_eq!(found("John and JOHN and john", &query("john")).len(), 3);
        let exact = FindQuery {
            case_sensitive: true,
            ..query("john")
        };
        assert_eq!(found("John and JOHN and john", &exact), ["john"]);
    }

    /// The reason a case-insensitive match walks both strings at once: a folded
    /// character can be a different number of bytes from the one it folds to, and
    /// the range has to be in the bytes of the text being searched.
    #[test]
    fn a_case_fold_that_changes_width_reports_the_searched_texts_own_bytes() {
        // U+212A KELVIN SIGN is three bytes and lower-cases to a one-byte 'k'.
        let text = "\u{212a}elvin";
        assert_eq!(text.len(), 8, "eight bytes for six characters");
        let hits = matches_in(text, &query("kelvin"));
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0], 0..8, "the whole word, in the text's own bytes");
        assert!(text.is_char_boundary(hits[0].end as usize));
    }

    /// The honest limit of a per-character fold, stated as a test so that nobody
    /// discovers it by accident: a character whose lower case is *two*
    /// characters only matches itself.
    #[test]
    fn a_one_to_many_fold_is_not_matched() {
        assert!(matches_in("\u{130}stanbul", &query("istanbul")).is_empty());
        assert_eq!(
            matches_in("\u{130}stanbul", &query("\u{130}STANBUL")).len(),
            1
        );
    }

    #[test]
    fn whole_word_needs_a_boundary_at_both_ends() {
        let whole = FindQuery {
            whole_word: true,
            ..query("cat")
        };
        assert_eq!(found("the cat sat", &whole), ["cat"]);
        assert!(found("concatenate", &whole).is_empty());
        assert!(found("cats", &whole).is_empty());
        assert!(found("bobcat", &whole).is_empty());
        assert_eq!(found("(cat)", &whole), ["cat"]);
        assert_eq!(found("cat", &whole), ["cat"]);
        // An apostrophe is not a word character, so the two halves are words.
        let dont = FindQuery {
            whole_word: true,
            ..query("don")
        };
        assert_eq!(found("don't", &dont), ["don"]);
    }

    #[test]
    fn a_match_never_lands_inside_a_character() {
        let text = "café 🎬 café";
        for hit in matches_in(text, &query("café")) {
            assert!(text.is_char_boundary(hit.start as usize));
            assert!(text.is_char_boundary(hit.end as usize));
        }
        assert_eq!(found(text, &query("café")).len(), 2);
        assert_eq!(found(text, &query("🎬")).len(), 1);
    }

    #[test]
    fn an_empty_query_matches_nothing() {
        assert!(matches_in("anything at all", &query("")).is_empty());
    }

    #[test]
    fn a_query_longer_than_the_text_matches_nothing() {
        assert!(matches_in("ab", &query("abc")).is_empty());
    }

    #[test]
    fn an_element_filter_is_empty_for_everything() {
        assert!(query("x").searches(BlockKind::Action));
        let dialogue_only = FindQuery {
            kinds: vec![BlockKind::Dialogue],
            ..query("x")
        };
        assert!(dialogue_only.searches(BlockKind::Dialogue));
        assert!(!dialogue_only.searches(BlockKind::Action));
    }
}
