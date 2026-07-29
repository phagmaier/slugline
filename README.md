<h1 align="center">Slugline</h1>

<p align="center">
  <strong>A fast, keyboard-driven screenplay editor for Linux.</strong><br />
  Write in plain Fountain. Export submission-quality PDFs.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Linux-333.svg?logo=linux" />
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-576cbc" />
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3%2FOFL-576cbc" />
</p>

---

<!-- TODO: replace these with real screenshots and a video -->
<p align="center">
  <img src="docs/screenshots/editor.png" alt="The editor" width="720" />
  <br/>
  <em>The editor, with autocomplete, scene navigator, and live spell-check.</em>
</p>

<p align="center">
  <img src="docs/screenshots/preview.png" alt="Page preview" width="720" />
  <br/>
  <em>Real-time page preview — the same layout the PDF will print.</em>
</p>

<p align="center">
  <img src="docs/screenshots/pdf.png" alt="Exported PDF" width="720" />
  <br/>
  <em>Exported PDF, typeset in Courier Prime to the inch — submission ready.</em>
</p>

---

## What is this?

Slugline is a desktop screenplay editor for writers who want a tool that stays
out of the way. You write in **[Fountain][fountain]** — plain text you can read
and edit anywhere — and Slugline gives you a clean editing surface, a live
page-count, and PDFs that match what a production office expects.

It does **not** need an account, an internet connection, or a subscription. It
never phones home. Your scripts live on your disk as `.fountain` files, and they
always will.

## Features

- **Fluid Fountain editing** — type scene headings, character cues, dialogue,
  transitions and more without reaching for the mouse. Slugline recognises
  Fountain syntax as you type and keeps the formatting invisible.
- **Keyboard-first** — every action has a shortcut. The command palette
  (<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>) lets you reach anything by
  name. See `docs/KEYMAP.md` for the full map.
- **Live autocomplete** — character names and scene headings are suggested from
  what you've already written.
- **Spell-check** — checks against your system's Hunspell dictionaries as you
  type. Underlines mistakes; never changes your text.
- **Real-time pagination** — the page count is always current, built from the
  same engine that produces the PDF. Six lines to the inch, exactly.
- **PDF export** — deterministic, submission-quality output in Courier Prime.
  Same script, same bytes, every time. Title page included. US Letter and A4
  both supported.
- **Fountain export** — a clean, canonical copy of your script. Great for sharing
  or checking into version control.
- **Script library** — browse every `.fountain` file you've worked on, with
  page counts, last-opened dates, and quick search.
- **Crash recovery** — if the editor quits unexpectedly, your unsent work is
  waiting for you the next time you open that script.
- **External-change detection** — if something else writes your file while it's
  open, Slugline asks before overwriting anything.
- **Title page editor** — fill in title, author, contact, and notes; the PDF
  prints it on its own sheet, unnumbered.

## Install

Build the release tarball and run the installer:

```sh
./tools/package.sh                                    # builds dist/slugline-<version>-linux-x64.tar.gz
./dist/slugline-*/install.sh                          # installs into ~/.local
sudo ./dist/slugline-*/install.sh /usr/local          # or system-wide
```

