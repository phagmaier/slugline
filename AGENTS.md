# Slugline Agent Guide

## Scope and architecture

- The repository is Linux-only. Phases 0–4 are complete: `crates/fountain` and `crates/document` are the Fountain core, `crates/storage` is the atomic save, the crash journal, backups and the library index, `crates/bridge` is the actor thread and the §6 surface, `app/` is the editor and the library, and `layout`/`render_pdf`/`spell` are intentional placeholders for later phases. Follow the phase order and exit criteria in `SPEC.md`; work within one phase at a time.
- Rust owns document state, Fountain semantics, persistence, pagination, and PDF output. Flutter owns input, caret/selection, scrolling, and widgets; Dart must ask Rust for screenplay semantics rather than reimplementing them.
- Workspace layers are enforced by `python3 tools/check_layering.py`: `fountain` has no workspace dependencies; `document -> fountain`; `layout -> document`; `render_pdf -> layout`; `storage -> document`; `spell` has none; `bridge` may depend on all. Update the workspace manifest, the script's tables, and the bridge's `WORKSPACE_CRATES` table together when adding a workspace crate or allowed edge.
- Every bridge offset is a UTF-16 code-unit offset named `*_utf16`. Only `crates/bridge/src/offsets.rs` may convert UTF-16 and UTF-8 offsets; invalid boundaries return `None`, never rounded or clamped. Offsets inside `document` are UTF-8 byte offsets and are named for it (ADR 0008).

## The editor

- `AppState` lives on one actor thread (`crates/bridge/src/actor.rs`); nothing else may hold a `Document`. Every bridge function hands the actor a closure. Long jobs — pagination, PDF export, the library scan — belong on a worker pool against a snapshot, not here (§2.3). A save is the pattern to copy: ask the actor for the bytes and the path, let go, write the file, come back to record what happened.
- **There is no timer anywhere in the core, and there must not be.** The actor thread blocks on its channel and wakes only when something happens, which is how §1.3's 0% idle CPU budget is met by construction. The autosave clock is Dart's (ADR 0014), and so is anything else that has to happen "in N seconds".
- The editor is one custom editing surface, not a widget per block (ADR 0005). `EditorController` owns the caret, the selection and the wrapped line geometry; every text change goes to the core as an `EditCommand` and comes back as a patch that is applied in place — never refetch the document (ADR 0009).
- `app/lib/editor/metrics.dart` holds §5.2's grid on loan. Phase 6's `layout` crate replaces it; do not grow a second opinion about screenplay geometry in Dart.
- `docs/KEYMAP.md` is the keyboard map, and `app/lib/editor/elements.dart` is the one table the shortcuts, the element selector and the command palette read. What a key *does* is Dart's; what an element is followed by is Rust's — see below.
- Every edit that reaches the document goes through `outcome` or `inferring` in `crates/bridge/src/api/doc.rs`, and both append to the crash journal. That is what lets the journal claim to hold every edit, so a new mutation must end in one of them — never in a bare `document.apply`.
- A block's kind changes only through `SetKind`. Automatic re-classification (§4.2) goes through `Document::reinfer`, which the bridge calls after every edit; `Ctrl+K` and `Ctrl+F` open panels the editor page owns, so that Escape closes one with a `setState` and never reaches the document.
- Widget tests run without the `.so`, so they drive the editor through `DocumentCore` with the double in `app/test/support/fake_core.dart`. That double does list surgery only: anything that decides what a screenplay *is* goes in Rust and is tested with `cargo test`. That is why the Enter/Tab table's content is proved in `crates/`, and the widget tests prove only that the key reaches the core (ADR 0011).

## Persistence

- `crates/storage` is where §1.2's "losing user text is a P0 bug" is cashed out. Two rules hold across all of it: a write either happened or did not, and a read never fails on bad input. A corrupt journal, a truncated library index and a hand-mangled preferences file each yield what could be read — they are read at startup and at recovery, the two moments when refusing to run costs most.
- Every file this project writes goes through `atomic::save_atomically`, including the ones it writes about itself. The five-step sequence is §Phase 4's, verbatim, and the tests in `crates/bridge/tests/persistence.rs` hold it to it.
- The journal records the **outcome** of an edit (a `Patch`), never the command (ADR 0013). Replaying is list surgery with no inference in it. Appends are not `fsync`ed on purpose; do not "fix" that without reading the ADR.
- The library index, the session and the backups' bookkeeping are **caches**. Deleting any of them must cost nothing but convenience, and an integration test deletes the index mid-session to prove it.
- A journal file's *absence* is what says a session ended cleanly. `Journal::discard` removes it and nothing else may.

