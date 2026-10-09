# bridge — scoped agent notes

Scope: the actor thread and the whole API surface. May depend on all
crates. Its generated Dart is `app/lib/src/rust/`.

Key files: `src/actor.rs` (the one `Document` owner), `src/api/doc.rs`,
`src/api/files.rs`, `src/api/layout.rs`, `src/api/events.rs`,
`src/api/spell.rs`, `src/api/lifecycle.rs`, `src/offsets.rs`,
`src/state.rs`.

Invariants:

- `AppState` lives on one actor thread; nothing else may hold a
  `Document`. Every bridge function hands the actor a closure. Long jobs
  run on a worker pool against a snapshot; a save is the pattern to copy.
- Every bridge offset is a UTF-16 code-unit offset named `*_utf16`. Only
  `src/offsets.rs` may convert UTF-16 and UTF-8; invalid boundaries return
  `None`, never rounded or clamped (ADR 0001).
- Kinds are flat on the surface (`Section` level rides alongside); results
  are patches applicable without another call; refusals are values, not
  exceptions (ADR 0009).
- Every edit reaching the document goes through `outcome` or `inferring`
  in `src/api/doc.rs`, and both append to the crash journal — never a bare
  `document.apply`. Paste and Enter are composed here into one transaction
  each (ADR 0010).
- `doc_number_scenes` and `doc_remove_scene_numbers` interrupt typing, convert
  the exact selection through `offsets.rs`, and journal one grouped outcome
  without reinference (ADR 0056).
- Keep `flutter_rust_bridge = "=2.12.0"` aligned with the Dart package and
  regenerate in the same change. Commit the generated bindings; never edit
  them by hand.
- FDX import creates an isolated unsaved session after decoding; it never binds
  the FDX source. Export is an immutable atomic copy, and conversion warnings
  require approval for its exact revision (ADR 0055).
  The imported initial body/title is the first full outcome patch against the
  normal untitled blank journal base, not an undo command or a stored FDX path
  (ADR 0062).

Verify: `cargo test -p slugline_bridge`, plus after touching `src/api/`:
`cd app && flutter_rust_bridge_codegen generate`, then
`./tools/check_bridge_bindings.sh` (the same check CI runs).

Governing ADRs: 0001, 0002, 0009, 0010, 0020, 0029, 0055, 0056, 0062. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. When an ADR changes
this crate, update this file in the same change.
