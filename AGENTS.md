# Slugline Agent Guide

The project is at 1.0. This guide records the invariants, rules and verification
commands for touching any subsystem. For rationale, read the ADR that owns what
you are changing — the index at the top of `docs/DECISIONS.md` says which files
each record governs.

## Which documents govern

Live and binding: this file, `docs/BACKLOG.md`, `docs/DECISIONS.md`,
`docs/BUDGETS.md`, `docs/KEYMAP.md`, `docs/LINE_BREAKING.md` and
`docs/DEPENDENCIES.md`.

`docs/archive/SPEC.md` and `docs/archive/REVIEW.md` are **provenance, not
instructions** — frozen, partly false, their imperatives retired at 1.0.
Read them for history; where any document disagrees with this one, this one
wins. `README.md` and `CHANGELOG.md`
are for users. `docs/MANUAL_GATES.md` lists the checks that need a person at a
real desktop: an agent cannot perform or fake them, so report and move on.

## Backlog

`docs/BACKLOG.md` holds the planned fixes in priority order, with a checklist at
the top and the rules for working an item under "How to use this file" — one item
per change, reproduce before changing. The owner has explicitly delegated
implementation choices and product decisions to agents: do not wait for sign-off
or ask the owner to choose between options. Use sound judgment, investigate, and
record the reasoning and outcome in the item's `Result` line. Ask only when
required information is genuinely unavailable and cannot be established from the
project or its sources.

## Commits

One backlog item per commit, subject led by the item's id —
`F3 — the preview renders emphasis instead of showing markers` — and a body
saying what changed, why, and what was verified. The `Result` line then names the
commit, which is how `tools/check_docs.py` tells a finished item from an
abandoned one. Git history is the only record of a change no ADR covers, so
`fixes` and `wip` cost the next agent real time.

When several agents work in the tree at once, each takes its own
worktree or branch named for its item (`w8-...`), one backlog item per
branch, and never ticks or rewrites another agent's item — record
out-of-scope findings under that item's "Found along the way" section
instead.

## Architecture

- **`crates/fountain`** — syntax: `BlockKind`, `TitlePage`, `Element`, parse,
  serialise, `infer_kind`.
- **`crates/document`** — identity and history: `BlockId`, `Block`, `Document`,
  `EditCommand`, undo, find/replace, Enter/Tab tables in `workflow.rs`.
  Re-exports `fountain`'s kinds (ADR 0008).
- **`crates/storage`** — atomic save, crash journal, backups, preferences,
  library index.
- **`crates/bridge`** — the actor thread (`actor.rs`) and the API surface under
  `src/api/` (`doc.rs`, `files.rs`, `layout.rs`, `events.rs`, `spell.rs`,
  `lifecycle.rs`); its generated Dart is `app/lib/src/rust/`. This directory is
  the authority for what the bridge exposes — not `docs/archive/SPEC.md`,
  whose §6 listing predates most of it. Depends on all other crates.
- **`crates/layout`** — pagination engine. Wired into the bridge at
  `crates/bridge/src/api/layout.rs`; `doc_paginate` runs it as an async
  snapshot job, and every successful save paginates the exact saved snapshot and
  caches its page count in the library. An incremental path (ADR 0022, refined
  by ADR 0049) uses per-block fingerprint hints.
- **`crates/render_pdf`** — writes PDF bytes itself: TrueType subsetter, sfnt
  writer, PDF object writer, SHA-256. No dependency outside the workspace (ADR
  0032). Courier Prime is vendored in `crates/render_pdf/fonts/`, and
  `app/fonts/` symlinks the same four files so the editor and the preview draw
  the script in the face the PDF prints it in. Replace a face and both change.
- **`crates/spell`** — pure Hunspell-compatible checker; bridge checks immutable
  block snapshots, editor paints results. No automatic correction; only Replace
  sends an `EditCommand` (ADR 0036).
- **`app/`** — the editor, keyboard workflow, autocomplete, library, title page,
  preview, export, navigator, spell-check presentation.

Rust owns document state, Fountain semantics, persistence, pagination, and PDF
output. Flutter owns input, caret/selection, scrolling, and widgets; Dart must
ask Rust for screenplay semantics rather than reimplementing them.

