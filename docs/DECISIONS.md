# Architecture Decision Records

One record per non-obvious choice: a choice between real alternatives that a
later agent would otherwise re-litigate. Newest last.

A record's decision is never rewritten once it is accepted. If the decision
changes, add a new record that names what it replaces — `**Supersedes:**`, or
`**Narrows:**` / `**Refines:**` / `**Extends:**` where only part of the older
record falls — and give the old record a `**Superseded by:**` line naming its
replacement. A record that nothing replaced, but whose phase or process has
since finished, takes a `**Historical:**` line instead. Those annotations are
the only edits an accepted record takes.

**Read the index before the records.** It is the map: what each record owns, and
whether it still governs. A record whose status is not `live` has been partly or
wholly replaced, and its status names the record that did it — read that one
too. A `historical` record is spent: it settled a question about a phase or a
process that has since finished, so nothing supersedes it and nothing needs to.

## Index

| # | Title | Owns | Status |
| --- | --- | --- | --- |
| 0001 | The bridge speaks UTF-16, and conversion is fallible | `crates/bridge/src/offsets.rs` | live |
| 0002 | Rust builds through cargokit, with the FRB version pinned exactly | `Cargo.toml`, `app/pubspec.yaml`, `app/lib/src/rust/`, `app/rust_builder/` | live |
| 0003 | `freezed` is accepted as a Dart dependency | `app/pubspec.yaml`, `app/lib/src/rust/` | live |
| 0004 | Layering is enforced by a script, not by cargo-deny | `tools/check_layering.py`, `Cargo.toml` | extended by 0055 — FDX codec shares syntax types |
| 0005 | Editor implementation: a single custom editing surface | `app/lib/editor/editor_surface.dart`, `spike/` | narrowed by 0018 — Dart line breaking is permanent; narrowed by 0069 — CJK input-method gate retired |
| 0006 | The project is called Slugline | `Cargo.toml`, `app/pubspec.yaml`, `crates/storage/src/paths.rs` | live |
| 0007 | Round-tripping is a tiling invariant, not a comparison | `crates/fountain/src/parse.rs`, `crates/fountain/src/serialise.rs` | refined by 0059 — canonical syntax excludes redundant pins; narrowed by 0061 — explicit safe boneyard replacement |
| 0008 | Syntax lives in `fountain`, identity and history live in `document` | `crates/fountain/src/model.rs`, `crates/document/src/lib.rs`, `crates/document/src/document.rs`, `crates/document/src/edit.rs` | live |
| 0009 | The bridge's document surface: flat kinds, patches, and refusals as values | `crates/bridge/src/api/doc.rs`, `app/flutter_rust_bridge.yaml`, `app/lib/src/rust/` | live |
| 0010 | Paste is composed in the bridge, and grouped by the document | `crates/bridge/src/api/doc.rs`, `crates/document/src/document.rs` | extended by 0061 — safe omission transactions |
| 0011 | Automatic classification is the recognition rules read forwards | `crates/fountain/src/infer.rs`, `crates/document/src/workflow.rs`, `crates/bridge/src/api/doc.rs`, `crates/document/src/document.rs` | partly superseded by 0059 — live pins are not unconditional persisted markers |
| 0012 | The custom surface's semantics tree is a render object per block | `app/lib/editor/surface_semantics.dart`, `app/test/editor/accessibility_test.dart` | live |
| 0013 | The crash journal records outcomes, not commands | `crates/storage/src/journal.rs`, `crates/document/src/recovery.rs`, `crates/bridge/src/api/doc.rs` | extended by 0063 — saved checkpoint identity translation |
| 0014 | The autosave clock lives in Dart | `app/lib/editor/autosave.dart`, `app/lib/editor/editor_page.dart` | partly superseded by 0043 — "autosave writes no backup" |
| 0015 | The file chooser is ours, because `file_selector` brings `http` | `app/lib/library/file_chooser.dart`, `tools/check_no_network.sh`, `app/pubspec.yaml` | superseded by 0052 — GTK chooser through the runner |
| 0016 | Accepting a recovery rewrites the journal; it does not write the script | `crates/bridge/src/api/files.rs`, `crates/storage/src/journal.rs`, `crates/bridge/tests/persistence.rs` | partly superseded by 0042 — recovery takes no journal lock; narrowed by 0068 — managed projects |
| 0017 | A default completion does not take Enter from the editor | `app/lib/editor/editor_controller.dart`, `crates/bridge/src/api/doc.rs`, `app/lib/editor/editor_surface.dart` | refined by 0051 — Shift+Enter always edits |
| 0018 | The editor is fluid, and its line breaking stays in Dart, pinned to Rust by a test | `app/lib/editor/line_layout.dart`, `crates/layout/src/line_break.rs`, `crates/layout/tests/line_break_differential.rs`, `docs/LINE_BREAKING.md` | partly superseded by 0040 — page indication; refined by 0057 — printed-width projection |
| 0019 | Emphasis markup is displayed literally in the editor through 1.0 | `app/lib/editor/metrics.dart`, `crates/render_pdf/src/pdf.rs`, `app/lib/editor/line_layout.dart` | superseded by 0044/0045/0057 — shared printed-width emphasis and editable styling |
| 0020 | Pagination crosses the bridge as an async snapshot job, and the page count is written after a save | `crates/bridge/src/api/layout.rs`, `crates/layout/src/lib.rs`, `crates/storage/src/library.rs` | extended by 0058 — scene pagination metadata |
| 0021 | Pinned autocomplete entities live in the library index | `crates/storage/src/library.rs`, `crates/document/src/entities.rs`, `crates/bridge/src/api/doc.rs` | live; narrowed by 0068 — managed projects |
| 0022 | Repagination is incremental by checkpoint, and validated rather than trusted | `crates/layout/src/engine.rs`, `crates/layout/src/model.rs`, `crates/layout/tests/incremental.rs` | refined by 0049 — what a checkpoint records, where a run resumes and stops |
| 0023 | One crash recovery is offered per launch | `app/lib/app.dart`, `app/lib/library/recovery_dialog.dart`, `crates/bridge/src/api/files.rs` | live |
| 0024 | The interval autosave keeps running while the writer types | `app/lib/editor/autosave.dart`, `crates/storage/src/watch.rs`, `crates/bridge/src/api/files.rs` | superseded by 0028 — own-write suppression mechanism |
| 0025 | The paginator's break rules get a focused review before Phase 7 | `crates/layout/src/engine.rs`, `crates/layout/tests/break_rules.rs` | historical — gate on a shipped phase; its record file is gone |
| 0026 | One save of a script at a time, by a per-session lock | `crates/bridge/src/api/files.rs`, `crates/bridge/src/state.rs` | live |
| 0027 | A save rebuilds its journal around what was typed during it | `crates/bridge/src/api/files.rs`, `crates/storage/src/journal.rs` | live |
| 0028 | A save is recognised by the file it left, not by a counted event | `crates/storage/src/watch.rs`, `crates/bridge/src/state.rs`, `crates/bridge/src/api/files.rs` | live |
| 0029 | Exporting a copy is not Save As, and it refuses two destinations | `crates/bridge/src/api/files.rs`, `app/lib/preview/export_dialog.dart`, `app/lib/core/document_core.dart`, `app/lib/library/save_dialogs.dart` | live; narrowed by 0068 — managed projects |
| 0030 | The completion popup names its gestures, and its rows are not click targets | `app/lib/editor/editor_surface.dart`, `app/test/editor/autocomplete_test.dart` | partly superseded by 0041 — popup activation and row cap |
| 0031 | A character extension is recognised by its letters, not its punctuation | `crates/document/src/entities.rs` | live |
| 0032 | The PDF writer is ours, and it interprets emphasis without leaving a gap | `crates/render_pdf/src/pdf.rs`, `crates/render_pdf/fonts/`, `crates/render_pdf/tests/golden.rs` | partly superseded by 0044/0045 — printed alignment and shared preview interpretation |
| 0033 | A title-page edit is journalled like any other edit | `crates/document/src/recovery.rs`, `crates/storage/src/journal.rs`, `crates/bridge/src/api/doc.rs` | refined by 0066 — repeated title entries |
| 0034 | Calibration: the grid is Final Draft's, and the references disagree with each other | `crates/layout/src/metrics.rs`, `crates/render_pdf/tests/element_indents.rs` | refined by 0046 — spacing belongs to lyric runs |
| 0035 | The navigator is a Rust semantic snapshot and a Dart interaction | `crates/bridge/src/api/doc.rs`, `app/lib/editor/navigator_sidebar.dart`, `crates/document/src/entities.rs` | partly superseded by 0041; extended by 0058 — navigator drawer below 900 px |
| 0036 | Spell checking is an immutable Rust snapshot and a Dart overlay | `crates/spell/src/lib.rs`, `crates/bridge/src/api/spell.rs`, `app/lib/editor/spell_dialog.dart` | live |
| 0037 | Preferences split display policy from screenplay output | `crates/storage/src/prefs.rs`, `app/lib/settings/preferences_dialog.dart`, `crates/bridge/src/api/appearance_prefs_dont_affect_pagination.rs` | partly superseded by 0052 — retained in-app chooser |
| 0038 | The save path checks the file it is replacing; the watcher only asks early | `crates/storage/src/watch.rs`, `crates/bridge/src/api/files.rs`, `crates/bridge/src/state.rs` | live; narrowed by 0068 — managed projects |
| 0039 | The release build unwinds; `panic = "abort"` is superseded | `Cargo.toml`, `app/linux/CMakeLists.txt` | live |
| 0040 | The fluid editor shows output page position in its status bar | `app/lib/editor/page_indicator.dart`, `app/lib/editor/editor_page.dart`, `crates/bridge/src/api/layout.rs` | live |
| 0041 | Suggestions follow writing intent, and narrow windows keep the page wide | `app/lib/editor/editor_surface.dart`, `app/lib/editor/editor_controller.dart`, `app/lib/editor/navigator_sidebar.dart` | refined by 0051 — Shift+Enter always edits |
| 0042 | Crash journals carry kernel ownership across publication | `crates/storage/src/journal.rs`, `crates/storage/Cargo.toml`, `crates/bridge/tests/persistence.rs` | live |
| 0043 | Previous versions include bounded automatic snapshots | `crates/storage/src/backup.rs`, `crates/bridge/src/api/files.rs`, `app/lib/library/backups_dialog.dart` | live; narrowed by 0068 — managed projects |
| 0044 | Layout aligns emphasis by printed width, without changing wraps | `crates/layout/src/engine.rs`, `crates/fountain/src/emphasis.rs`, `crates/layout/Cargo.toml` | extended by 0057 — printed wrapping |
| 0045 | Preview and PDF share resolved emphasis and heading weight | `crates/render_pdf/src/lib.rs`, `crates/bridge/src/api/layout.rs`, `crates/layout/src/model.rs`, `crates/storage/src/prefs.rs`, `app/lib/preview/preview_view.dart`, `app/lib/editor/editor_surface.dart`, `app/lib/settings/preferences_dialog.dart` | extended by 0047/0057 — sung dialogue and source-resolved wraps |
| 0046 | Consecutive lyric blocks share one leading blank | `crates/layout/src/engine.rs`, `crates/layout/src/metrics.rs`, `app/lib/editor/line_layout.dart`, `app/lib/editor/metrics.dart` | live |
| 0047 | Sung hard lines remain dialogue and carry lyric output metadata | `crates/fountain/src/syntax.rs`, `crates/fountain/src/lib.rs`, `crates/layout/src/engine.rs`, `crates/layout/src/line_break.rs`, `crates/layout/src/model.rs`, `crates/render_pdf/src/lib.rs` | live |
| 0048 | Page 1 is counted, and prints its number only when the page setup asks | `crates/layout/src/engine.rs`, `crates/layout/src/model.rs`, `crates/layout/tests/page_numbers.rs`, `crates/storage/src/prefs.rs`, `app/lib/editor/page_indicator.dart`, `app/lib/settings/preferences_dialog.dart` | live |
| 0049 | An incremental run resumes and stops only where the paginator recorded that it could | `crates/layout/src/engine.rs`, `crates/layout/src/model.rs`, `crates/layout/tests/incremental_differential.rs` | live |
| 0050 | Release-process budgets observe the shipped window and measured quiet | `tools/check_runtime_budgets.py`, `docs/BUDGETS.md`, `docs/MANUAL_GATES.md`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `tools/release_preflight.sh` | live |
| 0051 | Shift+Enter is a core-owned line break with its own undo transaction | `crates/bridge/src/api/doc.rs`, `app/lib/core/document_core.dart`, `app/lib/editor/editor_controller.dart`, `app/lib/editor/editor_surface.dart`, `app/lib/editor/commands.dart` | live |
| 0052 | GTK owns local file selection; the core still authorizes replacement | `app/linux/runner/my_application.cc`, `app/lib/library/file_chooser.dart`, `app/lib/library/quick_open_dialog.dart`, `app/lib/settings/preferences_dialog.dart`, `app/lib/preview/export_dialog.dart`, `app/lib/library/save_dialogs.dart` | live; narrowed by 0068 — managed projects |
| 0053 | The runner stops the engine before the process exits | `app/linux/runner/my_application.cc`, `tools/check_clean_close.py`, `.github/workflows/ci.yml`, `.github/workflows/release.yml` | live |
| 0054 | Dual dialogue is a disjoint pair with independent page continuations | `crates/layout/src/engine.rs`, `crates/layout/src/metrics.rs`, `crates/render_pdf/src/lib.rs`, `app/lib/editor/line_layout.dart`, `app/lib/editor/metrics.dart`, `app/lib/editor/elements.dart`, `app/lib/editor/editor_controller.dart` | live |
| 0055 | FDX is an interchange copy, while Fountain remains the native document | `crates/fdx/`, `crates/document/src/document.rs`, `crates/bridge/src/api/files.rs`, `app/lib/core/`, `app/lib/app.dart`, `app/lib/preview/export_dialog.dart` | refined by 0062 — imported untitled recovery starts against blank; narrowed by 0068 — managed projects |
| 0056 | Scene numbering is an explicit grouped Rust edit, not an output fallback | `crates/document/src/document.rs`, `crates/bridge/src/api/doc.rs`, `app/lib/core/document_core.dart`, `app/lib/editor/elements.dart`, `app/lib/editor/commands.dart`, `app/lib/editor/editor_controller.dart` | live |
| 0062 | An imported untitled document begins with a complete recovery outcome | `crates/bridge/src/api/files.rs`, `crates/bridge/src/api/doc.rs`, `crates/bridge/src/actor.rs`, `crates/bridge/tests/persistence.rs` | live; narrowed by 0068 — managed projects |
| 0057 | Inline emphasis uses printed wraps and an editable source projection | `crates/fountain/src/emphasis.rs`, `crates/layout/src/line_break.rs`, `crates/layout/src/engine.rs`, `crates/layout/src/model.rs`, `crates/bridge/src/api/doc.rs`, `crates/document/src/document.rs`, `crates/render_pdf/src/lib.rs`, `app/lib/core/document_core.dart`, `app/lib/editor/line_layout.dart`, `app/lib/editor/editor_surface.dart`, `app/lib/editor/editor_controller.dart`, `docs/LINE_BREAKING.md` | live |
| 0059 | Canonical Fountain persists necessary syntax, not redundant live pins | `crates/fountain/src/serialise.rs`, `crates/document/tests/clean_fountain.rs`, `crates/bridge/src/api/files.rs`, `app/integration_test/persistence_test.dart` | refined by 0060 — necessary authored-case syntax |
| 0060 | Forced Character cues retain authored case on every surface | `crates/fountain/src/case.rs`, `crates/fountain/src/serialise.rs`, `crates/layout/src/engine.rs`, `app/lib/editor/metrics.dart`, `app/lib/editor/editor_surface.dart`, `crates/render_pdf/tests/text_extraction.rs`, `app/integration_test/export_test.dart`, `app/integration_test/persistence_test.dart` | live |
| 0058 | The outline is source-ordered Rust structure and scene length is paginated occupied eighths | `crates/bridge/src/api/doc.rs`, `crates/bridge/src/api/layout.rs`, `app/lib/editor/navigator_sidebar.dart`, `app/lib/editor/page_indicator.dart` | live |
| 0061 | Omissions carry lossless semantic fragments inside Fountain boneyards | `crates/fountain/src/omission.rs`, `crates/document/src/omission.rs`, `crates/bridge/src/api/doc.rs`, `app/lib/editor/elements.dart`, `app/lib/editor/commands.dart`, `app/lib/editor/editor_controller.dart` | refined by 0063 — provenance-only seam normalization and checkpoint recovery |
| 0063 | Saved checkpoint outcomes use the base's identities without changing live state | `crates/storage/src/journal.rs`, `crates/bridge/src/api/files.rs`, `crates/document/src/omission.rs`, `crates/document/tests/omission.rs`, `app/integration_test/writing_test.dart` | live |
| 0064 | A quit parks the session; putting a script away ends it | `crates/bridge/src/state.rs`, `crates/bridge/src/api/files.rs`, `crates/storage/src/library.rs`, `app/lib/app.dart`, `app/lib/editor/editor_page.dart`, `tools/check_clean_close.py` | refined by 0067 — reading row on explicit open and recovery; narrowed by 0068 — managed projects |
| 0065 | The headless budget profile does not join the desktop's session bus | `tools/check_runtime_budgets.py`, `docs/BUDGETS.md` | live |
| 0066 | Repeated title entries are shown and edited individually | `crates/fountain/src/model.rs`, `crates/document/src/document.rs`, `crates/bridge/src/api/doc.rs`, `app/lib/editor/title_page_dialog.dart` | live |
| 0067 | Reopening and recovery reuse the saved reading row | `app/lib/app.dart`, `app/test/file_workflow_test.dart`, `app/integration_test/persistence_test.dart` | live |
| 0068 | Editable scripts are portable managed projects; import and migration copy sources | `crates/storage/src/project.rs`, `crates/bridge/src/api/files.rs`, `app/lib/app.dart`, `app/lib/library/` | live |
| 0069 | CJK input-method validation is outside the release scope | `docs/MANUAL_GATES.md` | live |

---

## ADR 0001 — The bridge speaks UTF-16, and conversion is fallible

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

Dart strings are UTF-16, Rust strings are UTF-8. Spec §2.4 already fixes the
policy — every offset crossing the bridge is a UTF-16 code-unit offset named
`*_utf16` — but leaves open what happens when an offset is *invalid*: one that
lands between the halves of a surrogate pair, or inside a multi-byte UTF-8
sequence.

The tempting answer is to round to the nearest boundary, because it never fails
and the caller never has to think.

### Decision

`crates/bridge/src/offsets.rs` is the only module in the project permitted to
convert between the two encodings, and every conversion returns `Option`.
Invalid offsets return `None`. Nothing is rounded, clamped, or guessed.

### Consequences

* A caller bug surfaces at the boundary, as a `None`, at the moment it happens.
  Rounding would turn the same bug into text corruption somewhere else, later,
  in a document the user cares about — and §1.2 makes losing user text a P0.
* Every bridge function that takes an offset has to decide what to do with
  `None`. That is the point.
* The module is tested against a string containing ASCII, a Latin-1 accent, CJK,
  and an astral-plane emoji, with a round-trip over every byte boundary of a
  realistic line of dialogue.
* Offsets are `u32` (§3.4). `clamp_u32` saturates rather than wrapping, because
  a wrapped offset is a small plausible-looking number and a saturated one is
  obviously wrong.

---

## ADR 0002 — Rust builds through cargokit, with the FRB version pinned exactly

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

Phase 0 requires `flutter build linux --release` to compile the Rust workspace
with no manual step. `flutter_rust_bridge_codegen integrate` offers two
backends: `cargokit` (a CMake/Gradle shim, works on any Flutter) and
`native-assets` (Dart build hooks, newer, still moving).

### Decision

Use `cargokit`, with the Rust crate living at `crates/bridge` — outside the
Flutter project — via `--rust-crate-dir ../crates/bridge`, so the workspace
layout of §2.5 survives. Pin `flutter_rust_bridge = "=2.12.0"` in Cargo.toml and
`flutter_rust_bridge: 2.12.0` in pubspec.yaml.

### Consequences

* `flutter build linux --release` compiles Rust and drops
  `libslugline_bridge.so` into `bundle/lib/`. Verified; CI asserts the file
  exists and that the whole bundle stays under the 60 MB budget (§1.3). It is
  24 MB today.
* The exact-version pin is not pedantry: the Rust crate and the Dart package
  exchange a generated ABI, and a mismatch produces glue that compiles and is
  silently wrong. Bump both in one commit, then re-run codegen.
* Regenerating bindings needs `cargo-expand` installed
  (`cargo install cargo-expand`). Generated Dart under `app/lib/src/rust/` is
  committed, so a plain build does not need it. CI does not re-run codegen, so a
  stale binding is caught by the integration tests rather than by codegen diff —
  revisit if that ever bites.
* Native assets is the likely future. Nothing in the project depends on which
  backend is used, so switching later is a codegen re-run, not a migration.

---

## ADR 0003 — `freezed` is accepted as a Dart dependency

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

§1.2 requires a written justification per dependency and rejects anything with a
large transitive tree. `flutter_rust_bridge` maps a Rust enum that carries data
onto a `@freezed sealed class` in Dart, and refuses to generate without
`freezed` present. §3.4's `EditCommand` and §6's `CoreEvent` are both exactly
that kind of enum, so this is not avoidable by design choice — only by giving up
sum types at the boundary and hand-rolling tag + nullable-field structs.

### Decision

Take the dependency: `freezed_annotation` at runtime, `freezed` and
`build_runner` as dev dependencies.

### Consequences

* Dart gets exhaustive `switch` over `CoreEvent` and `EditCommand`. The compiler
  catches a missing variant, which for an event enum that will keep growing is
  worth more than the dependency costs.
* `build_runner` runs during `flutter_rust_bridge_codegen generate`, never during
  `flutter build`. Generated `.freezed.dart` is committed, so the build stays a
  one-step build.
* The alternative — a struct with a `kind` tag and a nullable field per variant —
  moves the exhaustiveness check from the compiler to code review. Rejected.

---

## ADR 0004 — Layering is enforced by a script, not by cargo-deny

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0
**Superseded by:** ADR 0055 extends the allowed graph with `fdx -> fountain` and `bridge -> fdx`; the enforcement decision remains live.

### Context

§2.5 mandates that CI enforce "no upward crate dependencies" and suggests
`cargo-deny`. But cargo-deny's ban list is designed for *external* crates and
licences; expressing "`layout` may depend on `document` and nothing else in this
workspace" in it is awkward and produces an unhelpful message when violated.

### Decision

`tools/check_layering.py` reads `cargo metadata --no-deps`, compares each
crate's intra-workspace dependencies against an explicit allow-table, and fails
with the offending edge named. Standard library only.

### Consequences

* CI needs Python (present on every runner) and nothing else.
* Verified by construction: adding `slugline_layout` to `fountain`'s
  dependencies makes the check fail with
  `fountain -> layout violates §2.5 (allowed: nothing)`, and removing it makes it
  pass again.
* The same table appears twice — in the script and in `WORKSPACE_CRATES` in
  `handshake.rs`, which the demo window renders. A unit test asserts the second
  copy has seven entries and that `fountain` depends on nothing.
* This buys no licence or advisory auditing. If we ever want that, add
  `cargo-deny` alongside; it is not a replacement for this check.

---

## ADR 0005 — Editor implementation: a single custom editing surface

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0
**Superseded by:** ADR 0018 for the consequence below that Prototype C's line
breaking "must be replaced by" the Rust `layout` crate's output; the Dart wrap
implementation is permanent and stays on the keystroke path. ADR 0069 retires
the CJK input-method validation requirement in the Phase 3 exit gate. The rest
of this record stands.

> This is the decision Phase 0 exists to make. Every later phase depends on it.

### Context

Phase 0 required three throwaway prototypes, each loading a synthetic
3,000-paragraph document and supporting typing in any paragraph, arrow-key
navigation across paragraph boundaries, and a four-paragraph selection that can
be copied as text. All three were built (`spike/`), all three implement the same
`SpikeSurface` interface, and one benchmark script drives all three so the
numbers compare.

### Measurements

Release build, Flutter 3.44.8, Linux/Wayland, 60 Hz, 3,000 paragraphs, three
runs per prototype (ranges are across runs). Reproduce with:

```
cd spike
flutter build linux --release --dart-define=P=<a|b|c> --dart-define=BENCH=true
./build/linux/x64/release/bundle/spike
```

| | **A** — `EditableText` per block in a `ListView` | **B** — `super_editor` 0.3.0-dev.52 | **C** — one custom surface |
| --- | --- | --- | --- |
| Load to first frame | 33 ms | **397–411 ms** | 23 ms |
| Frame build while typing, p50 / p99 / max | 2.2 / 4.2 / **418 ms** | **15.2** / 24 / 109 ms | **0.55** / 1.0 / 1.5 ms |
| Frame build while scrolling, p50 / p99 / max | 12.3 / 55 / **453 ms** | 8.8 / 16.4 / 21 ms | **0.54** / 1.3 / 2.1 ms |
| Frame builds over the 16 ms budget | 6.5–8.5% | **17%** | **0%** |
| Keystroke → rendered frame (wall) | 16.7 ms = 1 frame | **85 ms = 5 frames** | 17.0 ms = 1 frame |
| Select 4 paragraphs + copy | **3.2 s** | 94–117 ms | 17 ms |
| RSS after run (budget: 250 MB) | 390–418 MB | 449–456 MB | **255 MB** |
| AOT size cost of the dependency | — | **+256 KB** | — |

Wall-clock figures are vsync-quantised: 16.7 ms is the floor, not a cost. Frame
**build** time is the number that says whether the budget can be sustained.

Two footnotes so the table is not read wrongly:

* "Boundaries crossed by 40 arrow-downs" was 40/40 for A, 30/40 for B, 3/40 for
  C — and **C is the correct one**. A moves the caret block-wise because it
  cannot see visual lines inside a paragraph; B and C move by visual line, so
  most Downs stay inside a wrapped paragraph, which is what a text editor does.
* B's +256 KB is negligible. Bundle size is not an argument against it, and the
  Phase 0 guidance about a package that "saves you three months and adds 2 MB"
  is correctly answered: the size never mattered.

### What the numbers mean

**A is not viable.** Frame builds of 400–450 ms during typing and scrolling, and
3.2 seconds to select four paragraphs, on a document a third the size of a
feature. The cost is structural: `EditableText` owns its own selection and knows
nothing about its neighbours, so every cross-paragraph operation is
reimplemented on top of it — and the reimplementation is what is slow, because
it can only work by rebuilding the list. A also has to retain a
`TextEditingController` and `FocusNode` per paragraph outside the virtualised
list, or the caret is lost on scroll.

**B works and is the honest contender.** Selection, IME, and multi-node editing
are solved, correctly, by people who have thought about it more than we will.
But:

1. **There is no stable release compatible with current Flutter.** Latest stable
   is 0.2.7 (June 2024); it does not compile against Flutter 3.44 — missing a
   `TextInputConnection.updateStyle` override. The measurements above are from
   `0.3.0-dev.52`, a prerelease. Adopting B means pinning a prerelease of a
   package whose stable line is two years behind, for a project whose lifetime is
   measured in years.
2. **It misses the frame budget at this size.** 15.2 ms median build while typing
   is *at* the 16 ms budget with an empty screenplay, no Rust in the loop, no
   pagination, no spell-check underlines, and nothing else on screen. 17% of
   frames are already over.
3. **We would be fighting it, structurally.** §2.1 says Rust owns the document,
   the undo history, and element inference. super_editor brings its own
   `MutableDocument`, its own `EditRequest`/undo pipeline, and its own node
   model. Adopting it means either two sources of truth — which §2.1 exists to
   forbid — or bypassing most of what we took the dependency for.

**C meets every budget with two orders of magnitude of headroom.** 0.55 ms
median build while typing, zero frames over 16 ms, RSS inside the 250 MB budget,
and cross-paragraph selection is trivial because a selection is two
`(block, offset)` pairs in a model we own. Line breaking is character counting on
the monospace grid (§5.1), so what the editor paints is what `layout::paginate`
will compute in Rust — the editor and the PDF cannot drift apart. And there is no
blinking-caret animation, so the 0% idle CPU budget is met by construction rather
than by fighting a widget that wants to animate.

### Decision

**Build the editor as a single custom editing surface (Prototype C).** One
`TextInputClient` for the document, our own line layout, our own caret and
selection painting, our own key handling, over the document model that Rust owns.

### The risk, stated plainly

The Phase 0 guidance warns that writing your own IME-correct text editor is how
this project dies, and that warning is not defused by these numbers. What the
prototype does *not* implement is the whole of the input surface:

* composition (IME) spanning a paragraph boundary — the prototype hands the
  platform one paragraph at a time, which is correct for every case except that
  one;
* word-wise and line-wise motion and deletion, and the platform text-editing
  intents that come with them;
* mouse-drag selection, double/triple-click, autoscroll during drag;
* accessibility, which `EditableText` provides free and we do not.

None of that gets cheaper with effort; it is simply work, and it belongs to
Phase 3.

Three things keep this from being an open-ended commitment:

1. We use Flutter's `TextInput`/`TextInputClient` plumbing. We own layout,
   painting, and the model — not the platform protocol. This is materially less
   than "write a text editor".
2. The screenplay grid is monospace and fixed (§5.1). No shaping, no font
   metrics, no bidi, no variable-width line breaking. The hardest part of a
   general text editor is absent from this one by specification.
3. **Phase 3 gets a hard exit gate:** CJK composition via ibus, dead-key accents,
   and clipboard round-trip through a real IME must pass as integration tests
   before Phase 3 closes. If they cannot be made to pass, this ADR is superseded
   and B is the fallback — which is why the spike code stays in the repository
   rather than being deleted.

### Consequences

* `spike/` is kept, not deleted. It is throwaway code, but it is the evidence,
  and B is the fallback path.
* `super_editor` is **not** a dependency of `app/`. It is only in `spike/`.
* The editor in Phase 3 starts from `spike/lib/prototype_c.dart`'s structure:
  line layout from the model, visible-band painting, position arithmetic in
  document coordinates.
* Prototype C's line breaking must be replaced by the Rust `layout` crate's
  output rather than duplicated in Dart — the Dart version exists only because
  the spike had no Rust in it. Flutter renders lines; it does not decide them.
  (§2.1: Flutter never derives screenplay semantics on its own.)

---

## ADR 0006 — The project is called Slugline

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1

### Context

Phase 0 shipped under the working name "screenplay", which was never a name so
much as a description: it was the directory the repository happened to be in.
The GitHub repository is `slugline`, after the industry term for a scene
heading, and §16 lists "application name, binary name, and reverse-DNS app ID"
as an open decision.

### Decision

The project is **Slugline**. Every identifier follows:

| | Before | After |
| --- | --- | --- |
| Rust crates | `screenplay_*` | `slugline_*` |
| Shared library | `libscreenplay_bridge.so` | `libslugline_bridge.so` |
| Dart package | `screenplay` | `slugline` |
| Binary | `screenplay` | `slugline` |
| Application ID | `com.phagmaier.screenplay` | `com.phagmaier.slugline` |
| XDG directories | `$XDG_*_HOME/screenplay/` | `$XDG_*_HOME/slugline/` |

The XDG paths are settled here rather than in Phase 4 because they are the one
part of the rename that is a user-visible file location, and Phase 4 should
inherit a decision rather than make one.

### Consequences

* Verified end to end rather than by search-and-replace alone: `flutter build
  linux --release` produces `bundle/slugline` and
  `bundle/lib/libslugline_bridge.so`, and `flutter_rust_bridge_codegen generate`
  reproduces the committed bindings with the new library stem.
* Name references inside ADRs 0002 and 0004 were updated in place. That is the
  one edit an accepted record may take: it changes what a thing is called, not
  what was decided. Anything else still needs a superseding record.
