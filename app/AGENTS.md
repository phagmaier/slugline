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
- `lib/editor/elements.dart` is the one table for shortcuts, element
  selector and palette; `docs/KEYMAP.md` is the keyboard map.
- A block's kind changes only through `SetKind`. Panels stay children of
  the editor page so Escape closes them with a `setState`.
- The editor never decides where a page ends: both modes read Rust's
  `pageStarts`. The preview paints Rust's runs and parses no emphasis.
- Dual-dialogue editing stays linear, but paired cue/body wraps use output
  widths. Kind/flag/structural patches must invalidate unchanged partners'
  contextual wraps; page ends still come only from Rust (ADR 0054).
- Widget tests drive `DocumentCore` through `fake_core.dart`, which does
  list surgery only. Anything deciding what a screenplay *is* is tested
  with `cargo test` (ADR 0011).
- Scene-number palette commands consume Rust text/selection patches; the fake
  applies explicit test-supplied patches without parsing suffixes (ADR 0056).
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

Verify from `app/`: `flutter pub get --enforce-lockfile`,
`dart format --output=none --set-exit-if-changed lib test integration_test test_driver`,
`flutter analyze`, `flutter test` (or `flutter test test/<area>/` for one
area), `flutter build linux --release`. Real-window suites run under Xvfb
via `./tools/test_linux_integration.sh`. After touching the runner or
upgrading Flutter, also `xvfb-run -a python3 ../tools/check_clean_close.py`.

Governing ADRs: 0005, 0011, 0012, 0018, 0041, 0045, 0052, 0053, 0054, 0055, 0056. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. When an ADR changes
this surface, update this file in the same change.