Workspace layers enforced by `python3 tools/check_layering.py`:
`fountain` has no workspace dependencies; `document -> fountain`;
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
- `app/lib/editor/metrics.dart` and `line_layout.dart` hold the grid and the
  editor's own line breaking. `ScreenplayMetrics` in `metrics.dart` owns the
  printed sheet in inches and every column is derived from it — **including the
  script's size**. The bundled face's advance is `advanceRatio` (pinned to the
  TTF by `test/editor/script_font_test.dart`), `fittedFontSize` returns the
  largest size whose page still crosses the viewport, and the text-size
  preference is the ceiling on that rather than a pixel count. Never measure a
  font to get an advance and never hard-code a script size.
  `app/lib/typography.dart` holds the other half of that split: the script is
  `scriptFontFamily` sized off the grid, the chrome is the platform sans through
  `chromeTextTheme`, and nothing is both. `page_geometry.dart`
  turns that grid into viewport coordinates, and **every** row-to-pixel
  conversion — painting, hit testing, caret scrolling, semantics — goes through
  `EditorGeometry`. Add a second one and page view breaks silently.
  The editor is fluid and unpaginated, and its
  wrapping is on the keystroke path where a bridge round trip does not belong
  (ADR 0018). They are a second implementation of one contract
  (`docs/LINE_BREAKING.md`), and the corpus-wide differential test holds them
  to it. Change one side without the other and the test fails; change it on
  purpose and regenerate with
  `UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential`.
- `docs/KEYMAP.md` is the keyboard map, and `app/lib/editor/elements.dart` is
  the one table the shortcuts, the element selector and the command palette
  read. What a key *does* is Dart's; what an element is followed by is Rust's.
- Every edit that reaches the document goes through `outcome` or `inferring` in
  `crates/bridge/src/api/doc.rs`, and both append to the crash journal. A new
  mutation must end in one of them — never in a bare `document.apply`.
- **The editor never decides where a page ends.** The `page_view` preference
  draws sheets instead of one column, but both modes read `PageIndicator`'s
  `pageStarts`, which is Rust's paginated snapshot re-expressed in editor rows.
  Before the first snapshot lands there are no page starts and the surface draws
  a plain column — that is the correct answer, not a gap to fill with an
  estimate.
- A block's kind changes only through `SetKind`. Automatic re-classification
  goes through `Document::reinfer`, which the bridge calls after every edit;
  `Ctrl+K` and `Ctrl+F` open panels the editor page owns, so that Escape closes
  one with a `setState` and never reaches the document.
- Widget tests run without the `.so`, so they drive the editor through
  `DocumentCore` with the double in `app/test/support/fake_core.dart`. That
  double does list surgery only: anything that decides what a screenplay *is*
  goes in Rust and is tested with `cargo test` (ADR 0011).

## Output — pagination, preview and PDF

- **`crates/render_pdf` writes the bytes itself** (ADR 0032). Do not replace a
  font face without re-running
  `UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf --test golden`.
- **The renderer makes no layout decisions.** Every row and column comes from
  `crates/layout` and is copied; `Geometry` multiplies a grid cell by its size
  in points. `render_pdf::emphasis_runs` shares resolved inline emphasis with
  the bridge (ADR 0045): body rows pair across wraps/pages, title rows pair
  individually, and an unpaired marker stays an ordinary character.
- **An incremental pagination is a full pagination, arrived at sooner** (ADR
  0049). `repaginate` keeps pages only from a page the paginator recorded an
  element beginning: before the edit, one it began before it had read the
  edited block; after it, one it begins again. A break rule that looks at
  anything beyond the element it is placing must be counted in `blocks_read`,
  beside it in `crates/layout/src/engine.rs`.
  `crates/layout/tests/incremental_differential.rs` holds the two paths to each
  other, pages and checkpoints both; never relax it to a page count.
- **The preview and PDF share the paginated snapshot and resolved runs.**
  `app/lib/preview/preview_view.dart` paints Rust's runs and makes no layout
  or emphasis-parsing decision. Raw row content and source identity stay intact.
  “Bold scene headings” is an output preference, off by default, followed by
  the editor, preview and PDF. Editor inline markup and wrapping remain literal.
- **Page 1 is counted but not marked** (ADR 0048). `Page::number` is still
  `Some(1)`; whether a page prints its number is whether the paginator gave it
  a page-number line, and page 1 gets one only under “Number the first page”,
  an output preference that is off by default. Preview and PDF draw the lines
  they are given; the editor's page view asks `PageIndicator.printsNumber`.
  Only `crates/layout` turns the option into that line; nothing else may
  re-derive it from the preference.
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
- After changing `crates/bridge/src/api/`, run
  `cargo install flutter_rust_bridge_codegen cargo-expand` once, then
   `cd app && flutter_rust_bridge_codegen generate`. Commit the generated
   bindings in `app/lib/src/rust/`; never edit them by hand. CI holds them
   with `tools/check_bridge_bindings.sh`, which regenerates to a temp dir
   and diffs — a stale binding fails there instead of in the Xvfb suites. Run
   `./tools/agent.sh bindings` for the same check locally.
- Keep Rust `flutter_rust_bridge = "=2.12.0"` and Dart
  `flutter_rust_bridge: 2.12.0` exactly aligned. Bump both and regenerate
  bindings in the same change.

## Verification

