# Slugline Agent Guide

## Development workflow

**Policy updated 2026-10-09: focused checks by default; full suites at substantial
development boundaries; release work only at the very end.** Finishing a small
task, backlog item, commit or agent turn does not require a full suite, release
build or green hosted CI. This policy replaces older workflow instructions in
handoffs, task descriptions, skills and agent memory. Specific current user
requests take precedence.

1. Read the relevant scoped `AGENTS.md` and the requested backlog item, if any.
   Read only the contracts and ADRs that the change touches; do not tour all
   project documents, historical results or evidence directories on every task.
2. For a bug, reproduce it with the smallest useful test or observation before
   editing. For docs, maintenance and new features, establish the intended
   result directly. Identify the observable result and focused check before
   coding; a short internal plan is enough, with no new planning document.
3. Make the change. Run focused checks while iterating, then verify the affected
   behavior once when the change is ready. Batch edits before checking; do not
   rerun passing checks after unrelated prose or commit bookkeeping changes.
4. Record the outcome briefly and stop at the requested boundary. Routine
   completion needs no release work, exhaustive evidence report or CI watch.
   If the user requests a batch, complete that batch without stopping for
   permission between its items; keep each item's changes and status distinct.

Implementation and product choices are delegated to agents. Decide routine
questions without asking for sign-off. Ask only for necessary information that
cannot be established from the project or its sources. Run `tools/doctor.sh`
for setup or environment problems, not as a ritual before every task.

## Which documents govern

This file owns the development workflow and verification scope. Scoped guides
describe subsystem invariants and relevant checks, not extra completion gates.
`docs/BACKLOG.md`, `docs/DECISIONS.md`, `docs/BUDGETS.md`, `docs/KEYMAP.md`,
`docs/LINE_BREAKING.md` and `docs/DEPENDENCIES.md` govern their respective
contracts; consult them when relevant.

`docs/archive/SPEC.md` and `docs/archive/REVIEW.md` are **provenance, not
instructions** — frozen, partly false, their imperatives retired at 1.0.
Read them only when history matters. `README.md` and `CHANGELOG.md` are for
users. `docs/MANUAL_GATES.md` lists final checks requiring a real desktop;
agents cannot perform or fake them, and they do not block routine development.

## Backlog

Use `docs/BACKLOG.md` when asked to take backlog work: choose the first unblocked
item unless one is named. Keep unrelated work separate. A direct user request
does not need a new backlog item just to authorize or record it.

Done means the requested behavior/acceptance criteria are met, relevant checks
pass, and the diff has been reviewed for accidental or unrelated changes. Tick
an existing item's box and update its Result in the same working change. A
partially implemented or blocked item stays unticked with `_open_` in its Result
and a brief progress/blocker note. Non-reproduction alone is not completion;
an already-fixed item can close when its acceptance criteria are confirmed.
Unrelated failures and final release/manual gates do not prevent completion.

For an existing item, keep its `Result` to one to three sentences: what changed,
the relevant verification, and any material limitation or non-obvious choice.
Reference the commit hash or descriptive subject when committing; a subject is
enough, so do not make an extra commit just to insert a hash. Preserve historical
results and useful failure artifacts, but do not append every command, test
count, passing log or unchanged invariant.

Update docs only when their contract, user behavior or actionable state changes.
Add an ADR for a durable architectural decision or a change to an accepted
decision, not for routine fixes or workflow edits. Handoffs and separate evidence
documents are optional unless requested or needed to continue a complex blocked
investigation. A handoff should contain only unresolved work, reproduction and
useful artifact paths. Record actionable adjacent bugs briefly under "Found along
the way"; do not turn every observation into another tracked task.

## Commits

Keep each commit focused. For backlog work, lead the subject with the item's id,
for example `F3 — the preview renders emphasis instead of showing markers`.
A short body is useful when the reason or verification is not obvious. Do not
duplicate the same explanation in a commit, backlog essay and new evidence doc.
Keep commit/push status truthful and honor the requested push boundary. Never
force-push or rewrite published history.

When several agents work in the tree at once, each takes its own
worktree or branch named for its item (`w8-...`), one backlog item per
branch, and never ticks or rewrites another agent's item — record
out-of-scope findings under that item's "Found along the way" section
instead.

## Architecture

`docs/ARCHITECTURE.md` maps the layers and entry points. Each crate and `app/`
has a scoped `AGENTS.md` with its key files, invariants and relevant ADRs.
The API under `crates/bridge/src/api/` is the bridge surface's authority;
generated Dart lives in `app/lib/src/rust/`.

