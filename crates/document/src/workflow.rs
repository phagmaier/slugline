//! The Enter and Tab tables of `docs/KEYMAP.md`.
//!
//! These are pure functions of a block's kind and its neighbour's, and they live
//! here rather than in the editor for the reason §2.1 gives: Flutter owns the
//! keyboard, but what a screenplay element is followed by is a screenplay
//! question, and a second opinion about it in Dart is a second opinion that can
//! drift. The editor binds the key; this says what the key means.
//!
//! They are not in `fountain` either. Fountain the format has nothing to say
//! about Tab — it does not know there is a keyboard. What it does say is *why*
//! these particular answers are right: Enter after a cue creates dialogue
//! because §4.1 reads the line after a cue as dialogue, and the two tables agree
//! with `infer_kind` everywhere, which is what stops one from undoing the other.

use slugline_fountain::BlockKind;

/// The element Enter creates when it is pressed at the end of a block of this
/// kind (§Phase 3's baseline table).
///
/// The block that is created is deliberately **not** forced: it is empty, so
/// there is nothing yet to pin, and leaving it unforced is what lets the first
/// thing typed into it be recognised — `INT.` into the block after a scene
/// heading promotes it right back to a scene heading.
pub fn kind_after_enter(kind: BlockKind) -> BlockKind {
    match kind {
        // A slug line is followed by what happens there.
        BlockKind::SceneHeading => BlockKind::Action,
        // A cue and a parenthetical are both followed by the words spoken.
        BlockKind::Character | BlockKind::Parenthetical => BlockKind::Dialogue,
        // A speech is followed by action. `Character` is the double-Enter case,
        // and it is not reached from here: see `enter_makes_a_cue`.
        BlockKind::Dialogue => BlockKind::Action,
        // A transition is followed by the scene it transitions to.
        BlockKind::Transition => BlockKind::SceneHeading,
        // A song has more than one line, and so does a stanza of lyrics.
        BlockKind::Lyric => BlockKind::Lyric,
        // Everything else — action, centred text, a section, a synopsis, a note,
        // a page break — is followed by action, which is Fountain's default and
        // the only kind that needs no marker.
        _ => BlockKind::Action,
    }
}

/// Whether Enter in an empty block should turn it into a character cue rather
/// than create another block — §Phase 3's "or Character on double-Enter".
///
/// Pressing Enter at the end of a speech leaves an empty Action block (the table
/// above). Pressing it again there means "I am not writing action, I am writing
/// another cue", and this is that second press. It is stated as a fact about the
/// block rather than as a memory of the previous keystroke so that there is no
/// hidden state to get out of step with the document.
pub fn enter_makes_a_cue(
    kind: BlockKind,
    forced: bool,
    text: &str,
    previous: Option<BlockKind>,
) -> bool {
    text.is_empty() && kind == BlockKind::Action && !forced && previous == Some(BlockKind::Dialogue)
}

/// The element Tab moves to, or `None` where Tab does nothing.
///
/// Tab is a two-step toggle rather than a longer ring, and the baseline table
/// is what fixes that: it gives Tab an answer for Action, Character and
/// Dialogue and a dash — nothing at all — for Scene heading, Parenthetical and
/// Transition. A ring would have to give the dashes an answer.
pub fn kind_after_tab(kind: BlockKind) -> Option<BlockKind> {
    match kind {
        // The cue you were about to write, when the block began as action.
        BlockKind::Action => Some(BlockKind::Character),
        // §Phase 3 reads "accept completion, else Parenthetical". Completion is
        // Phase 5; the editor tries it first and falls through to here.
        BlockKind::Character => Some(BlockKind::Parenthetical),
        BlockKind::Dialogue => Some(BlockKind::Parenthetical),
        _ => None,
    }
}