While you work, run what your change can break; before calling it done, run the
whole list. `tools/agent.sh` wraps the common invocations so every agent runs
the same flags (`./tools/agent.sh quick <crate>`, `./tools/agent.sh docs`,
`./tools/agent.sh lint`, `./tools/agent.sh backlog-next`, `./tools/agent.sh
regen` for print-only goldens). Environment pre-flight is
`./tools/doctor.sh`.

One subsystem at a time:

```sh
cargo test -p slugline_<crate>       # fountain, document, layout, render_pdf, storage, spell, bridge
cd app && flutter test test/<area>/  # editor/, preview/, library/, settings/
```

Rust checks from the repository root:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
python3 tools/check_layering.py
python3 tools/check_version.py
python3 tools/check_docs.py                # the docs still point at real files and live ADRs
python3 tools/make_reference.py --check   # after touching fountain's syntax, parser or serialiser
```

Flutter checks from `app/`:

```sh
flutter pub get --enforce-lockfile   # fails if the lockfile is not this toolchain's
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
flutter build linux --release
```

The Dart tree is formatter-clean, generated bindings included, and CI fails if
`dart format` would change anything. Run `dart format` on the Dart you touch;
on a clean tree that reformats nothing else. The style is the formatter's
default for the package's language version; there is no project configuration.

Integration tests open real windows and go through Xvfb; this is the script CI
runs, one test at a time, and it fails if its list and the files on disk
disagree:

```sh
./tools/test_linux_integration.sh
```

`./tools/check_no_network.sh` and the packaging smoke tests need the release
bundle. `./tools/release_preflight.sh` runs everything on this page plus
packaging and the metadata validators — the one command that proves a release
candidate, needing `LINUXDEPLOY` set — and is overkill for anything that is not
a release. Its one difference is a plain `flutter pub get`, so that a newer
local Flutter can still run it; CI is what holds the lockfile.

Golden regeneration (each needs a sentence in the commit message saying whether
the change was deliberate):

```sh
UPDATE_LAYOUT_GOLDENS=1 cargo test -p slugline_layout --test golden
UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf --test golden
UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential
```

`crates/render_pdf/tests/text_extraction.rs` needs `poppler-utils`; without it
the test prints `SKIPPED` and stops. CI installs it. The export integration
suite needs it too (`pdftotext`, `pdftohtml`) and does not skip: the script
above refuses to start without them, and CI's flutter job installs them.

To look at a PDF rather than a hash:
`cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf [a4]`

The full-disk test needs a small filesystem: CI mounts a 4 MB tmpfs and names
it in `SLUGLINE_FULL_DISK_DIR`. Locally the variable is unset and the test
falls back to proving only error classification; to run the real thing without
root, `unshare -Umr` a mount namespace,
`mount -t tmpfs -o size=4m,mode=1777` a scratch directory, and point the
variable at it.

The benchmark (`integration_test/keystroke_benchmark_test.dart`) measures the
keystroke path with and without the crash journal; both must stay under budget,
and the second number is what matters in a real session. `docs/BUDGETS.md` is
the live list of thresholds and what measures each — never change one without
changing its test in the same change.

F9's process budgets measure the shipped release bundle separately from the
Flutter integration suites (ADR 0050):

```sh
xvfb-run -a python3 tools/check_runtime_budgets.py --output target/runtime-budgets.json
```

It requires `xdotool`, installed in the CI flutter and release jobs. Startup is
exec to the first-frame window with an empty script argument; no-argument startup
opens the library, and the caret is static. Idle waits for measured quiet, then
requires zero CPU ticks and zero voluntary thread switches over ten seconds.
The Xvfb RSS ceiling is 320 MiB; the 250 MiB GPU-session budget remains manual
gate 5. Do not claim that a software-rendered pass proves the real-desktop figure.
`--only` selects a budget for deliberate failure checks; revert every injected
regression and rebuild.

## Project constraints

- Add a one-line justification to `docs/DEPENDENCIES.md` in the same change as
  every new Rust or Dart dependency. Avoid large transitive dependency trees.
- `Cargo.toml`'s `rust-version = "1.85"` is a fact about the dependency graph
  (`hashbrown` under `spellbook`, `notify-types` under `notify`), and CI's `msrv`
  job builds on exactly that toolchain. Avoid std APIs stabilised later, or raise
  the floor deliberately in the same change — which is why `storage` uses
  `libc::flock` and not `File::try_lock` (1.89); see ADR 0042.
- `app/pubspec.lock` is the resolution of the toolchain CI pins (Flutter 3.44.8),
  and CI resolves with `--enforce-lockfile`. The SDK pins four packages
  exactly, so `pub get` under a newer Flutter rewrites them — as does anything
  that runs it for you, the bridge code generator included. Restore the lockfile
  unless the change is a deliberate dependency or toolchain bump.
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
