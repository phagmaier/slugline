# Slugline — Mid-Project Remediation Plan

**Source audit:** `REVIEW.md`  
**Audit baseline:** commit `16b6cff` (`phase 6`), branch `dev`  
**Purpose:** repair and stabilize the existing implementation before beginning Phase 7  
**Status:** in progress — Phases 0 and 1 complete, Phase 2 next

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
- [ ] Multi-line Fountain blocks render, wrap, select, click, and position the caret correctly.
- [ ] Enter splits the block whether or not a completion is offered, and Escape closes every panel.
- [ ] Dart and Rust line breaking agree on the defined shared behavior.
- [ ] Rust pagination is reachable through the bridge and exercised outside its isolated crate tests.
- [ ] The library page count is updated from a saved pagination snapshot.
- [ ] The application does not treat its own save as an external file modification.
- [ ] Overlapping saves for the same session cannot write out of order.
- [ ] External-change checks perform disk I/O off the actor thread.
- [ ] Persisted scroll position is applied when reopening a script.
- [ ] Fountain “Export Copy” semantics are separate from “Save As.”
- [ ] CI runs all intended integration tests and a real ENOSPC/full-disk test.
- [ ] README, AGENTS, SPEC, ADRs, and implementation status agree.
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

- [ ] Run `flutter run -d linux`.
- [ ] Open `testdata/reference-feature.fountain`.
- [ ] Navigate to known multi-line dialogue/action blocks.
- [ ] Capture a before screenshot or written observation.
- [ ] Verify whether:
  - text overlaps the following row;
  - caret placement is wrong after `\n`;
  - mouse clicks map to wrong offsets;
  - selection rectangles are wrong.
- [ ] If the reported defect cannot be reproduced, stop this phase and document the discrepancy before changing code.

### 2.2 Define hard-newline semantics

- [ ] Treat embedded `\n` as a mandatory visual line break.
- [ ] Match the Rust `break_lines` split-first behavior.
- [ ] Decide and document offset ownership at the newline:
  - visual line ending offset;
  - next line starting offset;
  - click behavior at line end;
  - caret affinity if applicable.
- [ ] Ensure the newline remains part of the model text and is not dropped.
- [ ] Ensure behavior is valid for:
  - leading newline;
  - trailing newline;
  - consecutive newlines;
  - empty visual lines;
  - newline adjacent to wrap boundary.

### 2.3 Repair `wrapText`

Likely area: `app/lib/editor/line_layout.dart`.

- [ ] Split the source text into hard-line segments before soft wrapping.
- [ ] Preserve source offsets across each segment.
- [ ] Represent empty hard lines explicitly.
- [ ] Do not count `\n` as a printable column.
- [ ] Ensure soft-wrap boundaries retain correct absolute offsets.
- [ ] Avoid producing phantom lines.
- [ ] Keep performance suitable for the keystroke path.

### 2.4 Repair `DocumentLayout`

- [ ] Map block-local offsets to the correct visual line after hard breaks.
- [ ] Map visual line/column positions back to the correct model offsets.
- [ ] Ensure incremental rewrap invalidates all affected visual lines.
- [ ] Ensure downstream row indexes update correctly when a block gains or loses hard lines.
- [ ] Preserve stable block identity and patch-in-place behavior.
- [ ] Confirm no full-document refetch was introduced.

### 2.5 Repair painting and geometry

Likely area: `editor_surface.dart`.

- [ ] Paint one visual line per grid row.
- [ ] Never pass a multi-line string to a one-row paint operation.
- [ ] Verify caret x/y after every embedded newline.
- [ ] Verify selection rectangles spanning hard and soft wraps.
- [ ] Verify click-to-offset mapping on every visual line.
- [ ] Verify drag selection across newline boundaries.
- [ ] Verify scrolling and visible-row calculation with extra visual rows.
- [ ] Verify semantics/accessibility text remains coherent.