/// The element Shift+Tab moves to: the exact inverse of [`kind_after_tab`].
///
/// `previous` settles the only ambiguity. Two rows of the forward table lead to
/// a parenthetical, so coming back out of one asks what it is attached to — the
/// cue above it, or the speech above it.
pub fn kind_before_tab(kind: BlockKind, previous: Option<BlockKind>) -> Option<BlockKind> {
    match kind {
        BlockKind::Character => Some(BlockKind::Action),
        BlockKind::Parenthetical => match previous {
            Some(BlockKind::Character) => Some(BlockKind::Character),
            // Under a speech, or under nothing at all: dialogue is the row that
            // leads here, and it is also the only kind a parenthetical can sit
            // beside without the cue above it being orphaned.
            _ => Some(BlockKind::Dialogue),
        },
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// §Phase 3's baseline table, verbatim.
    #[test]
    fn the_baseline_table_holds() {
        let rows = [
            (BlockKind::SceneHeading, BlockKind::Action, None),
            (
                BlockKind::Action,
                BlockKind::Action,
                Some(BlockKind::Character),
            ),
            (
                BlockKind::Character,
                BlockKind::Dialogue,
                Some(BlockKind::Parenthetical),
            ),
            (BlockKind::Parenthetical, BlockKind::Dialogue, None),
            (
                BlockKind::Dialogue,
                BlockKind::Action,
                Some(BlockKind::Parenthetical),
            ),
            (BlockKind::Transition, BlockKind::SceneHeading, None),
        ];
        for (kind, enter, tab) in rows {
            assert_eq!(kind_after_enter(kind), enter, "Enter from {kind:?}");
            assert_eq!(kind_after_tab(kind), tab, "Tab from {kind:?}");
        }
    }

    #[test]
    fn shift_tab_reverses_every_step_tab_takes() {
        for kind in [BlockKind::Action, BlockKind::Character, BlockKind::Dialogue] {
            let forward = kind_after_tab(kind).expect("a step forward");
            let previous = match kind {
                // The block a parenthetical came back to sits above it.
                BlockKind::Dialogue => Some(BlockKind::Dialogue),
                other => Some(other),
            };
            assert_eq!(
                kind_before_tab(forward, previous),
                Some(kind),
                "Shift+Tab out of {forward:?} should return to {kind:?}"
            );
        }
    }

    #[test]
    fn tab_does_nothing_where_the_table_says_nothing() {
        for kind in [
            BlockKind::SceneHeading,
            BlockKind::Transition,
            BlockKind::Centered,
            BlockKind::Lyric,
            BlockKind::Section { level: 1 },
            BlockKind::Synopsis,
            BlockKind::Note,
            BlockKind::PageBreak,
            BlockKind::Opaque,
        ] {
            assert_eq!(kind_after_tab(kind), None, "Tab from {kind:?}");
        }
        for kind in [
            BlockKind::SceneHeading,
            BlockKind::Action,
            BlockKind::Dialogue,
            BlockKind::Transition,
            BlockKind::Opaque,
        ] {
            assert_eq!(kind_before_tab(kind, None), None, "Shift+Tab from {kind:?}");
        }
    }

    #[test]
    fn a_lyric_is_followed_by_another_lyric() {
        assert_eq!(kind_after_enter(BlockKind::Lyric), BlockKind::Lyric);
        assert_eq!(
            kind_after_enter(BlockKind::Section { level: 3 }),
            BlockKind::Action
        );
        assert_eq!(kind_after_enter(BlockKind::Centered), BlockKind::Action);
    }

    #[test]
    fn only_an_empty_unforced_action_block_under_a_speech_becomes_a_cue() {
        assert!(enter_makes_a_cue(
            BlockKind::Action,
            false,
            "",
            Some(BlockKind::Dialogue)
        ));
        // Something written in it: Enter splits, as everywhere else.
        assert!(!enter_makes_a_cue(
            BlockKind::Action,
            false,
            "He leaves.",
            Some(BlockKind::Dialogue)
        ));
        // The writer said Action out loud, so Enter does not argue.
        assert!(!enter_makes_a_cue(
            BlockKind::Action,
            true,
            "",
            Some(BlockKind::Dialogue)
        ));
        // Not under a speech at all.
        assert!(!enter_makes_a_cue(BlockKind::Action, false, "", None));
        assert!(!enter_makes_a_cue(
            BlockKind::Action,
            false,
            "",
            Some(BlockKind::SceneHeading)
        ));
        // Already something other than action.
        assert!(!enter_makes_a_cue(
            BlockKind::Dialogue,
            false,
            "",
            Some(BlockKind::Dialogue)
        ));
    }
}