* The word "screenplay" survives in prose throughout the repository, because the
  application is still a screenplay editor. Only identifiers moved.

---

## ADR 0007 — Round-tripping is a tiling invariant, not a comparison

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1
**Superseded by:** ADR 0061 permits explicit, whole-boneyard omission/restoration;
ordinary Opaque edits remain prohibited and parsed provenance still tiles exactly.

**Superseded by:** ADR 0059 refines canonical equality only; source tiling remains unchanged.

### Context

§3.2 requires that opening and resaving a file loses nothing, and §1.2 makes
losing user text a P0. The mechanism the spec names is provenance: each block
records the byte range it was parsed from, and unedited blocks are re-emitted
verbatim.

What the spec leaves open is what the ranges cover. The obvious reading — a
block's range is the bytes of its own lines — leaves the blank lines *between*
blocks belonging to nobody, and then losslessness becomes a second problem
stacked on provenance: how many blank lines were there, which of them were CRLF,
was there a tab on that empty one.

### Decision

**The provenance ranges tile the source exactly.** The title page's range runs
from the end of the BOM to the start of the first block; each block's range runs
from the start of its first line to the start of the next block's first line;
the last block's range runs to the end of the file. Every byte after the BOM
belongs to exactly one range, in order, with no gaps and no overlaps.

Byte-exactness is then not a feature to be maintained but a consequence:
serialising an untouched document is copying the source back out in pieces. The
blank lines, the CRLFs, the trailing tabs and the missing final newline are
inside somebody's range, so they come back.

The invariant is asserted directly — in unit tests, over every corpus file and
every truncation of one, and in the fuzz target — rather than only through the
round-trip comparison it implies, because a tiling failure names the block that
broke while a byte comparison names an offset.

### Consequences

* A file with no final newline resaves with no final newline. Phase 1's "output
  always ends with a single newline" is a property of the **canonical** writer —
  the path an edited block takes — and byte fidelity outranks it for bytes
  nobody touched. §1.2 decides that tie.
* Editing a block drops its provenance and nothing else's, so one edit
  canonicalises one block and leaves the rest of the file alone. Undo restores
  provenance along with text, so edit-then-undo-then-save is a no-op rather than
  a reformat.
* The serialiser therefore owns separators: an edited block writes the blank line
  that follows it. Where the separator a neighbour carries no longer matches the
  kind that will follow it — inserting a parenthetical after a line of dialogue,
  say — that neighbour's provenance is dropped too, and only then.
  Canonicalising a block the user never touched is exactly what this ADR exists
  to avoid.
* Whether the output is at the start of a line is asked of `\n`, not of *this
  document's* terminator. A file may mix them, and verbatim bytes are whatever
  the file had; asking the narrower question inserted a spurious `\r\n` into a
  CRLF file whose second line ended with a bare LF. Found by the fuzz target,
  not by the corpus.
* Three consequences of tolerance, each chosen so the parser cannot make text
  jump around under a caret that is still typing:
  * An unclosed `/*` runs to the end of the file, as every other Fountain
    implementation does. An unclosed `[[` is **not** a note — treating it as one
    would reclassify every block below the caret between keystrokes.
  * A line of nothing but whitespace is a separator. Fountain's convention that
    two spaces mean an intentional blank line inside Action is not modelled; the
    bytes still round-trip, and the difference is one Action block or two.
  * An `Opaque` block refuses every edit command. §3.2 defines Opaque as "always
    has provenance and therefore always round-trips exactly", and an edit that
    deleted the `*/` from a boneyard comment would turn the rest of the script
    into a comment. Found by a property test.
* Some element sequences have no Fountain spelling at all: dialogue with no cue
  above it, two adjacent dialogue blocks, an empty action paragraph, a scene
  heading whose whole text is `.`. The writer drops what it cannot say rather
  than writing a blank line that would split the neighbours apart — and a block
  with no text has no text to lose. Every element marker except `!` also
  swallows the whitespace beside it, so a padded text loses its padding when it
  takes a marker on. The property tests generate only representable documents,
  and say why.

---

## ADR 0008 — Syntax lives in `fountain`, identity and history live in `document`

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1

### Context

§3.1 puts `Document`, `Block` and `BlockKind` in `crates/document`. §2.5 says
`fountain` depends on nothing else in the workspace. A parser that returns a
`Document` cannot honour both.

§3.4 raises the same tension elsewhere: it gives `EditCommand` a `range_utf16`
field, while §2.4 and ADR 0001 permit UTF-16 conversion in exactly one module,
`bridge/src/offsets.rs`.

### Decision

Split by what each crate owns rather than by which struct the spec drew where.

* `fountain` owns **syntax**: `BlockKind`, `TitlePage`, `TitleField`, and
  `Element` — a parsed block with no identity. It parses to `Element`s and
  serialises from a borrowed view of them, so `document` can write its own blocks
  without copying their text.
* `document` owns **identity and history**: `Block` is an `Element` plus a
  `BlockId`, and `Document` adds the id counter, the retained source and undo. It
  re-exports `fountain`'s kinds rather than declaring its own, so there is one
  spelling of "this is a scene heading" in the workspace.
* `document::EditCommand` carries **UTF-8 byte offsets**. The bridge owns the
  `*_utf16` form and converts through `offsets.rs` on the way in, which is the
  arrangement ADR 0001 asks for. The fields are named `range` and `at` rather
  than `range_utf16`, because a name that lies is worse than a name that differs
  from the spec.

Two smaller departures from §3.4's literal text, both to keep an invariant
enforceable in one place: `InsertBlocks` takes id-less `NewBlock`s, so §3.1's
"never reused after deletion" is decided by the document; and `apply` returns
`Result`, because a stale id or an offset inside a character has to be answerable
without a panic.

### Consequences

* The layering check passes unchanged: `document -> fountain` was already the
  expected edge.
* An inverse is not an opposite command but a `Splice` carrying the original
  blocks — ids and provenance included. One clone per transaction, and undo
  restores provenance, which is the property that makes undo-then-save write the
  original bytes.
* `document` has no clock. §3.4's 600 ms coalescing rule needs one, so this crate
  coalesces consecutive text edits *to the same block* and exposes `commit()`;
  the caller that owns the clock — the bridge actor, in Phase 2 — decides when
  600 ms have passed. Keeping time out of the model is what lets the parser, the
  model and the pagination engine be tested without one.
* `index_of` is a linear scan. At a few thousand blocks that is a microsecond on
  the keystroke path; if it ever shows up in a profile the answer is an index
  beside `blocks`, maintained by the same splice that maintains the vector.
* The entity index named in §2.1 is not here. It belongs to Phase 5, and building
  it now would be scaffolding for a consumer that does not exist (§1.4).

---

## ADR 0009 — The bridge's document surface: flat kinds, patches, and refusals as values

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2

### Context

§6 fixes the *names* of the bridge functions and §3.4 the shape of
`EditCommand`, but three questions are left open by both, and each one is
answered on every keystroke:

1. `BlockKind::Section` carries a level. An enum with a payload becomes a
   `freezed` sealed class in Dart (ADR 0003), which the editor would then have
   to destructure on every block it paints and could not use as a map key.
2. `EditResult` says "the ids of blocks that changed, removed, inserted". Ids
   alone are not enough to patch a list: Dart would have to fetch the changed
   blocks and guess where the inserted ones went.
3. An edit can be refused. FRB's usual answer is a `Result` that becomes a
   thrown Dart exception.

### Decision

**Kinds are flat.** `BlockKind` on the bridge is a plain Dart enum with a
`Section` variant, and the level rides alongside in `BlockView::section_level`
(0 for everything else). `SetKind` carries the same pair.

**A result is a patch that can be applied without another call.** `EditResult`
carries whole `BlockView`s for changed blocks, `(index, BlockView)` for inserted
ones — the index being the position *after* the edit — and a `block_count` Dart
asserts its own list against. The order is: drop `removed`, update `changed`,
insert `inserted` in ascending index.

**A refusal is a value, not an exception.** `doc_apply` returns
`EditOutcome::Applied | Rejected { reason, message }`.

`u64` is mapped to Dart `int` rather than `BigInt`, via `type_64bit_int` in
`app/flutter_rust_bridge.yaml`.

### Consequences

* Dart switches exhaustively over `BlockKind` and uses it as the key of the
  element-metrics table. The cost is one field that means nothing for twelve of
  the thirteen variants — the "tag plus nullable field" shape ADR 0003 rejected
  for `CoreEvent`. It is accepted here for the opposite reason: a plain Dart
  enum *keeps* the compiler's exhaustiveness check, which is what ADR 0003 was
  buying. `EditCommand`, `EditOutcome` and `CoreEvent` remain sum types.
* No refetch: `test/editor/editor_controller_test.dart` watches the number of
  reads out of the core stay at one across a run of edits.
* Two refusals are ordinary user actions rather than bugs — typing inside a
  boneyard comment, and backspacing at the very start of the script — so the
  status bar shows them and nothing catches anything. Making them exceptions
  would put a `try` on the keystroke path for the sake of two cases that are not
  errors.
* Dart `int` is a native 64-bit signed integer on the only platform this project
  targets (§1.2), so the `BigInt` mapping was pure allocation on the path that
  runs for every visible block. The switch is codegen-wide: change it and every
  binding must be regenerated in the same commit, or the glue and the bindings
  disagree silently.
* `SetTitlePage` is absent from the bridge's `EditCommand`. The title page is
  edited in Phase 7 and a command with no caller is scaffolding (§1.4).

---

## ADR 0010 — Paste is composed in the bridge, and grouped by the document

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2
**Superseded by:** ADR 0061 adds explicit safe omission transactions; ordinary
pasted Opaque material still follows this ADR's Action conversion.

### Context

Phase 2 requires "copy, cut, paste (as Fountain-aware blocks)". Copying a
selection means asking what the selection *is* in Fountain, and pasting means
reading Fountain back and splicing it in — both are screenplay semantics, which
§2.1 puts in Rust.

A paste is not one `EditCommand`. Replacing a selection with three blocks is a
delete, a split, an insert and two text edits, and §3.4's rule that every
structural command starts a new transaction would make it five undo steps.
Worse, the split's new block has no id until the split has run, so the sequence
cannot even be written down in advance.

### Decision

`document` gains a grouping primitive: `Document::apply_group(before, plan)`
runs a closure that applies commands through a `Grouped` handle and sees each
result as it goes, and the whole run becomes **one** undo transaction. A failure
part-way through rolls the group back and reports the error, so the "a rejected
edit never half-happens" guarantee holds for a group as it does for a command.
`apply_all(commands)` is the sequence-shaped convenience over it.

The paste itself is composed in `bridge/src/api/doc.rs`, where the caret is
known, and its shape depends on where the caret is:

* **Inside a block** — the text is spliced in: the first pasted block joins what
  precedes the caret, the last joins what follows it, the rest become blocks.
* **At a block boundary, with more than one block to paste** — the blocks go in
  whole, above or below. Welding a copied scene heading onto the end of a line
  of dialogue is never what was meant.
* **Into an empty block** — the first pasted block fills it, kind and all.

Copying is `Document::extract`, which re-serialises the selected blocks — and
keeps the provenance of blocks the selection covers *whole*, so copying an
untouched scene reproduces the bytes it was written with rather than a canonical
rendering of them (§3.2).

### Consequences

* Typing over a selection that spans blocks is a paste, not two commands, so it
  is one undo step. That is why `adopt` refuses to carry plain unforced Action:
  it is the kind typed text has, and adopting it would silently demote a scene
  heading whose text the user selected and retyped. There is a named test.
* Phase 3's Replace All ("one undo transaction") already has its primitive.
* An `Opaque` block cannot be a *new* block — §3.2 defines Opaque as content
  that always has provenance, and pasted content has none — so `parse_blocks`
  turns one into Action carrying the same bytes, which the serialiser then
  protects with `!`. Nothing is lost except the invisibility of a pasted
  boneyard comment. It is the only lossy corner of the clipboard, and it is
  preferred to dropping the text (§1.2).
* `Ctrl+Shift+V` is the same path with `plain: true`: every line becomes an
  Action block and `forced` stays false, so the serialiser adds `!` only where a
  line would otherwise be read back as something else. A plain-pasted
  `INT. HOUSE - DAY` stays Action without the file gaining a marker it does not
  need.

---

## ADR 0011 — Automatic classification is the recognition rules read forwards

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 3

**Superseded by:** ADR 0059 for persisted markers only; live inference suppression remains unchanged.

### Context

Phase 3 asks for "automatic detection on the current block as you type", for
`INT.` in an action paragraph to promote it to a scene heading, and for §4.2's
scoping rules — one block either side of an edit, never a forced block, never a
block the caret is nowhere near.

The obvious implementation is a second set of rules: a table of "if the text
looks like this, make it that". That is exactly what ADR 0007 spent Phase 1
avoiding for the serialiser, and for the same reason: two opinions about what a
line means will disagree, and the disagreement shows up as a document whose
element types change every time it is saved and reopened.

There is also a subtler problem. Whether a block is "preceded by a blank line" —
which half of §4.1's rules depend on — is not a fact about its text. It is what
the serialiser decides from the two kinds involved (`needs_blank_between`). So
"what would the parser call this text?" has no answer until you say what the
block currently *is*.

### Decision

**`fountain::infer_kind` asks §4.1's own recognition functions, with the block's
current kind as part of the context.** It is the third caller of `syntax.rs`,
after the parser and the serialiser, and it is bound by one property: *it never
produces a kind the file would not give back*. There is a test that walks a
parsed script and asserts inference agrees with the parser on every unforced
block, and another that asserts a document, once re-classified, reads back with
the same kinds.

The current kind settles the blank-line question first. After a line of dialogue,
a block that is already dialogue is written adjacent to it and stays dialogue; a
block that is action is written after a blank line, is therefore a fresh element,
and is free to become a scene heading. Both are what a reparse would say.

Four things are never re-classified, and each is a rule rather than a special
case:

* **A forced block.** `forced` is the record that a human said what this element
  is — by typing `.`, `@`, `>`, `!`, or by pressing the shortcut. Automatic
  behaviour does not argue with it. This is also what makes §Phase 3's "an
  immediate element-type shortcut after an automatic change reverts and forces
  the user's choice" fall out for free rather than needing a mechanism.
* **An empty block.** There is nothing to classify, and the kind that put it
  there is the only intent available. Without this rule, the empty scene heading
  that Enter creates after a transition would flip to Action before a key was
  pressed.
* **A block whose kind is written with a marker its text no longer carries** —
  `~`, `#`, `=`, `===`, `> <`, `[[ ]]`, `/* */`. For those the kind *is* the
  marker; asking what the text looks like would answer Action every time and
  delete the marker on the way out. `BlockKind::is_inferable` names the six that
  §4.1 recognises from the text itself.
* **A dual cue.** The `^` pins it: a re-classified dual block would carry a flag
  on a kind that cannot hold one.

**Scope is `Document::reinfer`, and the bridge calls it after every edit.** It
takes the patch the edit produced and the caret the writer had, widens to one
block either side of everything that changed, and folds the kinds it changed into
the same patch — so Dart applies one patch and never learns that anything
reclassified at all. Two edits opt out: a plain paste (`Ctrl+Shift+V`), because
§Phase 2 says that path infers nothing, and Replace All, because it is a bulk
operation over blocks the writer is not looking at, which is the case §4.2 says
to leave alone.

**A re-classification joins the transaction of the keystroke that caused it.**
`History::reopen` puts back the transaction that has just closed, and
`record_alongside` appends without disturbing what the open one is coalescing. So
typing `INT. HOUSE - DAY` is one undo, and the promotion that happened at `INT.`
does not split the run of typing in two. This works because an `Inverse::Splice`
already carries the whole block — kind, `forced` and provenance — so a run's first
inverse restores a re-classified block for free; only the *neighbours* need an
inverse of their own.

### Consequences

* A typed scene heading is written **without** a marker, because inference never
  forces. A scene heading set from the menu is written with a `.`, because
  §Phase 3 says an explicit choice sets `forced = true`. That asymmetry is
  visible in the file and it is the intended one: the marker means "a human said
  so", which is what `forced` has always meant.
* `Action → Character` is on Tab rather than automatic. A cue is only a cue when
  something speaks under it (§4.1), so an all-capitals line with a blank line
  below it is action, and inference must say so or contradict the parser. The
  cue workflow is therefore *type the name, Tab* — and the character-name
  suggestion is a hint in the element bar, never a change.
* The keyboard workflow tables live in `document/src/workflow.rs`, not in
  `fountain` and not in Dart. Not `fountain`, because the format has nothing to
  say about Tab. Not Dart, because §2.1 does not allow a second opinion about
  what follows an element — which is why the "parameterised widget test"
  §Phase 3 asks for covers the *wiring* for every element type while the table's
  content is proved in Rust. `SPEC.md`'s Phase 3 list records the division.
* Enter is composed in the bridge, exactly as paste is (ADR 0010): delete the
  selection, split, set the new block's kind, in one transaction. `doc_enter` and
  `doc_tab` are the two functions §6's "keep this small" budget pays for it, and
  they buy back the alternative — Dart issuing two commands and the writer
  needing two undos.
* Re-classification costs a `Vec` of at most a handful of indices and one
  `infer_kind` call each, on every keystroke. The §1.3 benchmark on the 120-page
  reference script is unchanged: p99 keystroke-to-patch 1.29 ms against a 16 ms
  budget.

---

## ADR 0012 — The custom surface's semantics tree is a render object per block

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 3

### Context

ADR 0005 chose one custom editing surface over `EditableText` and listed four
things that choice costs. Three were paid in Phase 3. The fourth —
"accessibility, which `EditableText` provides free and we do not" — was the last
item outstanding, and `SPEC.md`'s Phase 3 list said so.

The gap was total, not partial. A `CustomPaint` contributes nothing to the
semantics tree, so a screen reader pointed at the editor found a scrollable
containing no text at all: not a degraded experience, an absent one.

Flutter offers three ways to put something there, and two of them cannot express
what a text editor needs:

1. **`Semantics` widgets.** They carry a `SemanticsProperties`, which has fields
   for a label, a value, `textField`, `readOnly`, `multiline` and every action —
   but **no field for a text selection**.
2. **`CustomPainter.semanticsBuilder`.** Same `SemanticsProperties`, same gap,
   plus one of its own: it is rebuilt when the painter is replaced, and this
   painter repaints from a `Listenable` without ever rebuilding.
3. **A render object.** `SemanticsConfiguration.textSelection` is public, and it
   is what carries the caret to AT-SPI as `textSelectionBase`/`textSelectionExtent`.
   `RenderEditable` reaches it the same way.

For a writing tool the caret is not a detail. A screen reader that can read the
paragraph but cannot say where in it you are has told you almost nothing.

### Decision

**One leaf render object per visible block** (`editor/surface_semantics.dart`),
positioned over the block it describes, painting nothing and hit-testing never.
Each one declares itself a multiline text field with the element type as its
`label` and the drawn text as its `value`; the block holding the caret also
carries the selection and the cursor-movement, set-selection, set-text and
clipboard actions.

Three details are load-bearing:

* **The label is the element type.** "Character, JOHN" is what a screenwriter
  needs to hear, and it is the thing no generic text field could say. It comes
  from `kindLabel`, the same table the element bar and the palette read.
* **The value is `displayText`, not the model's text.** §5.2 upper-cases scene
  headings and cues on screen only, and what is announced should be what is
  drawn. This is safe because `displayText` never changes a string's length —
  it refuses the upper-casing that would (`ß` → `SS`) — so the selection offsets
  index into the announced string exactly as they index into the model's.
* **Only the focused block offers cursor actions.** There is one caret. A block
  that does not hold it must not offer to move it, or the move would silently
  jump somewhere else first.

### Consequences

* **Nodes are built for the visible band only, and only while
  `SemanticsBinding.semanticsEnabled`.** A feature-length script is some three
  thousand blocks and a semantics tree of that size is one no screen reader wants
  and no frame budget affords. With no assistive technology attached the cost is
  not paid at all: `_blockSemantics` returns an empty list.
* **The surface now rebuilds on scroll — but only when semantics are on.** The
  painter repaints from a `Listenable` and does not rebuild, which is why the
  editor is as cheap as it is; a semantics tree cannot be updated that way, so
  scrolling and editing both queue a post-frame `setState` while something is
  listening. The §1.3 benchmark is measured with semantics off, which is the
  ordinary case, and is unchanged.
* **One node per block rather than one for the document.** A `value` is one
  string and the document's is half a megabyte. Per-block nodes are also what
  lets a screen reader navigate paragraph by paragraph, which is how someone
  actually reads a script.
* `SemanticsAction.setText` goes through `setSelection` + `insertText` rather
  than a command of its own, so an accessibility action takes exactly the path a
  paste takes: one undo step, and the same re-inference afterwards. An assistive
  technology must not be a second way into the document.
* The tests in `app/test/editor/accessibility_test.dart` assert on the
  `SemanticsData` the owner produces, not on the widgets that produce it. What
  reaches AT-SPI is the only thing that matters, and it is the only thing a
  widget-level assertion would not have checked.

---

## ADR 0013 — The crash journal records outcomes, not commands

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4

**Superseded by:** ADR 0063 extends saved checkpoint identity handling; outcome replay and journal durability remain unchanged.

### Context

§Phase 4 asks for "an append-only **edit journal** … [that] records committed
edit commands between saves", and its exit criterion is that the application can
be killed twenty times while typing without losing a keystroke beyond the last.

Taken literally, a journal of `EditCommand`s replays by re-running every rule
that decided what those commands did: the Enter/Tab tables in `workflow.rs`,
`Document::reinfer`, the validity checks in `edit.rs`, and the caret the writer
happened to have — because `reinfer`'s scope depends on it. Get any of them a
version out of step with the session that crashed, and the recovered script is
quietly not the one the writer was looking at. Recovery is the last place in this
codebase to want cleverness.

Two alternatives were considered and rejected:

* **Journal the serialised document.** Always recoverable, trivially correct, and
  half a megabyte per keystroke on a feature. Doing it per *transaction* instead
  brings it down to once per 600 ms of typing — but a 600 ms window is more than
  "the last keystroke", so it fails the exit criterion by construction.
* **Journal a splice against the previous serialised text.** Small records, but
  computing one costs a full serialise and diff on the keystroke path.

### Decision

**The journal records the `Patch` an edit produced** — the blocks that were
removed, the blocks as they now stand, and the blocks that appeared with the
index they appeared at. `document::recovery` defines the type;
`Document::replay` applies one; `storage::journal` writes and reads them.

Replaying is list surgery with no rules in it. It is also cheap enough to do
after **every** edit rather than every transaction, because one patch is the
blocks one edit touched — a paragraph, for a keystroke — which is what makes the
exit criterion reachable at all.

Three things fall out of the choice and are worth stating:

* **The patch is recorded after `reinfer`**, so the kinds in it are the kinds the
  writer was looking at, not the kinds the command asked for.
* **The header carries a checksum of the file** the journal was opened against.
  Block ids only mean anything against a particular parse, so recovery refuses to
  replay onto a file that changed underneath it rather than applying edits to
  whatever happens to be there now.
* **An undo is journalled like anything else.** A crash after an undo must not
  bring back the text it took away.

### On durability

Appends are written but **not** `fsync`ed, and that is deliberate. The threat
§Phase 4 names is the process dying — `SIGKILL`, a panic, an OOM kill — and a
`write(2)` that has returned has already reached the kernel, so the data survives
all of those whether or not it has reached the platter. `fsync` per keystroke
would be a disk round trip on the hot path to buy protection against power loss
only, and against power loss the last keystroke is unrecoverable anyway. The
atomic save in `storage::atomic` is what protects the *file* against that, and it
does `fsync`, twice.

The measured cost of the append is in the §1.3 benchmark, which now types into a
journalled document as well as an unattached one: p50 0.81 ms against 0.78 ms
without, p99 1.14 ms against a 16 ms budget.

### On the format

Line-delimited JSON, with the record and its newline written in **one**
`write_all`. That single write is the entire integrity scheme: a record followed
by a newline is a record the kernel took whole, and a trailing fragment is a
write that was interrupted. `journal::read` is total in the same sense the
Fountain parser is — no input makes it fail — because it is read at exactly the
moment the user has already lost something, and a recovery path that panics on a
damaged file turns a bad day into a lost script.

JSON rather than a packed binary format because when recovery goes wrong the
writer's text is *in there*, and they must be able to get it out with a text
editor.

### Consequences

* `document` gains `BlockSnapshot`, `Patch`, `Document::replay` and
  `Document::snapshot`. `replay` bypasses the undo history on purpose: the
  transactions it would push invert edits against a process that is gone.
* `storage::journal` mirrors `BlockSnapshot` as a serde struct rather than
  deriving `Serialize` on the model. `document` and `fountain` are the two crates
  §2.5 keeps pure, and a file format is not a thing the model should know about.
  The cost is two conversion functions and a test that walks every `BlockKind`
  through them — element kinds are written as **names**, not numbers, so that
  inserting a variant cannot silently reinterpret every journal on every disk.
* A script that has never been saved is journalled too, keyed by its handle, with
  an empty path in the header. It replays onto `Document::blank()`. That is the
  script a crash costs most.
* Every mutation in `api::doc` ends in `outcome` or `inferring`, and both
  journal. There is no path from Dart to the document that does not pass through
  one of them, which is what lets the journal claim to hold every edit.

---

## ADR 0014 — The autosave clock lives in Dart

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4
**Superseded by:** ADR 0043 for "Autosave writes no backup" only; the
Dart-owned clock, the suppression rules and the save-failure behaviour stand.

### Context

§Phase 4 asks for autosave "debounced after edit inactivity (default 2 s) and on
a hard interval (default 30 s), both configurable", and in the next line: it
"never runs while a modal is open or during an active IME composition".

§2.1 puts "file I/O, autosave, atomic writes, backups" in Rust's column, which
reads at first like an instruction to put the timers there too.

### Decision

**Rust owns the saving. Dart owns the deciding-when.** `AutosaveDriver`
(`editor/autosave.dart`) runs both timers and calls `doc_autosave`; the core has
no timer anywhere.

The reason is the second sentence, not the first. A modal is a widget and a
composition is a state of the platform's input connection — neither fact exists
in Rust, and neither can be sent to it without inventing a protocol whose only
purpose is to tell the core about the UI. §2.1's line is about who *writes the
file*, and that is still Rust: the driver's only power is to ask.

Keeping the clock out of the core also keeps §1.3's 0% idle CPU budget met by
construction rather than by tuning. The actor thread blocks on its channel and
wakes only when something happens; a timer in it would be a wakeup in an idle
process, which is the one thing that budget forbids.

### The two timers, and why both

* **Idle**, restarted on every edit. This is the one that normally fires.
* **Interval**, *not* restarted on every edit. Without it, a writer who never
  pauses for two seconds — which is what a good session looks like — would never
  be saved at all.

Both are cancelled the moment the document is clean, so an idle window costs no
wakeups, and neither is created for a document with nothing to save.

### Consequences

* **A suppression holds a save; it never cancels one.** A save deferred by a
  dialog happens when the dialog closes. §10 does not allow a save to be quietly
  dropped because the timing was awkward, and "the modal closed and the moment
  passed" is exactly that.
* Suppressions are a *set*, not a flag, so a dialog opened over a composition
  cannot un-suppress it by closing. `EditorPage.withModal` pairs every
  suppression with its release in a `finally`.
* **Autosave writes no backup.** A backup per autosave would be a hundred a day
  and would push yesterday's draft out of the retention window by lunchtime.
  §Phase 4's rolling backups are per explicit save.
* A failed autosave leaves the document dirty, so the interval keeps retrying: a
  disk that frees up gets written to without the writer doing anything. The
  failure reaches the status line via `CoreEvent::AutosaveFailed` rather than a
  modal — an autosave is not something the writer asked for — while an explicit
  save that fails is blocking, which is the split §Phase 4 draws.
* The rules are testable without the `.so`, which is where they are tested
  (`app/test/editor/autosave_test.dart`). What a save *does* to a file is Rust's
  and is proved in `cargo test`, per ADR 0011's division.

---

## ADR 0015 — The file chooser is ours, because `file_selector` brings `http`

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4
**Superseded by:** ADR 0052.

### Context

Phase 4 needs Open, Save As, New and Rename, and all four need a path from the
user. The obvious answer is `file_selector_linux`, a Flutter-team package that
puts up GTK's own dialog — a better dialog than anything we would write, using
the file manager's bookmarks and the platform's own conventions.

It pulls `file_selector_platform_interface`, which pulls **`http`**.

### Decision

**Write the chooser** (`library/file_chooser.dart`): list a directory, walk into
it, type a name.

§1.2 makes "the application makes **zero** network requests" a *build-time
assertion* (§13). An HTTP client linked into the shipped bundle is a thing that
assertion then has to argue with — and "it is linked but never reached" is
exactly the kind of exception that, once written into a check, stops the check
from meaning anything. The whole `file_selector` umbrella is worse still: eleven
packages, four of them implementations for platforms §1.2 says not to write code
for.

### Consequences

* The chooser is plainer than GTK's. It hides dotfiles and in-flight `.tmp-`
  saves, appends `.fountain` to a name with no extension, and is keyboard-first
  like the rest of the application (§1.1).
* **This is worth revisiting in Phase 10.** Either the §13 assertion is written
  precisely enough to allow a linked-but-unreached client, or the platform
  interface stops needing one. Until one of those happens, a native dialog costs
  more than it is worth.
* No dependency was added for Phase 4 on the Dart side at all.

---

## ADR 0016 — Accepting a recovery rewrites the journal; it does not write the script

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (repaired during the
mid-project remediation) · **Supersedes:** nothing; it states a sequence ADR 0013
left implicit
**Superseded by:** ADR 0042 for kernel-owned recovery; ADR 0068 for explicit managed succession of legacy candidates. Managed recovery remains dirty without writing the script.
### Context

Crash recovery is the one moment in this program where the writer's text exists
on disk only as a **journal**. Everywhere else the file is the truth and the
journal is the tail; here the journal is ahead of the file, and it is the only
thing that can reconstruct what was typed.

The sequence Phase 4 shipped was: replay the journal into memory → delete it →
start a new journal whose `base` was a checksum of the recovered *in-memory*
text. At the instant between the second and third steps there was no durable copy
of the recovered edits at all, and after the third there was one whose `base`
matched no file on any disk. Two things followed, and the audit (`REVIEW.md`, F2)
found both:

* A second crash before the writer saved or typed left a journal with **zero
  records**, which startup discards as "nothing was typed since the last save".
  Every recovered edit was gone, silently.
* A second crash *after* the writer typed left a journal `journal::verify`
  refused, because its `base` did not match the file. The recovered edits and the
  new typing became unreachable together, reported as `blocked`.

The doc comment on `recovery_accept` said the opposite: "so that a second crash
during recovery loses nothing either."

### Decision

**The successor journal is written before the old one is removed, and it is based
on the bytes the file still holds.**

Accepting an offer now does this, in order:

1. Read and verify the old journal. Verification returns the file's real bytes —
   still the pre-crash ones, because nothing has written to the script.
2. Replay onto those bytes, counting how many patches actually applied.
3. Open the document and bind it to its file, library entry and watch.
4. Write the successor with [`Journal::rebuild`]: the **same `base`**, plus the
   patches that replayed. It goes through `atomic::save_atomically`, so it either
   exists whole or does not exist.
5. Only now remove the old journal, and only when the successor did not already
   replace it at the same path.

There is no instant at which no journal describes the recovered edits.

A document adopted dirty also arms the autosave clock immediately
(`AutosaveDriver.documentAdopted`). Before, the clock started on the first edit
event, and a recovered document produces none — so nothing was saved until the
writer typed, which is not what a person does while reading recovered text.

### Alternatives considered

**Save the script immediately on accept, then checkpoint a fresh journal against
the written bytes.** This was the audit's first suggestion and it is simpler. It
was rejected because it overwrites the writer's file as a side effect of clicking
"Recover", which contradicts what Phase 4 promises and what the kill test
asserts: recovery never auto-applies, and the document comes back *dirty* so the
writer still has to say yes. It would also write a backup for a state nobody
approved.

