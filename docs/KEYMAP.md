# Keyboard map

Spec §16 lists "exact keyboard shortcut map" as an open decision, to be settled
before Phase 3. This is that decision.

Two rules govern the whole map:

1. **The keyboard is Flutter's; what a key *means* is the core's.** Binding Tab is
   a Dart concern. Which element follows a character cue is a screenplay
   question, so it lives in `crates/document/src/workflow.rs` and this document
   describes it rather than defining it. Dart never works out what an element is
   or what comes after it (§2.1).
2. **Nothing here can lose text.** Escape in particular is never a deletion and
   never a command; the worst it does is drop a selection.

Phase 10 makes the digits a preference. Until then these are the bindings, and
`app/lib/editor/elements.dart` is the one table the shortcuts, the element
selector and the command palette all read.

---

## Element types

`Ctrl` and a digit sets the element type of the block the caret is in. It never
touches a character of the text — that is a dedicated test
(`crates/document/tests/element_change_preserves_text.rs`).

| Key | Element |
| --- | --- |
| `Ctrl+1` | Scene heading |
| `Ctrl+2` | Action |
| `Ctrl+3` | Character |
| `Ctrl+4` | Dialogue |
| `Ctrl+5` | Parenthetical |
| `Ctrl+6` | Transition |
| `Ctrl+7` | Centred |
| `Ctrl+8` | Lyric |
| `Ctrl+9` | Section |
| `Ctrl+0` | Synopsis |
| — | Note, Page break — the palette only; there are ten digits and more element types |

The number-pad digits do the same thing as the ones above the letters.

Setting a type this way sets `forced = true`, exactly as §Phase 3 requires. Two
consequences worth stating out loud:

* **It suppresses automatic re-classification.** Pressing `Ctrl+2` immediately
  after the editor promoted a line to a scene heading reverts it *and* keeps it
  reverted, however much more of that slug line you type.
* **It is visible in the file**, as §4.1's forced form — `.` for a heading, `@`
  for a cue, `>` for a transition, `!` for action. That is Fountain's own way of
  recording "a human said so", which is the same thing `forced` means. The
  element bar shows a pin beside the element name when a block carries one.

Automatic detection never forces anything. A block promoted by typing `INT.` is an
unforced scene heading, and is written without a marker.

---

## Enter

Enter at the **end** of a block splits it and gives the new block below the type
that follows this one. Enter in the **middle** of a block breaks one element into
two, and both halves keep the type and the pin they had — pressing Enter halfway
through an action paragraph does not turn its second half into something else.

| Current element | Enter creates |
| --- | --- |
| Scene heading | Action |
| Action | Action |
| Character | Dialogue |
| Parenthetical | Dialogue |
| Dialogue | Action, or **Character** on a second Enter (see below) |
| Transition | Scene heading |
| Lyric | Lyric |
| Centred, Section, Synopsis, Note, Page break | Action |

The block Enter creates is **not** pinned. It is empty, so there is nothing to
pin yet, and leaving it open is what lets the first thing typed into it be
recognised.

**Double-Enter after a speech.** Enter at the end of a line of dialogue leaves an
empty Action block. Enter again there turns *that block* into a character cue
rather than creating another empty paragraph — which is the "or Character on
double-Enter" of §Phase 3, and the fast path for a back-and-forth exchange. It is
a fact about the block (empty, unforced action, under dialogue) rather than a
memory of the previous keystroke, so there is no hidden state to get out of step.

A selection is replaced first, and the whole keystroke — delete, split, kind
change — is **one** undo step.

---

## Tab

Tab moves to the next element type available where the caret is. Shift+Tab moves
back. Where the table says nothing, Tab does nothing at all: it is not a refusal,
there is no beep, and the focus never leaves the document.

| Current element | Tab | Shift+Tab |
| --- | --- | --- |
| Action | Character | — |
| Character | Parenthetical | Action |
| Dialogue | Parenthetical | — |
| Parenthetical | — | Character under a cue, Dialogue otherwise |
| Scene heading, Transition | — | — |
| Centred, Lyric, Section, Synopsis, Note, Page break | — | — |

Tab is a two-step toggle rather than a longer ring, and §Phase 3's baseline table
is what fixes that: it gives Tab an answer for Action, Character and Dialogue and
a dash for Scene heading, Parenthetical and Transition. A ring would have to
invent answers for the dashes. Shift+Tab is the exact inverse; the one ambiguity —
two rows lead to a parenthetical — is settled by what the parenthetical is
attached to.

Tab **pins** the type it sets, for the same reason the digits do: you asked.