## The Fountain core

- `fountain` owns syntax (`BlockKind`, `TitlePage`, `Element`, parse, serialise, `infer_kind`); `document` owns identity and history (`BlockId`, `Block`, `Document`, `EditCommand`, undo), find and replace, and the Enter/Tab tables in `workflow.rs`. `document` re-exports `fountain`'s kinds rather than declaring its own (ADR 0008).
- `infer_kind` is the third caller of `syntax.rs`, after the parser and the serialiser, and it is bound by the same rule: it must never produce a kind the file would not give back. Two tests hold it to that. Do not add a classification rule to it that the parser does not already have (ADR 0011).
- Provenance ranges **tile the source exactly**: every byte after the BOM belongs to exactly one range, in order. Byte-exact round-tripping is a consequence of that, so any change to the parser must keep the tiling test green (ADR 0007). Editing a block drops its provenance and nothing else's.
- Recognition rules live once, in `fountain/src/syntax.rs`, and the serialiser calls the same functions backwards to decide whether a re-serialised block needs a forced prefix. Do not add a second opinion about what a line means.
- `testdata/reference-feature.fountain` is generated by `python3 tools/make_reference.py`; do not hand-edit it. Corpus files are compared byte-for-byte — never reformat one or strip its trailing whitespace.

## Bridge and generated code

- `flutter build linux` invokes cargokit to compile `crates/bridge` and bundle `libslugline_bridge.so`; do not add a separate Rust build step for the app.
- After changing `crates/bridge/src/api/`, run `cargo install flutter_rust_bridge_codegen cargo-expand` once, then `cd app && flutter_rust_bridge_codegen generate`. Commit the generated bindings in `app/lib/src/rust/`; never edit them by hand.
- Keep Rust `flutter_rust_bridge = "=2.12.0"` and Dart `flutter_rust_bridge: 2.12.0` exactly aligned. Bump both and regenerate bindings in the same change.

## Verification

Run Rust checks from the repository root:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
python3 tools/check_layering.py
```

Run Flutter checks from `app/` (start with `flutter pub get` on a fresh checkout):

```sh
flutter analyze
flutter test                         # unit tests only
flutter test test/editor             # focused Dart tests
flutter build linux --release        # also builds and bundles Rust
flutter test integration_test/bridge_test.dart -d linux
flutter test integration_test/editor_test.dart -d linux
flutter test integration_test/writing_test.dart -d linux
flutter test integration_test/ime_test.dart -d linux
flutter test integration_test/keystroke_benchmark_test.dart -d linux
flutter test integration_test/persistence_test.dart -d linux
```

- The integration tests need the built `.so`; CI runs them after the release build under `xvfb-run`. The benchmark prints the §1.3 table it asserts on, so a regression says by how much. `ime_test.dart` is ADR 0005's exit gate as far as automation reaches it — it hands the surface the values a real input method sends, because `tester.testTextInput` is not registered in an integration binding. The `ibus` + CJK check it cannot replace is manual and has not been run; `SPEC.md` says so in both places. The Linux build needs GTK, clang, CMake, Ninja, pkg-config, and liblzma development packages; see `README.md` for Arch/Debian commands.
- A focused Rust run uses `cargo test -p slugline_bridge <test_name>`. Phase 4's four named tests are in `crates/bridge/tests/persistence.rs` and `crates/storage/src/journal.rs`; the kill test really does spawn and `SIGKILL` a child, and it runs under plain `cargo test`. The full-disk test needs a small filesystem to be real — give CI one at `SLUGLINE_FULL_DISK_DIR`, or it falls back to proving only the error classification.
- The benchmark measures the keystroke path twice: with and without the crash journal attached. Both must stay under the §1.3 budget, and the second one is the number that matters for a real session.

## Project constraints

- Add a one-line justification to `docs/DEPENDENCIES.md` in the same change as every new Rust or Dart dependency. Avoid large transitive dependency trees.
- Do not add network requests, telemetry, update checks, font downloads, databases, or persisted lock files. Loss of user text is a P0 defect.
- Do not edit an accepted ADR in `docs/DECISIONS.md`; add a superseding record instead. `spike/` is throwaway benchmark evidence for ADR 0005, is outside the Rust workspace, and is not built by CI.