**Adopt the old journal file as-is and keep appending.** Tempting — for a titled
script the successor would have the same name anyway — but wrong whenever the
replay stopped early or the journal was damaged. Its later records describe edits
the in-memory document does not have, so a future replay would diverge from what
is on screen. Rebuilding from the patches that actually applied is what keeps a
journal a description of *its own* document.

**Refuse to open when the successor cannot be written.** Safe, but it shows the
writer nothing at the moment they most want their text. `RecoveryOutcome` has a
`Degraded` arm instead: open, with the old journal kept, and a dialog saying that
nothing typed from here is being recorded.

### Consequences

* `recovery_accept` returns `RecoveryOutcome` — `Recovered`, `Degraded` or
  `Failed` — rather than `Option<DocumentHandle>`. A failure is a value with a
  message, per this file's existing convention for saves.
* A journal **none** of whose records replay is refused and left on disk
  untouched. Rebuilding would replace the writer's text with an empty file, and
  an empty journal is discarded at the next startup; `recovery_pending` already
  takes the view that an unreadable journal stays put, because a person can pick
  it apart by hand.
* Recovery still writes nothing to the script. That property is now load-bearing
  in two tests rather than one.
* `Journal::rebuild` is the only place that writes a journal wholesale. It shares
  its record encoder with `Journal::append`, and a test holds the two to
  producing identical bytes, so a rebuilt journal cannot drift into a format the
  reader treats as damage.

### Tests and invariants

In `crates/bridge/tests/persistence.rs`:

* `a_second_crash_straight_after_accepting_recovery_loses_nothing`
* `a_second_crash_after_typing_more_keeps_both`
* `a_failed_successor_leaves_the_offer_where_it_was`
* `the_successor_records_only_the_patches_that_replayed`
* `a_journal_that_cannot_replay_is_left_on_disk_rather_than_emptied`
* `an_untitled_recovery_survives_a_second_crash_too`

In `crates/storage/src/journal.rs`:

* `a_rebuilt_journal_is_what_an_appended_one_would_have_been`
* `rebuilding_replaces_a_journal_whole`
* `a_rebuilt_journal_carries_on_being_written_to`

In `app/test/editor/autosave_test.dart`:

* `a document adopted dirty is saved without waiting for a keystroke`
* `adopting a clean document arms nothing`

The first four fail against the previous sequence, each for the reason F2
describes; that was checked by reinstating it.

---

## ADR 0017 — A default completion does not take Enter from the editor

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 5 (repaired during the
mid-project remediation)

**Superseded by:** ADR 0051 for Shift+Enter's editing meaning; plain Enter and Tab
retain the completion behavior below.

### Context

The completion popup highlights its first item as soon as suggestions appear.
The shipped key routing treated that automatic highlight as a choice: Enter
accepted it before Enter could split the block. Because the incremental entity
index already contained the block being typed, a completed scene heading or cue
was often its own sole suggestion. Accepting it replaced the text with identical
text, so the primary writing gesture appeared dead.

The original specification said Tab or Enter could accept a highlighted item,
but did not distinguish the popup's automatic highlight from a highlight the
writer deliberately moved. Arm ordering silently made the former enough.

### Decision

**Tab accepts the default completion. Enter accepts a completion only after the
writer has navigated the popup with Up or Down; otherwise Enter always splits the
block.**

The controller records whether the current completion list has been navigated.
Refreshing or dismissing the list clears that state. Up and Down retain their
popup navigation behavior even when there is only one candidate, because the key
press itself is the writer's choice.

The bridge also removes a candidate whose replacement text is identical to the
active completion segment. Such a candidate can make no change and, in
particular, must not be the current block offered back to itself after the entity
index updates.

### Alternatives considered

**Always let Enter accept the default.** Rejected because merely displaying a
suggestion then disables block splitting, and an exact candidate can turn Enter
into a no-op.

**Never let Enter accept a completion.** Simpler, and Tab would still provide an
explicit acceptance gesture, but it unnecessarily removes the Enter workflow
already promised by Phase 5. Requiring popup navigation keeps that workflow
without stealing ordinary Enter.

**Only reorder the switch arms.** This fixes splitting but leaves the acceptance
rule accidental and leaves the useless self-suggestion in the popup.

### Consequences

* A writer can always split while the popup is merely showing its default item.
* Tab remains the fastest way to accept that default and still falls through to
  the element workflow when no completion exists.
* Up/Down followed by Enter explicitly accepts the selected item.
* Exact no-op candidates do not appear through the bridge. Ranking within the
  entity index remains unchanged for its other consumers and tests.
* The popup remains read-only until one of those acceptance gestures occurs.

### Tests and invariants

* `app/test/editor/autocomplete_test.dart` proves default Enter splits, Tab
  accepts, navigated Enter accepts, and Escape dismisses without editing.
* `crates/bridge/src/api/doc.rs::a_block_is_not_offered_back_to_itself_as_a_completion`
  proves the active block is not returned as an identical candidate.
* `app/test/editor/element_selector_test.dart` proves the palette takes focus and
  Escape after another panel had focus, even when editor completions are non-empty.
* `app/integration_test/editor_test.dart` and `writing_test.dart` exercise the
  complete real-core paths that originally exposed the failures.

---

## ADR 0018 — The editor is fluid, and its line breaking stays in Dart, pinned to Rust by a test

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (decided during the
mid-project remediation) · **Narrows:** ADR 0005 for 1.0; does not reverse it
**Superseded by:** ADR 0040 for "No page breaks, page numbers, or page gutters
in the editing surface" only; the fluid editor shows output page position in its
status bar.
**Refined by:** ADR 0057 supplies Rust-owned printed-width inline projections to
the same synchronous editor wrapper and differential contract.

### Context

Two questions were answered by the code without ever being written down, and the
audit (`REVIEW.md`, F3 and F10) found them by finding their consequences.

The first is §16's open item: does the editor view show page indication at all?
The editor has been a continuous scrolling surface since Phase 2 and nothing in
it knows what a page is.

The second is sharper. ADR 0005 accepted the custom surface partly on the promise
that "the editor renders the lines the `layout` crate computes rather than
duplicating it", and `metrics.dart` has carried a comment since Phase 2 saying
its numbers were on loan until that crate arrived. The crate arrived in Phase 6.
The editor still wraps its own text — and the two implementations disagree in
five observable ways:

| | `line_layout.dart` | `layout::break_lines` |
| --- | --- | --- |
| counting unit | UTF-16 code units | `char`s (an emoji is 1, not 2) |
| spaces at a wrap point | consumes one | consumes the whole run |
| trailing space at the width boundary | emits a phantom empty row | emits one row |
| tabs | one column | 4-column tab stops |
| hard newlines | none until remediation Phase 2 | splits first, always |

Nothing was testing for agreement, so the drift was free.

### Decision

**The editor view stays fluid and unpaginated through 1.0**, and **the Dart
wrapper stays**, as one implementation of a contract the Rust engine also
implements.

* No page breaks, page numbers, or page gutters in the editing surface. Page
  awareness lives in Phase 7's preview and the PDF, both rendered from the same
  `PaginatedScript`.
* `line_layout.dart` remains the wrap implementation on the keystroke path.
* The behaviour the two must share is written down as a contract (remediation
  Phase 6A) and enforced by a corpus-wide differential test comparing *wrap
  boundaries*, not rendered strings, for every block of every corpus file
  (Phase 6C). Where they must agree, drift fails CI.
* The five divergences are resolved by changing **Dart to match Rust**. The
  paginator is authoritative because it is what the PDF prints, and a writer who
  sees a line break in the editor that the page does not have has been lied to by
  the cheaper of the two.
* This narrows ADR 0005 rather than reversing it: that record's concern is that
  there be **one specification** of screenplay geometry, and the differential
  test is what supplies it. Should the editor ever grow page indication, this
  record is the one to supersede.

### Alternatives considered

**The editor asks Rust for wrap points per keystroke.** The literal reading of
ADR 0005. Rejected: it puts a bridge round trip and a cache-invalidation protocol
on the path with the 16 ms p99 budget (§1.3), and it solves by architecture what
one test pins for free. The bridge would also have to answer for a block that is
mid-composition, which is exactly when the answer is least stable.

**Rust computes every block's wraps on open, and patches them per edit.** No
per-keystroke round trip, but it is a second layout cache living in the bridge,
invalidated by every edit and every width change — strictly more machinery than
the differential test, and a new thing to be wrong.

**Paginate the editor itself.** Rejected by §16's own recommendation: fluid is
faster and simpler, and this would put page-break rules — the part of the
paginator that iterates to a fixed point — on the typing path.

### Consequences

* Two implementations exist on purpose. That is only safe while the differential
  test exists; until remediation Phase 6C lands, agreement is asserted for hard
  newlines alone and assumed everywhere else. Phase 6 is not complete without it.
* `metrics.dart`'s "on loan" framing is wrong and has been corrected in place:
  the numbers stay.
* F10's uppercase divergence must be settled *in the contract*, not left to
  whichever side is read first: the editor refuses length-changing uppercase (ß)
  to keep caret columns honest, and `layout::display_text` uppercases
  unconditionally.
* Emphasis markers count as columns on both sides — see ADR 0019, which is what
  keeps this contract from needing a notion of hidden text.
* If the differential test ever becomes impractical to maintain, the fallback is
  to consume Rust's wraps, not to let the test rot.

### Tests and invariants

This record is a decision; its enforcement is remediation Phase 6B/6C, and the
honest statement today is that most of it is not enforced yet.

* Exists: the hard-newline half, in `app/test/editor/line_layout_test.dart` and
  the reference-fixture case in `app/integration_test/editor_test.dart`.
* Required before Phase 6 closes: a corpus-wide differential test over every
  block of `testdata/`, comparing wrap boundaries, printing source block, width
  and both boundary lists on failure; plus a regression case for each of the five
  divergences above.

---

## ADR 0019 — Emphasis markup is displayed literally in the editor through 1.0

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2 (recorded during the
mid-project remediation)
**Superseded by:** ADR 0044 for printed-width alignment, ADR 0045 for shared
preview/PDF interpretation, and ADR 0057 for printed-width wrapping and resolved
editor styling with dim editable markers.

### Context

§16 left open whether `*italic*`, `**bold**`, `***bold italic***` and
`_underline_` appear in the editor as typed or are styled with their markers
hidden. The editor has shown them literally since Phase 2, because nothing in it
interprets them; no record said whether that was the decision or the default.

### Decision

**Literal, for 1.0.** Markers are ordinary characters: they are shown, they are
selectable, they are counted as columns for line breaking in the editor *and* in
the paginator. The PDF renderer (Phase 7) is the only thing that interprets them.

### Alternatives considered

**Style the text and hide the markers.** What most editors do, and prettier.
Rejected for 1.0 because it reintroduces exactly the divergence
`metrics.dart::displayText` refuses: display length stops matching model length,
and every caret column, click mapping and selection rectangle needs a second
coordinate space. That is the bug class remediation Phase 2 just spent a phase
removing for hard newlines.

**Style the text and keep the markers visible.** Cheaper — no second coordinate
space — but it is a half-measure that still needs a Fountain emphasis parser in
Dart, which is a screenplay-semantics question and therefore Rust's (§2.1).

### Consequences

* The editor never transforms text except by the length-preserving uppercase in
  `displayText`. Model offsets and display offsets stay equal.
* ADR 0018's differential test stays simple: both sides count the same
  characters, because neither side hides any.
* Fountain stays honest on screen — what is in the file is what is displayed.
* Upgrading later costs nothing that is not already owed: the emphasis parser
  Phase 7's PDF needs is the same one a styled editor would consume.

### Tests and invariants

* `app/test/editor/line_layout_test.dart` measures columns from model text, so a
  marker that stopped counting would move a wrap boundary and fail there.
* `crates/document/tests/element_change_preserves_text.rs` and
  `app/integration_test/writing_test.dart` hold the editor to changing no
  characters it was not asked to change.
* There is no styling code to test the absence of; this record is what says that
  absence is deliberate.

---

## ADR 0020 — Pagination crosses the bridge as an async snapshot job, and the page count is written after a save

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (decided during the
mid-project remediation) · **Implemented by:** remediation Phase 6D/6E

**Superseded by:** ADR 0058 extends the async snapshot with scene pagination metadata only.

### Context

`crates/layout` is complete, deterministic and golden-tested, and no code outside
its own tests calls it. `crates/bridge/Cargo.toml` has no edge to it,
`ScriptView::page_count` has been a hard zero since Phase 4, the debug dump is a
method with no view, and `repaginate` — the incremental path, with its
checkpoints and its cache (ADR 0022) — has never run in the application at all.
Phase 7 is the phase that consumes pagination, and it was going to have to
integrate it under feature pressure (audit finding F3).

The remaining question was what should *ask* for a pagination, given §2.3: the
actor thread owns the document and must never block, and anything over 2 ms is
async.

### Decision

**Pagination is an asynchronous job over an owned snapshot, and a successful save
is what triggers it.**

* `bridge` depends on `slugline_layout`. It defines its own DTOs for the result;
  internal layout types do not cross the boundary unexamined.
* The actor is visited twice, in the shape `write_document` already uses: take
  `ScriptSnapshot` plus the revision on the actor, let go, paginate on a worker,
  come back to record the result. `ScriptSnapshot` exists precisely to be the
  owned value that can leave (`crates/layout/src/lib.rs`).
* A result is committed only if it still describes the revision it was computed
  from. A stale result is dropped, never merged, and never overwrites a newer
  page count.
* **`page_count` is written after every successful save** — explicit and
  autosave alike — from the snapshot that was saved. It is not recomputed per
  keystroke, and library scan does not paginate unopened scripts: a scan that
  parsed and paginated every script would blow the cold-start budget (§1.3).
* Pagination failure never fails a save. The page count keeps its previous value,
  or stays absent.
* A page count is a **cache**, like everything else in the library index (§the
  storage crate's own rule): an entry never saved by a layout-capable build shows
  nothing, which is what the Phase 4 note already promised.

### Alternatives considered

**Paginate on every edit, or on a debounce.** Rejected: it burns CPU for a number
nobody is reading while typing, and §1.3's idle budget is 0% — a debounce is a
timer, and timers in the core are forbidden (ADR 0014).

**Paginate at library-scan time so every entry has a count.** Rejected on the
cold-start budget: the library must open in the time it takes to `stat` a
directory, not to parse it.

**Paginate on the actor thread and skip the snapshot.** Rejected outright by
§2.3. Full pagination of 120 pages is budgeted at 50 ms; the actor's budget is
2 ms.

**Expose `PaginatedScript` verbatim through FRB.** Tempting, and it is the type
Phase 7 wants. Rejected for now: `Arc<[LayoutLine]>`, checkpoints and cache
statistics are internal machinery, and freezing them into the generated bindings
makes every future engine change an API change.

### Consequences

* Phase 7 starts by consuming an integrated engine. That is the whole point of
  doing this before it rather than during it.
* The library gains a real page count, which is also the first end-to-end proof
  that the paginator runs correctly outside its own tests.
* The incremental path finally runs in the application, which is where its
  checkpoint reuse will actually be exercised (ADR 0022).
* One more worker job exists whose results can arrive out of order; the revision
  guard is what makes that safe, and it is the same discipline the save path
  already uses with `mark_saved_at`.
* A debug pagination surface (remediation Phase 6F) consumes this result rather
  than reimplementing anything in Dart — §Phase 6 permits exactly one UI artifact
  and this is it.

### Tests and invariants

None yet; this is a decision recorded ahead of its implementation. Required
before remediation Phase 6 closes:

* Bridge tests for normal, empty, very long and tolerated-malformed documents.
* A save updates the page count; an autosave does too.
* A pagination that fails leaves the save successful and the count untouched.
* An older pagination result cannot replace a newer one.
* A library scan paginates nothing.
* The page count survives a restart.
* At least one integration test proving the application — not a crate test —
  invokes pagination.

---

## ADR 0021 — Pinned autocomplete entities live in the library index

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 5 (recorded during the
mid-project remediation)

**Superseded by:** ADR 0068 for managed project workflows.

### Context

§16 asked where pinned entities are stored and recommended the library index.
Phase 5 implemented that and recorded nothing, so a §16 open item was closed
silently — one of the drifts the audit's F7 names. The choice is not obvious:
a pin is per-script data, and the obvious per-script place is the script.

### Decision

**Pins live in the library index, keyed by script id, and are never written into
the `.fountain` file.**

* `EntityIndex` holds pins in memory (`pinned: BTreeMap<(EntityKind, String),
  String>`), separately from the frequency aggregates, so a pinned entity
  survives dropping to zero occurrences.
* `doc_set_entity_pinned` writes the session's whole pin set into the script's
  library entry (`ScriptEntry::pinned_entities`) and saves the index; opening a
  script loads them back with `load_pins`.
* An **unsaved script has no entry to write to**, so its pins live in the
  session and become persistent the moment it gains one. Nothing is invented to
  hold them in the meantime: a hidden store for a file the writer has not named
  is what §1.2 forbids.
* Ranking is unchanged by pinning: **exact prefix > frequency > recency >
  alphabetical**, with `pinned` a flag on the candidate rather than a rank. A pin
  guarantees a candidate is *offered*; it does not push it to the top. The
  standard scene components (`DAY`, `NIGHT`, `INT.`, …) are seeded the same way —
  offered when they match, ranked with everything else.

### Alternatives considered

**Store pins in the `.fountain` file**, as a note or a boneyard comment.
Rejected: §1.2 makes the file the user's, and a screenwriting tool that leaves
its own bookkeeping in a plain-text screenplay breaks interchange with every
other Fountain tool. It would also make a pin an *edit* — dirtying the document,
entering the journal, and colliding with round-trip byte-exactness (ADR 0007).

**Store pins in preferences.** Wrong scope: pins are about one script's cast and
locations, and would leak between scripts.

**Rank pins above everything.** Rejected: the writer's own most-frequent
character is the better suggestion nine times in ten, and a pin is a request to
be *remembered*, not to be first. Making it a flag keeps the ranking rule the one
sentence §Phase 5 specifies and unit-tests against a fixed corpus.

### Consequences

* Deleting the library index loses pins and nothing else — consistent with the
  index being a cache the storage crate can rebuild.
* Pins for a script are available the moment it opens, before anything is typed.
* A pin taken on an untitled script is kept for the session and written out with
  the rest once the script is saved.
* The `.fountain` output stays exactly what the writer wrote.

### Tests and invariants

* `crates/storage/src/library.rs::the_index_round_trips` writes a pin through
  `set_pinned` and reads it back out of a reloaded index file.
* `crates/document/src/entities.rs::ranking_is_exact_then_frequency_then_recency_and_deterministic`
  holds the ranking rule this record leaves unchanged, and
  `removing_the_last_occurrence_removes_the_entity_incrementally` holds the
  unpinned half of the drop-out behaviour.
* **Gap, recorded rather than papered over:** nothing tests that a *pinned*
  entity survives losing its last occurrence, which is the one behaviour the pin
  exists for. `EntityIndex::complete` merges the pinned map in unconditionally,
  so it holds by construction — but by construction is not by test. Worth one
  unit test in `entities.rs` next time that file is opened.

---

## ADR 0022 — Repagination is incremental by checkpoint, and validated rather than trusted

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (recorded during the
mid-project remediation)
**Superseded by:** ADR 0049 for what a checkpoint records and for where an
incremental run resumes and stops, and for the gap under "Tests and invariants",
which its differential test closes. The fingerprints, the advisory hint and the
capped fixed point stand.

### Context

§5.4 requires incremental repagination inside 5 ms after a keystroke, against a
full pagination budget of 50 ms for 120 pages. Phase 6 built the machinery —
`PaginationCheckpoint`, a per-block layout cache, `CacheStats` — and, per §15
rule 6, owed a record of how it works. The audit found none (F7).

The danger with any incremental layout is not speed, it is *divergence*: an
incremental result that differs from what a full pagination would have produced
is a bug the golden tests cannot see, because they only ever run the full path.

### Decision

**Reuse is always proved, never assumed.**

* Every block carries a **fingerprint** — FNV-1a over its text, kind, dual flag
  and wrap width. A cached wrap is reused only when the fingerprint and the
  element layout both match; anything else is re-wrapped. FNV-1a is chosen for
  being stable across Rust versions, which a `DefaultHasher` is not, so a cache
  cannot behave differently on a different toolchain.
* Pagination retains **checkpoints**: page index, page number, the block that
  starts the page, its start line, and any continued character. `repaginate`
  restarts from the nearest checkpoint *before* the changed block, and only from
  one that starts cleanly on a block boundary with no dialogue continuation in
  flight — the two conditions that make a page's layout independent of what
  precedes it.
* A caller's hint about which block changed is **advisory**. Wrapped layout is
  validated for every block regardless, and a prefix of pages is retained only
  after the newly computed output proves it byte-for-byte equal. A wrong hint
  therefore costs time and cannot cost correctness.
* The break-rule loop is a **capped fixed point**; on failing to converge it
  falls back to the naive fill and records `fell_back_to_naive`. A page count is
  never allowed to depend on how many iterations ran.
* `CacheStats` reports hits, misses, reused pages and iterations, so a test can
  assert that the incremental path *was* incremental rather than merely correct.

### Alternatives considered

**Trust the changed-block hint and splice.** Faster, and the standard way to get
this wrong: any caller bug, any missed reinference, any dual-dialogue pairing
change turns into a page that silently differs from what a fresh pagination
would produce.

**Cache nothing and paginate fully every time.** 50 ms per keystroke against a
5 ms budget. Rejected by §1.3.

**Hash whole pages instead of blocks.** Coarser invalidation for no benefit: an
edit invalidates its page anyway, and per-block wraps are what is expensive to
recompute.

### Consequences

* The incremental path is bounded by the full path's correctness. Incremental
  output that differs from full output is a test failure, not a subtle artefact.
* The cache is dropped for blocks that no longer exist on every pagination, so it
  cannot grow past the document.
* Until remediation Phase 6D wires the bridge (ADR 0020), all of this runs only
  in `crates/layout/tests/`. That is the gap the audit named, not a fault in this
  design.

### Tests and invariants

* `crates/layout/tests/incremental.rs::one_edit_invalidates_one_block_and_reuses_a_checkpoint_prefix`
  — one edit misses exactly one block in the cache, at least eight pages are
  reused, and the reused prefix is equal to the previous output page for page.
  `CacheStats` is what proves the run was incremental rather than merely correct.
* `crates/layout/tests/incremental.rs::reference_pagination_is_identical_one_hundred_times`
  — the determinism requirement, over the 120-page reference.
* `crates/layout/tests/golden.rs::every_corpus_file_has_a_stable_letter_layout`
  — committed dumps, one per corpus file.
* `crates/layout/tests/break_rules.rs`: eleven tests, one minimal script per §5.3
  rule, including the pathological convergence case.
* `crates/layout/tests/pagination_is_fast_enough.rs`: the §1.3 budgets.
* **Gap, recorded rather than papered over:** no test compares `repaginate` of an
  edited snapshot against `paginate_snapshot` of that same edited snapshot — the
  one assertion that would catch incremental output diverging from full output.
  The engine validates the reused prefix internally, so the property holds by
  construction; ADR 0025's focused review should turn it into a test.

---

## ADR 0023 — One crash recovery is offered per launch

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (recorded during the
mid-project remediation)

### Context

Startup scans for journals and offers recovery. It opens the first offer the
writer accepts and returns, leaving any other journals on disk. A code comment
called this deliberate; nothing said whether it was acceptable, and the Phase 10
backlog carried "revisit multi-recovery UX" as scheduled work.

### Decision

**One offer per launch stands for 1.0.** Remaining journals are left untouched
and offered again at the next launch. Nothing is discarded, and no journal is
resolved without the writer seeing it.

### Alternatives considered

**Queue the offers and walk the writer through them.** More complete, and mostly
unreachable: the application holds **one open script at a time** (§1.4 rules out
multi-window and tabs for 1.0), so more than one crashed session requires a
crash, a relaunch, a second crash without resolving the first, and a third
launch. The failure mode of the simple design in that case is one extra dialog
on the next launch, which loses nothing.

**Resolve the others automatically.** Never: a journal is unsaved user text, and
discarding it without asking is the P0 §1.2 forbids.

### Consequences

* Recovery UX stays a single yes/no at startup, which is what it should be at the
  moment a writer wants their text back rather than a workflow.
* An unlucky sequence can leave a journal offered a launch later than ideal. It
  is still offered.
* This becomes wrong the day the app gains multi-window or tabbed editing — not
  on the 1.0 roadmap. Supersede this record then, do not stretch it.

### Tests and invariants

* What holds the *safety* half — a journal nobody resolved is never lost — is
  tested: `crates/bridge/tests/persistence.rs::recovery_will_not_replay_onto_a_file_that_moved_on`
  and `::a_journal_that_cannot_replay_is_left_on_disk_rather_than_emptied`, plus
  `app/test/editor/persistence_test.dart`'s "Recover and Discard are both offered,
  and nothing is automatic" and "closing the dialog decides nothing". Only
  `Journal::discard` removes a journal, and only on an accept or an explicit
  discard.
* ADR 0016's tests hold the accept path to losing nothing across a second crash.
* The *one offer* half is accepted by inspection, not by test: it is a `return`
  after the first opened offer in `app/lib/app.dart`, including on the `Degraded`
  path. Reaching a second simultaneous offer needs two crashed sessions, which
  needs two scripts open at once, which the application cannot do. A test would
  have to construct a state the app cannot reach.

---

## ADR 0024 — The interval autosave keeps running while the writer types

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (recorded during the
mid-project remediation) · **Extends:** ADR 0014
**Superseded by:** ADR 0028 for how own writes are suppressed: this record
records the write after it succeeds and swallows the first matching event, where
the shipped design records it before the write and matches every event. The rest
of this record stands.

### Context

ADR 0014 gave the autosave two timers: idle (2 s after typing stops) and interval
(every 30 s regardless). The interval timer is deliberately *not* restarted by
typing — a writer who never pauses is exactly who it protects.

That is also what makes audit finding F4 reachable. A save renames a file the
watcher is watching, so the app's own save produces a `FileChangedOnDisk` event
about itself. Nothing correlates that event with the save that caused it. If a
keystroke lands between the rename and Dart's handling of the event, the check
finds the document dirty and different, and the writer gets "Something else has
written to this file" — mid-sentence, about their own autosave. "Take theirs"
would then genuinely discard their typing.

The tempting fix is to stop the interval timer during typing. That would remove
the symptom by removing the protection.

### Decision

**The interval save keeps firing during continuous typing. F4 is fixed on the
watcher side, by correlating the app's own writes.**

* The core records each path it has itself written, with a save generation
  counter, in the step of `write_document` that already runs on the actor after a
  successful write.
* The first matching `FileChangedOnDisk` for that generation is swallowed.
* `doc_external_change` remains the backstop: suppression is an optimisation
  against a spurious prompt, never the thing that decides whether the file really
  changed.
* Suppression records are cleared when they go stale, so a genuine external write
  that arrives later is never eaten by an old one.
* Explicitly **not** acceptable as fixes: "do not save while typing", lengthening
  the interval, or making the external-change dialog less alarming. The dialog is
  right for a real external change; it must simply never fire for our own.

### Alternatives considered

**Restart the interval timer on each keystroke.** Turns it into a second idle
timer, and the writer who never pauses — the one case ADR 0014 wrote the second
timer for — goes unsaved indefinitely.

**Compare content instead of correlating writes.** `doc_external_change` already
does, and it is not enough: between our rename and the event, the writer typed,
so the content legitimately differs. Content comparison cannot distinguish "the
file changed because we wrote it, and then more was typed" from "someone else
wrote it".

**Stop watching the file during a save.** The watch is on the directory (a
rename replaces the inode), so the window is not cleanly closable, and closing it
would also miss a genuine external write landing in the same instant.

### Consequences

* The two-timer design of ADR 0014 is unchanged, and this record is why it must
  stay unchanged.
* The core keeps a small amount of per-path state whose lifecycle has to be
  documented where it lives — it is a suppression record, not a lock, and losing
  it costs one spurious prompt rather than any correctness.
* A genuine external write in the same millisecond as our own save could be
  swallowed. `doc_external_change` catches it on the next event or the next save.

### Tests and invariants

Required by remediation Phase 4B, which implements this:

* Save, immediately type, deliver the watcher event caused by that save, assert
  no modal and no lost typing.
* Deliver a genuine later external modification, assert the real path still runs.
* Multiple watcher events from one atomic rename sequence.
* Generation cleanup.

Existing today: `crates/storage/src/watch.rs`'s tests — in particular
`a_save_by_rename_is_reported_too`, which is the very event this record has to
suppress, and `a_change_to_a_neighbour_is_not_reported` — and the external-change
dialog tests in `app/test/editor/persistence_test.dart` ("an unmodified document
reloads without asking", "a modified document prompts with three answers"). None
of them can see F4 today, because nothing yet distinguishes our own write.

---

## ADR 0025 — The paginator's break rules get a focused review before Phase 7

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 → 7 (scheduled during
the mid-project remediation)
**Historical:** this record scheduled a focused review of the paginator's break
rules. The plan that was to hold its findings (`REMEDIATION_PLAN.md`) is no
longer in the tree, so whether the review was performed cannot be established
from the repository. Nothing supersedes this record. One obligation it was meant
to discharge outlived it: ADR 0022 defers a `repaginate`-versus-`paginate_snapshot`
equivalence test to this review. Backlog item F8 discharged it — see ADR 0049 and
`crates/layout/tests/incremental_differential.rs`.

### Context

The mid-project audit read the whole of `crates/` except the back half of
`crates/layout/src/engine.rs` — the `Paginator` break-rule implementation — and
said so (`REVIEW.md` §10.6, decision D-6). Everything else it left unread is
accepted on the strength of its tests. This one is not, for a specific reason:
its output has never been seen by a human. Golden files prove it is
*deterministic* and that it matches what it produced when the goldens were
written; they do not prove those pages are what §5.3 describes.

Phase 7 is where the output becomes user-visible, and §5.5 calibration is where
the break rules are interrogated against real printed pages.

### Decision

**A focused review of the back half of `engine.rs` is a gate on Phase 7, not a
task inside it.** It traces every page-break rule against §5.3 — orphan
prevention, dialogue splitting with `(MORE)`/`(CONT'D)`, scene-heading handling,
action splitting, the fixed-point cap, A4 derivation, deterministic ordering, and
source identity preservation — and reviews the golden tests for *coverage*
rather than pass status, adding rule-level tests where a rule is asserted only
incidentally.

The paginator is **not** to be rewritten absent concrete defects found by that
review.

### Alternatives considered

**Fold it into Phase 7 as it goes.** What D-6 originally suggested, and the
reason it is being made a gate instead: a rule defect found while building the
preview is found under pressure to ship the preview, and the cheapest resolution
at that moment is to change the golden file.

**Accept it on its tests, like the other unread modules.** Reasonable for
`find.rs` or `backup.rs`, whose behaviour is fully described by their assertions.
Not reasonable here: "this dump is stable" is a much weaker claim than "these
pages are correct", and no human has checked the second.

### Consequences

* Phase 7 begins with the engine either confirmed or corrected, and with any
  golden file that changes doing so as a reviewed decision rather than a fix.
* The review costs no extra calendar — it rides along with the Phase 7 kickoff —
  but it is a checkbox that can block, which is the point.
* Any defect found becomes a rule-level test first, in the style
  `crates/layout/tests/break_rules.rs` already uses.

### Tests and invariants

* Existing: `break_rules.rs` (one minimal script per rule), `golden.rs`
  (committed dumps, determinism over 100 runs), `incremental.rs`.
* Required by the review: a named test for any rule found to be covered only by a
  golden dump, and for any defect it finds.
* Recorded in `REMEDIATION_PLAN.md` Phase 6G; the review is not complete until
  its findings are written there.

---

## ADR 0026 — One save of a script at a time, by a per-session lock

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 4A)

### Context

`write_document` is deliberately three steps (§2.3): plan on the actor thread,
write off it, record back on it. The actor serialises each step. It does not
serialise the *sequence*, and nothing else did either.

So two saves of one script could plan in order and write in reverse. The pair
that reaches this in practice is an autosave already past its due point and an
explicit Ctrl+S: `AutosaveDriver._saving` guards only the driver's own calls, and
Ctrl+S goes through `saveWithDialogs → core.save()` without touching the driver,
while `withModal`'s suppression holds *future* autosaves rather than one already
in flight. With an edit landing between the two plans, the file transiently held
older bytes than the save that had already answered "Saved". Audit finding F5.

`mark_saved_at(min)` made it self-heal at the next autosave and both journal
checkpoints stayed consistent with whatever text won, so no text was lost. But
"the file briefly contains something older than what I was told was saved" is not
a property this codebase tolerates anywhere else.

### Decision

**A `Session` owns an `Arc<Mutex<()>>`, and every writer of that session's file
holds it across all three steps.** `write_document` takes it first, before it
plans; so does `backup_restore`, which is also a write of the document's file.

The lock is taken **off** the actor thread, by code that is already on an FRB
worker. Nothing inside an actor closure may take it — the point is that the actor
stays free while the disk is busy, and the one actor round trip this adds is two
channel sends to fetch the `Arc`.

Three consequences are the decision as much as the lock is:

1. **A second save waits; it is never refused.** §10 does not allow a save to be
   dropped because the timing was awkward.
2. **The plan is made after the wait.** So the save that queued writes whatever
   the document says by then — which is the coalescing, without a queue: if the
   save it waited for already wrote everything, it finds the document clean and
   answers `Unchanged`.
3. **It is per session.** Two scripts still save at the same time, and will still
   do so if the application ever opens more than one at once.

Alongside it, `SaveStateChanged` now carries the document's real dirty state
rather than a hardcoded `false`, and `AutosaveDriver` stops its timers only when
the document actually came back clean. An edit that lands while the file is being
written is genuinely unsaved, and both of those used to say otherwise.

### Alternatives considered

**A "save in flight" boolean, second save refused.** The audit's own first
suggestion. Rejected because refusing needs somewhere to reschedule from, and the
core has no timer and must not grow one (§1.3, ADR 0014) — so the refusal would
have to be handed back to Dart, and an explicit Ctrl+S that answers "busy" is a
worse thing to show a writer than one that takes 30 ms.

**A queue of pending saves on the session.** More machinery for the same result:
the queue can never usefully hold more than one entry, because a second waiter
would plan the same document state as the first. Replanning after the wait gets
that for free.

**One global save lock.** Simpler, and wrong the moment two scripts are open: one
script on a slow disk would stall an unrelated one. `one_script_at_the_disk_does_
not_hold_up_another` exists to stop this being reintroduced.

**Fixing it in Dart, by routing Ctrl+S through `AutosaveDriver`.** Rejected on
the same principle as ADR 0011: the guarantee belongs where the writes are. Dart
would still not cover `backup_restore`, a second window, or anything the bridge
gains later.

### Consequences

* A save can now block an FRB worker thread for the length of another save. That
  is bounded by one file write, saves of one script are rare, and FRB's default
  handler grows its pool rather than starving.
* `doc_save` can answer `Unchanged` where it previously answered `Saved` — when
  it queued behind a save that wrote its bytes for it. `SaveStatus.record`
  already treats `Unchanged` as success, and the status line reads `core.dirty`
  live, so the writer sees "saved".
* The lock is deliberately not held for `library_rename` or `library_duplicate`:
  neither writes the open document's own file through the save path.
* Poisoning is recovered from with `PoisonError::into_inner`. The lock guards
  ordering, not data; refusing to save because an earlier save panicked would be
  the wrong way round.

### Tests and invariants

In `crates/bridge/src/api/files.rs`, against the real save path:

* `an_older_save_cannot_land_after_a_newer_one` — the audit's scenario exactly.
  A `#[cfg(test)]` seam holds the first save between its plan and the disk; the
  second save is started after an edit and given half a second to overtake it.
  It must not, and the file must end with the newest text.
* `an_explicit_save_queued_behind_an_autosave_still_writes_the_newest_text` —
  the overlap that is reachable today.
* `a_save_with_nothing_left_to_write_says_unchanged` — the coalescing.
* `one_script_at_the_disk_does_not_hold_up_another` — the per-session half, and
  the one test here that passes without the lock as well as with it.
* `opening_one_path_twice_over_is_one_document` — the same check-then-act the
  audit found beside F5: `library_open` reads the file off the actor between its
  check and its insert, so `open_source` makes the check again where it is atomic.

In `app/test/editor/autosave_test.dart`:

* `an autosave that collides with one in flight is owed, not dropped`.
* `an edit that lands mid-write does not stop the clock`.

All four Rust save tests and both Dart tests were confirmed to fail with the lock
and the Dart changes reverted, not assumed to.

---

## ADR 0027 — A save rebuilds its journal around what was typed during it

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 4A follow-up) · **Extends:** ADR 0013

