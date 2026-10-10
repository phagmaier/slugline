# Manual verification gates

Some properties of this application are properties of the *session* — the input
method, the printer, the display server — and no test in this repository can
stand in for them. Each active gate below names what automation already proves,
what a person still has to do, and exactly how. None of them
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
- Not installed on that machine: `ibus`, `xorg-server-xvfb`
  (integration tests therefore run in CI only — which already gates all seven).

## 1. `ibus` + CJK input

**Status:** retired at the user's request on 2026-10-09 (ADR 0069).
Japanese/Chinese input-method composition and input-method emoji validation
are outside the requested product scope and no longer a release gate.

**Historical evidence:** No real IBus session was exercised. Prerequisite
checks on 2026-10-09 found no IBus tools on PATH or Anthy/Pinyin component
files. This gate was retired without establishing a real-IME pass.

## 3. Print calibration overlay

Automation pins indents and baseline alignment
(`render_pdf/tests/element_indents.rs` reads the finished PDF's text matrices;
`text_extraction.rs` checks Poppler text extraction). Grid alignment alone does
not prove consecutive-row pitch. ADR 0034 records the afterwriting / screenplain
comparison. Re-run the human half only if `layout::metrics` or the renderer
changed since ADR 0034:

1. Export the ADR's short script to PDF (US Letter).
2. `cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf`
3. `pdftotext -bbox out.pdf out-bbox.html` reports **word bounding boxes**, not
   baselines. Group words into printed rows on each page; multiple words or
   styled runs on one baseline are one row. With the default Courier Prime
   face, the first row's `yMin` is 72 pt from the top; its actual baseline is
   81.375 pt from the top (710.625 pt in US Letter PDF coordinates). Read the
   PDF text matrices (`Tm`) or decoded character origins to check baselines;
   for these unrotated exports, convert PDF y with `page height - y`. Compare
   bounding-box tops separately, and confirm the indents match §5.2.

   Check pitch using a disposable single Action block containing several short
   consecutive hard lines, and another single Action paragraph long enough to
   soft-wrap. Each pair of consecutive printed rows must be 12 pt apart. Also
   export paragraphs separated by blank rows: one intentional blank row makes
   the next text-bearing baseline 24 pt away. Compare each gap with its expected
   row count; **do not compare the average gap over all text-bearing rows with
   12 pt**. Exclude title pages and page numbers, and never measure across pages.
4. Open in a viewer (Evince/Okular) and print one page. Expected: 12pt Courier
   Prime, 1" top/bottom margins, page number 0.5" from the top. Page 1 carries
   no number unless “Number the first page” is on (ADR 0048), so print page 2,
   or turn the option on, to see one.

**Result (2026-10-09):** Reported automated measurement: first line y0 was
72.00 pt (target 72.0 pt, pass); average line pitch was 20.00 pt (target
12.0 pt, fail). The existing PDF regression in
`render_pdf/tests/element_indents.rs` checks that printed baselines lie on the
12 pt grid, but does not assert that the average gap between text-bearing rows
is 12 pt. Intentional blank rows can make that average larger while the grid
pitch remains 12 pt. The measurement script and PDF were not retained here, so
the discrepancy is unresolved and does not establish a renderer defect. Follow
up by checking how the script groups extracted text rows and accounts for blank
rows against the PDF operators and regression fixture. No renderer change was
made; keep this gate open until the result is reconciled.

**Independent follow-up (2026-10-09):** Disposable exports measured through
actual PDF text matrices, PyMuPDF 1.28.2 character origins and Poppler 26.08.0
`-bbox` agree: four consecutive hard lines and five soft-wrapped rows have
exactly 12 pt pitch. Three Action paragraphs occupying rows 0, 2, 4 and 5 have
text-bearing gaps of 24, 24 and 12 pt: their mean is exactly 20 pt despite the
12 pt grid. The first word-box top is 72 pt and the first baseline is 81.375 pt
from the top in each fixture; the existing element-indents fixture also stays
on the 12 pt grid. No renderer defect was reproduced and no renderer/layout
change was made. The missing original artifacts prevent identifying that
report's exact method; physical print/overlay verification remains pending.

**Print (2026-10-09):** User-reported pass: a printed page was checked and
looked correct. Printer, viewer and paper were not recorded. With the
follow-up above reconciling the 20 pt average, this gate is closed.

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

**Result (2026-10-09):** User-reported visual pass: everything looked correct
and no scaling, scrolling, resize, or export-dialog issues were noticed.
Machine and exact scale settings were not recorded.

## 5. Real-desktop runtime budgets

**Status:** retired at the user's request on 2026-10-09 (ADR 0070). A
real-GPU startup, idle and 250 MiB memory measurement is no longer a release
gate. The automated Xvfb checks in `tools/check_runtime_budgets.py`, with their
separate 320 MiB ceiling, still run in CI and the release workflow.

**Historical evidence:** No real-desktop pass was established. The 2026-10-06
Xvfb baseline exceeds 250 MiB and never settled the desktop claim. One desktop
run was attempted on 2026-10-09 on Hyprland through XWayland with Intel UHD 630
graphics: three empty-script startups took 297.963, 301.824 and 309.396 ms
against the 500 ms limit, then `xdotool getwindowfocus` failed on the third
launch and the run stopped before idle or RSS were measured. The focus failure
was not investigated.

**Optional measurement:** after `cd app && flutter build linux --release`, run
`python3 tools/check_runtime_budgets.py --desktop --output target/runtime-budgets-desktop.json`
from a real X11 or XWayland session without touching its disposable windows. It
uses isolated XDG directories. A desktop accessibility bus can wake the main
thread once per interval without a CPU tick (ADR 0065); that is the desktop's
message, not a timer of Slugline's.