### 2.6 Add regression tests

Unit tests:

- [ ] `"One.\nTwo."`
- [ ] `"One.\nTwo.\nThree."`
- [ ] `"\nTwo."`
- [ ] `"One.\n"`
- [ ] `"One.\n\nThree."`
- [ ] Hard newline plus soft wrap on both sides.
- [ ] Unicode before and after newline.
- [ ] Tabs and spaces near newline, anticipating Phase 6 alignment work.

Widget/geometry tests:

- [ ] Caret after newline.
- [ ] Caret at beginning of second hard line.
- [ ] Mouse click on second hard line.
- [ ] Selection across newline.
- [ ] Selection across hard newline plus soft wrap.
- [ ] Incremental edit inserts a newline.
- [ ] Incremental edit removes a newline.
- [ ] Opening the reference fixture produces non-overlapping visual rows.

### 2.7 Manual verification

- [ ] Reopen `reference-feature.fountain`.
- [ ] Capture an after screenshot or written observation.
- [ ] Verify typing, clicking, selecting, copying, and pasting in multi-line blocks.
- [ ] Verify no regression in single-line editor-authored blocks.
- [ ] Verify the keystroke benchmark remains within the existing budget.

## Exit conditions

- [ ] Embedded newlines are represented as mandatory visual breaks.
- [ ] Painting, caret, click mapping, and selection agree.
- [ ] Reference script no longer misrenders.
- [ ] New unit and widget tests pass.
- [ ] Existing editor and performance tests pass.
- [ ] No bridge round-trip was added to the per-keystroke wrap path.

## Suggested commit boundary

- [ ] `fix(editor): support hard newlines inside screenplay blocks`

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

- [ ] Confirm the four baseline failures still reproduce (`editor_test`, `writing_test`).
- [ ] Add a widget-level regression test that drives the editor with a *non-empty*
      `fake_core.completions`, so the stolen-Enter path is reachable without the `.so`.
- [ ] Confirm that test fails before the repair.

### 2B.2 Decide the acceptance gesture (F13)

- [ ] Decide what accepts a completion. `SPEC.md` §Phase 5 and the audit both describe
      acceptance as explicit; Tab is already wired to it.
- [ ] Decide whether Enter accepts at all, and if so only when the writer has moved the
      highlight off the default with the arrow keys.
- [ ] Stop the index from suggesting the block currently being typed — a scene heading
      offered as the sole completion for itself is never a useful suggestion.
- [ ] Record the decision as an ADR; it settles a §16 question the code answered silently.

### 2B.3 Repair the key routing

- [ ] Reorder or guard the `when _controller.completions.isNotEmpty` arms in
      `editor_surface.dart::_onKey` so Enter reaches `splitBlock()` under the decided rule.
- [ ] Verify Tab still accepts a completion, and still tabs when there is none.
- [ ] Verify Escape dismisses the popup without touching the document.
- [ ] Keep the popup's arrow-key handling.

### 2B.4 Root-cause and repair the palette Escape (F14)

- [ ] Determine whether Escape genuinely fails to leave the palette's focused `TextField`,
      or whether this is an artifact of the live integration binding's text-input connection.
- [ ] If it is a real defect, repair it in `command_palette.dart` and add a widget test.
- [ ] If it is a harness artifact, adjust `writing_test.dart` and say why in a comment —
      do not weaken the assertion.

### 2B.5 Audit the test double for other silent gaps

- [ ] Review `app/test/support/fake_core.dart` for defaults that are empty in the double and
      non-empty against the real core, and which therefore hide a branch.
- [ ] Note anything found; repair only what is cheap and in scope.

## Tests

- [ ] Enter splits the block while a completion is offered.
- [ ] The chosen acceptance gesture accepts the completion.
- [ ] The block being typed is not offered as its own completion.
- [ ] Escape closes the find bar, the palette, and then collapses the selection.
- [ ] `editor_test.dart` and `writing_test.dart` pass in full.

