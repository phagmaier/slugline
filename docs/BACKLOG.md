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
2. Read the item's section. For a bug, reproduce it with a focused test or
   observation before editing. If it does not reproduce, record that briefly
   rather than making a speculative fix. New features and docs changes need an
   intended result, not a fabricated failing runtime test.
3. Follow [AGENTS.md](../AGENTS.md#verification): focused verification is enough
   to finish a routine item. Full suites run once at a substantial development
   boundary or on explicit request; finishing each item does not trigger them.
   Historical test inventories and release checks in item descriptions are not
   recurring completion requirements. Release work waits for the explicitly
   requested final release task. Add an ADR only for a durable architectural
   decision or a change to an accepted decision; never rewrite the old decision.
4. The owner has delegated implementation choices and product decisions to
   agents. Do not wait for sign-off or ask the owner to choose between options.
   Use judgment and record only non-obvious choices that matter to the outcome.
   Larger or uncertain items may need planning before coding;
   that planning is part of the work, not an approval gate.
5. Stay inside the item. Record actionable adjacent defects briefly under
   [Found along the way](#found-along-the-way); do not log every observation.
6. When the requested behavior/acceptance criteria are met and relevant checks
   pass, review the diff, tick the item's box and fill in its `Result`
   with the date, outcome, focused verification and any material limitation in
   one to three sentences. Name the commit hash or intended descriptive subject
   when committing; a subject avoids a second bookkeeping commit just to add a
   hash. State separately if work is uncommitted. Do not delete historical items
   or expand their existing results into new reports. One item per commit, with
   its id leading the subject. Completion needs no exhaustive test counts,
   passing logs, separate handoff or green hosted CI.

Partial or blocked work remains unticked with `_open_` in its Result and a brief
progress/blocker note. Non-reproduction alone does not close a bug; an
already-fixed item can close when its acceptance criteria are confirmed. Fixing
a subset of an item's criteria is not completion. Unrelated failures and final
release/manual gates do not hold an otherwise completed item open. For a
requested batch, finish it without permission stops and update each status.

These rules were streamlined on 2026-10-09. Follow them over older handoffs,
remembered backlog workflows and per-item verification lists. Direct user work
outside the backlog does not require adding a tracking item.

Effort: **S** is under a day, **M** a few days, **L** a week or more.

## Checklist

This is the only place boxes are ticked.

**1. Safety — do these first**

- [x] [S1](#s1) A second launch deletes a running session's crash journal
- [x] [S2](#s2) Autosave never writes a previous version
- [x] [S3](#s3) The title-page dialog fuses multi-line fields
- [x] [S4](#s4) Opening and closing the title-page form must not alter existing text

**2. Small confirmed bugs**

- [x] [B1](#b1) Find's element filter cannot be reset to "Every element"
- [x] [B2](#b2) Page-view sheets are off-centre and clip on the left
- [x] [B3](#b3) README lists the wrong shortcuts and stale test counts
- [x] [B4](#b4) The native navigator test assumes a permanently docked sidebar
- [x] [B5](#b5) Navigator tab clicks disable the scene quick-jump shortcut
- [x] [B6](#b6) The committed Dart lockfile is not the pinned toolchain's
- [x] [B7](#b7) README names a Preferences section the dialog does not have
- [x] [B8](#b8) The Dart tree is not formatter-clean, and nothing checks it
- [x] [B9](#b9) CI's flutter job cannot run the export suite: no Poppler
- [x] [B10](#b10) Typing after Find opens appends to the seeded or resumed query
- [x] [B11](#b11) Restoring a previous version leaves the editor showing the old draft
- [x] [B12](#b12) Fast platform typing can overwrite characters through stale input echoes
- [x] [B13](#b13) A script with no printed pages throws in the page indicator
- [x] [B14](#b14) Find loses Escape and Enter after pointer interaction
- [x] [B15](#b15) Same-burst Save can precede the final native text update
- [x] [B16](#b16) Closing the window can end the process in SIGSEGV
- [x] [B17](#b17) Hosted Rust checks stop on stale Poppler package metadata
- [x] [B18](#b18) A retained Find query rescans the script on every edit
- [x] [B19](#b19) Save As leaves the old name in the app bar
- [x] [B20](#b20) Closing the window while a script is still opening throws
- [x] [B21](#b21) The status line gives a block that prints nothing the wrong page

**3. Fountain and output fidelity**

- [x] [F1](#f1) Common character-cue shapes are read as action
- [x] [F2](#f2) Emphasised centred, right-aligned and title lines are misaligned
- [x] [F3](#f3) The preview shows literal emphasis markers; heading weight differs between views
- [x] [F4](#f4) Consecutive lyric lines print double-spaced
- [x] [F5](#f5) A `~` line under a cue prints its tilde
- [x] [F6](#f6) Page 1 carries a page number
- [x] [F7](#f7) `@McCLANE` prints as `MCCLANE`
- [x] [F8](#f8) Incremental repagination is not proven equal to a full one
- [x] [F9](#f9) Cold start, idle CPU and RSS are budgets nothing measures

**4. Everyday workflow**

- [x] [W1](#w1) Switching scripts needs the mouse: no new, open or close shortcuts
- [x] [W2](#w2) The command palette is missing commands
- [x] [W3](#w3) No way to type a line break inside an element
- [x] [W4](#w4) No "go to page"
- [x] [W5](#w5) The preview always opens at page 1
- [x] [W6](#w6) A GTK title bar is stacked above the app's own bar on Hyprland
- [x] [W7](#w7) The file chooser is minimal — *option A, ADR 0052*
- [x] [W8](#w8) Find highlights only the current match
- [x] [W9](#w9) Previous versions can be restored but not looked at
- [x] [W10](#w10) Slugline is not installed on the owner's machine
- [x] [W11](#w11) The preview loses its page when the preview size or paper changes

**5. Larger features — plan and use judgment where needed**

- [x] [X1](#x1) Dual dialogue
- [x] [X2](#x2) Final Draft (FDX) import and export
- [x] [X3](#x3) Scene numbering commands
- [x] [X4](#x4) Emphasis that wraps by printed width and is styled in the editor
- [x] [X5](#x5) Outline in the navigator
- [x] [X6](#x6) Cleaner Fountain on disk (fewer `@`, `.`, `!` markers)
- [x] [X7](#x7) Omit and restore (editable boneyard)

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

<a id="s4"></a>
### S4 — Opening and closing the title-page form must not alter existing text

**Problem.** Opening the title-page form and closing it without typing can
rewrite the title page of a native Fountain file. Promoted from the two
2026-10-09 X2 title findings under [Found along the way](#found-along-the-way).

**Evidence (reproduced in a widget test and against the real core).**
- The form kept one value per key in a map, so a repeated key showed its
  *last* entry, while `TitlePage::get`/`set` address the *first*. It also
  committed every box on focus loss and on dispose, typed in or not.
- `Author:  John August` over `Author: Daniel Wallace` became two
  `Author: Daniel Wallace` lines. An empty `Notes:` line was removed, because an
  empty value means "remove". The script was left dirty with Undo steps.
- Every unchanged field still appended a whole title-page record to the crash
  journal: `doc_set_title_field` journalled the page even when the document
  had recorded no step.

**Change.** The form shows a key's first entry — the one the core reads and
writes — and commits a box only when its text differs from what the core holds.
`doc_set_title_field` journals the title page only when the document recorded
a step. Repeated native keys are neither merged nor normalised.

**Done when.** Opening and closing the form changes no title entry and adds no
dirty state, Undo step or journal record, for repeated keys, multi-line values
and custom fields alike. Editing a box changes only that entry; focus-loss and
dispose commits and multi-line values still work; Undo/Redo and save/reopen
keep untouched source bytes.

**Effort.** S.
**Result:** 2026-10-09 — reproduced in a widget test and against the real core: closing the untouched form
replaced a repeated key's first value with its last, removed an empty `Notes:`
line and journalled eight title records. The form now shows a repeated key's
first entry and writes only boxes whose text changed, and `doc_set_title_field`
no longer journals a field it left alone; the title-page widget tests and two
bridge regressions (unchanged fields record nothing and save byte-identically;
a repeated-key edit changes only its first entry through Undo/Redo, recovery
and save/reopen) pass. Limitation: a repeated key's later entries stay in the
file and print but are not shown in the form, and clearing its box removes them
all, as `TitlePage::set` always has. Commit:
`S4 — the title form writes only the boxes that were edited`.

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
**Result:** 2026-10-06 — verified in `6e92052`. A real-core diagnostic under
isolated XDG roots observed Characters clicks move focus from the navigator
field to the route scope, bypassing the page's Ctrl+J handler. The native
viewport was 1280 × 720 with a docked sidebar. Flutter 3.44.8 and Dart 3.12.2
match the repository/CI pins; no installation, version or dependency change was
needed. Linux-mode widget coverage reproduced the docked failure before the
fix; Android-mode and compact-drawer runs passed, exposing the previous
coverage gap rather than a new parsing defect.
`EditorPage` now owns a `FocusScope`, retaining unfocus inside the page's
shortcut boundary without forcing focus on tab clicks. Child editing keys
still run first and modal routes keep their own input boundary. Regressions
cover docked and compact quick-jump filtering, Enter selecting the scene,
unchanged screenplay source, and modal input isolation.
All 57 native tests across seven suites now pass, including the original
writing scenario. The rebuilt release UI was visually checked after Characters
→ Ctrl+J → `street` → Enter: only STREET remained and its heading received the
caret. Flutter analysis and 534 tests, Linux release/network checks, 598 Rust
tests, rustfmt/clippy and layering/version/docs checks passed. Temporary
diagnostics were removed; changelog and keymap describe the restored behavior.

<a id="b6"></a>
### B6 — The committed Dart lockfile is not the pinned toolchain's

**Problem.** `app/pubspec.lock` records versions the supported toolchain cannot
use. Every `flutter pub get` under Flutter 3.44.8 — CI's, the release
workflow's, and the one the bridge code generator runs — re-resolves four
packages and leaves the tree dirty, and CI builds and tests from that silent
re-resolution rather than from what is committed.

**Evidence (reproduced under Flutter 3.44.8 / Dart 3.12.2, the CI pin).**
`flutter pub get --enforce-lockfile` fails with “Unable to satisfy
`pubspec.yaml` using `pubspec.lock`”. A plain `flutter pub get` reports
“Changed 4 dependencies!” and moves `matcher` 0.12.20 → 0.12.19, `meta` 1.19.0 →
1.18.0, `test_api` 0.7.12 → 0.7.11 and `vector_math` 2.4.2 → 2.2.0. Those are
the exact versions the SDK's own `flutter` and `flutter_test` packages pin, so
no other resolution exists for this toolchain. The newer versions arrived in
`fc918d5` (2026-09-13), written by a newer local Flutter — which
`environment.flutter: ">=3.44.8"` permits. Found during F6, when regenerating
the bindings rewrote the file.

**Change.** Commit the pinned toolchain's resolution. Resolve with
`--enforce-lockfile` in CI and in the release workflow, so a lockfile written by
another SDK fails there instead of being replaced without a word. Say in
`AGENTS.md` whose file it is. Leave `tools/release_preflight.sh` and the
minimum-version constraint alone: a newer local toolchain still builds and
tests, and the drift it causes is now caught on push.

**Done when.** `flutter pub get --enforce-lockfile` passes under 3.44.8 and
leaves the tree clean, as does regenerating the bindings; analysis, tests and
the release build pass on the committed lockfile.

**Effort.** S.
**Result:** 2026-10-06 — verified in `a6815f6`. Reproduced first, as the
Evidence records. The lockfile now holds the four versions Flutter 3.44.8 pins,
and nothing else in it moved. CI's flutter job and the release workflow resolve
with `--enforce-lockfile`; `AGENTS.md` names the file's owner and lists the
check with the other Flutter checks. Under 3.44.8 / Dart 3.12.2 the enforced
resolve passes and leaves the tree clean, and so does regenerating the
bindings, which is what exposed this. Flutter analysis and 539 tests, the
Linux release build and network isolation pass on the committed lockfile. No
dependency was added or removed and the application is unchanged: pinned
builds were already resolving to these versions. Not exercised: the two
workflow files on GitHub. They carry the same one-flag change, and the command
was run locally under the same toolchain version. Left alone on purpose:
`tools/release_preflight.sh` still runs a plain `pub get`, so a newer local
Flutter can run it; if that rewrites the lockfile, CI now says so on push.

<a id="b7"></a>
### B7 — README names a Preferences section the dialog does not have

**Evidence (read).** `README.md` sends the reader to Preferences → “Output” →
**Bold scene headings**. `PreferencesDialog` has five sections — Appearance,
Writing, Autosave, Page defaults and Backups (`_heading` in
`app/lib/settings/preferences_dialog.dart`) — and the option is under Page
defaults. There is no “Output”. Found during F6, which added a second option
to the same section.

**Change.** Name the section the dialog has. The heading is what the writer
sees and what ADR 0048 already calls it, so the README moves, not the label.

**Done when.** Every Preferences section the README names exists in the dialog.

**Effort.** S.
**Result:** 2026-10-06 — verified in `3307256`. The README now says
Preferences → Page defaults. That is the only Preferences section it names;
the sentence F6 added refers to “the same Preferences section” and needed no
change. Checked against the dialog's five `_heading` calls by reading, which is
all a label needs. No code changed; `tools/check_docs.py` passes.

<a id="b8"></a>
### B8 — The Dart tree is not formatter-clean, and nothing checks it

**Problem.** `dart format` rewrites 41 of the application's 97 Dart files, so
formatting a file a change touches reformats lines the change has nothing to
do with, and a tree-wide run buries the change in thousands of them. Each item
that edits Dart either leaves its own code unformatted or spends time
separating its diff from the formatter's. F4 recorded the first and F6 the
second.

**Evidence (reproduced under Flutter 3.44.8 / Dart 3.12.2).**
`dart format --output=none --set-exit-if-changed lib test integration_test
test_driver` reports “Formatted 97 files (41 changed)”: 1,757 insertions and
1,275 deletions. Rust is held by `cargo fmt --all --check` in CI; Dart had
only `flutter analyze`, which does not look at layout. A configuration
that keeps trailing commas (`formatter: trailing_commas: preserve`) was tried
and still changes 36 files and about as many lines, so the default style costs
nothing extra and needs no configuration to explain. The generated bindings in
`app/lib/src/rust/` are already formatter-clean.

**Change.** Format the tree once with the pinned toolchain's default style, in
a commit that does nothing else, and check it where `cargo fmt` is checked: a
CI step, `tools/release_preflight.sh`, and the Flutter list in `AGENTS.md`.
The vendored Cargokit build tool under `app/rust_builder/` is not ours and is
left out.

**Done when.** The check passes on the whole tree; the formatting commit
changes nothing but whitespace and trailing commas; regenerating the bindings
keeps it passing; analysis, every Flutter test, the release build and the
native integration suites — the keystroke budgets among them — still pass.

**Effort.** S.
**Result:** 2026-10-06 — verified in `76c7c36` (the reformat, and nothing
else) and `e7dfd64` (the check). Reproduced first: 41 of 97 files changed. The
reformat is whitespace and trailing commas only — for each of the 41 files the
text before and after is identical once both are stripped out — and the
generated bindings were already clean and are untouched. The default style was
kept and nothing is configured. The check now runs as a CI step beside
`flutter analyze`, in `tools/release_preflight.sh`, and is listed in
`AGENTS.md` and `CONTRIBUTING.md`; `AGENTS.md` says to format the Dart a change
touches. Verified under Flutter 3.44.8 / Dart 3.12.2: the check passes on the
whole tree and again after regenerating the bindings; Flutter analysis and 539
tests, the Linux release build and network isolation pass; all seven native
integration suites pass under Xvfb, with both keystroke budgets met
(journalled p99: 4.09 ms). No Rust changed. Not exercised: the CI step on
GitHub; the same command was run locally under the same toolchain version.
Differently from the item's first sketch, the reformat and the check are two
commits, so that the mechanical one can be skipped in `git blame` — with a
`.git-blame-ignore-revs` entry, if the branch is merged without squashing.

<a id="b9"></a>
### B9 — CI's flutter job cannot run the export suite: no Poppler

**Problem.** Two tests in `app/integration_test/export_test.dart` read an
exported PDF back through Poppler — `pdftohtml` in F3's heading-weight test,
`pdftotext` in F6's first-page-number test. CI's flutter job installs xvfb and
not `poppler-utils`, so both throw `ProcessException: No such file or
directory` there while passing on any machine that has it.

**Evidence (observed on GitHub, run 37550528288, `main` at `4b79cce`).** The
export step reports “5 tests passed, 2 failed”, both failures being that
exception at the `Process.run` call. Every other step of the job passes,
including the writing suite. F3's test had never run on GitHub: the push before
this one (`e4503f4`) failed in the writing suite — the bug B5 fixed — and each
suite is its own step, so the job stopped before reaching the export suite.
The Rust job and the release workflow already install `poppler-utils`; only
this job was missed. `tools/test_linux_integration.sh` checks for `flutter` and
`xvfb-run` and not for these, so a local machine without Poppler fails in the
same way, mid-suite.

**Change.** Install `poppler-utils` in the flutter job beside xvfb. Have the
integration script require `pdftotext` and `pdftohtml` up front, so that their
absence is one legible line rather than two exceptions. Do not make the tests
skip: reading the PDF back is what they are for.

**Done when.** The export step passes on GitHub and the run for `main` is
green.

**Effort.** S.
**Result:** 2026-10-06 — verified in `76c60b3`. GitHub run 37551294134 for that
commit is green in all five jobs; the flutter job's export step passes all
seven of its tests and the job goes on to meet the keystroke budget, which the
earlier failure had also been hiding. Locally, with Poppler off the `PATH` the
integration script stops at “required command not found: pdftotext”, and with
it all seven suites pass. The tests were not changed and do not skip. This was
the first green run on `main` since `40b1f1c`: the two pushes between failed in
the writing suite (fixed by B5) and then here.

<a id="b10"></a>
### B10 — Typing after Find opens appends to the seeded or resumed query

**Problem.** Promoted from W8's second finding: opening Find over a selection
or resuming the last search leaves the query's caret at the end. Typing a new
query appends instead of replacing what was offered.

**Evidence (reproduced 2026-10-07).** Real keys on the W8 release bundle under
Xvfb: select `DAY`, open Find, type `house` → `DAYhouse`, “No matches”
(`target/b10-smoke/before-typed.png`). Two widget regressions on the unchanged
production code give `DAYhouse` and `quiethouse` rather than `house`.

**Change.** Select the entire query once when the bar first takes focus, for
both seeded and resumed searches. Typing replaces it; moving the caret first
allows amendment. Do not change toggle focus, repeated Ctrl+F, bar positioning
or search scheduling.

**Done when.** Seeded and resumed queries are replaceable by typing on the real
release surface and in widgets, later typing continues normally, and the script
is unchanged.

**Effort.** S.
**Result:** 2026-10-07 — verified in the commit named
`B10 — Find selects its opening query for replacement`. Named by subject here
so the implementation and its completion record stay in one commit.
`FindBar` selects the whole query once in its existing post-frame focus
callback, after requesting focus. No controller or search-policy change; the
other four W8 findings remain outside this item.

Reproduced before changing production code: the W8 release bundle appends
`house` to selected `DAY`, and the two new replacement widget cases fail with
`DAYhouse` and `quiethouse`. Three widget regressions now cover seeded and
resumed replacement, continued typing without reselecting, and Right-arrow
amendment; query input issues no script edits.

The rebuilt release, driven with real keys under Xvfb, shows selected `DAY`
on opening, `house` / “2 of 3” after typing, `houses` after further typing,
and resumed replacement with `DAY` / “1 of 1”. Reopening, waiting for field
focus, then Right and `s` yields `houses`; Find input followed by Save leaves
the script byte-identical. Frames and the saved script are in
`target/b10-smoke/`. An initial amendment driver sent Right before the opening
frame and produced `x`; its corrected run waits for field focus
(`after-amended-after-focus.png`). Bare Xvfb has no window manager to dispatch
Alt+F4, so the smoke closed the session with Ctrl+W before stopping the process.
Scratch state and processes were removed. This is software-rendered Xvfb
evidence, not a real-desktop claim.

Verified 646 Rust tests, 664 widget tests, all seven native suites (69 tests),
rustfmt/clippy, enforced lockfile, Dart formatting/analysis,
layering/version/docs/reference checks, Linux release build and headed network
isolation. Journalled keystroke p99: 2.48 ms. Workspace and Flutter output is
retained in `target/b10-rust.log` and `target/b10-flutter.log`. Runtime budgets
were not rerun; the known idle failure, its thresholds and its harness remain
unchanged. KEYMAP and CHANGELOG describe opening-query replacement. No Rust API,
binding, dependency, lockfile, golden or ADR change. Committed locally,
unpushed; W9 remains next.

<a id="b11"></a>
### B11 — Restoring a previous version leaves the editor showing the old draft

**Problem.** Restore replaces the core document and the file, but the editor
continues displaying the pre-restore text, caret and word count. Further editing
can target block identities that no longer belong to the restored document.

**Evidence (reproduced).** W9's release smoke restored the selected older bytes
and preserved the current draft in backups, but the screen stayed on the current
draft (`target/w9-smoke/after-restored.png`). `EditorPage._showBackups` drops
`BackupsDialog.show`'s restored boolean; `withModal` only holds autosave.
`EditorController.reloadFromCore` already rebuilds the editor after a whole
document replacement. Promoted from W9's finding ahead of W10: displayed/saved
text divergence is a correctness bug, installation is not.

**Change.** On successful restore, reload the current editor from the core and
refresh save status before releasing the modal autosave hold. Do not reload on
view, copy, cancellation or failure.

**Done when.** Restore from both the list and the read-only view replaces the
visible text and count; the next edit and save use the restored document without
unknown-block refusals. Cancellation and failed restore retain text and caret.
The pre-restore draft remains recoverable in previous versions.

**Effort.** S.
**Result:** 2026-10-08 — verified in `79935c1`. Promoted ahead of W10 because
displayed/saved text divergence is a correctness bug. Both native entry points
failed before the fix: the file contained `Earlier words.` while the controller
still contained the current draft. `_showBackups` now consumes the restored
boolean and calls the existing `reloadFromCore` plus save-status refresh inside
the modal autosave hold. It checks that the page still owns the same controller.
No extra core reload, parser, mutation or API is introduced.

Two native regressions cover the list and read-only-view entry points, a
different-sized restored document, caret reset, refreshed word count, preservation
of the replaced unsaved draft, and editing/saving the restored text. A widget
regression covers viewing then closing, and failed restore then closing: both
retain text and caret without edits. A first green attempt exposed an invalid
test assumption that block ids could not recur across replacement documents;
that incidental assertion was removed, and the test instead exercises editing
after replacing a two-block draft with a one-block version.

The rebuilt release was driven with real pointer and keyboard events under
Xvfb. The view restore changed the visible draft and count from 13 to 6 words,
with the exact earlier bytes on disk and the current text preserved in a backup.
Restoring that preserved draft directly from the list changed text and count
back to 13; typing and Save then produced the matching 16-word file. Frames and
both version sources are in `target/b11-smoke/`. Closing removed the journal;
the smoke processes and isolated caches were removed. This is software-rendered
evidence, not a real-desktop claim.

Verified 649 Rust tests, 671 widget tests, all seven native suites (71 tests),
rustfmt/clippy, enforced lockfile, Dart formatting/analysis, layering/version/docs
and reference checks, binding freshness, serial Linux release build and headed
network isolation. Journalled keystroke p99: 4.12 ms. Rust and Flutter output is
retained in `target/b11-rust.log` and `target/b11-flutter.log`; the Rust log
includes the initial docs check rejecting the pending Result spelling, corrected
before the successful docs check. Runtime budgets were not rerun; the known idle
failure, thresholds and harness remain unchanged. CHANGELOG records the fix.
No dependency, lockfile, Rust API, generated binding, golden or accepted ADR
decision changed. W10 remains next, F7 remains blocked by X6, and the other W8/W9
findings remain untouched. Committed locally; nothing was pushed.

---

<a id="b12"></a>
### B12 — Fast platform typing can overwrite characters through stale input echoes

**Problem.** Promoted from W10's separate finding, and explicitly prioritized
before X1 on 2026-10-08: an unpaced native-Wayland `wtype` burst loses letters.
The installed app paints and saves the same incomplete text.

**Evidence (reproduced before changing production code).** A fresh disposable
document, with the editor adopted and the caret at its end, has incomplete
journal patches before any Save shortcut. Immediate and later explicit saves
write the same incomplete bytes. A temporary diagnostic release records all 40
printable key-down characters arriving intact, while later platform editing
values already lack letters. `EditorSurface._syncEditingState` echoes every
accepted value back through the asynchronous input channel; selection placement
during a replacement also sends pre-edit text. These stale whole-block values
can overwrite newer platform input. Two widget regressions fail on the unchanged
implementation. This establishes an application input synchronization defect,
rather than incomplete driver delivery or a premature Save snapshot.

**Change.** Track the last known platform value, suppress intermediate outgoing
states while applying one platform edit, and send only a differing final result.
Application caret moves, structural edits and core refusals still synchronize.
Keep this correction separate from the published CI correction and W10.

**Done when.** The original unpaced burst reaches the journal and file intact on
the native release, with exact reopen; outgoing-channel regressions cover
accepted typing/composition and final structural/refused results. The native
storage regression covers immediate Save, Undo/Redo and reopen.

**Effort.** S.
**Result:** 2026-10-08 — verified in `0cb58de`. All 40 supplied key-down
characters arrived intact, but stale application state echoes caused incomplete
platform values and journal patches before Save. Track the last remote value
and batch each platform edit's synchronization; accepted text sends no echo,
while a differing final caret, structural or refused result still synchronizes.
The uninstrumented native-Wayland release now preserves the original unpaced
burst before Save, and same-burst Ctrl+S also saves/reopens exact bytes with clean
exits. No input delay, retry or relaxed assertion. Verified 649 Rust tests,
675 widget tests, all seven native suites (72 tests), journalled keystroke p99
4.37 ms, enforced lockfile, formatting/clippy/analysis, layering/version/docs,
serial release build and network isolation. Evidence and retained harness
failures are described in [FAST_INPUT.md](FAST_INPUT.md).

Separately published the original CI/W10 commits through `9b21f33`; hosted run
37764798245 passed all five jobs, including writing and subsequent native
suites. That hosted run does not cover B12. The B12 fix is committed locally,
unpushed; the owner-installed W10 executable remains its original build. No
automated prerequisite was unavailable. Local idle and manual GPU/IME gates
remain open; X1 and unrelated findings were not started.

---

<a id="b13"></a>
### B13 — A script with no printed pages throws in the page indicator

**Problem.** Promoted from W3's recorded finding on 2026-10-08. A Note-only
script produces zero printed pages, but `PageIndicator._updateCurrent` clamps
page 1 between 1 and 0. The native regression hides it with printable Action.

**Evidence.** Retained original failure: `target/w3-native-writing-retry.log`.
Reproduce the current implementation with empty and source-only snapshots and
the original Note-only native fixture before changing production code.

**Change.** Present zero printed pages without inventing page 1, keep pagination
Rust-owned, and remove the printable-content workaround.

**Done when.** Empty, Note-only and other non-printing scripts remain editable;
zero/nonzero transitions, Save and actual reopen work without exceptions in
continuous and page views. Zero pagination has no page target or furniture.

**Effort.** S.
**Result:** 2026-10-08 — verified in `f34aed7`.
Five current-tree widget regressions and the original Note-only native test
failed at the recorded clamp before the fix. Zero pagination now has no current
page and says “No printed pages”; page targets and furniture stay absent. Rust
still gives an empty editable Action one blank sheet, which remains “Page 1 of
1”. Fifteen page-indicator widget tests and seven focused native tests pass,
including both views, zero/nonzero Undo/Redo, exact BOM/CRLF file bytes, Save and
actual reopened editor status. The Note-only Shift+Enter test no longer relies
on printable Action. Logs are under `target/stabilization/b13-*`; intermediate
native harness mistakes (empty-sheet expectations, BOM/body distinction and
pointer placement on read-only boneyard after reopen) are retained separately.
Final shared matrix passes 649 Rust tests, 690 widgets and 82 native tests;
static, docs, serial package, tarball and network checks pass. Current Xvfb
process budgets pass; the earlier retained idle failure and manual GPU/IME gates
remain open.

---

<a id="b14"></a>
### B14 — Find loses Escape and Enter after pointer interaction

**Problem.** Promoted from W8's native finding on 2026-10-08. Clicking Match
case, Whole word or the element filter leaves Escape unable to close Find and
Enter unable to step matches.

**Evidence.** Original native screenshot:
`target/w8-smoke/found-escape-after-toggle.png`. Six current-tree Linux widget
regressions reproduce both failures after pointer interaction; retained in
`target/stabilization/b14-widget-red.log`.

**Change.** Give Find a focus scope so desktop field unfocus remains inside its
keyboard boundary. Let children handle their own keys first and retain popup
and modal behavior.

**Done when.** After clicking each control, Escape dismisses Find and Enter,
Shift+Enter and numpad Enter navigate normally; query input and navigation
leave the script bytes untouched. Verify widgets and a native pointer smoke.
Repeated Ctrl+F, placement, search performance and preview navigation stay
separate.

**Effort.** S.
**Result:** 2026-10-08 — verified in `e15126d`. Six Linux widget failures reproduced the keyboard loss
before the correction. A Find-owned `FocusScope` retains desktop field unfocus
inside its key handler without forcing query-field focus on clicks. All 36
Find widgets pass, including Enter/Shift+Enter/numpad Enter, Escape after all
three controls, popup-first Escape and modal isolation. Three real-core native
pointer tests pass with unchanged CRLF file bytes, clean dirty/journal state,
Save and exact reopen. Evidence: `target/stabilization/b14-*`; the intermediate
popup-finder failure is retained as a test-harness mistake. Final shared
matrix passes 649 Rust tests, 690 widgets and 82 native tests. Release OS pointer
clicks and real keys confirm match stepping and Escape after every control with
exact CRLF bytes after navigation and Save; screenshots were inspected under
`target/stabilization/pointer-smoke-clean/`, and WM_DELETE_WINDOW closes with
exit 0. The first smoke's xdotool direct window destruction produced BadDrawable
and exit 1; it remains separately retained under `pointer-smoke/` and is not an
ordinary-close result. Current Xvfb budgets and packaging/network checks pass;
earlier idle and manual GPU/IME gates remain open. Repeated Ctrl+F, placement,
search performance and preview navigation are untouched.

---

<a id="b15"></a>
### B15 — Same-burst Save can precede the final native text update

**Problem.** Found while executing the required installed B12 verification.
Typing and Ctrl+S in one unchanged unpaced burst can save a snapshot that lacks
the final period; the eventual text and later save/reopen are complete.

**Evidence.** Two installed release failures in
`target/fast-input/installed-b12-immediate-save/` and
`installed-b12-immediate-save-repeat/`. The settled journal records the final
period after the initial saved base. A passing identical run and a diagnostic
release control do not close the failure. This is separate from B12's stale
state echoes, which no longer overwrite the eventual text.

**Change.** Synchronize explicit Save with the native input queue before taking
a Rust snapshot; no clock, slower injection, key reconstruction or extra save.

**Done when.** A delayed platform text update is committed before the snapshot
in a widget regression; original unpaced native bursts immediately Save and
reopen exactly on the final installed package. Preserve the red runs and verify
that waiting for native input never mutates the text itself.

**Effort.** S.
**Result:** 2026-10-08 — implemented in `40cfad5`, published and verified in
hosted run [37775929481](https://github.com/phagmaier/slugline/actions/runs/37775929481)
at `804ba18`; all five jobs pass. The generated source-package installer
refreshed the existing user-local app. All 18 installed bundle files match the
verified stage, and `/proc/<pid>/exe` confirms the shell launcher reaches the
installed runner on both initial open and reopen. One before-save journal run
and three unchanged same-burst Ctrl+S runs preserve exact first-save, settled
pre-later-save, later-save and reopened bytes, with every Wayland process exit
zero. Two widget failures reproduce snapshot-before-input and disposal
boundaries. Explicit Save now waits
for a one-shot GTK idle acknowledgment on the existing native channel, then
checks the original editor is still mounted before asking Rust to snapshot.
This forwards already queued native input without a clock, input reconstruction,
text-state echo, composition confirmation or a second save. Both widgets and an
actual-runner persistence test pass; three uninstrumented native-Wayland runs
preserve exact first/later saved bytes and actual reopen with zero exits. The
full matrix passes 649 Rust tests, 690 widgets and all 82 native tests;
journalled keystroke p99 is 6.53 ms. Formatting, clippy, analysis, enforced
lockfile, docs/layering/version/reference, serial release package, isolated
tarball install/uninstall and network isolation pass. Current Xvfb process
budgets pass (startup 372.795 ms, RSS 275.41 MiB, a zero-activity idle interval);
this does not close the retained earlier idle failure or real-GPU/IME manual
gates. Evidence and initial harness failures remain under
`target/stabilization/`, `target/fast-input/save-order-*` and
`target/fast-input/installed-final-*`. Final installed Note-only checks pass in
both views; Find pointer/key checks preserve bytes. Their separate Xvfb
ordinary-close SIGSEGV is retained below with failing pre-fix package controls,
not claimed as a clean process exit. See [FAST_INPUT.md](FAST_INPUT.md#final-publication-and-installed-verification--2026-10-08).

<a id="b16"></a>
### B16 — Closing the window can end the process in SIGSEGV

**Problem.** Promoted from the final installed stabilization smoke, and taken
ahead of X1 at the owner's direction. An ordinary close — the window manager's
close button — can kill the process with SIGSEGV after the session has shut
down: the script is saved, the journal is discarded, and the process then dies
in `exit()` and leaves a core behind. Nothing the writer typed is lost. Every
close that crashes reports a crash to the desktop.

**Evidence (reproduced 2026-10-08).** The retained driver
`target/stabilization/shutdown-control.py` ends in `DONE -11` on the installed
build at `804ba18` and on the earlier CI package at `08c7a55`
(`shutdown-current-01/`, `shutdown-prior-01/`). In every core
`io.flutter.raster` is inside a Mesa GL call while the main thread is inside
`exit()` running Mesa's handlers. Controlled comparisons on the installed build
under Xvfb (`target/stabilization/b16/`, one isolated launch each):

- Save against no Save, both followed by Ctrl+W and a close 0.3 s later: one
  SIGSEGV in three each. Save is not involved.
- Closing 0.05, 0.15 and 3 s after Ctrl+W: four in six, three in six, none in
  six. The crash needs the library still sliding in.
- No script at all, closed while Tab moves focus through the library: five in
  six. The document and its Rust state are not involved.
- A script open, closed while the shortcuts dialog fades in: two in six.
- The window at rest, on either page: none in 19. Pointer movement, caret
  movement, scrolling, the palette and a close during startup: none in 42.
- The stock `flutter create` runner with a spinner and the same engine binary:
  three in eight.
- The owner's Hyprland session, on the hardware driver: two in seven.

**Change.** Stop the Flutter engine before `main()` returns, so the process's
exit handlers run with no frame in flight (ADR 0053). Not a longer wait before
closing, not a forced exit, not software or disabled rendering.

**Done when.** At least five ordinary-close runs of the corrected build exit
zero with no core recorded and exact Save and reopen bytes; a check that fails
on the uncorrected build runs in CI; the correction is published, hosted CI is
observed, and the installed app is refreshed and verified.

**Effort.** S.
**Result:** 2026-10-08 — corrected in `774c30a`, published and verified in
hosted run [37790817381](https://github.com/phagmaier/slugline/actions/runs/37790817381);
all five jobs pass, including the new "Ordinary close exits cleanly" step, whose
15 closes all exit zero on GitHub's runner. Flutter's embedder answers the close
button with `g_application_quit()` and leaves the window, the engine and the
engine's threads running, so `main()` returned into `exit()` with the raster
thread still drawing; Mesa's own exit handlers then freed what it was using.
`my_application_shutdown` now disposes the engine, which is where the embedder
calls `FlutterEngineShutdown` and joins those threads; at `exit()` the
corrected build no longer has an `io.flutter.*` or Dart VM thread. Destroying
the window instead was measured in the stock runner and failed three times in
24, because the view's dispose frees its compositor under the raster thread;
`_exit()` was rejected as a forced termination (ADR 0053). Different from the
item as promoted: this is not an Xvfb artefact. The installed build also died
on the Hyprland session, twice in seven closes.

`tools/check_clean_close.py` is the regression check, in CI's flutter job, the
release workflow and the preflight. It fails on the uncorrected installed build
four invocations in four and passed 87 closes on the corrected bundle. Before
publication that bundle also passed 74 Xvfb closes across the failing variants
and their controls and 12 on the Hyprland session, with no core recorded.

The source package built from `774c30a` was installed with its generated
installer. All 17 package files match the installed bundle byte for byte; the
runner is new and the Dart, Rust and engine libraries are the bytes already
installed. A stale `lib/native_assets.json` from the earlier local build is
left beside them: neither this package nor the hosted one ships it. On the
installed runner the committed check's 15 closes, the retained
`shutdown-control.py` twice (`DONE 0`, where it had been `DONE -11`), 30 matrix
closes and six on the Hyprland session through `~/.local/bin/slugline` all exit
zero with no core recorded: 53 ordinary closes. Six of those runs edit, Save,
close, reopen, edit and Save again, leaving `…river. Again\r\n` and then
`…river. Again Again\r\n` exactly.

The full matrix passes 649 Rust tests, 690 widgets and all 82 native tests
(journalled keystroke p99 2.24 ms), with formatting, clippy, analysis, the enforced lockfile, docs, layering,
version and reference checks, the serial release package, tarball
install/uninstall and network isolation. Xvfb process budgets pass on the
packaged bundle (startup 374.0 ms, RSS 273.2 MiB, a zero-activity idle
interval); that does not close the retained earlier idle failure or the
real-GPU and IME manual gates. No dependency, golden or generated-binding
change. Cores, symbolised stacks, per-run reports with package versions and
bundle hashes, the drivers, the stock-runner reproducer and
`completion-manifest.json` are under `target/stabilization/b16/`; the
reproductions with the retained driver are `shutdown-current-01/`,
`shutdown-prior-01/` and `shutdown-b16-installed-0{1,2}/` beside it. Three
unrelated observations from the same runs are under Found along the way.

<a id="b17"></a>
### B17 — Hosted Rust checks stop on stale Poppler package metadata

**Problem.** The hosted runner's apt index can name a package version that
Ubuntu mirrors have replaced. Rust verification then stops before any checks.

**Evidence (reproduced).** Hosted run
[37860589165](https://github.com/phagmaier/slugline/actions/runs/37860589165),
at `34844c7`, requests Poppler `24.02.0-1ubuntu9.9`; all attempted mirrors
return HTTP 404 for both `libpoppler134` and `poppler-utils`. The Rust job's
install step has no `apt-get update`. Flutter and packaging refresh first.

**Change.** Refresh apt metadata immediately before installing Poppler, using
the existing desktop-job convention. No package pin, retry, fallback or
runtime-budget change.

**Done when.** A hosted run installs Poppler and actually executes the Rust
formatting, Clippy, workspace/full-disk tests, layering, version and docs gates.

**Effort.** S.
**Result:** 2026-10-09 — fixed in `68370a7`. Refresh apt metadata before installing
Poppler, matching the other hosted jobs; no dependency pin, retry, fallback or
runtime-threshold change. Hosted
[37862474236](https://github.com/phagmaier/slugline/actions/runs/37862474236)
completed successfully: Poppler installation and every Rust check actually ran,
including workspace tests with the real full-disk fixture. Fuzz, MSRV, Flutter
(bindings, formatting, analyze, widgets, release, process/close budgets and
all seven native suites) and packaging/network/install smoke also passed.
`./tools/agent.sh docs` passed before implementation commit and after this
completion record. No deviation.

<a id="b18"></a>
### B18 — A retained Find query rescans the script on every edit

**Problem.** Promoted from W8's finding on 2026-10-09. Find retains its query
after closing so Ctrl+G can continue it, but every applied edit, undo/redo and
reload eagerly calls `core.find`. The synchronous `doc_find` scans the whole
document on the typing path even when no Find UI consumes the result.

**Evidence (reproduced).** With Find closed after searching for `house`, a
throwaway widget smoke recorded 20 whole-document Find calls for 20 typed
characters. Native Linux measurements on the 120-page reference, after actually
opening and closing Find with query `the`, failed the unchanged 16 ms command
budget: p99 58.61 ms without a journal and 67.83 ms with a journal. The existing
benchmark did not use Find.

**Change.** Cache matches against `EditorController.documentRevision`. Edits
only change that revision; match getters, highlighting, navigation and Replace
refresh ranges when consumed. Retain the query and the synchronous Rust API;
do not move matching semantics into Dart, add timers, or weaken the budget.
Extend both native keystroke benchmarks with a previously used, closed Find
bar, keeping the same isolated editing surface for both query states.

**Done when.** Closed Find performs no search during ordinary typing, yet
Ctrl+G, Ctrl+Shift+G, Replace, reopening, undo/redo and reload consume current
ranges. Open Find still displays current counts and tints. Both retained-query
native benchmarks meet the existing 16 ms p99 limits.

**Effort.** S.
**Result:** 2026-10-09 — fixed in `888df30`. Matches are now cached against the
existing document revision, not refreshed by edits. The closed-bar smoke went
from 20 scans for 20 keystrokes to zero, then one refresh on Ctrl+G. Match
consumers refresh once per revision; Replace refreshes both before editing and
before selecting its successor. Queries, filters and Rust matching stay intact.
Widget regressions cover closed-bar navigation after deletion/undo/redo, a
new match after an empty result, and Replace after an unseen astral-prefix edit.
An actual native UI smoke confirmed shifted UTF-16 selections, Replace without
an intervening getter, undo/redo and a reopened “1 of 1” count; its screenshots
were inspected and the throwaway scripts removed.

The final native benchmark opens and closes the real Find bar, then uses the
original isolated `EditorSurface` for both query states. With a retained query,
command p99 is 3.23 ms, frame-build p99 6.70 ms, and journalled command p99
3.89 ms; all remain below the unchanged 16 ms limits. Both journal variants
record all 270 edits. A preliminary harness left `EditorPage` mounted only for
the retained-query case: after the fix its command budget passed but its
frame-build p99 failed at 18.31 ms during concurrent workspace checks. That
measured a different surface, so the final harness preserves the original
surface contract and ran serially. This does not claim a separate full-page
frame budget or a real-desktop GPU measurement.

Verification passed: 709 Rust tests, 735 Flutter tests, all seven native suites
(91 tests), enforced Flutter lockfile, Rust/Dart formatting, Clippy with warnings
denied, Flutter analysis, Linux release build, layering/version/docs and the
reference-fixture check. No bridge API, bindings, dependency, golden or accepted
ADR changes.
The rebuilt release also passed all 15 ordinary-close checks, static network
linkage checks and `--version` in an isolated network namespace.

The separate release-process run passed startup and Xvfb RSS, but failed the
zero-wakeup idle gate (best interval: zero CPU ticks, one voluntary switch).
Evidence is in `target/b18-runtime-budgets.json`; it is recorded below rather
than changing unrelated idle behaviour or relaxing that gate.

<a id="b19"></a>
### B19 — Save As leaves the old name in the app bar

**Evidence (reproduced in a widget test).** Promoted from the 2026-10-09 X2
note under [Found along the way](#found-along-the-way). `_SluglineAppState`
reads the script's name from its path when it builds, and a Save As moves the
path without rebuilding it. An imported script saved for the first time went on
saying "Untitled"; `alpha.fountain` saved as `gamma.fountain` went on saying
"alpha", in the bar and in "Save changes to alpha.fountain?".

**Change.** The editor page reports a save that wrote the file, and the
application reads the name again. Dart only; the core already returns from a
Save As with the session on its new path.

**Effort.** S.
**Result:** 2026-10-09 — `EditorPage.onSaved` fires after any save the page ran
that wrote the file, and `_SluglineAppState` rebuilds, so the bar and the close
prompt take the new name. `app/test/file_workflow_test.dart` holds both cases;
on the rebuilt app a Save As through the real chooser changed the bar from
"find" to "renamed" (`target/b20/look/07-after-save-as.png`). Commit:
`B19 — Save As renames the script in the app bar`.

<a id="b20"></a>
### B20 — Closing the window while a script is still opening throws

**Evidence (reproduced).** Promoted from the 2026-10-08 B16 note under
[Found along the way](#found-along-the-way). Six of six early closes of the
current release build on the 120-page reference logged
`Unhandled Exception: Bad state: No element` from `EditorController`'s
constructor (`target/b20/base-*/first-process.log`). `_onExitRequested` runs
`core.shutdown()`, which closes the documents the core holds; one still being
opened is not among them, so it arrives afterwards as a closed handle — or the
process goes while its journal is half written, which is the orphaned
`<id>.log.tmp-…` the note recorded.

**Change.** Dart only, in `app/lib/app.dart`: a quit waits for an open the core
has not answered yet, nothing is opened or adopted once a quit is agreed, and a
document that arrives then is closed instead of handed to an editor.

**Effort.** S.
**Result:** 2026-10-09 — every request that makes the core open a document
goes through `_SluglineAppState._opening`, and the exit handler waits for those
before `shutdown`. `app/test/file_workflow_test.dart` holds the order; on the
rebuilt app eighteen of eighteen early closes logged nothing and left no
journal file, in the same ~315 ms, and `tools/check_clean_close.py` passes
(`target/b20/`). Limitation: a quit waits for an open in flight, so one stuck
on a dead mount holds the window until the read returns. Commit:
`B20 — a quit waits for the script that is still opening`.

<a id="b21"></a>
### B21 — The status line gives a block that prints nothing the wrong page

**Evidence (reproduced in a unit test).** Promoted from the 2026-10-06 W5 note
under [Found along the way](#found-along-the-way). `PageIndicator._adopt` gave
a note, synopsis or section the page its predecessor *began* on: under a
paragraph running from page 1 to page 3 the label read "Page 1 of 3" between
two lines that both read "Page 3 of 3".

**Change.** Carry the page the text above *ends* on to the blocks that reach no
page. Still only Rust's snapshot, read back; a block that prints keeps the
pages of its own lines.

**Effort.** S.
**Result:** 2026-10-09 — `_adopt` records each block's last page as well as its
first and gives non-printing blocks the last page of the text above them.
`app/test/editor/page_indicator_test.dart` holds the note case and passes with
the go-to-page tests. Commit:
`B21 — a block that prints nothing takes the page the text above ends on`.

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
**Result:** 2026-10-06 — verified in `eab21a4`. Reproduced with the PDF dump
example and Poppler: both sung lines retain `~` at the dialogue indent; a
standalone lyric removes it. The [Fountain reference](https://fountain.io/syntax/#lyrics)
says lyrics are always forced and their tilde is removed, while its
[dialogue rule](https://fountain.io/syntax/#dialogue) says any text after a cue
or parenthetical is dialogue; it does not resolve their overlap.
[Screenplain](https://github.com/vilcans/screenplain/blob/abf0d0800ab0b9dfd5bbe780137641e746afbad4/screenplain/parsers/fountain.py)
keeps the tilde in exported dialogue HTML and also in standalone action
(it has no lyric recogniser).
[Afterwriting's parser](https://github.com/afterwriting/aw-parser/blob/090e911c49599e0dbe41229e4f6a2c0f9639df8c/parser.js)
keeps the speech's dialogue kind but converts each leading `~` line to italic
markup. Both were run, not merely read.
[FountainJS](https://github.com/jonnygreenwald/fountain-js/blob/a0e57b77344c4fc333bd3ca2a653a58a9d62e0c1/src/token.ts)
was also run: it produces lyric tokens inside dialogue after a parenthetical or
spoken line and removes the tilde in HTML; directly under a cue it throws on
an undefined previous token. Decision: retain the dialogue block and literal
editable source, but resolve sung hard lines in Fountain for output, remove
only their lyric marker and italicise their wrapped rows. Do not detach a song
from its cue or change speech continuation rules.
ADR 0047 records that choice. Fountain owns recognition; cached layout rows
carry marker identity and hard-line style scope, and preview/PDF share the
resolved output. Regressions cover whitespace/tab boundaries, literal tildes
at soft wraps, source tiling, mixed speeches, composed emphasis, page splits
and cached/incremental pagination. A rebuilt release preview under Xvfb and a
Poppler raster show italic, marker-free sung dialogue with literal editor text
unchanged. PDF smokes also verify a two-page song and regular continuation
furniture. Default corpus layout goldens, PDF hashes and line-break fixtures
remain unchanged. Verification passed: 613 workspace tests, rustfmt, clippy
with warnings denied, layering/version/reference checks, Flutter analysis and
534 tests, Linux release build and network isolation.
All seven native integration suites passed under Xvfb, including preview/PDF
export and both keystroke budgets (journalled p99: 4.78 ms).

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
**Result:** 2026-10-06 — verified in `9b750f2`. Reproduced before changing
anything: every committed layout golden had `-3 -> ( 58, "1.")` under `PAGE 1`,
and a PDF exported from the reference script with the dump example read back
through Poppler with `1.` at the top right of its first screenplay sheet.
`PageConfig::number_first_page`, off by default, now decides it. The paginator
leaves the page-number line off the page numbered 1 unless it is set;
`Page::number` is still `Some(1)`, so the count, every later number, the
checkpoints and every row of script are the same under either setting. It is
stored as `number_first_page` with paper size and scene numbers and offered as
“Number the first page” under Page defaults. ADR 0048 records the decision.
What turned out differently from the item: only the paginator needed the rule.
Preview and PDF draw the lines they are given and followed without a change.
The editor's page view paints its own sheet numbers, so it reads which pages
of the paginated snapshot carry a number line (`PageIndicator.printsNumber`)
rather than the preference, which would have been a second copy of the rule in
Dart. The export dialog carries the saved value and has no toggle of its own,
as with heading weight, so the PDF cannot disagree with the sheets on screen.
Continuous view's page-break labels are the application's count, not a picture
of the sheet, and are unchanged. A one-page script still draws no sheet in page
view at all — the gap already listed under Found along the way — so there the
change shows only in preview and PDF.
Goldens were regenerated on purpose: each of the twelve layout goldens lost
exactly that one line, and all 22 PDF hashes changed. With the option on, all
22 PDFs reproduce the previously committed hashes byte for byte, so the new
default differs from the old output by the number alone. Line-break fixtures
are unchanged. Regressions cover both papers, page 2 remaining `2.`, an
explicit page break, an incremental edit on page 1 against a full pagination
under both settings, the two setups being cached apart, the stored preference
and both dialogs, the preview, and page view's painter, whose test fails when
its question is removed. Verification passed: 621 workspace tests, rustfmt,
clippy with warnings denied, layering/version/docs/reference checks, Flutter
analysis and 539 tests, Linux release build and network isolation. All seven
native integration suites passed under Xvfb, including a new one that drives
the real Preferences dialog and reads the exported PDF back under both
settings, and both keystroke budgets (journalled p99: 4.53 ms). The rebuilt
release under isolated XDG roots and Xvfb shows the first sheet unnumbered by
default and with `1.` when the stored preference is on.

<a id="f7"></a>
### F7 — `@McCLANE` prints as `MCCLANE`

**Evidence (reproduced).** On finalized X6 main `6aa026c`, all four retained
layout consumers fail before the fix, and a fresh PDF exports `@McCLANE` as
`MCCLANE` and `@éßMcClane` as `ÉßMCCLANE`. The saved PDF and Poppler bbox
extraction are retained under `target/retained-features/f7/`, alongside the
semantic red log and the retained test's initial compile failure.

**Prerequisite resolved by ADR 0059.** X6 preserves authored source case,
removes only redundant canonical forcing markers, and leaves no hidden
persisted pin. A deliberately typed lowercase or mixed-case Character therefore
needs `@` on reload and prints in that authored case. That is an intentional
product choice, not silent uppercase normalization. F7 follows it in ADR 0060.

**Change.** Forced Character blocks keep their case in the editor, single/dual
pagination, generated continuation names, preview resolved runs and PDF.
Unforced Character, SceneHeading and Transition capitalisation is unchanged.
Neither source text, classification, identity nor offset boundaries change.

A second reproduced interaction held a live forced `ÉLODIE (on the phone)`
but dropped `@` on Save and reopened the extension in capitals. ADR 0060 refines
marker necessity: retain `@` when the shared offset-stable uppercase mapping
would change authored rendering. Expanding mappings such as `ß` still need no
extra marker. Save remains read-only with respect to the actor, selection,
history and pins. This is the final serialization policy for X7.

Verified: 743 Rust tests, 750 Flutter widget tests, all seven native suites
(97 tests), binding drift, formatting/clippy/analyze, layering/version/docs and
reference checks. Native coverage includes actual painting, single/dual
pagination and continuation runs, selectable PDF output, force-only cache
invalidation, BOM/CRLF Save/reopen and one-step Undo/Redo. The deliberate golden
change preserves `mcCLANE` in the layout and Letter/A4 PDF hashes; no source or
line-breaking fixtures changed. After-Find journalled p99 is 4.79 ms.
Evidence and rejected draft runs are retained in `target/retained-features/f7/`.

**Effort.** S; prerequisite decision is resolved.

**Source projection.** The current X4 integration projects original UTF-8
spans before display casing. F7 keeps that path intact and chooses casing before
row/run preparation; Unicode source-boundary regressions hold the two policies.

**Found along the way (read).** The pre-existing continuation formatter checks
the raw cue's trailing `(CONT'D)`: paired markup after an authored continuation
extension can still produce a duplicate suffix. That separate furniture defect
is unchanged by authored-case rendering; no marker interpretation is duplicated
in this change.

**Result:** 2026-10-09 — individually verified in `db5f2c0`. The acceptance
paths and final serialization interaction above passed. Release startup best
373.285 ms, Xvfb RSS best 268.31 MiB, a ten-second idle interval with zero ticks
and voluntary switches, and all 15 ordinary closes passed with saved bytes
intact. Release build and no-network script passed. Logs, PDFs, bbox extraction,
initial failures and process JSON remain in `target/retained-features/f7/`.
Desktop manual gates remain pending.

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
**Result:** 2026-10-06 — verified in `312c74e`. The test was written first and
it failed, so this was a defect and not only a missing proof. Against the
engine as it stood, 898 of 12,374 single-block edits of the corpus on short
pages gave pages a full pagination does not, and on the reference feature at
US Letter shortening the paragraph page 5 begins with left 119 pages and a
break in the wrong place. Three causes, all in how reuse was licensed: a
checkpoint was trusted even when its own first block was the one edited; the
pages after an edit were kept on the strength of a script cut off at the next
checkpoint and one matching row; and an empty forced page was credited with
the first block of the script, which laid a 14-page script out as 22.
The fingerprints were sound; the restart and the stop were not, so ADR 0049
refines ADR 0022 rather than replacing it. The paginator now records which
pages an element began and how far it had read by then, and an incremental run
resumes and stops only on that record. A full pagination is unchanged: no
golden, PDF hash or line-break fixture moved.
`crates/layout/tests/incremental_differential.rs` is the test, 19 cases in
about four seconds. What turned out differently from the item: it compares
`PaginatedScript`'s pages, title page and checkpoints (there is no
`PaginationView` in `crates/layout`, and `stats` legitimately differs between
the paths). Corpus files are a page or two, so each is tiled and set on five-
and eight-row pages to reach checkpoints, and the reference feature covers real
paper. An insert can never take the incremental path, so the scene heading is
pushed across the boundary by growing a block, and a second case makes the
same push with an insert and holds the engine to a full pagination. Dual
dialogue is not yet set side by side (X1), so “the partner moves” is the
partner's speech crossing a page break and its `^` being removed.
The second half of “done when” was checked rather than assumed. 16 of the 19
tests fail against the old engine, 13 on differing pages. Reuse was then
broken on purpose 17 ways and every one fails the file; two survived the first
attempt, which produced the end-of-script heading case and took a redundant
line out of the fix. Verification passed: 640 workspace tests, rustfmt, clippy
with warnings denied, layering/version/docs/reference checks, Flutter lockfile,
format, analysis and 539 tests, Linux release build, network isolation and all
seven native integration suites (journalled keystroke p99 4.72 ms). The
incremental budget holds at 0.42 ms release and 4.7 ms debug. The 1.85
toolchain is not installed locally, so the MSRV check is left to CI's job.

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
**Result:** 2026-10-06 — complete in `4d53a17` (ADR 0050). One release-process
harness, `tools/check_runtime_budgets.py`, now measures all three properties in
its own CI step, in the release workflow and in release preflight. Both jobs
install `xdotool` and retain JSON measurements and full process logs on failure;
the Dart suite inventory is unchanged. No production timing marker was needed.
The shipped GTK runner shows its window on the first frame; fresh no-argument
startup opens the library (read in the startup code), so the harness passes a
zero-byte Fountain file and checks its journal separately. The caret is static,
and the first frame precedes script adoption: this is process startup, not an
editable-caret or evicted-file-cache claim. Direct X focus was established and
read back under bare Xvfb, with no window manager.

Startup remains < 500 ms, best of five. Idle requires two measured quiet seconds
within 60 seconds, then zero CPU ticks, voluntary thread switches and changed
threads in at least one of three consecutive ten-second intervals. Restarting
for every idle sample initially repeated late engine cleanup and failed all
three zero-CPU samples; that rejected control is retained. Consecutive intervals
move past cleanup and the permitted 30-second status refresh without a fixed
startup sleep or a percentage allowance. RSS reads the larger endpoint value
per interval and the best of three. The new 320 MiB Xvfb ceiling is deliberate,
with roughly 10% headroom above the initial 272–290 MiB baseline and
`LP_NUM_THREADS=4` / scale 1 pinned; the numeric 250 desktop limit is preserved,
with MiB units stated, in the same harness's manual profile and pending manual
gate 5. A software-rendered pass does not establish whether there is a real GPU
memory overrun.

All three deliberate regressions were rejected after rebuilding the runner,
one at a time: a 750 ms first-frame delay gave 1139 ms best startup; a 10 ms
periodic timer never achieved quiet within 60 seconds; a touched and retained
192 MiB allocation gave 458 MiB best RSS with the final sampling method. Every
injection was reverted byte for byte and the clean bundle rebuilt. Final clean
figures: 371 ms best startup, a ten-second interval with zero ticks/switches/
thread changes, 285 MiB best RSS (all readings 285–307 MiB). Reports, injection
patches and the rejected control remain under `target/f9/`.

Verified: 640 Rust tests, rustfmt, clippy, layering/version/docs/reference
checks; the pinned Flutter lockfile, formatting, analysis and 539 tests; Linux
release build and bundle size, network-library and namespace-version checks;
all seven native integration suites under Xvfb (journalled keystroke p99
3.35 ms); preflight shell syntax and shellcheck. No golden or fixture changed.
Rust 1.85 is not installed locally. The GPU manual gate and GitHub validation
of these unpushed commits remain pending.

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
**Result:** 2026-10-06 — verified in `b102636`. Reproduced the missing library
filter focus and Ctrl+W with failing widget tests before changing production.
Ctrl+N uses the existing path-based New chooser; Ctrl+O opens a shared modal
quick-open list, filtering title or path, with Browse always available; Ctrl+W
returns to the library, including in distraction-free mode. Chose a modal so
it uses the existing autosave suppression and owns its keyboard focus; Browse
hands off to the current chooser, with no new dependency or W7 chooser change.
The library focuses its filter, highlights and scrolls Up/Down selection, and
opens with Enter; missing rows remain visible and cannot open. The palette,
shortcut reference and keyboard map include all three actions. Choosing the
current path keeps its dirty session and history. A departure checks
`confirmClose` after the destination is selected, holds input and autosave,
and retains the old session until the destination opens successfully; Cancel,
a failed save/open, or edits later than a save keep the editor. Each new script
gets a fresh editor page so focus, scroll and panels cannot carry over.
Thirty new widget tests cover the keys, a complete pointer-free workflow,
long/missing lists, palette/Browse, failures, cancellation, source/history,
input and autosave. A new native writing case uses disposable XDG roots,
Tab/Enter through the save confirmation, and exact saved Fountain bytes read
back from disk; input values go directly to our TextInputClient as in the IME
suite. Verified locally: 640 Rust tests, 569 Flutter tests, formatting, clippy,
analysis, enforced lockfile, layering/version/docs, release build, 28.89 MiB
bundle, static network-library and network-namespace version checks, and all
seven Xvfb native suites (journalled keystroke p99 1.99 ms). Release-process
budgets pass: 372.773 ms best startup, a 10.019-second zero-tick/zero-switch
interval with no changed threads, and 275.51 MiB best RSS below the 320 MiB
Xvfb ceiling. Logs and reports are retained under `target/w1`. The 250 MiB GPU
budget remains pending manual gate 5. No binding or golden was regenerated.

<a id="w2"></a>
### W2 — The command palette is missing commands

**Evidence.** `editorCommands` (`app/lib/editor/commands.dart:32`) has no entry
for Preferences, Spell checking, Keyboard shortcuts, show/hide navigator,
distraction-free, page view versus continuous, text size, or back to the
library. The first three are in the overflow menu only.

**Change.** Add them, and anything W1, W3 and W4 introduce. The palette should
reach every command the app has.

**Effort.** S.
**Result:** 2026-10-06 — verified in `64c8d2e`. Reproduced all eight missing
entries with failing widget assertions on command rows before changing the
app. An initial assertion also counted the search field and passed incorrectly;
the corrected failure and both logs are retained. Added Preferences, Spell
checking, Keyboard shortcuts, show/hide navigator, enter/leave distraction-free
mode, page/continuous view and increase/decrease text size. W1's file actions
remain; W3 and W4 are still separate open items and will add their commands
when implemented. Debug builds also reach the existing Pagination debug dialog.
The product choice is to name the action for the current view and omit actions
with no handler or at a text-size bound (12/24). Preferences and spelling open
their existing dialogs; exports remain inside the preview. Navigator actions
are available after leaving distraction-free mode. A narrow window offers Show
navigator for its temporary drawer; Ctrl+K also works from the drawer's search,
closes it and focuses the palette without changing the docked preference.
Page-view changes use the existing atomic preference writer, and display actions
leave screenplay output setup alone. Preferences/shortcut dialogs share modal
autosave suppression across palette, keyboard and toolbar entry points.
Widget tests prove action execution, both view directions, preference failure,
limits and unavailable actions, 640/1200-pixel navigator behavior, focus return
and autosave held until dialog dismissal; fullscreen request counts use a mocked
window channel. A native Xvfb case drives the real preference writer and GTK
channel, reads `prefs.json`, opens all four added dialog actions including debug,
and checks unchanged source, selection, dirty state, output setup and exact
BOM/CRLF Fountain bytes. Verified all 640 Rust tests, rustfmt, clippy, layering,
version and docs checks; the enforced Flutter lockfile, 102-file format check,
analysis and all 590 widget tests; the 28.91 MiB Linux release bundle, network
library and isolated `--version` checks; all seven native suites, journalled
keystroke p99 3.36 ms. Release-process budgets passed: best startup 371.548 ms,
one 10.007-second interval with zero ticks/switches/thread changes, best RSS
273.85 MiB against the 320 MiB Xvfb ceiling. All samples and earlier test/lint
failures are retained under `target/w2-*`. The 250 MiB GPU claim stays pending
manual gate 5. No dependency, binding, golden or line-breaking fixture changed.
W2 is committed locally; W1's push passed CI run 37572492814. Stop here; W3 is
next, and no adjacent item was started.

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
**Result:** 2026-10-06 — verified in `9e664bd`. Reproduced the split instead
of an embedded newline with three failing widget cases (Action, Dialogue and
Note), retained in `target/w3-widget-red.log`. Shift+Enter and numpad
Shift+Enter now call `doc_line_break`; Rust reuses `BlockKind::is_multiline`
and runs the ordinary Enter plan in other kinds. Deleting a selection and
inserting the break are one isolated undo transaction, journalled through
`inferring`, with no kind table in Dart. Undo restores the original selection
and source; typing on either side stays separate. The product choice is for
Shift+Enter to edit even when a completion has been deliberately highlighted;
plain Enter keeps its completion behavior. ADR 0051 refines ADRs 0017/0041 for
that distinction. The palette offers Insert line break, KEYMAP and F1 teach it,
and input-method newlines still split, including while Shift is held.
Widget cases exercise TextInput typing, selection replacement, Unicode/numpad
offsets, completion priority, undo/redo and palette focus. Rust cases cover all
supported kinds and single-line fallbacks, reversed cross-element selections,
invalid offsets, read-only refusal and typing isolation. A real journal is
replayed through break/undo/redo and save, preserving untouched BOM/CRLF title
and opaque bytes. Native cases use the writing suite's per-character controller
typing helper, send Shift+Enter through the surface and save/reopen actual
Fountain files with adjacent lines in all three kinds. Initial native fixtures
had test-input/selection failures; those logs remain, alongside an incorrect
open-method compile failure and a corrected CRLF assertion. The Note-only
fixture's separate zero-page status error is recorded under Found along the
way and left unchanged; its final fixture includes printable Action text.
Verified all 646 Rust tests, rustfmt, clippy, layering, version and docs checks;
the enforced Flutter lockfile, 103-file format check, analysis and all 597
widget tests; all seven native suites (63 tests), journalled keystroke p99
2.36 ms; and the 28.91 MiB Linux release bundle, network-library and isolated
`--version` checks. Release-process budgets passed: best startup 381.486 ms,
one 10.009-second interval with zero ticks/switches/thread changes, best RSS
274.71 MiB against the 320 MiB Xvfb ceiling. Every startup/idle/RSS sample and
process log is retained in `target/w3-runtime-budgets.json`; other evidence and
failures are under `target/w3-*`. The 250 MiB GPU claim stays pending manual
gate 5. FRB 2.12.0 bindings were regenerated; no dependency, lockfile, golden
or line-breaking fixture changed. W3 is committed locally, unpushed. Stop here;
W4 is next, and no adjacent item was started.

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
**Result:** 2026-10-06 — W4's navigation is verified in `831f98b`, with the
separate pre-existing idle-gate failure below still open. Reproduced the absent
palette command and shortcut with two failing widget cases retained in
`target/w4-widget-red.log`. The palette now offers “Go to page…” and `Ctrl+L`
opens the same prompt; `Ctrl+G` remains Find next. KEYMAP and F1 teach it.
`PageIndicator.positionForPage` maps the paginator's first source line to the
editor's wrapped UTF-16 start, without deriving a boundary. Page 1 means the
first document block, including source-only opening material, and explicitly
scrolls to zero even when the caret is unchanged in a restored viewport. Three
failing scroll cases are retained in `target/w4-widget-scroll-red.log`.
The existing page-break map and single-page sheet behavior are unchanged.
The prompt validates against the live page count, disables Go before a snapshot
arrives and refuses absent blocks or shortened source lines. Invalid input and
cancellation preserve selection and source; successful navigation collapses
the selection, reveals the target and returns focus to the editor. The modal
uses the page's existing autosave suppression. Native cases use actual Rust
pagination in both views, with a title page, opening Note and one Action block
spanning several pages; palette, shortcut and numpad Enter navigation preserve
source, BOM/CRLF disk bytes, revision and journal state. Widget cases also cover
soft wraps, astral UTF-16 offsets, pending and refreshed snapshots, stale
targets, validation, cancellation, input-method submission and autosave.
Verified all 646 Rust tests, rustfmt, clippy, layering/version/docs; the enforced
Flutter lockfile, 105-file format check, analysis and all 616 widget tests;
all seven native suites (65 tests), with journalled keystroke p99 3.78 ms; and
the 28.93 MiB Linux release bundle, network-library and isolated-version checks.
Startup and Xvfb RSS passed: the first report's best values were 371.220 ms and
260.73 MiB; the retry's were 368.433 ms and 278.60 MiB against the 320 MiB
headless ceiling. **Idle did not pass:** both W4 runs, and a clean isolated W3
control at `351dada`, had the same one-switch main-thread intervals. The failed
reports, source inspection, control bundle and component digests are retained
under `target/w4-*` and recorded under Found along the way. No threshold or
harness was changed, and no all-green runtime/release-candidate claim is made.
Earlier compile and fixture failures also remain in the evidence logs.
The zero-page and single-page findings remain unchanged; the separate
code-read `Ctrl+Home` restore issue is recorded for investigation. Manual
gate 5's real-GPU 250 MiB claim remains pending. No Rust API, binding,
dependency, lockfile, golden or line-breaking fixture changed. W2+W3 were
pushed before W4; CI run 37577185534 passed on `351dada`. W4 is committed
locally, unpushed. Stop here; W5 and adjacent implementation were not started.

<a id="w5"></a>
### W5 — The preview always opens at page 1

**Evidence.** `PreviewView` builds a `ListView` with no initial offset
(`app/lib/preview/preview_view.dart:82`), and `ExportDialog` is not told where
the caret is.

**Change.** Open the preview scrolled to the page the caret is on.

**Effort.** S.
**Result:** 2026-10-06 — verified in `5385380`, with the pre-existing idle-gate
failure below still open. Reproduced first: six failing widget cases
(`target/w5-widget-red.log`) and, against the real core, the preview opening at
offset 0 with the caret on the last line of page 2 (`target/w5-native-red.log`).
The editor now hands the dialog the caret's block id and wrapped line, with the
blocks above it nearest first, and `PreviewView.sheetOf` finds that line in the
pagination the preview is about to draw. It is not the status line's page: that
is the page of the top visible line, from a snapshot that trails the text and
may be absent — the release smoke shows "Page 6 of 20" with the caret on page 7.
Choices: page 1 opens at the top with the title page, which has no caret
position of its own and would otherwise sit above the fold; a caret in
something that prints nothing opens where the text above it ends; a line the
pagination lacks falls to the nearest line above in its block, and `(MORE)` /
`CONT'D` furniture is nobody's line; the offset is clamped before the first
frame so the last page is not sprung back into range; and it happens once — a
later pagination, paper or size leaves the view alone. Differently from the
item: the sheet list became a fixed-extent `ListView.builder`. Left to measure
its children it laid out every sheet above the target — 89–148 ms for the last
of 120 pages in the test VM against 19 ms — and over-reported its length by 30%
from the top (`target/w5-first-frame.log`); sheet size, margins and gaps are
unchanged and a test holds them. Thirteen deliberate mistakes each fail a test
(`target/w5-mutations.log`). KEYMAP, README and CHANGELOG say what it does.
Verified all 646 Rust tests, rustfmt, clippy, layering/version/docs and the
reference script; the enforced Flutter lockfile, 106-file format check,
analysis and all 641 widget tests (25 new); all seven native suites (67 tests,
2 new, real pagination with a title page, CRLF and astral text), with
journalled keystroke p99 4.42 ms; and the 28.93 MiB Linux release bundle,
network-library and isolated-version checks. The release bundle was driven
under Xvfb with real keys: `Ctrl+L` to page 7 then `Ctrl+P` shows sheet 7 at
the top, and page 1 shows the title page (`target/w5-smoke/`). Startup and Xvfb
RSS passed: best 370.723 ms and 266.29 MiB against the 320 MiB headless
ceiling. **Idle did not pass:** the same one-switch outer intervals W4 recorded
and reproduced on a clean W3 control, in a harness that never opens the
preview (`target/w5-runtime-budgets.json`, `.log`). No threshold or harness was
changed, and no all-green runtime or release-candidate claim is made. Manual
gate 5's real-GPU 250 MiB claim remains pending. Three findings are recorded
under Found along the way and left unchanged: the preview keeps its pixel
offset rather than its page across a zoom or paper change, the status line
gives a non-printing block the page its predecessor began on, and W1–W4 have
no changelog entries. No Rust API, binding, dependency, lockfile, golden or
line-breaking fixture changed; no ADR, since nothing an accepted record decided
is altered. W4 and W5 are committed locally, unpushed. Stop here; W6 is next,
and no adjacent item was started.

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
**Result:** 2026-10-07 — verified in `4910ab2`. Reproduced on the real Hyprland
Wayland session: the release window stacked a GTK header bar above the app bar
(`target/w6-before.png`). The runner now recognizes GNOME in the colon-separated
`XDG_CURRENT_DESKTOP` list and keeps the existing X11 GNOME Shell check; other
Wayland desktops leave decoration to the compositor. Screenshot inspection of
the rebuilt native Wayland window confirms no GTK bar (`target/w6-after.png`).
F11 entered full screen (Hyprland reported both fullscreen states as 2), then
left it (both 0); compositor movement and resizing produced an undecorated
1100 × 700 floating window (`target/w6-fullscreen.png`,
`target/w6-move-resize.png`). GNOME is unverified: no GNOME session was available.
No forced undecoration, environment override, preference, or dependency was
added. Passed 646 Rust tests, 641 Flutter widget tests, all 67 native integration
tests, Rust formatting/clippy, Dart formatting/analysis, enforced lockfile,
layering/version/docs checks, Linux release build and network-isolation smoke.
The pre-existing W4/W5 idle-gate failure was not rerun or changed.

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

**Result:** 2026-10-07 — verified in `c9d740f`; chose option A (ADR 0052).
Reproduced New on the real release window (`target/w7-before.png`): it started
in `$HOME`, with no search, bookmarks or folder creation. GTK already ships
with the runner, so its native dialog supplies these features and keyboard
navigation without a selector plugin, HTTP client or new dependency; option B
would retain a second browser to maintain. ADR 0052 supersedes ADR 0015 and only
ADR 0037's retained custom-chooser decision.

The old browser is removed. `slugline/window` now performs asynchronous local
selection with file-type/All files filters, directory selection, folder
creation, a remembered parent folder and extensionless-save suffixes. New and
Browse from the editor start beside its current script; Save As, Rename and
Export retain their explicit folders. GTK overwrite confirmation is disabled:
Rust's `AlreadyExists` refusal and Slugline's shared Replace prompt are the one
confirmation; `ScriptIsOpen` is never retried. Existing save/export path
injection contracts remain unchanged.

A throwaway real-GTK Xvfb smoke passed Open, extensionless Fountain/PDF names,
explicit extensions, an existing destination without a GTK overwrite prompt,
TrueType selection, directories and Escape cancellation. On real Hyprland,
New created an extensionless choice as a `.fountain` file; Save As displayed
only Slugline's Replace prompt and wrote the selected destination after it.
Closing the chooser preserved the editor; closing its parent with a chooser
active exited 0. Screenshot evidence: `target/w7-native-new.png`,
`target/w7-wayland-created.png`, `target/w7-save-as-confirmation.png`.
GNOME remains unverified. The startup log included an OpenGL initial-size
timeout warning; no duplicate chooser-response or teardown warning was observed.

The initial smoke driver retained GTK's suggested suffix and produced
`.fountain.fountain`; selecting the whole entry and accepting completion
corrected the driver, not product code. One concurrently built debug/release
smoke stalled and was cancelled; the isolated run passed. An old autosave test
expected the removed chooser's title; its meaningful external-change/save-hold
cancellation case now uses the native-selection seam. Incidental chooser-widget
and copied-argument assertions were removed rather than repinned. Throwaway
smoke scripts, fixtures and isolated desktop state were removed.

Final verification: 646 Rust tests, 641 Flutter widget tests, all 67 native
integration tests, Rust formatting/clippy, Dart formatting/analysis, enforced
lockfile, layering/version/docs checks, Linux release build and headed
network-isolation smoke passed. Bundle: 30,331,354 bytes (28.93 MiB).
No Rust API, generated binding, dependency, lockfile or golden change. The
pre-existing idle-gate failure and all previously recorded findings remain
unchanged; no threshold or runtime-budget harness was changed or rerun.

<a id="w8"></a>
### W8 — Find highlights only the current match

**Evidence.** The painter draws the selection and nothing else for find; the
controller already holds every match (`EditorController.matches`).

**Change.** While the find bar is open, tint every visible match. When Find is
opened with a selection inside one block, start with that text.

**Effort.** S.
**Result:** 2026-10-07 — verified in `7acce51`, with the pre-existing idle-gate
failure below still open. Reproduced first: 14 widget cases failing on the
unchanged tree (`target/w8-widget-red.log`), and the release bundle built
before the change, driven with real keys under Xvfb — `house` matching seven
times with one of them marked, and Find opening on the last query with another
word selected (`target/w8-smoke/before-dark-*.png`).

The page tells the surface the bar is open (`EditorSurface.highlightMatches`)
and the painter tints `EditorController.matchesIn(block)` for the rows in its
band: grid cells through `EditorGeometry`, every row a wrapped match touches,
under the selection and under the text. `EditorController.startFind`, which the
page calls before it builds the bar, makes a selection inside one block the
query and otherwise resumes the last search; the toggles and the element filter
carry over either way. Rust still decides what matches; Dart adds no rule.

Choices. The tint is a 16% wash of the text colour, not the accent: the theme
keeps the accent for one thing at a time, and the match the caret is on is
already the selection, painted over its tint. The query outlives the bar for
`Ctrl+G`, so with the bar closed nothing is tinted. The seed is the block's
stored text — not the capitals a heading is drawn in, and not the clipboard's
Fountain. A selection across blocks does not seed, since no match crosses one;
nor does one across a `Shift+Enter` line break, which the one-line field cannot
show; nor does one that is already a match of the last search, so a reopened
search keeps the query as it was typed instead of respelling `house` as the
`HOUSE` it stopped on.

Differently from the item, two things the tint would otherwise have shown
wrongly. The search on opening moved out of the bar's first post-frame callback
into `startFind`, so the bar's first frame is never drawn over the previous
query's matches; that also corrects a count that went stale when Find reopened
on a match selected by hand ("2 of 7" on the first match,
`target/w8-smoke/before-dark-find-over-selection.png`). And `_selectMatch` now
notifies when a search lands on the selection already in force: "Match case"
could drop matches without moving the caret, and nothing was told to redraw.

Twenty new widget tests read the rectangles off the surface's own painter with
a recording canvas — a widget test has no script face, so its pixels say
nothing about what is behind the text. Two native tests read the real pixels,
in the face the script is set in, over the real core: a lower-case heading
drawn in capitals, offsets past an astral character, and the toggle case.
Twenty deliberate mistakes each fail a widget test and three fail the native
one (`target/w8-mutations.log`, `target/w8-native-mutations.log`). One early
mutation revert used `git checkout` and discarded the uncommitted work in
`editor_controller.dart`; it was re-applied before any result here was taken,
and every later revert restores from a copy. KEYMAP and CHANGELOG say what Find
does now.

Verified all 646 Rust tests, rustfmt, clippy, layering/version/docs and the
reference script; the enforced Flutter lockfile, 108-file format check,
analysis and all 661 widget tests; all seven native suites (69 tests), with
journalled keystroke p99 4.56 ms; the Linux release build, 30,331,399 bytes
(28.93 MiB), and the headed network-isolation smoke. The rebuilt bundle was
driven with real keys in the dark and the light theme
(`target/w8-smoke/after-*.png`): every match on screen tinted, the current one
selected over its tint, and `DAY` selected then `Ctrl+F` giving "DAY", "1 of
2". That was Xvfb with software rendering, not the Hyprland session. Startup
and Xvfb RSS passed: best 374.894 ms and 279.03 MiB against the 320 MiB
headless ceiling. **Idle did not pass:** the same one-switch outer intervals
(1, 64, 1) W4 recorded and reproduced on a clean W3 control, in a harness that
never opens Find (`target/w8-runtime-budgets.json`, `.log`). No threshold or
harness was changed, and no all-green runtime or release-candidate claim is
made. Manual gate 5's real-GPU 250 MiB claim remains pending.

Five findings are recorded under Found along the way and left unchanged. No
Rust API, binding, dependency, lockfile, golden or line-breaking fixture
changed; no ADR, since no accepted record decides how Find is presented.
Committed locally, unpushed. W9 is next; no adjacent item was started.

<a id="w9"></a>
### W9 — Previous versions can be restored but not looked at

**Evidence.** `app/lib/library/backups_dialog.dart` lists a time, a size and a
Restore button per version.

**Change.** Let the writer see a version before choosing it — a read-only view
of its text — and open it as a separate copy without replacing the current
script. More useful once S2 exists.

**Effort.** M.
**Result:** 2026-10-07 — verified in `a3b3593`. Reproduced with the unchanged
release bundle: previous versions offered timestamps, sizes and Restore, with
no way to read or copy one (`target/w9-smoke/before.png`). View now opens
selectable, read-only literal Fountain text. This is deliberately a source view
rather than print preview: title-page fields, markup and source-only material
are all available for inspection, with no second screenplay parser in Dart.
Back returns to the list. Existing Restore behavior is retained.

Open as copy asks GTK for a new filename, atomically writes the exact snapshot
that was viewed, then starts a separate Slugline process on that durable file.
Saving first gives the copy ordinary journalling, saving and recovery without
temporary-file lifetime rules. The copy uses the loaded snapshot even if
retention deletes its backing backup meanwhile. Existing files are never
overwritten, and open-script destinations are refused even if their file is
missing. A collision leaves the view open for another name; a launch failure
names the saved copy and retries opening it without writing again. Reading and
copying leave the original path, dirty flag, journal and document untouched.
Rust does the I/O off the actor; generated Dart/Rust bindings were regenerated.

Three Rust regressions cover exact bytes (BOM, CRLF, Unicode and trailing
whitespace), preservation of unsaved text and journal recovery, unavailable
versions and protected destinations. Six widget regressions cover read-only
selection, returning to the list, read errors, chooser cancellation, refused
writes, launch retry and in-flight modal lifetime. Verified 649 Rust tests,
670 widget tests and all 69 native tests, rustfmt/clippy, Dart formatting and
analysis, enforced lockfile, layering/version/docs and binding freshness.
The release build passed when run serially after the native suites; an earlier
concurrent release/native build collided over `build/lib/libapp.so`. Headed
network isolation passed. Native journalled keystroke p99 was 3.20 ms; no
process runtime budgets were rerun, and the known idle failure, thresholds and
harness remain unchanged.

Real-window release smoke proved the literal view and attempted typing were
read-only, the original-path refusal preserved the file and unsaved journal,
and an exact copy opened in a second process with its own journal. Editing and
saving the copy left the original byte-identical, and the original unsaved work
remained saveable. Restore from the view still writes the selected older bytes
and preserves the current draft first, but exposed the pre-existing stale
editor-after-restore handoff recorded under Found along the way; it was not
folded into this item. Evidence is in `target/w9-smoke/` and `target/w9-*.log`.
KEYMAP and CHANGELOG describe the workflow. No dependency, lockfile, golden,
line-breaking fixture or accepted ADR decision changed. The W8 side findings
remain untouched. W10 is the next unblocked item; nothing was pushed.

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
**Result:** 2026-10-08 — installed and verified in `38a60b7`, separately from
the CI writing-test correction `316f210`. Reproduced the missing command and
desktop entry before installation. Built the current source using the normal
`./tools/package.sh` remapping build, passed isolated tarball installation and
uninstallation, and ran its generated user-local installer. The command is
`~/.local/bin/slugline`, the bundle is `~/.local/lib/slugline`, the launcher is
`~/.local/share/applications/com.phagmaier.slugline.desktop`, and the MIME
definition is `~/.local/share/mime/packages/com.phagmaier.slugline.xml`.
The desktop session and existing launcher shell lacked `~/.local/bin` despite
the interactive shell having it. Added the PATH export to `~/.config/uwsm/env`
for future sessions, updated the live systemd manager and Hyprland environment,
and restarted `parkershell.service` to inherit it. Set only `text/x-fountain`'s
default to `com.phagmaier.slugline.desktop`; GIO identifies the actual smoke
file as Fountain and opens it with the installed executable and exact filename.
Verified the actual desktop launcher result and launch, installed command
version/help and GUI launch, `/proc` executable/argument identity, native-Wayland
editing and Ctrl+S, exact saved bytes, association-based reopen and visible text,
return to library and clean exit status 0. Screenshots, data and process logs
remain in `target/w10-smoke/`; no personal script was edited. README contains
the exact source-package/install commands, session-PATH setup and default-file
association command. Refreshed the installed documentation from the already
remapped bundle; package smoke, network isolation and docs/version checks pass.
The preceding correction passed 649 Rust tests, 671 widget tests and all 71
native tests, including the suites skipped by the failing hosted run.
The physical mouse double-click was not performed; the actual default-opening
path was exercised with `gio open`. No W10 desktop integration check was
unreachable. The unpaced synthetic-input finding below is not fixed; the known
local idle-budget failure and real-GPU manual memory gate remain unresolved.

<a id="w11"></a>
### W11 — The preview loses its page when the preview size or paper changes

**Evidence (reproduced in a widget test).** The sheet list keeps its scroll
offset in pixels, and a new preview size or paper changes how many pixels a
sheet is (`app/lib/preview/preview_view.dart`). Opened on page 47 of a 60-page
pagination at the default 58%, "Actual size" leaves page 28 at the top of the
pane, "Fit width" page 29 and switching to A4 page 27. Promoted from the
2026-10-06 W5 note under [Found along the way](#found-along-the-way).

**Change.** When the scale or the paper changes, keep the sheet at the top of
the pane: restate the offset from the sheet index and the new sheet extent,
using `PreviewGeometry`. No Rust, pagination or bridge change; the preview
still only reads Rust's snapshot and decides nothing about where a page ends.

**Effort.** S.
**Result:** 2026-10-09 — reproduced in `app/test/preview/preview_keeps_page_test.dart`: pages 28, 29 and 27
at the top instead of 47. `PreviewView` now restates its scroll position in
sheets at the new sheet height when the scale or paper changes, in the same
frame and kept within the list; that file and the five existing preview test
files pass, and the touched Dart is formatted and analyses clean. Limitation: it
keeps the sheet's index, not its text, so the pagination a new paper brings may
put different lines on that sheet. Commit:
`W11 — the preview keeps its sheet when its size or paper changes`.

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
**Result:** 2026-10-08 — verified in `ca867f8`; ADR 0054 records the choices.
Reproduced the corpus PDF before editing: MARTHA and DEREK had the same
x=266.4 and successive y=120/156 positions. They now start at x=165.6/396
on the same y=120 row; inspected the rendered PDF and the actual release
editor/preview under Xvfb.

Adjacent source speeches pair greedily without overlap when the second cue
is marked and both have a body. Hidden source blocks also interrupt pairing.
Unmatched flags print ordinary dialogue, preserving valid Fountain and its
words rather than rejecting the file or reaching across unrelated content.
Equal 28-cell measures at columns 0/32 leave a four-cell gutter; cues use
20 cells at 8/40 and parentheticals 20 at 4/36, entirely within each lane.
A pair that fits a fresh page stays together. Overheight lanes split
independently with the normal two-row/parenthetical protections and only
continuing speakers get (MORE)/CONT'D; pathological small-page raw segments
preserve all source rows without starving the body behind repeated cues.

The editor remains linear but uses paired widths and invalidates unchanged
partners on context changes. This extends the named output work because F4's
source-line/page-anchor invariant requires it, while avoiding a new two-column
caret/selection model. “Toggle dual dialogue” is a Character-only palette
command, registered in `elements.dart` with no new shortcut to collide with
the map. It flips the existing journalled SetDual flag, not editable text,
and preserves selection and undo/redo. The element bar identifies the flag.
No bridge API or binding generation was needed; preview already paints the
paginator's columns. Output emphasis now groups source rows instead of
spatial neighbors, and continued cues retain their complete wrapped names.

Deliberately regenerated the dual corpus layout and its Letter/A4 PDF hashes
because it now prints side by side; every other print golden, including the
reference feature, is unchanged. The differential fixture gained width 28.
Eleven pair-layout regressions and twenty exact incremental/full tests cover
membership, interruptions, partner movement, continuations, source conservation
and checkpoints. Four injected mistakes (pair flag, partner lookahead, editor
invalidation, interleaved emphasis) each failed the relevant test and were
restored; the complete-cue regression also failed before its fix.

Full verification: 662 Rust, 714 widget and 83 native tests; the scoped layout,
document, fountain and editor checks; formatting, Clippy, Dart analysis,
lockfile enforcement, docs and release build. The native dual test drives the
palette through preview, PDF bounding boxes, the journal, Save and reopen.
Open was 88.7 ms, journalled keystroke p99 3.34 ms and frame-build p99 7.53 ms.
Fifteen ordinary release closes and network isolation pass. Isolated process
startup is 376.025 ms and Xvfb RSS 274.93 MiB; idle retains the known
zero-tick/one-main-thread-switch failure, logged under “Found along the way”.
No idle threshold or harness was changed. Evidence and fault logs are under
`target/x1-dual-smoke/`, including `runtime-budgets-isolated.json`.
Real-desktop IME, Orca, HiDPI, print calibration and real-GPU RSS remain
unverified manual gates; no installation, push or merge was performed.

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

**Decision (2026-10-09, ADR 0055).** Implement both directions. WriterDuet can
already export Fountain, but Final Draft's documented export/import paths make
FDX independently useful for migration and editable collaboration. Fountain
remains the native save format: imports are isolated dirty candidates with
recovery journals initialized by a full outcome against blank (ADR 0062);
exports are immutable atomic copies. Conversion
warnings need explicit approval, bound to the exported revision. Preserve
authored content or refuse; do not promise production-layout/revision fidelity.
An unmodified self-authored fixture from the actual Fade In 5.0.15 Linux demo
supplies independent producer evidence, not just a Slugline self-round trip.
The actual consumer exposed absent paragraph bounds: emit standard finite
ParagraphSpec defaults, not a clone of native pagination, so recipient content
does not render blank. Reject stale semantic metadata that contradicts visible
paragraph kinds/alignment/page breaks. Keep approved diagnostics in the
scrollable approval dialog, not the fixed success footer.
Coalesce repeated imported title keys into one editable value; otherwise the
native title form would display the last value and write it into the first.
Resolve title emphasis per hard line, as the native preview/PDF do.

**Effort.** M–L.
**Result:** 2026-10-09 — implementation `6214b67`
(`X2 — Import and export editable FDX copies safely`), with this separate
completion record. ADR 0055 selects both migration import and editable-copy
export, with Fountain remaining native. The syntax-only `fdx -> fountain`
crate uses quick-xml 0.38.3; the bridge alone adds its dependency and owns
session/atomic-copy behavior. Imports create isolated dirty candidates,
warn before adoption, and preserve the old editor on cancellation/failure.
Exports require exact-revision conversion approval and existing replacement/
open-script protection, without changing native path, dirty state or history.

Supported kinds, numbers, disjoint dual speeches, BIU, title text, hard lines,
whitespace and Unicode are preserved. Unsupported authored text is retained
with diagnostics or refused, never silently replaced by empty content.
Nonprinting text may become visible to another recipient, explicitly warned.
Stale metadata cannot override visible paragraph kinds/alignment/page breaks
or conflicting raw text/style/scene-number content. Imported duplicate title
keys coalesce before the single-value native form; title emphasis stays
independent per hard line. Standard finite ParagraphSpec bounds are emitted
because real Fade In otherwise renders ordinary paragraphs blank; these are
interchange defaults, not promised native pagination/font/margin fidelity.
Approved warnings remain in the scrollable dialog, avoiding the reproduced
fixed-footer overflow after eight diagnostics.

Deviation from the pre-implementation recovery design is recorded, not hidden:
ADR 0062 refines ADR 0055's initial journal base. Untitled headers contain only
a checksum, so the full initial title/body outcome is recorded against blank,
without an Undo transaction. An explicit empty forced Action now retains its
native `!` representation to preserve imported caret identity on save/recovery.

Verified 701 Rust tests in 38 suites, 732 widgets and 88 native tests in seven
suites; formatting, clippy/analyze, layering/version/docs/reference, generated
bindings, Rust 1.85, release build and network isolation passed. Four deliberate
guard faults failed their regressions; stale metadata, title-field/row and
large-warning cases fail before and pass after. No goldens were regenerated.
The actual Fade In 5.0.15 producer fixture was imported, killed before document
typing, recovered and saved as Fountain. Its copy export reopened in Fade In
with title/BIU/Unicode/numbers/dual speeches/hard break and all authored words;
native and producer bytes stayed unchanged. Real title-form inspection and
paired scene-card XML import/save also passed.

The unchanged final runtime harness passed startup 375.568 ms, Xvfb RSS
275.29 MiB and an idle interval with zero ticks/switches; 15 stressed ordinary
closes exited zero. Earlier local failures remain retained, not reclassified
as passes; no idle fix or threshold change is claimed. Evidence:
`target/x2-fdx-smoke/` (verification/logs/screenshots and runtime/close JSON).
Genuine Final Draft, physical print calibration, desktop IME/Orca/HiDPI and
real-GPU 250 MiB RSS remain manual. Unrelated title-refresh, duplicate-native-
key and no-op-title-journal findings are recorded below and not fixed.

<a id="x3"></a>
### X3 — Scene numbering commands

**Evidence (reproduced).** The pre-change release palette has no matching
“Number scenes” command (`target/x3-smoke/baseline-number-scenes.png`).
Opening and saving the disposable mixed-number script preserves its bytes.
Scene numbers print only for headings carrying a Fountain suffix; the output
setting does not create them.

**Change.** Explicit “Number scenes” and “Remove scene numbers” commands,
each one journalled undo step with selection restoration. Number from 1 in
source order and deterministically replace existing numbers. Save and export
remain non-numbering operations. ADR 0056 records suffix/whitespace policy and
the reason numbering is an editor operation rather than an output fallback.

**Effort.** S–M.
**Result:** 2026-10-09 — implementation `765e61c`
(`X3 — Number and remove scene suffixes in one Rust transaction`), with this
separate completion record. ADR 0056 chooses explicit Script palette commands,
not automatic output numbering: Number scenes assigns 1..N to every heading,
replacing custom production identifiers; Remove scene numbers recognizes only
Fountain suffixes and removes at most one ASCII separator. Extra/trailing
whitespace and non-heading hashes remain intact. Rust groups the edits,
preserves identities/kinds/flags/title and maps both exact selection endpoints
for one Undo/Redo step. The bridge journals one outcome without reinference.
No-op operations leave revision, dirty state, history and journal unchanged;
Save/export and the existing gutter preference never invent numbers.

Verified 709 Rust tests in 39 suites, 732 widgets and 89 native tests in seven
suites; fmt/clippy/analyze, layering/version/docs/reference, generated bindings,
Rust 1.85, release and offline startup passed. Two mock-echo widget tests were
removed rather than counted as semantics proof. Native palette coverage checks
the actual combined journal record, reverse-selection restoration, save/reopen
and PDF gutters on/off. Deliberate skipped-forced-heading and lost-selection
faults fail behavioral regressions; both were restored and all five document
regressions pass. No goldens were regenerated.

Actual release Number/Remove commands, explicit Save, one-step Undo/Redo and
reopen preserved the title, action `#88#`, dual cue, literal `##`, and expected
numbered/unnumbered source; ordinary closes exited zero. The unchanged harness
also passed 15 stressed closes, 390.380 ms best startup, 274.65 MiB Xvfb RSS and
a zero-tick/zero-switch idle interval. Evidence: `target/x3-smoke/`. No budget
threshold changed. Desktop IME/Orca/HiDPI, physical print calibration and
real-GPU 250 MiB RSS remain manual; no unrelated item was fixed.

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
**Result:** Completed 2026-10-08 in `2790d75` (ADR 0057), integrated with the
first-edit caret correction `3cf175e` on 2026-10-09. Rust supplies source-resolved
inline metadata to both printed-width wrappers and output. The editor styles
content while keeping dim half-cell markers individually editable; Ctrl+B/I/U
wrap selections in one journalled undo group with exact Unicode boundaries and
selection direction. Actual dense markup clipped text and the End caret, so
cached horizontal extents and caret reveal expose it without shrinking the
script, moving printed wraps or changing page anchors. Preserved the integrated
`ı`/`ſ` UTF-8 source-span correction. Deliberately regenerated the differential
fixture; existing layout goldens and PDF hashes passed unchanged.
Verified 728 Rust tests, 739 widget tests and 90 native tests across all seven
suites, formatting/clippy/analyze, bindings, Rust 1.85, docs/layers/version/reference,
release pagination/PDF budgets, release build and offline startup. Real editor,
preview/PDF, formatting/Save/Undo/Redo and dense caret/hit smoke passed; two
behavioral fault injections failed regressions and were reverted. Unchanged
Xvfb gates passed: 368.336 ms best startup, 267.3125 MiB RSS, a ten-second
zero-tick/zero-switch interval, and all 15 stressed ordinary closes exited zero.
Evidence: root `target/x4-resume-smoke/`. No new hosted run was performed; X3's
hosted startup failure remains unresolved. Desktop IME/Orca, print calibration,
HiDPI and real-GPU RSS remain manual gates.
The integration audit reproduced a first dense paste leaving the End caret
offscreen until another character. The surface now initializes its width cache
when attaching the controller, and resets it on controller replacement, so the
first edit requests geometry rebuild and post-layout reveal. The new native
first-paste regression passes under Xvfb; the Find revision cache is retained.

<a id="x5"></a>
### X5 — Outline in the navigator

**Evidence (reproduced).** `doc_navigator` (`crates/bridge/src/api/doc.rs:354`)
returns scenes and characters. Sections (`#`) and synopses (`=`), which
Fountain has for outlining, are not shown, and a scene row has no page number
or length. On current main `a5e2c02`, a real native editor opened section and
synopsis source but displayed neither row. The failing run is retained in
`target/retained-features/x5/baseline-native-red.log`.

**Change.** Show sections and synopses as structure above their scenes, and a
page number and length for each scene.

**Implementation contract (ADR 0058).** Rust supplies source-ordered section,
synopsis and scene nodes with explicit parent/depth; source-only and pre-scene
outline material remains navigable. Scene pagination travels in the existing
async immutable snapshot, as actual start page and occupied eighth-page length,
excluding the title page and counting shared-page bands independently. Edits and
setup changes clear metadata to pending; stale or superseded jobs cannot supply
it, including an already-computed job superseded by a title-page commit. Filter context, every-node jumps, scene-only reorder, character navigation
and quick scene search retain their existing keyboard/sidebar/drawer behavior.

Verification includes 749 Rust and 759 Flutter widget tests, regenerated FRB
bindings and drift comparison, formatting/clippy/analyze, layering/version/docs
and reference checks. Rust regressions cover source order, skipped section
levels, hidden/pre-scene material, parentage after scene move/Undo, shared-page
bands, wrapped headings, title exclusion and continued dual lanes. Controlled
widget deliveries cover old-current, stale, Undo and title races. Native wide
and narrow consumers compare displayed labels to actual Rust snapshots, then
filter/jump, move a scene with its synopsis and Undo to exact source/identities.
All seven native suites passed (99 tests); after-Find journalled p99 is
4.26 ms under unchanged budgets. The Linux release builds. Failed draft compilation and test-assumption runs remain alongside the original
reproduction in `target/retained-features/x5/`.

**Effort.** M.
**Result:** 2026-10-09 — individually verified in `f1ca7f4`. The hierarchy,
async title/edit/history guards and native consumers above passed. Linux release
startup best 383.759 ms, Xvfb RSS best 270.55 MiB, ten-second zero-tick/zero-switch
idle, all 15 ordinary closes with exact saved bytes and the no-network script
passed. Logs and process JSON are in `target/retained-features/x5/`; after-Find
journalled p99 is 4.26 ms. Desktop manual gates remain pending.

<a id="x6"></a>
### X6 — Cleaner Fountain on disk

**Evidence (reproduced).** On published main `af3ae3c`, all three retained
document consumer regressions fail: redundant `.`, `!`, `@` and `>` appear
on pinned native syntax; an edited uppercase cue acquires redundant `@`
inside an otherwise exact BOM/CRLF source. The fresh red log is
`target/retained-features/x6/baseline-red.log`. The retained review also
recorded the native double-Enter workflow saving redundant `@MARY`.

**The decision (ADR 0059).** Canonical new/edited blocks carry forcing markers
only where existing grammar and context require them. Untouched provenance
is still byte-exact. No Save-time text normalization, stored capitals or hidden
persisted pins: the UI pin remains live until reload, then source syntax wins.
Empty forced Action retains `!` so recovery has its ID-bearing base block.
Necessary ambiguous markers, character orphans, duals, title-page guards,
protected punctuation and whitespace/partial states remain recoverable.

This intentionally unblocks F7: a deliberately typed mixed/lowercase Character
needs `@` and will print in its own case after F7, not as automatically stored
capitals. Standard uppercase names stay uppercase. Kind/text/dual equivalence,
not incidental `forced` equality, is the canonical round-trip contract.

The regressions cover necessary syntax and clean bytes, live choices
through Save versus reload inference, Unicode/case, untouched BOM/CRLF,
Undo-restored provenance, and post-checkpoint recovery including empty FDX
imports. The original imported untitled blank base remains unchanged (ADR 0062).
Verified before integration: 736 Rust tests; 742 Flutter widget tests; all
seven native suites (94 tests across split runs); formatting, clippy, analysis,
layering/version/docs/reference and regenerated-binding checks; Linux release
build, Xvfb runtime budgets, all 15 ordinary closes and the no-network script.
The native BOM expectation was corrected to compare raw saved bytes instead of
Dart UTF-8-decoded source; the failed run remains retained. Journalled
keystroke p99 after Find is 4.27 ms, with unchanged budgets. The actual full-disk
regression passed in a private namespace. Evidence is under
`target/retained-features/x6/`. Desktop manual gates remain pending.

**Effort.** M.
**Result:** 2026-10-09 — implemented and individually verified in `360af81`.
All checks and consumer regressions above passed; logs, the initial failures,
release runtime JSON and ordinary-close JSON are retained under
`target/retained-features/x6/`. The after-Find journalled p99 is 4.27 ms.
Manual desktop gates and the inherited hosted startup investigation remain open.

<a id="x7"></a>
### X7 — Omit and restore

**Evidence (reproduced).** A `/* … */` block is read-only in the editor — the status
bar says "That block round-trips verbatim and cannot be edited"
(`app/lib/editor/element_bar.dart:345`) — and nothing in the editor creates
one. The retained draft reproduces the reported `café` seam: its live right
remainder is Dialogue but reopens as Action. A fractured nested note swallows
the generated record. Experimental fixes reproduced intermediate-step Undo and
wrong scene selections. Fresh failures are retained under
`target/retained-features/x7/`.

**Change.** Commands to move a selection or a scene into a boneyard block and
back out, each one undo step.

**Decision (ADR 0061).** Store exact semantic fragments and seam/owner witnesses
inside a checksummed, slash-escaped real boneyard. Use the final ADR 0059/0060
necessary-marker policy. During omission, SetKind makes interrupted right/tail
speech explicit Action; necessary orphan cue forcing agrees with saved rendering.
The record restores original semantics only after matching witnesses and validating
reassembly with the actual serializer/parser. Unsafe nested-note/comment seams,
changed context, bad checksums and damaged/unsupported headers refuse atomically.

Group at the public mutation boundary, preserving the actual directed selection.
Stage the new history separately so a late multi-restore failure retains existing
Undo/Redo text. A reproduced recovery failure after Redo was fixed by emitting
transaction-boundary identities; newly inserted remainders cannot also be changes
to absent IDs. Save remains read-only over actor state. Palette, KEYMAP and F1
help share all three commands, with no dedicated shortcuts.

Final refusal/recovery review reproduced two further failures: deleted live seam
whitespace was treated as parser trimming, and saved partial-heading history used
live identities against differently numbered parsed blocks. Saved-source whitespace
changes also reproduced the normalization gap. ADR 0063 restricts normalization to
untouched provenance matching the serializer's witnessed bytes, and translates
journal identities at a saved checkpoint without changing actor state. Buffered
outcomes, new inserts and second-crash recovery retain the existing record format.

**Found along the way (read).** Generic `apply_group` rollback still clears
pre-existing Redo after a late failure in unrelated grouped commands. X7's public
commands stage their history; extending that protection to other commands is a
separate task.

Final local release idle measurement fails with one voluntary main-thread switch
in otherwise zero-tick intervals. The unchanged, previously verified `593e6ad`
bundle fails with the same pattern; both reports are retained, without changing
budgets or retrying to discard the failure. This shared, unattributed idle gate
remains open outside X7's functional acceptance.

**Effort.** M.
**Result:** 2026-10-09 — implemented in `fcae98c` and finally verified with
checkpoint/witness fixes in `ff31629`. The reported `café` remainder has identical
live and reopened semantics; restoration reattaches the exact original Dialogue.
Delimiter hazards, directed/one-step history, late atomic refusals, live and
saved-source whitespace changes, and Redo recovery have consumer regressions.
Actual recovery offers/acceptance pass for Unicode Dialogue and partial headings
before and after a saved checkpoint, followed by exact BOM/CRLF restoration and
Save/reopen. Save preserves actor identities, provenance, pins, revision and
history. Buffered journal outcomes, later inserts and second-crash replay pass.

All 781 Rust tests, 763 widget tests and 103 native tests across all seven suites
pass. Native palette/F1, Unicode Save/reopen, whole-scene dual-cue restoration,
preview and Poppler PDF exclusion are exercised. FRB generation and binding drift,
formatting, clippy, analysis, enforced lockfile, layering/version/reference and
docs checks pass. The real full-disk test passes in a private mount namespace,
leaving host `/tmp` alone. The Linux release builds; after-Find journalled p99 is
4.56 ms and frame-build p99 is 7.01 ms with unchanged budgets.

Final release startup best is 368.463 ms and Xvfb RSS best is 287.559 MiB. Idle
fails: otherwise zero-tick intervals contain one voluntary main-thread switch.
The unchanged `593e6ad` release control reproduces the same failure, so the idle
gate remains unattributed and open; no retry replaced either report. All 15
ordinary closes exit zero with exact saved bytes. No-network linkage and isolated
`--version` checks pass. Initial verification, failed experiments, final `seam-*`
logs, matched control JSON and immutable release hashes remain under
`target/retained-features/x7/`, with final summaries in
`checkpoint-verification.json` and `checkpoint-release-hashes.json`.
Manual desktop gates 1–5 and the inherited startup investigation remain pending.

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

- 2026-10-09 — B18 verification: the rebuilt release passed startup (best
  380.75 ms) and Xvfb RSS (best 289.08 MiB), but
  `check_runtime_budgets.py` failed the unchanged idle gate. No interval had
  zero voluntary switches: samples had 1, 63 and 1; CPU ticks were 0, 7 and 0.
  The first interval also changed its thread set. Retained report:
  `target/b18-runtime-budgets.json`. Cause not established; no retry, idle
  workaround or threshold change made as part of the Find fix.

- 2026-10-09 — X2 native smoke: Save As writes the chosen Fountain file and
  marks the imported document saved, but the app bar still says “Untitled”.
  Opening that saved file normally shows its filename. No title-refresh fix
  belongs to FDX interchange; the chooser subsequently suggests the correct
  saved basename. Evidence: `target/x2-fdx-smoke/native-fdx-export-finished.png`.
  Promoted to [B19](#b19) on 2026-10-09.

- 2026-10-09 — X2 source finding: an existing native Fountain title page with
  duplicate keys is still unsafe in the title form. `title_page_dialog.dart`
  builds a last-value map but `TitlePage::get/set` use the first value, and the
  form commits on closing even without typing. [INFERENCE] That can replace
  the first value with the last. FDX imports now coalesce repeated fields
  before the form sees them; the pre-existing native-file case is not changed.
  Promoted to [S4](#s4) on 2026-10-09.

- 2026-10-09 — X2 native title inspection: opening and closing the title form
  without typing adds seven title snapshots to the journal, so recovery says
  “8 edits” including import's initial outcome. The recovered words and title
  values are unchanged. No-op title journalling is existing behavior and is
  left outside X2. Evidence: `target/x2-fdx-smoke/native-title-safety-recovery-offer.png`.
  Fixed with [S4](#s4) on 2026-10-09.

- 2026-10-08 — X1 publication: fast-forwarded and pushed `main` at `34844c7`.
  [Hosted CI run 37860589165](https://github.com/phagmaier/slugline/actions/runs/37860589165)
  passes Flutter (including native integration, process budgets and ordinary
  close), packaging, fuzzing and MSRV. The Rust job fails before any Rust
  checks: installation of Poppler version `24.02.0-1ubuntu9.9` receives HTTP
  404 for both `libpoppler134` and `poppler-utils` from the Ubuntu mirrors.
  That job does not refresh apt metadata before installation, unlike the
  desktop-build jobs. Refreshing it with `apt-get update` is separate CI
  maintenance, not an X1 change. No workflow or thresholds were changed.
  Promoted to [B17](#b17) for the approved CI bootstrap repair.

- 2026-10-08 — X1 verification: the isolated release runtime check again fails
  idle with zero ticks but one voluntary main-thread switch in each quiet
  interval, matching the retained W4–W8 finding. Startup (376.025 ms) and
  Xvfb RSS (274.93 MiB) pass. No threshold/harness change or idle fix belongs
  to X1. Raw samples: `target/x1-dual-smoke/runtime-budgets-isolated.json`.

- 2026-10-08 — final installed stabilization smoke: Find's real pointer/key
  assertions and exact CRLF bytes pass twice, then an ordinary
  `WM_DELETE_WINDOW` close exits with SIGSEGV on the Xvfb raster thread.
  This is distinct from the earlier direct `XDestroyWindow`/BadDrawable
  teardown. The preceding B12 hosted package at `08c7a55` reproduces the
  ordinary-close SIGSEGV twice without opening Find. Its Flutter engine hash
  matches the final installed engine; retained cores share the same
  `libgallium` offsets above Flutter raster frames. This establishes a failure
  before B13/B14/B15, not its corruption origin or a dependency fix. Keep the
  shutdown issue open independently of the successful installed Wayland
  input/Save/reopen checks and hosted CI. Evidence, logs, cores and package
  provenance: `target/stabilization/pointer-smoke-installed*/`,
  `shutdown-b12-*/` and `shutdown-control-package-hashes.json`.
  Promoted to [B16](#b16) on 2026-10-08.

- 2026-10-08 — installed B12 verification: two unchanged unpaced bursts with
  Ctrl+S in the same `wtype` invocation saved all text except the final period.
  The settled journal and later Save/reopen preserve it. A third identical
  injection passed; it does not close the intermittent native Save-ordering
  failure. Promoted to [B15](#b15) to complete the required installation check.
  Evidence and exact artifacts: [FAST_INPUT.md](FAST_INPUT.md#installed-b12-follow-up--2026-10-08).

Add a dated line here for anything noticed while working on an item that is
not part of that item.

- 2026-10-09 — B20, seen in a widget test: `_onExitRequested` disposes the open
  script's controller and leaves its `EditorPage` in the tree, so any frame
  built between the quit being agreed and the process going asserts
  "EditorController was used after being disposed" in a debug build. Release
  builds do not check. Not changed: B20 only orders the quit behind an open.

- 2026-10-08 — B16, reproduced under Xvfb: closing the window the moment it
  first appears, while the script named on the command line is still being
  opened, logs `Unhandled Exception: Bad state: No element` from
  `EditorController`'s constructor through `_SluglineAppState._adopt`. Six of
  six on the installed build at `804ba18` and eight of ten on the B16 bundle,
  with the 120-page reference script; never with no script argument. The
  process still exits zero and the file's bytes are unchanged. Read, not
  proven: the exit request runs `core.shutdown()`, which closes the handle
  that `_startUp` is about to hand to a new editor. One of the ten B16 runs
  also left `<id>.log.tmp-<pid>-…` in the journal directory, an atomic write
  the exit interrupted; the journal scan lists only `.log`, so nothing offers
  it for recovery. Left unchanged. Logs:
  `target/stabilization/b16/cur-G1-early-reference-*/first-process.log`,
  `fix-G1-early-reference-07/state/slugline/journal/`.
  Promoted to [B20](#b20) on 2026-10-09.
- 2026-10-08 — B16, observed on the Hyprland session: Ctrl+W in the instant
  after a Save's bytes reach the file is answered with "Save changes? There are
  edits here that are not in the file yet", with "saved just now" already in
  the status bar behind it
  (`target/stabilization/b16/wayland-cur-02/save-close-still-open.png`). An
  unpaced driver hit it three times in three there and never under Xvfb. The
  save writes the file, then its previous-version copy, and only then clears
  the dirty flag on the actor, so the question is asked of a file that already
  holds the text. It errs on the safe side and no person is that fast; recorded
  because any harness must wait for the journal to restart, not for the bytes.
  Left unchanged.
- 2026-10-08 — B16, observed on the Hyprland session: every launch logs
  `Gdk-Message: Unable to load  from the cursor theme`, with an empty cursor
  name, on the installed build and the B16 bundle alike. Not investigated.

- 2026-10-08 — W10, observed during the installed native-Wayland smoke: an
  unpaced `wtype` text burst did not arrive intact. The saved action was
  `Installed command ready. Verifed hrough insalled assoiation.` rather than
  the supplied `Installed command ready. Verified through installed association.`
  A separate replacement entered with 30 ms between keys saved and reopened
  byte-exactly. Cause is not established; no input-path change was made for W10.
  Evidence: `target/w10-smoke/fast-input-observation.fountain` and
  `target/w10-smoke/installed-saved.png`. Investigate separately rather than
  treating the paced installation smoke as a fix for fast input.
  Promoted to [B12](#b12) on 2026-10-08 after tracing intact delivered keys,
  stale outgoing application states, and incomplete committed text before Save.

- 2026-10-07 — W9, reproduced in the release smoke: **Restore** from a version
  view writes the selected older text to disk and preserves the current text in
  backups, but the editor still paints the pre-restore text and word count
  (`target/w9-smoke/after-restored.png`). The unchanged
  `EditorPage._showBackups` discards `BackupsDialog.show`'s restored boolean;
  `withModal` only suppresses/releases autosave, and the existing
  `EditorController.reloadFromCore` is not called. That handoff predates W9
  (source-read at the starting commit); the visible/disk mismatch was exercised
  after W9. Promoted to [B11](#b11) ahead of installation on 2026-10-08.
  Reading a version and opening a copy do not replace the current document and
  need no refresh.

- 2026-10-07 — W8, reproduced on the release bundle with a real pointer and
  real keys: after a click on "Match case", "Whole word" or the element filter,
  Escape no longer closes the find bar and Enter no longer steps
  (`target/w8-smoke/found-escape-after-toggle.png`; the first run of W8's native
  test failed on it too). Read, not proven: a desktop text field gives up the
  keyboard on a click outside it, to the page's focus scope; the bar's key
  handler sees keys only while something inside the bar has it, and
  `EditorPage._onPageKey` has no Escape. The close button still works. It
  predates W8, which changes no focus handling. Left unchanged in W8;
  promoted to [B14](#b14) on 2026-10-08.
- 2026-10-07 — W8, reproduced on the release bundle: text typed after Find
  opens is appended to what the field holds rather than replacing it — `DAY`
  seeded, `x` typed, "DAYx", "No matches"
  (`target/w8-smoke/found-typed-after-seed.png`). The same goes for a resumed
  query. Flutter's desktop default is to select a one-line field's text when it
  takes the keyboard, and here it does not; the cause is not established. Not
  exercised on the pre-W8 build, though W8 changes only what text the field
  starts with. More noticeable since W8: a writer who opens Find over a
  selection and then wants something else has to clear the field first. Worth
  its own small item. Left unchanged.
  Promoted to [B10](#b10) on 2026-10-07.
- 2026-10-07 — W8, read: `Ctrl+F` with the find bar already open does nothing.
  `EditorPage._show` returns when the panel asked for is the one showing, so
  from the script it neither moves the keyboard to the find field nor takes a
  new selection, and from inside the field the page's key handler has no
  `Ctrl+F` case. W8 seeds on opening, as its item says; a writer who selects
  other text with the bar still open and presses `Ctrl+F` gets no new search.
  Not exercised. Left unchanged.
- 2026-10-07 — W8, observed in its release frames: the find bar floats over the
  top right of the script and hides the matches under it. At 1400 px it covers
  the right of the first seven rows, and with them three of the seven matches
  (`target/w8-smoke/after-dark-find-open.png`). The surface scrolls a selected
  match into the viewport, not out from under the bar. It predates W8 and shows
  more now that every other match is tinted. Left unchanged.
- 2026-10-07 — W8, read: every edit re-runs the retained Find query through a
  synchronous whole-document scan, even with the bar closed; the original
  keystroke benchmark never opened Find. Reproduced and resolved as
  [B18](#b18) on 2026-10-09; no longer an open finding.
- 2026-10-07 — W7, observed on the native Hyprland release launch: GTK/Flutter
  logged “Timed out waiting for OpenGL frame of size 1920x1080 (have 1280x720)”
  during startup. The subsequent editor and
  chooser rendered correctly in the recorded screenshots, and the session
  exited 0. Startup-size/frame synchronization is outside W7; left unchanged,
  with no claim that a correct later frame explains or fixes the warning.
- 2026-10-06 — W5, reproduced: the preview keeps its scroll offset in pixels
  when the sheets change size, so it does not keep its page. Opened on page 47
  of a 60-page pagination at the default 58%, "Actual size" leaves page 28 at
  the top of the pane, "Fit width" page 29 and switching to A4 page 27
  (`target/w5-found-along-the-way.log`). It was always so; it went unnoticed
  while every preview began at the top, where the offset is zero at any size.
  W5 opens on the caret's page and then leaves the view alone, as its item
  asks, so the first zoom after opening now moves the writer some twenty pages.
  Worth its own small item: `PreviewView` already knows the sheet extent, so
  keeping the sheet at the top of the pane across a scale or paper change is
  arithmetic on the existing controller. Left unchanged here.
  Promoted to [W11](#w11) on 2026-10-09.
- 2026-10-06 — W5, reproduced: the status line's page for a block that prints
  nothing is the page its predecessor *began* on. `PageIndicator._adopt` fills
  `_pageAtBlock` from `firstPageAtBlock`, so a note under a paragraph running
  from page 1 to page 3 reads "Page 1 of 3" between two lines that both read
  "Page 3 of 3" (`target/w5-found-along-the-way.log`). The label flickers back
  while scrolling past such a note. W5's own lookup uses the page the text
  above ends on and does not go through the indicator; the indicator is
  unchanged.
  Promoted to [B21](#b21) on 2026-10-09.
- 2026-10-06 — W5, read: `CHANGELOG.md` has no entry for W1–W4. New, Open and
  Close shortcuts, the added palette commands, `Shift+Enter` line breaks and
  "Go to page…" are all user-visible and all absent from "Unreleased"; W5 adds
  its own line and leaves theirs for whoever cuts the next release notes.

- 2026-10-06 — W4's first release-process budget run failed idle: all three
  ten-second intervals had voluntary thread switches (1, 64, 1); the first
  also lost two threads. The outer intervals had zero CPU ticks and one wakeup
  each on the main GTK/Flutter thread. Startup and RSS passed. The failed
  report and full samples remain in `target/w4-runtime-budgets.json` and
  `target/w4-runtime-budgets.log`; `target/w4-idle-inspection.txt` records the
  bounded source inspection. W4 adds no clock, and its page-command methods
  are not called during this harness. The isolated wakeups are not attributed;
  the unchanged W4 retry reproduced the same outer one-switch intervals, and
  a clean, isolated W3 checkout at `351dada` reproduced them without W4.
  The retry and W3 reports are `target/w4-runtime-budgets-retry.json` and
  `target/w4-runtime-budgets-w3-control.json`, with matching log files. The
  control bundle is retained at `target/w4-w3-control-bundle`; component
  digests, clean checkout receipt and build logs are under `target/w4-*`.
  This is a pre-existing failure in the current environment, not a passed idle
  gate. Investigate the wakeups separately; no threshold, harness or production
  code was changed for the controls.

- 2026-10-06 — W4's restored-viewport page-one case led to a separate code-read
  navigation gap: `Ctrl+Home` calls `moveToDocumentEdge`, but
  `EditorSurface._onDocumentChanged` clears `_restoreInProgress` only when the
  caret differs from `_initialFocus`. If a session restores a scrolled viewport
  while its caret is still at document start, `Ctrl+Home` leaves that guard in
  place and `_ensureCaretVisible` returns. W4 explicitly reveals its own page
  target; the general shortcut behavior is unchanged. Reproduce and investigate
  separately.

- 2026-10-06 — W3's native fixture exposed a zero-page presentation error:
  a Note-only script has no printed pages, and `PageIndicator._updateCurrent`
  (`app/lib/editor/page_indicator.dart:272`) throws while clamping 1 to a
  zero upper bound. Observed in `target/w3-native-writing-retry.log`; left
  unchanged because pagination presentation is outside W3. The Note fixture
  now includes a printable Action paragraph. Investigate the zero-page case
  separately, including empty scripts and content that prints nothing.
  Promoted to [B13](#b13) on 2026-10-08.

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
  Promoted to [B8](#b8) with F6's note below.
- 2026-10-06 — F4's full native integration run passed bridge and editor suites,
  then failed `writing_test.dart` at line 174: “the real entity index and scene
  parser drive the navigator” expected visible `STREET` and found none.
  This differs from the earlier closed-drawer `HOUSE` failure fixed by B4.
  Recorded the observed failure without changing navigator code or rerunning
  the failed scenario; investigate separately from lyric spacing.
  Promoted to [B5](#b5) after the owner requested investigation; the docked
  Linux navigator loses its page-level shortcut focus boundary on tab clicks.
- 2026-10-06 — F6: `dart format` run over all of `app/` rewrites 41 of its 97
  Dart files, not only the ones an item touches (see F4's note above). Nothing
  gates Dart formatting, so a tree-wide run buries a change in thousands of
  unrelated lines; it was undone here file by file. Either format the tree once
  in its own change and check it in CI, or have `AGENTS.md` say to leave it.
  Promoted to [B8](#b8) after the owner asked whether to address it; the tree
  is formatted once and the check added.
- 2026-10-06 — F6: `flutter_rust_bridge_codegen generate` ran `pub get` and
  rewrote `app/pubspec.lock` under the pinned Flutter 3.44.8, moving `matcher`
  0.12.20 to 0.12.19, `meta` 1.19.0 to 1.18.0 and `test_api` 0.7.12 to 0.7.11.
  Restored, and `flutter test` and the release build left it alone afterwards.
  The committed lockfile looks resolved by a newer SDK than the one CI pins;
  not investigated.
  Promoted to [B6](#b6) after the owner asked whether to address it: the
  lockfile cannot be satisfied by the pinned toolchain at all.
- 2026-10-06 — F6: `README.md` sends the reader to Preferences → “Output” for
  Bold scene headings, but the dialog's section is headed “Page defaults”.
  Left as it is; the sentence added for F6 does not repeat the label.
  Promoted to [B7](#b7) after the owner asked whether to address it.
- 2026-10-06 — Pushing F6 and B6–B8 to `main` gave the first GitHub run to get
  past the writing suite since F3, and it failed in the export suite: CI's
  flutter job has no `poppler-utils`. Promoted to [B9](#b9) at once, since the
  push that exposed it left `main` red.
- 2026-10-06 — F8, read: the break-rule loop in `paginate_internal` cannot fail
  to converge. `paginate_flow` with the rules on never reads the previous
  iteration's pages, so the second ruled pass always equals the first. Every
  full pagination therefore lays the script out three times — once naively,
  twice by the rules — for the pages one ruled pass gives;
  `break_rule_iterations` is only ever 1 or 2, and `fell_back_to_naive` and
  `BREAK_RULE_ITERATION_CAP` cannot be reached. Nothing is wrong on the page.
  The cost is in the full-pagination budget (4.8 ms of 50 ms on the reference
  feature). Left alone: ADR 0022's capped fixed point owns that loop, so
  removing it wants its own record.
- 2026-10-06 — F8, reproduced: a paragraph taller than a page that arrives when
  the page is exactly full opens the next page with a blank row. `place_action`
  skips its carry-over check for a block no page can hold, and `add_blank` then
  starts the new page with the paragraph's leading blank, which
  `top_aware_spacing` would have dropped. One row of that page is lost. It is
  what a full pagination does, so it is outside F8;
  `a_page_that_opens_on_a_blank_row_is_not_somewhere_to_resume` asserts the
  blank because the incremental path has to agree with it, and will need
  rewriting with any fix.

- 2026-10-06 — F9, read: the ordinary CI Flutter job enumerates seven native
  suite steps directly instead of invoking `tools/test_linux_integration.sh`.
  Its suite-versus-files inventory check therefore runs locally and in the
  release workflow, but not in ordinary CI. All seven current suites are
  listed and were run here; a future eighth could be omitted from that job
  without exercising the guard. The guide's claim that ordinary CI runs the
  script is inaccurate. Left outside F9; consider sharing the inventory check
  while retaining separately named suite failures.
