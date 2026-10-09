# document — scoped agent notes

Scope: identity and history over `fountain`'s syntax. `Block` is an `Element`
plus a `BlockId`; `Document` adds the id counter, retained source and undo.
Depends only on `fountain`.

Key files: `src/document.rs`, `src/edit.rs` (`EditCommand`, grouping),
`src/workflow.rs` (Enter/Tab tables), `src/history.rs`, `src/recovery.rs`,
`src/entities.rs`, `src/find.rs`.

Invariants:

- Kinds are re-exported from `fountain`, never redeclared (ADR 0008).
- `EditCommand` carries UTF-8 byte offsets. The bridge owns the `*_utf16`
  form and converts on the way in; nothing here touches UTF-16 (ADR 0008).
- `InsertBlocks` takes id-less `NewBlock`s, so id reuse is decided here, and
  `apply` returns `Result` instead of panicking on stale ids.
- Multi-command edits (paste, Enter, Replace All) go through the grouping
  primitive so one user gesture is one undo transaction; a mid-group failure
  rolls back (ADR 0010).
- Automatic re-classification is `Document::reinfer` over the patch plus one
  block either side, and joins the keystroke's transaction. Never
  re-classify forced, empty, marker-written or dual blocks (ADR 0011).
- This crate has no clock; coalescing is closed by the caller's `commit()`.
- Semantic interchange imports use `Document::from_script`: fresh identities,
  dirty revision, no source/provenance and no history. Snapshot accessors borrow
  title and elements; Opaque imports remain read-only (ADR 0055).
- A semantic import with no body still has an editable forced empty Action.
  Its explicit `!` representation survives Save/reopen, so later edits and
  recovery patches retain block identity instead of acting on a missing caret.
- Explicit scene-number commands edit only recognised suffixes through one
  group, mapping both selection endpoints in Rust. No-op commands change
  neither revision nor undo depth (ADR 0056).
- Grouped inline formatting records the exact returned selection through
  `Grouped::set_selection`, so redo restores content endpoints/direction as well
  as text; validation is atomic with the group (ADR 0057).
- ADR 0061's explicit OmitSelection/OmitScene/RestoreOmitted commands are the
  only safe creation/replacement path for Opaque boneyards without provenance.
  Ordinary opaque edits/inserts remain refused. Restoration validates seam
  witnesses and rolls late failures back.
- Save is not an edit: live kind pins, authored case and history stay intact.
  Reload takes its pin truth from native source syntax; canonical round-trips
  compare kind/text/dual, not redundant pins. Undo restores provenance and pins
  together (ADR 0059); keep identity-bearing empty forced Action blocks.

Verify: `cargo test -p slugline_document`.

Governing ADRs: 0008, 0010, 0011, 0055, 0056, 0057, 0059, 0061. Full rules in `AGENTS.md`; the layer map
in `docs/ARCHITECTURE.md`. When an ADR changes this crate, update this file
in the same change.