Rust owns document state, Fountain semantics, persistence, pagination, and PDF
output. Flutter owns input, caret/selection, scrolling, and widgets; Dart must
ask Rust for screenplay semantics rather than reimplementing them.

Workspace layers enforced by `python3 tools/check_layering.py`:
`fountain` has no workspace dependencies; `document -> fountain`; `fdx -> fountain`;
`layout -> document` and `-> fountain` (printed-width alignment, ADR 0044);
`render_pdf -> layout` and `-> fountain`;
`storage -> document`; `spell` has none; `bridge` may depend on all.
Update the workspace manifest and the script's tables together when adding a
workspace crate or allowed edge.

Every crate takes `version.workspace = true`; the release version lives in
`app/pubspec.yaml`. `python3 tools/check_version.py` fails if `Cargo.toml`,
the AppStream metainfo or the changelog disagrees.

Every bridge offset is a UTF-16 code-unit offset named `*_utf16`. Only
`crates/bridge/src/offsets.rs` may convert UTF-16 and UTF-8 offsets; invalid
boundaries return `None`, never rounded or clamped. Offsets inside `document`
are UTF-8 byte offsets and are named for it (ADR 0008).

## The editor

- `AppState` lives on one actor thread (`crates/bridge/src/actor.rs`); nothing
  else may hold a `Document`. Every bridge function hands the actor a closure.
  Long jobs — pagination, PDF export, the library scan — belong on a worker
  pool against a snapshot. A save is the pattern to copy: ask the actor for the
  bytes and the path, let go, write the file, come back to record what happened.
- **There is no timer anywhere in the core, and there must not be.** The actor
  thread blocks on its channel and wakes only when something happens. The
  autosave clock is Dart's (ADR 0014), and so is anything else that has to
  happen "in N seconds".
- The editor is one custom editing surface, not a widget per block (ADR 0005).
  `EditorController` owns the caret, the selection and the wrapped line
  geometry; every text change goes to the core as an `EditCommand` and comes
  back as a patch that is applied in place — never refetch the document (ADR
  0009).
- `ScreenplayMetrics` in `app/lib/editor/metrics.dart` owns the printed grid,
  including script size. Use its pinned `advanceRatio` and `fittedFontSize`;
  the text-size preference is a ceiling, not a pixel count. Never measure a
  font for its advance or hard-code script size. Script and platform-sans chrome
  typography stay separate in `app/lib/typography.dart`. Every row-to-pixel
  conversion goes through `EditorGeometry` in `page_geometry.dart`.
- Editor wrapping stays synchronous in Dart; no bridge round trip belongs on
  that keystroke path. Rust and Dart share `docs/LINE_BREAKING.md`, held by the
  differential test (ADR 0018). Change the contract on both sides together;
  deliberate fixture regeneration is described in `crates/layout/AGENTS.md`.
- `docs/KEYMAP.md` is the keyboard map, and `app/lib/editor/elements.dart` is
  the one table the shortcuts, the element selector and the command palette
  read. What a key *does* is Dart's; what an element is followed by is Rust's.
- Every edit that reaches the document goes through `outcome` or `inferring` in
  `crates/bridge/src/api/doc.rs`, and both append to the crash journal. A new
  mutation must end in one of them — never in a bare `document.apply`.
- **The editor never decides where a page ends.** The `page_view` preference
  draws sheets instead of one column, but both modes read `PageIndicator`'s
  `firstPage` and `pageStarts`, which are Rust's paginated snapshot re-expressed
  in editor rows. Before the first snapshot lands there is no first page and the
  surface draws a plain column — that is the correct answer, not a gap to fill
  with an estimate.
- A block's kind changes only through `SetKind`. Automatic re-classification
  goes through `Document::reinfer`, which the bridge calls after every edit;
  `Ctrl+K` and `Ctrl+F` open panels the editor page owns, so that Escape closes
  one with a `setState` and never reaches the document.
- Save preserves live pins and authored text/case, emitting forcing syntax only
  where native grammar/context requires it for canonical new/edited blocks.
  Reload takes its pin truth from the source; no hidden persisted pin cache
  or automatic stored capitals. Untouched provenance stays byte-exact (ADR 0059).
- Widget tests run without the `.so`, so they drive the editor through
  `DocumentCore` with the double in `app/test/support/fake_core.dart`. That
  double does list surgery only: anything that decides what a screenplay *is*
  goes in Rust and is tested with `cargo test` (ADR 0011).
- The runner stops the engine before process exit (ADR 0053).
  `my_application_shutdown` in `app/linux/runner/my_application.cc` disposes
  only the engine, joining its threads. Never replace it with window destruction
  or `_exit()`. Run `tools/check_clean_close.py` for runner/shutdown changes or
  Flutter upgrades, not unrelated editor work.

