# Slugline — Mid-Project Remediation Plan

**Source audit:** `REVIEW.md`  
**Audit baseline:** commit `16b6cff` (`phase 6`), branch `dev`  
**Purpose:** repair and stabilize the existing implementation before beginning Phase 7  
**Status:** in progress — Phases 0–5 complete; later remediation phases not started

---

## How to use this document

This is the execution companion to `REVIEW.md`.

- `REVIEW.md` remains the diagnostic record and source of evidence, unchanged.
- This document is the implementation tracker. Findings discovered after the audit are
  numbered on from it and recorded here rather than in `REVIEW.md`; F13 and F14 came out of
  the Phase 0 baseline run and are worked in Phase 2B.
- Complete phases in order unless a phase explicitly says its internal tasks are order-independent.
- Do not combine remediation work with unrelated Phase 7 feature work.
- Do not rewrite healthy subsystems merely because a different design is possible.
- Every checked item must correspond to code, a test, documentation, or a recorded verification result.
- When a task changes architecture or intent, update or add the relevant ADR in the same change.
- Prefer one focused commit per logically independent repair.
- Generated bridge files may change when regeneration is required, but should not be edited manually.

### Checkbox meaning

- `[ ]` Not started
- `[x]` Completed and verified
- `[!]` Blocked — document the reason directly below the task
- `[-]` Deliberately skipped — document the decision and justification

---

# Global completion criteria

The remediation effort is complete only when all of the following are true:

- [x] No known path can lose recovered user text after accepting crash recovery.
- [x] Multi-line Fountain blocks render, wrap, select, click, and position the caret correctly.
- [x] Enter splits the block whether or not a completion is offered, and Escape closes every panel.
- [ ] Dart and Rust line breaking agree on the defined shared behavior.
- [ ] Rust pagination is reachable through the bridge and exercised outside its isolated crate tests.
- [ ] The library page count is updated from a saved pagination snapshot.
- [x] The application does not treat its own save as an external file modification.
- [x] Overlapping saves for the same session cannot write out of order.
- [x] External-change checks perform disk I/O off the actor thread.
- [x] Persisted scroll position is applied when reopening a script.
- [ ] Fountain “Export Copy” semantics are separate from “Save As.”
- [x] CI runs all intended integration tests and a real ENOSPC/full-disk test.
- [x] README, AGENTS, SPEC, ADRs, and implementation status agree.
- [ ] The real Linux `ibus` + CJK IME gate has been performed and recorded.
- [ ] All repository verification commands pass.
- [ ] No Phase 7 preview or PDF feature work began before the Phase 7 gate was satisfied.

---

# Non-goals and protected architecture

Do **not** rewrite or replace the following as part of this remediation:

- [ ] Preserve `crates/fountain` and its tiling/provenance architecture.
- [ ] Preserve `crates/document`, inverse-splice undo, grouped transactions, and reinference model.
- [ ] Preserve `crates/storage/atomic.rs` and the journal design; repair the recovery acceptance sequence around them.
- [ ] Preserve the single-threaded actor ownership model.
- [ ] Preserve bridge conventions: closures in, patches out, refusals as values, and `offsets.rs` as the single UTF conversion boundary.
- [ ] Preserve incremental Dart patch application and the never-refetch discipline.
- [ ] Preserve the single-surface editor.
- [ ] Preserve the fluid, unpaginated editor for 1.0.
- [ ] Preserve literal Fountain emphasis markers in the editor for 1.0.
- [ ] Preserve interval autosave during continuous typing.
- [ ] Preserve the project’s behavior-focused testing style.

---

# Phase 0 — Baseline, branch, and reproducibility record

## Objective

Establish a clean baseline so every remediation can be measured against the audited commit.

## Tasks

### Repository state

- [x] Confirm the current branch and commit.
  - Expected audit baseline: branch `dev`, commit `16b6cff`.
  - Actual start point: branch `dev`, commit `d3f2fb8`.
- [x] Record any commits made after the audit.
  - One: `d3f2fb8 initial review`, which adds `REVIEW.md` and nothing else.
- [x] Create a dedicated remediation branch.
  - Created `fix/mid-project-remediation` from `d3f2fb8`.
- [x] Confirm the worktree is clean before starting.
  - Clean apart from this untracked plan, now tracked.
- [x] Copy `REVIEW.md` and this plan into the repository documentation location if they are not already tracked.
  - `REVIEW.md` is already tracked at the repository root; `REMEDIATION_PLAN.md` is now tracked beside it. `docs/` is reserved for ADRs, dependencies and the keymap.
- [x] Add a short remediation status section to the project’s normal progress document.
  - Added under `README.md` → “Remediation status”. The stale “Phase 1 complete” line is deliberately left for Phase 3 (F7) and is flagged as stale rather than silently corrected here.

### Baseline verification

Run and record the result of:

- [x] `cargo fmt --check` — clean.
- [x] `cargo clippy --workspace --all-targets -- -D warnings` — clean.
- [x] `cargo test --workspace` — 334 passed, 0 failed, 0 ignored.
- [x] `tools/check_layering.py` — clean. `tools/make_reference.py --check` also run: fixture current.
- [x] `flutter analyze` — “No issues found”.
- [x] `flutter test` — 260 passed.
- [x] Existing bridge build command — `flutter build linux --release` succeeded; `libslugline_bridge.so` bundled; bundle 26.5 MB against the 60 MB §1.3 budget.
- [x] Existing `.so`-dependent integration tests that can be run locally — all six run; see the log below.

### Baseline artifact

- [x] Record:
  - Rust test count.
  - Flutter test count.
  - Integration tests actually executed.
  - Any test skipped due to environment limitations.
  - Current known failures.
- [x] Do not begin repairs if the baseline unexpectedly differs materially from the audit; first explain the discrepancy in the implementation log.
  - No discrepancy: no code changed between the audit baseline and this branch point.

## Exit conditions

- [x] Clean remediation branch exists.
- [x] Baseline commands and results are recorded.
- [x] Any post-audit code changes have been identified — there are none.
- [x] The audit findings are still applicable or have been explicitly updated.
  - `git diff --stat 16b6cff..HEAD` touches only `REVIEW.md`, so every finding F1–F12 still describes the code as it stands.

## Implementation log — Phase 0

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `d3f2fb8` (`initial review`, on `dev`)
**Ending commit:** this commit, on `fix/mid-project-remediation`

### Changes made

- Branched `fix/mid-project-remediation` from `d3f2fb8`.
- Tracked `REMEDIATION_PLAN.md` at the repository root, beside the already-tracked `REVIEW.md`.
- Added a “Remediation status” section to `README.md`.
- Recorded F13 and F14 below (see “Deviations from plan”), which the audit could not have found.

No product code was changed in Phase 0.

### Tests added or changed

None. Phase 0 measures; it does not repair.

### Commands run

```text
git rev-parse --abbrev-ref HEAD          # dev
git log --oneline 16b6cff..HEAD          # d3f2fb8 initial review
git diff --stat 16b6cff..HEAD            # REVIEW.md only, 710 insertions

cargo fmt --all --check                  # clean
cargo clippy --workspace --all-targets -- -D warnings
                                         # clean
cargo test --workspace                   # 334 passed, 0 failed, 0 ignored
python3 tools/check_layering.py          # clean
python3 tools/make_reference.py --check   # fixture current

cd app
flutter --version                        # 3.44.8 stable, Dart 3.12.2
flutter pub get                          # clean
flutter analyze                          # No issues found
flutter test                             # 260 passed
flutter build linux --release            # built; bundle 26.5 MB of the 60 MB budget
test -f build/linux/x64/release/bundle/lib/libslugline_bridge.so   # present, 2.0 MB

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/editor_test.dart              -d linux   # 5 passed, 1 FAILED
flutter test integration_test/writing_test.dart             -d linux   # 8 passed, 3 FAILED
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
```

### Results

**Baseline artifact.**

| Measure | Value |
| --- | --- |
| Rust tests | 334 passed, 0 failed, 0 ignored (`cargo test --workspace`) |
| Flutter unit/widget tests | 260 passed (`flutter test`) |
| Integration tests executed | all six, locally, against the release `.so` |
| Integration tests passing | `bridge_test` (4), `ime_test` (9), `keystroke_benchmark_test` (2), `persistence_test` (12) |
| Integration tests failing | `editor_test` (1 of 6), `writing_test` (3 of 11) |
| Rust lint/format/layering | clean |
| `flutter analyze` | clean |
| Release build | succeeds, `libslugline_bridge.so` bundled, 26.5 MB bundle |

Rust test breakdown: `bridge` 64 + `persistence.rs` 10; `document` 87 + 3 + 2 + 1 doc-test;
`fountain` 71 + 4 + 2 + 3 + 5 + 1 doc-test; `layout` 6 + 10 + 2 + 2 + 1; `render_pdf` 1;
`spell` 1; `storage` 58.

Keystroke benchmark against the 120-page reference (2880 blocks, 6419 rows), well inside
the §1.3 budget:

```text
open → editable:  51.9 ms (budget 250 ms)
keystroke → patched    p50 1.41   p99 2.42   max 5.02 ms
frame build            p50 3.30   p99 5.40   max 10.39 ms
frame raster           p50 0.89   p99 1.24   max 1.47 ms
builds over 16 ms: 0 of 271
keystroke → journalled p50 1.58   p99 2.07   max 2.75 ms
```

**Tests skipped due to environment limitations.**

- The real full-disk/ENOSPC path in `crates/bridge/tests/persistence.rs` did not run.
  `SLUGLINE_FULL_DISK_DIR` is unset locally, so the test fell back to proving only the
  error classification. This is the known gap; remediation Phase 3.5 closes it in CI.
- `xvfb` is not installed on this machine. The integration tests were run against the real
  session display (`DISPLAY=:0`, XWayland under Hyprland) instead. This did not affect the
  results — see the root-cause work below, which shows the failures are code defects and
  reproduce deterministically.
- The manual `ibus` + CJK IME gate remains unperformed, as `SPEC.md` already says. Phase 9A.

**Known failures at baseline.** Four, all newly discovered, all deterministic across
repeated runs, all in code untouched since the audit. They are described as F13 and F14
below.

### Deviations from plan

Phase 0 says not to begin repairs if the baseline differs materially from the audit, and to
explain the discrepancy first. It does differ, so here is the explanation.

`REVIEW.md` line 13 says outright: *“Integration tests requiring the `.so` were not run in
this session.”* The audit therefore assessed the code by reading it, and its finding list
F1–F12 contains nothing about the four failures below. Running those tests is what Phase 0
asked for, and it found real defects. Nothing about the audit is thereby wrong — F1–F12 all
still apply, unchanged — but the finding list is incomplete, so this plan gains F13 and F14
and a new Phase 2B.

No repairs were made. The two findings are recorded and scheduled, not fixed.

#### F13 — Enter is dead whenever the completion popup has a suggestion

`editor_surface.dart:_onKey` matches Enter against the completion popup *before* it matches
Enter against `splitBlock()`:

```dart
case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
    when _controller.completions.isNotEmpty:
  _controller.acceptCompletion();
...
case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
  _controller.splitBlock();
```

The entity index suggests the block the writer is currently typing. Type
`INT. HOUSE - DAY`, and by the time it is classified as a scene heading it is itself an
indexed entity and the sole completion offered for itself. Enter then “accepts” that
suggestion — replacing the text with the identical text — and never splits the block. To
the writer, Enter is simply dead after every scene heading and every character cue.

Reproduced directly against the real core: after typing `INT. HOUSE - DAY`,
`controller.completions` holds one `Completion`, and Enter leaves the document at one
`sceneHeading` block. After typing `ABC` (an action line, no entity match)
`controller.completions` is empty and Enter correctly produces two blocks.

This is what all three of these baseline failures are:

- `editor_test.dart`: *setting every element type by hand keeps the text exactly* — expected
  four blocks, got two.
- `writing_test.dart`: *a whole scene, keyboard only, with nothing set by hand* — Enter after
  a heading was expected to give `action`, gave `sceneHeading`.
- `writing_test.dart`: *double-Enter after a speech asks for the next cue* — got
  `@MARYHello yourself.` where `@MARY\nHello yourself.` was expected.

Why the green suites missed it: the widget tests drive the editor through
`app/test/support/fake_core.dart`, whose `completions` field defaults to `const []`. With no
suggestions there is nothing to steal Enter, so the headless Enter tests take the
`splitBlock()` branch and pass. Only the real core self-suggests, so only the `.so`
integration tests can see this — and CI runs `editor_test` but has never run on this branch,
since `dev` was never pushed and CI triggers on `main` and pull requests. `writing_test` is
one of the three integration tests CI does not run at all (audit finding F7).

Severity: High. It is a keyboard-driven screenplay editor in which Enter does not work after
a slug line.

#### F14 — Escape does not close the command palette

`writing_test.dart`: *Escape closes each panel and never changes the document* fails at its
second panel. Escape closes the Find bar correctly; the `Ctrl+K` command palette stays open,
with “Element or command” still on screen after Escape and `pumpAndSettle`.

`command_palette.dart` puts `Focus(onKeyEvent: _onKey)` around a `TextField(autofocus:
true)`, and `_onKey` does handle Escape. Not root-caused in Phase 0 — it may be a real
defect in how the key bubbles out of the focused `TextField`, or an artifact of the live
integration binding’s real text-input connection. Phase 2B determines which before changing
anything.

Severity: Medium, and dependent on the above.

### New risks or follow-up findings

- The gap F13 fell through is structural, not a one-off: the Dart test double can be
  *quieter* than the real core, and a default of “no suggestions / no results” makes a whole
  class of “panel is open” branches unreachable in the headless suite. Worth a look during
  Phase 2B for other `fake_core.dart` defaults that are empty by default and non-empty in
  practice.
- Nothing in this repository has ever been through CI on the `dev` line of work: `dev` was
  never pushed, and CI triggers on `main` and pull requests. Every “CI runs this” claim in
  the documentation is untested for Phases 2–6. This reinforces F7 and Phase 3.4.

### Reviewer notes

