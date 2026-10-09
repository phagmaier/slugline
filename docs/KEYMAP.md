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

These bindings are stable for 1.0, and
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

Setting a type this way pins it for the current editing session (ADR 0059).
Two consequences worth stating out loud:

* **It suppresses automatic re-classification.** Pressing `Ctrl+2` immediately
  after the editor promoted a line to a scene heading reverts it *and* keeps it
  reverted, however much more of that slug line you type.
* **Saving preserves syntax, not redundant pins.** A naturally recognized heading,
  uppercase cue with dialogue, transition or ordinary Action needs no extra
  `.`, `@`, `>` or `!`. A marker remains wherever Fountain requires one, including
  mixed/lowercase cues and forced lowercase extensions, orphan cues and Action
  text resembling another element.
  The element bar's pin stays live through Save; after reload source syntax is
  authority, with no hidden pin cache.

Your text and capitalization are always stored as authored, never automatically
uppercased. A deliberately typed Character named `McCLANE` or `mary` needs `@`.
Forced cues retain authored case in editor, preview and PDF (ADR 0060);
`@` is also necessary when an authored extension would otherwise change case
on reopen. Type `MCCLANE` or `MARY` for an uppercase cue.
Unedited explicit markers remain byte-exact until that block is edited.

**Dual dialogue:** on a Character cue, `Ctrl+K` → “Toggle dual dialogue” flips
the cue's flag without changing its text or selection. The marked cue's element
bar says “Dual dialogue”; undo/redo restores the flag. There is no dedicated
shortcut. The cue serializes with a trailing `^`, but do not type that marker
into its text. It pairs with the immediately preceding speech when both have
a body and no intervening element; an unmatched flag prints normally.

**Scene numbering:** `Ctrl+K` → “Number scenes” numbers all Scene headings
from 1 in document order, replacing existing Fountain `#12A#` numbers.
“Remove scene numbers” removes recognised trailing number suffixes. Each
command is one undo/redo step, including selection restoration. They preserve
heading words, element kinds and flags; removal consumes at most one separating
ASCII space, retaining other whitespace. Already-numbered and already-unnumbered
scripts are not dirtied by a no-op command. Numbers are saved in Fountain and
printed according to the existing Scene numbers output setting. Save and export
never number a script automatically. Neither command has a dedicated shortcut.
**Omit and restore:** `Ctrl+K` → “Omit selection”, “Omit scene”, or
“Restore omitted text” (no dedicated shortcuts, ADR 0061). Selection omission
keeps exact partial character boundaries; a collapsed selection is refused.
Selection omission refuses existing read-only boneyards and selections leaving
an unclosed comment or nested-note opener in a visible remainder, without widening.
Scene omission follows Rust's existing scene-heading boundaries. Omitted text
is a read-only Fountain boneyard and is absent from preview/PDF. Restore uses
the boneyard under the caret or those intersecting the selection, returning
editable screenplay elements. Each gesture is one undo step, including the
directed caret/selection. Save/reopen retains the text and element semantics.
Changed neighboring text/semantics, damaged omission records, or fragments that
cannot safely round-trip refuse restoration without changing text. Undo the
context change before restoring; an unsafe record remains lossless and omitted.


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

**Shift+Enter** inserts a hard line break inside Action, Dialogue and Note,
keeping both lines in one element. In other kinds it follows the normal Enter
workflow. It replaces any selection and is one undo step, separate from typing
before or after it. Shift+Enter takes this editing meaning even when a completion
has been highlighted with Up/Down; plain Enter still accepts that completion.
An input-method newline continues to split elements. The command palette also
offers "Insert line break", and F1 lists the shortcut.

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
Parenthetical". Enter normally keeps its editing meaning and splits the block;
after Up/Down explicitly moves through the popup, Enter accepts that chosen item.
Escape dismisses and suppresses the highlighted item for the rest of the session.
Merely showing or automatically highlighting an item never changes text (ADR 0017).
Suggestions appear while typing or when explicitly requested with **Ctrl+Space**.
Opening a script, moving the caret, and undo/redo leave them closed. Cycling
forward into a character cue offers the cast, including an empty cue. Navigation
and focus loss dismiss the popup; Shift+Up/Down always extend the selection.
The list shows up to four candidates at a time and follows the keyboard highlight
(ADR 0041). The popup says how to accept or dismiss an item in its footer, because none of it was
guessable from the screen (ADR 0030). It is keyboard-only on purpose: clicking a
candidate places the caret in the text under the popup, as any other click on the
page does, and never accepts.

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
| `Ctrl+B` / `Ctrl+I` / `Ctrl+U` | Wrap the selection in bold / italic / underline Fountain markup |
| `Ctrl+Space` | Show suggestions at the caret, including the cast in an empty cue |
| `Backspace` | Delete backwards; at offset 0, join to the block above |
| `Delete` | Delete forwards; at the end, pull the next block up |
| `Ctrl+Backspace` | Delete the word before the caret; at offset 0, join to the block above |
| `Ctrl+Delete` | Delete the word after the caret |

