//! Automatic element classification (§4.2).
//!
//! This is the third caller of [`crate::syntax`], and it asks the same question
//! the parser does — "what is this line?" — about a block that is already in a
//! document. The parser reads it off a file; this reads it off the block's text
//! and its two neighbours. Because both go through the same recognition rules,
//! re-classifying a block moves it *towards* what the file would parse back as
//! rather than away from it: typing `INT. HOUSE` into an action paragraph
//! promotes it to a scene heading, and the serialiser then writes the line
//! without the `!` it would otherwise need to protect it.
//!
//! Nothing here decides *when* to ask. §4.2's scope rules — one block either
//! side of an edit, never a forced block, never a block the caret is nowhere
//! near — belong to the document, which is the only thing that knows where the
//! caret is. See `slugline_document::Document::reinfer`.

use crate::syntax;
use crate::BlockKind;

/// Where a block sits, as far as classification is concerned.
///
/// One block either side is the whole of it: §4.1's rules reach exactly that
/// far. "Preceded by a blank line" is a question about the block above, and
/// "followed by a non-blank line" one about the block below.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Context {
    pub previous: Option<BlockKind>,
    /// The kind the block has now. It is an input, not just the thing being
    /// replaced — see [`infer_kind`].
    pub current: BlockKind,
    pub next: Option<BlockKind>,
}

