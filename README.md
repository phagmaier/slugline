# Slugline

A fast, keyboard-driven screenplay editor that reads and writes plain Fountain
files and produces submission-quality PDFs. Linux only.

**Status: Phases 0–8 written; Phase 9 (spell checking) is next.**
`crates/fountain` and `crates/document` read and write Fountain losslessly and hold
the model, the edit commands and undo. `crates/bridge` is the actor thread and the
§6 surface, `app/` is the editor, keyboard workflow, autocomplete, library,
preview, export and navigator, and `crates/storage` is the atomic save, crash
journal, backups, preferences and library index. `crates/layout` paginates and
`crates/render_pdf` writes deterministic PDFs from that layout. `spell` remains
the one-constant placeholder for Phase 9. See `docs/DECISIONS.md`.

## Remediation status

The **stabilization gate is passed**, as of 2026-07-26. A mid-project audit is
recorded in `REVIEW.md`; the repairs it called for are tracked phase by phase in
`REMEDIATION_PLAN.md`, on branch `fix/mid-project-remediation`. All fourteen
findings are closed, the Phase 10 verification is green — Rust 435 tests, Dart 320
unit and 49 integration, the real ENOSPC path, and the keystroke benchmark inside
its §1.3 budget — and Phase 7 (PDF export and preview) is open for work.

The phases were: 0 baseline, 1 recovery durability, 2 multi-line blocks, 2B keys
swallowed by panels, 3 documentation and CI, 4 save serialization and the watcher,
5 scroll restoration, 6 layout convergence and the pagination bridge, 7 export
copy versus Save As, 8 defensive cleanup, 9 the manual IME, accessibility and
end-to-end gates, and 10 final verification. What was knowingly left undone is the
deferred backlog at the end of that plan; none of it blocked Phases 7 or 8, which
are now written too — PDF/title-page/preview output and scene/character navigation.

## Requirements

Flutter (stable), a Rust toolchain, and the GTK desktop build dependencies.

```sh
# Arch
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 xz

# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

`poppler` is optional and test-only: `cargo test` reads an exported PDF back
through `pdftotext` to prove the text in it is selectable and in reading order.
Without it that one test prints `SKIPPED` and stops rather than passing quietly.

```sh
sudo pacman -S --needed poppler   # Arch
sudo apt install poppler-utils    # Debian/Ubuntu
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