## Output — pagination, preview and PDF

- `crates/render_pdf` writes PDF bytes itself without external dependencies
  (ADR 0032). Its vendored fonts also serve the editor through `app/fonts/`
  symlinks. Font changes need deliberate golden/hash verification.
- **The renderer makes no layout decisions.** Every row and column comes from
  `crates/layout` and is copied; `Geometry` multiplies a grid cell by its size
  in points. Shared resolved emphasis is scanned before
  wrapping (ADR 0057); body scopes cross hard lines, title source hard lines
  resolve individually, and unpaired markers remain ordinary characters.
- Incremental pagination must equal full pagination, pages and checkpoints
  both (ADR 0049). Resume/stop only at recorded safe element boundaries; count
  beyond-element lookahead in `blocks_read`. Never reduce
  `crates/layout/tests/incremental_differential.rs` to page-count equality.
- **The preview and PDF share the paginated snapshot and resolved runs.**
  `app/lib/preview/preview_view.dart` paints Rust's runs and makes no layout
  or emphasis-parsing decision. Raw row content and source identity stay intact.
  Forced Character cues retain authored case in the editor, resolved output
  runs and continuation labels; ordinary cues and scene headings still display
  capitals. Rendering never changes stored text, kind or source offsets
  (ADR 0060).
  “Bold scene headings” is an output preference, off by default, followed by
  editor, preview and PDF. Both line breakers use printed-width source projections;
  editor paired markers stay dim and individually editable (ADR 0057).
- Page 1 is counted but unmarked by default (ADR 0048). Only the paginator
  turns “Number the first page” into a page-number line. Preview/PDF draw it;
  editor page view asks `PageIndicator.printsNumber`, never the preference.
- **An export is not a Save As** (ADR 0029). `doc_export_pdf` and
  `doc_export_fountain` both refuse `AlreadyExists` (retry with
  `overwrite: true`) and `ScriptIsOpen` (never retried). The export dialog
  shares `confirmReplace` with the save dialog.
- A title-page edit is journalled like any other edit (ADR 0033): `Patch`
  carries an optional title page, `doc_set_title_field` calls
  `outcome_with_title_page`, and undo records it unconditionally.

## Persistence

- `crates/storage` is where "losing user text is a P0 bug" is cashed out. Two
  rules hold across all of it: a write either happened or did not, and a read
  never fails on bad input. A corrupt journal, a truncated library index and a
  hand-mangled preferences file each yield what could be read.
- Every file this project writes goes through `atomic::save_atomically`,
  including the ones it writes about itself. The tests in
  `crates/bridge/tests/persistence.rs` hold it to it.
- The journal records the **outcome** of an edit (a `Patch`), never the command
  (ADR 0013). Replaying is list surgery with no inference in it. Appends are
  not `fsync`ed on purpose; do not "fix" that without reading the ADR.
- The library index, the session and the backups' bookkeeping are **caches**.
  Deleting any of them must cost nothing but convenience.
- **A quit parks the session; putting a script away ends it** (ADR 0064).
  `shutdown` leaves a script that is still open marked open in the index, with
  its row, and the next launch reopens it; `doc_close` marks it put away. Dart
  calls `shutdown` before it disposes the open script. `doc_set_scroll` is
  memory only — `session_park` writes the index when Dart's settle timer or a
  put-away says so, never per row.
- A journal file's *absence* is what says a session ended cleanly.
  `Journal::discard` removes it and nothing else may. `Journal::create` will
  not start a session over one that is already there. `Journal::replace` is the
  one door that overwrites, for the session that already holds that journal and
  has just replaced its document from disk; `restart_journal` in
  `crates/bridge/src/api/files.rs` picks between them. **Every way of coming
  away without a journal is reported, never swallowed**: a name a pending
  recovery holds, a state directory the core never found, and a journal
  directory that is full or unwritable all end in
  `Session::set_journal_unavailable` and one `JournalBroken`, and the status
  line goes on saying "recovery record unavailable" for the rest of that
  session. `Session::record` treats a missing journal as broken for the same
  reason. A failure never fails the open: the editor still works and the file
  still saves. Startup obeys the same rule: `scriptToRestore` in
  `app/lib/app.dart` never session-restores a script an undecided offer names.