- Baseline command output is not committed; it was captured to a scratch directory during
  the run and is summarised above in full.
- The `README.md` status line still says “Phase 1 complete”. That is F7 and belongs to
  Phase 3; Phase 0 flagged it as stale rather than silently correcting it, so that Phase 3
  still has a real task and a real diff.

---

# Phase 1 — Recovery durability: eliminate the recovered-text loss window

**Audit findings:** F2  
**Priority:** P0 data safety  
**Must complete before:** all other feature work

## Objective

After the user accepts crash recovery, the recovered text must remain durably recoverable even if the application crashes again before the user types or manually saves.

## Required behavior

The old recovery journal must not be destroyed until the recovered state is durably represented on disk or in a valid journal based on the real on-disk file.

A recovered document adopted in a dirty state must immediately enter the autosave lifecycle without requiring a subsequent edit event.

## Tasks

### 1.1 Reproduce and pin the failure first

- [x] Locate the existing bridge persistence/kill-test harness.
  - `crates/bridge/tests/persistence.rs`. Note it cannot link the bridge — `slugline_bridge` is `cdylib`/`staticlib` only — so it drives `document` + `storage` directly, and the new tests match that level with an `accept` helper mirroring `recovery_accept`.
- [x] Add a failing regression test for:
  1. Open a file.
  2. Make an unsaved edit.
  3. Kill the process.
  4. Restart and accept recovery.
  5. Kill the process again before manual save and before further typing.
  6. Restart again.
  7. Assert that the recovered edit is still recoverable.
  - `a_second_crash_straight_after_accepting_recovery_loses_nothing`.
- [x] Add a second failing case:
  1. Accept recovery.
  2. Type additional text.
  3. Crash before a completed save.
  4. Assert both recovered and newly typed text remain recoverable.
  - `a_second_crash_after_typing_more_keeps_both`.
- [x] Confirm the new tests fail for the reason described in F2.
  - Checked by reinstating the old sequence in the helper: four tests fail, and the untitled one reports `left: "" right: "FADE IN:\n"` — the whole recovered document gone, exactly F2(a).

### 1.2 Choose and document the durability sequence

Implement one coherent strategy rather than patching symptoms.

Preferred sequence:

- [x] Replay the old journal into memory.
- [x] Keep the old journal intact while recovery is unresolved.
- [-] Persist the recovered state immediately when a valid bound path exists.
  - **Deliberately not done.** Writing the script on accept contradicts what Phase 4 promises and what the kill test asserts: recovery never auto-applies, and the document comes back dirty so the writer still has to agree. It would also write a rolling backup for a state nobody approved. The alternative strategy below is used instead, and it is the one the plan explicitly permits.
- [-] Only after durable write success: discard/checkpoint the old journal; create or restart the active journal against the bytes actually written; mark the document saved at the correct revision.
  - Not applicable for the same reason — there is no write to succeed. The equivalent gate is kept: the old journal is removed only after the successor journal exists.
- [x] For an untitled or pathless recovery:
  - do not discard the only durable recovery data;
  - require Save As or maintain a valid recovery journal until a path is established.
  - The successor journal is maintained. An untitled recovery gets one under this process's own name, and the old one is removed only once it exists — `an_untitled_recovery_survives_a_second_crash_too`.
- [x] Define failure behavior for immediate recovery persistence:
  - retain the old journal;
  - keep the recovered document open;
  - surface a clear save/recovery error;
  - never silently downgrade to memory-only state.
  - `RecoveryOutcome::Degraded` — open, old journal retained, and a dialog that says nothing typed from here is being recorded.

Alternative strategy is allowed only if:

- [x] The new journal is based on the actual file bytes.
  - Its `base` is the `source` that `journal::verify` read from the file, so `verify` succeeds after a second crash instead of returning `blocked`.
- [x] Recovered edits are represented as replayable records before the old journal is deleted.
  - `Journal::rebuild` writes header plus records through `atomic::save_atomically`; the old journal is removed after, and only when the successor did not already replace it at the same path.
- [x] The double-crash tests prove durability.

### 1.3 Repair the bridge recovery sequence

Likely area: `crates/bridge/src/api/files.rs::recovery_accept`.

- [x] Remove the sequence that discards the old journal before durability is established.
- [x] Ensure journal base checksums correspond to actual bytes on disk.
- [x] Ensure journal checkpoint/restart occurs only after the durable state transition.
- [x] Update the inaccurate comment claiming a second crash loses nothing.
  - Replaced with a numbered account of the sequence and of what the old one did instead.
- [x] Ensure partial failures leave a recoverable state.
  - Three of them: a successor that cannot be written → `Degraded` with the old journal kept; a journal none of whose records replay → `Failed`, journal untouched; a replay that stops early → the successor records only what applied.
- [x] Preserve refusal/error-as-value conventions.
  - `RecoveryOutcome` carries the message, matching `SaveOutcome`. No panics, no exceptions.
- [x] Avoid introducing disk I/O on the actor thread beyond the project’s established write architecture.
  - `Journal::rebuild` runs between actor calls, not inside a closure — the same shape as `write_document`.

### 1.4 Arm autosave when adopting dirty state

Likely area: `app/lib/editor/autosave.dart`.

- [x] Identify the document-adoption path used after recovery.
  - `_SluglineAppState._adopt` in `app/lib/app.dart`, shared by recovery, session restore and library open.
- [x] Add an explicit API or event that tells `AutosaveDriver` a dirty document has been adopted.
  - `AutosaveDriver.documentAdopted()`.
- [x] Arm the idle autosave timer immediately after recovery acceptance.
- [x] Preserve the interval autosave behavior.
  - Both timers start, and a test covers the interval firing for a recovered document.
- [x] Ensure autosave is not armed for a clean document.
- [x] Ensure recovery adoption does not require a fake edit or controller mutation.
  - `documentAdopted` reads `core.dirty`; nothing is written to the document.
- [x] Add a widget/unit test proving dirty-on-adopt schedules autosave.

### 1.5 Verify recovery UX

- [x] Recovery acceptance still restores the correct text.
- [x] Recovery rejection still discards only what the user rejected.
  - `recovery_discard` is untouched.
- [x] Broken/blocked recovery still reports its existing distinct state.
  - `recovery_pending`'s `blocked` field is untouched; a journal that fails `verify` still comes back blocked rather than being accepted.
- [x] Save failures after recovery do not destroy the journal.
  - `write_document` checkpoints only after a successful write; unchanged.
- [x] Recovery of one offer per launch remains unchanged for 1.0.
  - `app.dart` still returns after the first offer it opens, including on the `Degraded` path.
- [x] No unrelated rewrite of `journal.rs` or `atomic.rs` was introduced.
  - `atomic.rs` untouched. `journal.rs` gained `rebuild` and two small shared helpers; `create`, `append`, `checkpoint`, `discard`, `read` and `verify` are unchanged.

## Tests

- [x] Second crash immediately after accepting recovery.
- [x] Second crash after typing more text.
- [x] Recovery immediate-save failure retains recoverability.
  - `a_failed_successor_leaves_the_offer_where_it_was`, which makes the journal directory read-only.
- [x] Dirty-on-adopt arms autosave.
- [x] Clean-on-adopt does not arm autosave.
- [x] Existing journal truncation/fuzz tests still pass.
- [x] Existing kill tests still pass.

## Exit conditions

- [x] The two new crash regression tests pass.
- [x] No old journal is discarded before a durable successor exists.
- [x] Autosave begins for a recovered dirty document without another edit.
- [x] All Rust and Flutter tests pass.
  - Rust 340 passed. Flutter 263 passed. `editor_test` and `writing_test` still fail on F13/F14 with the same counts as the Phase 0 baseline — Phase 2B's work, untouched here.
- [x] A code comment or ADR clearly states the recovery durability sequence.
  - Both: the numbered sequence on `recovery_accept`, and ADR 0016 in `docs/DECISIONS.md`.

## Suggested commit boundary

- [x] `fix(storage): preserve recovered edits across a second crash`

## Implementation log — Phase 1

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `ae77ea6` (Phase 0)
**Ending commit:** this commit

### Changes made

- `crates/storage/src/journal.rs`: added `Journal::rebuild`, which writes a whole journal — header plus a run of records — through `atomic::save_atomically` and reopens it for appends. Factored the record encoder out of `append` so the two writers cannot drift.
- `crates/bridge/src/api/files.rs`: rewrote `recovery_accept` to the sequence in ADR 0016, and changed its return type from `Option<DocumentHandle>` to a new `RecoveryOutcome` enum.
- `app/lib/app.dart`: handles the three outcomes; calls `autosave.documentAdopted()` on every adoption.
- `app/lib/editor/autosave.dart`: added `documentAdopted()`.
- `app/lib/library/recovery_dialog.dart`: added `showRecoveryNotJournalled` and `showRecoveryFailed`.
- `docs/DECISIONS.md`: ADR 0016.
- Regenerated bindings with `flutter_rust_bridge_codegen generate`; no generated file was hand-edited.

### Tests added or changed

Six in `crates/bridge/tests/persistence.rs`, three in `crates/storage/src/journal.rs`, three in `app/test/editor/autosave_test.dart`. Named in ADR 0016.

### Commands run

```text
cargo fmt --all --check                                       # clean
cargo clippy --workspace --all-targets -- -D warnings         # clean
cargo test --workspace                                        # 340 passed, 0 failed
python3 tools/check_layering.py                               # clean
cd app && flutter analyze                                     # No issues found
cd app && flutter test                                        # 263 passed

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed
flutter test integration_test/editor_test.dart              -d linux   # 5 passed, 1 failed (F13)
flutter test integration_test/writing_test.dart             -d linux   # 8 passed, 3 failed (F13, F14)
```

### Results

Rust 334 → 340; Flutter 260 → 263. `editor_test` and `writing_test` fail with exactly the Phase 0 baseline counts, on F13/F14, which Phase 2B owns.

The keystroke path is not on the recovery path and the benchmark confirms it — p99 1.30 ms patched and 1.31 ms journalled, against 2.42 and 2.07 at baseline, 0 of 271 builds over 16 ms.

### Deviations from plan

**The preferred sequence was not used; the permitted alternative was.** The plan's first choice is to save the script immediately on accept and checkpoint a fresh journal against the written bytes. That writes the writer's file as a side effect of clicking "Recover", which contradicts Phase 4's "recovery never auto-applies" and the kill test's assertion that the file is untouched, and it would write a rolling backup for a state nobody approved. The alternative the plan allows — a successor journal based on the file's real bytes, carrying the replayed patches, written before the old journal is removed — gives the same durability without touching the script. Its three conditions are all met and checked off above. ADR 0016 records the reasoning and the alternatives.

**One case the plan did not name.** A journal *none* of whose records replay would, under a naive rebuild, be replaced by an empty successor — and an empty journal is discarded at the next startup, turning "we could not read your edits" into "your edits are gone". `recovery_accept` now refuses that case outright and leaves the journal on disk, which is the same view `recovery_pending` already takes of a journal it cannot read. Covered by `a_journal_that_cannot_replay_is_left_on_disk_rather_than_emptied`.

**An API change was needed.** `recovery_accept` returns `RecoveryOutcome` rather than `Option<DocumentHandle>`, because the plan asks for a failure that is surfaced rather than silent. Bindings were regenerated through the documented command.

### New risks or follow-up findings

- `RecoveryOutcome::Degraded` leaves a live session with no journal and the old journal still on disk. If that session then saves, the stale journal stays behind and will be offered — and refused as `blocked` — at the next launch, because the file no longer matches its base. That is the honest state and it loses nothing, but it is worth a look during Phase 3's documentation pass so the behaviour is written down somewhere a user-facing message can be checked against.
- Nothing in Phase 1 touched the save path, so F4/F5/F8 are exactly as the audit left them.

### Reviewer notes

- The claim that the new tests catch F2 was verified, not assumed: the old sequence was reinstated in the test helper and four tests failed with F2's symptoms before it was reverted.
- `crates/bridge/tests/persistence.rs` cannot call `recovery_accept` — the crate has no `rlib` — so its `accept` helper mirrors the bridge sequence by hand. The two must be kept in step; both carry a comment saying so.

---

# Phase 2 — Multi-line editor correctness

**Audit findings:** F1  
**Priority:** High user-visible correctness  
**Must complete before:** layout integration and Phase 7

## Objective

Correctly handle embedded hard newlines inside one parsed screenplay block across wrapping, painting, caret placement, selection, mouse hit testing, scrolling, and incremental relayout.

## Tasks

### 2.1 Manually confirm the current defect

- [-] Run `flutter run -d linux`.
  - Deliberately replaced by a Linux-device integration test that renders `EditorSurface` over the real Rust parse of the reference fixture. This session cannot operate a human GUI, and the test exercises the exact widget and `.so` without pretending a manual pass occurred.
- [x] Open `testdata/reference-feature.fountain`.
  - The new integration test parses and opens the generated fixture through `RustDocumentCore`.
- [x] Navigate to known multi-line dialogue/action blocks.
  - The integration test inspects every parsed block containing `\n`, rather than sampling one.
- [x] Capture a before screenshot or written observation.
  - Before the repair, `wrapText("One.\nTwo.", 60)` returned only `(0, 9)`. Fourteen focused assertions failed: the painter's sole slice still contained `\n`, the caret after it stayed on row 0, and a row-1 click mapped into row 0.
- [x] Verify whether:
  - text overlaps the following row;
  - caret placement is wrong after `\n`;
  - mouse clicks map to wrong offsets;
  - selection rectangles are wrong.
- [-] If the reported defect cannot be reproduced, stop this phase and document the discrepancy before changing code.
  - Not applicable: the focused regressions reproduced F1 before implementation.

### 2.2 Define hard-newline semantics

- [x] Treat embedded `\n` as a mandatory visual line break.
- [x] Match the Rust `break_lines` split-first behavior.
- [x] Decide and document offset ownership at the newline:
  - visual line ending offset;
  - next line starting offset;
  - click behavior at line end;
  - caret affinity if applicable.
