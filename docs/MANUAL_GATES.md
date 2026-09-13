# Manual verification gates

Some properties of this application are properties of the *session* — the input
method, the screen reader, the printer, the display server — and no test in
this repository can stand in for them. Each gate below names what automation
already proves, what a person still has to do, and exactly how. None of them
blocks day-to-day development; all of them should be run before calling any
1.0.x done, and the results recorded here (date, machine, pass/fail).

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

Automation proves the `TextInputClient` contract (`integration_test/ime_test.dart`:
composition, dead keys, an astral-plane composition, a composition the caret
leaves, a newline from the method, clipboard round trip). It cannot prove a real
`ibus` session, which owns its own process, timing and surrounding-text queries.

1. `sudo pacman -S --needed ibus ibus-anthy` (or `ibus-libpinyin`), log out/in.
2. `ibus-daemon -drx`, add Anthy (Japanese) and Pinyin (Chinese) in
   `ibus-setup`, set the trigger (default Super+Space).
3. Open a script, switch to Anthy, type a word with a candidate selection
   (e.g. `k a n j i` + Space + Enter). Expected: composing underline under the
   reading, committed text lands at the caret, undo takes it back in one step.
4. Repeat with Pinyin. Then: start a composition, move the caret to another
   block mid-composition, and confirm the session ends on the old block rather
   than writing into the new one (the `_sessionBlock` behaviour).
5. Type an emoji through the method (Ctrl+Shift+E picker or `:name:` entry).
   Expected: no offset drift after it — caret, selection and the next keystroke
   all agree.

Failures here outrank all other gates: ADR 0005's fallback (adopting
`super_editor`) gets more expensive every release this gate is deferred.

## 2. Orca screen-reader pass

Automation proves the semantics tree (`test/editor/accessibility_test.dart`
asserts on `SemanticsData`: labels, values, selection base/extent, actions).
It cannot prove Orca reads a screenplay *well*.

1. `sudo pacman -S --needed orca`, enable in Settings → Accessibility.
2. Open the reference script with Orca running. Arrow through a scene heading,
   an action paragraph and a dialogue exchange. Expected: each block announced
   with its element type, then its text; the caret block exposes the selection.
3. Type a sentence with Orca on. Expected: characters/words echoed, one undo
   step per typing run (screen-reader typing bypasses coalescing — known and
   accepted, but confirm it is one step per run, not per character).
4. Open the library, the navigator and the export dialog. Expected: rows read
   as "title, time, pages"; dialogs read their titles and focused controls.

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
   Prime, 1" top/bottom margins, page number 0.5" from the top.

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