### Context

`Journal::checkpoint` truncates a journal to a bare header whose `base` is the
bytes just written, and its comment states the reason: "the records before it
describe edits that are now in the file, and replaying them onto it would apply
them twice."

That is true of every record a save covered. It is false of anything typed while
the save was writing. A save plans its bytes on the actor thread, lets go, and
writes off it (§2.3, ADR 0012) — so an edit can land in between, and
`mark_saved_at(plan.revision)` correctly leaves the document dirty for it. But
the checkpoint then threw its journal record away along with the rest.

The result was a window in which a keystroke was in neither the file nor the
journal. Worse than merely unrecorded: at the next launch `recovery_pending`
finds an empty journal, reads it as a session that ended cleanly, and
`discard_at`s it. Nothing is offered and nothing says anything was lost. §1.2
calls losing user text a P0, and the journal exists so that "not a keystroke
beyond the last" is true; this was a gap in exactly that claim. Recorded as F15
while verifying Phase 4A, which neither caused it nor widened it.

### Decision

**A save that had edits land during it rebuilds its journal around them instead
of emptying it.**

`Session::begin_save` arms a buffer *inside the same actor closure that reads the
bytes to be written*, so there is no instant in which an edit is in neither. Each
subsequent `Session::record` appends to the journal as before and then keeps the
patch. Step three takes the buffer:

* **Empty** — the ordinary case, and nothing changes: `checkpoint` as before.
* **Non-empty** — `Journal::rebuild_at` writes a whole successor journal whose
  `base` is the bytes just written and whose records are exactly those patches,
  through `atomic::save_atomically`.

`rebuild_at` is `Journal::rebuild` (ADR 0016) addressed by path rather than by
id, because a Save As has already changed the id by the time step three runs
while the journal file has not moved. Rebuilding by id there would leave the old
file behind, and an unowned journal is a recovery offered for a session that did
not crash.

The buffer is armed only for the length of one write. A session that is not
saving buffers nothing, so the cost falls on the file write and not on typing —
and the patch is *moved* into `record` rather than cloned, so the keystroke path
allocates no more than it did.

### Alternatives considered

**Do not checkpoint at all when the document comes back dirty.** One line. The
journal keeps every record, but its `base` no longer matches the file, so
`journal::verify` refuses it and the next launch reports the offer as `blocked`.
Better than silent loss — the text is in a file a person can read — and much
worse than recovering it, which the rebuild does for the same window.

**Buffer every patch since the last checkpoint, unconditionally.** Simpler: no
arming, no disarming, no early-return discipline in `write_document`. Rejected on
memory: autosave can be turned off entirely (`autosave_enabled: false` is
supported on purpose), and a long session would then hold every patch of every
edit in RAM alongside the same data on disk. Arming for the width of one write
bounds it to what was typed in a few milliseconds.

**Re-append the kept records after `checkpoint` truncates in place.** No new
journal API needed. Rejected for the reason ADR 0016 gave for `rebuild`: a crash
between the truncate and the re-append loses exactly the records this exists to
save. A whole-journal write has to be atomic.

**Keep patch revisions and filter by `plan.revision`.** Considered and dropped as
redundant: arming happens in the same closure that serialises, so everything
buffered is by construction after the planned bytes. A revision field would be a
second source of truth for the same fact.

### Consequences

* Every path out of `write_document` after the plan must disarm — a refused save
  that left the buffer armed would hold patches for a checkpoint that never
  comes. There is one `abandon_save` for all three, and a test that covers each.
* A failed rebuild leaves the journal exactly as it was. Its `base` no longer
  matches the file, so recovery refuses it rather than replaying onto the wrong
  bytes; nothing is destroyed, which is the property that matters. Same shape as
  the failed `checkpoint` this replaces.
* `Session::record` takes its `Patch` by value. The only caller is
  `api::doc::journal`, which built it and dropped it.
* The window is now closed for the save path. It was never open for recovery:
  ADR 0016 already writes a successor journal rather than emptying one.

### Tests and invariants

In `crates/bridge/src/api/files.rs`, driving the real save path with the same
`#[cfg(test)]` seam Phase 4A added:

* `an_edit_typed_during_a_save_is_still_in_the_journal` — the defect. A save is
  held between planning and writing, an edit lands, and after it completes the
  file holds the older bytes, the document is dirty, and *the journal replayed
  onto the file gives back what the writer can see*. That last assertion is the
  invariant; the test states it as `recovers_to() == the document`.
* `a_save_with_nothing_typed_during_it_empties_the_journal` — the ordinary case
  still checkpoints to zero records, so the rebuild is not on every save.
* `a_save_that_writes_nothing_does_not_leave_the_session_buffering` — all three
  abandon paths: clean, unwritable, and no path at all.

Confirmed to fail with the rebuild reverted: the mid-write test reports zero
journalled records where one was typed.

---

## ADR 0028 — A save is recognised by the file it left, not by a counted event

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 4B) · **Refines:** ADR 0024

### Context

ADR 0024 settled the shape of the F4 repair: the interval autosave keeps firing
while the writer types, and the app's own watcher echo is suppressed by
correlating writes rather than by weakening the timer. It also sketched the
mechanism — "record each path it has itself written, with a save generation
counter, in the step of `write_document` that already runs on the actor after a
successful write", and "the first matching `FileChangedOnDisk` for that
generation is swallowed."

Implementing it found two things wrong with that sketch, both of which would have
shipped a suppression that does not suppress:

1. **Recording after the write loses the race it exists to win.** The rename is
   what causes the event, and `notify` delivers it from its own thread while the
   save is still returning from `save_atomically`. Step three is an actor round
   trip away. The event that most needs swallowing — the one for the save that
   just happened — routinely arrives before there is anything for it to match.
2. **"The first matching event" assumes one event per save.** A filesystem is
   entitled to describe one rename as several events, and inotify does exactly
   that for some save shapes. Swallowing one and letting the rest through would
   turn a modal into a slightly rarer modal.

### Decision

**A suppression record is opened before the write and closed after it, and it
identifies the file we produced rather than counting events.**

* `OwnWrites` (in `storage/watch.rs`) holds one record per path: a generation,
  and — once the write has landed — a `Fingerprint` of the file, being its
  device, inode, length and nanosecond mtime.
* `OwnWrites::begin` runs immediately before `atomic::save_atomically`, and
  `finished`/`abandoned` immediately after. While a write is in flight, every
  event about that path is swallowed: it is either our own rename or a write our
  rename is about to overwrite regardless.
* `OwnWrites::is_echo` answers **every** event about the path, not the first. A
  file that still matches the fingerprint is one nothing has happened to since we
  wrote it, so there is nothing to report — however many times the filesystem
  says so.
* The first event that does *not* match drops the record and is reported. That,
  plus the next write to the same path and `forget` on close/Save As, is the
  whole of the expiry: nothing here gets less true with age, so nothing needs a
  clock and §1.3's idle budget is untouched.
* The generation is what stops an overtaken write from finishing or abandoning
  the record of the write that replaced it.
* Everything ADR 0024 decided stands: both autosave timers are unchanged,
  `doc_external_change` remains authoritative, and losing a record costs one
  spurious prompt rather than any correctness.

### Alternatives considered

**Record after the write, as ADR 0024 sketched.** Kept honest by a test rather
than by argument: `a_save_still_at_the_disk_already_suppresses_its_own_event`
fails against that sequence, because the event arrives while the save is still at
the disk.

**Compare the file's content instead of its identity.** A read of the whole
script on `notify`'s thread, for every event, to answer a question a `stat`
answers. The fingerprint is one `stat` of an inode this process wrote
milliseconds ago, so it is in the kernel's cache; a content read is the disk I/O
§2.3 forbids on exactly the thread that must not block.

**Match on mtime alone.** An in-place write of the same length in the same
nanosecond is not reachable, but an atomic save replaces the inode and that is
free to check — so the fingerprint checks it, and a `git checkout` that restores
byte-identical content is still reported as the external change it is.

**Suppress in Dart, by ignoring events for a moment after a save returns.** A
timer, in the layer that has one — but the app does not learn that the save
finished until after the event may already have been handled, and "for a moment"
is a guess about a filesystem the app cannot see.

**Stop watching during the save.** ADR 0024 already rejected it: the watch is on
the directory, so the window is not cleanly closable, and closing it would also
miss a genuine external write in the same instant.

### Consequences

* `FileWatcher::new` takes the register, so the filter is inside the watcher and
  every consumer of it gets the same answer. The bridge keeps its own `Arc` in
  `Storage::own_writes`, because a build with no inotify still writes files.
* Every write of a document's file must bracket itself — `write_document` and
  `backup_restore` both do, through `OwnWrite`, whose `abandoned` matters as much
  as its `finished`: a record left in flight would swallow the next real change.
* A genuine external write landing inside our own write is swallowed. It was
  already doomed — our rename overwrites it — and `doc_external_change` compares
  against the file at the moment it is asked, so nothing is reported as agreeing
  that does not.
* The suppression state is per path and cleared on close, so a session holds at
  most one record per open script.

### Tests and invariants

In `crates/storage/src/watch.rs`, against real inotify and the real atomic save:

* `our_own_save_is_not_reported`, and its indispensable other half
  `an_external_write_straight_after_our_own_save_is_still_reported`.
* `every_event_from_one_save_is_swallowed_not_just_the_first`,
  `an_event_while_we_are_still_writing_is_swallowed`,
  `a_second_save_suppresses_its_own_event_too`.
* `an_abandoned_write_suppresses_nothing`,
  `a_write_cannot_finish_or_abandon_a_later_writes_record`,
  `the_event_that_did_not_match_clears_the_record`,
  `a_deleted_file_is_not_our_own_write`, `unwatching_forgets_what_we_wrote_there`.

In `crates/bridge/src/api/files.rs`, against the real save path:

* `a_save_is_not_reported_as_somebody_elses_write` — F4 exactly: save, type, and
  the echo is still suppressed while `doc_external_change` still reports dirty
  and different, which is why suppression happens before it and not inside it.
* `an_external_write_straight_after_our_save_is_still_reported`,
  `a_save_still_at_the_disk_already_suppresses_its_own_event`,
  `a_failed_save_leaves_nothing_suppressed`,
  `save_as_suppresses_the_new_path_and_forgets_the_old_one`,
  `closing_a_script_forgets_what_we_wrote_there`.

In `app/integration_test/persistence_test.dart`, end to end against the `.so`:
*our own save is not reported as somebody else writing the file* — the only test
in the repository where a real rename produces a real inotify event that a real
`CoreEvent` stream either carries or does not.

Confirmed to fail first: with `is_echo` stubbed to `false`, eleven of these fail,
the integration test among them; with the bracket moved after the write, the
in-flight one does.

---

## ADR 0029 — Exporting a copy is not Save As, and it refuses two destinations

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 7)

**Superseded by:** ADR 0068 for managed project workflows.

### Context

§6 lists `doc_save_as` and `doc_export_fountain` as different functions. The
bridge had one function wearing both names, and it was the Save As one: it wrote
the file and then *moved the session onto it* — path, journal, watch, library
entry and the dirty flag all followed. F9 in `REVIEW.md` is that conflation.

Nothing was broken by it while no menu offered an export, and that is exactly why
it had to be settled before Phase 7 draws the export dialog: "export a copy and
carry on editing the original" is a verb the writer will reach for, and the
version of it that quietly rebinds the session is one that loses the thread of
what they are editing — a Ctrl+S afterwards writes the copy, not the script.

### Decision

**`doc_export_fountain` writes one file and changes nothing else.** It takes the
serialised document from the actor, writes it with `atomic::save_atomically` off
the actor, and returns. There is no `begin_save`, no `mark_saved_at`, no journal
checkpoint or rebuild, no `rebind`, no library refresh, no backup, no
`SaveStateChanged`, and no pagination job. The document stays dirty if it was
dirty, because the copy is not where this script lives.

`doc_save_as` keeps its existing rebinding semantics unchanged, and now says so
in its own documentation rather than claiming to be both.

**Two destinations are refused, as values rather than as exceptions**, in the
same style as the rest of `SaveOutcome`:

* `SaveFailure::AlreadyExists` — something is already at that path and the caller
  did not pass `overwrite`. The UI asks and calls again saying yes. Save As is
  untouched by this: it has always replaced what the chooser was pointed at, and
  changing that is a separate question from F9.
* `SaveFailure::ScriptIsOpen` — the destination is a file this application has
  open, and `overwrite` does not lift it. Paths are compared as written and then
  canonicalised, so a symlinked directory cannot spell an open script into a
  different name.

### Alternatives considered

**Leave the overwrite question to the file chooser.** A dialog is where the
question is *asked*, but a rule that lives only in a dialog is a rule the next
dialog does not have. The core is the layer that can make a silent overwrite
impossible rather than merely unlikely, and it is the layer with a test.

**Allow exporting over an open script, since it is our own file.** It is not this
session's file, and that is the trouble: the other session's journal has a `base`
of the bytes being replaced, so after such a write `journal::verify` would refuse
the recovery — the writer's crash journal would be quietly useless, which §1.2
calls a P0. The same argument applies to exporting over the script being edited.
There is already a verb for writing this script's file, and it is Save As.

**Bracket the export in `OwnWrites` like every other write.** Unnecessary once
open scripts are refused: an open script is the only thing the watcher watches,
so an export can never produce an event that reaches Dart. Bracketing it anyway
would add a suppression record for a path nothing is listening to, and a record
left in flight is the one failure mode `OwnWrite` exists to avoid (ADR 0028).

**Mark the document saved after an export.** Tempting — the bytes are on a disk
somewhere — and wrong: the file the writer is editing does not have them. The
dirty flag is about *this* script's file, and any other reading of it ends with
the editor claiming work is safe that no file the session knows about holds.

### Consequences

* `doc_export_fountain(handle, path, overwrite)` is the third write verb in
  `api/files.rs`, beside `doc_save`/`doc_autosave` and `doc_save_as`. Dart reaches
  it through `DocumentCore.exportFountain`, which is what Phase 7's export command
  must call; `saveAs` is what Save As calls, and the two are not interchangeable.
* `SaveFailure` grew two variants, so every exhaustive `switch` over it in Dart
  gained an arm — `save_dialogs.dart` and `save_status.dart`. Neither reaches a
  save; the sentences live beside the others rather than in a second table that
  could drift.
* An export takes no save lock. It writes a file no save writes, and holding up
  an autosave of the script for the duration of a copy would be paying for a
  conflict that cannot happen.
* The overwrite check is a `path.exists()` before the rename, so it races with
  anything else creating that file in the same instant. That is the race every
  file chooser has; what it buys is that the ordinary case cannot overwrite
  without having been asked.

### Tests and invariants

In `crates/bridge/src/api/files.rs`, written in pairs — the same question asked
of Save As and of export:

* `save_as_changes_the_active_path` and
  `save_as_rebinds_the_journal_and_the_library_entry`, beside
  `an_export_writes_the_expected_bytes` and
  `an_export_leaves_the_session_exactly_where_it_was` — which checks the path,
  the dirty flag, the script's own file, the journal's base and what it recovers
  to, the library entry, that nothing is left armed, and that nothing is
  suppressed.
* `an_export_refuses_to_overwrite_until_it_is_told_to`,
  `an_export_never_writes_a_script_that_is_open` (including through a symlinked
  directory), `a_failed_export_changes_nothing`,
  `an_export_with_nowhere_to_go_says_so`.

In `app/integration_test/persistence_test.dart`, against the real `.so`: *an
export writes a copy and Save As moves the session* — the generated binding
carrying the distinction, `overwrite` argument included.

Confirmed to fail first: with `doc_export_fountain` implemented as
`write_document(handle, Some(path), true)` — the F9 behaviour — four of the six
Rust tests fail; with the open-script refusal removed, one does; with the
overwrite check and the canonical comparison removed, two do.

---

## ADR 0030 — The completion popup names its gestures, and its rows are not click targets

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 5 (mid-project
remediation, Phase 9)
**Superseded by:** ADR 0041 for the popup's activation rule and its fixed
eight-row presentation; the decision that its rows are not click targets stands.

### Context

ADR 0017 settled which *key* accepts a completion: Tab takes the default, Enter
takes a candidate the writer moved to with Up or Down, and Enter otherwise
splits the block. It said nothing about the mouse, and the popup was built to
match — each row was a `Container` whose only pressable part was the pin button.

Phase 9's manual pass reported autocomplete as not working at all: "if it
suggests something and I press enter or click it nothing happens". Both halves
are explained. Enter splitting the block is ADR 0017 behaving exactly as
decided. Clicking did nothing because nothing was listening. What neither of
them explains is why the writer had to guess: the popup listed candidates and
said nothing about the one gesture that takes them.

### Decision

**The popup carries a footer naming its gestures** — `Tab accepts · ↑↓ then
Enter · Esc dismisses`. That is the repair for the reported defect.

**A click on a candidate does not accept it.** The rows stay labels, and a
pointer that lands on the popup goes on meaning what it has always meant on this
surface: place the caret in the text.

### Alternatives considered

**Make the rows click targets.** This was written, tested and rejected on the
evidence. The popup is positioned one line below the caret, floats over the
writer's own page, and — because `_refreshCompletions` runs on every caret move,
not only while typing — is showing far more of the time than a popup that waits
for a typed prefix. It is up to eight rows tall, which measured 344 px over a
566 px editor: opening any script whose first block is a scene heading puts a
six-candidate list of `INT.`/`EXT.`/`EST.` over the top of the page.

With the rows clickable, a click aimed at the text under that list writes a
scene prefix into the script instead of moving the caret. This is not a
hypothetical: three integration tests in `writing_test.dart` — all three whose
script begins with a scene heading — turned `INT. HOUSE - DAY` into
`EST.INT. HOUSE - DAY` on the ordinary tap their helper uses to focus the
surface, and the panel test lost its focus and its Find bar with it. Seven test
helpers across five files use that tap, which is a fair measure of how firmly
"clicking the surface places the caret" is this surface's contract.

Every other editor makes its suggestion list clickable, and that convention is
built on a popup that appears when you type. Ours appears when the caret moves.
Until that changes, a click cannot tell aim from accident, and §1.2 makes the
wrong guess a P0: it mutates the script.

**Accept on click only after the pointer has hovered the popup.** A writer
clicking the text under the popup has hovered it on the way. It separates the
test harness from the human, which is not the same as separating aim from
accident, and a rule that only holds in production is a rule with no test.

**Suppress the popup when there is no typed prefix, then make rows clickable.**
It would remove the hazard, and it would also remove Tab in an empty character
cue offering the cast — the gesture §7 exists for. Rejected as a bad trade made
for the sake of a gesture nobody asked for.

### Consequences

* The reported defect is fixed by the footer: the writer is told that Tab
  accepts, which they could not have known from the screen.
* The popup is one row taller. It is still positioned one line below the caret.
* `autocomplete_test.dart` pins both halves — *the popup says what accepts a
  candidate*, and *clicking a candidate does not write it into the document*,
  which is the invariant the rejected version broke.
* If a click gesture is wanted later, this record is the list of what it has to
  answer first, and `writing_test.dart` is the test that will say whether it did.
  The saved diff is not kept in the tree.

## ADR 0031 — A character extension is recognised by its letters, not its punctuation

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 5 (mid-project
remediation, Phase 9)

### Context

§7 says the extensions `(V.O.)`, `(O.S.)`, `(O.C.)`, `(CONT'D)` and `(SUBTITLE)`
are stripped for the entity index key and retained for display, so that `BOB` and
`BOB (V.O.)` are one character with one completion and one frequency count.

`normalize_character` matched those five spellings literally — case-insensitively,
but otherwise exactly. Phase 9's manual pass typed `BOB (O.S)`, which is the same
extension with one period missing, and got a second character: a phantom `BOB
(O.S)` in the completion list beside the real `BOB`, with the speeches divided
between them. `(VO)`, `(V.O)` and a word processor's `(CONT’D)` all did the same.
A test named `a_name_that_merely_resembles_an_extension_keeps_it` had pinned that
behaviour deliberately, on the reasoning that a near-miss might be a name.

### Decision

**The trailing parenthesised group is an extension when its letters and digits,
uppercased, spell one of `VO`, `OS`, `OC`, `CONTD`, `SUBTITLE`.** Case, periods,
spaces and the apostrophe — straight or typographic — are all ignored, because
they are what a writer varies. Anything else in parentheses is part of the name
and is kept: `(VOICE)`, `(JR)`, `(32)` and `(O S T)` are untouched.

Only the index *key* is affected. The cue is displayed, serialised and parsed
exactly as typed, so `BOB (O.S)` still reads `BOB (O.S)` on the page and in the
file.

### Alternatives considered

**Add the near-miss spellings to the table.** `(O.S)`, `(OS)`, `(O.S.)`, `(OS.)`
for each of five extensions, times an apostrophe variant, is a table nobody can
keep complete — and the one spelling left out is the one a writer uses.

**Keep exact matching and fix it in the UI instead.** Offering to merge two
characters is a feature; the writer here did not make two characters, they made
one and typed it twice.

**Ignore punctuation everywhere in a cue, not only in the trailing group.** Too
wide: `MRS. PEEL` and `MRS PEEL` are the same character to a reader, but the same
rule would also merge names that only look alike, and §7 asks for extension
normalisation, not name normalisation.

### Consequences

* `a_name_that_merely_resembles_an_extension_keeps_it` changed meaning and was
  rewritten around cases that are still kept, beside a new
  `an_extension_missing_its_punctuation_is_still_an_extension`. This is a
  deliberate behaviour change, not a weakened assertion.
* F11's rule holds: the split is `text`'s own byte index of the `(`, never a
  length measured on an uppercased copy, so `BOB (ſUBTıTLE)` still normalises
  without a char-boundary panic. Nothing on the path allocates.
* The match reads only the trailing group, so the cost does not grow with the
  length of the name.
* A character genuinely called `BOB (OS)` is now indexed as `BOB`. Nobody is
  called that.

---

## ADR 0032 — The PDF writer is ours, and it interprets emphasis without leaving a gap

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 7
**Superseded by:** ADR 0044 for the raw-marker alignment consequence and
ADR 0045 for sharing output emphasis with the preview. The PDF writer and
gap-free placement remain unchanged.

### Context

§Phase 7 asks for a PDF a production company can be sent, and §2.6 shortlisted
`printpdf` for the job. Everything §Phase 7 asks for beyond "put characters on a
page", though, is a statement about *bytes*: a fixed `/ID`, a timestamp that
obeys `SOURCE_DATE_EPOCH`, no dependence on hash-map iteration order, font
subsetting, and a SHA-256 a golden test pins. Those are properties of a writer,
not of a drawing API.

There was a second question underneath it. ADR 0019 made the PDF renderer the
only thing that interprets `*italic*`, and the paginator counts the markers as
columns while it decides where a line breaks. So when the renderer drops them,
something has to happen to the cells they occupied.

### Decision

**Write the PDF here.** `crates/render_pdf` is a TrueType subsetter, an sfnt
writer, a PDF object writer and a SHA-256, in about a thousand lines with no
dependency outside the workspace. Courier Prime is vendored — four faces and
`OFL.txt`, `include_bytes!`d — and embedded as a subsetted `CIDFontType2` with
`Identity-H` encoding and a `/ToUnicode` CMap, which is what makes the text
selectable and searchable. Nothing is compressed: a screenplay is text, the
streams are readable, and there is one less place for output to vary.

**Every glyph is declared 600/1000 em wide.** Courier Prime's own advance is
1228/2048 — 599.6 — and a viewer positions text by the widths in the font
dictionary. Declaring the real number would put the end of a sixty-column line a
third of a point off §5.2's grid.

**A row's runs are drawn one after another from the row's own left edge.** The
paginator decided the row and where it starts; the renderer draws what is left of
it with no gap where a marker was. A gap is not a screenplay.

### Alternatives considered

**`printpdf`.** A large tree, its own font subsetter, and a `/ID` and creation
date this crate would have to reach past it to fix. It would have written the
easy half and left the half §Phase 7 actually specifies.

**Leave the marker cells blank.** Strictly the most faithful reading of "the
paginator counted them", and it looks wrong: `He reads *quietly* and` prints with
a hole either side of the word. Rejected on sight of the first rendered page.

**Teach the paginator to measure printed width.** Fixes the alignment of an
emphasised transition or centred line as well as the gaps — and makes the
paginator interpret emphasis, which ADR 0019 reserved for exactly one place.

**Compress the content streams.** A `flate2` dependency to save perhaps 60% of
666 kB. Subsetting the font is where the weight was; the rest is the file being
inspectable.

### Consequences

* Same script, same setup, same `DocumentInfo` — same bytes. `crates/render_pdf/
  tests/golden.rs` pins the SHA-256 of every corpus file on both papers.
* `render` is pure; `creation_time` is the only function that reads anything
  outside its arguments and `render` does not call it.
* An emphasised transition or centred line ends a marker or two short of where an
  unemphasised one would, because the paginator aligned it while the markers
  still counted. That is the visible residue of ADR 0019's trade, and it is
  confined to right-aligned and centred elements — action and dialogue, where
  emphasis actually appears, are left-aligned and unaffected.
* Four faces are vendored but only the ones a script uses are embedded, so an
  unemphasised screenplay carries one.
* A character outside the Basic Multilingual Plane has no glyph in Courier Prime
  and prints as `.notdef`. It is in the file, it is in the editor, and it does
  not stop an export.

### Tests and invariants

* `crates/render_pdf/tests/golden.rs` — the committed hashes, and that two
  different scripts get two different `/ID`s.
* `crates/render_pdf/tests/text_extraction.rs` — `pdftotext` reads the page in
  order, with no marker in it and non-ASCII intact.
* `crates/render_pdf/tests/export_is_fast_enough.rs` — §Phase 7's 1000 ms budget,
  and that subsetting keeps a 120-page export sendable.
* `sfnt.rs`'s own tests re-parse a subset as a font file, which is the cheapest
  strong check that its tables, offsets and checksums line up.

---

## ADR 0033 — A title-page edit is journalled like any other edit

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 7

**Superseded by:** ADR 0066 refines which entry a title-field edit addresses.

### Context

`EditCommand::SetTitlePage` has existed in `document` since Phase 1 and had no
caller until Phase 7 made the title page editable. The crash journal records a
`Patch`, and a `Patch` was a list of blocks: an edit that changes only the title
page produces an empty one. So the first version of the title-page editor could
lose a draft date typed thirty seconds before the power went, while losing none
of the dialogue typed thirty seconds before that.

§1.2 does not grade user text by which part of the document it is in.

### Decision

**`Patch` carries an optional title page**, whole rather than as a delta, and
`Document::replay` applies it. The journal record gains an optional `title` field
that is written only on the edits that changed it, so an ordinary keystroke's
line is exactly as long as it was before Phase 7 and a journal written by an
earlier build still reads.

