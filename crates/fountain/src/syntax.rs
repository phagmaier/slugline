//! The recognition rules of §4.1, in one place.
//!
//! The parser uses these to decide what a line is. The serialiser uses the same
//! functions, backwards, to decide whether a re-serialised block needs a forced
//! prefix to survive being read again. Keeping both callers on one
//! implementation is what makes "parse, edit one block, serialise, reparse"
//! stable: there is no second opinion about what a line means.

use crate::BlockKind;

/// An explicit Fountain element marker at the start of a line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Marker {
    SceneHeading,
    Action,
    Character,
    Transition,
    Centered,
    Lyric,
    Section(u8),
    Synopsis,
    PageBreak,
}

impl Marker {
    pub(crate) fn kind(self) -> BlockKind {
        match self {
            Marker::SceneHeading => BlockKind::SceneHeading,
            Marker::Action => BlockKind::Action,
            Marker::Character => BlockKind::Character,
            Marker::Transition => BlockKind::Transition,
            Marker::Centered => BlockKind::Centered,
            Marker::Lyric => BlockKind::Lyric,
            Marker::Section(level) => BlockKind::Section { level },
            Marker::Synopsis => BlockKind::Synopsis,
            Marker::PageBreak => BlockKind::PageBreak,
        }
    }

    /// Whether this marker sets `forced` (§3.1: `.`, `@`, `>`, `!`).
    ///
    /// `~`, `#`, `=` and `===` are not "forcing" anything: they are the only
    /// way to write a lyric, a section, a synopsis or a page break, so the kind
    /// already implies the marker and `forced` would carry no information.
    pub(crate) fn forces(self) -> bool {
        matches!(
            self,
            Marker::SceneHeading | Marker::Action | Marker::Character | Marker::Transition
        )
    }
}

/// Reads an element marker off the front of a line.
///
/// `line` must already be trimmed of leading whitespace. Returns the marker and
/// the text that follows it; the text is trimmed on both ends except after `!`,
/// which exists to force an Action and therefore keeps the writer's spacing.
pub(crate) fn marker_of(line: &str) -> Option<(Marker, &str)> {
    let first = line.chars().next()?;
    let squared = line.trim_end();
    match first {
        '=' if is_page_break(line) => Some((Marker::PageBreak, "")),
        '=' => Some((Marker::Synopsis, line[1..].trim())),
        '#' => {
            let level = line.chars().take_while(|&c| c == '#').count();
            if (1..=6).contains(&level) {
                Some((Marker::Section(level as u8), line[level..].trim()))
            } else {
                None
            }
        }
        '~' => Some((Marker::Lyric, line[1..].trim())),
        // `..` is not a scene heading: it is how a line that starts with a dot
        // escapes itself, and an ellipsis at the start of dialogue is common.
        '.' if line.len() > 1 && !line.starts_with("..") => {
            Some((Marker::SceneHeading, line[1..].trim()))
        }
        '!' => Some((Marker::Action, &line[1..])),
        '@' => Some((Marker::Character, line[1..].trim())),
        '>' if squared.len() >= 2 && squared.ends_with('<') => {
            Some((Marker::Centered, squared[1..squared.len() - 1].trim()))
        }
        '>' => Some((Marker::Transition, line[1..].trim())),
        _ => None,
    }
}

/// A line of three or more `=` and nothing else (§4.1).
pub(crate) fn is_page_break(line: &str) -> bool {
    let line = line.trim();
    line.len() >= 3 && line.chars().all(|c| c == '=')
}

/// Begins with `INT`, `EXT`, `EST`, `INT./EXT`, `INT/EXT` or `I/E`, in any
/// case, and the prefix is a whole word (§4.1). The caller is responsible for
/// the "preceded by a blank line" half of the rule.
pub(crate) fn is_scene_heading(line: &str) -> bool {
    const PREFIXES: [&str; 6] = ["INT./EXT", "INT/EXT", "I/E", "INT", "EXT", "EST"];
    let upper = line.trim().to_uppercase();
    PREFIXES.iter().any(|prefix| {
        upper == *prefix
            || upper
                .strip_prefix(prefix)
                .is_some_and(|rest| rest.starts_with([' ', '.', '/']))
    })
}

/// All-caps and ending in `TO:` (§4.1). The caller checks that a blank line
/// sits on both sides.
pub(crate) fn is_transition(line: &str) -> bool {
    let line = line.trim();
    line.ends_with("TO:") && is_all_caps(line)
}

/// Splits a character cue into its name and its dual-dialogue flag, or returns
/// `None` if the line is not shaped like a cue.
///
/// §4.1 fixes the character set: letters, digits, `.`, `(`, `)`, `'`, `-`, and
/// spaces. "All-caps" is read as "contains an upper-case letter and no
/// lower-case one", which means a cue written entirely in a caseless script
/// (CJK) needs the `@` prefix. That is the honest reading: without case there
/// is nothing to distinguish a cue from a line of action.
pub(crate) fn character_of(line: &str) -> Option<(&str, bool)> {
    let line = line.trim();
    let (name, dual) = match line.strip_suffix('^') {
        Some(name) => (name.trim_end(), true),
        None => (line, false),
    };
    if name.is_empty() || !is_all_caps(name) {
        return None;
    }
    let allowed = name
        .chars()
        .all(|c| c.is_alphanumeric() || matches!(c, '.' | '(' | ')' | '\'' | '-' | ' '));
    allowed.then_some((name, dual))
}

