<h1 align="center">Slugline</h1>

<p align="center">
  <strong>A fast, keyboard-driven screenplay editor for Linux.</strong><br />
  Write in plain Fountain. Export submission-quality PDFs.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Linux-333.svg?logo=linux" />
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.2-576cbc" />
  <img alt="License" src="https://img.shields.io/badge/license-GPLv3%2FOFL-576cbc" />
</p>

---

<p align="center">
  <img src="githubAssets/editor.png" alt="The editor" width="720" />
  <br/>
  <em>The editor, with autocomplete, scene navigator, and live spell-check.</em>
</p>

<p align="center">
  <img src="githubAssets/opening.png" alt="File Selector" width="720" />
  <br/>
  <em>Work on multiple projects and keep track of all of them.</em>
</p>

<p align="center">
  <img src="githubAssets/pdf.png" alt="Exported PDF" width="720" />
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
  (<kbd>Ctrl</kbd>+<kbd>K</kbd>) lets you reach anything by
  name. See `docs/KEYMAP.md` for the full map.
- **Live autocomplete** — character names and scene headings are suggested from
  what you've already written.
- **Scene navigator** — outline sidebar to jump straight to any scene in your
  screenplay.
- **Find & replace** — quick search and replace designed specifically for text
  and Fountain formatting.
- **Spell-check** — checks against your system's Hunspell dictionaries as you
  type. Underlines mistakes; never changes your text.
- **Real-time pagination** — the page count is always current, built from the
  same engine that produces the PDF. Six lines to the inch, exactly.
- **PDF export** — deterministic, submission-quality output in Courier Prime.
  Same script, same bytes, every time. Title page included. US Letter and A4
  both supported.
- **Fountain export** — a clean, canonical copy of your script. Great for sharing
  or checking into version control.
- **FDX interchange** — import screenplay content into a new Fountain script,
  or export an editable FDX copy for collaborators. Conversion warnings are
  shown before proceeding; production revision and page-layout fidelity is not
  promised.
- **Script library** — browse every `.fountain` file you've worked on, with
  page counts, last-opened dates, and quick search.
- **Crash recovery** — if the editor quits unexpectedly, your unsent work is
  waiting for you the next time you open that script.
- **External-change detection** — if something else writes your file while it's
  open, Slugline asks before overwriting anything.
- **Title page editor** — fill in title, author, contact, and notes; the PDF
  prints it on its own sheet, unnumbered.

## Install

> [!IMPORTANT]
> The first public release targets **x86_64 Linux only**. Slugline has primarily
> been tested on Arch Linux; reports from other current desktop distributions
> are welcome.