- [x] Ensure the newline remains part of the model text and is not dropped.
- [x] Ensure behavior is valid for:
  - leading newline;
  - trailing newline;
  - consecutive newlines;
  - empty visual lines;
  - newline adjacent to wrap boundary.

### 2.3 Repair `wrapText`

Likely area: `app/lib/editor/line_layout.dart`.

- [x] Split the source text into hard-line segments before soft wrapping.
- [x] Preserve source offsets across each segment.
- [x] Represent empty hard lines explicitly.
- [x] Do not count `\n` as a printable column.
- [x] Ensure soft-wrap boundaries retain correct absolute offsets.
- [x] Avoid producing phantom lines.
- [x] Keep performance suitable for the keystroke path.

### 2.4 Repair `DocumentLayout`

- [x] Map block-local offsets to the correct visual line after hard breaks.
- [x] Map visual line/column positions back to the correct model offsets.
- [x] Ensure incremental rewrap invalidates all affected visual lines.
- [x] Ensure downstream row indexes update correctly when a block gains or loses hard lines.
- [x] Preserve stable block identity and patch-in-place behavior.
- [x] Confirm no full-document refetch was introduced.

### 2.5 Repair painting and geometry

Likely area: `editor_surface.dart`.

- [x] Paint one visual line per grid row.
- [x] Never pass a multi-line string to a one-row paint operation.
- [x] Verify caret x/y after every embedded newline.
- [x] Verify selection rectangles spanning hard and soft wraps.
- [x] Verify click-to-offset mapping on every visual line.
- [x] Verify drag selection across newline boundaries.
- [x] Verify scrolling and visible-row calculation with extra visual rows.
- [x] Verify semantics/accessibility text remains coherent.

### 2.6 Add regression tests

Unit tests:

- [x] `"One.\nTwo."`
- [x] `"One.\nTwo.\nThree."`
- [x] `"\nTwo."`
- [x] `"One.\n"`
- [x] `"One.\n\nThree."`
- [x] Hard newline plus soft wrap on both sides.
- [x] Unicode before and after newline.
- [x] Tabs and spaces near newline, anticipating Phase 6 alignment work.

Widget/geometry tests:

- [x] Caret after newline.
- [x] Caret at beginning of second hard line.
- [x] Mouse click on second hard line.
- [x] Selection across newline.
- [x] Selection across hard newline plus soft wrap.
- [x] Incremental edit inserts a newline.
- [x] Incremental edit removes a newline.
- [x] Opening the reference fixture produces non-overlapping visual rows.

### 2.7 Manual verification

- [-] Reopen `reference-feature.fountain` manually.
  - Deliberately replaced by the real Linux-device integration test described in 2.1.
- [x] Capture an after screenshot or written observation.
  - The reference fixture now lays out as 2,880 blocks and 6,510 rows; every visual slice from every multi-line block excludes `\n`, and every following block starts at or below its predecessor's end row.
- [x] Verify typing, clicking, selecting, copying, and pasting in multi-line blocks.
  - Widget tests cover incremental insertion/removal, real pointer click and drag gestures, selection across hard and soft wraps, and copy/paste while preserving the hard break.
- [x] Verify no regression in single-line editor-authored blocks.
  - The complete 279-test Flutter unit/widget suite passes.
- [x] Verify the keystroke benchmark remains within the existing budget.

## Exit conditions

- [x] Embedded newlines are represented as mandatory visual breaks.
- [x] Painting, caret, click mapping, and selection agree.
- [x] Reference script no longer misrenders.
- [x] New unit and widget tests pass.
- [x] Existing editor and performance tests pass.
  - `flutter test` and the benchmark pass. The full real-core `editor_test` is 6 passed, 1 failed on the unchanged F13 stolen-Enter case assigned to Phase 2B; its new reference-fixture case passes.
- [x] No bridge round-trip was added to the per-keystroke wrap path.

## Suggested commit boundary

- [ ] `fix(editor): support hard newlines inside screenplay blocks`

## Implementation log — Phase 2

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** OpenAI GPT-5.6 Sol (OpenCode)
**Starting commit:** `67e872e` (Phase 1)
**Ending commit:** working tree

### Changes made

- `app/lib/editor/line_layout.dart`: split model text into hard-line segments before soft wrapping, retained absolute UTF-16 ranges, represented empty hard lines, and recorded each terminating newline's model offset without putting it in the printable slice.
- `DocumentLayout` keeps its existing row/index machinery; the corrected line list makes caret, click, scrolling and incremental reindexing agree without a refetch or bridge call.
- `app/lib/editor/editor_surface.dart`: selection painting now draws each printable line independently and gives a selected non-printing newline a half-cell marker.
- No Rust, bridge API, generated binding, dependency, or screenplay-semantic code changed.

### Tests added or changed

- `line_layout_test.dart`: hard-line matrices for leading, trailing and consecutive newlines, soft wraps on both sides, wrap-boundary adjacency, Unicode, tabs/spaces, newline ownership and downstream rows.
- `editor_controller_test.dart`: caret, vertical movement, real pointer click/drag, hard-plus-soft selection, incremental newline insertion/removal and multi-line copy/paste.
- `editor_test.dart`: opens the generated reference fixture through the real Rust core and proves every one-row paint slice excludes `\n` and downstream row ranges do not overlap.
- The new tests were run before implementation: fourteen focused assertions failed with F1's row/offset symptoms.

### Commands run

```text
cd app
flutter analyze                                                   # clean
flutter test                                                      # 279 passed
flutter test integration_test/editor_test.dart -d linux           # 6 passed, 1 failed (unchanged F13; Phase 2B)
flutter test integration_test/keystroke_benchmark_test.dart -d linux
                                                                  # 2 passed

cargo fmt --all --check                                           # clean
cargo clippy --workspace --all-targets -- -D warnings             # clean
cargo test --workspace                                            # 343 passed
python3 tools/check_layering.py                                   # clean
```

### Results

The reference fixture gained the missing hard rows (6,419 at the Phase 0 baseline to 6,510 now). Open-to-editable was 55.5 ms; keystroke-to-patch p99 was 1.38 ms; frame-build p99 was 4.42 ms; journalled keystroke p99 was 1.27 ms; no frame exceeded 16 ms.

### Deviations from plan

The two manual GUI launches were deliberately replaced, not silently checked off. A Linux-device integration test opens the actual fixture against `libslugline_bridge.so`, renders the real `EditorSurface`, and exhaustively checks every multi-line block. Human visual inspection remains useful, but no screenshot or human `flutter run` interaction was claimed.

Phase 2B was not changed. Its F13 failure remains exactly visible in the full `editor_test`, and F14 remains assigned there.

---

# Phase 2B — Keys swallowed by editor panels

**Findings:** F13, F14 — both discovered by the Phase 0 baseline, not by the audit
**Priority:** High user-visible correctness (F13 breaks the primary writing gesture)
**Must complete before:** Phase 9C's end-to-end smoke test can mean anything

## Objective

Enter must split the block whenever the writer has not chosen a suggestion, and Escape must
close whichever panel is open. See the Phase 0 implementation log for the evidence and the
reproduction.

## Tasks

### 2B.1 Pin the failures

- [x] Confirm the four baseline failures still reproduce (`editor_test`, `writing_test`).
- [x] Add a widget-level regression test that drives the editor with a *non-empty*
      `fake_core.completions`, so the stolen-Enter path is reachable without the `.so`.
- [x] Confirm that test fails before the repair.

### 2B.2 Decide the acceptance gesture (F13)

- [x] Decide what accepts a completion. `SPEC.md` §Phase 5 and the audit both describe
      acceptance as explicit; Tab is already wired to it.
- [x] Decide whether Enter accepts at all, and if so only when the writer has moved the
      highlight off the default with the arrow keys.
  - Enter accepts after explicit Up/Down navigation. With one candidate the index remains
    zero, but the arrow key itself is still an explicit choice; ADR 0017 records that edge case.
- [x] Stop the index from suggesting the block currently being typed — a scene heading
      offered as the sole completion for itself is never a useful suggestion.
- [x] Record the decision as an ADR; it settles a §16 question the code answered silently.

### 2B.3 Repair the key routing

- [x] Reorder or guard the `when _controller.completions.isNotEmpty` arms in
      `editor_surface.dart::_onKey` so Enter reaches `splitBlock()` under the decided rule.
- [x] Verify Tab still accepts a completion, and still tabs when there is none.
- [x] Verify Escape dismisses the popup without touching the document.
- [x] Keep the popup's arrow-key handling.

### 2B.4 Root-cause and repair the palette Escape (F14)

- [x] Determine whether Escape genuinely fails to leave the palette's focused `TextField`,
      or whether this is an artifact of the live integration binding's text-input connection.
- [x] If it is a real defect, repair it in `command_palette.dart` and add a widget test.
- [-] If it is a harness artifact, adjust `writing_test.dart` and say why in a comment —
      do not weaken the assertion.
  - Not applicable. The defect reproduced in a widget test once the double was given a
    non-empty completion list: after Find had focus, palette `autofocus` did not reclaim it,
    and the editor's completion Escape arm consumed the key. The integration assertion is unchanged.

### 2B.5 Audit the test double for other silent gaps

- [x] Review `app/test/support/fake_core.dart` for defaults that are empty in the double and
      non-empty against the real core, and which therefore hide a branch.
- [x] Note anything found; repair only what is cheap and in scope.
  - `completions = const []` was the silent gap. The new Enter and panel-focus regressions
    opt into a non-empty list, and the field now documents that requirement. `tabAnswer` and
    `suggestion` are intentionally injected by their focused tests; `find` computes real hits;
    the remaining empty persistence answers do not hide an editor key-routing branch.

## Tests

- [x] Enter splits the block while a completion is offered.
- [x] The chosen acceptance gesture accepts the completion.
- [x] The block being typed is not offered as its own completion.
- [x] Escape closes the find bar, the palette, and then collapses the selection.
- [x] `editor_test.dart` and `writing_test.dart` pass in full.

## Exit conditions

- [x] All six integration tests pass locally.
- [x] The acceptance gesture is specified in an ADR, not left to arm ordering.
- [x] No regression in `flutter test` or the keystroke benchmark.

## Suggested commit boundary

- [ ] `fix(editor): stop the completion popup swallowing Enter`

## Implementation log — Phase 2B

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** OpenAI GPT-5.6 Sol (OpenCode)
**Starting commit:** `2c12109` (Phase 2)
**Ending commit:** working tree

### Changes made

- `EditorSurface` now lets Enter split while the popup only has its automatic default
  highlight. Up/Down marks the popup as explicitly navigated, after which Enter accepts;
  Tab continues to accept the default candidate.
- `doc_complete` removes an exact no-op replacement, so a newly indexed cue or scene
  component cannot be offered back as its own sole completion.
- `CommandPalette` gives its query field an explicit focus node and requests it on creation,
  matching the already-correct Find bar rather than relying on `autofocus` to displace the
  previously focused field.
- Added ADR 0017 and aligned `SPEC.md` and `docs/KEYMAP.md` with the explicit gesture.
- Audited `FakeCore`'s quiet defaults. Only `completions` hid this key-routing branch; tests
  now opt into the non-empty state and its field comment records why.
- No bridge signature, generated binding, dependency, Fountain semantic, or persistence code changed.

### Tests added or changed

- `autocomplete_test.dart`: default Enter splits with a candidate showing; Up/Down then
  Enter accepts it. The first test failed before the repair because `core.enters` stayed empty.
- `element_selector_test.dart`: Find → Escape → palette → Escape with non-empty editor
  completions. It failed before the repair with the palette still visible, reproducing F14
  without the `.so`.
- `doc.rs`: `a_block_is_not_offered_back_to_itself_as_a_completion`.
- The existing `writing_test.dart` assertion was not weakened or adjusted.

### Commands run

```text
flutter test integration_test/editor_test.dart -d linux           # before: 6 passed, 1 failed
flutter test integration_test/writing_test.dart -d linux          # before: 8 passed, 3 failed
flutter test test/editor/autocomplete_test.dart --plain-name ...  # failed before repair
flutter test test/editor/element_selector_test.dart --plain-name ...
                                                                  # failed before repair

cargo fmt --all --check                                           # clean
cargo clippy --workspace --all-targets -- -D warnings             # clean
cargo test --workspace                                            # 344 passed
python3 tools/check_layering.py                                   # clean
cd app && flutter analyze                                         # No issues found
cd app && flutter test                                            # 282 passed
cd app && flutter build linux --release                           # succeeds

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/editor_test.dart              -d linux   # 7 passed
flutter test integration_test/writing_test.dart             -d linux   # 11 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
```

### Results

F13 and F14 no longer reproduce. All 45 integration tests pass. The 120-page benchmark
reported 3.03 ms keystroke-to-patch p99, 5.41 ms frame-build p99, 2.61 ms journalled
keystroke p99, and 0 of 271 frames over 16 ms.

### Deviations from plan

The self-suggestion is filtered at the bridge result rather than removed from the entity
index. The index's documented exact-prefix ranking remains intact for other consumers; the
bridge removes only a candidate that would replace the active segment with identical text.

### New risks or follow-up findings

None. The real Linux `ibus` + CJK manual gate remains Phase 9A and was not claimed here.

---

# Phase 3 — Documentation, ADR, and CI truthfulness

**Audit findings:** F7 and test-gap #4  
**Priority:** High process integrity  
**Can overlap with:** Phases 1–2 only if done in a separate commit

## Objective

Restore documentation and CI as trustworthy descriptions of the project’s actual state.

## Tasks

### 3.1 Update project status documents

- [x] Update `README.md` from Phase 1 status to the actual completed phase.
  - "Phases 0–6 written, in a stabilization gate", naming what each crate now is and
    saying outright that page counts are blank because `layout` is unwired.
- [x] Update `AGENTS.md` to reflect:
  - Phases 0–6 completed subject to this remediation;
  - `layout` is implemented but not yet fully integrated;
  - `render_pdf` and `spell` remain placeholders;
  - the actual integration tests run in CI.
  - The `layout` point is its own bullet, because "Phase 6 is complete" was exactly the
    sentence that misled: the crate is done and the feature does not exist.
