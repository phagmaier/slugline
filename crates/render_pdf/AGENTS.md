# render_pdf — scoped agent notes

Scope: PDF bytes. TrueType subsetter, sfnt writer, PDF object writer,
SHA-256 — all written here, no dependency outside the workspace (ADR 0032).
Depends on `layout` and `fountain` (`document` as a dev-dependency for
tests).

Key files: `src/pdf.rs`, `src/lib.rs` (`emphasis_runs`), `src/sfnt.rs`,
`src/fonts.rs`, `src/sha256.rs`, `fonts/` (vendored Courier Prime).

Invariants:

- The renderer makes no layout decisions. Every row and column comes from
  `layout`; `Geometry` only multiplies a grid cell by its point size.
- Output emphasis is resolved before wrapping: body scopes cross explicit hard
  lines/pages; title source hard lines resolve individually before soft wraps.
  LayoutLine.resolved_runs prevents re-parsing split markup (ADR 0057).
- Dual lanes consume each source row's resolved runs, never pair markers in
  spatial output-fragment order (ADR 0054).
- Case is already resolved by layout: forced Character cues retain their own
  case in content, styled runs and continuation labels. Neither preview nor
  PDF uppercases them again, and source identity stays intact (ADR 0060).
- Do not replace a font face without re-running the golden hash test; the
  editor draws in the same vendored faces via symlinks, so both change
  together (ADR 0032).
- `tests/text_extraction.rs` needs `poppler-utils`; without it the test
  prints `SKIPPED`.
- To look at a PDF rather than a hash:
  `cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf [a4]`.

Verification follows the [root policy](../../AGENTS.md#verification): run the
relevant `cargo test -p slugline_render_pdf` filter or test target. Include golden
or text-extraction coverage when output changes; use the whole crate only when
warranted. Regenerate hashes only for deliberate output changes:
`UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf --test golden`, with a
brief reason in the commit message. No release/package checks for routine edits.

Governing ADRs: 0032, 0044, 0045, 0047, 0048, 0054, 0057, 0060. Full rules in `AGENTS.md`;
the layer map in `docs/ARCHITECTURE.md`. Update these notes only when their
invariants or pointers change.