In Phase 5, Tab in a character cue accepts the completion if one is showing, and
falls through to this table if not. §Phase 3's row reads "accept completion, else
Parenthetical"; Phase 3 implements the *else*.

### The cue workflow

The reason Action → Character is on Tab and not automatic: a cue is only a cue
when something speaks under it (§4.1), and an all-capitals line with a blank line
below it is a line of action. So typing a name and expecting a cue cannot work
until the dialogue exists. Instead:

    JOHN            type the name
    Tab             it becomes a Character cue, pinned
    Enter           a Dialogue block appears
    Tab             …or make it the parenthetical first
    (quietly)
    Enter           and back to dialogue
    It came.        speak

Tab changes the type of the block the caret is **in**; it does not create one.
The parenthetical above is the empty dialogue block Enter just made, turned into
a parenthetical before anything was typed into it.

When the name is one the script already uses, the element bar says so —
`Tab: Character — JOHN` — which is §Phase 3's "typing an existing character name
in an Action-position block suggests Character". It is a suggestion. Nothing
changes until Tab.

A parenthetical typed as the *first* thing in a dialogue block needs no key at
all: `(quietly)` in dialogue position is a parenthetical by §4.1, and automatic
classification says so.

---

## Editing

| Key | Action |
| --- | --- |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z`, `Ctrl+Y` | Redo |
| `Ctrl+X` | Cut, as Fountain |
| `Ctrl+C` | Copy, as Fountain |
| `Ctrl+V` | Paste, as Fountain-aware blocks |
| `Ctrl+Shift+V` | Paste as plain text — Action blocks, nothing inferred |
| `Ctrl+A` | Select all |
| `Backspace` | Delete backwards; at offset 0, join to the block above |
| `Delete` | Delete forwards; at the end, pull the next block up |
| `Ctrl+Backspace` | Delete the word before the caret; at offset 0, join to the block above |
| `Ctrl+Delete` | Delete the word after the caret |

## Files

| Key | Action |
| --- | --- |
| `Ctrl+S` | Save |
| `Ctrl+Shift+S` | Save as… |

Both are also in the command palette, along with "Previous versions…".

There is no key for "open" or "new": both need a path, so both are a dialog
either way, and the library is one Escape and one click away.

`Ctrl+S` on a script that has never been saved asks where to put it. A save that
fails says why — read-only, no permission, full disk each get their own sentence
— and offers Save As, blocking, in a dialog that cannot be clicked away. §Phase 4
requires exactly that, and the reason is that a toast is a thing a writer scrolls
past.

Saving by hand is a habit, not a requirement: autosave writes two seconds after
you stop typing and every thirty seconds while you do not, and every edit in
between is already in a crash-recovery record on disk.

## Moving

| Key | Action |
| --- | --- |
| `←` `→` | One grapheme cluster, across block boundaries |
| `Ctrl+←` `Ctrl+→` | One word; stops at the end of a block before crossing it |
| `↑` `↓` | One visual line |
| `PageUp` `PageDown` | One screen |
| `Home` `End` | Start and end of the visual line |
| `Ctrl+Home` `Ctrl+End` | Start and end of the script |
| `Shift` + any of the above | Extend the selection |

A word is a run of letters, digits, marks, `_` and the apostrophe, so `café` is
one word and so is `don't`. Word-wise motion stops at the end of a block rather
than carrying on into the next one: stopping there is what makes `Ctrl+→` a way of
getting *to* the end of a paragraph.

## The mouse

The exit criterion for this phase is that you never need it. It still works.

| Action | Effect |
| --- | --- |
| Click | Place the caret |
| Double click | Select the word |
| Triple click | Select the whole element |
| Drag | Extend the selection; held against an edge, it scrolls |
| Shift+click | Extend the selection to the click |

## Panels

| Key | Action |
| --- | --- |
| `Ctrl+K` | Command palette — every element type and every command, searchable |
| `Ctrl+F` | Find and replace |
| `Ctrl+G` | Find next |
| `Ctrl+Shift+G` | Find previous |
| `Escape` | Dismiss the open panel; with none open, drop the selection |

At most one panel is open at a time. Two panels would both want Escape and both
want the focus, and neither question has a good answer.

Inside the find bar, `Enter` and `Shift+Enter` step through the matches.

Inside the palette, `↑` and `↓` move the highlight and `Enter` runs it.

### Escape

`Escape` never changes the document. With a panel open it closes it; with nothing
open it collapses the selection to its focus. It is not a deletion, it is not
"revert", and it does not cancel an edit already applied — undo is for that. This
is §Phase 3's "Escape dismisses completion / palette / dialog, and never loses
text", and it is why both panels are children of the editor page rather than
routes or dialogs: closing one is `setState`, and the document is not involved.