/// What §4.1 would call `text` where this block sits, or `None` when the
/// question does not apply to it.
///
/// The block's **current** kind is part of the context, and that is what makes
/// the answer stable rather than oscillating. Whether a block is preceded by a
/// blank line is not a fact about its text: it is what the serialiser decides
/// from the two kinds involved (`needs_blank_between`). So the current kind
/// settles it first, and the text is read in the position that produces.
///
/// Concretely, after a line of dialogue:
///
/// * a block that is *already* dialogue or a parenthetical is written adjacent
///   to it, is therefore read as part of the same speech, and stays dialogue;
/// * a block that is action is written after a blank line, is therefore read as
///   a fresh element, and is free to become a scene heading or a transition.
///
/// Both are what a reparse would say, which is the property worth having: this
/// function never invents a kind the file would not give back.
pub fn infer_kind(text: &str, at: Context) -> Option<BlockKind> {
    if !at.current.is_inferable() || text.is_empty() {
        return None;
    }

    if at.previous.is_some_and(BlockKind::opens_dialogue) && at.current.continues_dialogue() {
        let parenthetical = !text.contains('\n') && syntax::is_parenthetical(text);
        return Some(if parenthetical {
            BlockKind::Parenthetical
        } else {
            BlockKind::Dialogue
        });
    }

    // Everything from here down is separated from what precedes it by a blank
    // line, so the rules that require one are in play. All three are single-line
    // elements by definition (§4.1), which is why a paragraph that has grown a
    // second line is action whatever its first line says.
    if text.contains('\n') {
        return Some(BlockKind::Action);
    }
    if syntax::is_scene_heading(text) {
        return Some(BlockKind::SceneHeading);
    }
    // Like the parser, a transition needs a blank line after it. When speech
    // follows immediately, even `CUT TO:` can instead be a character cue.
    if syntax::is_transition(text) && !at.next.is_some_and(BlockKind::continues_dialogue) {
        return Some(BlockKind::Transition);
    }
    // A cue is only a cue when something speaks under it (§4.1); the same
    // capitals with a blank line below them are a line of action. The dual
    // marker is left to `SetDual`: a `^` the writer typed into an action line is
    // text, and turning it into a flag here would take a character off the page.
    let cue = matches!(syntax::character_of(text), Some((_, false)));
    if cue && at.next.is_some_and(BlockKind::continues_dialogue) {
        return Some(BlockKind::Character);
    }
    Some(BlockKind::Action)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(previous: Option<BlockKind>, current: BlockKind, next: Option<BlockKind>) -> Context {
        Context {
            previous,
            current,
            next,
        }
    }

    /// An action paragraph, with a blank line above it.
    fn action(text: &str) -> Option<BlockKind> {
        infer_kind(text, at(Some(BlockKind::Action), BlockKind::Action, None))
    }

    #[test]
    fn int_and_ext_promote_an_action_paragraph() {
        assert_eq!(action("INT. HOUSE - DAY"), Some(BlockKind::SceneHeading));
        assert_eq!(action("EXT. ROAD"), Some(BlockKind::SceneHeading));
        assert_eq!(action("I/E CAR - NIGHT"), Some(BlockKind::SceneHeading));
        assert_eq!(action("int. house - day"), Some(BlockKind::SceneHeading));
        // Half-typed, and a word that merely starts with the same letters.
        assert_eq!(action("IN"), Some(BlockKind::Action));
        assert_eq!(action("INTERIOR OF THE HOUSE"), Some(BlockKind::Action));
    }

    #[test]
    fn a_transition_is_recognised_and_a_near_miss_is_not() {
        assert_eq!(action("CUT TO:"), Some(BlockKind::Transition));
        assert_eq!(action("SMASH CUT TO:"), Some(BlockKind::Transition));
        assert_eq!(action("Cut to:"), Some(BlockKind::Action));
        assert_eq!(action("CUT TO"), Some(BlockKind::Action));
    }

    #[test]
    fn a_cue_needs_something_to_speak_under_it() {
        assert_eq!(
            infer_kind(
                "JOHN",
                at(
                    Some(BlockKind::Action),
                    BlockKind::Action,
                    Some(BlockKind::Dialogue)
                )
            ),
            Some(BlockKind::Character)
        );
        // Nothing below, so the same capitals are action — which is exactly what
        // reparsing the file would say.
        assert_eq!(action("JOHN"), Some(BlockKind::Action));
        assert_eq!(
            infer_kind(
                "JOHN",
                at(
                    Some(BlockKind::Action),
                    BlockKind::Action,
                    Some(BlockKind::Action)
                )
            ),
            Some(BlockKind::Action)
        );
    }

    #[test]
    fn a_dual_marker_is_left_as_text() {
        assert_eq!(
            infer_kind(
                "JOHN ^",
                at(
                    Some(BlockKind::Action),
                    BlockKind::Action,
                    Some(BlockKind::Dialogue)
                )
            ),
            Some(BlockKind::Action)
        );
    }

    #[test]
    fn a_block_after_a_cue_is_dialogue_or_a_parenthetical() {
        let after_cue =
            |text: &str, current| infer_kind(text, at(Some(BlockKind::Character), current, None));
        assert_eq!(
            after_cue("Hello.", BlockKind::Dialogue),
            Some(BlockKind::Dialogue)
        );
        assert_eq!(
            after_cue("(quietly)", BlockKind::Dialogue),
            Some(BlockKind::Parenthetical)
        );
        assert_eq!(
            after_cue("quietly)", BlockKind::Parenthetical),
            Some(BlockKind::Dialogue)
        );
        // A slug line typed into dialogue is dialogue: the cue above it means
        // the serialiser writes it adjacent, and the parser reads it as speech.
        assert_eq!(
            after_cue("INT. HOUSE - DAY", BlockKind::Dialogue),
            Some(BlockKind::Dialogue)
        );
    }

    #[test]
    fn action_after_dialogue_is_still_action() {
        // The block the Enter table creates after a speech. It is separated from
        // the dialogue by a blank line, so it is a fresh element and may be
        // promoted — the thing a reparse would agree with.
        let after_speech =
            |text: &str| infer_kind(text, at(Some(BlockKind::Dialogue), BlockKind::Action, None));
        assert_eq!(after_speech("He leaves."), Some(BlockKind::Action));
        assert_eq!(
            after_speech("INT. ROAD - DAY"),
            Some(BlockKind::SceneHeading)
        );
    }

    #[test]
    fn dialogue_whose_cue_has_gone_becomes_action() {
        assert_eq!(
            infer_kind(
                "Hello.",
                at(Some(BlockKind::Action), BlockKind::Dialogue, None)
            ),
            Some(BlockKind::Action)
        );
        assert_eq!(
            infer_kind("(quietly)", at(None, BlockKind::Parenthetical, None)),
            Some(BlockKind::Action)
        );
    }

    #[test]
    fn a_paragraph_of_more_than_one_line_is_action() {
        assert_eq!(
            action("INT. HOUSE - DAY\nJohn enters."),
            Some(BlockKind::Action)
        );
        assert_eq!(action("CUT TO:\nand back."), Some(BlockKind::Action));
    }

    #[test]
    fn marker_only_kinds_and_empty_blocks_are_left_alone() {
        for kind in [
            BlockKind::Centered,
            BlockKind::Lyric,
            BlockKind::Section { level: 2 },
            BlockKind::Synopsis,
            BlockKind::Note,
            BlockKind::PageBreak,
            BlockKind::Opaque,
        ] {
            assert_eq!(
                infer_kind("INT. HOUSE - DAY", at(None, kind, None)),
                None,
                "{kind:?} carries its marker in its kind"
            );
        }
        // An empty block has nothing to classify, and the kind that put it there
        // is the only intent available.
        assert_eq!(
            infer_kind("", at(None, BlockKind::SceneHeading, None)),
            None
        );
    }

    /// Inference must agree with the parser, or a document would change kinds
    /// every time it was saved and reopened.
    #[test]
    fn inference_agrees_with_a_reparse() {
        use crate::parse;

        for source in [
            "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\n(quietly)\nHello.\n\nCUT TO:\n",
            "Action.\n\nJOHN\nHello.\nMore.\n\nEXT. ROAD - NIGHT\n",
        ] {
            let script = parse(source);
            let kinds: Vec<BlockKind> = script.elements.iter().map(|e| e.kind).collect();
            for (index, element) in script.elements.iter().enumerate() {
                if element.forced {
                    continue;
                }
                let inferred = infer_kind(
                    &element.text,
                    at(
                        index.checked_sub(1).map(|i| kinds[i]),
                        element.kind,
                        kinds.get(index + 1).copied(),
                    ),
                );
                assert_eq!(
                    inferred,
                    Some(element.kind),
                    "inference disagrees with the parser about {:?} in {source:?}",
                    element.text
                );
            }
        }
    }
}