- [x] Update the project’s current-phase/progress section.
  - Three of them, since the project has three: `README.md`'s status and remediation
    sections, `AGENTS.md`'s first three bullets, and a new "where the project is" note in
    `SPEC.md` §0 that names this plan as the live tracker.
- [x] Mark the remediation period as a stabilization gate before Phase 7.
  - In all three, plus a blockquoted gate directly above `SPEC.md`'s Phase 7 heading.
- [x] Remove or update stale comments pointing to already-completed phases.
  - `files.rs`'s `page_count` ("Zero until Phase 6's `layout` crate can count pages" —
    Phase 6 came and went), `line_layout_test.dart`'s header (which promised the editor
    would render Rust's rows), and `metrics.dart`'s "these numbers are on loan" (they are
    not on loan; ADR 0018 keeps them). `spell`, `render_pdf` and `file_chooser.dart` point
    at Phases 9, 7 and 10, which have not happened, and were left alone.
- [x] Correct the `document.rs` provenance re-anchoring comment or explicitly defer it.
  - Deferred explicitly: it now says Phase 4 shipped without it, that serialising from the
    original source is correct, that the only cost is holding those bytes for the session,
    and that it waits on a measurement rather than on a phase.

### 3.2 Update SPEC invariant checklist

- [x] Mark existing verified invariants accurately.
  - `roundtrip_is_byte_exact`, `parser_never_panics` and
    `autocomplete_requires_explicit_action` ticked; the last of those was settled by
    Phase 2B and ADR 0017.
- [x] Link or name the actual tests for:
  - byte-exact round trip;
  - parser never panics;
  - element change preserves text;
  - unsaved-change/recovery guarantees where applicable.
- [x] Leave later-phase invariants unchecked.
  - `spellcheck_never_modifies` (9), `appearance_prefs_dont_affect_pagination` (10),
    `pdf_output_is_deterministic` (7), each now saying which phase owns it.
- [x] Add explicit remediation gates if the spec has a phase checklist section.
  - A new unticked Phase 6 exit criterion ("reachable from the application"), the Phase 7
    gate blockquote, and the §0 note that a tick means implemented *and* tested.
- [x] Ensure no item is checked when only half implemented, such as scroll persistence
      without restoration.
  - Session restore unticked with F6 named. Two more were found while checking the rest:
    the external-modification prompt has no own-save suppression (F4/F8) and nothing
    serialises two saves of one script (F5). Both are now unticked lines that say so.
    `no_network_syscalls` was already unticked; it now says why, since §1.2 calls it a
    build-time assertion and there is no such assertion.

### 3.3 Record decisions as ADRs

Create or update ADRs for:

- [x] Fluid, unpaginated editor through 1.0. — ADR 0018.
- [x] Dart editor wrapper retained but differentially pinned to Rust line breaking.
  - ADR 0018, same record: D-1 is one decision and splitting it would have produced two
    halves neither of which stands alone.
- [x] Rust pagination exposed through the bridge as an asynchronous snapshot job. — ADR 0020.
- [x] `page_count` updated after successful saves from a background pagination snapshot.
  - ADR 0020, same record: the page count is the first consumer that forces the wiring,
    which is the argument for doing them together.
- [x] Literal emphasis markers in the editor for 1.0. — ADR 0019.
- [x] Pinned entity storage and ranking decision from Phase 5. — ADR 0021.
- [x] Phase 6 checkpoint/fingerprint pagination design if not already documented. — ADR 0022.
- [x] One recovery offer per launch remains acceptable for 1.0. — ADR 0023.
- [x] Interval autosave remains active during continuous typing. — ADR 0024, which extends
      ADR 0014 rather than editing it, per this repository's rule.
- [x] The focused Phase 7 review requirement for the back half of `layout/engine.rs`.
  - ADR 0025, which makes it a gate *on* Phase 7 rather than a task inside it.

Each ADR must include:

- [x] Context.
- [x] Decision.
- [x] Alternatives considered.
- [x] Consequences.
- [x] Tests or invariants enforcing the decision.
  - Every record names them. Where the decision precedes its implementation (0018, 0020,
    0024) the section says so and lists what must exist before the owning remediation phase
    closes; where a claimed test turned out not to exist, the record says that instead —
    see "New risks or follow-up findings".
- [x] Status and date.

### 3.4 Close CI integration-test gaps

- [x] Inspect current CI commands.
  - Three jobs: `rust`, `fuzz`, `flutter`. The `flutter` job already built the release
    bundle, asserted the `.so` was bundled and the 60 MB budget, installed `xvfb`, and ran
    three of the six integration tests.
- [x] Add `.so` build/setup before all bridge-dependent Flutter integration tests.
  - Already correct and unchanged: `flutter build linux --release` precedes every one of
    them, and every test step is in the same job, so they all run against that bundle.
- [x] Run:
  - `bridge_test`
  - `editor_test`
  - `keystroke_benchmark_test`
  - `writing_test`
  - `ime_test`
  - `persistence_test`
  - Six steps, one per file, so a failure names itself. The benchmark is last so nothing
    else is competing for the runner while it measures.
- [x] Confirm `xvfb` or equivalent display setup is applied consistently.
  - Every one of the six is `xvfb-run -a`.
- [x] Ensure CI fails when any intended integration test fails.
  - No `continue-on-error` anywhere in the workflow, and every test step is a plain `run`.
- [x] Update `AGENTS.md` to list exactly what CI runs.
  - Named individually, with the instruction to add a step in the same change as a seventh
    integration file. `SPEC.md` §13 gained a per-job table saying the same thing.

### 3.5 Add real full-disk/ENOSPC CI coverage

- [x] Identify the test using `SLUGLINE_FULL_DISK_DIR`.
  - `crates/bridge/tests/persistence.rs::a_full_filesystem_is_a_clear_error_and_no_truncated_file`,
    via `full_disk_directory()`.
- [x] Mount or provision a deliberately small tmpfs in CI.
  - 4 MB at `/mnt/slugline-full-disk`, `mode=1777` because the test runs as the
    unprivileged runner user.
- [x] Set `SLUGLINE_FULL_DISK_DIR` to that location.
  - On the `cargo test --workspace` step only, so nothing else inherits it.
- [x] Confirm the test reaches a real full-disk condition rather than only fallback
      classification.
  - Confirmed locally, not assumed: the same mount was reproduced without root in a user
    namespace (`unshare -Umr`, `mount -t tmpfs -o size=4m,mode=1777`) and the test passed
    with the variable set. Passing *requires* the real path — with the directory present the
    fallback branch is unreachable, and the assertions are `expect_err` plus
    `matches!(SaveError::NoSpace)`, which only hold if the write genuinely returned ENOSPC.
- [x] Verify cleanup runs even after test failure.
  - An `if: always()` unmount step, so a failure that leaves the ballast behind cannot hand
    a full filesystem to a later run on a cached runner. The test also removes its own
    ballast and script on the success path.
- [x] Document any CI-platform limitation.
  - In `AGENTS.md`: CI has root and mounts the tmpfs, a local run has neither and falls back
    to the classification half — with the `unshare` recipe for running the real thing
    locally anyway.

### 3.6 Documentation verification

- [x] Search for stale phase references.
  - `Phase 1 complete`, `Phases 0–4 are complete` and the `page_count`/`metrics.dart`
    comments were the whole set; all corrected. The three surviving forward references
    (Phases 7, 9, 10) name phases that genuinely have not happened.
- [x] Search for “placeholder” claims about `layout`.
  - One remained, in `crates/layout/src/lib.rs`, and it is accurate: it describes a
    constant kept for callers of the *Phase 0* placeholder, not the crate.
- [x] Search for incorrect integration-test counts.
  - `AGENTS.md`'s "CI runs them after the release build" was the false one. Now named
    individually in `AGENTS.md` and tabulated in `SPEC.md` §13.
- [x] Search for unresolved §16 decisions now settled by D-1 through D-5.
  - Three ticked with their ADR: fluid editor (0018), literal emphasis (0019), pinned
    entity storage (0021). Licence and scene-number gutter style remain genuinely open; the
    gutter line now says `layout` implements all three styles and Phase 7 picks.
- [x] Confirm docs do not claim F1/F2/F3 are fixed until their phases actually pass.
  - F1 and F2 are fixed and their phases passed. F3 is *not*, and four documents now say
    so unprompted: the new Phase 6 exit criterion, `SPEC.md` §2.5's layering note, the
    library page-count line, and `AGENTS.md`'s dedicated bullet.

## Exit conditions

- [x] README, AGENTS, SPEC, ADRs, and CI agree.
- [x] Six intended integration tests gate CI.
- [x] Real ENOSPC behavior is exercised in CI.
- [x] No known checked specification item overstates implementation.
  - Four boxes were unticked in this phase; three of them were found by reading the spec
    against the audit rather than by the plan naming them.
- [x] Future coding agents receive accurate project context.

## Suggested commit boundaries

- [x] `docs: synchronize phase status and architecture decisions`
- [x] `ci: run full integration suite and real ENOSPC test`

## Implementation log — Phase 3

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `cdf3f3d` (Phase 2B)
**Ending commit:** the two commits named above

### Changes made

Documentation:

- `README.md`: status rewritten from "Phase 1 complete… there is still no editor" to what
  the tree actually contains, including the fact that `layout` is unwired. The remediation
  section now lists which phases are done instead of apologising for a stale line.
- `AGENTS.md`: phases corrected; two new bullets — one for `layout` being implemented and
  unintegrated, one for the stabilization gate and this plan being the live tracker; the
  `metrics.dart` bullet rewritten around ADR 0018; the CI claim made exact; the full-disk
  paragraph updated with what CI does and how to run the real thing locally.
- `SPEC.md`: a "where the project is" note in §0; a Phase 7 gate blockquote; §13's invariant
  checklist ticked, named and explained; §13 gained a table of what CI actually runs; §16's
  three settled decisions ticked with their ADRs; §2.5's layering rule corrected to name
  `check_layering.py` (ADR 0004) and the missing `bridge → layout` edge; four Phase 4/6
  boxes unticked with their finding numbers.
- `docs/DECISIONS.md`: ADRs 0018 through 0025.

Code comments only — no behaviour changed in this phase:

- `crates/document/src/document.rs`: the provenance re-anchoring comment now defers
  explicitly instead of pointing at a phase that has passed.
- `crates/bridge/src/api/files.rs`: `page_count`'s comment names ADR 0020 instead of
  Phase 6.
- `app/lib/editor/metrics.dart`, `app/test/editor/line_layout_test.dart`: both said the Rust
  crate would replace the Dart geometry; ADR 0018 decided otherwise, and they now describe
  the contract and the differential test that will hold it.

CI:

- `.github/workflows/ci.yml`: the `flutter` job runs all six integration tests, one step
  each, under `xvfb-run`, benchmark last. The `rust` job mounts a 4 MB tmpfs, names it in
  `SLUGLINE_FULL_DISK_DIR` for `cargo test --workspace`, and unmounts it with `if: always()`.

### Tests added or changed

None, and that is the point of this phase: it changes what CI *runs* and what the documents
*claim*, not what the code does. The three integration files added to CI already existed and
already passed; they simply gated nothing.

### Commands run

```text
cargo fmt --all --check                                       # clean
cargo clippy --workspace --all-targets -- -D warnings         # clean
cargo test --workspace                                        # 344 passed, 0 failed
python3 tools/check_layering.py                               # clean, 7 crates
python3 tools/make_reference.py --check                       # fixture current
cd app && flutter analyze                                     # No issues found
cd app && flutter test                                        # 282 passed

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/editor_test.dart              -d linux   # 7 passed
flutter test integration_test/writing_test.dart             -d linux   # 11 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed

# The ENOSPC path, proved before writing the CI step:
unshare -Umr sh -c 'mount -t tmpfs -o size=4m,mode=1777 tmpfs $D &&
  SLUGLINE_FULL_DISK_DIR=$D cargo test -p slugline_bridge --test persistence a_full_filesystem'
                                                              # 1 passed, real path
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"   # valid
```

### Results

Rust 344 and Flutter 282, both unchanged from Phase 2B — a documentation phase that moved a
test count would be a documentation phase that did something else. All 45 integration tests
pass locally, which matters more than usual this time: three of them now gate CI and never
have before.

### Deviations from plan

**Ten ADR bullets became eight records.** D-1 (fluid editor + pinned Dart wrapper) is one
decision with one rationale, and D-3 (bridge pagination + page count after save) is one
decision whose second half is the argument for its first. Splitting either would have left
four records that only make sense read in pairs. Every bullet is accounted for above with
the record that carries it.

**Three ADRs record decisions that are not implemented yet** — 0018's differential test,
0020's bridge wiring, 0024's own-save suppression. Their "Tests and invariants" sections say
so and list what must exist before remediation Phases 6 and 4 close, rather than describing
tests as though they were there.

### New risks or follow-up findings

Writing the ADRs meant checking every test each one claimed, and two claims did not survive.
Both are recorded inside the ADR that wanted them rather than quietly dropped:

- **Nothing tests that a pinned entity survives losing its last occurrence** (ADR 0021).
  That is the single behaviour a pin exists for. It holds by construction —
  `EntityIndex::complete` merges the pinned map in unconditionally — and by construction is
  not by test. One unit test in `entities.rs`, whenever that file is next open.
- **Nothing compares `repaginate` against `paginate_snapshot` for the same edited
  snapshot** (ADR 0022). `incremental.rs` proves the reused *prefix* matches the previous
  output and that the cache was used; it never checks that the incremental result equals a
  full pagination of the edited document, which is the assertion that would catch
  incremental drift. Assigned to the ADR 0025 review in Phase 6G.

Also worth carrying forward: the `Degraded` recovery risk logged in Phase 1 was checked
against this phase's documentation pass. It is honest behaviour and loses nothing, but no
user-facing document describes it; Phase 4's dialogs work is the natural place, since that
is where the stale-journal prompt would be seen.

### Reviewer notes

- The tmpfs step was verified before it was written, in a user namespace, because a CI-only
  step that has never run is exactly the kind of thing this phase exists to stop the project
  from claiming.
