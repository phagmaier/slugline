# Manual verification gates

Some properties of this application are properties of the *session* — the input
method, the screen reader, the printer, the display server — and no test in
this repository can stand in for them. Each active gate below names what automation
already proves, what a person still has to do, and exactly how. None of them
blocks day-to-day development. Run them during the explicitly requested final
release validation and record the results here (date, machine, pass/fail).
Routine task completion does not require repeating or enumerating these gates.
Retired entries are historical or optional checks, not release requirements.

## 0. What was already checked on 2026-09-13

On an Omarchy (Arch) Wayland desktop, against this tree:

- `cargo test -p slugline_render_pdf` — green, including `element_indents`
  (the automated half of gate 3).
- `flutter test` — 508/508 green.
- HiDPI smoke: the debug bundle launched under `GDK_SCALE=2`, opened the
  120-page reference script, rendered correctly (screenshot verified: headings,
  dialogue, parentheticals, gutter page number all correct), and exited cleanly.
- Not installed on that machine: `ibus`, `orca`, `xorg-server-xvfb`
  (integration tests therefore run in CI only — which already gates all seven).

## 1. `ibus` + CJK input

**Status:** retired at the user's request on 2026-10-09 (ADR 0069).
Japanese/Chinese input-method composition and input-method emoji validation
are outside the requested product scope and no longer a release gate.

**Historical evidence:** No real IBus session was exercised. Prerequisite
checks on 2026-10-09 found no IBus tools on PATH or Anthy/Pinyin component
files. This gate was retired without establishing a real-IME pass.

## 2. Orca screen-reader pass

**Status:** retired at the user's request on 2026-10-09.
Verified Orca compatibility is outside the requested product scope and is no
longer a release gate. Existing accessibility support remains in place.

Automation proves the semantics tree (`test/editor/accessibility_test.dart`
asserts on `SemanticsData`: labels, values, selection base/extent, actions).
It cannot prove Orca reads a screenplay *well*.

**Optional verification procedure:**

1. `sudo pacman -S --needed orca`, enable in Settings → Accessibility.
2. Open the reference script with Orca running. Arrow through a scene heading,
   an action paragraph and a dialogue exchange. Expected: each block announced
   with its element type, then its text; the caret block exposes the selection.
3. Type a sentence with Orca on. Expected: characters/words echoed, one undo
   step per typing run (screen-reader typing bypasses coalescing — known and
   accepted, but confirm it is one step per run, not per character).
4. Open the library, the navigator and the export dialog. Expected: rows read
   as "title, time, pages"; dialogs read their titles and focused controls.

**Historical evidence:** Prerequisite check on 2026-10-09 found no Orca executable
on PATH in the current environment. No real-desktop Orca pass was performed;
this gate was retired without establishing verified Orca compatibility.

## 3. Print calibration overlay

Automation pins the grid (`render_pdf/tests/element_indents.rs` measures a
finished PDF with `pdftotext -bbox`; ADR 0034 records the afterwriting /
screenplain comparison). Re-run the human half only if `layout::metrics` or
the renderer changed since ADR 0034:

1. Export the ADR's short script to PDF (US Letter).
2. `cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf`
3. `pdftotext -bbox out.pdf - | head` and confirm every baseline still lands on
   the six-lines-to-the-inch grid and the indents match §5.2.
4. Open in a viewer (Evince/Okular) and print one page. Expected: 12pt Courier
   Prime, 1" top/bottom margins, page number 0.5" from the top. Page 1 carries
   no number unless “Number the first page” is on (ADR 0048), so print page 2,
   or turn the option on, to see one.

## 4. HiDPI and fractional scaling

Automation covers in-app text scaling (`writing_polish_test.dart` pumps 800px
windows at 1.5×). The compositor half needs eyes:

1. `GDK_SCALE=2 ./build/linux/x64/release/bundle/slugline` on a HiDPI output.
   Expected: crisp glyphs, sheet corners still 4px, no overflow stripes.
2. Fractional scale (e.g. 150% in the compositor settings). Expected: no
   half-pixel caret/selection drift while scrolling a long script.
3. Resize the window from fullscreen down to ~800px wide. Expected: the script
   shrinks to fit (fitted size), the element bar ellipsizes without overflow,
   the export dialog shrinks instead of striping (min 480px, then scrolls).


## 5. Real-desktop runtime budgets

F9's automated Xvfb/llvmpipe harness enforces a separate 320 MiB RSS regression
ceiling. It cannot establish whether the original 250 MiB limit is exceeded on
a GPU desktop. The same harness has a manual profile that keeps that limit:

1. Build with `cd app && flutter build linux --release`, then return to the
   repository root. Use a real desktop with GPU rendering (X11, or XWayland on
   Wayland), scale 1 and `xdotool` installed. Unset `LIBGL_ALWAYS_SOFTWARE` and
   `LP_NUM_THREADS` if previously set for headless tests; confirm hardware
   rendering with the desktop's graphics diagnostics.
2. Run `python3 tools/check_runtime_budgets.py --desktop --output target/runtime-budgets-desktop.json`.
   Do not interact with or move focus from its disposable windows. It uses
   isolated XDG directories and copies the reference script, leaving personal
   scripts and preferences alone. The script establishes and checks X input
   focus; a person must confirm the visible editor and caret and actual GPU use.
3. Expected: best-of-five first-frame startup < 500 ms, a ten-second idle
   interval with zero CPU ticks and voluntary switches, and best-of-three
   reference-script RSS < 250 MiB over three consecutive observation intervals.
   Inspect all recorded samples, not only the passing minimum. Record the date,
   desktop/GPU, toolchain and report here. A desktop that runs an accessibility
   bus wakes the main thread through GTK's bridge some seconds after a burst of
   frames: one switch, no CPU tick (ADR 0065). Say so if that is what an
   interval shows; it is the desktop's message, not a timer of Slugline's.

**Result:** pending. The 2026-10-06 Xvfb baseline exceeds 250 MiB and does not
settle the real-desktop claim. A headless pass does not close this gate.