Download published builds from the
**[latest GitHub Release](https://github.com/phagmaier/slugline/releases/latest)**.
`SHA256SUMS` on that page covers both release artifacts.

### AppImage

Download `Slugline-<version>-x86_64.AppImage`, then:

```sh
chmod +x Slugline-*-x86_64.AppImage
./Slugline-*-x86_64.AppImage
```

The AppImage is self-contained and does not install files. Keep it wherever you
keep applications. On systems where AppImage/FUSE mounting is unavailable, it
can still be unpacked with `--appimage-extract`.

### Release tarball

Download `slugline-<version>-linux-x86_64.tar.gz` and `SHA256SUMS` from the same
release, then extract and install for your user:

```sh
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf slugline-*-linux-x86_64.tar.gz
cd slugline-*-linux-x86_64
./install.sh
```

The default prefix is `~/.local`; pass an absolute prefix such as `/usr/local`
to `install.sh` if you are deliberately managing a shared installation. The
included `uninstall.sh` accepts the same prefix. It removes only packaged files
and never removes scripts, preferences, backups, or recovery data.

### Building from source

After installing the [source build requirements](#source-build-requirements),
run these commands from the checkout root. No `sudo` is needed for installation:

```sh
(cd app && flutter pub get --enforce-lockfile)
./tools/package.sh
./tools/smoke_test_tarball.sh
version="$(./tools/release_version.sh)"
"./dist/slugline-$version-linux-x86_64/install.sh"
export PATH="$HOME/.local/bin:$PATH"
slugline --version
```

The packaging build remaps source paths in the Rust library, then creates both
`dist/slugline-<version>-linux-x86_64.tar.gz` and its extracted staging directory.
The installer puts the command in `~/.local/bin`, the application bundle in
`~/.local/lib/slugline`, and the launcher, icons and Fountain MIME definition
under `~/.local/share`.

Keep `~/.local/bin` in your **desktop-session PATH**, not just your interactive
shell's PATH: the launcher uses `Exec=slugline %f` and `TryExec=slugline`.
For a UWSM-managed desktop, add this line to `~/.config/uwsm/env`, preserving any
existing contents, then log out and back in so launchers inherit it:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The installer registers Fountain support without overriding your chosen default.
To make Slugline the application used when opening `.fountain` files:

```sh
xdg-mime default com.phagmaier.slugline.desktop text/x-fountain
xdg-mime query default text/x-fountain
```

The query should print `com.phagmaier.slugline.desktop`. Open Slugline from your
application menu or open a `.fountain` file in your file manager.

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

Save with <kbd>Ctrl</kbd>+<kbd>S</kbd>. Open Preview and export with
<kbd>Ctrl</kbd>+<kbd>P</kbd>, then choose PDF export; the preview opens on the
page your caret is on. Everything else is in the command palette.

To bring in an `.fdx` screenplay, choose **Import FDX…** in the library or
command palette. Review any conversion warnings before replacing the current
editor. The original FDX stays untouched; the imported script is unsaved and
**Save** asks for a `.fountain` destination. Ordinary **Open** remains Fountain.
Choose **Export FDX copy…** in Preview to share screenplay content. If the
script changes after warning approval, the new conversion needs fresh approval.
FDX interchange is not an exact round trip for production revisions, locked
pages, custom fonts or margins.

New or edited blocks save with `.`, `@`, `>` and `!` only where Fountain needs
them to preserve their meaning. Existing unedited source stays byte-exact.
Tab and element shortcuts pin the type while you edit, including after Save;
after reload the saved syntax decides the type. Text and capitalization are
never automatically changed on disk. A deliberately mixed/lowercase cue such
as `McCLANE` or `mary` therefore needs `@` to retain its Character meaning.
Type `MCCLANE` or `MARY` when you want a standard uppercase cue.

Use the palette for Preferences, Spell checking, Keyboard shortcuts, showing or
hiding the navigator, distraction-free mode, page/continuous view and text size.
View commands name the change they will make; text size stays between 12 and 24.

Editor, preview and PDF render Fountain's italic, bold and underline emphasis.
In the editor, paired markers remain editable as dim half-size characters;
wrapping counts printed text, not markup. Dense markup can extend beyond the
viewport: use the bottom scrollbar, or move the caret to reveal it, without
changing printed wraps. Use <kbd>Ctrl</kbd>+<kbd>B</kbd>,
<kbd>Ctrl</kbd>+<kbd>I</kbd> or <kbd>Ctrl</kbd>+<kbd>U</kbd> to wrap a selection
in one undo step. Preferences (<kbd>Ctrl</kbd>+<kbd>,</kbd>) → Page defaults →
**Bold scene headings** changes heading weight in all three views; it defaults
off and does not change wrapping.

Page 1 is left unnumbered, as is conventional; **Number the first page** in the
same Preferences section prints its `1.` in page view, preview and PDF.

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

## Source build requirements

You need Flutter 3.44.8 (the CI-pinned stable SDK), Rust 1.85 or newer, GTK 3
development headers, and desktop registration tools:

```sh
# Arch
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 xz desktop-file-utils shared-mime-info xdg-utils

# Debian/Ubuntu
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev desktop-file-utils shared-mime-info xdg-utils

# Optional: needed for one PDF text-extraction test
sudo apt install poppler-utils   # or pacman -S poppler
```

For a development run, from the checkout root:

```sh
(cd app && flutter run -d linux)
```

For a release build and user-local installation, use the
[packaging commands above](#building-from-source), rather than copying a
source-tree bundle. Do not run native integration builds and a release build
concurrently; they share Flutter build outputs.

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
cargo test --workspace                                    # Rust tests
python3 tools/check_layering.py                           # crate layering
python3 tools/check_version.py                            # consistent versioning
cd app && flutter test                                    # Dart unit tests
./tools/test_linux_integration.sh                         # Linux integration tests
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
fuzz/            cargo-fuzz targets (nightly; CI gives each a two-minute smoke run)
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

Pull requests and `main` run Rust formatting, Clippy and tests; Flutter analysis,
unit and Xvfb integration tests; version and layering checks; desktop metadata
validation; a release build; and the network-isolation gate. A version tag must
pass the same release gates plus tarball and AppImage smoke tests before GitHub
publishes any assets. See [the release guide](docs/RELEASING.md).

## What's left?

A handful of checks still need a person at a real desktop: Wayland and X11 with
HiDPI/fractional scaling, additional distributions and GTK versions, real
`ibus` plus CJK input, and printing from a PDF viewer.

## Reporting issues

Use the [GitHub issue tracker](https://github.com/phagmaier/slugline/issues).
Reduce a file to a minimal Fountain example when possible. **Do not upload or
paste a private, confidential, or unreleased screenplay into an issue or log.**

## License

The code is [GPLv3](LICENSE). The bundled Courier Prime typeface is under the
[SIL Open Font License](crates/render_pdf/fonts/OFL.txt).

---

<p align="center">
  <sub>No telemetry. No accounts. No network. Just your script.</sub>
</p>

[fountain]: https://fountain.io
