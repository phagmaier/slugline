# spell — scoped agent notes

Scope: pure Hunspell-compatible checking over immutable block snapshots.
Depends on nothing in the workspace.

Key files: `src/lib.rs`. The bridge surface is
`crates/bridge/src/api/spell.rs`; presentation is the editor's spell
dialog.

Invariants:

- No automatic correction. Only Replace sends an `EditCommand`; everything
  else is an overlay the editor paints (ADR 0036).
- The checker never sees a mutable document — snapshots only.

Verify: `cargo test -p slugline_spell`.

Governing ADRs: 0036. Full rules in `AGENTS.md`; the layer map in
`docs/ARCHITECTURE.md`. When an ADR changes this crate, update this file in
the same change.