**One field per call, one undo step per call.** `doc_set_title_field` takes a key
and a value; an empty value removes the field, and setting a field to what it
already holds is not an edit at all — the editor rebuilds its form as the writer
types, and a form that re-sent every field would fill the undo stack with edits
that did nothing.

**Undo and redo always record it.** An `EditResult` does not say whether the step
just taken was a title-page one, and the cost of always saying is nine short
strings on a line a writer produces by pressing a key on purpose.

### Alternatives considered

**A field on `EditResult`.** Threading `title_page_changed` through every
construction site of a type six modules build, to avoid one `bool` at one call
site in the bridge.

**Let the autosave cover it.** It does, two seconds later. §Phase 4's exit
criterion is "never lost a keystroke beyond the last one", and a title page is
made of keystrokes.

**A separate title-page journal.** Two files to keep in step, two recoveries to
reconcile, for a feature that is nine strings.

### Consequences

* `Patch::is_empty` accounts for the title page, and the bridge skips a journal
  line for an edit that changed nothing — which is what makes the "setting a
  field to what it holds is not an edit" rule true on disk as well as on screen.
* The keys a journal records keep the spelling they were written with, so a
  writer's own `Revision Colour:` survives a crash as well as it survives a save.
* `outcome_with_title_page` is a second entry point beside `outcome`, and the
  rule in `AGENTS.md` still holds: every mutation ends in one of them.

### Tests and invariants

* `crates/bridge/src/api/files.rs::a_title_page_edit_survives_a_crash_like_any_other_edit`
  — what the journal recovers is what the writer can see, through an edit, a
  title-page change, another edit, and two undos.
* `crates/document/src/document.rs::replaying_a_patch_restores_a_title_page_the_file_never_got`
* `crates/storage/src/journal.rs::a_title_page_edit_is_recorded_and_read_back_whole`
  and `an_ordinary_keystroke_line_says_nothing_about_the_title_page`.

---

## ADR 0034 — Calibration: the grid is Final Draft's, and the references disagree with each other

**Date:** 2026-07-26 · **Status:** accepted · **Phase:** 7 · **Satisfies:** §5.5
**Superseded by:** ADR 0046 refines lyric spacing only.

### Context

§5.2 gives an element table and says of it: "These values are starting points,
not gospel. Different houses differ by a tenth of an inch. Put every one of them
in a single `layout::metrics` module as named constants with a source comment,
then calibrate against reference PDFs (see §5.5) before Phase 7 exits." §5.5
asks for the same short script produced in a known-good reference tool, exported,
and overlaid.

### The measurement

`testdata/`-shaped calibration script — a scene heading, an action paragraph, a
cue with a parenthetical and a line of dialogue, a transition and a centred line —
exported from three tools on US Letter and measured with `pdftotext -bbox`, which
reports each word's bounding box in points from the paper's top-left.

| Element | Slugline | afterwriting 1.17.3 | screenplain 0.12.0 |
| --- | --- | --- | --- |
| Scene heading, left | 108.0 pt (1.5″) | 108.0 (1.5″) | 108.0 (1.5″) |
| Action, left | 108.0 (1.5″) | 108.0 (1.5″) | 108.0 (1.5″) |
| Dialogue, left | 180.0 (2.5″) | 180.0 (2.5″) | 172.8 (2.4″) |
| Parenthetical, left | 223.2 (3.1″) | 216.0 (3.0″) | 201.6 (2.8″) |
| Character, left | 266.4 (3.7″) | 252.0 (3.5″) | 244.8 (3.4″) |
| Transition, right | 540.0 (7.5″) | 547.2 (7.6″) | 547.2 (7.6″) |
| Centred, axis | 324.0 (4.5″) | 306.0 (4.25″) | 327.6 (4.55″) |
| Line pitch | 12.0 pt | 12.0 pt | 12.0 pt |
| First text row | 1″ from top | 1″ | 1″ |
| Page number | 0.5″ from top, right edge 7.5″ | — | — |

Reproduce it with `cargo run -p slugline_render_pdf --example dump -- script.fountain
ours.pdf`, `npx afterwriting --source script.fountain --pdf theirs.pdf --config
<(echo '{"print_profile":"usletter"}')`, and `screenplain --format pdf`.

### Decision

**Keep §5.2's table.** Its numbers are Final Draft's defaults — 3.7″ character,
3.1″ parenthetical, 2.5″ dialogue, 60 columns between 1.5″ and 7.5″ — and Final
Draft is the application a script sent to a production company is most likely to
be read in.

The two open-source references disagree with each other by more than either
disagrees with us, which is §5.2's "different houses differ by a tenth of an
inch" arriving exactly as predicted. Both right-align a transition to 7.6″, which
is their own 61-column text width rather than the 1.0″ right margin they each
declare; a 61-column line does not fit between 1.5″ and 7.5″.

**Centred text is centred on the text area**, at 4.5″, not on the paper at 4.25″.

**A scene heading at the top of a page keeps its one blank line** (§5.2), which
puts our first heading one row below afterwriting's. Both are on the same 12-point
rules; ours starts on the second of them.

### The exit criterion, honestly

§Phase 7's exit criterion is "a printed page overlaid on a reference-tool page
matches on every element indent". Overlaid on either reference, ours matches on
the left margin, the action and scene-heading indent, the line pitch, the
baseline grid and the paper; it matches afterwriting on dialogue too. It differs
on character and parenthetical by 0.2″ and 0.1″ — and the two references differ
from *each other* on those by 0.1″ and 0.2″. The criterion as written cannot be
satisfied against every reference at once, because the references do not satisfy
it against each other. What is satisfied is the criterion behind it: every
element of ours lands on the fixed grid at the position the house style §5.2
chose, and the deltas against two others are measured and written down above.

### Consequences

* `layout::metrics` is unchanged by calibration, and now says so.
* `crates/render_pdf/tests/element_indents.rs` pins each indent as measured out
  of the finished PDF — not out of `metrics` — so a future change to either the
  grid or the renderer has to be deliberate.
* If a house ever needs 3.5″ cues, it is a `PageConfig` field and a golden
  update, not a redesign: the indents already live in one module.
* Poppler — which is what both `evince` and `okular` render with — is covered
  automatically: `text_extraction.rs` reads the pages back through `pdftotext`,
  and the pages in this comparison were rasterised with `pdftoppm` and looked at.
  **Firefox and Chrome have not been opened on an export**, and neither has a
  printer. Both use the same `/ToUnicode` mechanism poppler does, so the risk is
  low and it is not zero; §Phase 11 packaging is where a printed page belongs.

---

## ADR 0035 — The navigator is a Rust semantic snapshot and a Dart interaction

**Status:** Accepted
**Date:** 2026-07-26
**Phase:** 8
**Superseded by:** ADR 0041 for treating the docked navigator as the expanded
state on narrow windows; below 900 px it is a temporary drawer that does not
overwrite the saved preference.
**Superseded by:** ADR 0058 for sections, synopsis attachment and actual scene
pagination metadata; its source-ordered outline replaces the scene-only list.

### Context

Phase 8 needs two related views of an open screenplay: scene headings in
document order, split into scene number, prefix, location and time of day; and
characters with occurrence counts. The character facts already live in
`document::EntityIndex`, which is updated from every edit patch. Scene-heading
recognition and Fountain's trailing `#12A#` syntax already live in Rust too.

The navigator also needs interaction state that does not belong in the core:
which tab and filtered row have keyboard focus, which visual row is at the top
of the fluid editor, and whether the sidebar is expanded. Sending a bridge call
for every arrow key or scroll pixel would put navigation bookkeeping on the
editing path. Re-parsing headings or normalising character names in Dart would
instead give Flutter a second opinion about screenplay semantics.

Phase 7 already assigned `Ctrl+P` to Preview and export. Phase 8 asks for a
"`Ctrl+P`-style" quick jump, which describes the searchable quick-open gesture;
it cannot also own the literal key without taking a shipped command away.

### Decision

`doc_navigator` returns one read-only `NavigatorView` from the actor:

* scenes are the document's `SceneHeading` blocks in document order;
  `document::scene_heading_parts` uses Fountain's shared
  `split_scene_number` rule and names the remaining prefix, location and time;
* characters and their counts come from the session's incrementally maintained
  `EntityIndex`; their stable cue block ids are returned in document order so a
  click can jump without another semantic query;
* a stale handle returns an empty snapshot, as the other read-only document
  views do.

Dart reads the snapshot when the page opens and, while the sidebar is visible,
120 ms after a document revision. Selection-only notifications do not refresh
it. Dart maps the returned scene ids over its existing block list so caret and
scroll changes can highlight a scene without crossing the bridge.

The sidebar owns filtering, the Scenes/Characters tabs, arrow-key selection and
Enter. A jump sets a collapsed caret at the returned stable block id; the
existing editor-surface listener scrolls that caret into view. `Ctrl+J` expands
the sidebar and focuses the scene filter. `Ctrl+P` remains Preview and export.

The expanded state is the `navigator_visible` global preference. It is read with
the other preferences at document adoption and written through the existing
atomic preferences path. The collapsed editor keeps a visible button back to
the navigator.

Drag-and-drop scene reordering remains out of scope exactly as Phase 8 says.

### Consequences

* Dart displays screenplay facts but does not derive them. The widget-test
  `FakeCore` receives explicit `NavigatorView` data and performs no parsing.
* Typing pays the entity index's existing incremental update. Snapshot refresh
  is debounced in Dart and never runs for caret motion alone.
* Authored Fountain scene numbers appear when present; no number is invented for
  an unnumbered heading.
* `crates/document/src/entities.rs` tests scene splitting and index-derived
  counts, `crates/bridge/src/api/doc.rs` tests the complete snapshot, and
  `app/test/editor/navigator_test.dart` covers the Phase 8 gestures and
  highlighting. `app/integration_test/writing_test.dart` proves the real Rust
  snapshot drives the Flutter navigator.

---

## ADR 0036 — Spell checking is an immutable Rust snapshot and a Dart overlay

**Status:** Accepted
**Date:** 2026-07-27
**Phase:** 9

### Context

Spell checking has two very different costs. Loading a Hunspell dictionary and
checking thousands of words must not enter the actor or the keystroke path;
deciding which stable document block and which screenplay entities a result
belongs to must not be reimplemented in Dart. The editor also needs a 300 ms
pause after typing, paint-only underlines and context-menu interaction, none of
which belongs in a timer-free Rust core.

Personal and project words are user data. They need the same atomic-write
guarantee as every other Slugline file, while a missing or damaged sidecar must
never make its Fountain file unusable. Most importantly, a spelling result is
advice: it must not become an edit unless the writer chooses a replacement.

### Decision

`crates/spell` is a pure string-checking layer around `spellbook`. It discovers
paired `.aff` and `.dic` files in conventional Linux Hunspell directories,
loads an immutable dictionary, tokenises Unicode words, and returns UTF-8 byte
ranges. It knows nothing about documents or the bridge.

The bridge owns the selected dictionary behind an `Arc`, the personal words,
and per-session project words and ignores. A block request briefly asks the
actor for immutable text and entity-index data, runs the checker off the actor,
then commits the result only if the exact cache key still matches. That key
covers block text, accepted words, and global/session spelling revisions, so an
edit, language change, dictionary addition or ignore cannot reuse stale work.
Only `offsets.rs` converts the returned byte ranges to UTF-16.

Dart owns the 300 ms edit debounce. Startup and full-document rechecks are
asynchronous per-block sweeps whose repaint notifications are batched and yield
between batches. The editor paints red waves and opens the menu; Rust supplies
suggestions and records ignores/dictionary additions. Only Replace constructs
an `EditCommand::ReplaceText`.

The personal word list is
`$XDG_CONFIG_HOME/slugline/personal.dic`. A script at `name.fountain` uses
`name.fountain.dic` beside it. Both are sorted, readable word lists written
through `storage::atomic::save_atomically`; missing, unreadable or malformed
lines are treated as an empty or partial overlay. Character names and scene
locations are accepted from the session's existing `EntityIndex`.

No dictionary is bundled and no network fallback exists. If no installed pair
can be loaded, the language selector says which system paths were searched and
the editor remains fully usable. The enabled flag and selected installed
language live in the existing preferences JSON.

### Alternatives considered

**Check in Dart.** This would either add a second native dictionary stack or
move screenplay/entity semantics across the ownership boundary.

**Check the whole document after each edit.** Even on a worker this creates
avoidable work and late results. Stable block ids and a cache already give the
smaller unit.

**Put the debounce in Rust.** The core has no timers by construction; scheduling
repaints and reacting to keystrokes are Flutter responsibilities.

**Teach Hunspell each accepted word.** Personal, project, ignore and entity
overlays change independently. Keeping them in the cache key avoids cloning or
mutating the multi-megabyte dictionary.

**Correct from the best suggestion automatically.** A spell checker cannot
know a writer's invented name or deliberate word. This would violate Phase 9's
central invariant.

### Consequences

* Startup pays dictionary parsing once. Block requests share that immutable
  value and cached answers, and stale worker results are discarded.
* Ignore Once is tied to the exact block, text fingerprint and UTF-8 range;
  Ignore All lasts for the session. Personal and project additions persist.
* The project sidecar does not participate in opening, saving or serialising
  the screenplay, so deleting it loses convenience and no script text.
* `crates/bridge/src/api/spellcheck_never_modifies.rs` exercises every
  non-replacement surface and proves source and dirty state are unchanged.
  `app/test/editor/spell_check_test.dart` proves paint-only underlines, the
  debounce, every menu action and an asynchronous 120-page/3,000-block sweep.
  `crates/spell/src/lib.rs` proves discovery, checking, token ranges and tolerant
  word-list persistence.

---

## ADR 0037 — Preferences split display policy from screenplay output

**Status:** Accepted
**Date:** 2026-07-27
**Phase:** 10
**Superseded by:** ADR 0052 for the retained in-app chooser only.

### Context

Phase 10 puts many choices in one settings surface, but only two of them may
affect screenplay geometry: paper size and scene-number gutters. Theme, editor
text size and window chrome are presentation. Autosave is a Dart-owned clock.
PDF font choice changes glyph shapes but must not become a second pagination
input. These distinctions need to survive hand-edited preference files and live
changes while a script is open.

The phase also revisits the custom file chooser from ADR 0015. The native
Flutter Linux selector still brings an HTTP client into the release dependency
graph, conflicting with the build-time zero-network proof. The existing chooser
already provides the required file workflow and can select a directory without
that dependency.

### Decision

Preferences are tolerant, readable JSON at
`$XDG_CONFIG_HOME/slugline/prefs.json`, written atomically. On first launch after
an older build, `preferences.json` is read and copied to the new path; the old
file is left as a harmless fallback. Enum-like strings are validated, numeric
retention and timer values are bounded, and unknown fields remain forward
compatible.

Dart applies light, dark or system theme mode, editor text size and
distraction-free chrome immediately. Autosave timers are reconfigured in place.
F11 also asks the GTK runner to enter or leave actual full screen through one
small method channel. F1 opens the in-app copy of the keyboard map.

Rust remains the owner of output defaults. Explicit and automatic saves count
pages with the preferred paper and scene-number gutters, and preview/export
opens with that same setup. A selected TrueType system face is read off the
actor and embedded by `render_pdf`; its widths are declared on the fixed
screenplay grid, and the UI warns that a non-standard face may not visually fit
that grid. With only one selected face, PDF fill-and-stroke and matrix shear
preserve bold and italic emphasis without guessing sibling font paths.

New scripts start with a title page named from the chosen file and one editable
scene heading. The library empty state explains Fountain ownership and offers
both Create and Open. The dependency-free chooser is retained and gains an
explicit directory-selection mode for backup location.

The `Ctrl+digit` element map remains stable for 1.0. The earlier forward note
in `docs/KEYMAP.md` that Phase 10 might make it configurable was not a SPEC
requirement and would add another way for the shortcut sheet and element table
to disagree.

### Consequences

* `crates/bridge/src/api/appearance_prefs_dont_affect_pagination.rs` changes
  every appearance-only value and compares the pagination dump byte-for-byte.
* The saved page count, preview and PDF all use Rust `PageConfig`; editor zoom
  changes only the fluid custom surface.
* A malformed system font reports an export failure rather than panicking the
  process. Courier Prime remains the deterministic default.
* Widget tests cover live autosave reconfiguration, settings round-trips,
  F1/F11/zoom keys, output defaults, focus-mode chrome and Escape dismissal,
  including blocking failure dialogs that remain non-click-away.
* No dependency was added, and the zero-network packaging proof remains
  straightforward.

## ADR 0038 — The save path checks the file it is replacing; the watcher only asks early

**Status:** Accepted
**Date:** 2026-07-27
**Phase:** Post-Phase 10 refinement

**Superseded by:** ADR 0068 for managed project workflows.

### Context

§Phase 4's external-modification rule was implemented entirely around the file
watcher: `notify` reported that another program had written an open script, Dart
asked `doc_external_change`, and the writer chose. A save asked nothing at all —
it serialised the document and renamed it over whatever was there.

That made the watcher the only thing standing between an autosave and somebody
else's edit, and the watcher is allowed not to be there. `FileWatcher::new` was
reduced to `.ok()` in `api::files::init` and every per-file `watcher.watch` to a
`let _`, so a kernel without inotify, an exhausted `max_user_watches`, or a
filesystem the backend cannot watch all produced a core that looked exactly like
a working one and silently replaced external edits. The NFS caveat in
`storage::watch` was the same hole, already written down and not treated as one.
ADR 0024 and ADR 0028 had made the watcher *precise* about its own writes;
neither made it *present*.

### Decision

The check moves to where the overwrite happens, and the watcher keeps only the
job it can actually do.

`storage::watch::DiskState` records what a file held when this application last
read or wrote it: one `stat` fingerprint and a 64-bit hash of the contents.
Every path that establishes a session's file records it — open, save, Save As,
reload, restore from backup, accepted recovery, and the external-change check
when it finds the file identical to the document. `write_document` compares it
against the file immediately before replacing it, off the actor and under the
session's save claim.

The comparison has four answers. `Unchanged` is one cached `stat` and is what
every save of every quiet session costs. `Restamped` — new inode or timestamps,
identical bytes — proceeds silently, because `touch` and a `git checkout` that
restored the same text are not edits anybody has to decide about. `Unreadable`
proceeds too: a deleted file has nothing to preserve, and a refusal there would
be one the writer could not resolve, since the prompt that follows a refusal
reads the file as well. `Changed` refuses with `SaveFailure::ChangedOnDisk` and
emits the same `CoreEvent::FileChangedOnDisk` the watcher would have pushed, so
one Dart path handles both sources.

"Keep mine" answers that refusal through a new `doc_accept_disk_state`, which
records what the file holds *now*. The writer's next save may replace the
version they were shown and nothing later than it.

A Save As is exempt. Its destination was named through a chooser that has
already asked about replacing what is there (ADR 0029), and refusing a path
somebody just typed would answer a question with the question.

The watch failure itself is no longer discarded. `watch` marks the session
`watch_broken` and pushes `CoreEvent::ExternalWatchUnavailable` once, exactly as
`restart_journal` reports a journal it could not start; `doc_watch_state` exposes
it and the status line says "external changes not watched" for the rest of the
session, in every state including a failure.

### Consequences

* External-change protection no longer depends on a feature the machine is
  entitled not to provide. On a core with no watcher at all, an autosave over
  somebody else's edit is refused rather than silently performed — which is what
  `crates/bridge/src/api/files.rs`'s new tests run against, since the bridge test
  fixture has always installed `watcher: None`.
* The watcher is now what it should have been: promptness. Losing it costs a
  warning, not a guarantee, and the writer is told which one they have.
* One `stat` per save in the ordinary case, and one whole-file read only when
  something really did touch the file since we wrote it.
* The content hash is 64-bit and never persisted, so a comparison can in
  principle collide and let an external edit be overwritten. Holding a second
  copy of every open script to avoid that costs half a megabyte per session for
  a probability far below the disk errors the atomic save already accepts.
* A writer who dismisses the external-change prompt without deciding will have
  their next save refused again. That is the intended shape: the refusal stands
  until somebody answers it, and the status line says so meanwhile.

---

## ADR 0039 — The release build unwinds; `panic = "abort"` is superseded

**Status:** Accepted
**Date:** 2026-07-27
**Phase:** 11 — Packaging & 1.0

### Context

§Phase 11's release checklist asks for `panic = "abort"`, alongside LTO,
`codegen-units = 1` and stripped symbols. The other three are in
`[profile.release]`. The fourth is not, and has not been since the bridge was
written: `Cargo.toml` says `panic = "unwind"` with a one-line comment.

This was never decided, only done, and a checklist item contradicted by a
comment is exactly the kind of thing that gets "fixed" by someone tidying up.
Shipping 1.0 with the divergence undocumented is how a deliberate choice becomes
an accident.

The reason it is `unwind` is `flutter_rust_bridge`. Every generated wire function
wraps its call in `catch_unwind` and turns a Rust panic into a Dart exception.
With `panic = "abort"` there is nothing to catch: the panic aborts the process
immediately, `catch_unwind` never returns, and the machinery FRB generates for
the purpose is dead code.

What that costs is specific to this application. The Rust side owns the open
document, and the crash journal is what makes §1.2's "losing user text is a P0"
survivable — but the journal is only as good as the chance to *use* it. A panic
in, say, pagination or the PDF writer, on a worker thread, against a snapshot, is
not a reason to destroy the session that holds the writer's unsaved text. Under
`unwind` it becomes an exception on one call, the editor stays up, and the
writer can save. Under `abort` it is a `SIGABRT` with the document gone from
memory and recovery deferred to the next launch, which is the outcome the whole
of Phase 4 exists to avoid.

The usual argument for `abort` is that unwinding past FFI is undefined behaviour.
It does not apply here: FRB's `catch_unwind` sits *inside* the Rust frame, so no
panic crosses the boundary. It is caught before it can.

### Decision

**The release profile keeps `panic = "unwind"`, and §Phase 11's checklist item
is withdrawn rather than deferred.** The other three release settings stand and
are now all satisfied — the native runner is stripped by `-s` in
`app/linux/CMakeLists.txt`, which was the half of "stripped symbols" that had
been missed.

A panic remains a bug, not a control-flow mechanism. `parser_never_panics` and
the fuzz targets are what keep the core from relying on this.

### Consequences

* A panic in a bridge call surfaces in Dart as an exception on that call and the
  session survives with its journal intact. The writer can save their work,
  which is the only outcome §1.2 actually cares about.
* Binaries carry unwind tables. On this workspace that is a few tens of
  kilobytes against a 28 MiB bundle, well inside the 60 MiB budget.
* `abort` cannot be reinstated without breaking FRB's error translation. Anyone
  who wants it back needs an ADR superseding this one, and a different answer for
  what happens to unsaved text when the PDF writer hits an edge case.
* SPEC §Phase 11's line now reads as satisfied-by-exception, and points here.

---

## ADR 0040 — The fluid editor shows output page position in its status bar

**Status:** Accepted
**Date:** 2026-07-28
**Phase:** Post-1.0 refinement
**Supersedes:** ADR 0018 only where it excludes all page indication

### Context

ADR 0018 correctly kept page geometry out of the keystroke path and made the
editing surface continuous. In practice, a long-form writer still needs to know
roughly where the visible text lands in the paginated screenplay without
opening Preview after every edit. A scroll percentage or a Dart estimate would
disagree with the PDF precisely where page-break rules matter.

### Decision

The editor remains continuous: it gains no page boxes, breaks, gutters, or
layout decisions. Its bottom status bar shows `Page current of total`, sourced
from an asynchronous Rust `PaginationView` using the active output setup.

Dart maps the top visible editor row to the paginator's stable block id and
wrapped source-line index. The shared line-breaking contract makes that mapping
exact even when one block spans pages. Non-printing source blocks inherit the
preceding printable page. Pagination is debounced after document revisions and
runs on the existing snapshot worker path, never on the keystroke path.

### Consequences

* The writer gets live page orientation while retaining a fluid editor.
* Preview and PDF remain the only paginated renderings and the only owners of
  page boundaries and printed page numbers.
* The indicator can briefly show the last complete snapshot while a new
  pagination is running, matching Preview's existing stale-snapshot policy.


---

## ADR 0041 — Suggestions follow writing intent, and narrow windows keep the page wide

**Status:** Accepted
**Date:** 2026-09-06
**Supersedes:** ADR 0030's popup activation and fixed eight-row presentation;
ADR 0035's permanently docked navigator presentation on narrow windows.

**Superseded by:** ADR 0051 for Shift+Enter's editing meaning; the other
suggestion and navigator decisions stand.

### Context

Opening a scene heading displayed six prefix suggestions over the first page.
Moving through a script could leave stale suggestions taking the arrow keys.
The navigator and a fixed-width Find overlay also competed with the screenplay
in tiled windows. Small status and hint text was difficult to read.

### Decision

Opening, reloading, undoing and moving the caret leave suggestions closed.
Typing asks Rust for candidates; Ctrl+Space explicitly requests them, including
an empty character cue's cast. Cycling forward into an element also asks for
suggestions, preserving Action → Character → cast completion. Navigation,
selection and focus loss dismiss the popup. Unmodified Up/Down choose candidates;
Shift+Up/Down still extend the document selection. Tab accepts and Enter accepts
only after explicit navigation, as in ADR 0017. Candidate rows remain keyboard
only; pin controls retain their existing meaning.

The popup shows at most four rows, keeps the highlighted candidate visible,
and fits above or below the caret within the editor viewport. A separate
listenable builder updates the popup without rebuilding the editing surface.
All candidate content and replacement offsets continue to come from Rust.

Below 900 logical pixels the navigator is a temporary drawer, leaving the full
width available for writing. Opening it in a narrow window does not overwrite
the saved preference for a docked navigator in a wider window. Choosing a scene
or character returns focus to the script. Find is constrained to the editor's
available width and can scroll in short windows. Commands are exposed in the
toolbar as well as Ctrl+K; Ctrl+Space is listed in the palette and shortcut help.

Small chrome uses the existing 12-point type token, with tertiary text contrast
of at least 4.5:1 against the three chrome surfaces in both themes. The status
bar accommodates text scaling. Screenplay font size, layout and pagination
remain governed by their existing grid contracts.

### Verification

Widget tests cover quiet opening, typing and explicit suggestions, modified
arrow keys, navigating beyond the visible suggestion rows, retained Find
filters, and editor tools at 640, 800 and 1280 logical pixels with 100% and 150%
text scaling. Theme tests cover contrast. Linux integration tests exercise
actual Rust editing, the keyboard workflow, and the keystroke budget.

---

## ADR 0042 — Crash journals carry kernel ownership across publication

**Date:** 2026-10-06 · **Status:** accepted
**Supersedes:** ADR 0016's recovery sequence only where it omits journal ownership;
its replay, successor-before-removal and never-save-on-recovery rules remain.

### Context

Backlog S1 was reproduced with two release processes using throwaway `/tmp`
XDG roots: startup removed the first process's empty journal while that process
continued holding and appending to its unlinked inode. A non-empty journal
could likewise be offered, accepted or discarded while its writer was live.

### Decision

Every live `Journal` holds an exclusive, nonblocking `flock` on its open file
description for the session's lifetime. Recovery takes the same lock before
reading, retains it through cleanup or acceptance, and refuses a live owner.
Offers hold no long-lived reservation: accept and discard acquire ownership
again, so a stale dialog cannot act on another process's successor.

Acquisition compares the descriptor's device/inode with the current pathname.
A descriptor opened before a replacement cannot authorize operations on the
replacement. Recovery reads its locked descriptor; unlink happens before the
descriptor and lock are dropped.

Owned reload/rebase and `Journal::rebuild_at` retain the predecessor lock while
the existing atomic-save machinery writes and locks a successor temporary
inode. Replacement renames it over the predecessor and returns that exact
descriptor, already locked, for continued appends. Initial publication uses a
same-directory hard link followed by temporary-name removal: the complete,
locked inode becomes visible without clobbering a racing creator. No `.lock`
file, timer, PID registry or single-instance restriction is added.

