# Slugline

A fast, keyboard-driven screenplay editor that reads and writes plain Fountain
files and produces submission-quality PDFs. Linux only.

**Status: Phase 1 complete** — the Fountain core. `crates/fountain` reads and
writes Fountain losslessly and `crates/document` holds the model, the edit
commands and undo. There is still no editor: `flutter run` opens the Phase 0
window that proves the Rust ↔ Dart boundary works. See `docs/DECISIONS.md`.

## Remediation status

The project is in a **stabilization gate**, not new feature work. A mid-project
audit is recorded in `REVIEW.md`; the repairs it calls for are tracked phase by
phase in `REMEDIATION_PLAN.md`, on branch `fix/mid-project-remediation`. Phase 7
(PDF export and preview) does not begin until that plan's Phase 10 authorization
gate passes.

The status line above is known to be stale — correcting it is remediation
Phase 3 (audit finding F7), not a claim this README currently makes accurately.

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
`libslugline_bridge.so`. There is no separate Rust build step.

## Test

```sh
cargo test --workspace                                    # Rust
python3 tools/check_layering.py                           # crate layering (§2.5)
python3 tools/make_reference.py --check                   # the 120-page fixture is current
cd app && flutter test                                    # Dart unit tests
cd app && flutter test integration_test/ -d linux         # bridge proofs, needs the .so
```

Benchmarks and fuzzing are not part of `cargo test`:

```sh
cargo bench -p slugline_fountain                          # §1.3 budgets, with numbers
cargo install cargo-fuzz && rustup toolchain install nightly
cd fuzz && cargo +nightly fuzz run parse -- -runs=1000000
cd fuzz && cargo +nightly fuzz run roundtrip -- -runs=1000000
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
fuzz/            cargo-fuzz targets. Separate workspace, nightly only, not built by CI.
spike/           Phase 0 editor prototypes. Throwaway code, kept as evidence for ADR 0005.
testdata/        Fountain corpus and golden files
tools/           Build and CI scripts
docs/            DECISIONS.md (ADRs) and DEPENDENCIES.md
```

The crate layering rule of spec §2.5 is enforced in CI: `fountain` depends on
nothing, `layout` only on `document`, `render_pdf` only on `layout`, `bridge` on
everything. No cycles, no upward dependencies.
