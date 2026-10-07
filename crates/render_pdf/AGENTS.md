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
- Output emphasis is shared with the preview through resolved runs: body
  rows pair across wraps/pages, title rows pair individually, unpaired
  markers stay ordinary characters (ADR 0045).
- Do not replace a font face without re-running the golden hash test; the
  editor draws in the same vendored faces via symlinks, so both change
  together (ADR 0032).
- `tests/text_extraction.rs` needs `poppler-utils`; without it the test
  prints `SKIPPED`.
- To look at a PDF rather than a hash:
  `cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf [a4]`.

Verify: `cargo test -p slugline_render_pdf`. Hash changes are deliberate or
they are bugs: `UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf
--test golden` — with a sentence in the commit message.

Governing ADRs: 0032, 0044, 0045, 0047, 0048. Full rules in `AGENTS.md`;
the layer map in `docs/ARCHITECTURE.md`. When an ADR changes this crate,
update this file in the same change.