See [Building from source](#building-from-source) for the dependencies you'll
need first. The installer puts the binary, desktop entry, icon, MIME
association, and both licence texts in place and refreshes the desktop caches.
An `uninstall.sh` beside it reverses everything. Neither touches your scripts,
preferences, or backups.

A Flatpak manifest lives at `packaging/flatpak/` and an AppImage script at
`tools/make_appimage.sh` — these aren't published yet, but they're ready for
when packaged distribution starts.

## Quick start

```sh
slugline                         # opens the library
slugline my-script.fountain      # opens or creates a script
slugline --version
slugline --help
```

Open a `.fountain` file and start typing. Here is enough Fountain to write an
entire screenplay:

```fountain
Title: My Script
Author: Jane Doe

INT. COFFEE SHOP - DAY

A writer stares at a screen. The cursor blinks.

WRITER
(to herself)
It all starts with a scene heading.

CUT TO BLACK
```

Save with <kbd>Ctrl</kbd>+<kbd>S</kbd>. Export a PDF with
<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd>. Everything else is in the command
palette.

> [!TIP]
> If you're new to Fountain, start at [fountain.io][fountain]. The syntax fits
> on a napkin, and Slugline supports every production element in the spec.

## Why Fountain?

[Fountain][fountain] is a plain-text markup language for screenplays. A
`.fountain` file looks like a script and reads like a script, but it is also
valid plain text — you can open it in any editor, diff it in git, or email it to
a collaborator.

Slugline reads and writes Fountain **losslessly** — every byte you didn't change
comes back out exactly as it went in. No reformatting, no surprises.

## Building from source

You need Flutter (stable), a Rust toolchain, and GTK 3 development headers:

```sh
# Arch
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 xz

# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

# Optional: needed for one PDF text-extraction test
sudo apt install poppler-utils   # or pacman -S poppler
```

Then:

```sh
cd app
flutter run -d linux                 # debug
flutter build linux --release        # release
```

`flutter build linux` compiles the Rust workspace through cargokit and bundles
`libslugline_bridge.so` — there is no separate Rust build step.

## How it works

Slugline is built in two halves that share one definition of a screenplay:

| Layer | What it does |
|-------|-------------|
| **Rust** (`crates/`) | Fountain parsing and serialisation, document model with undo, pagination engine, PDF renderer, atomic file I/O, crash journal, Hunspell-compatible spell-check, and the actor thread that owns all state. |
| **Dart/Flutter** (`app/`) | The editor surface, keyboard workflow, autocomplete, library, title-page form, preview, export dialog, navigator, and spell-check presentation. |

The editor never decides where a page ends — the Rust paginator does. The Rust
side never touches the screen — Flutter owns every pixel. They talk through a
generated bridge at `crates/bridge/`.

Architecture decisions are recorded in `docs/DECISIONS.md`.

## Development

```sh
cargo test --workspace                                    # Rust (543 tests)
python3 tools/check_layering.py                           # crate layering
python3 tools/check_version.py                            # consistent versioning
cd app && flutter test                                    # Dart unit tests (328)
cd app && xvfb-run -a flutter test integration_test/ -d linux   # integration (56)
./tools/check_no_network.sh                               # network-isolation gate
cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings
```

Run integration tests under `xvfb-run` — they open real windows and need a
fixed virtual display for reproducible results (`xorg-server-xvfb` on Arch,
`xvfb` on Debian).

### Project layout

```
crates/          Rust — fountain, document, layout, render_pdf, storage, spell, bridge
app/             Flutter application
fuzz/            cargo-fuzz targets (nightly only, not in CI)
spike/           Editor prototypes kept as evidence for ADR 0005
testdata/        Fountain corpus and golden files
tools/           Build and CI scripts
docs/            Architecture decisions and dependency justifications
```

### Regenerating the bridge

Only after changing `crates/bridge/src/api/`:

```sh
cargo install flutter_rust_bridge_codegen cargo-expand   # once
cd app && flutter_rust_bridge_codegen generate
```

Generated Dart under `app/lib/src/rust/` is committed and must not be
hand-edited.

## Verification

**2026-07-27** — Rust 543 tests including 2 doc tests, Dart 328 unit and 56
integration, `flutter analyze` clean, `clippy -D warnings` clean, layering and
version checks green, both release binaries stripped, network-isolation gate
passing, release build under 60 MiB.

## What's left?

A handful of manual checks that need a person at a machine — Wayland/X11 with
HiDPI and fractional scaling, two distributions with different GTK versions,
real `ibus` + CJK input, and printing from a PDF viewer. None are code changes;
they're verification gates this machine cannot exercise.

## License

The code is [GPLv3](LICENSE). The bundled Courier Prime typeface is under the
[SIL Open Font License](crates/render_pdf/fonts/OFL.txt).

---

<p align="center">
  <sub>No telemetry. No accounts. No network. Just your script.</sub>
</p>

[fountain]: https://fountain.io
