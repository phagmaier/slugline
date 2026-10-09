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
- Inline source metadata rides on every BlockView/patch, translated only through
  offsets.rs. `doc_format_selection` validates scanner semantics, groups one
  gesture and finishes through journalled `outcome`; marker-only formatting
  preserves element kinds rather than reinferring them (ADR 0057).
- Omit selection/scene and Restore omitted text are structural, journalled
  outcomes without reinference (ADR 0061); offsets still convert only through
  `offsets.rs`, and exact pre/post selections belong to the transaction.
- Save never reparses/replaces the actor's Document to clear redundant pins.
  Source syntax becomes authority only on reload. Checkpoints describe the exact
  saved bytes and subsequent outcomes must replay against their block identities,
  including an empty forced Action's `!` representation (ADR 0059). Pass the
  saved snapshot's source-ordered identities to the journal checkpoint/rebuild;
  translate outcomes there without changing actor identities or history (ADR 0063).
- `AppState::close` is a script put away; `AppState::park` is the application
  going with it open, and is what `shutdown` uses so the next launch reopens it.
  `shutdown` and `session_park` are process-wide: a test ends its own session
  with `park` rather than calling either (ADR 0064).
- `doc_navigator` supplies outline parent/depth in source order (ADR 0058).
  Scene page/occupied-eighth length travels in the async pagination snapshot;
  deriving it never runs on the actor or the keystroke path.
- Keep `flutter_rust_bridge = "=2.12.0"` aligned with the Dart package and
  regenerate in the same change. Commit the generated bindings; never edit
  them by hand.
- Both imports create isolated candidates; publish and checkpoint a managed
  project before editor adoption. External sources are never bound to autosave.
  Legacy recovery retains its predecessor until protected managed succession
  (ADR 0068). Export is an immutable atomic copy, and conversion warnings
  require approval for its exact revision (ADR 0055).
  The imported initial body/title is the first full outcome patch against the
  normal untitled blank journal base, not an undo command or a stored FDX path
  (ADR 0062).

Verification follows the [root policy](../../AGENTS.md#verification): run the
relevant `cargo test -p slugline_bridge` filter or test target; the whole crate
only when warranted. When exposed API/types change, run
`cd app && flutter_rust_bridge_codegen generate` and include generated outputs.
Implementation-only edits do not require regeneration. Do not regenerate a
second time via `tools/check_bridge_bindings.sh` after successful generation
unless investigating drift or changing codegen configuration. Native checks
are for failures requiring the real bridge/runtime, not every bridge edit.

Governing ADRs: 0001, 0002, 0009, 0010, 0020, 0029, 0055, 0056, 0057, 0058, 0059, 0061, 0062, 0063, 0064, 0068. Full rules in
`AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. Update these notes only
when their invariants or pointers change.