- **The watcher asks early; the save path is what actually protects the file**
  (ADR 0038). `storage::watch::DiskState` is what a session last knew its file
  to hold, and `write_document` compares it against the file immediately before
  replacing it. Identical bytes written again proceed silently and a file that
  is gone is recreated; bytes nobody here has seen come back as
  `SaveFailure::ChangedOnDisk`. Every path that establishes what is in the file
  records a new `DiskState` — open, save, reload, restore, accepted recovery,
  and the external-change check when it finds the file identical. Save As is
  exempt: its destination came from a chooser that already asked. The watch
  failing marks the session `watch_broken`, pushes `ExternalWatchUnavailable`
  once, and the status line says "external changes not watched" for the rest of
  the session.
- **Save As moves the session; an export copies the text and moves nothing**
  (ADR 0029). `doc_save_as` rebinds path, journal, watch, backups and library
  entry; `doc_export_fountain` writes one file and leaves every one of them —
  and the dirty flag — alone. `doc_save_as` refuses `AlreadyExists` (retry with
  `overwrite: true`) and `ScriptIsOpen`; the session's own file is the one
  exception — Save As onto where the script already lives is a save.

## The Fountain core

- `fountain` owns syntax; `document` owns identity and history. `document`
  re-exports `fountain`'s kinds (ADR 0008).
- `infer_kind` is the third caller of `syntax.rs`, after the parser and the
  serialiser, and it is bound by the same rule: it must never produce a kind
  the file would not give back. Do not add a classification rule to it that the
  parser does not already have (ADR 0011).
- Provenance ranges **tile the source exactly**: every byte after the BOM
  belongs to exactly one range, in order. Byte-exact round-tripping is a
  consequence. Any change to the parser must keep the tiling test green (ADR
  0007). Editing a block drops its provenance and nothing else's.
- Recognition rules live once, in `fountain/src/syntax.rs`, and the serialiser
  calls the same functions backwards. Do not add a second opinion about what a
  line means.
- `testdata/reference-feature.fountain` is generated by
  `python3 tools/make_reference.py`; do not hand-edit it. Corpus files are
  compared byte-for-byte — never reformat one or strip its trailing whitespace.

## Bridge and generated code

- `flutter build linux` invokes cargokit to compile `crates/bridge` and bundle
  `libslugline_bridge.so`; do not add a separate Rust build step.
- When the exposed bridge API/types change, run
  `cd app && flutter_rust_bridge_codegen generate`. Include generated Dart and
  Rust bindings in the change; never edit them by hand. Implementation-only
  edits under `src/api/` do not need regeneration. Install codegen tools only
  if missing. `tools/check_bridge_bindings.sh` regenerates into a temp directory
  and diffs; do not repeat that expensive check immediately after successful
  generation unless investigating drift or changing codegen configuration.
- Keep Rust `flutter_rust_bridge = "=2.12.0"` and Dart
  `flutter_rust_bridge: 2.12.0` exactly aligned. Bump both and regenerate
  bindings in the same change.

## Verification

Choose checks from the changed behavior and its failure modes. The commands in
scoped guides are a menu, not a mandatory list for every edit.

| Change | Normal completion checks |
| --- | --- |
| Prose or agent instructions | Review the diff; run `python3 tools/check_docs.py` when changing governed docs. No Rust/Flutter builds or tests. |
| Local Rust behavior | Format touched code and run the relevant test filter or test target in the owning crate. Use the whole crate only when the impact warrants it. |
| Local Flutter behavior | Format touched Dart; run the relevant widget test file or named tests. Analyze changed files when code/types change. |
| Save, recovery, source preservation or history | Focused tests for affected persistence/round-trip/Undo behavior, including failure cases. Use save/reopen or native checks where a unit test cannot cover the failure. |
| Shared syntax, wrapping, pagination or output | The affected contract/differential/golden tests and relevant consumers, not every unrelated suite. |
| Tooling/configuration | Exercise the changed tool or configuration; shell syntax for shell edits. Layering, version, reference and binding checks only when their inputs change. |

Start with existing coverage. Add a regression test when it catches a meaningful
behavioral failure; do not add tests for prose, trivial presentation changes or
tests that merely repeat the implementation. Confirm filtered tests actually run.

`./tools/agent.sh quick <crate> [cargo-test-args...]` supports focused Rust
checks; `./tools/agent.sh native <suite> [flutter-test-args...]` selects one native
suite (`native --list` lists them). The optional `docs` command combines fast
structural checks; `lint` is workspace-wide. None is a mandatory pre-flight.
Run dependency resolution only for setup or dependency/toolchain changes.

### Full development validation

Run the complete applicable Rust/Flutter suites **once at the end of a substantial
feature, refactor or accumulated batch of related changes**, or when the user
explicitly requests full validation. A shared-contract change spanning several
layers or a broad runtime/toolchain change is a useful boundary; line count or
the end of each small backlog item is not. Choose that boundary before starting
expensive checks. Do not use full validation as an automatic per-commit gate.

