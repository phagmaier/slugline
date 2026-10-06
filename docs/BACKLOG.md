# Slugline backlog

A working list of fixes and improvements, in the order they are worth doing.
It comes from a whole-product review of version 1.0.2 at commit `b868f05`
(2026-10-06). The goal behind it: make Slugline good enough to replace a paid
screenwriting service for one writer on Linux.

Every item was checked against the app as it was at that commit. Items say how:
**reproduced** means something was run and the wrong result observed;
**read** means the behaviour follows from the code and was not exercised.
Line numbers are from that commit and will drift — search for the named symbol.

## How to use this file

For whoever (or whatever) picks up an item:

1. Take the first unticked item that is not **blocked**, unless told to take a
   specific one. One item per change. An item is blocked when its section carries
   a `**Blocked by XN.**` line and its checklist line says `— *blocked by XN*`;
   skip it and take the next, rather than starting it and stopping. If you find
   one blocked while working it, add both notes and move on. An item that unblocks
   another says so on its own checklist line — `— *unblocks XN*` — so the
   dependency is visible from either end. `tools/check_docs.py` holds both to each
   other.
2. Read the item's section in full, then **reproduce the problem before changing
   anything**. If it does not reproduce, do not "fix" it: write what you found on
   the item's `Result` line and stop.
3. Follow `AGENTS.md` — its invariants and its verification commands apply to
   every item here. Where an item changes something an accepted ADR decided, add
   a superseding ADR in the same change; do not edit the old one.
4. The owner has delegated implementation choices and product decisions to
   agents. Do not wait for sign-off or ask the owner to choose between options.
   Use judgment, do any needed research or deliberation, and record the reason
   for the choice. Larger or uncertain items may need planning before coding;
   that planning is part of the work, not an approval gate.