Use `libc::flock` rather than `File::try_lock`: std requires Rust 1.89; this
Linux-only project keeps its Rust 1.82 floor. `libc` is already transitive and
becomes a documented direct dependency. The unsafe boundary is one syscall
with an owned descriptor and constant flags; append adds no lock or stat call.
The [Linux flock contract](https://man7.org/linux/man-pages/man2/flock.2.html)
releases the lock when the last descriptor for that open file description closes.

### Consequences and verification

- Locks are advisory; older Slugline builds or external tools that ignore them
  can still modify a journal. Lock errors fail closed. Unsupported hard links
  or filesystem locking leave the session explicitly unprotected, not silently
  unlocked. Opening the same script in a second process still reports recovery
  record unavailable rather than stealing its journal.
- `/proc/<pid>/fd` may show the removed temporary *name* after initial hard-link
  publication. That is not a lost journal: the final `.log` and descriptor have
  the same device/inode and a positive link count. The two-window release smoke
  verified both final journal paths survived and the first lock remained held.
- The bridge's real-process regression covers live empty and edited journals,
  direct/stale accept and discard, reload, save with an edit during the write,
  locked atomic replacement, and recovery after two successive `SIGKILL`s.
- Persistence tests serialize simulated session lifetimes around subprocess
  spawning. A fork can briefly inherit another test's descriptor before exec
  closes it, keeping its lock alive after the owning test drops its journal.
  A throwaway fork experiment confirmed this descriptor-lifetime behavior.

---

## ADR 0043 — Previous versions include bounded automatic snapshots

**Date:** 2026-10-06 · **Status:** accepted
**Supersedes:** ADR 0014's "Autosave writes no backup" consequence only.
Its Dart-owned timers, suppression rules and save-failure behavior remain.

**Superseded by:** ADR 0068 for managed project workflows.

### Context

A writer who relies entirely on autosave still needs previous versions, not
only the current file and a crash-recovery journal. Backlog S2's bridge smoke
reproduced no backup on opening and no backup after autosave, while an explicit
dirty save did create one. ADR 0014 avoided an unbounded stream of autosave
backups to protect older drafts, but withholding all autosave history makes the
manual-save habit a requirement for version recovery.

The same gap affects starting text changed outside Slugline while a script is
closed. Opening that file should preserve its on-disk starting point before
editing, including the first opening when the backup cache is absent. Explicit
save remains a deliberate version boundary even when autosave has already made
the document clean.

### Decision

Make snapshot decisions in the existing open/save worker paths, using the
newest backup's filename timestamp and a byte comparison with its contents:

* Opening snapshots the on-disk starting text when it differs from the newest
  backup. A missing cache establishes the first baseline. Opening ignores the
  age gate, including when the newest filename has a future timestamp.
* Autosave snapshots changed text only when the newest backup is at least ten
  minutes old. Any newer backup, including an explicit save or opening snapshot,
  restarts that eligibility window. A future timestamp delays eligibility until
  ten minutes after that timestamp; no correction state is added.
* With no newest backup, an automatic snapshot can establish the baseline.
  Missing or unreadable newest contents prompt a rescue snapshot when the age
  gate permits one, rather than treating an unavailable comparison as equality.
* Every explicit save attempts an unconditional snapshot, even for identical
  bytes or a clean `Ctrl+S` after autosave.

Snapshots use atomic writes and remain best effort. Backup-cache read, write or
retention failures do not fail an otherwise successful open or script save.
The script's own write failures still follow the existing save-error behavior.
There is no new core timer, per-document snapshot state, index or dependency;
Dart's existing autosave timers still decide when to request a save.

Retention is the union of the existing configurable newest N and daily M tiers
with a fixed hourly tier: keep the newest snapshot in each UTC-hour bucket for
the current hour and the previous 23 hours. Defaults remain N = 10 and M = 7;
no preference or retention field is added for the hourly tier.

### Consequences

* Autosave-only writers gain previous versions without making every autosave a
  backup. Byte-identical automatic saves and openings do not consume history.
* Opening preserves changed external starting text even if the script was not
  open when another program changed it. The first opening creates a baseline
  instead of requiring the writer to remember a manual save.
* Rapid explicit saves cannot evict all earlier hours from recent history.
  Retention is bounded by N + 24 + M copies before overlaps are removed. This
  is a time-bucket policy, not source tagging: the newest snapshot in an hour
  may replace an earlier autosnapshot or explicit snapshot in that same hour.
* A clock moved into the future can postpone automatic snapshots, but cannot
  prevent an opening baseline or an explicit-save snapshot. The policy derives
  eligibility from existing filenames rather than maintaining another clock.
* An unavailable cache can leave gaps in previous versions without preventing
  the writer from opening or saving the screenplay. Atomic publication avoids
  exposing a partially written snapshot.

---

## ADR 0044 — Layout aligns emphasis by printed width, without changing wraps

**Date:** 2026-10-06 · **Status:** accepted
**Historical:** ADR 0057 ends the raw-width wrapping consequence below; this record's printed-alignment decision remains in force.
**Supersedes:** ADR 0032's raw-marker alignment consequence and ADR 0019's
restriction of emphasis interpretation to the PDF renderer, for alignment only.
Literal editor display and raw-width wrapping remain unchanged.

### Context

Backlog F2's PDF dump reproduced `_**BRICK & STEEL**_` centred at column 26.5,
`> THE **END** <` at 27.5, and `> **FADE OUT:**` ending at 56 instead of 60.
Layout counted markup while choosing the left edge; PDF removed it while
drawing. Escaping backslashes caused the same disagreement.

### Decision

Layout measures printed width with `fountain::emphasis`'s existing tokenisation
and pairing rules. Paired markers and escaping backslashes take no printed
cells; unpaired markers and escaped characters remain printable. Width APIs
count tokens without allocating styled runs or copies of the printed text.

Body rows are measured together for each block, so a paired run crossing a wrap
is hidden on both rows. Title rows are measured individually, matching the PDF
renderer's existing title-row interpretation. This applies to centred title
fields and right-aligned draft dates, as well as centred body lines and
transitions. Left-aligned placement does not need emphasis measurement.

Only horizontal alignment changes. Line breaking still measures raw text under
`docs/LINE_BREAKING.md`; layout preserves row content, source-line identity and
page breaks. The renderer still copies layout coordinates and chooses faces;
it makes no wrapping or alignment decision. Integer grid columns put odd-width
centred text half a column left of the exact centre, within the F2 tolerance.

Add the direct workspace edge `layout -> fountain` rather than re-exporting a
syntax scanner through `document` or implementing another one in layout.
No external dependency is added.

### Verification

The PDF coordinate regressions measure finished text operators for centred
lines, titles, transitions and draft dates, including nested, escaped, unpaired
and cross-wrap emphasis. The actual dump executable and `pdftotext -bbox` show
the reported title and centred line at 29.5 and the transition ending at 60.

The corpus audit before regeneration found only two layout changes: the
emphasised titles in `05-title-page` and `reference-feature` move three columns
right. Their Letter and A4 PDF hashes are deliberately regenerated; all other
layout coordinates, row content, page breaks and PDF hashes stay unchanged.

---

## ADR 0045 — Preview and PDF share resolved emphasis and heading weight

**Date:** 2026-10-06 · **Status:** accepted
**Supersedes:** ADR 0019's restriction of styled emphasis to the PDF and
ADR 0032's private PDF-only paragraph interpretation.
**Extends:** ADR 0037's shared output defaults with scene-heading weight.
**Superseded by:** ADR 0047 extends resolved output with sung-dialogue italics.
**Refined by:** ADR 0057 resolves source emphasis before wrapping; title source
hard lines, rather than already wrapped output rows, define title pairing scopes.

### Context

F3 reproduced two disagreements: the preview painted raw paired markers in a
regular face, and the editor painted headings bold while the PDF printed them
regular. A preview labelled as printed output must not have its own
interpretation of Fountain.

### Decision

`render_pdf::emphasis_runs` exposes the PDF's existing paragraph interpretation.
Both PDF placement and bridge conversion consume its resolved text, bold,
italic and underline flags. Body rows pair across consecutive source rows of
one block, including page boundaries; `(MORE)` and continued cues are scanned
individually without interrupting that paragraph. Title rows pair individually.
Page numbers and scene-number gutters remain literal. Unpaired markers remain
printable and escapes follow the existing Fountain scanner.

`LayoutLineView` retains raw `content`, block identity, source-row index and
grid coordinates beside required resolved runs. Flutter paints those runs with
the bundled faces, advancing by printed Unicode scalars on the existing grid.
It does not parse markup, wrap text, or decide page breaks.

“Bold scene headings” is one persisted output preference, off by default.
Regular uppercase headings preserve Slugline's existing printed output and
default PDF hashes; bold is an explicit stylistic choice, not a new mandatory
screenplay rule. Modern examples also use bold headings, as
[Final Draft's element guide](https://www.finaldraft.com/blog/how-to-use-final-draft-script-elements)
shows, so the option supports that convention without changing old exports.
The editor, preview and PDF follow the same base heading weight. Output inline
bold remains additive, and italic headings become bold italic when enabled.
Scene-number gutters and other furniture do not inherit heading weight.

Layout carries a scene-heading flag on its content rows, rather than asking
the renderer to infer element kinds from uppercase text. `PageConfig` carries
weight so cached preview results describe their requested setup, not a later
preference value. Geometry is unchanged. The bridge names Fountain run types
through a direct workspace dependency, without re-exporting them through the
document model or adding an external package.

### Boundaries and verification

Editor inline markup remains literal and selectable; raw-width wrapping remains
the `docs/LINE_BREAKING.md` contract. Printed-width wrapping, styled editor
emphasis and shortcuts belong to X4, not this decision.

Bundled-font pixel comparisons prove marker-free italic preview painting,
mixed faces/underline and grid advancement, and both heading weights. The
editor regression observes actual painted styles and live repainting.
Rust tests cover cross-page pairing, independent titles, escapes, unpaired
markers, additive heading weight and finished PDF face operators without
moving coordinates. Native Linux UI verification changes the setting, paints
the real preview and exports through its PDF button; Poppler identifies italic
body text and regular/bold headings for the two settings. Default layout
goldens, PDF hashes and line-break fixtures remain unchanged.

---

## ADR 0046 — Consecutive lyric blocks share one leading blank

**Date:** 2026-10-06 · **Status:** accepted
**Refines:** ADR 0034 — lyric spacing in the retained element table only.

### Context

F4 reproduced consecutive Fountain lyric blocks at a 24-point pitch in an
exported PDF. Each block independently requested a blank row, so a verse was
double-spaced in the paginator and the editor.

### Decision

Keep the lyric indent, width and default leading blank. Suppress that blank
only when the immediately preceding document block is also a lyric. Source
blank separators are not independent document blocks and do not split a run;
another element kind does. Existing page-top suppression still applies.

Resolve spacing from current block order while preparing Rust layout and while
indexing editor rows. Do not change Fountain parsing or group lyrics into a new
element. The prepared spacing also feeds scene-heading lookahead, so its
two-content-row carry rule sees the same rows that will be placed.

Cached wraps remain reusable, but cached predecessor-dependent spacing is not
authoritative: every preparation resolves it again. An incremental slice begins
at a page top, where its first lyric needs no leading blank regardless of the
preceding page. Editor patch reindexing likewise updates untouched successors.

### Verification

Layout regressions cover three consecutive lyrics, an interlude that starts a
new run, use of the final row on a short page, and predecessor kind changes and
removal with cached wraps. Editor regressions cover the same run spacing and
patch-driven successor reindexing. Poppler rasterisation and bounding boxes of
the exported reproduction show a 12-point pitch. Layout goldens and PDF hashes
were deliberately regenerated but remained unchanged for the existing corpus.
The new lyric-run regressions cover the changed output; line breaking is unchanged.
The rebuilt Linux release was opened under isolated XDG roots and Xvfb;
screenshots of its editor and preview both show consecutive lyric rows.


---

## ADR 0047 — Sung hard lines remain dialogue and carry lyric output metadata

**Date:** 2026-10-06 · **Status:** accepted
**Extends:** ADR 0045 — marker-free, shared preview/PDF output for sung dialogue.

### Context

F5 reproduced a leading `~` under a character cue in printed dialogue. The
[Fountain reference](https://fountain.io/syntax/#lyrics) requires removal of a
lyric's tilde, but its [dialogue rule](https://fountain.io/syntax/#dialogue)
also makes any text after a cue or parenthetical dialogue. It does not settle
their overlap. The implementation comparison and pinned source links are in
`docs/BACKLOG.md`, F5: Screenplain preserves the tilde; Afterwriting removes
it and applies italic markup without changing the dialogue kind. FountainJS
supports lyric tokens within speeches after a spoken line or parenthetical,
but its direct-under-cue case currently throws.

### Decision

A sung hard line in a speech remains Dialogue. Retain its literal text, block
identity and provenance, rather than splitting it into a standalone Lyric and
losing its cue, speech break rules or canonical adjacency. This is output
interpretation, not a new block kind or automatic classification rule.

Fountain's `dialogue_lyric_marker_utf8` calls the existing marker recogniser
on a hard line's leading-whitespace-trimmed view and returns the actual marker
offset. Only a leading, unescaped `~` qualifies. Other element kinds and
mid-hard-line tildes remain literal.

Layout wraps once with source spans and caches lyric metadata with each row.
`LayoutLine::is_lyric` covers every wrap of the sung hard line;
`lyric_marker_utf8` identifies the single raw-row byte to omit, only on the row
that contains it. Source spans distinguish that marker from a literal tilde at
a later soft-wrap start, including expanded tabs and indentation that wraps
before the marker. Leading whitespace and raw row content remain intact.

The shared output resolver removes only the metadata-designated marker before
pairing inline emphasis, then adds italic to sung rows' resolved runs. Inline
bold and underline still compose, and explicit inline emphasis can still pair
across hard lines. Lyric base italics end at the source newline but survive
wraps and page breaks. Generated continuation cues and `(MORE)` do not inherit
them. Preview consumes the same runs as PDF; neither recognises lyric syntax.

No bridge API, bindings, editor metrics, speech grouping, page break rule or
line-breaking contract changes. The editor continues to show the literal tilde
and count its column, as it does inline emphasis markers. Standalone Lyric
blocks keep their existing style and run spacing.

### Verification

Regressions cover semantic marker boundaries, byte-exact source tiling,
tabs/Unicode whitespace and wrapped indentation, hard-newline style reset,
literal tildes at soft-wrap starts, speech continuation, cached full and
incremental pagination, composed emphasis, finished PDF faces and Poppler text
extraction. The PDF dump smoke exercises direct, mixed and two-page songs;
Poppler XML confirms italic sung output, bold-italic composition and regular
neighboring speech/continuation furniture. Rasterisation shows marker-free
italic lyrics at the dialogue indent.
The rebuilt Linux release preview was opened under isolated XDG roots and Xvfb;
its actual-size sheet shows the same italic, marker-free lyrics while the
editor behind it retains the source tildes. Default corpus layout goldens,
PDF hashes and line-break fixtures remain unchanged.
All seven native integration suites passed, including preview/PDF export and
the journalled keystroke budget (p99 4.78 ms).


---

## ADR 0048 — Page 1 is counted, and prints its number only when the page setup asks

**Date:** 2026-10-06 · **Status:** accepted
**Extends:** ADR 0037's shared output defaults with first-page numbering.

### Context

F6 reproduced `1.` at the top right of the first screenplay page, in the
committed layout goldens and in a PDF exported from the reference script.
`Paginator::push_page` wrote a page-number line for every page it closed. The
usual screenplay convention leaves the first page unnumbered: it is identified
by being first, and the count starts showing on page 2. Some readers and
templates do want the `1.`, so the convention is a default and not a rule.

Three things read a page's number and could each have grown an opinion: the
preview and the PDF, which copy the paginator's lines, and the editor's page
view, which paints its own sheet numbers as chrome.

### Decision

`PageConfig::number_first_page`, **off by default**, is the one place the choice
is made. It is stored as `number_first_page` beside paper size, scene numbers
and heading weight, and offered as “Number the first page” under Page defaults.

The paginator leaves the `LayoutLineKind::PageNumber` line off the page whose
number is 1 unless the option is on. Nothing else changes:

* `Page::number` is still `Some(1)`. The number is the page's place in the
  count — what the status bar, the checkpoints and the preview's keys use — and
  not a promise that it is printed. Only a page-number line says that. Making
  page 1 `None` instead would have made it indistinguishable from a title page.
* The exemption is keyed on the number, not on being first in a run. An
  incremental repagination restarts from a checkpoint's own number, so both
  paths reach the same answer, and an explicit page break does not start a
  second unnumbered page.
* The line sits in the top margin (row −3), so no row of script moves and the
  page count, every later number and every checkpoint are identical under
  either setting. With the option on, the output is byte-for-byte what it was
  before this record.
* It is an output setting, not an appearance preference: it changes the
  paginated snapshot, by exactly one line. It therefore takes part in
  `PageConfig` equality, so a committed pagination is never served for the
  other setting and a prior output for it is never reused as a prefix. A PDF's
  `/ID` is a digest of the layout dump and so already tells the two apart.

The preview and the PDF need no rule; they draw the lines they are given. The
editor's page view asks `PageIndicator.printsNumber`, which records which pages
of the snapshot carry a page-number line. It does not read the preference:
that would be a second copy of “page 1 is unnumbered unless…” in Dart, free to
drift from the paginator's. Continuous view keeps the gutter label beside each
page-break rule — that is the application counting the pages that begin there,
not a picture of the sheet, and page 1 never had one.

The export dialog carries the saved value and has no toggle of its own, as with
heading weight. A per-export override would let the PDF disagree with the
sheets the writer has been looking at, for a choice that is made once per
script at most.

Not chosen: dropping the number outright with no option. The backlog asks for
the option, and it costs one field to keep every existing printout
reproducible.

### Verification

`crates/layout/tests/page_numbers.rs` shows no page-number line on page 1 by
default and `1.` at the usual cell with the option on, on both papers, with
page 2 still `2.`, the remaining pages, checkpoints and script rows equal, an
explicit break not restarting the exemption, and an incremental edit on page 1
equal to a full pagination under both settings. Bridge tests cover the stored
preference reaching `PageConfig`, both setups being cached apart, and the dump
differing by exactly the one line. Widget tests cover the preference dialog,
the export dialog carrying the saved value, the preview drawing a number only
where a line exists, and page view painting a sheet number only where the
snapshot has one; removing the painter's question makes that test fail.

Layout goldens and PDF hashes were regenerated deliberately. Each of the twelve
goldens lost exactly its `-3 -> ( 58, "1.")` line under `PAGE 1`. All 22 PDF
hashes changed; with the option on, all 22 reproduce the previously committed
hashes exactly. Line-break fixtures are unchanged. A native test drives the real
Preferences dialog, paginates through the bridge and reads the exported PDF
back with Poppler under both settings.

---

## ADR 0049 — An incremental run resumes and stops only where the paginator recorded that it could

**Date:** 2026-10-06 · **Status:** accepted
**Refines:** ADR 0022 — what a checkpoint records, and where an incremental run
resumes and stops. Its fingerprints, its advisory hint and its fixed point stand.

### Context

F8 asked for the test ADR 0022 deferred: `repaginate` of an edited snapshot
against `paginate_snapshot` of the same snapshot. Written, it failed. Over the
corpus on short pages, 898 of 12,374 single-block edits gave pages a full
pagination does not. On the reference feature at US Letter, shortening the
paragraph page 5 begins with left the page count at 119 and a page break in the
wrong place — the defect the backlog item warned of, in the page view, the
preview, an exported PDF and the page count a save records.

Three things were wrong, and all three were in how reuse was licensed.

1. **The restart read the page, not the paginator.** A checkpoint counted as
   somewhere to resume if its first laid-out line was line 0 of a block and it
   carried no `(CONT'D)`: a statement about what the page looks like. Whether
   the paginator would begin that page there *again* depends on what it read to
   decide so — the element itself, which is carried over whole because of its
   own height; the rows a scene heading keeps with it; the whole of a speech.
   The engine accepted a checkpoint whose first block was the block edited. So
   a paragraph, a speech or a heading that had been carried over to page 5, 9,
   13… stayed there after an edit that made it fit on the page before, or
   stayed whole after one that let it split.
2. **The stop compared against a script that ended early.** To keep the pages
   after an edit, the engine laid out only the blocks up to the next checkpoint
   and compared the last row with the old page's. A scene heading at the foot
   of that range saw nothing under it and was left there; a lyric's place was
   decided without the lyric before it. And agreeing about the last row of a
   page is not agreeing about what begins the next.
3. **Inferring a clean start had holes.** A forced page with nothing on it was
   credited with the first block of the script, so an edit after two `===` in a
   row laid the whole script out again from that page: 22 pages for a script of
   14. A page that opens on a blank row above a paragraph taller than a page
   was resumed without the blank.

ADR 0022 says a prefix of pages "is retained only after the newly computed
output proves it byte-for-byte equal". The code never did that, and cannot: the
proof is laying the prefix out, which is the cost being avoided. What can be
had for nothing is a record of what those pages were made from.

### Decision

**The paginator records, as it lays a page out, whether an element began that
page and how far it had read by then. Reuse is licensed by that record and by
nothing worked out from the page afterwards.**

* A page is **begun by an element** when the element's first line is the page's
  first row and the page held nothing before it. That page and every page after
  it are then a function of the script from that element on, the page setup and
  the page number. `Paginator::add_row` records it at the moment it happens. A
  page that opens part-way through a paragraph, on a `(CONT'D)`, on a blank
  row, or with no rows at all, is not one.
* With it goes **`settled_blocks`**: how many leading blocks of the snapshot
  the paginator had read when the element began the page — the element, and
  whatever placing it looked ahead to. `blocks_read` is that account. A block or
  a forced break is decided by the blocks up to itself. A speech also took the
  block after it, which is how it learned its body ends. A scene heading reads
  as far as the rows it keeps with it. Running out of script reads all of it,
  blocks that are not laid out included.
* **Resuming.** From the latest checkpoint whose `settled_blocks` is no greater
  than the changed block's index, and otherwise from the top of the script. An
  edit at or beyond that mark cannot have changed anything the earlier pages,
  or the decision to begin this one, were made from. A checkpoint page whose
  own first element was edited is therefore never resumed from; the one before
  it is.
* **Stopping.** The run lays out the whole of the remaining script, by the
  rules a full pagination uses and over the same blocks — never a script cut
  short. It stops when an element beyond the changed block begins a checkpoint
  page that the previous output also records as begun by that element. The page
  index is the same, so the number is; from there the script is what it was.
  The pages after are kept, that page's checkpoint is taken from this run, and
  later ones stand.
* `PaginationCheckpoint` is now `page_index`, `page_number`, `start_block` and
  `settled_blocks`. `start_block_line` and `continued_character` are gone: they
  were the inference.
* Every block is still fingerprinted on every run, and anything but exactly the
  hinted block having changed is a full pagination, as ADR 0022 has it. That
  validation and the wrapping are now one pass over the blocks instead of two.
* What a full pagination returns is untouched. No layout golden and no PDF hash
  changed.

**For whoever changes the paginator: a rule that looks at anything beyond the
element it is placing must be counted in `blocks_read`.** The rule and its
account sit side by side in `paginate_flow`, and the differential test is what
notices an omission.

### Alternatives considered

**Tighten the old conditions** — require the changed block to come after the
checkpoint's first block, compare more of the last page. Each closes one case.
A heading's look-ahead reaches two elements on, a speech is as long as it is, a
lyric looks back one block, and a block that is not laid out can become one
that is. That is a second description of what the paginator depends on, kept
somewhere other than the paginator, which is how the first version went wrong.

**Prove the prefix by laying out a little more of it** — resume a checkpoint
early and compare. It moves the question back one checkpoint, where it is the
same question. Only the top of the script is safe without an argument.

**Drop the incremental path.** A full pagination of the reference feature is
4.8 ms in a release build against a budget of 5 ms for the incremental one, and
it grows with the script. `docs/BUDGETS.md` keeps both rows.

**Resume exactly at a page that follows a forced break**, whatever was edited
on it. Sound: such a page does not depend on its first element. Not done,
because it is one more case to argue for a construct few scripts contain, and
what it saves is resuming one checkpoint later.

### Consequences

* An edit inside the element a checkpoint page begins with, or inside what that
  element read, resumes one checkpoint earlier than before: up to eight pages
  laid out again instead of four. On the reference feature an incremental run
  went from 0.35 ms to 0.42 ms in a release build and stayed at 4.7 ms in a
  debug one, against budgets of 5 ms and 12 ms.
* The run stops more often than it did. In three of the cases the backlog item
  names — a block that grows a row, a heading pushed over a break, a dual
  partner that moves — the old engine had the pages right and laid everything
  after them out again; it now stops at the next checkpoint that begins as it
  did.
* An incremental result's checkpoints equal a full pagination's, and the test
  compares them. What a run may do next therefore does not depend on how many
  incremental runs came before it.
* A layout that fell back to the naive fill is never resumed from.
* `PaginationCheckpoint` changed shape. Nothing outside `crates/layout` read
  it; `CacheStats`, which does cross the bridge, did not change, so no binding
  was regenerated.

### Verification

`crates/layout/tests/incremental_differential.rs` compares pages, the title
page and checkpoints — never the page count alone — and counts the runs that
kept pages, so that it cannot pass by never taking the incremental path.

* Every single-block edit of every corpus file, tiled and set on pages of five
  and of eight rows: sixteen edits a block — the same height, taller, much
  taller, shorter, hard lines, the dual mark, and each of ten kinds — each then
  undone. 24,748 incremental runs, each against a full pagination from nothing.
* A walk of 160 cumulative edits per corpus file, with blocks inserted, removed
  and moved among them, so that incremental runs follow full ones and each
  other.
* The reference feature on US Letter and A4, edited at the blocks each
  checkpoint page begins with and the last block of the page before.
* Named cases on US Letter for the four the backlog item lists and for each
  failure above, each asserting the row that moved and the pages kept.

Against the engine as it was, thirteen of those nineteen tests fail on pages
that differ and three more on the count of pages kept. Reuse was then broken on
purpose seventeen ways, one at a time — resuming from a page whose first
element was the one edited, forgetting what a speech or a heading read, stopping
at a checkpoint page whatever began it, trusting the hint — and each made the
file fail.


---

## ADR 0050 — Release-process budgets observe the shipped window and measured quiet

**Date:** 2026-10-06 · **Status:** accepted · **Phase:** post-1.0, F9
**Extends:** ADR 0014 with an observation of idle wakeups; Dart still owns timers
and the actor still blocks on its channel.

### Context

Cold start, idle CPU and reference-script RSS had acceptance numbers and no
harness. A release-process baseline under Xvfb reproduced about 272–290 MiB RSS,
already above 250 MiB, and heavy startup work until roughly 12 seconds. The
process then sleeps, except for occasional engine cleanup and the existing
30-second status-age redraw. A fixed ten-second startup sleep can sample active
initialisation and call it idle. CPU ticks can also miss a frequent but cheap
poller entirely.

The first frame needs no new instrumentation: `first_frame_cb` in the GTK
runner shows the window on Flutter's first frame. A fresh no-argument launch
shows the library, and script adoption follows that first frame. The caret is
static. “Cold start to blinking cursor” cannot truthfully name that event.

### Decision

`tools/check_runtime_budgets.py` runs the built release bundle, using disposable
script copies and fresh XDG directories on every launch. It has no test-only
entry point in the application and changes no production source. CI runs it in
its own step, as do the release workflow and release preflight after building
the bundle. They install/check `xdotool`; the Dart integration-suite inventory
is unchanged. JSON output retains every sample and full process logs even on a
failure, and both workflows upload it even when the step fails.

* Startup is the wall-clock time immediately before spawning to a PID-owned
  visible window, found by `xdotool`. It includes fork/exec, query overhead and
  up to 5 ms of query spacing. The startup file is zero bytes; its journal is
  checked separately so a failed open cannot masquerade as a script launch.
  Best of five must be < 500 ms. This is first-frame process startup, not the
  editor-ready measurement or an evicted filesystem cache. ADR 0005's frame
  build measurement still owns keystroke rendering; startup includes engine
  initialisation and cannot be measured by that callback alone.
* Idle and RSS use three consecutive ten-second intervals in one fresh
  reference-script process. It waits for two consecutive seconds of zero
  process CPU ticks, zero voluntary context switches across all threads, and a
  stable thread set; a 60-second timeout fails rather than pretending that the
  process settled. X input focus is set
  directly (no window manager required), then read back before and after each
  ten-second interval. Best of three must have zero ticks, switches and thread
  changes. Fresh processes for all three intervals were rejected: they can
  reproduce the same late engine-thread cleanup phase every time; consecutive
  intervals move past it without a fixed startup sleep. Voluntary switches
  expose even a poller too cheap to consume a CPU tick; involuntary switches
  are scheduler preemption and are not charged as
  application wakeups. This interval is shorter than the permitted 30-second
  status refresh. Best of three admits one affected interval without granting
  repeated wakeups a small-percent allowance. It cannot detect a poller slower
  than the observation window and does not claim zero activity forever.
* RSS reads `VmRSS` before and after that interval, keeps the larger reading
  per interval and the best of three intervals. The original 250 MiB limit is
  retained for a real GPU desktop in the same harness's `--desktop` profile,
  and remains pending in manual gate 5. The Xvfb baseline exceeds it; no GPU
  session has determined how much is software-renderer overhead. Add a
  separate 320 MiB headless regression ceiling, deliberately with about 10%
  headroom above the observed range. The default software profile sets X11,
  scale 1, `LIBGL_ALWAYS_SOFTWARE=1` and `LP_NUM_THREADS=4` to reduce variation.
  A passing headless ceiling cannot close the desktop budget.

### Consequences

No core timer, startup marker, benchmark allocation or production polling is
added. The harness cleans up only disposable sessions by SIGTERM (SIGKILL if
necessary); that is not evidence about clean shutdown. The X display and
`xdotool` are harness prerequisites, not shipped dependencies.

The original startup limit is unchanged. Idle's literal percentage becomes an
observable no-wakeup interval that accounts for the existing status timer by
name; RSS gains a separate environment-specific ceiling, rather than silently
replacing the desktop figure. MiB states the units already used by the bundle
check. Best-of-N and the observation limits are recorded in the live table.

Acceptance includes deliberately delaying the runner's first-frame callback,
adding a cheap 10 ms GTK timer, and retaining a touched 192 MiB allocation, one
at a time. Each must fail its own budget against a rebuilt release bundle.
All injections are reverted and the clean bundle rebuilt before completion.

---

## ADR 0051 — Shift+Enter is a core-owned line break with its own undo transaction

**Date:** 2026-10-06 · **Status:** accepted · **Backlog:** W3
**Refines:** ADR 0017 and ADR 0041 for Shift+Enter's interaction with completion
acceptance. Plain Enter and Tab keep their existing behavior.

### Context

Enter splits elements, but Action, Dialogue and Note already accept embedded
newlines. A plain ReplaceText insertion would coalesce with typing around it;
a Dart kind table would duplicate `BlockKind::is_multiline`. A highlighted
completion must not take the new line-break gesture away from writing.

### Decision

Shift+Enter, including numpad Enter, and the palette's "Insert line break"
call `doc_line_break`. The bridge asks the earliest selected block's existing
`is_multiline` rule: it replaces the selection with a newline for multiline
kinds and runs the ordinary Enter plan otherwise. Selection direction does not
change which element receives the edit. Read-only content and invalid UTF-16
boundaries retain the core's normal refusals.

The bridge groups selection deletion and newline insertion into one isolated
undo transaction, then uses `inferring` to classify and journal its outcome.
Undo restores the original selection and source provenance; redo reapplies the
break. Typing before and after stays in separate transactions. No mutation or
screenplay-kind policy is added to Dart.

The Shift+Enter key case precedes completion acceptance, so it always edits.
Plain Enter still accepts a deliberately navigated suggestion. Newlines from
an input method continue through the surface's ordinary splitting path.

### Verification

Widget tests cover typing both lines, numpad Enter, selection replacement,
completion priority, undo/redo and palette focus. Bridge tests cover all
multiline and single-line kinds, Unicode boundaries, reversed cross-element
selections, refusal atomicity and typing isolation. A persistence test replays
the actual journal through break, undo and redo, then checks the saved bytes,
retaining untouched BOM/CRLF title and opaque content. Native writing cases
save and reopen Action, Dialogue and Note through the real core and filesystem.

---

## ADR 0052 — GTK owns local file selection; the core still authorizes replacement

**Date:** 2026-10-07 · **Status:** accepted · **Backlog:** W7
**Supersedes:** ADR 0015, and ADR 0037's retained in-app chooser decision only.

**Superseded by:** ADR 0068 for managed project workflows.

### Context

The in-app chooser starts at home, with no bookmarks, search, folder creation
or list keyboard navigation. Backlog W7 offers native GTK selection (A) or
building those features ourselves (B). The Linux runner already links GTK 3
and has a `slugline/window` method channel for full screen.

### Decision

Choose A: GTK's `GtkFileChooserDialog`, called directly from the runner, not
through `file_selector`. Reuse the toolkit already shipped, with no new Dart
or Rust dependency. B would retain a second file-browser implementation and
keyboard model to maintain without improving document safety.

`FileChooser.show` is an async Dart adapter, not a Flutter widget or fallback
browser. The runner shows a modal, transient dialog and completes the method
on response or destruction, without a nested `gtk_dialog_run`. Only one chooser
may be active. Cancellation returns null; platform failures are shown in Dart.

File modes use an extension filter with an All files choice; the font chooser
uses `.ttf`, exports use `.pdf` or `.fountain`, and backup preferences select a
directory. GTK owns navigation, search, bookmarks and folder creation. Selection
is local-only. An explicit folder takes precedence over the last accepted
folder remembered in runner memory, then home. New and Browse from the editor,
Save As, Rename and Export supply the current script's folder. No new preference,
cache or persisted path is introduced. A save name with no dot gains the
caller's extension before it is returned; an explicit extension is preserved.

Disable GTK overwrite confirmation. A chosen path is not permission to replace
its bytes: the core still refuses `AlreadyExists`, and Save As and Export
still use their one shared Replace dialog before retrying with `overwrite:
true`. `ScriptIsOpen` is never retried. New and Rename retain their existing
core behavior. `SavePathChooser` and `PathChooser` keep their injection contracts.

### Consequences

The old custom directory browser and its incidental widget assertions are
removed. Widget tests select or cancel through the method-channel seam; native
chooser interaction must also be exercised against the real runner, because a
mocked path cannot prove GTK behavior.

The zero-network requirement is unchanged. No selector plugin, HTTP client,
portal or remote-location chooser is added. `tools/check_no_network.sh` remains
the packaging smoke proof. GTK's appearance follows the system theme rather
than Slugline's Flutter theme.

### Verification

A throwaway native integration smoke exercised the real runner under Xvfb:
Open, extensionless Fountain/PDF save names, explicit suffix preservation,
an existing destination without a GTK overwrite prompt, TrueType selection,
directory selection and Escape cancellation. The script was removed after
passing. Its initial input driver retained GTK's selected-name suffix and
produced `.fountain.fountain`; selecting the complete entry and accepting its
completion corrected the driver without changing product code.

The release window was also exercised on native Wayland under Hyprland: New
created an extensionless choice as a real `.fountain` file; Save As selected an
occupied path, displayed only Slugline's confirmation, and wrote after Replace.
Closing the dialog preserved the editor; closing its parent with a chooser
active exited with status 0. Screenshot evidence is under `target/w7-*`.
The startup log included an OpenGL initial-size timeout warning; no duplicate
chooser-response or teardown warning was observed.

---

## ADR 0053 — The runner stops the engine before the process exits

**Date:** 2026-10-08 · **Status:** accepted · **Backlog:** B16
**Extends:** ADR 0050 with an observation of the shipped process's ordinary
close. Its budgets, and its SIGTERM cleanup of disposable sessions, are unchanged.

### Context

Closing the window could end the process with SIGSEGV after the session had
shut down cleanly: scripts saved, journals discarded, `AppExitResponse.exit`
returned. Every core has the same shape. The main thread is inside `exit()`,
running handlers and destructors; `io.flutter.raster` is still inside a GL call
— `glReadPixels`, `glTexSubImage2D`, a program link, a draw — and faults in
state those handlers have freed. Mesa registers such handlers itself: one
destroys the table `_mesa_format_from_array_format` searches, another joins
its worker queues.

Flutter's Linux embedder is why a frame is still being drawn. `FlView` stops
the window's `delete-event`, asks Dart through `System.requestAppExit`, then
detaches the window from the application and calls `g_application_quit()`.
Nothing destroys the window or stops the engine, so `g_application_run()`
returns and `main()` goes into `exit()` with the engine's threads running.
Whether the process survives is whether a frame happens to be in flight.

It is not Save, the document or the Rust core. On the installed build under
Xvfb a close with the window at rest was clean 19 times in 19. A close while
the library slid in after Ctrl+W, a dialog faded in over the script or focus
moved through the library ended in SIGSEGV 16 times in 30, with and without a
Save, and with no script ever opened. The same engine binary under the stock
`flutter create` runner, showing only a spinner, died 3 times in 8. On the
owner's Hyprland session, on Intel's hardware driver rather than a software
rasteriser, the installed build died 2 times in 7. Flutter's `master` has the same template and the same
`fl_view_dispose`; there is no upstream fix to adopt.

### Decision

`my_application_shutdown` disposes the engine: `g_object_run_dispose` on the
`FlEngine` the view owns, held by the runner as a weak pointer. `FlEngine`'s
dispose is where the embedder calls `FlutterEngineShutdown`, which joins the
UI, raster and IO threads and the Dart VM's before it returns. The window and
its view are left exactly as Flutter leaves them. `exit()` then runs every
handler it always ran, with nothing left to race them.

Three alternatives were measured or considered and rejected.

*Destroying the window in shutdown.* The ordinary GTK answer does not reach
`FlutterEngineShutdown`: `fl_view_dispose` first asks the engine to remove the
view, and that request's completion holds an engine reference until a main-loop
iteration that never comes after a quit. It also frees the view's compositor —
framebuffer, pixel buffer, frame mutex — while the raster thread may be
presenting into it. In the stock runner, three variants (destroy; then drain
the main context; then block until the engine is finalized) failed 3 times in
24: two SIGSEGV and one abort in `g_mutex_clear` on the locked frame mutex.

*`_exit()` after `g_application_run()`.* It would stop the crash by skipping
every exit handler in the process, with the engine's threads still mid-frame
when the kernel takes them. That is a forced termination reported as status 0,
and the item required an ordinary one.

*Waiting.* Dart has no signal for "the raster thread has finished", and a pause
long enough for an animation to end is a clock that hides the race for exactly
the frames it was tuned on.

Disposing an object the runner does not implement is the cost. It is
acceptable because nothing uses the engine afterwards: the main loop has
stopped, the view is never drawn or disposed again, and the process is on its
way out. An engine already finalized by some other route has cleared the weak
pointer, and there is nothing to do.

### Consequences

At `exit()` the installed build had 45 threads, among them `io.flutter.raster`,
`io.flutter.io`, three `io.worker`s and the Dart VM's. The corrected build has
38 and none of those. What remains is parked: GLib's, Pango's, Mesa's own
workers, and the core's actor, pool, watcher and disk threads. A core thread
that finishes a job after the VM is gone posts to a port map that answers
`false` — read in the pinned VM's `PortMap::PostMessage`, and exercised by ten
closes during startup with pagination and the library scan still running. The
bridge exposes no opaque Rust object for the VM to finalize on its way down.

Shutting the engine down took 1.3–5.2 ms in the stock runner. Close-to-exit
time is unchanged within the harness's resolution on both display servers.

The decision rests on `FlEngine`'s dispose being its shutdown, which has been
true of every embedder this project has shipped and is not a documented
contract. `tools/check_clean_close.py` is what notices if that changes: run it
on every Flutter upgrade, and treat a failure there as this record's decision
needing to be made again rather than as a flaky test.

### Verification

`tools/check_clean_close.py` drives the shipped release bundle under Xvfb, in
CI's flutter job and the release workflow. Each run types an edit, saves,
presses Ctrl+W and closes while the library slides in; reopens, edits, saves
and closes while the shortcuts dialog fades in; then closes the library while
focus moves through it. The close is a `WM_DELETE_WINDOW`, not `XDestroyWindow`.
Every process must exit zero by itself, and the final bytes prove the reopened
editor held the first save. Five runs are fifteen closes. Against the
uncorrected build the same command failed four invocations in four, once at
each of its three closes.

It waits for a Save by the journal restarting from the saved text, not by the
bytes appearing: the session clears its dirty flag in that actor turn, and a
Ctrl+W before it is rightly answered with "Save changes?".

On the corrected bundle: 74 Xvfb closes across the variants that had failed
and their controls, 60 through the committed check, and 12 on the Hyprland
session, all exiting zero with no core recorded and exact bytes. The evidence,
cores, symbolised stacks, drivers and the stock-runner reproducer are under
`target/stabilization/b16/`.

---

## ADR 0054 — Dual dialogue is a disjoint pair with independent page continuations

**Date:** 2026-10-08 · **Status:** accepted · **Phase:** post-1.0, X1

### Context

Fountain already reads and writes a trailing `^` as a Character block's `dual`
flag. `SetDual` already validates, journals and undoes that flag without editing
the cue's text. The layout ignored it: the dual-dialogue corpus PDF put MARTHA
at `(266.4, 120)` and DEREK at `(266.4, 156)` in Poppler's top-origin points,
one speech below the other. There was no editor command.

Pairing, column widths and a pair's page-break behavior had no governing
decision. The fluid editor must still name the same wrapped source lines as
the paginator, even though it does not place simultaneous speeches side by
side or decide where pages end.

### Decision

**Pair adjacent speeches greedily, in source order, without overlap.** A speech
is a Character and its consecutive Dialogue/Parenthetical body. Both bodies
must contain at least one block, and the second cue must carry `dual`. Any
intervening source block, even a nonprinting note or section, interrupts the
pair. An unmatched marked cue prints as an ordinary speech; its flag survives
on disk. Thus `A, B^, C^` pairs A with B and leaves C ordinary. A first marked
cue may be the left partner of a following marked cue. Empty-text body blocks
count as body blocks, just as they do for ordinary dialogue.

This follows the corpus and Fountain's “with the preceding dialogue” meaning
without reaching back across action or silently constructing three columns.
Refusing an orphan would make opening an otherwise valid Fountain file fail;
printing it ordinarily preserves its words and a later edit can give it a
partner.

**Use two 28-cell measures separated by four cells inside the existing
60-cell text area.** All columns below are relative to that area's left edge:

| Kind | Left origin | Right origin | Wrap width |
| --- | ---: | ---: | ---: |
| Dialogue | 0 | 32 | 28 |
| Character | 8 | 40 | 20 |
| Parenthetical | 4 | 36 | 20 |

The equal measures give neither speaker priority. Cues and parentheticals are
tucked inside their own measure; the rightmost cue cell still ends at 60.
The four-cell gutter remains empty even for long unbroken words. Ordinary
speech geometry does not change. Generated continued cues also wrap at the
paired cue width, rather than spilling into the other speaker.

**Keep a pair together if it fits a fresh page.** If it does not fit the
remaining rows, move the whole pair to the next page. A taller pair may use
the current page only if both active lanes can start legally there.

For an overheight pair, align active cues at the top of each segment and split
each lane independently. A legal split leaves at least two Dialogue rows on
both sides and does not strand a Parenthetical. Reserve `(MORE)` for a lane
that continues and repeat only that lane's cue with `(CONT'D)` overleaf.
The page uses the taller lane segment's height; a shorter completed partner
does not repeat. This preserves normal speech-break protections without
forcing a finished speaker to manufacture dialogue.

On a pathological small page or an unsplittable overheight cue/parenthetical,
only the affected lane falls back to capacity-bounded raw rows. Retain pending
cue/body rows and stop generating new continuation prefixes for that lane,
so progress cannot be starved by repeating an overheight cue. The other lane
still follows legal splitting. Source rows are never discarded or duplicated.

**Keep the editor linear, but wrap both paired speeches at the output
widths.** Its ordinary indents and source order remain. Pair membership here
is wrapping context only, mirrored under the shared line-breaking contract,
not a second Fountain classifier or a page-break rule. Refresh context after
a patch and rewrap only blocks whose contextual width changed. A flag, kind,
insert, delete or undo can therefore invalidate an unchanged partner's wrap.
Page positions continue to come from Rust's `(block, source_line)` metadata,
not from equating linear editor height with simultaneous output height.

Side-by-side editing would also need two-column caret motion, selections,
hit testing and accessibility. It is not necessary to toggle or correctly
print dual dialogue and would change the custom editor's interaction model.

**Offer “Toggle dual dialogue” in the palette on a Character cue.** Register
its label in `elements.dart`; do not invent a shortcut that collides with the
existing map. The element bar identifies a marked cue as dual dialogue.
The command flips `SetDual`, preserves text and selection, and uses existing
undo/redo and journalling. The `^` belongs to serialization, never editable
cue text. No bridge API or generated binding changes are needed.

**Resolve output emphasis by source block and line, not spatial adjacency.**
Two columns interleave both on a sheet and across sheets. Group references
to consecutive source rows before scanning emphasis, then return each run
to its original positioned line. This prevents the other speaker from
closing an emphasis pair, without copying or changing the source text.
Preview and PDF continue to consume the same resolved runs and columns.

### Consequences

Pair membership becomes part of wrap-cache context. Changing a partner's flag
or kind can miss several cached blocks and legitimately take the full
pagination path. Speech/pair lookahead is included in `blocks_read`, so no
checkpoint can retain a prefix whose placement depended on an edited partner.
Incremental verification still compares pages and checkpoints, not counts.

The dual-dialogue corpus layout and its Letter/A4 PDF hashes deliberately
change. The line-breaking fixture gains width 28; width 20 already existed.
The reference feature has no dual flags and keeps its output.

### Verification

The rendered corpus PDF and native release preview were inspected, with
screenshots and Poppler bounding boxes retained under `target/x1-dual-smoke/`.
MARTHA and DEREK now start at x=165.6 and x=396 on the same y=120 baseline.
Only `03-dual-dialogue.layout.txt` and that corpus file's two PDF hashes changed;
the reference feature's layout and PDF hashes stayed identical.

Eleven focused layout tests cover pairing, orphan/interruption cases, legal
and asymmetric continuations, source conservation on four/five/eight-row
pages, and narrow continued cues. A regression failed before preserving the
complete wrapped cue name: `UVWXY` vanished from its continuation label.
Twenty incremental tests compare full pages and checkpoints, including a
new sweep of pair membership and rejected candidate lookahead.

Four deliberate faults each failed their regression: invert the pairing flag,
forget the right partner in `blocks_read`, skip editor contextual invalidation,
and scan emphasis in spatial order. The lookahead probe kept a stale prefix
and produced 60 pages against a full run's 59. Every probe was restored.

The whole workspace passed 662 Rust tests, the Flutter suite 714 widget tests,
and all seven Linux suites 83 native tests. The native dual test invokes the
palette, checks paired preview/source-line metadata and PDF bounding boxes,
then saves and reopens the marked cue. Formatting, Clippy, analysis, docs,
lockfile enforcement and the release build passed. Fifteen ordinary release
closes and network isolation passed.

The isolated Xvfb process check passed 376.025 ms startup and 274.93 MiB RSS.
Idle failed: the first and third intervals each had zero ticks but one
voluntary switch on the main thread. Its retained JSON is
`target/x1-dual-smoke/runtime-budgets-isolated.json`; the known idle issue,
thresholds and harness were left unchanged. An earlier concurrent run is
retained separately as `runtime-budgets.json`: its startup samples overlapped
native builds and its reference process exited 1 before interval measurements.
Neither a headless pass nor these screenshots close the real-desktop/print
gates in `docs/MANUAL_GATES.md`.

---

## ADR 0055 — FDX is an interchange copy, while Fountain remains the native document

**Date:** 2026-10-09 · **Status:** accepted · **Backlog:** X2
**Extends:** ADR 0004 with a syntax-only FDX codec and its bridge edge.
**Superseded by:** ADR 0062 for the initial import journal base; ADR 0068 for managed publication before adoption. The interchange and native-format decisions remain.

### Context and evidence

Slugline's backlog aims to replace a paid screenwriting service for one writer
on Linux. Migration and delivering an editable script to collaborators are
different needs. [WriterDuet exports Fountain as well as FDX](https://www.writerduet.com/article/261-export-a-document),
so migration from it does not require another parser.
[Final Draft's export formats](https://kb.finaldraft.com/hc/en-us/articles/27525594609684-How-do-I-export-a-Final-Draft-file-to-a-different-format-like-RTF-or-TXT)
include FDX but not Fountain, while its
[import guidance](https://kb.finaldraft.com/hc/en-us/articles/15575076862228-Can-Final-Draft-import-a-file-written-in-a-Fountain-based-screenwriting-program)
says `.fountain` is not directly accepted and warns that third-party FDX can
format differently. Both directions therefore have independent practical value.
The archived specification's import non-goal is historical, not rewritten.

The actual release application was run against a self-authored FDX file before
editing. It opened the XML as one Action block with zero scenes/characters and
offered only PDF and Fountain exports. Its editor and export-dialog screenshots
are retained under `target/x2-fdx-smoke/`; an ordinary close exited zero.

Public XML examples show typed paragraphs, multiple styled Text children,
numbered scene headings, positional title-page paragraphs and a Paragraph
containing DualDialogue, whose children contain the two speeches in order.
Sources are the [MIT Lexington FDX profile](https://github.com/LaPingvino/lexington/tree/4b30b71d68d38749058da4d9d3c5b58bfca95e42/fdx)
and [public FDX examples](https://github.com/rsdoiel/fdx/tree/main/testdata).
The latter repository is AGPL: its text/code is not copied into Slugline.
No producer provenance is inferred merely from a FinalDraft root tag.

### Decision

**Implement both import and export, not native FDX editing.** Fountain remains
the save format. FDX is a conversion of screenplay content, not a byte-exact
round-trip promise for revision sets, locked pages, custom fonts or margins.
Every textual structure is either represented, retained through an explicit
mapping with a warning, or rejected before the operation changes live content.
Unsupported content must never disappear silently.

**The codec is `fdx -> fountain`; only the bridge adds `-> fdx`.** It owns XML
recognition/emission and reuses the existing kinds, title fields, elements and
emphasis scanner. It owns no Document, history, disk I/O or pagination. XML
semantics do not move into Dart or the Fountain recognition rules. The layer
tables and manifest change together.

Use `quick-xml 0.38.3` with default features disabled: its only mandatory runtime
dependency is memchr and its declared Rust floor is below 1.85. Streaming events
avoid a second DOM/Serde model. UTF-8 is borrowed; BOM-marked UTF-16 is decoded
once. Unsupported encoding declarations, malformed XML and external/custom
entity constructs return errors rather than guessed text or network reads.
Write deterministic UTF-8 XML with correct escaping and no external resources.

**Import creates an isolated, unsaved session with no source path.** Read and
decode before visiting the actor; only the actor constructs the Document,
directly from semantic elements, with fresh identities and empty undo history.
Initialize the normal canonical Fountain crash-journal base. A journal failure
is reported with the existing unprotected-session mechanism, never hidden.
The UI presents conversion warnings before adopting the candidate; cancellation
closes it and retains the old editor. Save asks for a Fountain destination.
The source FDX file is never rebound, watched, overwritten or library-indexed.

**Export obeys ADR 0029.** Capture one immutable semantic snapshot, encode and
write off the actor through atomic saving. Refuse AlreadyExists until confirmed
and ScriptIsOpen even with overwrite. An export changes no dirty flag, active
path, history, journal, watcher, backup bookkeeping or library entry. Show
conversion warnings before proceeding; refuse unrepresentable textual data.
Use the existing chooser/replace confirmation, not another dialog framework.

**Map content, not page layout.** Standard screenplay types remain explicit
kinds; centered Action and Lyrics retain their meaning. Existing scene numbers
are preserved, not newly generated. StartsNewPage creates a page-break element.
DualDialogue becomes the source-ordered speeches with the second cue marked;
exports group only actual ADR 0054 pairs, never manufacture an orphan's partner.
Notes, outline and omitted content retain their text with a documented FDX
representation or an explicit warning, never an empty replacement.

Bold/italic/underline Text runs become Fountain emphasis using its existing
escaping and pairing semantics. Adjacent identical styles coalesce; leading and
trailing whitespace stays outside paired markers. Resolve the generated markup
back through the shared scanner to detect an unrepresentable style boundary:
retain the printable words and report any style normalization. Hard lines and
literal markup characters remain literal. Title pages use standard positional
grouping where reliable; unmatched text is preserved in Notes/Other with a
warning. Explicit field metadata in Slugline-created FDX is an interchange aid,
not a requirement imposed on other consumers.

### Alternatives and consequences

Export-only would help collaborators but leave Final Draft migration dependent
on a lossy plain-text intermediary. Native FDX Save would require preserving
production metadata the editor cannot represent and expose the source to
autosave loss. Both are rejected. A universal format registry, a second
persistence format and a sidecar cache have no necessary consumer here.

Fountain's original-source tiling and unedited byte-exact round trips remain
unchanged. Imported FDX has no Fountain provenance and does not synthesize one.
Generated APIs are regenerated with the existing pinned bridge toolchain.

### Verification contract

Tests cover element/style/text conservation, dual/number metadata, Unicode,
whitespace, malformed input, unsupported-content diagnostics, cancel/failure
isolation, save/reopen/recovery and copy-export refusals/state preservation.
Native UI smoke exercises import, editing, preview, export and Fountain Save.
Writer/reader self-round trips are not independent compatibility proof.
An isolated official Fade In demo is available for producer/consumer smoke
without installation; genuine Final Draft acceptance remains explicitly manual
unless a real consumer can be exercised. Final evidence belongs in X2's Result.

## ADR 0062 — An imported untitled document begins with a complete recovery outcome

**Date:** 2026-10-09 · **Status:** accepted · **Backlog:** X2
**Refines:** ADR 0055's import journal initialization.

**Superseded by:** ADR 0068 for managed project workflows.

### Evidence

ADR 0055 proposed the canonical imported Fountain as the initial journal base.
An untitled journal header contains a checksum, not its base text. Recovery
has no file path from which to reload that text and starts against a blank
document. A crash immediately after import, before typing or saving, therefore
cannot reconstruct an imported document from that header alone.

The release smoke imported an actual Fade In FDX, killed the process before
any typing, recovered its initial title/body outcome on restart, and saved
the recovered script as Fountain. A deliberate omission of the initial
recorded patch removes that recovery offer. The bridge regression exercises
the same pending-offer and acceptance path without a keystroke.

### Decision

Initialize an imported untitled session against the normal blank base and
record one complete semantic outcome immediately: replace block 1, insert
the remaining fresh identities in order, and include the complete title page.
This is an initialization patch, not a fabricated text command or undo entry.
Do not bind the source FDX path or serialize a second persisted import base.

Use the existing journal failure/event path for this initial outcome. Failure
does not fail import or silence the sticky unprotected-session status.
Normal subsequent edits, checkpoints, save and clean-close behavior do not
change. Recovery is still outcome replay, without inference (ADR 0013).

### Consequences and verification

An imported document is recoverable before its first edit, while Undo still
has no import transaction. Construction and initial recording are linear in
block count; snapshot each block directly, not with repeated identity scans.

The initial-crash regression verifies the offered document's ordered content
and title, accepted session and empty undo history. Import/edit/replay/save
tests also verify identity continuity and source-file isolation.

## ADR 0056 — Scene numbering is an explicit grouped Rust edit, not an output fallback

**Date:** 2026-10-08 · **Status:** accepted · **Backlog:** X3

### Context

Fountain's existing scene-number suffixes already survive save/reopen and
print when the output scene-number setting asks for a gutter. A script with
no suffixes prints no numbers, and the pre-change release palette cannot add
or remove them. Production scene identifiers belong to the script: changing
them only while exporting would leave the editor, collaborators and saved
Fountain describing different scene numbers.

### Decision

Offer “Number scenes” and “Remove scene numbers” under Script in the palette,
with labels in `elements.dart` and no new keyboard shortcuts. Number every
SceneHeading from 1 in source order, replacing existing suffixes rather than
attempting production-style insertion numbering. Removal recognises only
suffixes accepted by Fountain's existing `split_scene_number`; an interior
hash or an empty `##` is heading text, not a second syntax implementation.

Rust owns both operations. `Document::number_scenes` and
`Document::remove_scene_numbers` accept the caller's optional UTF-8 selection,
use the existing atomic grouping primitive and return one combined patch.
They replace only the suffix's text through `ReplaceText`, preserving ids,
kinds, forced/dual flags, title page and untouched block provenance. Existing
suffixes become `#N#`; new suffixes are ` #N#` inserted before trailing
whitespace. Removal deletes the recognised `#…#` and at most one separating
ASCII space. Extra spaces, tabs, leading and trailing whitespace remain;
this makes adding/removing a new suffix reversible without normalising a
heading's spacing. Undo restores the original source bytes/provenance.

Map both selection endpoints through each suffix replacement in Rust. A
position before the suffix stays fixed, a position after it shifts by the
byte-length delta, and a position inside replaced numeric text goes to the
suffix start, an exact UTF-8 boundary. Keep selection direction. Store before
and after selections in the grouped transaction, so undo/redo restores them
without Dart clamping or recreating semantic offsets.

The bridge's synchronous `doc_number_scenes(handle, at)` and
`doc_remove_scene_numbers(handle, at)` interrupt typing, convert the caller's
UTF-16 selection using `offsets.rs`, and finish through the journalled
`outcome` path. Do not reinfer: changing a numeric suffix is not changing an
element's meaning. No-op operations record no inverse, change no revision,
leave dirty state and redo intact, and append no journal line.

Dart exposes `DocumentCore.numberScenes(at)` and `removeSceneNumbers(at)`,
then applies Rust's text/selection patch through the editor's ordinary path.
The widget fake applies explicit supplied patches and never recognises
Fountain or generates numbers. Save, Fountain export, pagination and PDF
export do not invoke these edits. The existing output scene-number setting
still controls whether the stored numbers print.

### Consequences

Renumbering is deliberately destructive to custom production identifiers,
but explicit and reversible in one step. Removing numbers can leave original
extra separator whitespace; deleting all of it would be an unrelated heading
rewrite. There is no automatic numbering preference and no duplicated
recogniser in Dart. The bridge needs generated function bindings, not new
DTO fields or command variants.

### Regression coverage

Document regressions cover source-order replacement, mixed/forced headings,
non-heading hash text, dual/title/id/provenance preservation, exact spacing,
save/reparse, reverse selections and suffix caret mapping, isolated
undo/redo, no-op revision/redo preservation and atomic invalid selections.
Bridge regressions cover UTF-16 mapping, whole-document patches, no-op dirty
state, stale handles and invalid surrogate boundaries. Widget/native
regressions invoke both palette commands, apply patches, restore selections
through one-step undo/redo, inspect the actual combined journal record, save
and reopen numbered/unnumbered scripts, and check the existing output gutter
setting and PDF text without automatic source changes. Verification results
remain for the integrating owner; no checks are claimed here.

## ADR 0057 — Inline emphasis uses printed wraps and an editable source projection

**Date:** 2026-10-08 · **Status:** accepted
**Supersedes:** ADR 0019's literal-width wrapping and unstyled editor policy.
**Refines:** ADR 0018's synchronous differential line-breaking contract.
**Extends:** ADR 0044's printed alignment and ADR 0045's shared output runs.

### Context

Raw markers caused early wrapping although output removed them. Merely removing
them from a display string would destroy source-coordinate caret, selection and
IME behavior. Interpreting Fountain in Dart would introduce a second semantic
authority; asking Rust for wraps on every edit would replace the synchronous
editor contract with an unnecessary round trip. Re-scanning raw output rows
after soft wrapping can also change marker eligibility.

### Decision

Extend Fountain's existing tokenizer/pairer with sparse `SourceRun` intervals:
UTF-8 source start/end, resolved `Emphasis`, and a `hidden` flag. Plain gaps cost
no run. Paired markers and escaping slashes have zero printed width; unpaired
markers remain literal. Ordinary/Dialogue pairing spans the block's source hard
lines, with hard boundaries acting as spaces for opener/closer eligibility.
Dialogue's semantic leading `~` is hidden before pairing and implies italic only
on its own hard line. Title values resolve each source hard line independently
before soft wrapping.

Both wrappers count the retained printed scalar/tab cells. Hidden prefixes
belong to the following cell, suffixes to the final row, and hidden syntax in a
consumed space gap extends the preceding row's source span. Width comes from the
retained cell map, not a substring's length. No source text is rewritten by
layout. `LayoutLine.resolved_runs` preserves pre-wrap faces through pages and
dual lanes; `source_span` retains the prepared block's source coordinates.
Generated furniture can use the existing output scanner fallback.

The bridge translates ranges only through `offsets.rs` and attaches
`BlockView.inline_runs` to load, changed/inserted patches and history results.
Each `InlineRunView` has `start_utf16`, `end_utf16`, `bold`, `italic`, `underline`,
and `hidden`. Dart uses this metadata synchronously; it never pairs markers.
Plain blocks have empty metadata and keep their existing fast path.

Printed columns and editable display columns are deliberately distinct.
In the editor each hidden scalar has a dim half-cell slot and half-size regular
face between the printed cells; content uses the resolved bold/italic/underline
face. This is readable markup, not glyphs superimposed on script text. Such a
row may extend beyond the printed measure; it is never rewrapped because of
editor-only syntax slots. Caret, pointer hit-testing, vertical movement,
selection/find rectangles and IME/spelling underlines share the display map.
Page/source anchors still use printed wraps and unchanged EditorGeometry rows.
IME, semantics and clipboard retain exact Fountain source and UTF-16 offsets.

`doc_format_selection(handle, at, InlineStyle)` owns Ctrl+B/I/U and palette
formatting. It plans source-preserving marker insertions per selected block/hard
line, keeps boundary whitespace outside inserted markers, and checks the
scanner's before/after projection so no original printed character or unrelated
face changes. Unsafe markup/escape intersections, invalid offsets, empty or
whitespace-only selections, and read-only content refuse before mutation.
This wraps, rather than toggles, selected content.

One actor-owned group contains the entire gesture. `Grouped::set_selection`
records selected-content endpoints and direction for redo; undo restores the
original source selection. Formatting finishes through journalled `outcome`,
not reinference: wrapping an entire heading/cue must not demote its element.

### Alternatives

Zero-width overlaid marker glyphs were rejected because adjacent/nested markers
overlap content and cannot be individually hit-tested. Literal full-width wraps
retain the observed early-wrap bug. A Dart emphasis scanner or extra bridge
query on each edit breaks semantic ownership or the synchronous typing path.

### Regression contract

Native scanner, wrapping, output and formatting tests cover marker boundaries,
escapes/literals, Unicode, hard/sung scopes, title wraps, output page carries,
whitespace/provenance, atomic refusal and journalled undo/redo selections.
The differential generator exports scalar-indexed sparse runs alongside source
spans and printed widths; Dart compares the same projection, including dual
widths. Editor tests exercise actual painted faces, dim markers, independently
addressable source boundaries, source IME input and patch/history behavior.
A real-core Linux integration test drives all three shortcuts and verifies
printed geometry, retained selections and one-step undo/redo.

Fixture and layout/PDF golden regeneration is deliberate: markup stops counting
as printed columns, tab stops now follow printed text, pre-wrap output scopes
survive boundaries, and title emphasis survives source-hard-line soft wraps.
No verification result is asserted here; the integration owner runs the gates
and reviews/regenerates affected baselines.


---

## ADR 0061 — Omissions carry lossless semantic fragments inside Fountain boneyards

**Date:** 2026-10-09 · **Status:** accepted
**Superseded by:** ADR 0063 refines seam normalization and recovery after saved structural edits; the omission record format remains unchanged.
**Extends:** ADR 0007's protected-block model and ADR 0010's grouped structural
gestures. Only explicit safe boneyard replacement narrows provenance-only Opaque
editing; ordinary commands retain their existing protections.

### Context

X7 requires exact partial selections, not silently widened whole elements, and
saved/reopened omissions must restore editable screenplay semantics. Fountain
has no standalone Dialogue or Parenthetical marker. Commenting only a raw
fragment therefore loses its kind when a cue or adjacent block changes.
Inventing a cue, keeping a persisted sidecar, or globally allowing Opaque text
editing would either alter the screenplay or expose comment-terminator hazards.

### Decision

The three palette-only commands are **Omit selection**, **Omit scene** and
**Restore omitted text**, reached through Ctrl+K; there are no dedicated key
bindings. Omit selection preserves the exact character boundaries supplied by
the editor (UTF-16 converted fallibly through `offsets.rs`). A collapsed or
separator-only selection is refused without mutation. A selection ending at the next block's
start excludes that block. Omit scene uses the heading at/before the focus
through the block before the next heading, including sections, notes, existing
boneyards and empty structural blocks.
Selection omission refuses existing read-only boneyards; scene omission may contain complete nested boneyards. A partial
selection that leaves an unclosed comment or nested-note opener in a visible remainder is
also refused atomically rather than letting that opener capture the generated
omission or unrelated later text. Selecting the complete delimiter span is
safe; the selected opener/terminator text is escaped losslessly in the record.

A generated omission is a real standalone Fountain `/* ... */` boneyard,
represented as read-only Opaque. Its content is a readable, versioned semantic
record, not a fake screenplay cue/sentinel or an external sidecar. The header is
`Slugline omission v2`; a trailing `checksum` line carries a 16-digit hexadecimal
FNV-1a integrity check of the complete UTF-8 record prefix, including the outer
opener and newlines, before that checksum line. This detects accidental damage,
not maliciously authored records; structural and semantic validation still
reject records that cannot be represented safely.

`left`, `right`, `before` and `after-seam` are either `none` or an element record.
`preceding N` is followed by N `prior` records, nearest first, witnessing the
preceding speech owner. `following N` is followed by N `after` records. The
remaining one-or-more `block` records are the selected fragments in document
order. Each element record carries a kind, the original forced/dual bits
(`0`/`1`), and quoted exact model/source text,
including inline emphasis. Kinds are `scene`, `action`, `character`, `dialogue`,
`parenthetical`, `transition`, `centered`, `lyric`, `section-1` through
`section-6`, `synopsis`, `note`, `page-break`, and `boneyard`.
Backslash, slash, square brackets, quote, LF and CR are escaped as `\\`,
`\x2f`, `\x5b`/`\x5d`, `\"`, `\n`, and `\r`; every slash is replaced, not merely backslash-prefixed, because
Fountain comment recognition does not treat `\/` as an escaped slash.
Escaped brackets cannot create a nested-note opener around the omission record.
Unicode scalars are literal. Even unmatched
`*/`, nested/unclosed `/*`, and existing boneyards are consequently conserved
without being able to close the outer comment. Block ids are never persisted.

Partial boundary blocks remain visible and retain their ids; one block split
on both sides gives its second remainder a fresh id. The left/right witnesses
retain exact remainder text and semantics. Fountain trims single-line markers,
so matching normalized remainders recover their original seam whitespace.
Restore joins the selected fragments back to matching witnessed remainders.
Changed text, kind, dual ownership or missing adjacent content refuses the
gesture; newer neighboring text is never overwritten or silently merged.
When a reopen has reclassified a known untouched speech remainder, its exact witness permits
restoring the original semantics. A different-kind, different-text seam, a
missing remainder, or a missing cue that would orphan restored speech refuses
the entire gesture. Restore never searches elsewhere or overwrites new text.

Boneyards interrupt speech context. Any unselected speech tail serializes as
literal forced Action blocks with real separators while omitted; `following`
witnesses restore those original Dialogue/Parenthetical kinds when the text
still matches. A preceding unchanged cue's `before` witness restores its
original forced bit after a reopen required an `@` to keep that cue a cue.
Existing same-kind text edits also refuse restoration. Marker drift after a
provenance-backed reopen is allowed only when the exact text, kind and dual
semantics still match: ADR 0059 intentionally drops redundant live forced pins.
The stored original flags are restored in the live document, without demanding
redundant markers on disk.

Restore acts on the boneyard under a collapsed caret, or every boneyard
intersecting a nonempty selection, ignoring editable blocks between them. A
recognizable malformed/unsupported semantic record refuses restoration; its
metadata must never silently become printable Action. Foreign boneyards are
unwrapped and parsed as body Fountain (never as a replacement title page).
Closed, nested, unclosed-to-EOF and empty foreign comments are supported.
Nested comments remain real, separately restorable boneyards. Reintroducing an
unclosed nested comment before later writing is refused so it cannot swallow
that writing.
Reassembled typed fragments are passed through the real Fountain serializer and
parser before mutation. A change to text, kind or dual semantics refuses the
restore rather than consuming a record that Save would partially discard or
reinterpret. Literal unclosed comments in printable text therefore stay safely
inside their lossless record; they are not exposed as source that swallows text.

These are explicit structural document commands. Arbitrary ReplaceText,
Split/Merge, SetKind, DeleteRange and ordinary InsertBlocks still cannot edit
or manufacture Opaque blocks. Generated omissions/restored nested boneyards
may have no original provenance; that is the sole narrowing of the old
provenance-only Opaque model. The parser's exact source tiling remains intact.
Untouched blocks/title retain their source; selected fragments and structural
seams use the existing canonical/provenance paths. Undo restores ids, original
provenance, exact source and the directed caret/selection. Each gesture is one
isolated transaction and one journal outcome; a late restoration failure rolls
back the entire group. There is no reinference of stored fragments or their
unrelated neighbors. Preview/PDF already exclude Opaque at layout's boundary.

### Live seams and one-step history

The retained draft left the right ` friend.` as Dialogue after omitting `café`
from `JOHN` / `Hello café friend.`; Fountain reopens it as Action because the
boneyard interrupts the speech. The omission gesture now uses the shared grammar
for its left remainder and makes the interrupted right/tail explicit Action
through SetKind. Records retain original fragments/flags for exact restoration.
No Save-time actor reparse, hidden cue or redundant-marker policy is added.

Necessary orphan `@` syntax can also change a lowercase cue extension's rendering
under ADR 0060. An omission pins that temporary cue consistently in the same
gesture; restoration reinstates its original flags after matching the expected
visible witness. A forcing difference that changes Character rendering is never
accepted merely because the block has reopened provenance. Nested-note seams
that could capture the generated record refuse before any splice.

The combined experimental snapshot's independent SetKind steps reproduced Undo
stopping at an intermediate split. An inner group also replaced the actual
scene selection with its computed scene range. All three public omission commands
now enter one group at the document mutation boundary with the caller's directed
selection. Existing grouped callers retain their atomic rollback. One gesture
produces one history transaction and one journal outcome. The gesture's new
history is staged independently and appended only on success, so a late refusal
retains existing Undo/Redo text without cloning the whole history. Undo/Redo
patches now express the identities at the transaction boundaries: newly inserted
remainders are never also journalled as changes to missing blocks. Recognizable
record structure with a damaged header refuses rather than becoming foreign
printable comment text.

### Regression contract

Consumer regressions cover Unicode offsets, reversed/cross-block partial
selections, trimmed heading/cue/parenthetical seams, dual/forced semantics,
whole scene boundaries, nested/comment terminators, changed context, malformed
records and late-group rollback, Save/reopen/journal replay and actual recovery
offer/acceptance before and after a checkpoint, actual editable
restoration, palette patch/undo/redo selections, and omission exclusion from
preview rows and Poppler-extracted PDF text. Generated-binding reconciliation,
formatting and execution are recorded with the X7 backlog Result.
---

## ADR 0059 — Canonical Fountain persists necessary syntax, not redundant live pins

**Date:** 2026-10-09 · **Status:** accepted · **Backlog:** X6

**Superseded by:** ADR 0060 refines marker necessity for authored Character case only.

**Supersedes:** ADR 0007's edited canonical flag equality and ADR 0011's unconditional serialization of live pins only.

### Context

The retained X6 review recorded a release reproduction where double-Enter
and typing `MARY` below `JOHN` saved a redundant `@MARY`. A fresh reproduction
on published main `af3ae3c` fails all three document consumer regressions:
pinned heading, Action, cue and transition acquire `.`, `!`, `@` and `>` despite
already being native syntax, and the edited uppercase cue retains redundant
`@` inside an otherwise untouched BOM/CRLF file. The log is retained at
`target/retained-features/x6/baseline-red.log`.

Tab, digit shortcuts and double-Enter deliberately pin a type against live
inference. Treating that session state as an unconditional output marker
leaves a noisier source file and makes F7's source-case rendering expose
machine-added markers rather than the writer's intended syntax.

### Decision

For new or edited canonical SceneHeading, Character, Transition and Action,
use the existing shared grammar and existing context/title/protected-text
guards to emit a forcing marker only when native Fountain needs it. Do not
add another classifier. Untouched provenance continues through the verbatim
path, including explicit markers, BOM, CRLF, indentation and trailing spaces.

Preserve all authored text and capitalization. Serialization is a read, not
an edit: it changes no live text, pin, revision, selection or history. A pin
remains live through Save; after reload source syntax is authority. There is
no persisted sidecar, hidden pin cache or automatic stored capitals.
Necessary ambiguous markers, orphan cues, dual syntax, top-level title-key
guards, literal punctuation and partial states remain protected. A pinned
empty Action emits `!`: unlike a separator this represents a real block,
needed by crash-journal base identities and empty imported documents.
Whitespace-only Action lines also require `!` to avoid becoming separators.

Canonical equality is kind/text/dual, not redundant `forced` equality.
Undo still restores the original provenance and pin, so an untouched source
marker returns with its exact bytes. Journal outcomes continue to carry live
pins for edited blocks. The actor keeps its Document: Save does not replace
it with a separately parsed document. Journal checkpoints refer to the exact
saved bytes, and later outcome patches replay onto that source base.

An imported untitled FDX session still starts against `Document::blank()`'s
exact bytes and carries its full initial outcome (ADR 0062), never a header
checksum of the imported serialization. Its first Save checkpoints the exact
persisted Fountain, including an empty imported Action's identity-bearing `!`.

### Product tradeoff and F7

This deliberately enables F7, rather than silently uppercasing stored names.
A deliberately typed mixed/lowercase Character (`McCLANE`, `mary`) requires
`@`; once F7 lands it prints in its authored case in editor, preview and PDF.
Writers wanting uppercase cues should type uppercase names. Naturally
uppercase cues with a speech need no redundant marker and remain uppercase.
The serializer does not change display code or the SceneHeading caps rule.

### Verification contract

Regressions cover clean native Save/reload, semantic kind/text/dual equality,
Unicode/case, necessary markers, CRLF/BOM and byte-exact untouched blocks,
restored source pins on Undo, and post-checkpoint crash replay targeting blocks
after an empty forced Action. Empty FDX import covers the exact untitled blank
base, first Save, later Unicode edits, Undo/Redo and production recovery
offer/accept. Save is checked against actor identity, revision, generation,
selection and live pins. Verification evidence belongs in the X6 backlog
Result; no corpus source or golden fixture is reformatted by this change.

## ADR 0060 — Forced Character cues retain authored case on every surface

**Date:** 2026-10-09 · **Status:** accepted · **Backlog:** F7

**Refines:** ADR 0059 — necessary syntax also preserves forced Character rendering case.

### Context

The baseline prints `@McCLANE` as `MCCLANE` in the editor, preview and
selectable PDF text. The parser and worker snapshot already retain both
`text` and `forced`; the information is lost only at display preparation.

ADR 0059 resolves the X6 prerequisite: canonical Fountain retains only forcing
markers required to preserve classification, keeps the author's exact text and
case, and stores no hidden kind pin. A live UI pin lasts until reload, after
which Fountain source syntax is authority. Deliberately lowercase or mixed-case
Character names need `@` and print in that authored case. This is the intentional
product tradeoff; automatically uppercasing stored names is not an alternative.

### Decision

A Character block with `forced = true` is displayed as authored. Unforced
Character cues, SceneHeading and Transition retain their existing
locale-independent, stable-UTF-16 uppercase display mapping. No new parser
rule, case preference, persisted flag or capitalization normalization is added.

Layout selects this policy before wrapping, so original single/dual cues,
styled runs and generated continuation names all inherit the same spelling.
The appended `(CONT'D)` furniture keeps its conventional case. Preview and PDF
consume the resolved case and never uppercase again. With pre-wrap source
projection, case selection must apply to both raw display content and resolved
run text without rewriting source spans or block identity.
An unstyled authored `(cont'd)` extension is recognized without ASCII case
normalization and is not followed by a duplicate `(CONT'D)` on later pages.

Dart's `displayText` requires an explicit forcing flag. Both actual production
callers — surface painting and surface semantics — supply it. Stable scalar and
UTF-16 boundaries keep caret, selection, hit testing, find and spelling on the
writer's source offsets; those consumers never mutate the source to match the
display. Forced Unicode cues bypass uppercase mapping entirely.

The layout fingerprint gains exactly one byte, `forced`, per block. It needs
no new block lookahead or `blocks_read` dependency: the flag belongs to the
same snapshot block already read. Toggling it must invalidate the cue wrap
and preserve full/incremental pages and checkpoints.

### Necessary case syntax through Save/reopen

With F7 active, classification alone does not decide whether `@` is redundant.
After editing `@MARY` to `ÉLODIE (on the phone)`, the initial X6 canonical path
removed `@`; reopen then uppercased the extension despite the live authored
rendering. The failing consumer is retained as
`target/retained-features/f7/case-save-reopen-red.log`.

Retain `@` for a forced cue whenever ordinary display would change its text,
including a naturally recognized uppercase base with a lowercase extension.
The offset-stable Rust uppercase mapping now lives once in `fountain::case`,
used by both layout and serialization. Layout's public helper remains a
re-export, so the existing differential contract still holds. Expanding maps
such as `(ß)` remain verbatim already and do not justify an extra marker.
Untouched provenance stays exact; serialization still changes no actor text,
selection, history, revision or live pin. This is the final necessary-marker
policy future omission witnesses must use.

### Consequences

Typing a mixed/lowercase name and choosing Character does not secretly change
its stored spelling or promise an uppercase printed name. Use uppercase source
when uppercase printing is wanted; `@` is the source notation for authored
case. Existing forced uppercase names remain visibly unchanged.

Source files and corpus bytes are not rewritten. Golden layout/PDF output may
change only for forced names or extensions containing lowercase text; uppercase
forced cues and ordinary cues keep their previous presentation. Changes after
X4's projected wraps are separate from this case decision and must be reviewed
separately, not accepted as incidental capitalization churn.

### Evidence and enforcement

On finalized X6 main `6aa026c`, all four retained layout consumer tests
fail before the display change. The retained tests first required an iterator
repair for today's `Arc` page lines; both the compile failure and semantic red
run are preserved. The baseline PDF and Poppler extraction at
`target/retained-features/f7/baseline.pdf` and `baseline-bbox.html` show
`MCCLANE` and `ÉßMCCLANE` for authored mixed-case cues.

Consumer regressions cover single/dual long speeches and continuation names,
full/incremental forcing toggles, Unicode widths and caret boundaries, exact
original UTF-8 source spans despite `ı` → `I`, actual per-cell editor painting
and semantics, find/hit-test/spelling source cells, styled resolved output,
native editor/preview painting, real-actor forcing-only pagination and Undo,
native BOM/CRLF Save/reopen with Undo/Redo, and Poppler PDF extraction. The golden change is deliberate and limited to
`02-every-element`'s authored `mcCLANE` cue and its Letter/A4 PDF hashes.
Verification evidence belongs in the F7 backlog Result.

---

## ADR 0058 — The outline is source-ordered Rust structure and scene length is paginated occupied eighths

**Status:** Accepted
**Date:** 2026-10-08
**Backlog:** X5
**Extends:** ADR 0035's semantic navigator and ADR 0020's async pagination.

### Context

Sections and synopses are outline structure even though they do not print.
Editor wrapping cannot supply output page positions or scene lengths. A second
pagination request per navigator refresh would duplicate work, while a cached
answer shown after an edit would claim to describe text it did not paginate.

### Decision

`NavigatorView.outline` is a flat, source-ordered vector of `NavigatorNode`
values: source block id, kind, text, optional parent block id and zero-based
depth. Only Section, Synopsis and SceneHeading occur. Rust scans the document
alongside the existing scene snapshot; character navigation still uses the
entity index. No edit, inference, provenance or undo behavior changes.

A section belongs to the nearest preceding section with a strictly smaller
Fountain level. Equal or lower levels close previous sections; skipped levels
do not create synthetic nodes. Depth counts actual ancestors, not hash marks.
A scene belongs to the current innermost section. A synopsis belongs to the
most recent section or scene, until another section or scene is encountered.
Ordinary text and hidden blocks do not change that attachment. A synopsis before
either anchor is a root node. All nodes retain source order: a section summary
appears before its scenes, while a synopsis written inside a scene follows its
heading. Hidden-only scripts can therefore have a useful outline without any
scenes; empty scripts have no outline. Boneyard contents do not create nodes.

`PaginationView.scenes` contains `ScenePaginationView { block, page,
length_eighths }`. This is computed off the actor from the same immutable
paginated script as preview and page indication. Page is the actual numbered
screenplay page of the first printed heading line. Length is **occupied
eighth-pages**: on each page, count the inclusive row band from the scene's first
to last Content/More/Continued row; include spacing inside that band, exclude
external blanks, gutters, page numbers and unused page bottoms. Sum the bands,
multiply by eight, divide by that setup's actual text-row capacity, and round
up once per scene. Shared pages contribute separate bands to adjacent scenes.
Long scenes sum their actual bands across pages, not an inclusive page count.
Title pages never participate. Structure does not print and contributes no
length. A scene lacking a printed heading has no pagination metadata.

Dart reuses `PageIndicator`'s debounced async job rather than requesting layout
from navigator refresh or typing. Its scene-metadata map is immutable. Every
document edit immediately clears that map and invalidates the in-flight request;
setup changes do the same. Delivery requires both the latest request token and
the unchanged controller edit epoch, and only Rust's Current outcome supplies
scene metadata. Stale outcomes never supply it, even when undo returns to a
previous Rust revision. Controller revisions are local monotonically advancing
edit epochs and must not be compared numerically with Rust undo revisions.
Title-dialog commits use the same invalidation/debounce entry point: those edits
reach the core directly and do not advance the controller's body edit epoch.
The request token therefore also guards title mutations. No body reload or
extra document-revision query is introduced.
Unknown/pending values display ellipses, never estimated pages.

The existing Scenes/Characters tabs, drawer threshold, focus return, shortcuts
and character cue cycling remain. Outline sections are accessible headers;
every outline row supports clicking and arrow/Enter activation. Filtering uses
supplied parents to retain ancestor context and descendants of matching
structure. Quick scene search initially selects the first matching scene.
When no scene directly matches, keyboard activation selects the matching
section or synopsis rather than an ancestor retained only as context.
Only scenes have drag handles and move menus, and reordering is unavailable
while filtered. Outline drop positions resolve to the next scene in the proposed
order and call the existing atomic MoveScene command; sections are not a new
movable unit. Moving a scene retains that command's source-range semantics,
including intervening outline blocks, and Rust recomputes hierarchy afterward.
The fake core only reorders supplied nodes with its block-list surgery; it
does not compute parentage, attachments, page positions or length.

### Consequences and regression coverage

Bridge regressions exercise actual parsed hierarchy, pre-scene material, skipped
levels, source-id jumps, hidden/empty documents, scene move/undo, shared-page
length, title-page exclusion, wrapped headings, continued dual-dialogue bands
and edited repagination. Consumer regressions exercise sidebar/drawer jumps,
accessible hierarchy, context filtering, scene and synopsis search, reorder/undo
and pending/current metadata. Controlled async deliveries cover old-current,
stale, title-commit and undo-revision races without recreating pagination
semantics in the fake. Generated bridge reconciliation and execution of checks
belong to the integration owner.

---

## ADR 0063 — Saved checkpoint outcomes use the base's identities without changing live state

**Date:** 2026-10-09 · **Status:** accepted
**Refines:** ADR 0013's saved checkpoint identity handling and ADR 0061's seam
matching and saved omission recovery. The read-only Save contract remains.

### Context

Splitting a scene heading for an omission leaves live identities in source order
`[1, 3, 4, 2]`. Parsing its saved Fountain assigns `[1, 2, 3, 4]`. A checkpoint
that writes later Restore/Undo/Redo outcomes with live identities can therefore
replace the wrong block during recovery. Changing the actor document to match
the parse would break ADR 0059's Save selection, history and live-pin invariants.

Separately, accepting a trimmed seam witness without checking provenance lets
a live whitespace deletion masquerade as parser normalization. Restoration then
silently puts deleted text back instead of refusing the changed witness.

### Decision

The save's immutable snapshot supplies source-ordered block identities to the
journal checkpoint and buffered-outcome rebuild. A session-local map translates
those identities into the saved base's one-based parse identities. Newly inserted
identities get stable fresh numbers above the base; retained entries also cover
removal and subsequent reinsertion through Undo/Redo. Each later record translates
removed, changed and inserted identities before encoding the ordinary outcome.

The map never changes a live Patch, actor Document, selection, revision, history
or kind pin. It is not persisted: records already contain recovery identities,
so the existing recovery parse/replay and second-crash journal rebuild need no
new schema or hidden semantic cache. A successful new checkpoint resets the map.
Buffered edits are translated against the snapshot actually saved, rather than
the newer document present when the write completes. Untouched saved provenance,
BOM and line endings remain available to the recovery parse.

Omission seam normalization requires untouched parsed provenance whose bytes
match the actual serializer's representation of the witnessed text, excluding
separator newlines. Provenance alone cannot authorize a whitespace change made
outside the editor. A changed live block must match the exact witnessed text;
rejection adds no history or journal outcome and keeps live text and the record.

### Evidence and consequences

The real recovery API regression failed after a saved partial heading followed
by Restore/Undo/Redo/Undo, duplicating the omission over the following Action.
It now passes for both heading and Unicode Dialogue cases, before and after a
checkpoint, with offer/acceptance, exact restoration and BOM/CRLF Save/reopen.
A storage consumer replays buffered changes and later inserts into the saved
base, preserves untouched bytes, and repeats recovery through a second journal.

Core and native consumers reproduce live and saved-source whitespace deletions,
require atomic refusal and verify the existing Undo selection/text remains usable. The failed
logs and final verification belong to the X7 backlog Result. No journal version,
forcing policy, dependency, budget or golden output changes.

---

## ADR 0064 — A quit parks the session; putting a script away ends it

**Date:** 2026-10-09 · **Status:** accepted

**Superseded by:** ADR 0067 for reading-row restoration; ADR 0068 for managed project binding. Quit and put-away rules remain.

### Context

The library index carries `open` and `scroll_row` for each script, and startup
reopens the first open one at that row. The comments beside both said a quit
and a crash each put the writer back where they were. Neither did. `shutdown`
closed every document, and a close marks its script not open, so an ordinary
quit came back to the library; Dart had in any case closed the script before
calling it. `doc_set_scroll` only changes memory, so a process that died came
back to the row of the last unrelated index write — row 0 unless a save had
followed the scrolling. Whether a clean quit should reopen the script had never
been decided, only assumed in both directions.

### Decision

**Quitting with a script open is not putting it away.** The next launch that
names no file comes back to that script at the row it was showing. `Ctrl+W`,
and switching to another script, put a script away: it is not reopened. Crash
recovery still comes first and a file named on the command line still wins.

- The core has two endings for a session. `AppState::close` is the writer
  putting the script away. `AppState::park` is the application going with it
  open: the same journal discard and unwatch, with the library entry left open
  and given the row. `shutdown` parks.
- **Dart calls `shutdown` before it lets go of the open script.** Disposing the
  controller closes the document, and a document closed first is one that was
  put away. Only the autosave clock stops earlier.
- The row reaches the disk when Dart says so, through `session_park`: two
  seconds after the view last moved, and when a script is put away. The core
  has no clock to do it (ADR 0014) and `doc_set_scroll` runs per row, which is
  too often for a file write. A process that dies inside those two seconds
  comes back to the row before the last scroll.
- Save As takes the session to the new path: the old entry is closed and the
  new one takes the row.

The index is still a cache (ADR 0043). Deleting it costs the session along with
the recent list, and nothing else.

### Consequences

The first launch after an ordinary quit opens a script instead of the library.
`tools/check_clean_close.py`'s third launch names no script and used to rely on
that library; it now has to come back to the script its second launch was
closed in, puts it away, and closes the library as before — so the shipped
bundle's restore is checked wherever that tool runs.

Opening a script from the library still starts at its top, and so does an
accepted recovery; the row is used by session restore alone.

---

## ADR 0065 — The headless budget profile does not join the desktop's session bus

**Date:** 2026-10-09 · **Status:** accepted
**Extends:** ADR 0050's default software profile. Its thresholds, sampling and
`--desktop` profile are unchanged.

### Context

The idle gate failed on the development machine in every measured run from W4
on, and passed on hosted CI: zero CPU ticks and one voluntary switch of the
main thread in each quiet ten-second interval. Nothing had attributed it.

Logging every thread's switches at 50 ms placed the wakeups six to nine
seconds after each burst of frames — after startup settles, and after each
30-second status refresh — and never otherwise. Two launches differing in one
variable each settled it. Without `DBUS_SESSION_BUS_ADDRESS` there were none;
with it and `NO_AT_BRIDGE=1` there were none. Run as gdb's child, the wakeup is
`dbus_watch_handle` called from libatspi's main-loop source: a message arriving
on an accessibility bus.

`xvfb-run` started from a desktop session hands that session's bus address to
the process. GTK's accessibility bridge finds the live desktop's AT-SPI bus
through it and joins, and whatever that bus then sends wakes the main thread.
The application sets no timer for it and does no work when it arrives. A hosted
runner has no session bus, which is the whole difference.

### Decision

The default profile removes `DBUS_SESSION_BUS_ADDRESS` and `AT_SPI_BUS_ADDRESS`
from the measured process's environment, beside the display, scale and
software-rendering settings it already pins. The budget is still zero ticks and
zero voluntary switches in the best of three intervals. `--desktop` keeps the
environment it is given: there the bus is part of the desktop being measured.

Rejected: allowing one switch per interval, which would admit a real
ten-second poller; `NO_AT_BRIDGE=1`, which also silences the bridge where a bus
is legitimately present and so measures a differently configured process than
the one shipped; a private `dbus-run-session`, which adds a process and a
dependency to answer a question that needs neither.

### Evidence and consequences

On one release bundle: the unchanged harness measured 1, 74 and 1 switches and
failed; with the two variables removed it measured 0, 74 and 0 and passed, the
74 being the status refresh. A do-nothing three-second GLib timer preloaded
into the same unmodified bundle then measured 4, 68 and 3 and failed, so the
profile has not blinded the gate. Startup settling also fell from 13.2 s to
10.6 s. Reports and probes are under `target/b29/`.

The headless profile now measures the same process on a workstation as on a
runner. On a real desktop that runs an accessibility bus the application is
woken by that bus's messages; a `--desktop` run can show one main-thread switch
with no CPU tick for that reason, and manual gate 5's reader should know it.

---

## ADR 0066 — Repeated title entries are shown and edited individually

**Date:** 2026-10-09 · **Status:** accepted
**Refines:** ADR 0033's field addressing; its history and journal rules remain.

### Context

A native Fountain file can repeat a title key. The title form showed only its
first entry, but clearing that box removed every entry with the key. S4 stopped
untouched forms from writing, while leaving this destructive mismatch unresolved.

### Decision

Show each existing entry in its own box, including repeated custom fields and
multi-line values. Group the standard fields under their usual labels and the
custom fields below; equal keys keep their source order. Do not merge entries
or normalise their values.

`doc_set_title_entry` addresses a key and its zero-based occurrence in the live
title page. Editing or clearing affects only that entry; the older
`doc_set_title_field` addresses occurrence zero and obeys the same removal rule.
The occurrence after the last can append, and larger occurrences are refused.
The form updates the remaining occurrences when it removes an entry, retaining
each surviving box's identity and pending text. A standard field with no entries
still offers an empty box.

Keep ADR 0033's one entry per undo step and whole-title-page outcome in the crash
journal. An unchanged box sends nothing; an unchanged or refused core call
records nothing. An untouched form preserves the original source bytes.

### Alternatives and consequences

A single merged box would erase the distinction the file made between entries.
Showing later entries as read-only would prevent the writer from editing them.
Individual boxes expose all the existing text and make deletion explicit.

The focused title-page widget and bridge tests cover later and custom entries,
focus-loss/dispose commits, deletion followed by editing a surviving box, no-op
and invalid occurrences, Undo/Redo, journal replay and save/reopen. Whole-page
provenance is dropped by an intentional title edit as before; Undo restores the
original bytes, and the BOM, CRLF and untouched body survive save/reopen.

---

## ADR 0067 — Reopening and recovery reuse the saved reading row

**Date:** 2026-10-09 · **Status:** accepted
**Refines:** ADR 0064's reading-row restoration; its quit, put-away and settle rules remain.

### Context

The library keeps a script's reading row after it is put away or crashes.
Opening and recovery retain that entry, but only startup session restore passed
its row to the editor. Library and quick-open selections and accepted recovery
therefore returned to the top and replaced the stored row with zero.

### Decision

Whenever the app adopts an existing script, use its path's current library row
unless the caller supplies an explicit row, including zero. Resolve the row in
`_adopt`, before replacing the current editor, so library, quick-open, named
startup paths and successful or degraded recovery follow the same rule.

Untitled/imported scripts and paths absent from the index start at zero. The
editor's existing geometry applies the row and clamps it if the file became
shorter; pagination landing still preserves that viewport. This restores a
visual row, not a source-text anchor across edits or changes in wrapping.

### Consequences and verification

The library remains a cache: losing it costs reading position, never text.
Recovery still requires the writer's choice and remains dirty until saved.
After the asynchronous library lookup, adoption rechecks whether the app is
mounted or exiting and closes an unused handle instead of creating an editor.

File-workflow widget tests cover separate library/quick-open rows, shortening,
an explicit zero session row and quit/unmount during lookup. Focused native
persistence tests exercise actual library opening and accepted journal recovery,
check the viewport's reported row, preserve file bytes before Save and verify
the recovered text and BOM/untouched CRLF bytes through Save and actual reopen.

## ADR 0068 — Editable scripts are portable managed projects

**Date:** 2026-10-09 · **Status:** accepted
**Narrows:** ADR 0016, ADR 0021, ADR 0029, ADR 0038, ADR 0043, ADR 0052, ADR 0055, ADR 0062 and ADR 0064 for managed project workflows.

### Context

Arbitrary external paths made every New and first imported Save ask for a destination,
and autosave could replace the imported Fountain original. Pins lived only in a
central cache; moving that cache lost user metadata. The approved
[managed library plan](MANAGED_LIBRARY_PLAN.md) makes copying into a portable
library the boundary before text entry.

### Decision

Rust owns the library root, stable random project identity, validation and
transactions. A lazy first-run default uses Documents/Slugline, falling back to
home/Slugline. Explicit test paths use their own data/library directory. Once a
root is used or selected it is persisted; disappearance reports unavailability
and never creates another working copy. Selecting another root validates it
and saves preferences before activation; it leaves the old files in place.

A project is an ordinary direct-child directory named from its initial display
name and a 128-bit lowercase hexadecimal ID. Its script.fountain is ordinary
UTF-8 Fountain. A version-1 project.json owns ID, display name, archive state,
user entity pins and optional import/migration origin. Unknown JSON fields
survive updates. Rename changes metadata only. A root scan reconstructs the
library; central index version 2 owns convenience state such as recency, pages,
open state and reading row. Missing, damaged, future-format, conflicting and
interrupted projects stay visible for explicit repair or text rescue. Repair
preserves raw damaged metadata first; unsupported formats are never rewritten.
Root aliases canonicalize to one location, while project child symlinks cannot
escape validation. Copies of an ID are conflicts, not additional editable identities.

New and both import formats prepare an isolated candidate. Fountain captures
exact UTF-8 bytes, including BOM, CRLF and untouched regions. FDX captures its
original bytes under imports/source.fdx and stores Rust-produced Fountain.
Warnings, copy confirmation and the old document's close decision precede
publication. Exclusively owned staging uses atomic saves and Linux
RENAME_NOREPLACE with parent synchronization and a directory flock; cleanup
removes only that operation's staging. The actor's live Document, history and
identities survive adoption. Its initial outcome is journalled against blank,
then checkpointed against the exact published base. A durable transaction marker
reconciles interrupted publication without overwriting or creating repeated copies.

Save and autosave write only a validated managed project. Missing files, roots,
archive state or identity conflicts refuse the write and retain dirty text and
recovery evidence. Exports copy a captured snapshot without rebinding or clearing
dirty state. Ctrl+Shift+S is Export a copy. Exports require explicit replacement
approval and refuse managed project contents, closed projects and aliases.
The compatibility Save As API permits only a save onto the session's own file.

Previous versions live in each project's versions directory. Opening baselines,
manual snapshots, the autosave age gate and retention policy remain from ADR 0043.
The old global backup preference remains readable only as migration input.
Duplicate captures active unsaved text (saved bytes when closed), copies pins,
allocates a new ID and starts independent versions. Archive and Restore change
metadata without deleting text or versions. Open as copy captures viewed version
text, resolves the current editor, then creates an independent managed project.

Legacy index version 1 is retained atomically as compatibility input before the
new cache is written. Migration is selective, copy based and resumable from
per-project origin markers; it retains external files, old versions, pins and
reading position. Version collisions are copied without overwriting; failures
report partial status and keep completed copies for retry. Pending recovery
precedes saved-file migration. Legacy recovery remains an unbound candidate;
cancel or failed protection leaves its predecessor intact. Explicit migration
publishes saved recovered bytes and establishes a kernel-owned successor before
retiring that predecessor. Managed recovery still arrives dirty without saving.
Ordinary quit parking, put-away, late callback checks and saved-row restoration
remain in force.

### Consequences and verification

The library directory is portable user data. The central list remains a cache;
deleting it may lose reading convenience but cannot lose labels, pins, archive
state, identity or screenplay text. Origin records explain copies and offer an
existing-copy choice; they never establish synchronization or content identity.

Storage tests cover exact publication, no-clobber collisions, metadata damage,
unknown fields and root/child alias boundaries. Bridge tests cover independent
active duplicates, export isolation, missing-library guards, resumable legacy
history and predecessor/live-successor ownership. Widget tests cover keyboard
creation, copy/export confirmation, cancellation, dirty close and late adoption.
Selected Linux native persistence, bridge, export and writing checks preserve
byte/reopen, input, recovery, history and output assertions through generated APIs.

---

## ADR 0069 — CJK input-method validation is outside the release scope

**Date:** 2026-10-09 · **Status:** accepted
**Narrows:** ADR 0005's CJK input-method validation requirement.

### Context

The user explicitly removed Japanese/Chinese input-method support validation
from the requested product scope.

### Decision

Retire manual gate 1, including real IBus CJK composition and input-method
emoji validation, and remove its task from `todo.md`. Unverified CJK
composition does not require adopting ADR 0005's fallback editor.

### Consequences

The retired gate retains its historical evidence without claiming a pass.
Any future real-CJK support commitment requires its own validation scope.
