# Screenplay

A fast, keyboard-driven screenplay editor that reads and writes plain Fountain
files and produces submission-quality PDFs. Linux only.

**Status: Phase 0 complete** — toolchain, bridge, and the editor decision. There
is no editor yet; `flutter run` opens a window that proves the Rust ↔ Dart
boundary works. See `docs/DECISIONS.md`.

## Requirements

Flutter (stable), a Rust toolchain, and the GTK desktop build dependencies.

```sh
# Arch
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 xz

# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

## Build and run

```sh
cd app
flutter run -d linux                 # debug
flutter build linux --release        # release; compiles the Rust workspace too
```

`flutter build linux` compiles `crates/bridge` via cargokit and bundles
`libscreenplay_bridge.so`. There is no separate Rust build step.

## Test

```sh
cargo test --workspace                                    # Rust
python3 tools/check_layering.py                           # crate layering (§2.5)
cd app && flutter test                                    # Dart unit tests
cd app && flutter test integration_test/ -d linux         # bridge proofs, needs the .so
```

`cargo fmt --all --check` and `cargo clippy --workspace --all-targets -- -D warnings`
must both be clean; CI runs them.

## Regenerating the bridge

Only needed after changing `crates/bridge/src/api/`:

```sh
cargo install flutter_rust_bridge_codegen cargo-expand   # once
cd app && flutter_rust_bridge_codegen generate
```

Generated Dart under `app/lib/src/rust/` is committed and must never be
hand-edited.

## Layout

```
crates/          Rust core — fountain, document, layout, render_pdf, storage, spell, bridge
app/             Flutter application
spike/           Phase 0 editor prototypes. Throwaway code, kept as evidence for ADR 0005.
testdata/        Fountain corpus and golden files
tools/           Build and CI scripts
docs/            DECISIONS.md (ADRs) and DEPENDENCIES.md
```

The crate layering rule of spec §2.5 is enforced in CI: `fountain` depends on
nothing, `layout` only on `document`, `render_pdf` only on `layout`, `bridge` on
everything. No cycles, no upward dependencies.