5. Stay inside the item. If you notice something else, add a line under
   [Found along the way](#found-along-the-way) instead of fixing it.
6. When the work is verified: tick the item's box in the checklist and fill in
   its `Result` line with the date, the commit, and anything that turned out
   differently from what the item describes. Do not delete items. One item per
   commit, with the item's id leading the subject — see `AGENTS.md`. Tick the box
   once the commit exists, so the `Result` can name it; a ticked box whose
   `Result` still says "commit pending" is reported by `tools/check_docs.py`.

Effort: **S** is under a day, **M** a few days, **L** a week or more.

## Checklist

This is the only place boxes are ticked.

**1. Safety — do these first**

- [x] [S1](#s1) A second launch deletes a running session's crash journal
- [x] [S2](#s2) Autosave never writes a previous version
- [x] [S3](#s3) The title-page dialog fuses multi-line fields

**2. Small confirmed bugs**

- [x] [B1](#b1) Find's element filter cannot be reset to "Every element"
- [x] [B2](#b2) Page-view sheets are off-centre and clip on the left
- [x] [B3](#b3) README lists the wrong shortcuts and stale test counts
- [x] [B4](#b4) The native navigator test assumes a permanently docked sidebar
- [ ] [B5](#b5) Navigator tab clicks disable the scene quick-jump shortcut

**3. Fountain and output fidelity**

- [x] [F1](#f1) Common character-cue shapes are read as action
- [x] [F2](#f2) Emphasised centred, right-aligned and title lines are misaligned
- [x] [F3](#f3) The preview shows literal emphasis markers; heading weight differs between views
- [x] [F4](#f4) Consecutive lyric lines print double-spaced
- [ ] [F5](#f5) A `~` line under a cue prints its tilde
- [ ] [F6](#f6) Page 1 carries a page number
- [ ] [F7](#f7) `@McCLANE` prints as `MCCLANE` — *blocked by X6*
- [ ] [F8](#f8) Incremental repagination is not proven equal to a full one
- [ ] [F9](#f9) Cold start, idle CPU and RSS are budgets nothing measures

**4. Everyday workflow**

- [ ] [W1](#w1) Switching scripts needs the mouse: no new, open or close shortcuts
- [ ] [W2](#w2) The command palette is missing commands
- [ ] [W3](#w3) No way to type a line break inside an element
- [ ] [W4](#w4) No "go to page"
- [ ] [W5](#w5) The preview always opens at page 1
- [ ] [W6](#w6) A GTK title bar is stacked above the app's own bar on Hyprland
- [ ] [W7](#w7) The file chooser is minimal — *choose A or B yourself*
- [ ] [W8](#w8) Find highlights only the current match
- [ ] [W9](#w9) Previous versions can be restored but not looked at
- [ ] [W10](#w10) Slugline is not installed on the owner's machine

**5. Larger features — plan and use judgment where needed**

- [ ] [X1](#x1) Dual dialogue
- [ ] [X2](#x2) Final Draft (FDX) import and export
- [ ] [X3](#x3) Scene numbering commands
- [ ] [X4](#x4) Emphasis that wraps by printed width and is styled in the editor
- [ ] [X5](#x5) Outline in the navigator
- [ ] [X6](#x6) Cleaner Fountain on disk (fewer `@`, `.`, `!` markers) — *unblocks F7*
- [ ] [X7](#x7) Omit and restore (editable boneyard)

---

## 1. Safety

<a id="s1"></a>
### S1 — A second launch deletes a running session's crash journal

**Problem.** With a script open, starting another Slugline — `slugline
other.fountain`, or double-clicking a file — removes the first session's crash
journal from disk. The first session keeps appending to the deleted file and is
never told, so a crash after that loses everything since its last save. If the
first session has unsaved journalled edits instead, the second launch offers
them as a "crash recovery": Discard deletes the live journal, Recover opens a
second copy of the document. The app holds one script per window, so a second
window is the natural way to look at another script.

**Evidence (reproduced with the 1.0.2 release build).**
- `recovery_pending` (`crates/bridge/src/api/files.rs:1811`) scans every
  `*.log` in the journal directory at startup and deletes any with no records
  (`:1828`). Nothing checks whether the journal's owner is still running.
- The runner registers `G_APPLICATION_NON_UNIQUE`
  (`app/linux/runner/my_application.cc:336`), so every launch is a new process.
- `Journal` keeps its file open for the session
  (`crates/storage/src/journal.rs:217`), so `append` and `checkpoint` go on
  succeeding against the unlinked file.
- Observed: instance 1 open, journal `<id>.log` present. Start instance 2 on a
  different script. The file is gone from the directory and
  `/proc/<pid1>/fd` shows `…/journal/<id>.log (deleted)`.
  See [recipe 3](#recipes).

**Change.** Make a live journal distinguishable from an abandoned one without a
lock file that could outlive a crash: hold an advisory lock on the open journal
file for the life of the session (the kernel drops it when the process dies).
The startup scan, `recovery_accept` and `recovery_discard` (`files.rs:2028`)
must neither offer nor delete a journal another live process has locked.
Re-take the lock wherever the journal file is replaced — `Journal::rebuild_at`
renames a new file into place.

**Done when.**
- A test with two real processes (the kill test in
  `crates/bridge/tests/persistence.rs` is the pattern) shows: a live session's
  empty journal survives another process's startup scan; a live session's
  non-empty journal is not offered; a `SIGKILL`ed session's journal is still
  offered.
- Repeating the observation above leaves instance 1's journal on disk.

**Watch out.**
- `File::try_lock` in std needs Rust 1.89; the workspace declares
  `rust-version = "1.82"`. Either raise it or call `flock` through `libc`
  (already in the tree transitively; a direct dependency needs its line in
  `docs/DEPENDENCIES.md`).
- "No persisted lock files" is a project constraint. A lock on the journal
  itself satisfies it; a separate `.lock` file does not.
- Two instances opening the *same* script already end in "recovery record
  unavailable" for the second, because `Journal::create` refuses an existing
  file. Keep that.
- Making the app single-instance is a different change and not part of this.

**Effort.** S–M.
**Result:** 2026-10-06 — verified in `c1db1f9`. Reproduced recipe 3 with release processes and isolated
`/tmp` XDG roots: launch 2 removed launch 1's journal. Journals now hold
exclusive `libc::flock` locks; startup, accept and discard acquire ownership,
and atomic creation/replacement publishes an already locked inode. Rust 1.82
was the floor when this landed and the `libc` route was taken to stay under it;
the floor has since been corrected to 1.85, which `File::try_lock` (1.89) still
exceeds, so the decision stands. No separate lock file or single-instance
policy. ADR 0042 records
the ownership/publication trade-offs. The real bridge two-process regression
covers live empty/non-empty journals, direct and stale recovery decisions,
reload, save-time replacement, same-script refusal and two successive
`SIGKILL`s. Repeated recipe 3 leaves both `.log` paths on disk; the first
descriptor matches its final journal's device/inode with link count 1 and
refuses a foreign lock. Its `/proc` label can name the unlinked temporary name
after hard-link publication, not a lost journal. Verification: 563 workspace
tests, clippy with warnings denied, formatting, layering/version checks,
508 Flutter tests, Flutter analysis, binding regeneration and the rebuilt
Linux release smoke all passed. Persistence fixtures serialize simulated
sessions to avoid subprocess forks briefly inheriting other tests' journal
locks before exec.

<a id="s2"></a>
### S2 — Autosave never writes a previous version

**Problem.** "Previous versions" gains an entry only on Ctrl+S or Save As. A
writer who relies on autosave — which `docs/KEYMAP.md` tells them they can —
has no history at all. An accidental deletion that autosaves, followed by
closing the script, cannot be undone.

**Evidence (read; corroborated).**
- `doc_autosave` calls `write_document(handle, None, false)`
  (`crates/bridge/src/api/files.rs:903`); the third argument is `with_backup`,
  which gates `backup::write` (`:1115`). `doc_save` (`:545`) and `doc_save_as`
  (`:626`) pass `true`.
- Retention is "newest N copies plus the newest per day"
  (`crates/storage/src/backup.rs:197`).
- On the owner's machine `~/.local/state/slugline/` contains no `backups/`
  directory.

**Change.** Let autosaves snapshot too, throttled:
- on an autosave, write a backup when the newest backup of this script is older
  than an interval (suggested: 10 minutes) and the text differs from it;
- when a script is opened and its text differs from the newest backup, write
  one, so the state before the session is kept;
- explicit saves keep writing one every time.

Decide "older than" by comparing the clock with the newest backup's timestamp
(its file name), at the moment of the save. Extend retention so throttled
snapshots are not pushed out by a burst of manual saves — for example, also keep
the newest copy per hour for the last day. Update the dialog's empty-state
sentence (`app/lib/library/backups_dialog.dart:89`) and the "Saving by hand"
paragraph in `docs/KEYMAP.md`.

**Done when.** Tests show: an autosave-only session produces backups no closer
together than the interval; opening a changed file produces one; retention keeps
what the new rule says; an explicit save still always writes one; a failed
backup still does not fail the save.

**Watch out.** No timer may be added to the core — the comparison happens when
a save is already running. Backups go through `save_atomically`. They are a
cache: deleting them must cost only convenience.

**Effort.** S–M.
**Result:** 2026-10-06 — verified in `d487d5f`. Reproduced with an actual bridge smoke executable: opening
created no backup, autosave wrote edited bytes with `backup: None`, and an
explicit dirty save created one. Autosaves now snapshot different saved bytes
when the newest filename timestamp is at least ten minutes old; opening keeps
different on-disk starting text without an age gate, including a first baseline
when the cache is absent. Explicit saves snapshot every time, including clean
Ctrl+S after autosave. No core timer, new preference, index or dependency.
ADR 0043 supersedes only ADR 0014's no-autosave-backup decision.
Retention adds the newest copy in each of the current and previous 23 UTC hours
to the existing newest-N and daily-M tiers: bounded recent history survives
manual-save bursts, though a newer copy can replace one within the same hour.
Same-millisecond snapshots now sort by numeric suffix and keep increasing that
suffix after pruning, so comparisons and retention use the actual newest copy.
Deterministic coverage includes exact interval boundaries, unchanged text,
manual-save age resets, clock rollback, missing/unreadable caches, hourly/daily
retention and same-millisecond bursts. Bridge coverage proves changed/identical
opening, throttled autosaves, clean explicit saves/Save As, and backup failures
that leave opening and saving successful. The post-change executable exercised
those open/save paths; a Linux dialog smoke visually verified the new empty
state. Throwaway harnesses were removed. Verification: 579 workspace tests,
clippy with warnings denied, Rust formatting, layering/version checks, binding
regeneration, Flutter analysis, 508 Flutter tests and all 16 Linux persistence
integration tests passed.

<a id="s3"></a>
### S3 — The title-page dialog fuses multi-line fields

**Problem.** Editing any multi-line title-page value except Notes joins its
lines together. Multi-line Title, Author and Contact are ordinary Fountain.

**Evidence (reproduced in a widget test).**
- `_box(key, label, hint, multiline: key == 'Notes')`
  (`app/lib/editor/title_page_dialog.dart:116`) gives every other field
  `maxLines: 1` (`:157`). Flutter's single-line field strips every `\n` from the
  whole value on the first edit.
- A Contact of `Next Level Productions\n1588 Mission Dr.\nSolvang, CA 93463`
  plus one typed character became
  `Next Level Productions1588 Mission Dr.Solvang, CA 934630`.
- The core is fine with multi-line values: `canonical_title_page`
  (`crates/fountain/src/serialise.rs:203`) writes continuation lines indented.

**Change.** Every title-page field accepts several lines (one line tall until it
needs more), and Enter inserts a line break. Optional, same dialog: a way to add
a key that is not in the form.

**Done when.** A widget test edits a three-line Contact and the value committed
to the core still has three lines. Add a Rust round-trip test for a multi-line
value if one is not already there.

**Watch out.** Fields commit on focus loss and on dialog dispose — keep both.
Title-page edits already go through `doc_set_title_field` and the journal
(ADR 0033); nothing changes there.

**Effort.** S.
**Result:** 2026-10-06 — verified in `3a5dcd8`. Reproduced the newline loss in the Contact field, then changed every
title-page field, including additional keys, to accept newlines and grow from
one line as needed. The regression widget test preserves a three-line Contact
after editing; the existing Fountain multi-line canonical round-trip test also
passes. All seven title-page widget tests passed, including focus-loss and
dialog-dispose commits.

---

## 2. Small confirmed bugs

<a id="b1"></a>
### B1 — Find's element filter cannot be reset to "Every element"

**Problem.** After restricting Find to one element type, choosing "Every
element" does nothing. The filter is remembered when the bar is reopened, so
Find stays restricted until the script is closed.

**Evidence (reproduced in a widget test).** The menu is a
`PopupMenuButton<BlockKind?>` whose "Every element" item has `value: null`
(`app/lib/editor/find_bar.dart:309`). Flutter treats a null result as a
dismissal and calls `onCanceled`, never `onSelected`. After choosing Dialogue
and then Every element, the last query still had `kinds == [dialogue]`. The
existing tests only ever restrict.

**Change.** Give "Every element" a non-null value.

**Done when.** A test in `app/test/editor/find_replace_test.dart` restricts,
then resets, and the query's `kinds` is empty.

**Effort.** S.
**Result:** 2026-10-06 — verified in `40b1f1c`. Reproduced with a visible menu-item click: Dialogue → Every element
left `kinds == [dialogue]`. Popup selections now use non-null typed records,
including the unrestricted choice, without changing the nullable filter or
Rust query contract. The widget regression covers reset, cancellation and
close/reopen persistence. A native Linux smoke against the real Rust core
observed three matches → one Dialogue match → three matches after reset and
reopening; the test double's simplified search remains unchanged.

<a id="b2"></a>
### B2 — Page-view sheets are off-centre and clip on the left

**Problem.** In page view (the default) the sheet of paper sits left of centre
at every window width. In a narrow window — half a screen on a tiling desktop,
or any window with the navigator open — its left edge is off-screen and a strip
of bare background shows on the right. `githubAssets/editor.png` shows it.

**Evidence (reproduced with the app's own geometry classes, text size 15).**

| Editor width (px) | Fitted font size | Gap left of sheet | Gap right of sheet |
| ---: | ---: | ---: | ---: |
| 640 | 11.73 | −20.5 | 62.7 |
| 812 | 14.88 | −19.5 | 73.1 |
| 900 | 15.00 | 21.3 | 114.2 |
| 1280 | 15.00 | 211.3 | 304.2 |

`columnLeft` (`app/lib/editor/page_geometry.dart:72`) centres the 60-column
text column in the viewport less the 48 px scrollbar strip, and `sheetLeft`
(`:83`) hangs the sheet 1.5 inches to its left. The sheet's margins are 1.5 and
1 inch, so centring the text does not centre the sheet. `fittedFontSize`
(`app/lib/editor/metrics.dart:118`) sizes the script for "sheet plus a quarter
inch each side", which the geometry then does not honour.

**Change.** When page view is on, centre the sheet and place the text column
inside it. Key this on the `pageView` preference rather than on whether sheets
are drawn yet, so nothing shifts when the first pagination arrives. Continuous
view stays as it is.

**Done when.** `app/test/editor/page_geometry_test.dart` asserts, across widths
from the 800 px minimum window up to a wide one, that the sheet's left gap is
never negative and the two gaps differ by no more than the scrollbar reserve;
and that a click still maps to the cell it lands on.

**Watch out.** Every row-or-column-to-pixel conversion goes through
`EditorGeometry` — painting, hit testing, caret scrolling, semantics, the
completion popup. Change the geometry, not the callers.

**Effort.** S.
**Result:** 2026-10-06 — verified in `40b1f1c`. Reproduced at editor width 800 and preferred text size 15: sheet gaps
were −19.60/72.35 px. `EditorGeometry` now centres the sheet inside the scrollbar
reserve, then places the text inside its left margin, keyed on `pageView` rather
than pagination readiness. Continuous placement, font fitting and vertical
pagination are unchanged; existing column bounds still protect extremely narrow
viewports. Fitted-metrics regressions cover widths 640–3840, preferences 15/24,
first-snapshot stability, continuous placement and narrow/fallback bounds, with
a widget caret-hit regression. Native visual/click smoke passed at widths 800,
1280 and 991 with the navigator docked; the 800 px sheet gaps are now
2.37/50.37 px. The narrow navigator drawer and rebuilt release were also checked.

<a id="b3"></a>
### B3 — README lists the wrong shortcuts and stale test counts

**Evidence (read).** `README.md:53` gives Ctrl+Shift+P for the command palette
and `README.md:154` gives Ctrl+Shift+E for PDF export. The real keys are Ctrl+K
and Ctrl+P (`docs/KEYMAP.md`). Ctrl+Shift+E does nothing, and Ctrl+Shift+P opens
the preview because `_onPageKey` ignores Shift for that key
(`app/lib/editor/editor_page.dart:525`). `README.md:215–219` quotes 553 Rust,
457 Dart and 56 integration tests; at the review there were 554 and 508.

**Change.** Correct the shortcuts. Drop the counts or make them not need
maintaining.

**Effort.** S.
**Result:** 2026-10-06 — verified in `40b1f1c`. Confirmed README drift against `docs/KEYMAP.md` and the keyboard
handlers. The README now gives Ctrl+K for the palette and describes Ctrl+P as
opening Preview and export, where PDF export is selected; test totals were
removed rather than repinned. Native smoke and the rebuilt release both opened
the documented surfaces with those keys. Batch verification: 524 Flutter tests,
Flutter analysis, 579 Rust workspace tests, clippy with warnings denied, Rust
formatting, layering/version checks and the Linux release build passed.
Temporary reproduction/native-smoke harnesses were removed. Native smoke used
the current display because `xvfb-run` is unavailable; the full Linux integration
suite was not run.

<a id="b4"></a>
### B4 — The native navigator test assumes a permanently docked sidebar

**Problem.** The full Linux integration gate stops at the navigator assertion
in `app/integration_test/writing_test.dart`, before reaching its remaining files.

**Evidence (reproduced during F3 verification).** The native test opens an
`EditorPage` with `navigatorVisible: true` and immediately expects `HOUSE`.
The narrow window instead uses ADR 0041's temporary, initially closed drawer:
the saved preference governs docking in wide windows, not opening a drawer.
The existing responsive widget tests already exercise explicit drawer opening.

**Change.** Open the navigator through Ctrl+J before asserting on its rows.
Wait for drawer animations, retain the real-core scene/character assertions,
and check that filtering to `street` removes `HOUSE` before Enter jumps.
Do not change application navigation to satisfy a stale fixture.

**Done when.** All 12 native writing tests and the full seven-file Linux
integration gate pass, including the navigator's actual keyboard interaction.

**Effort.** S.
**Result:** 2026-10-06 — committed as `B4 — the native navigator test opens the
compact drawer` (this commit), separately from F3. Confirmed the failure was a
stale fixture: `navigatorVisible` preserves the wide-window docked preference,
while ADR 0041 requires explicit opening of the narrow-window drawer.
The test now invokes Ctrl+J, waits for drawer transitions and retains its
real-core scene/character checks. Filtering to `street` must remove `HOUSE`
and leave `STREET` before Enter selects the correct block.
The actual native writing flow passed all 12 tests. The full
`tools/test_linux_integration.sh` gate passed all 57 tests across seven files;
the journalled keystroke p99 was 2.89 ms, within budget. All 529 Flutter tests,
17 targeted navigator/responsive-editor tests, Flutter analysis and
docs/version/layering/formatting checks passed. No application code, existing
ADR behavior, F3 implementation or output goldens changed.

<a id="b5"></a>
### B5 — Navigator tab clicks disable the scene quick-jump shortcut

**Problem.** On Linux with a docked navigator, opening it with Ctrl+J, clicking
Characters, then pressing Ctrl+J again neither switches back to Scenes nor
focuses the filter. Typing the scene query is ignored.

**Evidence (reproduced during F4 verification and diagnosed separately).**
The native writing suite failed its `STREET` visibility assertion. A temporary
real-core diagnostic on this machine's 1280 × 720 viewport observed the filter
lose focus to the route-level scope after Characters was clicked; the second
Ctrl+J never reached `EditorPage._onPageKey`. An isolated XDG root behaved the
same. The installed Flutter 3.44.8 / Dart 3.12.2 match the repository and CI
pins. Linux-mode widget tests reproduce the docked failure; Android-mode widget
tests and the compact drawer do not, because their focus behavior differs.

**Change.** Keep child-field unfocus inside an editor-owned focus scope instead
of the route's scope. Preserve the normal desktop unfocus behavior and child-first
key handling; do not force focus on tab clicks or bypass modal dialogs.

**Done when.** Ctrl+J returns from Characters to scene search in docked and
compact layouts; typing `street` filters to STREET and Enter jumps without
changing screenplay text. Modal-dialog input remains outside page shortcuts.
The native writing suite and full Linux integration gate pass.

**Effort.** S.
**Result:** _open_

---

## 3. Fountain and output fidelity

Samples in this section were rendered with [recipe 2](#recipes). Columns are
counted from the left edge of the text area.

<a id="f1"></a>
### F1 — Common character-cue shapes are read as action

**Problem.** A speech whose cue contains `#`, `&`, `/` or `,`, or has a
lowercase extension, is parsed as action together with its dialogue. Scripts
written elsewhere use these constantly, so an imported script comes in wrong.

**Evidence (reproduced).** Each of these rendered at column 0 with its line of
dialogue under it at column 0. Expected: cue at column 22, dialogue at 10.

```fountain
COP #1
Freeze.

MOM (on the phone)
Hello?

MR. & MRS. SMITH
Hello.

HANS/GRETEL
Hello.
```

`character_of` (`crates/fountain/src/syntax.rs:306`) accepts only letters,
digits, space and `. ( ) ' -`, and `is_all_caps` (`:330`) rejects any lowercase
letter, including inside a parenthesised extension. The Fountain syntax
reference defines a character as any line entirely in uppercase with a blank
line before it and a non-blank line after it, and says extensions may be upper
or lower case (`HANS (on the radio)`).

**Change.** Bring `character_of` in line with that: test capitals on the part
of the line outside any trailing parenthesised extension, and stop restricting
punctuation. Keep the `^` dual-dialogue suffix.

**Done when.** Parser tests cover the four shapes above. The round-trip,
tiling and stability tests stay green. Corpus goldens either do not change or
are regenerated on purpose, with the reason in the commit message.

**Watch out.** This rule has three callers — the parser, the serialiser and
`infer_kind` — and all three must agree (ADR 0011). Scene-heading and
transition rules are checked before it and must stay first. The existing test
that `JOHN, JR.` is *not* a cue encodes the old rule and needs changing
deliberately. `normalize_character` in `crates/document/src/entities.rs` feeds
autocomplete and the navigator and must cope with the new characters.

**Effort.** S–M.
**Result:** 2026-10-06 — verified in `e71b3be`. Reproduced with the PDF dump executable: all four examples and
`JOHN, JR.` printed with their dialogue at column 0. The shared recognizer now
accepts unrestricted punctuation and checks capitals only outside balanced
trailing parenthesised extensions, including stacked and nested groups; the
original cue text and `^` flag are retained. A name still needs an uppercase
letter outside its extensions, and lowercase in the name still requires `@`.
Scene-heading and transition precedence is unchanged. Removing the colon
restriction also makes `CUT TO:` followed immediately by speech a cue, as the
Fountain rule requires; inference now respects that non-blank-after context.
Regression coverage includes parser/serialiser/inference agreement, BOM/CRLF
byte-exact resaves, provenance tiling, cue-shaped action protection and invalid
extensions. Autocomplete and navigator regressions verify punctuation,
frequencies and occurrence IDs; `normalize_character` needed no change, and
ADR 0031's known-extension-only normalization remains intact. The post-change
PDF smoke's extracted coordinates prove cue column 22 and dialogue column 10
for all five examples. All 584 Rust workspace tests, clippy with warnings
denied, formatting and layering/version checks passed. Corpus layout and PDF
goldens and line-break fixtures are unchanged; no regeneration was needed.

<a id="f2"></a>
### F2 — Emphasised centred, right-aligned and title lines are misaligned

**Problem.** A centred or right-aligned line containing `*`, `**` or `_`
markers prints shifted left. It is most visible on the title page, where the
Fountain convention is `_**TITLE**_`.

**Evidence (reproduced).**

| Line | Centre it printed at | Expected |
| --- | ---: | ---: |
| Title `_**BRICK & STEEL**_` | column 26.5 | 30 |
| `> THE **END** <` | column 27.5 | 30 |
| Unemphasised title-page lines | column 30 | 30 |

The paginator aligns a row using its raw length, markers included
(`block_rows`, `crates/layout/src/engine.rs:937`; title page, `:1104`). The
renderer then draws the printed text from that column with the markers closed
up (`place`, `crates/render_pdf/src/lib.rs:274`). ADR 0032 records the effect.

**Change.** Compute alignment from the printed width — the row with paired
markers and escaping backslashes removed. `fountain::emphasis` already knows
which markers pair. Do it in `layout`, so the renderer still makes no layout
decision.

**Done when.** A PDF test in the style of
`crates/render_pdf/tests/element_indents.rs` shows an emphasised centred line
and an emphasised title centred to within half a column, and an emphasised
right-aligned transition ending at column 60.

**Watch out.** Layout goldens and PDF hashes change; regenerate them on purpose.
This item does not touch wrapping — that is X4. Check the layering script still
passes if `layout` needs emphasis scanning it cannot currently reach.

**Effort.** S–M.
**Result:** 2026-10-06 — verified in `5e8f8fe`. The actual PDF dump executable
and `pdftotext -bbox` reproduced the reported title centre at 26.5, centred
`THE **END**` at 27.5, and an emphasised transition ending at 56. After the
layout fix, both centres are 29.5 (within half a column of 30), and the
transition ends at 60. An emphasised draft date also ends at 60; escaped-marker
text centres at 30 and unpaired-marker text remains at 30.
`fountain::emphasis` now exposes count-only printed-width measurement using
its existing tokenisation and pairing, without allocating styled text.
Layout measures body rows together across wraps, title rows individually,
and leaves left-aligned placement and raw-width wrapping unchanged. ADR 0044
supersedes the alignment-only parts of ADRs 0019/0032; the direct
`layout -> fountain` edge is documented and enforced.
Three new finished-PDF coordinate regressions failed before and pass after;
they cover nested emphasis, escapes, unpaired markers, right-aligned draft
dates and pairing across wrapped body rows. All 588 Rust workspace tests,
clippy with warnings denied, formatting and layering/version checks passed.
Before regeneration, the corpus audit found only two changed title columns:
`05-title-page` and `reference-feature`, each moved three columns right.
Their dumped title centres are now 29.5 and 30 respectively. Two layout
goldens and their four Letter/A4 PDF hashes were deliberately regenerated;
all other layout coordinates, text, page breaks and PDF hashes are unchanged.
Line-break fixtures are unchanged. Flutter checks were not run; this change
does not implement preview styling (F3). Temporary smoke artifacts were
removed. Eventual commit-message note: "Layout goldens and PDF hashes changed
deliberately to align emphasised titles by printed width; wrapping and page
breaks are unchanged."

<a id="f3"></a>
### F3 — The preview shows literal emphasis markers; heading weight differs between views

**Problem.** The preview is presented as "the pages as they will print", but it
draws `*asterisks*` literally while the PDF styles them. Separately, the editor
draws scene headings bold and the PDF and preview draw them plain.

**Evidence (read).** `_PagePainter` paints `line.content` in one style
(`app/lib/preview/preview_view.dart:266`). The editor sets
`FontWeight.bold` for scene headings (`app/lib/editor/editor_surface.dart:1406`);
nothing in `layout` or `render_pdf` does.

**Change.**
- Have the bridge hand the preview each line's emphasis runs, computed by the
  same Rust code the PDF uses, and draw those. Dart must not reimplement
  emphasis.
- Make heading weight one decision. Suggested: an output option "Bold scene
  headings", off by default, which the PDF, the preview and the editor all
  follow. Choose the default based on screenplay conventions and product
  consistency; record the rationale.

**Done when.** A preview test shows an italic run drawn without its markers and
in the italic face; editor, preview and PDF agree on heading weight for both
settings of the option.

**Effort.** M.
**Result:** 2026-10-06 — committed as `F3 — preview and PDF share emphasis and
heading weight` (this commit). Reproduced before editing with actual preview
and editor paint regressions; the PDF dump executable printed regular headings
and italic body emphasis while the preview painted literal markers and the
editor used bold headings.
`render_pdf::emphasis_runs` now resolves output runs once per consumer with the
existing cross-wrap/cross-page block pairing, individually scanned title and
continuation rows, literal page-number/gutter furniture, escapes and unpaired
markers. The bridge carries resolved faces beside unchanged raw row content,
coordinates and source identity; Dart paints runs and never parses Fountain.
“Bold scene headings” is a persisted output option, off by default to preserve
existing printed output and regular uppercase-heading convention; bold remains
an explicit supported stylistic choice. Editor, preview and PDF follow its
base heading weight, while output inline bold remains additive. ADR 0045
supersedes only the output-interpretation restrictions of ADRs 0019/0032 and
extends ADR 0037. X4 wrapping and editor inline styling remain untouched.
Bundled-font pixel regressions prove marker-free italic painting, mixed
bold/italic/underline faces, scalar-grid advancement and both heading weights;
the editor regression observes actual painted styles and live repainting.
Rust regressions cover paragraph boundaries, heading options, cache separation
and finished PDF face operators without coordinate changes. The real Linux
preferences/preview/export UI exercised both settings through its PDF button;
Poppler extracted italic `quietly` and regular/bold headings, and screenshots
of the actual preview and rendered PDFs were inspected. Temporary screenshot
hooks were removed. Bridge bindings were regenerated, not hand-edited.
Verification: all 595 Rust workspace tests and 529 Flutter tests passed, as
did clippy with warnings denied, Rust formatting, layering/version/docs checks,
Flutter analysis, six complete native integration files, the serialized Linux
release build and headed network isolation. The journalled keystroke p99 was
3.49 ms, within budget. The full integration script is not wholly green:
`writing_test.dart` passed 11 tests but failed its narrow-window navigator
expectation; recorded under Found along the way and left outside F3.
A concurrent debug/release build failed to find `libapp.so`; after integration
finished, the serialized release build passed without a product-code change.
Default layout goldens, PDF hashes, line-break fixtures and page breaks are
unchanged; no golden regeneration was needed. F1/F2 and earlier work were
preserved.

<a id="f4"></a>
### F4 — Consecutive lyric lines print double-spaced

**Evidence (reproduced).** Three consecutive `~` lines printed on rows 5, 7 and
9. Each lyric line is its own block and `LYRIC_BLANKS_BEFORE` is 1
(`crates/layout/src/metrics.rs:94`). The editor mirrors it
(`app/lib/editor/metrics.dart`, the lyric entry).

**Change.** One blank line before the first lyric of a run and none between
consecutive lyric blocks, in both the paginator and the editor.

**Done when.** A layout test shows three consecutive lyrics on consecutive
rows; the editor draws the same; the line-break differential test passes.

**Watch out.** The editor's row count per block must keep matching the
paginator's, or page positions in the editor drift. Goldens and PDF hashes
change.

**Effort.** S.
**Result:** 2026-10-06 — verified in `2926725`. Reproduced consecutive lyrics at
24-point pitch in an exported PDF and failing paginator/editor regressions.
Both layouts now suppress the leading blank only after another lyric block;
new runs retain one blank and existing page-top suppression is unchanged.
Spacing is resolved from current order, including cached wraps and untouched
editor successors after predecessor changes/removal. ADR 0046 refines ADR 0034.
Regressions cover three consecutive rows, interludes, the last row before a page
break and predecessor edits/removal. The rebuilt release's editor and preview
were visually checked under Xvfb; Poppler measured a 12-point lyric pitch.
Unlike the expectation above, deliberately regenerated corpus layout goldens
and PDF hashes remained unchanged; the new regressions cover lyric runs.
Verification passed: 598 workspace tests (including line-break differential),
rustfmt, clippy with warnings denied, layering/version/docs checks, Flutter
analysis and 531 tests, Linux release build and network isolation. Native bridge,
editor, IME, persistence, export and keystroke suites passed. The writing suite's
separate navigator `STREET` visibility failure and optional formatter's existing
style differences are recorded under “Found along the way”; neither was changed.

<a id="f5"></a>
### F5 — A `~` line under a cue prints its tilde

**Evidence (reproduced).** `OOMPA LOOMPAS` followed directly by
`~Everybody give a cheer!` printed the line at the dialogue indent with the
tilde. The parser checks dialogue context before element markers
(`crates/fountain/src/parse.rs:267`), so the line is dialogue text.

**Change.** Decide what a sung line inside a speech is. Before changing
anything, check how the Fountain reference and two other implementations treat
it and record the answer here. The likely shape is a lyric that stays part of
the speech for page-break purposes and prints without its tilde.

**Watch out.** Lower confidence than the other items: the Fountain reference
does not spell this case out. If the investigation says the current behaviour
is defensible, close the item with that finding.

**Effort.** S to investigate; M if it becomes a change.
**Result:** _open_

<a id="f6"></a>
### F6 — Page 1 carries a page number

**Evidence (reproduced).** Page 1 prints `1.` at the top right. `push_page`
(`crates/layout/src/engine.rs:681`) numbers every page. The usual screenplay
convention leaves the first page unnumbered.

**Change.** A page-setup option for numbering the first page, off by default,
followed by the paginator, the preview, the PDF and the editor's page view.

**Done when.** A layout test shows no page-number line on page 1 by default and
one when the option is on; page 2 is still `2.`.

**Watch out.** Nearly every layout golden and PDF hash changes; regenerate on
purpose. Appearance preferences must not affect pagination — this is an output
setting and belongs with paper size and scene numbers.

**Effort.** S.
**Result:** _open_

<a id="f7"></a>
### F7 — `@McCLANE` prints as `MCCLANE`

**Evidence (reproduced).** Fountain's `@` exists to keep a cue's own
capitalisation. Slugline upper-cases every character block for display
(`layout_for`, `crates/layout/src/engine.rs:441`).

**Blocked by X6.** Slugline currently puts `@` on every cue made with Tab,
Ctrl+3 or double-Enter, and upper-cases cues for display only. Honouring `@`
today would make any cue the writer typed in lowercase print in lowercase.
Decide X6 first.

**Effort.** S once unblocked.
**Result:** _open_

---

<a id="f8"></a>
### F8 — Incremental repagination is not proven equal to a full one

**Problem.** `repaginate` reuses per-block fingerprints instead of laying the
document out again (ADR 0022). Nothing checks that its result equals what a full
`paginate_snapshot` of the same edited document would produce, so the fast path
rests on the hints being right rather than on a test. A wrong reuse surfaces as
a stale page count or a sheet boundary in the wrong place — the kind of defect a
writer finds after printing.

**Evidence (read).** ADR 0022 admits the gap and defers the test: "no test
compares `repaginate` of an edited snapshot against `paginate_snapshot` … ADR
0025's focused review should turn it into a test". That review is spent — the
plan holding its findings left the tree — and ADR 0025 now carries a
`Historical:` line naming this gap. `crates/layout/tests/incremental.rs` has two
tests, `one_edit_invalidates_one_block_and_reuses_a_checkpoint_prefix` and
`reference_pagination_is_identical_one_hundred_times`; neither compares the two
paths.

**Change.** A differential test over `testdata/corpus/`: paginate, apply an
edit, `repaginate`, and assert the incremental `PaginationView` equals a full
`paginate_snapshot` of the edited document — pages, rows and page breaks. Cover
what a fingerprint could plausibly get wrong: an edit that changes a block's
wrapped *height*, one that changes it within its height, an insert that pushes a
scene heading across a page boundary, and dual dialogue whose partner moves.

**Done when.** The test exists, runs over the corpus, and fails when
`repaginate`'s reuse is deliberately broken. Check that second half rather than
assuming it: a test that passes either way proves nothing.

**Watch out.** Do not make a failure go away by relaxing the comparison to page
count alone — a wrong page *break* with the right count is the defect. ADR 0022
owns the fingerprint design; if the test shows the hints are unsound, supersede
the record rather than widening a tolerance.

**Effort.** M.
**Result:** _open_

---

<a id="f9"></a>
### F9 — Cold start, idle CPU and RSS are budgets nothing measures

**Problem.** Three of the budgets in `docs/BUDGETS.md` have no test: cold start
to a blinking cursor (< 500 ms), idle CPU with the window focused (0%), and RSS
with the reference script open (< 250 MB). Those are the three a writer feels
without measuring anything — a slow launch, a fan on an idle machine, an editor
that grows until the desktop swaps — and the three nothing would notice
regressing. SPEC §1.3 set all three; only the budgets that got a harness
survived.

**Evidence (read).** `docs/BUDGETS.md` marks each as measured by nothing. The
other nine rows are enforced: `openBudgetMs` and `keystrokeBudgetMs` in
`app/integration_test/keystroke_benchmark_test.dart`, the repagination budgets in
`crates/layout/tests/pagination_is_fast_enough.rs`, parse and serialise in
`crates/fountain/tests/parse_is_fast_enough.rs`, export in
`crates/render_pdf/tests/export_is_fast_enough.rs`, and bundle size in
`.github/workflows/ci.yml`. `app/test/startup_test.dart` covers startup *logic*
and takes no timings.

**Change.** One release-mode harness over the built bundle at
`app/build/linux/x64/release/bundle` that:

- launches with an empty script and times from `exec` to the first presented
  frame;
- reads `/proc/<pid>/status` for `VmRSS` with the reference script open;
- samples `/proc/<pid>/stat` over a quiet interval for idle CPU, asserting no
  polling wakeups rather than a small percentage.

Run it from `tools/test_linux_integration.sh` or its own CI step, whichever
keeps a failure legible.

**Done when.** All three rows in `docs/BUDGETS.md` name a measurement, and each
fails when its property is deliberately broken. Confirm that second half rather
than assuming it: a timing test that cannot fail is the failure mode this item
exists to prevent.

**Watch out.** A shared runner's worst run is not the number that matters — take
a best-of-N the way the pagination tests do, and say so in the reason string.
Take frame time from the frame build callback, not wall clock: vsync quantises
wall clock to 16.7 ms, which is the floor rather than a cost (ADR 0005). Adding
production code so a benchmark can find its startup marker is the wrong trade;
measure what ships.

**Effort.** M.
**Result:** _open_

---

## 4. Everyday workflow

Everything in this section is **read** from the code unless it says otherwise.

<a id="w1"></a>
### W1 — Switching scripts needs the mouse: no new, open or close shortcuts

**Problem.** The only way to another script is the back arrow and then a click
in the library. There is no key for new, open or "back to the library", and in
distraction-free mode there is no bar to click either. The library list cannot
be driven with the arrow keys.

**Evidence.** `_onPageKey` (`app/lib/editor/editor_page.dart:508`) has none of
these keys. The library handles only F1 and Ctrl+,
(`app/lib/library/library_page.dart:177-188`) — typing already filters
(`Key('library-search')`, `library_page.dart:339`), but the list cannot be
walked or opened from the keyboard. `docs/KEYMAP.md` says "There is no
key for open or new".

**Change.**
- Ctrl+O: a quick-open panel listing library scripts with type-to-filter, plus
  a "Browse…" entry.
- Ctrl+N: new script. Ctrl+W: back to the library.
- Library: Up/Down moves the selection and Enter opens it. The filter field
  already exists; give it focus on open.
- Update `docs/KEYMAP.md`, the shortcuts dialog and the command palette.

**Done when.** Widget tests cover each key, and a test goes from the library to
a script, to another script, to a new script without a pointer event.

**Watch out.** Leaving a script always goes through `confirmClose`. At most one
panel is open at a time, and Escape never changes text.

**Effort.** M.
**Result:** _open_

<a id="w2"></a>
### W2 — The command palette is missing commands

**Evidence.** `editorCommands` (`app/lib/editor/commands.dart:32`) has no entry
for Preferences, Spell checking, Keyboard shortcuts, show/hide navigator,
distraction-free, page view versus continuous, text size, or back to the
library. The first three are in the overflow menu only.

**Change.** Add them, and anything W1, W3 and W4 introduce. The palette should
reach every command the app has.

**Effort.** S.
**Result:** _open_

<a id="w3"></a>
### W3 — No way to type a line break inside an element

**Problem.** Enter always starts a new element, so two lines of one action
paragraph — a list, an address, a sign, a text-message exchange — can only be
pasted in, never typed. Files that contain them display correctly.

**Evidence.** The Enter case in `_onKey`
(`app/lib/editor/editor_surface.dart:541`) calls `splitBlock` whatever the
modifiers. The core allows `\n` inside Action, Dialogue and Note
(`BlockKind::is_multiline`, `crates/fountain/src/model.rs:41`).

**Change.** Shift+Enter inserts a line break at the caret in those kinds. In
other kinds it behaves as Enter. Document it in `docs/KEYMAP.md`.

**Done when.** A widget test types two lines with Shift+Enter between them and
the saved Fountain has them adjacent with no blank line; undo removes the break
in one step.

**Watch out.** The edit must go through the controller's normal path so it is
journalled. A newline arriving from an input method must still split.

**Effort.** S.
**Result:** _open_

<a id="w4"></a>
### W4 — No "go to page"

**Problem.** Notes from readers arrive as page numbers. There is no way to jump
to page 47.

**Evidence.** No such command exists. The data does, with one edge:
`PageIndicator._firstLineOfPage` holds the first printable line of each page,
but `_resolvePageStarts` drops page 1 (`if (number <= 1) continue;`,
`app/lib/editor/page_indicator.dart:118`) — a page start is a page *break*, and
nothing breaks before the first page. So "go to page 1" has to mean "scroll to
the top", not a lookup that will find nothing. (The same exclusion is why a
one-page script draws no sheet furniture; that is logged under
[Found along the way](#found-along-the-way).)

**Change.** A "Go to page…" command in the palette, with a shortcut recorded in
`docs/KEYMAP.md`, that moves the caret to the first line of that page; page 1 is
the document start.

**Watch out.** The editor never decides where a page ends; use the paginated
snapshot, and do nothing rather than estimate when there is none yet.

**Effort.** S.
**Result:** _open_

<a id="w5"></a>
### W5 — The preview always opens at page 1

**Evidence.** `PreviewView` builds a `ListView` with no initial offset
(`app/lib/preview/preview_view.dart:82`), and `ExportDialog` is not told where
the caret is.

**Change.** Open the preview scrolled to the page the caret is on.

**Effort.** S.
**Result:** _open_

<a id="w6"></a>
### W6 — A GTK title bar is stacked above the app's own bar on Hyprland

**Problem.** On the owner's desktop the window has a GTK header bar with the
title and window buttons, then the app's own bar under it. All three
screenshots in `githubAssets/` show it. On a tiling compositor it is a wasted
row.

**Evidence.** `use_header_bar` is true on every Wayland session
(`app/linux/runner/my_application.cc:145`).

**Change.** Use the header bar only on GNOME; elsewhere let the compositor
decide. A preference would also do.

**Done when.** Checked by eye on Hyprland: no GTK-drawn bar, F11 full screen
still works, the window still moves and resizes. Checked that GNOME is
unchanged, or noted as unverified.

**Watch out.** Without a custom title bar GTK 3 may still draw its own
decoration when the compositor does not offer server-side decoration. Test
rather than assume.

**Effort.** S.
**Result:** _open_

<a id="w7"></a>
### W7 — The file chooser is minimal

**Problem.** New, Open, Save As, Export and two preferences all go through an
in-app chooser that always starts in `$HOME`, lists every file, and has no
type-to-filter, no keyboard movement through the list, no new-folder and no
memory of the last folder.

**Evidence.** `defaultDirectory` returns `$HOME`
(`app/lib/library/file_chooser.dart:70`); `_list` shows everything but dotfiles
(`:103`).

**Choose an approach after weighing the trade-offs; record the rationale.**
- **Option A (recommended).** Call GTK's native file chooser from the runner
  over the existing `slugline/window` method channel. That gives the system
  dialog with bookmarks and recent folders, adds no Dart dependency and makes no
  network request. It supersedes ADR 0015, so it needs a new ADR. Effort M.
- **Option B.** Keep the in-app chooser and improve it: remember the last
  folder, start beside the current script, filter to `.fountain` with a toggle,
  type-to-filter, arrow keys and Enter, new folder. Effort S–M.

**Watch out.** `tools/check_no_network.sh` must still pass. The core refuses an
existing destination until asked twice; with a native dialog that asks about
overwriting itself, make sure the writer is not asked twice. The choosers are
already injectable for tests (`SavePathChooser`, `PathChooser`).

**Result:** _open_

<a id="w8"></a>
### W8 — Find highlights only the current match

**Evidence.** The painter draws the selection and nothing else for find; the
controller already holds every match (`EditorController.matches`).

**Change.** While the find bar is open, tint every visible match. When Find is
opened with a selection inside one block, start with that text.

**Effort.** S.
**Result:** _open_

<a id="w9"></a>
### W9 — Previous versions can be restored but not looked at

**Evidence.** `app/lib/library/backups_dialog.dart` lists a time, a size and a
Restore button per version.

**Change.** Let the writer see a version before choosing it — a read-only view
of its text — and open it as a separate copy without replacing the current
script. More useful once S2 exists.

**Effort.** M.
**Result:** _open_

<a id="w10"></a>
### W10 — Slugline is not installed on the owner's machine

**Evidence (observed 2026-10-06).** `slugline` is not on `PATH` and there is no
desktop entry under `~/.local/share/applications`, so double-clicking a
`.fountain` file cannot open it. `tools/package.sh` builds a tarball with an
`install.sh`; it was not run during the review.

**Change.** Verify that building from source and running the installer gives a
working `slugline` command, a launcher entry and the `.fountain` file
association on this machine. Put the exact commands in the README.

**Effort.** S.
**Result:** _open_

---

## 5. Larger features

These features are authorized backlog work. Some need planning and research
before implementation; use judgment, resolve open choices, and document the
decisions as part of the work.

<a id="x1"></a>
### X1 — Dual dialogue

**Evidence (reproduced).** `STEEL` followed by `BRICK ^` prints as two speeches
one after the other. The parser records the flag; `group_speeches`
(`crates/layout/src/engine.rs:558`) ignores it. The editor has no command for
it — the only mention in Dart is an import in
`app/lib/core/document_core.dart:45`.

**Change.** A command that toggles dual on a cue, and side-by-side layout in
the paginator, the preview and the PDF.

**Watch out.** Narrower columns mean new widths in both line breakers and in
`docs/LINE_BREAKING.md`; page-break rules need a paired-speech case.

**Effort.** M–L.
**Result:** _open_

<a id="x2"></a>
### X2 — Final Draft (FDX) import and export

**Planning question.** Establish the likely migration and collaboration needs
from the project context and available sources. If a specific service can
export Fountain, import may not be needed for migration; weigh that against the
value of FDX export and choose a sensible scope. Record the evidence and
decision before implementation.

**Notes.** FDX is XML. Writing it needs no dependency; reading it needs an XML
parser, which needs a line in `docs/DEPENDENCIES.md`. The original spec lists
Final Draft import as a non-goal, so this reverses a recorded decision.

**Effort.** M–L.
**Result:** _open_

<a id="x3"></a>
### X3 — Scene numbering commands

**Evidence (read).** Scene numbers print only for headings that already carry
`#12#` (`crates/layout/src/engine.rs:964`). Turning the setting on for a script
without them prints nothing, and there is no command that adds them.

**Change.** "Number scenes" and "Remove scene numbers" commands, each one undo
step. Alternatively, number automatically at output when no heading has one.

**Effort.** S–M.
**Result:** _open_

<a id="x4"></a>
### X4 — Emphasis that wraps by printed width and is styled in the editor

**Evidence (reproduced).** `This action line has **bold**, *italic* and
_underlined_ words so it wraps early.` broke after "underlined" at 48 columns.
The same sentence without markers filled 60. Markers count as columns in both
line breakers by design (ADR 0019).

**Change.** Wrap by printed width; show emphasis styled in the editor with its
markers dimmed; add Ctrl+B, Ctrl+I and Ctrl+U to wrap a selection.

**Watch out.** This changes the line-breaking contract on both sides
(`docs/LINE_BREAKING.md`, the differential fixtures) and supersedes ADR 0019.
Do F2 first.

**Effort.** M–L.
**Result:** _open_

<a id="x5"></a>
### X5 — Outline in the navigator

**Evidence (read).** `doc_navigator` (`crates/bridge/src/api/doc.rs:354`)
returns scenes and characters. Sections (`#`) and synopses (`=`), which
Fountain has for outlining, are not shown, and a scene row has no page number
or length.

**Change.** Show sections and synopses as structure above their scenes, and a
page number and length for each scene.

**Effort.** M.
**Result:** _open_

<a id="x6"></a>
### X6 — Cleaner Fountain on disk

**Evidence (read).** Tab, Ctrl+digit and double-Enter set `forced`
(`crates/bridge/src/api/doc.rs:769`, `:917`), and the serialiser writes the
marker whenever `forced` is set (`crates/fountain/src/serialise.rs:259` for
cues; `:237`, `:271`, `:286` for the others). The project's own test expects
`JOHN\nHello.\n\n@MARY\nHello yourself.\n`
(`app/integration_test/writing_test.dart:193`). Headings and cues are also
upper-cased for display only, so a file can hold `@john` and
`int. kitchen - day`.

**The decision.** Whether a file written by Slugline should carry a marker only
where the text would otherwise be misread, and whether text shown in capitals
should be stored in capitals. It is valid Fountain either way. The cost of
changing: the "pin" would not survive a reload unless it is kept somewhere
else, and ADR 0011 and the round-trip stability tests are built on the current
rule.

**Effort.** M.
**Result:** _open_

<a id="x7"></a>
### X7 — Omit and restore

**Evidence (read).** A `/* … */` block is read-only in the editor — the status
bar says "That block round-trips verbatim and cannot be edited"
(`app/lib/editor/element_bar.dart:345`) — and nothing in the editor creates
one.

**Change.** Commands to move a selection or a scene into a boneyard block and
back out, each one undo step.

**Effort.** M.
**Result:** _open_

---

<a id="recipes"></a>
## Reproduction recipes

**1. The test suites.** From `AGENTS.md`: `cargo test --workspace` and, in
`app/`, `flutter test`. At the review: 554 and 508, all passing.

**2. Where text lands in a PDF.**

```sh
cargo run -p slugline_render_pdf --example dump -- sample.fountain out.pdf
pdftotext -bbox out.pdf out.html
```

In `out.html` each word has `xMin`/`yMin` in points. The text area starts at
x = 108; a column is 7.2 points and a row is 12, with row 0 at y = 72. So
`column = (xMin − 108) / 7.2`.

**3. Two instances (S1).** Use throwaway data directories so real scripts and
journals are never involved:

```sh
export XDG_DATA_HOME=/tmp/sl/data XDG_STATE_HOME=/tmp/sl/state \
       XDG_CONFIG_HOME=/tmp/sl/config XDG_CACHE_HOME=/tmp/sl/cache
slugline /tmp/sl/a.fountain &      # instance 1
ls $XDG_STATE_HOME/slugline/journal/
slugline /tmp/sl/b.fountain &      # instance 2
ls $XDG_STATE_HOME/slugline/journal/
ls -l /proc/<pid of instance 1>/fd | grep journal
```

Never run this against the real `~/.local/state/slugline`.

## Leave alone

The review found nothing that argues for changing these, and several items
above depend on them staying put:

- The Rust core's shape: one owner thread, edits as patches, lossless
  round-trip, atomic saves, the journal format.
- The in-house PDF writer and the pagination break rules.
- The single custom editing surface and the test that pins its line breaking to
  the paginator's.
- The Enter and Tab logic, and autocomplete never inserting without a key.
- The two-timer autosave, the external-change prompts, and save-failure dialogs
  that block and offer Save As.
- No network, no accounts, no telemetry.
- The static caret and zero idle CPU as the default.

## Parked ideas

Not approved, not scheduled, no boxes. Listed so they are not lost:
typewriter scrolling; a caret-blink option; automatic `(CONT'D)` when the same
character resumes after action; splitting dialogue across pages only at
sentence ends; per-character and scene-length reports; scene headings as PDF
bookmarks; opening the PDF after export. Tabs are deliberately not here: once
S1 is fixed, two windows cover it.

## Found along the way

Add a dated line here for anything noticed while working on an item that is
not part of that item.

- 2026-10-06 — While preparing B2's visual smoke, read a separate single-page
  presentation gap: `PageIndicator._resolvePageStarts` excludes page 1, and
  `EditorGeometry.sheeted` requires a nonempty start list. A one-page pagination
  therefore has no sheet furniture despite page view being enabled. Not
  exercised or changed; investigate separately from horizontal centring.
- 2026-10-06 — While indexing the ADRs, found an unowned correctness gap.
  ADR 0022 (incremental repagination by checkpoint) said its missing
  `repaginate`-versus-`paginate_snapshot` equivalence test was owed to "ADR 0025's
  focused review", but that review is spent and the plan that held its findings
  is no longer in the tree. Promoted to [F8](#f8), which is where the work now
  lives; ADR 0025 records the history and points at it.
- 2026-10-06 — While correcting the declared Rust floor from 1.82 to 1.85,
  found that `SaveError::from_io` no longer needs its raw-errno guard:
  `io::ErrorKind::StorageFull` and `QuotaExceeded` have existed since 1.83, so
  `matches!(error.raw_os_error(), Some(28) | Some(122))` in
  `crates/storage/src/atomic.rs` is a fallback the named kinds already cover.
  Behaviour is the same either way — the match is on `error.kind()` — so this is
  a three-line deletion, not a fix. It touches the save path's error
  classification, so it wants the full-disk test
  (`SLUGLINE_FULL_DISK_DIR`, see the recipes above) rather than a drive-by.
- 2026-10-06 — F3's full Linux integration script stopped in
  `writing_test.dart`: “the real entity index and scene parser drive the
  navigator” expects visible `HOUSE` immediately after opening. The test's
  native narrow window instead uses ADR 0041's closed navigator drawer below
  900 px (`EditorPage._buildEditor`). The fixture needs to open that drawer or
  establish a wide viewport before asserting on its rows. Left unchanged in F3:
  navigator presentation was outside that item.
  Promoted to [B4](#b4) after the owner requested investigation. This is a stale
  integration fixture, not a navigation-product defect; B4 records its separate
  correction and full-gate verification.
- 2026-10-06 — F4's optional Dart formatting check flags all three touched Dart
  files, including existing constructors, switch arms and test assertions under
  the installed formatter. Kept the surrounding style rather than reformatting
  unrelated code; Flutter analysis and tests remain the required Dart checks.
- 2026-10-06 — F4's full native integration run passed bridge and editor suites,
  then failed `writing_test.dart` at line 174: “the real entity index and scene
  parser drive the navigator” expected visible `STREET` and found none.
  This differs from the earlier closed-drawer `HOUSE` failure fixed by B4.
  Recorded the observed failure without changing navigator code or rerunning
  the failed scenario; investigate separately from lyric spacing.
  Promoted to [B5](#b5) after the owner requested investigation; the docked
  Linux navigator loses its page-level shortcut focus boundary on tab clicks.