## Exit conditions

- [ ] All six integration tests pass locally.
- [ ] The acceptance gesture is specified in an ADR, not left to arm ordering.
- [ ] No regression in `flutter test` or the keystroke benchmark.

## Suggested commit boundary

- [ ] `fix(editor): stop the completion popup swallowing Enter`

---

# Phase 3 — Documentation, ADR, and CI truthfulness

**Audit findings:** F7 and test-gap #4  
**Priority:** High process integrity  
**Can overlap with:** Phases 1–2 only if done in a separate commit

## Objective

Restore documentation and CI as trustworthy descriptions of the project’s actual state.

## Tasks

### 3.1 Update project status documents

- [ ] Update `README.md` from Phase 1 status to the actual completed phase.
- [ ] Update `AGENTS.md` to reflect:
  - Phases 0–6 completed subject to this remediation;
  - `layout` is implemented but not yet fully integrated;
  - `render_pdf` and `spell` remain placeholders;
  - the actual integration tests run in CI.
- [ ] Update the project’s current-phase/progress section.
- [ ] Mark the remediation period as a stabilization gate before Phase 7.
- [ ] Remove or update stale comments pointing to already-completed phases.
- [ ] Correct the `document.rs` provenance re-anchoring comment or explicitly defer it.

### 3.2 Update SPEC invariant checklist

- [ ] Mark existing verified invariants accurately.
- [ ] Link or name the actual tests for:
  - byte-exact round trip;
  - parser never panics;
  - element change preserves text;
  - unsaved-change/recovery guarantees where applicable.
- [ ] Leave later-phase invariants unchecked.
- [ ] Add explicit remediation gates if the spec has a phase checklist section.
- [ ] Ensure no item is checked when only half implemented, such as scroll persistence without restoration.

### 3.3 Record decisions as ADRs

Create or update ADRs for:

- [ ] Fluid, unpaginated editor through 1.0.
- [ ] Dart editor wrapper retained but differentially pinned to Rust line breaking.
- [ ] Rust pagination exposed through the bridge as an asynchronous snapshot job.
- [ ] `page_count` updated after successful saves from a background pagination snapshot.
- [ ] Literal emphasis markers in the editor for 1.0.
- [ ] Pinned entity storage and ranking decision from Phase 5.
- [ ] Phase 6 checkpoint/fingerprint pagination design if not already documented.
- [ ] One recovery offer per launch remains acceptable for 1.0.
- [ ] Interval autosave remains active during continuous typing.
- [ ] The focused Phase 7 review requirement for the back half of `layout/engine.rs`.

Each ADR must include:

- [ ] Context.
- [ ] Decision.
- [ ] Alternatives considered.
- [ ] Consequences.
- [ ] Tests or invariants enforcing the decision.
- [ ] Status and date.

### 3.4 Close CI integration-test gaps

- [ ] Inspect current CI commands.
- [ ] Add `.so` build/setup before all bridge-dependent Flutter integration tests.
- [ ] Run:
  - `bridge_test`
  - `editor_test`
  - `keystroke_benchmark_test`
  - `writing_test`
  - `ime_test`
  - `persistence_test`
- [ ] Confirm `xvfb` or equivalent display setup is applied consistently.
- [ ] Ensure CI fails when any intended integration test fails.
- [ ] Update `AGENTS.md` to list exactly what CI runs.

### 3.5 Add real full-disk/ENOSPC CI coverage

- [ ] Identify the test using `SLUGLINE_FULL_DISK_DIR`.
- [ ] Mount or provision a deliberately small tmpfs in CI.
- [ ] Set `SLUGLINE_FULL_DISK_DIR` to that location.
- [ ] Confirm the test reaches a real full-disk condition rather than only fallback classification.
- [ ] Verify cleanup runs even after test failure.
- [ ] Document any CI-platform limitation.

### 3.6 Documentation verification