- Four SPEC boxes were unticked. Three of them (F4, F5, F8) the plan did not ask for; they
  were found by reading the checklist against the audit, which 3.2's last task requires in
  spirit. Their phases have not run yet, so ticking them would have been the same defect
  this phase is repairing.
- No ADR was edited. ADR 0024 extends ADR 0014 and says so in its header, per the rule in
  `AGENTS.md`.
- Phase 10's audit finding closure table still shows F2, F13 and F14 unticked although
  Phases 1 and 2B closed them, while F1 is ticked. That table is Phase 10's to sign off
  under a full verification run, so it was left alone rather than ticked from here; this
  note is so the inconsistency is not read later as three open findings.

---

# Phase 4 — Save serialization and external-change correctness

**Audit findings:** F4, F5, F8  
**Priority:** High stabilization  
**Internal order:** F5 → F4 → F8

## Objective

Guarantee that saves for one document cannot interleave, that self-generated watcher events are suppressed safely, and that external-change disk work does not block the actor.

---

## Phase 4A — Serialize saves per session

### Tasks

- [x] Identify every caller of `write_document`.
  - Three, all in `files.rs`: `doc_save`, `doc_save_as`, `doc_autosave`. From Dart:
    `core.save()` (Ctrl+S and the palette, via `saveWithDialogs`), `core.saveAs()` (Save As,
    Export, and the external-change dialog's "Save as"), and `core.autosave()` (both
    `AutosaveDriver` timers and `saveNow`). `backup_restore` does not call it but writes the
    same file by the same three-step shape, so it is covered too.
- [x] Confirm overlap is possible between:
  - interval autosave;
  - idle autosave;
  - explicit Ctrl+S;
  - dialog-mediated save;
  - recovery-triggered save if introduced in Phase 1.
  - Confirmed for the first four, and the audit's pair — Ctrl+S against an autosave already
    past `_due` — is the one that is reachable today. The two timers cannot overlap *each
    other*: both go through `_due → _save`, which the driver's `_saving` flag guards. Phase 1
    introduced no recovery-triggered save on purpose (it writes a successor journal, not the
    script), so there is nothing there to overlap.
- [x] Add per-session save coordination in `AppState` or the session object.
  - `Session::save_lock`, an `Arc<Mutex<()>>` taken off the actor thread and held across all
    three steps. ADR 0026.
- [x] Choose one behavior:
  - queue the latest requested save; or
  - reject/coalesce redundant overlapping saves and schedule the newest revision.
  - Both, and they turn out to be one thing: the second save waits, then **plans again**. So
    it writes the newest revision, or discovers the save it waited for already wrote those
    bytes and answers `Unchanged`. Nothing is refused and nothing is dropped.
- [x] Do not rely only on Dart-side `_saving`.
  - The guarantee is entirely in Rust; `_saving` cannot cover Ctrl+S, which never reaches the
    driver. It is kept, with its comment rewritten to say what it is and is not, and it now
    *owes* the save it declines rather than dropping it.
- [x] Ensure two save plans for the same session cannot write in reverse order.
- [x] Allow unrelated sessions to save independently if the architecture later supports them.
  - Per session, and `one_script_at_the_disk_does_not_hold_up_another` is the test that stops
    a future global lock being introduced by accident.
- [x] Ensure save completion marks only the revision actually persisted.
  - `mark_saved_at(plan.revision)` was already correct. What was not: `SaveStateChanged`
    emitted a hardcoded `dirty: false`, and `AutosaveDriver` cancelled its timers on any
    `Saved`. Both now read the document's real state, so an edit that landed mid-write is
    reported unsaved and stays on the clock.
- [x] Ensure journals checkpoint against the bytes that actually won.
  - Asserted directly: `journal_agrees_with_the_file` reads the live journal off disk and
    requires `journal::verify` to accept it against the file's current contents.
- [x] Apply equivalent protection to concurrent `library_open` check-then-act behavior, or explicitly separate it into a follow-up task with a regression test.
  - Repaired here rather than deferred: `open_source` makes the `handle_for` check again
    inside the actor closure that inserts, where it is atomic. `library_open`'s earlier check
    is now documented as the optimisation it is.

### Tests

- [x] Start save A.
- [x] Edit the document.
- [x] Start save B.
- [x] Force A and B completion order to invert.
  - A `#[cfg(test)]` seam holds A between its plan and the disk. It is the only way to make
    the inversion deterministic, and it is keyed by path so tests cannot stall each other.
- [x] Assert the file ends with the newest revision.
- [x] Assert UI “Saved” status corresponds to durable bytes.
  - Two halves. In Rust: each save reports the byte count it actually wrote, and the document
    is clean at the end. In Dart: `an edit that lands mid-write does not stop the clock`,
    since `SaveStatus.label` reads `core.dirty` and the clock is what gets it to false.
- [x] Assert journal state matches the resulting file.
- [x] Test explicit save overlapping autosave.
- [x] Test duplicate concurrent library open if repaired here.
  - Both halves: `open_source` called twice over one path (deterministic), and eight
    concurrent `library_open` calls (realistic).

### Exit conditions

- [x] Same-session saves are serialized or safely coalesced.
- [x] No older save can overwrite a newer acknowledged save.
- [x] Regression tests pass.
  - And were confirmed to fail first: with the lock and the `handle_for` re-check reverted,
    four of the five Rust tests fail; with the Dart changes reverted, both Dart tests fail.

### Implementation log — Phase 4A

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `792d6b5` (Phase 3)
**Ending commit:** this commit

#### Changes made

- `crates/bridge/src/state.rs`: `Session` gained `save_lock: Arc<Mutex<()>>` and
  `Session::save_lock()`. The field comment says what it is for and the one rule that keeps
  it safe — it is never locked on the actor thread.
- `crates/bridge/src/api/files.rs`:
  - `write_document` gained a step zero that takes the lock before it plans, so plan, write
    and record are one atomic sequence per session.
  - `backup_restore` takes the same lock: it is a write of the document's file by another
    name, and an autosave landing inside one would leave the file and the document
    describing different versions.
  - Step three now answers whether the document is *still* dirty, and `SaveStateChanged`
    carries that instead of a hardcoded `false`.
  - `open_source` re-checks `handle_for` inside the actor closure that inserts.
  - A `#[cfg(test)]` `stall` module: the seam the inversion test needs. No call site and no
    static exist outside `cargo test`.
- `app/lib/editor/autosave.dart`: an autosave that collides with one in flight is now *owed*
  rather than dropped, and paid when the in-flight save returns; the timers are cancelled
  only when the document actually came back clean. The class doc gained a "Two saves at
  once" section saying where the guarantee lives, and `_saving`'s comment no longer claims
  to be it.
- `app/test/support/fake_core.dart`: writes can be held open (`holdWrites`), and a write
  now snapshots its bytes before the hold and clears the dirty flag only if nothing changed
  meanwhile — the same shape as `mark_saved_at(plan.revision)`.
- `SPEC.md` §Phase 4: the "two saves cannot interleave" box is ticked, with what makes it
  true and the tests that hold it.
- `docs/DECISIONS.md`: ADR 0026.
- No bridge signature changed, so no binding regeneration was needed. No dependency was
  added.

#### Tests added or changed

Five in `crates/bridge/src/api/files.rs` (the first unit tests that file has had) and two in
`app/test/editor/autosave_test.dart`. All seven are named in ADR 0026.

#### Commands run

```text
cargo fmt --all --check                                       # clean
cargo clippy --workspace --all-targets -- -D warnings         # clean
cargo test --workspace                                        # 349 passed, 1 failed (F16,
                                                              #   pre-existing, see below)
python3 tools/check_layering.py                               # clean, 7 crates
cd app && flutter analyze                                     # No issues found
cd app && flutter test                                        # 284 passed
cd app && flutter build linux --release                       # succeeds

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
flutter test integration_test/editor_test.dart              -d linux   # 7 passed
flutter test integration_test/writing_test.dart             -d linux   # 11 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed

# The negative controls, run before trusting any of the above:
#   lock + handle_for re-check reverted → 4 of 5 Rust tests fail
#   autosave.dart reverted              → both Dart tests fail
```

#### Results

Rust 344 → 349, Flutter 282 → 284. One Rust test fails, and it is not this phase's: F16
below, a pre-existing `fountain` round-trip case that proptest happened to find during this
verification run.

The integration suite and the benchmark are unchanged by this phase — the keystroke path does
not touch `write_document` — and were run as the Phase 4 gate rather than as evidence for 4A.

#### Deviations from plan

**`library_open` was repaired here rather than deferred.** The plan allows either. It was one
line inside a closure that already existed, in the same file and the same class of defect, and
splitting it out would have cost more in ceremony than it saved in review.

**The tests needed a `#[cfg(test)]` seam in production code.** "Force A and B completion order
to invert" cannot be done from outside — the window is between two steps on two threads. The
seam is a map of holds keyed by the file being written; it is compiled only under `cargo test`
and the shipped library has neither the map nor the call site.

#### New risks or follow-up findings

**F15 — a save checkpoints away the journal record of an edit that landed while it was
writing.** Found while asserting "journals checkpoint against the bytes that actually won",
which is true, but not the whole story.

In step three, `journal.checkpoint(&path, &text)` truncates the journal to a bare header
whose base is the bytes just written, and resets `records` to 0. Its comment says "the
records before it describe edits that are now in the file" — true only if nothing was typed
during the write. If something was, `mark_saved_at(plan.revision)` correctly leaves the
document dirty, but that edit's journal record has just been erased. A crash in the window
between the checkpoint and the next autosave loses it silently: `recovery_pending` finds an
empty journal, treats it as a clean session, and discards it.

The window is one file write plus an actor round trip, which is small; the consequence is
losing user text, which §1.2 calls a P0. Serialization does not widen or narrow it — the
same window existed before Phase 4A and exists after.

It is not repaired here because it is not what 4A is: the fix is for the session to retain
the patches applied since the plan and rebuild the journal through `Journal::rebuild` (which
Phase 1 already added) with base = the written bytes and those patches as its records. That
means a new buffer on `Session`, invalidation rules for it, and its own kill test. It wants
its own phase, in the same neighbourhood as 4B and 4C.

**F16 — the serialiser does not force a transition that would reparse as a title-page
entry.** Not found by reading anything: `cargo test --workspace` failed once during this
phase's verification, in `crates/fountain/tests/canonical_form_is_stable.rs`, and proptest
wrote the shrunk seed into `canonical_form_is_stable.proptest-regressions`. That new line is
the only change to `crates/fountain` in this commit, and it is left in on purpose — deleting
it would un-find the defect.

The case is a `Transition` whose text is `IN: TO:`. Serialised bare, it reparses as nothing:

```text
parse("IN: TO:\n")
  title entries: [TitleEntry { field: Other("IN"), value: "TO:" }]
  elements: []
```

Confirmed against a clean checkout with this phase's changes stashed, so it predates them and
nothing here caused it. The regressions file already pins three siblings — `=== TO:`,
`INT. TO:`, and `.` — which pass, so the serialiser's "would this line be read as something
else" check exists and simply has no case for a title-page key. Per ADR 0007 and `AGENTS.md`
that check lives in `fountain/src/syntax.rs` and is the parser's rules run backwards, so the
repair belongs there and nowhere else.

Severity: Low in practice — a writer would have to name a transition `SOMETHING: SOMETHING`
at the very top of a script — but it is a **byte-exact round-trip** failure, which §13 lists
as an invariant and `SPEC.md` ticks. It is not repaired here because `crates/fountain` is on
this plan's protected list, the change is a Fountain semantics change rather than a save one,
and folding it into a commit about save ordering is exactly what "one focused commit per
logically independent repair" forbids. It needs its own task; until it has one,
`cargo test --workspace` fails this one test.

---

## Phase 4A′ — F15 and F16

Both findings above, repaired in one follow-up pass because each is small, each is
self-contained, and neither belongs in the commit that found it.

### F15 — a save must not checkpoint away what was typed during it

- [x] Keep the records for edits that land between a save's plan and its checkpoint.
  - `Session::begin_save` arms a buffer *inside the closure that reads the bytes*, so no
    edit is ever in neither. `Session::record` appends to the journal as before and then
    keeps the patch. `Session::finish_save` hands them to step three.
- [x] Rebuild rather than truncate, and do it atomically.
  - `Journal::rebuild_at`: ADR 0016's `rebuild` addressed by path instead of by id, because
    a Save As has changed the id by step three while the journal file has not moved.
    Rebuilding by id would leave the old file behind, and an unowned journal is a recovery
    offered for a session that did not crash.
- [x] Leave the ordinary save alone.
  - Nothing typed during the write means an empty buffer means `checkpoint`, exactly as
    before. The rebuild is not on the common path.
- [x] Bound the memory.
  - Armed only for the length of one write, so a session that is not saving buffers nothing.
    That matters because `autosave_enabled: false` is supported: buffering everything since
    the last checkpoint would hold a whole session's patches in RAM.
- [x] Keep the keystroke path where it was.
  - `record` takes its `Patch` by value rather than cloning it. Its one caller built it and
    dropped it, so this allocates nothing new.
- [x] Disarm on every path that plans and then does not write.
  - Three: no path, nothing to write, and the write failed. One `abandon_save` for all of
    them, and one test covering each — a buffer left armed would hold patches for a
    checkpoint that never comes.
- [x] Define the failure behaviour.
  - A failed rebuild leaves the journal untouched. Its base no longer matches the file, so
    recovery refuses it rather than replaying onto the wrong bytes; nothing is destroyed.
    The same shape as the failed `checkpoint` it replaces.
- [x] Tie the buffer's lifetime to the journal it describes.
  - `Session::set_journal` clears it. `doc_reload` and `backup_restore` replace the journal
    outright, and a "Take Theirs" landing during a save would otherwise have those records
    rebuilt into a journal that never held them, for a document that no longer exists.
- [x] Record the decision. — ADR 0027, which extends ADR 0013.

Tests, in `crates/bridge/src/api/files.rs` against the real save path:

- [x] `an_edit_typed_during_a_save_is_still_in_the_journal` — the file holds the older
      bytes, the document is dirty, and the journal replayed onto the file gives back what
      the writer can see. That last one is the invariant.
- [x] `a_save_with_nothing_typed_during_it_empties_the_journal`.
- [x] `a_save_that_writes_nothing_does_not_leave_the_session_buffering`.
- [x] Confirmed to fail first: with the rebuild reverted, the mid-write test reports zero
      journalled records where one was typed.

### F16 — a block written bare at the top must not be eaten by the title page

- [x] Repair it where the recognition rules live.
  - `swallowed_by_title_page` in `serialise.rs`, which asks `parse::looks_like_title_key` —
    the parser's own rule, run backwards, as `AGENTS.md` requires. The Action arm already
    asked it inline; the check is now stated once and asked by every kind that can be
    written without a marker.
- [x] Decide how wide to make it.
  - All four bare-writable kinds, not just the one that is reachable. `is_scene_heading` and
    `character_of` both happen to reject the `Key: value` shape today, so only `Transition`
    reaches it — but relying on that coincidence would let a future loosening of either rule
    reopen the hole silently, and what it costs is a block vanishing on reopen.
- [x] Keep the pinned proptest seed.
  - `canonical_form_is_stable.proptest-regressions` keeps the line proptest wrote. It is the
    only reason this was found, and it now passes.
- [x] Do not over-force.
  - Two of the three cases in the first test are negative: the same text below the top, and
    the same text under a title page, are both still written bare.

Tests, in `crates/fountain/src/serialise.rs`:

- [x] `a_block_that_would_be_read_as_a_title_key_is_marked_at_the_top`.
- [x] `no_kind_written_bare_at_the_top_is_eaten_by_the_title_page` — the other three kinds,
      so that if `character_of` or `is_scene_heading` is ever loosened, this is where it
      shows up.
- [x] Both confirmed to fail with the `Transition` guard reverted.

### Implementation log — Phase 4A′

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `934326e` (Phase 4A)
**Ending commit:** this commit

#### Changes made

- `crates/storage/src/journal.rs`: `rebuild` split into `rebuild_at(path, …)` plus a
  by-id wrapper. No behaviour change for the recovery caller.
- `crates/bridge/src/state.rs`: `Session::saving`, `begin_save`, `finish_save`, and
  `record` taking its patch by value.
- `crates/bridge/src/api/files.rs`: the plan closure arms the buffer; three early returns
  disarm through `abandon_save`; step three rebuilds instead of checkpointing when anything
  was typed during the write.
- `crates/bridge/src/api/doc.rs`: one call site, `record(patch)` rather than `record(&patch)`.
- `crates/fountain/src/serialise.rs`: `swallowed_by_title_page`, asked by all four kinds
  that can be written bare.
- `SPEC.md` §Phase 4: a new ticked invariant for the checkpoint rule.
- `docs/DECISIONS.md`: ADR 0027.

#### Tests added or changed

Three in `crates/bridge/src/api/files.rs`, two in `crates/fountain/src/serialise.rs`.

#### Commands run

```text
cargo fmt --all --check                                       # clean
cargo clippy --workspace --all-targets -- -D warnings         # clean
cargo test --workspace                                        # 354 passed, 0 failed
python3 tools/check_layering.py                               # clean, 7 crates
cd app && flutter analyze                                     # No issues found
cd app && flutter test                                        # 284 passed
cd app && flutter build linux --release                       # succeeds

flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/persistence_test.dart         -d linux   # 12 passed
flutter test integration_test/editor_test.dart              -d linux   # 7 passed
flutter test integration_test/writing_test.dart             -d linux   # 11 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed

# Negative controls:
#   step three's rebuild reverted to a plain checkpoint → the mid-write test fails,
#     reporting 0 journalled records where 1 was typed
#   the Transition guard reverted                       → both fountain tests fail
```

#### Results

Rust 349 passed / 1 failed → **354 passed / 0 failed**. The workspace suite is green again:
F16 was the failure, and the fountain and bridge crates gained two and three tests. Flutter
unchanged at 284 — neither finding is Dart's.

#### Deviations from plan

**F16's guard was applied to four kinds where one is reachable.** Argued above rather than
assumed: the narrow fix would have left the invariant true by coincidence of two unrelated
predicates, and the cost of that coincidence breaking is a block disappearing from the
writer's script on reopen.

**F15 has no kill test.** `crates/bridge/tests/persistence.rs` cannot link the bridge, so a
real `SIGKILL` test of this window would have to hand-mirror the save sequence — a second
mirror to keep in step, next to the recovery one already there. The unit test drives the
real `write_document` instead, and asserts the same thing the kill test would: the journal
replayed onto the file equals the document.

#### New risks or follow-up findings

None new. The two carried forward from Phase 4A are now closed, and the `Degraded` recovery
note from Phase 1 is still open for Phase 4B's dialogs work.

---

## Phase 4B — Suppress own-save watcher echoes

### Tasks

- [x] Preserve interval autosave during continuous typing.
  - Not a line of `autosave.dart` changed, and that is ADR 0024's whole point: the
    timer that protects a writer who never pauses is the one that made F4 reachable,
    and the repair had to be on the watcher side or it would have been a regression
    dressed as a fix.
- [x] Add an own-write correlation mechanism in the core.
  - `OwnWrites` in `crates/storage/src/watch.rs`, consulted by the watcher's own
    callback and written by the save path through `Storage::own_writes`.
- [x] Use the audit decision:
  - path;
  - save generation counter;
  - recorded after successful write;
  - swallow the first matching watcher event for that generation.
  - Path and generation as specified. The other two are deliberately not as
    specified, and both changes are load-bearing rather than cosmetic — a record
    made *after* the write loses the race to the event that caused it, and "the
    first matching event" is wrong on exactly the platforms the next task asks
    about. ADR 0028 records the refinement and the two negative controls that
    prove each half of it. See "Deviations from plan".
- [x] Define behavior for platforms that emit multiple filesystem events for one atomic save.
  - Every event about a file that still matches the fingerprint we recorded is
    swallowed, not just the first. Suppression is a property of the file, so a
    filesystem that reports one rename as four events gets the same answer four
    times — `every_event_from_one_save_is_swallowed_not_just_the_first`.
- [x] Avoid suppressing a genuine external write that occurs immediately after the app’s save.
  - The fingerprint is what makes "immediately after" harmless: another program's
    write changes the inode (an atomic save) or the length and mtime (an in-place
    one), so it does not match and is reported. Held by
    `an_external_write_straight_after_our_own_save_is_still_reported` in Rust and
    by the second half of the integration test.
- [x] Keep `doc_external_change` as the correctness backstop.
  - Untouched. `a_save_is_not_reported_as_somebody_elses_write` asserts it still
    answers `(dirty, differs) = (true, true)` in the very scenario the suppression
    exists for — the suppression is *in front of* it, never inside it.
- [x] Clear stale suppression records.
  - Four ways, no clock: the first event that contradicts the record, the next
    write to the same path, `unwatch`, and `close`/Save As. §1.3's idle budget is
    why there is no sweep — nothing here gets less true with age.
- [x] Document the correlation lifecycle.
  - The four numbered steps on `OwnWrites`, at the code, plus ADR 0028.

### Tests

- [x] Save a file.
- [x] Immediately type additional text.
- [x] Deliver the watcher event caused by the app’s own save.
  - Really delivered, not simulated: `our_own_save_is_not_reported` saves through
    `atomic::save_atomically` under a real `FileWatcher`, and the integration test
    does it end to end through the `.so` and the `CoreEvent` stream.
- [x] Assert no external-change modal is shown.
  - At the level each test can reach: no `FileChangedOnDisk` reaches Dart, which is
    the only thing `handleExternalChange` — and therefore the modal — runs from.
- [x] Assert unsaved new typing remains intact.
- [x] Deliver a genuine later external modification.
- [x] Assert the real external-change path still runs.
- [x] Test multiple watcher events from one atomic rename sequence.
  - As repeated `is_echo` calls, since a real filesystem cannot be made to emit a
    second event on demand. That is exactly what a second event does.
- [x] Test generation cleanup.
  - `a_write_cannot_finish_or_abandon_a_later_writes_record`,
    `an_abandoned_write_suppresses_nothing`,
    `the_event_that_did_not_match_clears_the_record`,
    `closing_a_script_forgets_what_we_wrote_there`,
    `save_as_suppresses_the_new_path_and_forgets_the_old_one`.

### Exit conditions

- [x] Own saves never trigger the external-change prompt.
- [x] Genuine external writes are still detected.
- [x] Interval autosave remains unchanged.

### Implementation log — Phase 4B

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** Claude Opus 5 (Claude Code)
**Starting commit:** `954b25e` (Phase 4A′)
**Ending commit:** this commit

#### Changes made

- `crates/storage/src/watch.rs`: `OwnWrites`, the register of writes this process
  made itself, with the four-step lifecycle documented on the type; a
  `Fingerprint` of device, inode, length and nanosecond mtime; `FileWatcher::new`
  now takes the register and filters with it, and `unwatch` forgets the path.
- `crates/bridge/src/state.rs`: `Storage::own_writes`, held beside the watcher
  rather than inside it because a build with no inotify still writes files;
  `AppState::close` forgets the path it is letting go of.
- `crates/bridge/src/api/files.rs`: `init` creates the register and hands it to
  the watcher; `write_document` and `backup_restore` bracket their writes with a
  small `OwnWrite` helper whose `abandoned` matters as much as its `finished`;
  `rebind` forgets the path a Save As has left.
- `docs/DECISIONS.md`: ADR 0028, refining ADR 0024 rather than editing it.
- `SPEC.md` §Phase 4: "The prompt never fires for our own save" ticked, with the
  mechanism and the tests that hold it.
- No bridge signature changed, so no binding regeneration. No dependency added.
  No Dart application code changed at all — the event simply stops arriving.

#### Tests added or changed

Ten in `crates/storage/src/watch.rs`, six in `crates/bridge/src/api/files.rs`, one
in `app/integration_test/persistence_test.dart`. All seventeen are named in
ADR 0028.

#### Commands run

```text
cargo fmt --all --check                                       # clean
cargo clippy --workspace --all-targets -- -D warnings         # clean
cargo test --workspace                                        # 370 passed, 0 failed
python3 tools/check_layering.py                               # clean, 7 crates
cd app && flutter analyze                                     # No issues found
cd app && flutter test                                        # 284 passed
cd app && flutter build linux --release                       # succeeds

flutter test integration_test/persistence_test.dart         -d linux   # 13 passed
flutter test integration_test/bridge_test.dart              -d linux   # 4 passed
flutter test integration_test/editor_test.dart              -d linux   # 7 passed
flutter test integration_test/writing_test.dart             -d linux   # 11 passed
flutter test integration_test/ime_test.dart                 -d linux   # 9 passed
flutter test integration_test/keystroke_benchmark_test.dart -d linux   # 2 passed

# Negative controls, run before trusting any of the above:
#   `is_echo` stubbed to false      → 11 tests fail, the integration test
#                                     among them, against the real .so
#   the bracket moved to after the write (ADR 0024's literal sequence)
#                                   → a_save_still_at_the_disk_already_
#                                     suppresses_its_own_event fails
```

#### Results

Rust 354 → 370. Flutter unit tests unchanged at 284, which is the honest number:
nothing in Dart changed, because the repair is that an event stops being sent.
The integration suite is 45 → 46.

#### Deviations from plan

**The audit's sketch was refined in two places, and both were proved rather than
argued.** ADR 0024 said "recorded after successful write" and "swallow the first
matching watcher event". Neither survived contact with a real filesystem:

- Recording after the write loses the race to the event it is meant to catch.
  `notify` delivers from its own thread while `save_atomically` is still
  returning, and step three is an actor round trip away. The bracket is therefore
  opened *before* the write; an event arriving inside it is either our own rename
  or a write our rename is about to overwrite. The control:
  `a_save_still_at_the_disk_already_suppresses_its_own_event` fails against the
  literal sequence.
- "The first matching event" assumes one event per rename, which is the very
  assumption the next task in this phase says not to make. Suppression is keyed on
  the file's identity instead, so a filesystem reporting one save as four events
  gets four consistent answers.

ADR 0028 records both, refining ADR 0024 rather than editing it, per the rule in
`AGENTS.md`.

**The filtering lives inside `FileWatcher` rather than in the bridge's callback.**
`watch.rs`'s header says the module does not decide whether to reload or ask, and
that is still true — it now decides only whether a change was *ours*, which is a
question about the filesystem rather than about the document. The gain is that
the composition under test is the composition that ships: the bridge cannot
assemble the filter differently from the way `watch.rs`'s own tests do.

**The Dart-side test is an integration test, not a widget test.** A widget test
would have to fake the event to assert the modal does not open, which asserts
that a fake was not sent. The real proof needs a real rename producing a real
inotify event, and its second half — a genuine external write that must still get
through — is what stops the first half passing on a machine where the watcher
never fires at all.

#### New risks or follow-up findings

- **A save whose file cannot be `stat`ed drops its record** rather than keeping an
  in-flight one, so its echo is reported and the writer may see one spurious
  prompt. That is the safe direction (the backstop then compares the file and
  usually finds it in step), and it is the only reachable case where F4 survives.
- Phase 4C now has a second reason to exist: `doc_external_change` still reads the
  disk and serialises the whole document on the actor thread, and suppression has
  made that path rarer without making it cheaper.
- The `Degraded` recovery note carried since Phase 1 is still open. Phase 4B
  touched no dialog, so it stays open for whoever next works on that surface.

---

## Phase 4C — Move external-change I/O off the actor

### Tasks

- [x] Convert `doc_external_change` from synchronous actor-blocking behavior to an asynchronous split operation.
- [x] On actor:
  - snapshot path;
  - snapshot dirty state;
  - snapshot current serialised/revision information needed for comparison.
- [x] Off actor:
  - read disk;
  - compare contents/checksum;
  - perform any potentially slow work.
- [x] Back on actor:
  - validate the result is not stale;
  - return the appropriate action/refusal.
