# Remaining work

This is a working checklist of the open follow-ups currently recorded across
the project. The numbered backlog in [docs/BACKLOG.md](docs/BACKLOG.md) has no
unchecked items; these entries come from its unresolved findings and from
[docs/MANUAL_GATES.md](docs/MANUAL_GATES.md). Check an item off here when it is
finished, and update its source note if the status or evidence changes.

## Bugs and engineering follow-ups

- [x] Fix generic `apply_group` rollback so a rejected grouped edit preserves
  Redo history that existed before the group. See
  [X7's resolved finding](docs/BACKLOG.md#x7).
  **Result:** Confirmed and fixed in `Preserve history when grouped edits fail`:
  every group stages its history until success, retaining prior Undo/Redo and
  pending typing on rejection or no-op. Document regressions and the bridge
  document API tests pass.
- [x] Investigate the pagination case where an action paragraph taller than a
  page arrives when the current page is exactly full: the next page starts
  with a blank row. Update the incremental/full-pagination expectation when
  correcting it. See [F8's remaining finding](docs/BACKLOG.md#f8).
  **Result:** Confirmed and fixed in `F8 — Drop leading blanks when oversized actions cross pages`:
  oversized actions carry over before spacing when fewer than two content rows
  fit, so the new page starts with content. Break-rule regressions, full/incremental
  differential tests (including checkpoint reuse), and unchanged layout goldens pass.
- [x] Investigate the inherited hosted startup failure noted during X3/X4/X6
  work and record whether it still reproduces. The backlog calls it unresolved
  but does not include the original failure details. See [X3](docs/BACKLOG.md#x3),
  [X4](docs/BACKLOG.md#x4), and [X6](docs/BACKLOG.md#x6).
  **Result:** Reviewed in `F9 — Close the inherited startup follow-up as not reproduced`:
  the historical ten-second timeout is retained, but the latest startup-measuring
  hosted run [37936974961](https://github.com/phagmaier/slugline/actions/runs/37936974961)
  at `ebd12d8` completed all five launches and passed at 413.076 ms best.
  Closed as non-reproduced under the requested triage rule; the original cause
  remains unknown, diagnostics remain enabled, and newer Development checks
  do not measure startup.

## Manual validation

These checks need a real desktop or external application. They are final
validation work and do not block routine development.

- [ ] Repeat print calibration if layout metrics or the renderer changed since
  ADR 0034; record the result. See
  [manual gate 3](docs/MANUAL_GATES.md#3-print-calibration-overlay).
- [ ] Check HiDPI and fractional scaling on a real desktop, including resizing
  a long script and the export dialog. See
  [manual gate 4](docs/MANUAL_GATES.md#4-hidpi-and-fractional-scaling).
- [ ] Measure startup, idle behavior, and RSS on a real GPU desktop against the
  250 MiB limit. See
  [manual gate 5](docs/MANUAL_GATES.md#5-real-desktop-runtime-budgets).
- [ ] Verify import/export with a genuine Final Draft file; the X2 record says
  this compatibility check remains manual. See
  [X2](docs/BACKLOG.md#x2).

## Findings to triage

These are documented observations without a confirmed defect or a dedicated
backlog item. Decide whether to investigate, promote, or close them with a
reason.

- [x] Review the immediate Ctrl+W-after-Save observation: the close prompt can
  briefly say there are unsaved edits after the bytes have reached disk. See
  [the B16 follow-up note](docs/BACKLOG.md#found-along-the-way).
  **Result:** Confirmed and fixed in `Wait for explicit Save before confirming close`:
  close waits for native input and active explicit saves before checking dirty
  state. File-workflow and native-input widget regressions pass, including a
  newer edit and failed save; the original Wayland driver was not rerun.
- [x] Investigate the empty-cursor-name GTK warning seen at launch and establish
  whether it affects behavior. See
  [the B16 follow-up note](docs/BACKLOG.md#found-along-the-way).
  **Result:** Investigated in `Classify the GTK cursor warning at startup`:
  Flutter 3.44.8 initializes its Linux cursor name to an empty string; GTK rejects
  that lookup and inherits the default cursor. The isolated native Wayland probe
  rendered the editor, loaded the subsequent default cursor, and closed with exit 0
  without changing the script bytes; no behavioral defect was observed in these
  checks, and the upstream initialization warning remains.
- [x] Review the GTK/Flutter startup frame-size warning seen during the W7
  native launch; later frames rendered correctly, and its cause is unknown.
  See [the W7 follow-up note](docs/BACKLOG.md#found-along-the-way).
  **Result:** Reviewed in `W7 — Close the startup frame-size follow-up as not reproduced`:
  an uninstrumented native Hyprland launch of the existing Flutter 3.44.8 debug
  bundle rendered at 1900 × 1008 without the frame-size warning, closed normally
  with exit 0, and preserved exact CRLF script bytes. Closed under the requested
  non-reproduction rule; the historical release-launch cause remains unknown
  (`target/frame-size-triage/wayland-verified/`).