Inline formatting is one undo step, retaining selection direction and selecting
the original content inside the new markers. Rust formats each selected block
and hard line without removing whitespace or changing element kinds. Empty,
whitespace-only, read-only or unsafe existing-markup selections are refused
without mutation. This is wrapping, not a toggle. Dim half-size markers remain
editable while the text uses its resolved face; wrapping counts printed width.

## Files

| Key | Action |
| --- | --- |
| `Ctrl+N` | New script… |
| `Ctrl+O` | Quick-open a library script, or Browse… |
| `Ctrl+W` | Back to the library |
| `Ctrl+S` | Save |
| `Ctrl+Shift+S` | Save as… |
| `Ctrl+P` | Preview and export… |
| `Ctrl+,` | Preferences |
| `Ctrl++`, `Ctrl+-` | Increase or decrease editor text size |
| `F1` | Keyboard shortcut reference |
| `F11` | Distraction-free full screen |

New, Open, Import FDX, Back to the library, Save, Save as and Preview are also in
the command palette, along with "Previous versions…" and "Title page…".
Preferences, Spell checking, Keyboard shortcuts, navigator visibility,
distraction-free mode, page/continuous view and text-size changes are there too.
View entries name the action available now: "Hide navigator", "Leave
distraction-free mode", or "Use continuous view" when those modes are active.
Text-size changes stop at 12 and 24. In distraction-free mode, leave it first
to show the navigator. In narrow windows "Show navigator" opens the temporary
drawer; `Ctrl+K` closes it and focuses the palette without changing the saved
docked preference. Debug builds also offer "Pagination debug" when output is
attached.

`Ctrl+O` opens a searchable recent-script list. Type to filter by title or path,
use `↑` / `↓` to select, and `Enter` to open. The last entry, "Browse…", opens
the file chooser and remains available even when no scripts match. `Escape`
closes either chooser without changing the draft. `Ctrl+N` asks where to create
the new script. Choosing the current script in quick-open keeps its session and
undo history.

New, Browse, Import FDX, Save As, Rename and Export use GTK's local file dialog,
with system bookmarks, search, keyboard navigation and folder creation.
File dialogs start beside the current script when one is open; otherwise they remember the last
accepted folder during this launch, falling back to home. Fountain/FDX/PDF/font
filters have an All files choice. Extensionless save names gain the selected
format's extension. GTK does not ask about replacement: Save As and Export
still ask once in Slugline after the core refuses an occupied destination.
Preferences uses the same dialog for a TrueType font or a backup folder.

The library focuses its search field when it opens. Typing filters by title or
path, `↑` / `↓` selects a row, and `Enter` opens it; a missing file cannot be
opened. New and Open work there too. Leaving an editor through New, Open or
`Ctrl+W` always checks unsaved changes with the same Save / Discard / Cancel
dialog as the back arrow. Input and autosave are held during that action, and
the current session stays open until the destination has loaded successfully.
These keys also work in distraction-free mode.

**Import FDX…** is also a library button. It decodes an isolated candidate
before asking to close the current script. Cancelling the chooser, conversion
warnings or unsaved-changes prompt keeps the current editor untouched; decode
failure is reported without closing it. An accepted import is a new, unsaved
Fountain script with no binding to its source FDX. Save asks for a Fountain
destination, and the source is never watched, autosaved or library-indexed.

`Ctrl+P` opens the pages as they will print, with PDF, Fountain copy and FDX copy
exports inside it. **An export is not a Save As.** Each writes a file somewhere
else. Only Save As makes the writer's session follow it there — after an export the
script is still the script it was, with its own path, its own journal and its own
unsaved changes (ADR 0029). The core refuses a destination that is already there
until it is asked twice, and refuses a script this application has open outright.
FDX copies convert screenplay content, not exact production revisions, locked
pages, fonts or margins. Review conversion warnings before a copy is written.
Approval applies only to that document revision: changed content requires a new
warning prompt. Cancelling approval writes nothing, and a write failure is shown
even when conversion warnings were accepted.

The preview opens on the page the caret is on, from the key, the palette and the
toolbar alike. The page is looked up in the pagination the preview is about to
draw, by the caret's own wrapped line, so a paragraph that crosses pages opens on
the page the caret's line prints on. A caret in something that prints nothing —
a note, a synopsis, a section — opens where the text above it ends. Page 1 opens
at the top, title page included. It happens once, as the preview opens: changing
the paper or the preview size afterwards is not a reason to go back there.

`Ctrl+S` on a script that has never been saved asks where to put it. A save that
fails says why — read-only, no permission, full disk each get their own sentence
— and offers Save As, blocking, in a dialog that cannot be clicked away. §Phase 4
requires exactly that, and the reason is that a toast is a thing a writer scrolls
past.

Saving by hand is a habit, not a requirement: autosave writes two seconds after
you stop typing and every thirty seconds while you do not, and every edit in
between is already in a crash-recovery record on disk.

