# layout — scoped agent notes

Scope: the pagination engine. Depends on `document` and `fountain` (the
`layout -> fountain` edge exists for printed-width emphasis alignment,
ADR 0044).

Key files: `src/engine.rs` (break rules, checkpoints), `src/model.rs`,
`src/metrics.rs` (the printed grid), `src/line_break.rs`.

Invariants:

- Only this crate turns preferences into page geometry. Preview, PDF and
  the editor draw the lines they are given; nothing else re-derives page
  numbers or page ends (ADR 0048).
- Alignment uses printed width (paired markers and escapes removed), never
  raw length; wrapping stays raw-width (ADR 0044).
- An incremental repagination is a full pagination arrived at sooner:
  resume and stop only where the paginator recorded it could, and count
  every beyond-the-element lookahead in `blocks_read` (ADR 0049).
- Never relax `tests/incremental_differential.rs` to a page count; it holds
  pages and checkpoints of both paths to each other.
- Consecutive lyric blocks share one leading blank; spacing resolves from
  current order including cached wraps (ADR 0046).
- Page 1 is counted but prints its number only under "Number the first
  page" (ADR 0048).
- Dual dialogue pairs source-adjacent speeches without overlap. Cache widths
  include pairing context; count partner/lookahead dependencies in
  `blocks_read`. Independent lane continuations retain source-line identity
  (ADR 0054).

Verify: `cargo test -p slugline_layout`. Golden changes are deliberate or
they are bugs:
`UPDATE_LAYOUT_GOLDENS=1 cargo test -p slugline_layout --test golden`,
`UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential`
— each needs a sentence in the commit message.

Governing ADRs: 0020, 0022, 0044, 0046, 0048, 0049, 0054. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. When an ADR changes
this crate, update this file in the same change.