- [ ] Search for stale phase references.
- [ ] Search for “placeholder” claims about `layout`.
- [ ] Search for incorrect integration-test counts.
- [ ] Search for unresolved §16 decisions now settled by D-1 through D-5.
- [ ] Confirm docs do not claim F1/F2/F3 are fixed until their phases actually pass.

## Exit conditions

- [ ] README, AGENTS, SPEC, ADRs, and CI agree.
- [ ] Six intended integration tests gate CI.
- [ ] Real ENOSPC behavior is exercised in CI.
- [ ] No known checked specification item overstates implementation.
- [ ] Future coding agents receive accurate project context.

## Suggested commit boundaries

- [ ] `docs: synchronize phase status and architecture decisions`
- [ ] `ci: run full integration suite and real ENOSPC test`

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

- [ ] Identify every caller of `write_document`.
- [ ] Confirm overlap is possible between:
  - interval autosave;
  - idle autosave;
  - explicit Ctrl+S;
  - dialog-mediated save;
  - recovery-triggered save if introduced in Phase 1.
- [ ] Add per-session save coordination in `AppState` or the session object.
- [ ] Choose one behavior:
  - queue the latest requested save; or
  - reject/coalesce redundant overlapping saves and schedule the newest revision.
- [ ] Do not rely only on Dart-side `_saving`.
- [ ] Ensure two save plans for the same session cannot write in reverse order.
- [ ] Allow unrelated sessions to save independently if the architecture later supports them.
- [ ] Ensure save completion marks only the revision actually persisted.
- [ ] Ensure journals checkpoint against the bytes that actually won.
- [ ] Apply equivalent protection to concurrent `library_open` check-then-act behavior, or explicitly separate it into a follow-up task with a regression test.

### Tests

- [ ] Start save A.
- [ ] Edit the document.
- [ ] Start save B.
- [ ] Force A and B completion order to invert.
- [ ] Assert the file ends with the newest revision.
- [ ] Assert UI “Saved” status corresponds to durable bytes.
- [ ] Assert journal state matches the resulting file.
- [ ] Test explicit save overlapping autosave.
- [ ] Test duplicate concurrent library open if repaired here.

### Exit conditions

- [ ] Same-session saves are serialized or safely coalesced.
- [ ] No older save can overwrite a newer acknowledged save.
- [ ] Regression tests pass.

---

## Phase 4B — Suppress own-save watcher echoes

### Tasks

- [ ] Preserve interval autosave during continuous typing.
- [ ] Add an own-write correlation mechanism in the core.
- [ ] Use the audit decision:
  - path;
  - save generation counter;
  - recorded after successful write;
  - swallow the first matching watcher event for that generation.
- [ ] Define behavior for platforms that emit multiple filesystem events for one atomic save.
- [ ] Avoid suppressing a genuine external write that occurs immediately after the app’s save.
- [ ] Keep `doc_external_change` as the correctness backstop.
- [ ] Clear stale suppression records.
- [ ] Document the correlation lifecycle.

### Tests

- [ ] Save a file.
- [ ] Immediately type additional text.
- [ ] Deliver the watcher event caused by the app’s own save.
- [ ] Assert no external-change modal is shown.
- [ ] Assert unsaved new typing remains intact.
- [ ] Deliver a genuine later external modification.
- [ ] Assert the real external-change path still runs.
- [ ] Test multiple watcher events from one atomic rename sequence.
- [ ] Test generation cleanup.

### Exit conditions

- [ ] Own saves never trigger the external-change prompt.
- [ ] Genuine external writes are still detected.
- [ ] Interval autosave remains unchanged.

---

## Phase 4C — Move external-change I/O off the actor

### Tasks

- [ ] Convert `doc_external_change` from synchronous actor-blocking behavior to an asynchronous split operation.
- [ ] On actor:
  - snapshot path;
  - snapshot dirty state;
  - snapshot current serialised/revision information needed for comparison.