- [x] Avoid a full serialisation on the actor when a revision hash or prepared snapshot can serve.
  - `Document::serialisation_snapshot` copies only immutable serialisation inputs; Fountain
    serialisation itself runs on the FRB worker. The original source remains shared by `Arc`.
- [x] Handle file missing, unreadable, replaced, or encoding-error cases.
  - All remain refusals (`None`), including a path replaced by a directory and non-UTF-8 bytes.
- [x] Ensure a stale async result cannot overwrite newer state.
  - `Session::document_generation` advances on edits, undo/redo, reload and backup restore.
    The final actor pass validates generation, path and dirty state. Automatic reload is also
    guarded by `only_if_clean`, so typing between the check and reload cannot be discarded.

### Tests

- [x] Slow disk-read simulation does not block edits queued to the actor.
- [x] Result is discarded or revalidated if the document changes during the async check.
- [x] Missing file behavior remains correct.
- [x] Dirty and clean document paths remain correct.
- [x] Own-save suppression and external comparison work together.

### Exit conditions

- [x] No disk read occurs inside the actor closure for external-change checks.
- [x] No large serialisation blocks the actor in this path.
- [x] External-change behavior remains correct under races.

## Phase 4 overall exit conditions

- [x] Save concurrency regression test passes.
- [x] Own-save echo regression test passes.
- [x] Actor-thread responsiveness test passes.
- [x] All existing persistence and save tests pass.
- [x] No autosave safety behavior was weakened.

## Suggested commit boundaries

- [x] `fix(storage): serialize saves per document session`
- [x] `fix(storage): suppress watcher events from own saves`
- [x] `refactor(storage): move external-change IO off actor`

### Implementation log — Phase 4C

**Started:** 2026-07-25
**Completed:** 2026-07-25
**Primary implementer/agent:** OpenAI GPT-5.6 Sol (OpenCode)
**Starting commit:** `8defd10` (`fix(storage): suppress watcher events from own saves`)
**Ending commit:** working tree

#### Changes made

- `doc_external_change` is now an asynchronous three-step operation: actor snapshot, worker
  serialisation/read/compare, actor validation. Its Dart surface is consequently a `Future`.
- `document` exposes `SerialisationSnapshot`, which carries no history or live `Document` and
  serialises through the same `serialise_parts` implementation as `Document::serialise`.
- `Session::document_generation` is monotonic across edits, undo/redo and document replacement,
  so a worker answer cannot mistake a reloaded document or an undone revision for its snapshot.
- The comparison holds the per-session save claim and `EditorPage` suppresses autosave through
  the complete check and decision. Explicit saves await the same decision barrier, so neither a
  timer nor Ctrl+S can overwrite the external version before the writer chooses.
- Automatic clean-document reload now uses `only_if_clean` and validates generation and path
  after its own disk read. Reload also takes the session's save claim, so an older save cannot
  land afterward. Explicit “Take theirs” retains its deliberate discard semantics.
- Regenerated the Rust and Dart FRB bindings with `flutter_rust_bridge_codegen generate`.

#### Tests added or changed

- `a_slow_external_change_read_does_not_block_an_edit_and_revalidates` holds the worker read,
  proves a real edit still completes on the actor, then proves the old answer is recomputed.
- Added clean, dirty, matching-content, missing, unreadable, non-UTF-8 and guarded-reload cases.
- Added a save-versus-reload interleaving test proving reload waits for a save already at disk.
- Added core and widget regressions proving no save passes a pending comparison and an autosave
  or Ctrl+S due during the check remains owed until the writer resolves the conflict.
- Added a document test proving a serialisation snapshot remains the revision it captured.
- Updated the fake core, widget test and real persistence integration test for the async API.

#### Commands run

```text
cargo fmt --all --check                                # clean
cargo clippy --workspace --all-targets -- -D warnings  # clean
cargo test --workspace                                 # 377 passed
python3 tools/check_layering.py                         # clean
cd app && flutter analyze                              # No issues found
cd app && flutter test                                 # 285 passed
cd app && flutter build linux --release                # succeeds
cd app && flutter test integration_test/persistence_test.dart -d linux
                                                        # 13 passed
```

#### Results

F8 is closed: neither the disk read nor Fountain serialisation runs in an actor closure, edits
remain responsive during a stalled read, and every state-changing race returns a refusal rather
than applying or acting on stale state. Phase 4's save ordering, journal and own-write suppression
tests remain green. No dependency or ADR was added; this implements the existing §2.3 rule rather
than changing an architectural decision.

---

# Phase 5 — Restore persisted scroll position

**Audit findings:** F6  
**Priority:** Medium stabilization

## Objective

When reopening a script, apply the persisted `scrollRow` to the editor viewport after layout is available.

## Tasks

- [x] Trace `ScriptView.scrollRow` from bridge response to `_openPath`.
- [x] Add an initial scroll row parameter to the editor/controller/surface boundary.
- [x] Apply the initial position only after the first valid layout extent exists.
- [x] Convert row to offset using the correct line height and viewport model.
- [x] Clamp to the current maximum scroll extent.
- [x] Handle files that changed and now contain fewer rows.
- [x] Avoid overwriting the restored position with an automatic focus/caret scroll.
- [x] Ensure a new untitled document starts at row 0.
- [x] Ensure subsequent user scrolling continues to persist as before.
- [x] Avoid repeated jump-to-initial-row during rebuilds.

## Tests

- [x] Persist a nonzero row.
- [x] Reopen the script.
- [x] Assert the viewport begins at the restored row.
- [x] Test row beyond new document extent clamps safely.
- [x] Test row 0.
- [x] Test initial focus does not immediately reset the restored position.
- [x] Test restoration occurs once.

## Documentation

- [x] Mark the Phase 4 scroll-position requirement complete only after the application test passes.
- [x] Update any comment that currently implies persistence alone is restoration.

## Exit conditions

- [x] Restored scripts visibly reopen near the saved row.
- [x] Widget/integration regression test passes.
- [x] Existing scrolling performance and persistence tests pass.

## Suggested commit boundary

- [ ] `fix(editor): apply persisted scroll position on reopen`

## Implementation log — Phase 5

**Started:** 2026-07-26

**Completed:** 2026-07-26

**Primary implementer/agent:** OpenAI GPT-5.6 Sol (OpenCode)

**Starting commit:** `0ba2095`

**Ending commit:** working tree

### Changes made

- `app.dart` now carries the restored `ScriptView.scrollRow` through document
  adoption instead of discarding it after reading the path. Recovery, library
  opens and newly created documents keep the row-zero default.
- `EditorPage` passes the initial row to `EditorSurface`. The surface waits until
  its `ScrollPosition` has content dimensions, converts the visual row through
  the existing padding and line-height model, clamps it to the current extent,
  and applies it once.
- Caret visibility is held until restoration completes, and the clamped row is
  reported through the existing persistence callback. No bridge API, generated
  binding, dependency or editor layout contract changed.
- `SPEC.md` now marks the Phase 4 session-scroll requirement complete and names
  the tests that prove both persistence and restoration.

### Tests added or changed

- Added `scroll_restore_test.dart`: nonzero row, row zero, initial focus,
  shortened-document clamping, clamped-row reporting, one-shot restoration and
  subsequent user scrolling.
- Extended `integration_test/persistence_test.dart` to persist row 42 through the
  real bridge, start `SluglineApp`, reopen the session and inspect the actual
  editor viewport.

### Commands run

```text
cd app && flutter analyze                                      # clean
cd app && flutter test                                         # 289 passed
cd app && flutter test test/editor/scroll_restore_test.dart    # 4 passed
cd app && flutter test integration_test/persistence_test.dart -d linux
                                                               # 14 passed
cd app && flutter test integration_test/keystroke_benchmark_test.dart -d linux
                                                               # 2 passed
cargo fmt --all --check                                        # clean
cargo clippy --workspace --all-targets -- -D warnings          # clean
cargo test --workspace                                         # 377 passed
python3 tools/check_layering.py                                 # clean
```

### Results

F6 is closed: the value persisted by `doc_set_scroll` is now consumed by the
application and applied only after the viewport can clamp it correctly. The
120-page benchmark remained inside every budget: 1.42 ms keystroke-to-patch p99,
6.33 ms frame-build p99, 1.66 ms journalled-keystroke p99, and no frame over
16 ms.

### Deviations from plan

None. No ADR was added because this completes behavior already specified by
Phase 4 rather than changing an architectural decision.

---

# Phase 6 — Layout convergence and bridge integration

**Audit findings:** F3, F10, related F1 divergences  
**Priority:** Architecture gate for Phase 7  
**Must complete before:** any preview/PDF implementation

## Locked decisions

- The editor remains fluid and unpaginated for 1.0.
- Dart remains the hot-path editor wrapping implementation.
- Rust remains the authoritative pagination implementation.
- Shared line-breaking behavior must be enforced by differential testing.
- Preview and PDF will consume the same Rust `PaginatedScript`.
- Page count is computed after successful saves from a background snapshot.
- Emphasis markers remain literal in the editor and count as columns.

## Objective

Eliminate accidental layout drift, expose Rust pagination through the bridge, and prove the engine works in the application architecture before Phase 7 depends on it.

---

## Phase 6A — Define the shared line-breaking contract

- [ ] Write a concise shared contract covering:
  - character/counting unit;
  - hard newline behavior;
  - tab expansion;
  - space-run consumption at wrap points;
  - trailing spaces;
  - empty lines;
  - wrap offsets;
  - Unicode and astral-plane text;
  - uppercase display transformation;
  - emphasis-marker column counting.
- [ ] State explicitly which behavior must match between Dart editor wrapping and Rust `break_lines`.
- [ ] State which behavior may differ because the editor is fluid and pagination has page-level rules.
- [ ] Record the contract in an ADR or dedicated layout contract document.

---

## Phase 6B — Resolve known Dart/Rust divergences

### Counting units

- [ ] Determine the authoritative unit for wrap columns.
- [ ] Align Dart and Rust behavior for astral-plane characters.
- [ ] Ensure caret safety still uses grapheme boundaries where required.
- [ ] Add emoji/non-BMP regression cases.

### Space runs

- [ ] Make Dart consume spaces at wrap boundaries the same way Rust does.
- [ ] Add repeated-space cases.
- [ ] Verify source offsets remain correct even when display spaces are skipped.

### Trailing spaces

- [ ] Eliminate the Dart phantom empty line at a width boundary.
- [ ] Add `wrapText("abc ", 3)` or equivalent regression coverage.
- [ ] Test several trailing-space lengths.

### Tabs

- [ ] Match Rust 4-column tab stops.
- [ ] Test tabs at columns 0, 1, 3, 4, and near wrap boundaries.
- [ ] Confirm caret/click mapping remains model-offset based.

### Hard newlines

- [ ] Confirm Phase 2 semantics match Rust.
- [ ] Include hard-newline cases in the shared test corpus.

### Uppercasing

- [ ] Resolve editor vs paginator behavior for length-changing uppercase such as `ß`.
- [ ] Prefer one explicit specification rather than accidental behavior.
- [ ] Preserve caret/model offset correctness in the editor.
- [ ] Add scene-heading and transition cases with Unicode.
- [ ] Record the decision in the layout contract.

---

## Phase 6C — Build a corpus-wide differential test

- [ ] Choose a maintainable comparison mechanism:
  - expose Rust wrap results through a test-only bridge;
  - generate fixtures from Rust and consume them in Dart tests; or
  - run a cross-language integration test.
- [ ] Compare wrap boundaries, not just rendered strings.
- [ ] Run over:
  - every block in `testdata` corpus;
  - generated edge cases;
  - multi-line blocks;
  - Unicode;
  - tabs;
  - repeated/trailing spaces;
  - empty text;
  - extreme widths.
- [ ] Make failures print:
  - source block;
  - width;
  - Dart boundaries;
  - Rust boundaries;
  - first mismatch.
- [ ] Add the differential test to CI.
- [ ] Avoid brittle comparisons of unrelated page-level pagination decisions.

## Exit condition for 6C

- [ ] Dart and Rust agree for the defined shared line-break contract across the complete corpus.

---

## Phase 6D — Expose pagination through the bridge

### Rust dependency and API

- [ ] Add the `slugline_layout` dependency to `crates/bridge`.
- [ ] Define bridge DTOs for the minimum required pagination result.
- [ ] Avoid leaking unstable internal layout types unnecessarily.
- [ ] Include:
  - page count;
  - pages;
  - placed visual elements/lines needed by future preview;
  - source/block identity;
  - debug representation or diagnostic data as appropriate.
- [ ] Ensure offsets and identities remain unambiguous.

### Async snapshot job

- [ ] Snapshot the document/revision on the actor.
- [ ] Run pagination off the actor on a worker thread.
- [ ] Return or commit results only if they correspond to the intended revision.
- [ ] Define cancellation or stale-result behavior.
- [ ] Ensure rapid saves do not create unbounded pagination work.
- [ ] Exercise the incremental pagination path outside crate-local tests if that path is intended for application use.
- [ ] Add bridge tests for normal, empty, long, and malformed-tolerated documents.

### Generated bindings

- [ ] Regenerate Flutter Rust Bridge bindings through the normal command.
- [ ] Do not manually edit generated files.
- [ ] Verify generated code is included only where expected.

---

## Phase 6E — Update library page count after save

- [ ] Trigger background pagination after every successful explicit save.
- [ ] Trigger it after every successful autosave.
- [ ] Use the saved document snapshot, not live mutable state.
- [ ] Store page count in the library entry as best-effort cache data.
- [ ] Do not paginate every file during library scan.
- [ ] Do not recompute on every keystroke.
- [ ] Ensure stale pagination results cannot replace a newer page count.
- [ ] Define behavior when pagination fails:
  - save still succeeds;
  - page count remains previous/unknown;
  - error is logged or surfaced appropriately.
- [ ] Display no page count for entries never processed by a layout-capable build, preserving current intended UX.

### Tests

- [ ] Save causes page count update.
- [ ] Autosave causes page count update.
- [ ] Pagination failure does not fail the save.
- [ ] Older pagination result cannot overwrite newer result.
- [ ] Library scan does not eagerly paginate all scripts.
- [ ] Page count survives restart.

