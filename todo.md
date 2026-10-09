# Remaining work

This is a working checklist of the open follow-ups currently recorded across
the project. The numbered backlog in [docs/BACKLOG.md](docs/BACKLOG.md) has no
unchecked items; these entries come from its unresolved findings and from
[docs/MANUAL_GATES.md](docs/MANUAL_GATES.md). Check an item off here when it is
finished, and update its source note if the status or evidence changes.

## Bugs and engineering follow-ups

- [ ] Fix generic `apply_group` rollback so a rejected grouped edit preserves
  Redo history that existed before the group. X7's public commands stage their
  history, but unrelated grouped commands still have this gap. See
  [X7's remaining finding](docs/BACKLOG.md#x7).
- [ ] Investigate the pagination case where an action paragraph taller than a
  page arrives when the current page is exactly full: the next page starts
  with a blank row. Update the incremental/full-pagination expectation when
  correcting it. See [F8's remaining finding](docs/BACKLOG.md#f8).
- [ ] Investigate the inherited hosted startup failure noted during X3/X4/X6
  work and record whether it still reproduces. The backlog calls it unresolved
  but does not include the original failure details. See [X3](docs/BACKLOG.md#x3),
  [X4](docs/BACKLOG.md#x4), and [X6](docs/BACKLOG.md#x6).

## Manual validation

These checks need a real desktop or external application. They are final
validation work and do not block routine development.

- [ ] Run the real IBus CJK input check (Japanese or Chinese), including
  composition, caret movement during composition, and emoji input. See
  [manual gate 1](docs/MANUAL_GATES.md#1-ibus--cjk-input).
- [ ] Complete the Orca screen-reader pass for editing, library navigation,
  and dialogs. See [manual gate 2](docs/MANUAL_GATES.md#2-orca-screen-reader-pass).
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

- [ ] Review the immediate Ctrl+W-after-Save observation: the close prompt can
  briefly say there are unsaved edits after the bytes have reached disk. See
  [the B16 follow-up note](docs/BACKLOG.md#found-along-the-way).
- [ ] Investigate the empty-cursor-name GTK warning seen at launch and establish
  whether it affects behavior. See
  [the B16 follow-up note](docs/BACKLOG.md#found-along-the-way).
- [ ] Review the GTK/Flutter startup frame-size warning seen during the W7
  native launch; later frames rendered correctly, and its cause is unknown.
  See [the W7 follow-up note](docs/BACKLOG.md#found-along-the-way).