Previous versions do not require a manual-save habit either. Autosaves snapshot
changed text at most every ten minutes, comparing it with the newest saved
version. Opening a script preserves its changed on-disk starting text, including
a baseline when there are no previous versions yet. Saving explicitly records a
version every time: even a clean `Ctrl+S` after autosave keeps that version.
Snapshots are best effort; an unavailable backup cache does not fail opening or
saving the script.

Open “Previous versions…” from the overflow menu or command palette. **View**
shows selectable, read-only Fountain text, including the title page and literal
markup; **Back** returns to the list. **Open as copy…** asks for a new filename,
saves the exact viewed text and opens it in a separate Slugline window. Existing
files and open scripts are refused: choose another name, rather than replacing
them. The original script, unsaved edits and crash record stay where they were.
If the new window cannot start, the dialog names the saved copy and offers
**Open saved copy** to retry without writing it again. **Restore** remains the
way to replace the current script, after backing up its current text first.

Retention combines the newest N versions, the newest version in each UTC-hour
bucket across the current hour and the previous 23 hours, and M daily versions.
The defaults are N = 10 and M = 7. Overlapping versions count only once, so these
tiers retain at most N + 24 + M copies. Rapid manual saves cannot evict every
earlier hour, though a newer copy can replace an older one within the same hour.

## Moving

| Key | Action |
| --- | --- |
| `←` `→` | One grapheme cluster, across block boundaries |
| `Ctrl+←` `Ctrl+→` | One word; stops at the end of a block before crossing it |
| `↑` `↓` | One visual line |
| `PageUp` `PageDown` | One screen |
| `Home` `End` | Start and end of the visual line |
| `Ctrl+Home` `Ctrl+End` | Start and end of the script |
| `Ctrl+L` | Go to an output page by number |
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
| `Ctrl+J` | Show the navigator and focus its scene quick-jump filter |
| `Escape` | Dismiss the open panel; with none open, drop the selection |

At most one panel is open at a time. Two panels would both want Escape and both
want the focus, and neither question has a good answer.

Inside the find bar, `Enter` and `Shift+Enter` step through the matches.
While the bar is open every match on screen is tinted, and the one the caret is
on is the selection. Closing the bar takes the tint away; `Ctrl+G` still walks
the same matches.

Opening Find with text selected inside one element, on one line of it, searches
for that text. The toggles and the element filter stay as they were. With no
selection, or one that crosses elements or a line break, the last search
resumes — as it does when the selection is the match that search stopped on.
The opening query is selected in the find field, so typing replaces it. Move
the caret first (for example with `→`) to amend it instead.

Inside the palette, `↑` and `↓` move the highlight and `Enter` runs it.

“Go to page…” is also in the palette. Enter a page number and press `Enter` or
choose Go; `Escape` cancels and returns to the script. Page 1 is the document
start, including any opening notes or other source-only elements. Later pages
place the caret at their first source line from the last paginated snapshot,
in continuous view or page view. Until a snapshot is available, no jump is made.
The title page is not part of the script's page numbering.

In windows narrower than 900 logical pixels, the navigator opens temporarily
over the editor and closes when you choose any outline row or character.
Wider windows keep the saved docked-sidebar preference.

`Ctrl+J` also returns from Characters to Scenes and focuses the scene filter
after a navigator tab click. Type the scene query, then press `Enter` to jump;
the query never becomes screenplay text. Modal dialogs retain their own input
focus rather than activating the editor's page shortcuts.

Inside the navigator, typing filters the current Scenes or Characters list,
`↑` and `↓` move the highlight, and `Enter` jumps. Clicking a scene or accepting
one from the keyboard places the caret at its heading; clicking a character
jumps to its next cue. `Ctrl+J` uses the quick-open shape Phase 8 calls
"`Ctrl+P`-style"; the literal `Ctrl+P` remains Preview and export from Phase 7.

Scenes includes the source-ordered outline: nested `#` sections, `=` synopses,
and scene headings. Every row jumps to its own source block. Searching keeps
matching rows and their parent sections; a matching section or synopsis also
shows its descendants. Quick scene search initially highlights the first
matching scene, not a contextual section. Arrow keys can reach every outline
row, including pre-scene synopses and sections with no scenes. Only scenes
have drag handles or move commands; clear the filter to reorder.

Scene metadata is `p. N · E/8 p`: the actual starting screenplay page and
occupied length rounded up to eighth-pages. On each printed page, the scene
contributes the band from its first occupied row to its last, including internal
spacing and continuation furniture but not surrounding blanks. Bands are summed
before rounding; scenes sharing a page each contribute their own band. Title
pages never count. `p. … · length …` means current Rust pagination is pending,
not an estimate.

### Escape

`Escape` never changes the document. With a panel open it closes it; with nothing
open it collapses the selection to its focus. It is not a deletion, it is not
"revert", and it does not cancel an edit already applied — undo is for that. This
is §Phase 3's "Escape dismisses completion / palette / dialog, and never loses
text", and it is why both panels are children of the editor page rather than
routes or dialogs: closing one is `setState`, and the document is not involved.
