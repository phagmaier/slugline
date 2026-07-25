# Screenplay Agent Guide

## Scope and architecture

- The repository is Linux-only. Phase 0 is complete: `app/` is an FRB handshake proof, and the Rust crates other than `bridge` are intentional placeholders for later phases. Follow the phase order and exit criteria in `SPEC.md`; work within one phase at a time.
- Rust owns document state, Fountain semantics, persistence, pagination, and PDF output. Flutter owns input, caret/selection, scrolling, and widgets; Dart must ask Rust for screenplay semantics rather than reimplementing them.
- Workspace layers are enforced by `python3 tools/check_layering.py`: `fountain` has no workspace dependencies; `document -> fountain`; `layout -> document`; `render_pdf -> layout`; `storage -> document`; `spell` has none; `bridge` may depend on all. Update the workspace manifest, the script's tables, and the bridge's `WORKSPACE_CRATES` table together when adding a workspace crate or allowed edge.
- Every bridge offset is a UTF-16 code-unit offset named `*_utf16`. Only `crates/bridge/src/offsets.rs` may convert UTF-16 and UTF-8 offsets; invalid boundaries return `None`, never rounded or clamped.

## Bridge and generated code

- `flutter build linux` invokes cargokit to compile `crates/bridge` and bundle `libscreenplay_bridge.so`; do not add a separate Rust build step for the app.
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
flutter test test/proof_text_test.dart # focused Dart test
flutter build linux --release        # also builds and bundles Rust
flutter test integration_test/bridge_test.dart -d linux
```

- The bridge integration test needs the built `.so`; CI runs it after the release build under `xvfb-run`. The Linux build needs GTK, clang, CMake, Ninja, pkg-config, and liblzma development packages; see `README.md` for Arch/Debian commands.
- A focused Rust run uses `cargo test -p screenplay_bridge <test_name>`.

## Project constraints

- Add a one-line justification to `docs/DEPENDENCIES.md` in the same change as every new Rust or Dart dependency. Avoid large transitive dependency trees.
- Do not add network requests, telemetry, update checks, font downloads, databases, or persisted lock files. Loss of user text is a P0 defect.
- Do not edit an accepted ADR in `docs/DECISIONS.md`; add a superseding record instead. `spike/` is throwaway benchmark evidence for ADR 0005, is outside the Rust workspace, and is not built by CI.