- [ ] Off actor:
  - read disk;
  - compare contents/checksum;
  - perform any potentially slow work.
- [ ] Back on actor:
  - validate the result is not stale;
  - return the appropriate action/refusal.
- [ ] Avoid a full serialisation on the actor when a revision hash or prepared snapshot can serve.
- [ ] Handle file missing, unreadable, replaced, or encoding-error cases.
- [ ] Ensure a stale async result cannot overwrite newer state.

### Tests

- [ ] Slow disk-read simulation does not block edits queued to the actor.
- [ ] Result is discarded or revalidated if the document changes during the async check.
- [ ] Missing file behavior remains correct.
- [ ] Dirty and clean document paths remain correct.
- [ ] Own-save suppression and external comparison work together.

### Exit conditions

- [ ] No disk read occurs inside the actor closure for external-change checks.
- [ ] No large serialisation blocks the actor in this path.
- [ ] External-change behavior remains correct under races.

## Phase 4 overall exit conditions

- [ ] Save concurrency regression test passes.
- [ ] Own-save echo regression test passes.
- [ ] Actor-thread responsiveness test passes.
- [ ] All existing persistence and save tests pass.
- [ ] No autosave safety behavior was weakened.

## Suggested commit boundaries

- [ ] `fix(storage): serialize saves per document session`
- [ ] `fix(storage): suppress watcher events from own saves`
- [ ] `refactor(storage): move external-change IO off actor`

---

# Phase 5 — Restore persisted scroll position

**Audit findings:** F6  
**Priority:** Medium stabilization

## Objective

When reopening a script, apply the persisted `scrollRow` to the editor viewport after layout is available.

## Tasks

- [ ] Trace `ScriptView.scrollRow` from bridge response to `_openPath`.
- [ ] Add an initial scroll row parameter to the editor/controller/surface boundary.
- [ ] Apply the initial position only after the first valid layout extent exists.
- [ ] Convert row to offset using the correct line height and viewport model.
- [ ] Clamp to the current maximum scroll extent.
- [ ] Handle files that changed and now contain fewer rows.
- [ ] Avoid overwriting the restored position with an automatic focus/caret scroll.
- [ ] Ensure a new untitled document starts at row 0.
- [ ] Ensure subsequent user scrolling continues to persist as before.
- [ ] Avoid repeated jump-to-initial-row during rebuilds.

## Tests

- [ ] Persist a nonzero row.
- [ ] Reopen the script.
- [ ] Assert the viewport begins at the restored row.
- [ ] Test row beyond new document extent clamps safely.
- [ ] Test row 0.
- [ ] Test initial focus does not immediately reset the restored position.
- [ ] Test restoration occurs once.

## Documentation

- [ ] Mark the Phase 4 scroll-position requirement complete only after the application test passes.
- [ ] Update any comment that currently implies persistence alone is restoration.

## Exit conditions

- [ ] Restored scripts visibly reopen near the saved row.
- [ ] Widget/integration regression test passes.
- [ ] Existing scrolling performance and persistence tests pass.

## Suggested commit boundary

- [ ] `fix(editor): apply persisted scroll position on reopen`

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

- [ ] F1 — multi-line blocks fixed and verified.
- [ ] F2 — recovery durability fixed and verified.
- [ ] F3 — layout contract, differential test, and bridge integration complete.
- [ ] F4 — own-save watcher events suppressed.
- [ ] F5 — saves serialized/coalesced safely.
- [ ] F6 — scroll restored.
- [ ] F7 — docs, ADRs, SPEC, and CI synchronized.
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
3. [ ] Phase 2 — Multi-line editor correctness
3b. [ ] Phase 2B — Keys swallowed by editor panels (F13, F14)
4. [ ] Phase 3 — Documentation, ADRs, and CI
5. [ ] Phase 4 — Save serialization, watcher suppression, async external checks
6. [ ] Phase 5 — Scroll restoration
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