---

## Phase 6F — Add a debug pagination surface

- [ ] Add a development-only or feature-flagged way to request/view pagination debug output.
- [ ] Ensure it consumes the bridge pagination result rather than reimplementing layout in Dart.
- [ ] Include enough information to inspect:
  - page boundaries;
  - block placement;
  - split elements;
  - continuation markers;
  - fixed-point iterations if relevant.
- [ ] Keep it clearly separate from the Phase 7 polished preview.
- [ ] Add at least one integration test proving application-level pagination invocation works.

---

## Phase 6G — Focused paginator review

Per D-6:

- [ ] Perform a focused code review of the back half of `crates/layout/src/engine.rs`.
- [ ] Trace every page-break rule against the spec.
- [ ] Verify:
  - orphan prevention;
  - dialogue splitting;
  - continued dialogue;
  - scene-heading handling;
  - action splitting;
  - fixed-point cap behavior;
  - A4 derivation;
  - deterministic ordering;
  - source identity preservation.
- [ ] Review golden tests for coverage rather than only pass status.
- [ ] Add any missing rule-level tests discovered.
- [ ] Do not rewrite the paginator absent concrete defects.

## Phase 6 exit conditions — Phase 7 gate

- [ ] Shared line-breaking contract is documented.
- [ ] Five known Dart/Rust divergences are resolved.
- [ ] Corpus-wide differential test passes in CI.
- [ ] Bridge depends on and invokes `slugline_layout`.
- [ ] Pagination runs asynchronously from a document snapshot.
- [ ] Page count updates after successful saves.
- [ ] Debug pagination output is reachable through the app or integration harness.
- [ ] Focused paginator review is recorded.
- [ ] No editor per-keystroke bridge round trip was introduced.
- [ ] No preview or PDF feature work has started prematurely.

## Suggested commit boundaries

- [ ] `fix(layout): align Dart wrapping with Rust contract`
- [ ] `test(layout): add corpus-wide Dart Rust differential coverage`
- [ ] `feat(bridge): expose async pagination snapshots`
- [ ] `feat(library): update page counts after successful saves`
- [ ] `chore(layout): add debug pagination view and focused review notes`

---

# Phase 7 — Separate Fountain export from Save As

**Audit findings:** F9  
**Priority:** Required before Phase 7 export UI

## Objective

Provide two distinct operations:

- **Save As:** write to a new path and rebind the active session.
- **Export Fountain Copy:** write a copy without changing the active document path, journal binding, library identity, or editing session.

## Tasks

### API semantics

- [ ] Rename or clarify any API that conflates the two operations.
- [ ] Implement `doc_export_fountain` as a true copy operation.
- [ ] Ensure export:
  - serialises the current document;
  - writes atomically;
  - does not mark the document saved unless the product specification explicitly says it should;
  - does not change active path;
  - does not restart/rebind journal;
  - does not alter library identity;
  - does not change watcher subscription;
  - does not affect recent-file/session restoration binding.
- [ ] Ensure Save As retains its existing rebinding semantics.

### Tests

- [ ] Save As changes active path.
- [ ] Save As rebinds journal and watcher.
- [ ] Export writes the expected bytes.
- [ ] Export leaves active path unchanged.
- [ ] Export leaves journal base/binding unchanged.
- [ ] Export leaves dirty state unchanged according to the chosen specification.
- [ ] Export failure does not alter session state.
- [ ] Exporting over an existing file uses the correct confirmation/refusal flow.

### Documentation

- [ ] Update bridge API docs.
- [ ] Update SPEC terminology if ambiguous.
- [ ] Ensure future Phase 7 dialogs call the correct operation.

## Exit conditions

- [ ] Export Copy and Save As have distinct tested semantics.
- [ ] No Phase 7 dialog can accidentally rebind the user’s session when exporting.

## Suggested commit boundary

- [ ] `feat(storage): separate Fountain export copy from Save As`

---

# Phase 8 — Defensive robustness cleanup

**Audit findings:** F11 and selected F12  
**Priority:** Low, bounded cleanup  
**Rule:** no broad refactor

## Objective

Harden cheap failure points without distracting from architectural work.

## Tasks

### Character normalization

- [ ] Refactor `normalize_character` to avoid slicing one string using lengths derived from another transformed string.
- [ ] Use a safe case-insensitive suffix check.
- [ ] Avoid repeated `to_uppercase()` inside the loop.
- [ ] Add Unicode and suffix-edge tests.
- [ ] Ensure no char-boundary panic is possible.

### Duplicate close

- [ ] Remove the duplicate core close in `_OpenScript.dispose()` or make ownership explicit.
- [ ] Add/retain idempotency only where genuinely required.
- [ ] Verify one session produces one close side effect.

### Unknown block IDs

- [ ] Replace `_indexOf` fallback-to-zero behavior.
- [ ] Choose a safe behavior:
  - assertion plus refusal in debug/release;
  - nullable result handled by caller;
  - explicit controlled resync.
- [ ] Ensure stale IDs can never redirect edits to block 0.
- [ ] Add a regression test.

### Entity frequency underflow

- [ ] Replace unchecked decrement with a guarded invariant.
- [ ] Decide whether index desynchronization should:
  - return an error;
  - rebuild the index;
  - assert in debug and recover in release.
- [ ] Add an invariant test.

### Word motion

- [ ] Decide whether astral-plane letter word motion must be fixed now or deferred.
- [ ] If fixed, classify by Unicode scalar/grapheme rather than UTF-16 surrogate halves.
- [ ] Add non-BMP letter tests.
- [ ] If deferred, record it as cosmetic debt.

### Phase 0 handshake/spike cleanup tracking

- [ ] Add explicit Phase 11 cleanup tasks for:
  - `handshake.rs`;
  - `proofEvents`;
  - `spike/`;
  - production binary surface verification.
- [ ] Do not remove them before the IME gate if existing ADRs prohibit it.

## Exit conditions

- [ ] Cheap panic/corruption footguns are removed.
- [ ] No broad architectural rewrite occurred.
- [ ] Deferred cosmetic items are explicitly tracked.

## Suggested commit boundary

- [ ] `chore: harden low-risk editor and entity invariants`

---

# Phase 9 — Manual platform gates

**Audit hidden risks:** real `ibus` + CJK, Orca, app-level behavior  
**Priority:** Must perform before declaring stabilization complete

## Objective

Verify important behavior that automated tests do not establish.

---

## Phase 9A — Linux IME gate

### Environment

- [ ] Record Linux distribution and desktop/session.
- [ ] Record Flutter version.
- [ ] Record input method framework and version.
- [ ] Configure real `ibus`.
- [ ] Install at least one CJK input method.

### Test matrix

- [ ] Start composition.
- [ ] Update composition repeatedly.
- [ ] Commit composition.
- [ ] Cancel composition.
- [ ] Replace selected text using IME.
- [ ] Compose at beginning, middle, and end of a block.
- [ ] Compose across text containing emoji/non-BMP characters.
- [ ] Compose near soft wrap.
- [ ] Compose after a hard newline inside a block.
- [ ] Undo and redo committed IME text.
- [ ] Save, close, and reopen committed IME text.
- [ ] Crash/recover committed IME text if practical.
- [ ] Confirm caret and selection do not corrupt model offsets.
- [ ] Confirm no duplicate commit occurs.
- [ ] Confirm autocomplete does not incorrectly accept during composition.

### Result

- [ ] Record pass/fail with exact reproduction steps.
- [ ] If failed, evaluate the ADR 0005 fallback before further major editor investment.
- [ ] Do not mark the gate complete based only on `ime_test.dart`.

---

## Phase 9B — Accessibility smoke test

- [ ] Run the app with Orca.
- [ ] Verify document/editor role is announced.
- [ ] Verify focused text and caret movement are meaningful.
- [ ] Verify selection changes are announced reasonably.
- [ ] Verify dialogs and recovery prompts are reachable.
- [ ] Verify library script selection is navigable.
- [ ] Record limitations without expanding remediation into a full accessibility phase unless a blocker is found.

---

## Phase 9C — End-to-end editing smoke test

Using `reference-feature.fountain`:

- [ ] Open the script.
- [ ] Navigate through multi-line action and dialogue.
- [ ] Type, delete, undo, and redo.
- [ ] Use keyboard screenplay workflow.
- [ ] Trigger autocomplete and explicitly accept.
- [ ] Save while continuously typing.
- [ ] Confirm no self-save external-change prompt.
- [ ] Close and reopen.
- [ ] Confirm scroll restoration.
- [ ] Confirm page count appears after save.
- [ ] Trigger crash recovery scenario.
- [ ] Accept recovery and confirm second-crash durability with a manual spot check.
- [ ] Export a Fountain copy and confirm active path remains unchanged.

## Exit conditions

- [ ] IME gate is passed or a blocking failure is explicitly escalated.
- [ ] Accessibility smoke test is recorded.
- [ ] End-to-end editing smoke test passes.
- [ ] Manual results are linked from the remediation record.

---

# Phase 10 — Final verification and remediation closeout

## Objective

Prove the repaired codebase is stable, documented, and ready to begin Phase 7.

## Full automated verification

- [ ] `cargo fmt --check`
- [ ] `cargo clippy --workspace --all-targets -- -D warnings`
- [ ] `cargo test --workspace`
- [ ] `tools/check_layering.py`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Build release `.so`.
- [ ] Run all six intended integration tests.
- [ ] Run the real ENOSPC/full-disk CI path locally if supported.
- [ ] Run corpus-wide Dart/Rust differential layout test.
- [ ] Run pagination bridge integration tests.
- [ ] Run recovery double-crash regression tests.
- [ ] Run save concurrency and watcher-echo regression tests.
- [ ] Run scroll restoration test.
- [ ] Run export-copy semantics tests.
- [ ] Run keystroke benchmark and compare to baseline.

## Audit finding closure table

- [x] F1 — multi-line blocks fixed and verified.
- [ ] F2 — recovery durability fixed and verified.
- [ ] F3 — layout contract, differential test, and bridge integration complete.
- [ ] F4 — own-save watcher events suppressed.
- [ ] F5 — saves serialized/coalesced safely.
- [ ] F6 — scroll restored.
- [x] F7 — docs, ADRs, SPEC, and CI synchronized.
- [ ] F8 — external-change I/O moved off actor.
- [ ] F9 — export copy separated from Save As.
- [ ] F10 — uppercase rule resolved and tested.
- [ ] F11 — character normalization hardened.
- [ ] F12 — selected defensive items fixed or explicitly deferred.
- [ ] F13 — the completion popup no longer swallows Enter.
- [ ] F14 — Escape closes the command palette, or the harness artifact is documented.

## Regression review

- [ ] Confirm no healthy subsystem was unnecessarily rewritten.
- [ ] Review diff size by subsystem.
- [ ] Check for accidental dependency-direction violations.
- [ ] Check generated files were regenerated, not hand-edited.
- [ ] Check no debug-only UI ships unintentionally.
- [ ] Check no new TODO hides required remediation.
- [ ] Check no test was weakened to make it pass.
- [ ] Check failures/refusals remain distinct and user-readable.
- [ ] Check no disk I/O was newly added to the actor thread.
- [ ] Check no full-document refetch was introduced on edit.

## Documentation closeout

- [ ] Mark remediation status complete.
- [ ] Update project phase status to “ready for Phase 7.”
- [ ] Link all new ADRs.
- [ ] Record final test counts.
- [ ] Record manual IME/accessibility results.
- [ ] Record known deferred low-priority debt.
- [ ] Keep `REVIEW.md` unchanged as the original audit record except for an optional link to this plan.

## Phase 7 authorization gate

Phase 7 may begin only when:

- [ ] Phases 1–7 of this remediation plan are complete.
- [ ] Phase 9 IME gate is complete or a conscious project-level exception is recorded.
- [ ] Phase 10 automated verification passes.
- [ ] Pagination is already integrated through the bridge.
- [ ] Preview and PDF work are required to consume the same `PaginatedScript`.
- [ ] The focused paginator review has been completed.
- [ ] There are no unresolved P0/High data-loss or editor-geometry defects.

## Suggested final commit

- [ ] `chore: complete mid-project remediation and open Phase 7 gate`

---

# Recommended execution order summary

1. [x] Phase 0 — Baseline and branch
2. [x] Phase 1 — Recovery durability
3. [x] Phase 2 — Multi-line editor correctness
3b. [x] Phase 2B — Keys swallowed by editor panels (F13, F14)
4. [x] Phase 3 — Documentation, ADRs, and CI
5. [x] Phase 4 — Save serialization, watcher suppression, async external checks
6. [x] Phase 5 — Scroll restoration
7. [ ] Phase 6 — Layout convergence and pagination bridge integration
8. [ ] Phase 7 — Export Copy vs Save As
9. [ ] Phase 8 — Defensive cleanup
10. [ ] Phase 9 — Manual platform gates
11. [ ] Phase 10 — Final verification and Phase 7 authorization

---

# Per-phase implementation log template

Copy this section beneath each phase while working.

## Implementation log — Phase N

**Started:**  
**Completed:**  
**Primary implementer/agent:**  
**Starting commit:**  
**Ending commit:**  

### Changes made

- 

### Tests added or changed

- 

### Commands run

```text

```

### Results

- 

### Deviations from plan

- 

### New risks or follow-up findings

- 

### Reviewer notes

- 

---

# Deferred backlog after remediation

These items are not blockers unless testing elevates them:

- [ ] Revisit multi-recovery UX only if multi-window or tabbed editing is added.
- [ ] Remove Phase 0 handshake/spike surfaces during Phase 11 cleanup, subject to ADR constraints.
- [ ] Revisit file chooser behavior per ADR 0015.
- [ ] Improve non-BMP word-motion granularity if left deferred.
- [ ] Perform full §5.5 print calibration during Phase 7.
- [ ] Expand Orca support beyond smoke-test level in the appropriate accessibility phase.
- [ ] Revisit emphasis styling only after 1.0; markers remain literal for now.

---

*End of remediation plan.*
