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
- Alignment and wrapping use printed width (paired markers and escape slashes
  removed), with exact source spans and pre-resolved output runs (ADR 0057).
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
- Forced Character cues preserve authored case in both lanes and continuation
  labels. Unforced cues and scene headings keep capitals. Case presentation
  never alters text, source identity or source/UTF-16 boundaries (ADR 0060).
  The wrap fingerprint includes `forced`; no extra block lookahead is needed.

Rust uppercase display is shared with `fountain::case`, so necessary saved cue
markers and rendering agree through reopen (ADR 0060).

Verification follows the [root policy](../../AGENTS.md#verification): run the
relevant `cargo test -p slugline_layout` filter or test target. Break/checkpoint
changes need incremental differential coverage; wrap changes need the Rust/Dart
line-break contract checks. Use the whole crate only when warranted. Regenerate
fixtures only for deliberate output/contract changes:
`UPDATE_LAYOUT_GOLDENS=1 cargo test -p slugline_layout --test golden`,
`UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential`
— each needs a sentence in the commit message.

Governing ADRs: 0020, 0022, 0044, 0046, 0048, 0049, 0054, 0057, 0060. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. Update these notes only
when their invariants or pointers change.
