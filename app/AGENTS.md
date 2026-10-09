# app — scoped agent notes

Scope: the Flutter editor. Input, caret/selection, scrolling and widgets
are Dart's; screenplay semantics are Rust's — Dart asks, never re-derives
(ADR 0018).

Key areas: `lib/editor/` (surface, controller, metrics, `line_layout.dart`,
`page_geometry.dart`, `elements.dart`), `lib/preview/`, `lib/library/`,
`lib/settings/`, `lib/core/` (`DocumentCore`), `test/support/fake_core.dart`.

Invariants:

- One custom editing surface, not a widget per block (ADR 0005).
  `EditorController` owns caret, selection and wrapped-line geometry; every
  text change goes to the core as an `EditCommand` and comes back as a patch
  applied in place — never refetch the document (ADR 0009).
- The script's size derives from the grid in `lib/editor/metrics.dart`;
  never measure a font for an advance, never hard-code a script size. Every
  row-to-pixel conversion goes through `EditorGeometry` — never add a
  second one.
- Editor wrapping stays in Dart on the keystroke path; the differential
  test holds it to Rust's `line_break.rs`. Change one side only with the
  other, or regenerate fixtures deliberately (ADR 0018).
- Inline semantics arrive as sparse `BlockView.inlineRuns`, not a Dart parser.
  Wrap on printed cells; dim syntax has separate half-cell editable slots.
  Painting, caret/hits, selection and underlines use VisualLine's display map;
  IME/accessibility/clipboard remain exact source UTF-16 (ADR 0057).
- Dense syntax can extend past the viewport without changing printed wraps.
  Horizontal scrolling exposes those slots; caret/hits share its offset, and
  DocumentLayout caches editable extents alongside each block's wraps.
- `lib/editor/elements.dart` is the one table for shortcuts, element
  selector and palette; `docs/KEYMAP.md` is the keyboard map.
- A block's kind changes only through `SetKind`. Panels stay children of
  the editor page so Escape closes them with a `setState`.
- Kind pins are live through Save; after reload native Fountain syntax is
  authority (ADR 0059). No Dart syntax/marker decisions, stored capitals or
  hidden persisted pin cache. Deliberate mixed/lowercase cues require `@`.
- The editor never decides where a page ends: both modes read Rust's
  `pageStarts`. The preview paints Rust's runs and parses no emphasis.
- Dual-dialogue editing stays linear, but paired cue/body wraps use output
  widths. Kind/flag/structural patches must invalidate unchanged partners'
  contextual wraps; page ends still come only from Rust (ADR 0054).
- Every `displayText` caller supplies the block's forcing flag explicitly.
  Forced Character cues retain authored case; ordinary cues and headings keep
  capitals. Painting and semantics share that string, while selection,
  hit testing, find and spelling retain its stable source boundaries (ADR 0060).
- Widget tests drive `DocumentCore` through `fake_core.dart`, which does
  list surgery only. Anything deciding what a screenplay *is* is tested
  with `cargo test` (ADR 0011).
- Scene-number palette commands consume Rust text/selection patches; the fake
  applies explicit test-supplied patches without parsing suffixes (ADR 0056).
- Navigator structure and scene page/length are Rust data (ADR 0058). Reuse
  `PageIndicator`'s async pagination; invalidate scene metadata immediately on
  edits/setup changes, and reject stale or superseded requests. The controller's
  local edit epoch is not Rust's undo revision.
- Omit selection, Omit scene and Restore omitted text are palette-only commands
  from `elements.dart` (ADR 0061). The controller applies core patches and
  selections; neither it nor the fake parses semantic omission records.
- The tree is formatter-clean including generated bindings: run `dart
  format` on the Dart you touch. The lockfile belongs to Flutter 3.44.8;
  restore it unless bumping deliberately.
- FDX remains Rust-owned conversion: import adopts an isolated unsaved Fountain
  candidate only after warnings and close confirmation. Cancel/failure closes
  only the candidate. Export is a copy with revision-bound warning approval,
  shared replacement confirmation and no open-script overwrite (ADR 0055).
- `linux/runner/my_application.cc` disposes the engine in
  `GApplication::shutdown`, so its threads are joined before `main()` returns
  into the process's exit handlers. Never destroy the window there instead,
  and never `_exit()` (ADR 0053).

Verification follows the [root policy](../AGENTS.md#verification). From `app/`,
format touched Dart, analyze changed files as needed, and run the relevant
widget test file or named tests. Use an area suite only when the impact warrants
it. Do not run all widget/native suites or a release build for a small UI fix.
Run `flutter pub get --enforce-lockfile` only for setup or dependency changes.

For a real-window/input/bridge failure, select one suite with
`../tools/agent.sh native <suite> [flutter-test-args...]`; it runs under Xvfb.
All files via `../tools/test_linux_integration.sh` are for a
substantial native batch or explicit full native validation. After runner or
shutdown changes or a Flutter upgrade, run `tools/check_clean_close.py` from
the root under Xvfb against the relevant bundle. Build only if needed for that
check or reproduction. Release/packaging work waits for the final release task.

Governing ADRs: 0005, 0011, 0012, 0018, 0041, 0045, 0052, 0053, 0054, 0055, 0056, 0057, 0058, 0059, 0060, 0061. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. Update these notes only
when their invariants or pointers change.