Rust validation is `cargo fmt --all --check`,
`cargo clippy --workspace --all-targets -- -D warnings` and
`cargo test --workspace`. Flutter validation from `app/` is the whole-tree
Dart format check, `flutter analyze` and `flutter test`. Run both for a broad
cross-layer batch; a substantial change confined to one side needs that side.
After they pass, rerun only checks affected by subsequent changes or failures.

Native tests are for behavior requiring the real bridge, input system or runner.
Select the relevant suite with `./tools/agent.sh native <suite>`; the complete
`./tools/test_linux_integration.sh` belongs to a batch affecting several native
workflows or an explicit full native validation, not every UI edit.
An app build needed for reproduction is allowed; do not build a release bundle
just to close an ordinary task. Run `tools/check_clean_close.py` for
runner/shutdown changes or Flutter upgrades, and `tools/check_runtime_budgets.py`
for relevant performance changes; neither is a routine feature-completion gate.

### Release and hosted CI

**GitHub release compilation, packaging, installers, AppImage/tarball smokes,
network-isolation checks, release preflight and publishing are deferred until the
project's final release task is explicitly requested.** Do not run, wait for,
retry or fix them during normal development. A small task being "done" does not
make it a release task. `docs/RELEASING.md` and `tools/release_preflight.sh` are
references for that final task, not a development checklist.

Automatic development CI in `.github/workflows/checks.yml` runs cheap docs and
tooling checks. The expensive matrix in `.github/workflows/ci.yml` is manual
final validation; do not trigger it during routine development. The tag-triggered
release workflow remains reserved for final publishing. Do not poll or wait for
CI as part of routine completion. Inspect CI only when requested or needed to
diagnose the current change; report actual results without claiming unobserved
success.

### Evidence and correctness

Report what was checked and any relevant limitation briefly. Keep useful failed
logs/cores for unresolved defects; do not manufacture a new evidence dossier for
passing work. Do not mask a reproduced failure with sleeps, slower input,
retries, relaxed assertions or forced termination.

If a check fails, determine whether the failure belongs to this change before
expanding the work. Repair failures caused by the change; record unrelated ones
briefly and continue. Use a minimal prior-version control only when attribution
will change that decision. Do not build a clean checkout or rerun a full matrix
by default. After repeated attempts reveal the same external blocker with no
new evidence, stop the detour and report the narrow blocker. Never claim the
affected behavior is verified when its relevant check still fails.

When relevant, verify exact bytes, BOM/CRLF, untouched source, journal recovery
and actual reopen. Full-disk classification alone is not a real full-disk test;
PDF extraction marked `SKIPPED` is not a pass. Widget, native, installed and
real-desktop results are distinct: Xvfb does not close manual GPU gate 5. An
ordinary-close check must inspect process exit and retain a failing core, not
just wrapper success. Mention only the gates relevant to the change or requested
validation; do not restate every pending manual gate in every completion.

Regenerate goldens only for deliberate output/contract changes, explain why
briefly, and never bless a failure by updating expected output. Scoped guides
and `./tools/agent.sh regen` contain the regeneration commands. Budget thresholds
remain governed by `docs/BUDGETS.md`; change the measuring test and contract
together if deliberately changing one.

## Project constraints

- Add a one-line justification to `docs/DEPENDENCIES.md` in the same change as
  every new Rust or Dart dependency. Avoid large transitive dependency trees.
- Rust's minimum version is 1.85; avoid newer std APIs unless raising the floor
  deliberately. Storage uses `libc::flock`, not newer `File::try_lock` (ADR 0042).
- `app/pubspec.lock` belongs to Flutter 3.44.8. Newer Flutter, including codegen
  running `pub get`, may rewrite it. Restore it unless deliberately changing
  dependencies or the toolchain; CI uses `--enforce-lockfile`.
- Do not add network requests, telemetry, update checks, font downloads,
  databases, or persisted lock files. Loss of user text is a P0 defect.
- Never rewrite an accepted ADR's decision in `docs/DECISIONS.md`. A later
  decision adds a record naming what it replaces (`**Supersedes:**`, or
  `**Narrows:**` / `**Refines:**` / `**Extends:**` when only part falls), and the
  old record gains one line: `**Superseded by:**`, or `**Historical:**` when
  nothing replaced it but its phase is over. Those annotations and the index's
  status column are the only edits an accepted record takes; an ADR contradicting
  the code with neither is an unrecorded supersession to report, not to rewrite.
- `spike/` is throwaway benchmark evidence for ADR 0005, is outside the Rust
  workspace, and is not built by CI.