/// Wrapped in parentheses (§4.1). Only meaningful directly after a character
/// cue or a dialogue line; the caller checks that.
pub(crate) fn is_parenthetical(line: &str) -> bool {
    let line = line.trim();
    line.len() >= 2 && line.starts_with('(') && line.ends_with(')')
}

/// At least one upper-case letter and no lower-case one. Digits, punctuation
/// and caseless scripts are neutral.
fn is_all_caps(text: &str) -> bool {
    let mut saw_upper = false;
    for c in text.chars() {
        if c.is_lowercase() {
            return false;
        }
        saw_upper |= c.is_uppercase();
    }
    saw_upper
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scene_heading_prefixes() {
        for heading in [
            "INT. HOUSE - DAY",
            "int. house - day",
            "EXT PARK",
            "EST. SHOT",
            "I/E CAR - NIGHT",
            "INT./EXT. CAR",
            "INT/EXT CAR",
            "INT.",
        ] {
            assert!(is_scene_heading(heading), "{heading:?} should be a heading");
        }
        for other in [
            "INTERIOR OF THE HOUSE",
            "ESTABLISHING",
            "INTO THE WOODS",
            "IN THE CAR",
            "",
        ] {
            assert!(
                !is_scene_heading(other),
                "{other:?} should not be a heading"
            );
        }
    }

    #[test]
    fn transitions_are_all_caps_and_end_in_to() {
        assert!(is_transition("CUT TO:"));
        assert!(is_transition("SMASH CUT TO:"));
        assert!(!is_transition("Cut to:"));
        assert!(!is_transition("CUT TO"));
        assert!(!is_transition("FADE OUT."));
    }

    #[test]
    fn character_cues_and_extensions() {
        assert_eq!(character_of("JOHN"), Some(("JOHN", false)));
        assert_eq!(character_of("JOHN (V.O.)"), Some(("JOHN (V.O.)", false)));
        assert_eq!(character_of("MARY-ANNE"), Some(("MARY-ANNE", false)));
        assert_eq!(character_of("R2-D2"), Some(("R2-D2", false)));
        assert_eq!(character_of("JOSÉ"), Some(("JOSÉ", false)));
        assert_eq!(character_of("JOHN ^"), Some(("JOHN", true)));
        assert_eq!(character_of("JOHN^"), Some(("JOHN", true)));

        assert_eq!(character_of("John"), None);
        assert_eq!(character_of("1234"), None);
        assert_eq!(character_of(""), None);
        assert_eq!(character_of("^"), None);
        // A comma is outside the §4.1 character set.
        assert_eq!(character_of("JOHN, JR."), None);
        // Caseless scripts have no upper case to find.
        assert_eq!(character_of("日本"), None);
    }

    #[test]
    fn markers_strip_themselves_from_the_text() {
        assert_eq!(
            marker_of(".INT HOUSE"),
            Some((Marker::SceneHeading, "INT HOUSE"))
        );
        assert_eq!(marker_of("@McCLANE"), Some((Marker::Character, "McCLANE")));
        assert_eq!(
            marker_of(">BURN TO PINK:"),
            Some((Marker::Transition, "BURN TO PINK:"))
        );
        assert_eq!(
            marker_of("> THE END <"),
            Some((Marker::Centered, "THE END"))
        );
        assert_eq!(
            marker_of("~Willy Wonka"),
            Some((Marker::Lyric, "Willy Wonka"))
        );
        assert_eq!(
            marker_of("### Act Two"),
            Some((Marker::Section(3), "Act Two"))
        );
        assert_eq!(
            marker_of("= A synopsis"),
            Some((Marker::Synopsis, "A synopsis"))
        );
        assert_eq!(marker_of("==="), Some((Marker::PageBreak, "")));
        assert_eq!(marker_of("!  spaced"), Some((Marker::Action, "  spaced")));
    }

    #[test]
    fn non_markers_are_left_alone() {
        assert_eq!(marker_of("...trailing off"), None);
        assert_eq!(marker_of("."), None);
        assert_eq!(marker_of("####### seven"), None);
        assert_eq!(marker_of("Ordinary action."), None);
        assert_eq!(marker_of("=="), Some((Marker::Synopsis, "=")));
    }

    #[test]
    fn only_dot_and_at_and_gt_and_bang_set_forced() {
        assert!(Marker::SceneHeading.forces());
        assert!(Marker::Character.forces());
        assert!(Marker::Transition.forces());
        assert!(Marker::Action.forces());
        assert!(!Marker::Lyric.forces());
        assert!(!Marker::Section(1).forces());
        assert!(!Marker::Synopsis.forces());
        assert!(!Marker::PageBreak.forces());
    }

    #[test]
    fn page_breaks_need_three_equals() {
        assert!(is_page_break("==="));
        assert!(is_page_break("========"));
        assert!(!is_page_break("=="));
        assert!(!is_page_break("=== nope"));
    }

    #[test]
    fn parentheticals_are_wrapped() {
        assert!(is_parenthetical("(quietly)"));
        assert!(!is_parenthetical("(unclosed"));
        assert!(!is_parenthetical("()x"));
    }
}
