# Architecture Decision Records

One record per non-obvious choice (spec §2.5). Newest last. A record is never
edited after it is accepted — if the decision changes, add a new record that
supersedes it and say so in both.

---

## ADR 0001 — The bridge speaks UTF-16, and conversion is fallible

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

Dart strings are UTF-16, Rust strings are UTF-8. Spec §2.4 already fixes the
policy — every offset crossing the bridge is a UTF-16 code-unit offset named
`*_utf16` — but leaves open what happens when an offset is *invalid*: one that
lands between the halves of a surrogate pair, or inside a multi-byte UTF-8
sequence.

The tempting answer is to round to the nearest boundary, because it never fails
and the caller never has to think.

### Decision

`crates/bridge/src/offsets.rs` is the only module in the project permitted to
convert between the two encodings, and every conversion returns `Option`.
Invalid offsets return `None`. Nothing is rounded, clamped, or guessed.

### Consequences

* A caller bug surfaces at the boundary, as a `None`, at the moment it happens.
  Rounding would turn the same bug into text corruption somewhere else, later,
  in a document the user cares about — and §1.2 makes losing user text a P0.
* Every bridge function that takes an offset has to decide what to do with
  `None`. That is the point.
* The module is tested against a string containing ASCII, a Latin-1 accent, CJK,
  and an astral-plane emoji, with a round-trip over every byte boundary of a
  realistic line of dialogue.
* Offsets are `u32` (§3.4). `clamp_u32` saturates rather than wrapping, because
  a wrapped offset is a small plausible-looking number and a saturated one is
  obviously wrong.

---

## ADR 0002 — Rust builds through cargokit, with the FRB version pinned exactly

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

Phase 0 requires `flutter build linux --release` to compile the Rust workspace
with no manual step. `flutter_rust_bridge_codegen integrate` offers two
backends: `cargokit` (a CMake/Gradle shim, works on any Flutter) and
`native-assets` (Dart build hooks, newer, still moving).

### Decision

Use `cargokit`, with the Rust crate living at `crates/bridge` — outside the
Flutter project — via `--rust-crate-dir ../crates/bridge`, so the workspace
layout of §2.5 survives. Pin `flutter_rust_bridge = "=2.12.0"` in Cargo.toml and
`flutter_rust_bridge: 2.12.0` in pubspec.yaml.

### Consequences

* `flutter build linux --release` compiles Rust and drops
  `libslugline_bridge.so` into `bundle/lib/`. Verified; CI asserts the file
  exists and that the whole bundle stays under the 60 MB budget (§1.3). It is
  24 MB today.
* The exact-version pin is not pedantry: the Rust crate and the Dart package
  exchange a generated ABI, and a mismatch produces glue that compiles and is
  silently wrong. Bump both in one commit, then re-run codegen.
* Regenerating bindings needs `cargo-expand` installed
  (`cargo install cargo-expand`). Generated Dart under `app/lib/src/rust/` is
  committed, so a plain build does not need it. CI does not re-run codegen, so a
  stale binding is caught by the integration tests rather than by codegen diff —
  revisit if that ever bites.
* Native assets is the likely future. Nothing in the project depends on which
  backend is used, so switching later is a codegen re-run, not a migration.

---

## ADR 0003 — `freezed` is accepted as a Dart dependency

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

§1.2 requires a written justification per dependency and rejects anything with a
large transitive tree. `flutter_rust_bridge` maps a Rust enum that carries data
onto a `@freezed sealed class` in Dart, and refuses to generate without
`freezed` present. §3.4's `EditCommand` and §6's `CoreEvent` are both exactly
that kind of enum, so this is not avoidable by design choice — only by giving up
sum types at the boundary and hand-rolling tag + nullable-field structs.

### Decision

Take the dependency: `freezed_annotation` at runtime, `freezed` and
`build_runner` as dev dependencies.

### Consequences

* Dart gets exhaustive `switch` over `CoreEvent` and `EditCommand`. The compiler
  catches a missing variant, which for an event enum that will keep growing is
  worth more than the dependency costs.
* `build_runner` runs during `flutter_rust_bridge_codegen generate`, never during
  `flutter build`. Generated `.freezed.dart` is committed, so the build stays a
  one-step build.
* The alternative — a struct with a `kind` tag and a nullable field per variant —
  moves the exhaustiveness check from the compiler to code review. Rejected.

---

## ADR 0004 — Layering is enforced by a script, not by cargo-deny

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

### Context

§2.5 mandates that CI enforce "no upward crate dependencies" and suggests
`cargo-deny`. But cargo-deny's ban list is designed for *external* crates and
licences; expressing "`layout` may depend on `document` and nothing else in this
workspace" in it is awkward and produces an unhelpful message when violated.

### Decision

`tools/check_layering.py` reads `cargo metadata --no-deps`, compares each
crate's intra-workspace dependencies against an explicit allow-table, and fails
with the offending edge named. Standard library only.

### Consequences

* CI needs Python (present on every runner) and nothing else.
* Verified by construction: adding `slugline_layout` to `fountain`'s
  dependencies makes the check fail with
  `fountain -> layout violates §2.5 (allowed: nothing)`, and removing it makes it
  pass again.
* The same table appears twice — in the script and in `WORKSPACE_CRATES` in
  `handshake.rs`, which the demo window renders. A unit test asserts the second
  copy has seven entries and that `fountain` depends on nothing.
* This buys no licence or advisory auditing. If we ever want that, add
  `cargo-deny` alongside; it is not a replacement for this check.

---

## ADR 0005 — Editor implementation: a single custom editing surface

**Date:** 2026-07-24 · **Status:** accepted · **Phase:** 0

> This is the decision Phase 0 exists to make. Every later phase depends on it.

### Context

Phase 0 required three throwaway prototypes, each loading a synthetic
3,000-paragraph document and supporting typing in any paragraph, arrow-key
navigation across paragraph boundaries, and a four-paragraph selection that can
be copied as text. All three were built (`spike/`), all three implement the same
`SpikeSurface` interface, and one benchmark script drives all three so the
numbers compare.

### Measurements

Release build, Flutter 3.44.8, Linux/Wayland, 60 Hz, 3,000 paragraphs, three
runs per prototype (ranges are across runs). Reproduce with:

```
cd spike
flutter build linux --release --dart-define=P=<a|b|c> --dart-define=BENCH=true
./build/linux/x64/release/bundle/spike
```

| | **A** — `EditableText` per block in a `ListView` | **B** — `super_editor` 0.3.0-dev.52 | **C** — one custom surface |
| --- | --- | --- | --- |
| Load to first frame | 33 ms | **397–411 ms** | 23 ms |
| Frame build while typing, p50 / p99 / max | 2.2 / 4.2 / **418 ms** | **15.2** / 24 / 109 ms | **0.55** / 1.0 / 1.5 ms |
| Frame build while scrolling, p50 / p99 / max | 12.3 / 55 / **453 ms** | 8.8 / 16.4 / 21 ms | **0.54** / 1.3 / 2.1 ms |
| Frame builds over the 16 ms budget | 6.5–8.5% | **17%** | **0%** |
| Keystroke → rendered frame (wall) | 16.7 ms = 1 frame | **85 ms = 5 frames** | 17.0 ms = 1 frame |
| Select 4 paragraphs + copy | **3.2 s** | 94–117 ms | 17 ms |
| RSS after run (budget: 250 MB) | 390–418 MB | 449–456 MB | **255 MB** |
| AOT size cost of the dependency | — | **+256 KB** | — |

Wall-clock figures are vsync-quantised: 16.7 ms is the floor, not a cost. Frame
**build** time is the number that says whether the budget can be sustained.

Two footnotes so the table is not read wrongly:

* "Boundaries crossed by 40 arrow-downs" was 40/40 for A, 30/40 for B, 3/40 for
  C — and **C is the correct one**. A moves the caret block-wise because it
  cannot see visual lines inside a paragraph; B and C move by visual line, so
  most Downs stay inside a wrapped paragraph, which is what a text editor does.
* B's +256 KB is negligible. Bundle size is not an argument against it, and the
  Phase 0 guidance about a package that "saves you three months and adds 2 MB"
  is correctly answered: the size never mattered.

### What the numbers mean

**A is not viable.** Frame builds of 400–450 ms during typing and scrolling, and
3.2 seconds to select four paragraphs, on a document a third the size of a
feature. The cost is structural: `EditableText` owns its own selection and knows
nothing about its neighbours, so every cross-paragraph operation is
reimplemented on top of it — and the reimplementation is what is slow, because
it can only work by rebuilding the list. A also has to retain a
`TextEditingController` and `FocusNode` per paragraph outside the virtualised
list, or the caret is lost on scroll.

**B works and is the honest contender.** Selection, IME, and multi-node editing
are solved, correctly, by people who have thought about it more than we will.
But:

1. **There is no stable release compatible with current Flutter.** Latest stable
   is 0.2.7 (June 2024); it does not compile against Flutter 3.44 — missing a
   `TextInputConnection.updateStyle` override. The measurements above are from
   `0.3.0-dev.52`, a prerelease. Adopting B means pinning a prerelease of a
   package whose stable line is two years behind, for a project whose lifetime is
   measured in years.
2. **It misses the frame budget at this size.** 15.2 ms median build while typing
   is *at* the 16 ms budget with an empty screenplay, no Rust in the loop, no
   pagination, no spell-check underlines, and nothing else on screen. 17% of
   frames are already over.
3. **We would be fighting it, structurally.** §2.1 says Rust owns the document,
   the undo history, and element inference. super_editor brings its own
   `MutableDocument`, its own `EditRequest`/undo pipeline, and its own node
   model. Adopting it means either two sources of truth — which §2.1 exists to
   forbid — or bypassing most of what we took the dependency for.

**C meets every budget with two orders of magnitude of headroom.** 0.55 ms
median build while typing, zero frames over 16 ms, RSS inside the 250 MB budget,
and cross-paragraph selection is trivial because a selection is two
`(block, offset)` pairs in a model we own. Line breaking is character counting on
the monospace grid (§5.1), so what the editor paints is what `layout::paginate`
will compute in Rust — the editor and the PDF cannot drift apart. And there is no
blinking-caret animation, so the 0% idle CPU budget is met by construction rather
than by fighting a widget that wants to animate.

### Decision

**Build the editor as a single custom editing surface (Prototype C).** One
`TextInputClient` for the document, our own line layout, our own caret and
selection painting, our own key handling, over the document model that Rust owns.

### The risk, stated plainly

The Phase 0 guidance warns that writing your own IME-correct text editor is how
this project dies, and that warning is not defused by these numbers. What the
prototype does *not* implement is the whole of the input surface:

* composition (IME) spanning a paragraph boundary — the prototype hands the
  platform one paragraph at a time, which is correct for every case except that
  one;
* word-wise and line-wise motion and deletion, and the platform text-editing
  intents that come with them;
* mouse-drag selection, double/triple-click, autoscroll during drag;
* accessibility, which `EditableText` provides free and we do not.

None of that gets cheaper with effort; it is simply work, and it belongs to
Phase 3.

Three things keep this from being an open-ended commitment:

1. We use Flutter's `TextInput`/`TextInputClient` plumbing. We own layout,
   painting, and the model — not the platform protocol. This is materially less
   than "write a text editor".
2. The screenplay grid is monospace and fixed (§5.1). No shaping, no font
   metrics, no bidi, no variable-width line breaking. The hardest part of a
   general text editor is absent from this one by specification.
3. **Phase 3 gets a hard exit gate:** CJK composition via ibus, dead-key accents,
   and clipboard round-trip through a real IME must pass as integration tests
   before Phase 3 closes. If they cannot be made to pass, this ADR is superseded
   and B is the fallback — which is why the spike code stays in the repository
   rather than being deleted.

### Consequences

* `spike/` is kept, not deleted. It is throwaway code, but it is the evidence,
  and B is the fallback path.
* `super_editor` is **not** a dependency of `app/`. It is only in `spike/`.
* The editor in Phase 3 starts from `spike/lib/prototype_c.dart`'s structure:
  line layout from the model, visible-band painting, position arithmetic in
  document coordinates.
* Prototype C's line breaking must be replaced by the Rust `layout` crate's
  output rather than duplicated in Dart — the Dart version exists only because
  the spike had no Rust in it. Flutter renders lines; it does not decide them.
  (§2.1: Flutter never derives screenplay semantics on its own.)

---

## ADR 0006 — The project is called Slugline

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1

### Context

Phase 0 shipped under the working name "screenplay", which was never a name so
much as a description: it was the directory the repository happened to be in.
The GitHub repository is `slugline`, after the industry term for a scene
heading, and §16 lists "application name, binary name, and reverse-DNS app ID"
as an open decision.

### Decision

The project is **Slugline**. Every identifier follows:

| | Before | After |
| --- | --- | --- |
| Rust crates | `screenplay_*` | `slugline_*` |
| Shared library | `libscreenplay_bridge.so` | `libslugline_bridge.so` |
| Dart package | `screenplay` | `slugline` |
| Binary | `screenplay` | `slugline` |
| Application ID | `com.phagmaier.screenplay` | `com.phagmaier.slugline` |
| XDG directories | `$XDG_*_HOME/screenplay/` | `$XDG_*_HOME/slugline/` |

The XDG paths are settled here rather than in Phase 4 because they are the one
part of the rename that is a user-visible file location, and Phase 4 should
inherit a decision rather than make one.

### Consequences

* Verified end to end rather than by search-and-replace alone: `flutter build
  linux --release` produces `bundle/slugline` and
  `bundle/lib/libslugline_bridge.so`, and `flutter_rust_bridge_codegen generate`
  reproduces the committed bindings with the new library stem.
* Name references inside ADRs 0002 and 0004 were updated in place. That is the
  one edit an accepted record may take: it changes what a thing is called, not
  what was decided. Anything else still needs a superseding record.
* The word "screenplay" survives in prose throughout the repository, because the
  application is still a screenplay editor. Only identifiers moved.

---

## ADR 0007 — Round-tripping is a tiling invariant, not a comparison

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1

### Context

§3.2 requires that opening and resaving a file loses nothing, and §1.2 makes
losing user text a P0. The mechanism the spec names is provenance: each block
records the byte range it was parsed from, and unedited blocks are re-emitted
verbatim.

What the spec leaves open is what the ranges cover. The obvious reading — a
block's range is the bytes of its own lines — leaves the blank lines *between*
blocks belonging to nobody, and then losslessness becomes a second problem
stacked on provenance: how many blank lines were there, which of them were CRLF,
was there a tab on that empty one.

### Decision

**The provenance ranges tile the source exactly.** The title page's range runs
from the end of the BOM to the start of the first block; each block's range runs
from the start of its first line to the start of the next block's first line;
the last block's range runs to the end of the file. Every byte after the BOM
belongs to exactly one range, in order, with no gaps and no overlaps.

Byte-exactness is then not a feature to be maintained but a consequence:
serialising an untouched document is copying the source back out in pieces. The
blank lines, the CRLFs, the trailing tabs and the missing final newline are
inside somebody's range, so they come back.

The invariant is asserted directly — in unit tests, over every corpus file and
every truncation of one, and in the fuzz target — rather than only through the
round-trip comparison it implies, because a tiling failure names the block that
broke while a byte comparison names an offset.

### Consequences

* A file with no final newline resaves with no final newline. Phase 1's "output
  always ends with a single newline" is a property of the **canonical** writer —
  the path an edited block takes — and byte fidelity outranks it for bytes
  nobody touched. §1.2 decides that tie.
* Editing a block drops its provenance and nothing else's, so one edit
  canonicalises one block and leaves the rest of the file alone. Undo restores
  provenance along with text, so edit-then-undo-then-save is a no-op rather than
  a reformat.
* The serialiser therefore owns separators: an edited block writes the blank line
  that follows it. Where the separator a neighbour carries no longer matches the
  kind that will follow it — inserting a parenthetical after a line of dialogue,
  say — that neighbour's provenance is dropped too, and only then.
  Canonicalising a block the user never touched is exactly what this ADR exists
  to avoid.
* Whether the output is at the start of a line is asked of `\n`, not of *this
  document's* terminator. A file may mix them, and verbatim bytes are whatever
  the file had; asking the narrower question inserted a spurious `\r\n` into a
  CRLF file whose second line ended with a bare LF. Found by the fuzz target,
  not by the corpus.
* Three consequences of tolerance, each chosen so the parser cannot make text
  jump around under a caret that is still typing:
  * An unclosed `/*` runs to the end of the file, as every other Fountain
    implementation does. An unclosed `[[` is **not** a note — treating it as one
    would reclassify every block below the caret between keystrokes.
  * A line of nothing but whitespace is a separator. Fountain's convention that
    two spaces mean an intentional blank line inside Action is not modelled; the
    bytes still round-trip, and the difference is one Action block or two.
  * An `Opaque` block refuses every edit command. §3.2 defines Opaque as "always
    has provenance and therefore always round-trips exactly", and an edit that
    deleted the `*/` from a boneyard comment would turn the rest of the script
    into a comment. Found by a property test.
* Some element sequences have no Fountain spelling at all: dialogue with no cue
  above it, two adjacent dialogue blocks, an empty action paragraph, a scene
  heading whose whole text is `.`. The writer drops what it cannot say rather
  than writing a blank line that would split the neighbours apart — and a block
  with no text has no text to lose. Every element marker except `!` also
  swallows the whitespace beside it, so a padded text loses its padding when it
  takes a marker on. The property tests generate only representable documents,
  and say why.

---

## ADR 0008 — Syntax lives in `fountain`, identity and history live in `document`

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 1

### Context

§3.1 puts `Document`, `Block` and `BlockKind` in `crates/document`. §2.5 says
`fountain` depends on nothing else in the workspace. A parser that returns a
`Document` cannot honour both.

§3.4 raises the same tension elsewhere: it gives `EditCommand` a `range_utf16`
field, while §2.4 and ADR 0001 permit UTF-16 conversion in exactly one module,
`bridge/src/offsets.rs`.

### Decision

Split by what each crate owns rather than by which struct the spec drew where.

* `fountain` owns **syntax**: `BlockKind`, `TitlePage`, `TitleField`, and
  `Element` — a parsed block with no identity. It parses to `Element`s and
  serialises from a borrowed view of them, so `document` can write its own blocks
  without copying their text.
* `document` owns **identity and history**: `Block` is an `Element` plus a
  `BlockId`, and `Document` adds the id counter, the retained source and undo. It
  re-exports `fountain`'s kinds rather than declaring its own, so there is one
  spelling of "this is a scene heading" in the workspace.
* `document::EditCommand` carries **UTF-8 byte offsets**. The bridge owns the
  `*_utf16` form and converts through `offsets.rs` on the way in, which is the
  arrangement ADR 0001 asks for. The fields are named `range` and `at` rather
  than `range_utf16`, because a name that lies is worse than a name that differs
  from the spec.

Two smaller departures from §3.4's literal text, both to keep an invariant
enforceable in one place: `InsertBlocks` takes id-less `NewBlock`s, so §3.1's
"never reused after deletion" is decided by the document; and `apply` returns
`Result`, because a stale id or an offset inside a character has to be answerable
without a panic.

### Consequences

* The layering check passes unchanged: `document -> fountain` was already the
  expected edge.
* An inverse is not an opposite command but a `Splice` carrying the original
  blocks — ids and provenance included. One clone per transaction, and undo
  restores provenance, which is the property that makes undo-then-save write the
  original bytes.
* `document` has no clock. §3.4's 600 ms coalescing rule needs one, so this crate
  coalesces consecutive text edits *to the same block* and exposes `commit()`;
  the caller that owns the clock — the bridge actor, in Phase 2 — decides when
  600 ms have passed. Keeping time out of the model is what lets the parser, the
  model and the pagination engine be tested without one.
* `index_of` is a linear scan. At a few thousand blocks that is a microsecond on
  the keystroke path; if it ever shows up in a profile the answer is an index
  beside `blocks`, maintained by the same splice that maintains the vector.
* The entity index named in §2.1 is not here. It belongs to Phase 5, and building
  it now would be scaffolding for a consumer that does not exist (§1.4).

---

## ADR 0009 — The bridge's document surface: flat kinds, patches, and refusals as values

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2

### Context

§6 fixes the *names* of the bridge functions and §3.4 the shape of
`EditCommand`, but three questions are left open by both, and each one is
answered on every keystroke:

1. `BlockKind::Section` carries a level. An enum with a payload becomes a
   `freezed` sealed class in Dart (ADR 0003), which the editor would then have
   to destructure on every block it paints and could not use as a map key.
2. `EditResult` says "the ids of blocks that changed, removed, inserted". Ids
   alone are not enough to patch a list: Dart would have to fetch the changed
   blocks and guess where the inserted ones went.
3. An edit can be refused. FRB's usual answer is a `Result` that becomes a
   thrown Dart exception.

### Decision

**Kinds are flat.** `BlockKind` on the bridge is a plain Dart enum with a
`Section` variant, and the level rides alongside in `BlockView::section_level`
(0 for everything else). `SetKind` carries the same pair.

**A result is a patch that can be applied without another call.** `EditResult`
carries whole `BlockView`s for changed blocks, `(index, BlockView)` for inserted
ones — the index being the position *after* the edit — and a `block_count` Dart
asserts its own list against. The order is: drop `removed`, update `changed`,
insert `inserted` in ascending index.

**A refusal is a value, not an exception.** `doc_apply` returns
`EditOutcome::Applied | Rejected { reason, message }`.

`u64` is mapped to Dart `int` rather than `BigInt`, via `type_64bit_int` in
`app/flutter_rust_bridge.yaml`.

### Consequences

* Dart switches exhaustively over `BlockKind` and uses it as the key of the
  element-metrics table. The cost is one field that means nothing for twelve of
  the thirteen variants — the "tag plus nullable field" shape ADR 0003 rejected
  for `CoreEvent`. It is accepted here for the opposite reason: a plain Dart
  enum *keeps* the compiler's exhaustiveness check, which is what ADR 0003 was
  buying. `EditCommand`, `EditOutcome` and `CoreEvent` remain sum types.
* No refetch: `test/editor/editor_controller_test.dart` watches the number of
  reads out of the core stay at one across a run of edits.
* Two refusals are ordinary user actions rather than bugs — typing inside a
  boneyard comment, and backspacing at the very start of the script — so the
  status bar shows them and nothing catches anything. Making them exceptions
  would put a `try` on the keystroke path for the sake of two cases that are not
  errors.
* Dart `int` is a native 64-bit signed integer on the only platform this project
  targets (§1.2), so the `BigInt` mapping was pure allocation on the path that
  runs for every visible block. The switch is codegen-wide: change it and every
  binding must be regenerated in the same commit, or the glue and the bindings
  disagree silently.
* `SetTitlePage` is absent from the bridge's `EditCommand`. The title page is
  edited in Phase 7 and a command with no caller is scaffolding (§1.4).

---

## ADR 0010 — Paste is composed in the bridge, and grouped by the document

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2

### Context

Phase 2 requires "copy, cut, paste (as Fountain-aware blocks)". Copying a
selection means asking what the selection *is* in Fountain, and pasting means
reading Fountain back and splicing it in — both are screenplay semantics, which
§2.1 puts in Rust.

A paste is not one `EditCommand`. Replacing a selection with three blocks is a
delete, a split, an insert and two text edits, and §3.4's rule that every
structural command starts a new transaction would make it five undo steps.
Worse, the split's new block has no id until the split has run, so the sequence
cannot even be written down in advance.

### Decision

`document` gains a grouping primitive: `Document::apply_group(before, plan)`
runs a closure that applies commands through a `Grouped` handle and sees each
result as it goes, and the whole run becomes **one** undo transaction. A failure
part-way through rolls the group back and reports the error, so the "a rejected
edit never half-happens" guarantee holds for a group as it does for a command.
`apply_all(commands)` is the sequence-shaped convenience over it.

The paste itself is composed in `bridge/src/api/doc.rs`, where the caret is
known, and its shape depends on where the caret is:

* **Inside a block** — the text is spliced in: the first pasted block joins what
  precedes the caret, the last joins what follows it, the rest become blocks.
* **At a block boundary, with more than one block to paste** — the blocks go in
  whole, above or below. Welding a copied scene heading onto the end of a line
  of dialogue is never what was meant.
* **Into an empty block** — the first pasted block fills it, kind and all.

Copying is `Document::extract`, which re-serialises the selected blocks — and
keeps the provenance of blocks the selection covers *whole*, so copying an
untouched scene reproduces the bytes it was written with rather than a canonical
rendering of them (§3.2).

### Consequences

* Typing over a selection that spans blocks is a paste, not two commands, so it
  is one undo step. That is why `adopt` refuses to carry plain unforced Action:
  it is the kind typed text has, and adopting it would silently demote a scene
  heading whose text the user selected and retyped. There is a named test.
* Phase 3's Replace All ("one undo transaction") already has its primitive.
* An `Opaque` block cannot be a *new* block — §3.2 defines Opaque as content
  that always has provenance, and pasted content has none — so `parse_blocks`
  turns one into Action carrying the same bytes, which the serialiser then
  protects with `!`. Nothing is lost except the invisibility of a pasted
  boneyard comment. It is the only lossy corner of the clipboard, and it is
  preferred to dropping the text (§1.2).
* `Ctrl+Shift+V` is the same path with `plain: true`: every line becomes an
  Action block and `forced` stays false, so the serialiser adds `!` only where a
  line would otherwise be read back as something else. A plain-pasted
  `INT. HOUSE - DAY` stays Action without the file gaining a marker it does not
  need.

---

## ADR 0011 — Automatic classification is the recognition rules read forwards

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 3

### Context

Phase 3 asks for "automatic detection on the current block as you type", for
`INT.` in an action paragraph to promote it to a scene heading, and for §4.2's
scoping rules — one block either side of an edit, never a forced block, never a
block the caret is nowhere near.

The obvious implementation is a second set of rules: a table of "if the text
looks like this, make it that". That is exactly what ADR 0007 spent Phase 1
avoiding for the serialiser, and for the same reason: two opinions about what a
line means will disagree, and the disagreement shows up as a document whose
element types change every time it is saved and reopened.

There is also a subtler problem. Whether a block is "preceded by a blank line" —
which half of §4.1's rules depend on — is not a fact about its text. It is what
the serialiser decides from the two kinds involved (`needs_blank_between`). So
"what would the parser call this text?" has no answer until you say what the
block currently *is*.

### Decision

**`fountain::infer_kind` asks §4.1's own recognition functions, with the block's
current kind as part of the context.** It is the third caller of `syntax.rs`,
after the parser and the serialiser, and it is bound by one property: *it never
produces a kind the file would not give back*. There is a test that walks a
parsed script and asserts inference agrees with the parser on every unforced
block, and another that asserts a document, once re-classified, reads back with
the same kinds.

The current kind settles the blank-line question first. After a line of dialogue,
a block that is already dialogue is written adjacent to it and stays dialogue; a
block that is action is written after a blank line, is therefore a fresh element,
and is free to become a scene heading. Both are what a reparse would say.

Four things are never re-classified, and each is a rule rather than a special
case:

* **A forced block.** `forced` is the record that a human said what this element
  is — by typing `.`, `@`, `>`, `!`, or by pressing the shortcut. Automatic
  behaviour does not argue with it. This is also what makes §Phase 3's "an
  immediate element-type shortcut after an automatic change reverts and forces
  the user's choice" fall out for free rather than needing a mechanism.
* **An empty block.** There is nothing to classify, and the kind that put it
  there is the only intent available. Without this rule, the empty scene heading
  that Enter creates after a transition would flip to Action before a key was
  pressed.
* **A block whose kind is written with a marker its text no longer carries** —
  `~`, `#`, `=`, `===`, `> <`, `[[ ]]`, `/* */`. For those the kind *is* the
  marker; asking what the text looks like would answer Action every time and
  delete the marker on the way out. `BlockKind::is_inferable` names the six that
  §4.1 recognises from the text itself.
* **A dual cue.** The `^` pins it: a re-classified dual block would carry a flag
  on a kind that cannot hold one.

**Scope is `Document::reinfer`, and the bridge calls it after every edit.** It
takes the patch the edit produced and the caret the writer had, widens to one
block either side of everything that changed, and folds the kinds it changed into
the same patch — so Dart applies one patch and never learns that anything
reclassified at all. Two edits opt out: a plain paste (`Ctrl+Shift+V`), because
§Phase 2 says that path infers nothing, and Replace All, because it is a bulk
operation over blocks the writer is not looking at, which is the case §4.2 says
to leave alone.

**A re-classification joins the transaction of the keystroke that caused it.**
`History::reopen` puts back the transaction that has just closed, and
`record_alongside` appends without disturbing what the open one is coalescing. So
typing `INT. HOUSE - DAY` is one undo, and the promotion that happened at `INT.`
does not split the run of typing in two. This works because an `Inverse::Splice`
already carries the whole block — kind, `forced` and provenance — so a run's first
inverse restores a re-classified block for free; only the *neighbours* need an
inverse of their own.

### Consequences

* A typed scene heading is written **without** a marker, because inference never
  forces. A scene heading set from the menu is written with a `.`, because
  §Phase 3 says an explicit choice sets `forced = true`. That asymmetry is
  visible in the file and it is the intended one: the marker means "a human said
  so", which is what `forced` has always meant.
* `Action → Character` is on Tab rather than automatic. A cue is only a cue when
  something speaks under it (§4.1), so an all-capitals line with a blank line
  below it is action, and inference must say so or contradict the parser. The
  cue workflow is therefore *type the name, Tab* — and the character-name
  suggestion is a hint in the element bar, never a change.
* The keyboard workflow tables live in `document/src/workflow.rs`, not in
  `fountain` and not in Dart. Not `fountain`, because the format has nothing to
  say about Tab. Not Dart, because §2.1 does not allow a second opinion about
  what follows an element — which is why the "parameterised widget test"
  §Phase 3 asks for covers the *wiring* for every element type while the table's
  content is proved in Rust. `SPEC.md`'s Phase 3 list records the division.
* Enter is composed in the bridge, exactly as paste is (ADR 0010): delete the
  selection, split, set the new block's kind, in one transaction. `doc_enter` and
  `doc_tab` are the two functions §6's "keep this small" budget pays for it, and
  they buy back the alternative — Dart issuing two commands and the writer
  needing two undos.
* Re-classification costs a `Vec` of at most a handful of indices and one
  `infer_kind` call each, on every keystroke. The §1.3 benchmark on the 120-page
  reference script is unchanged: p99 keystroke-to-patch 1.29 ms against a 16 ms
  budget.

---

## ADR 0012 — The custom surface's semantics tree is a render object per block

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 3

### Context

ADR 0005 chose one custom editing surface over `EditableText` and listed four
things that choice costs. Three were paid in Phase 3. The fourth —
"accessibility, which `EditableText` provides free and we do not" — was the last
item outstanding, and `SPEC.md`'s Phase 3 list said so.

The gap was total, not partial. A `CustomPaint` contributes nothing to the
semantics tree, so a screen reader pointed at the editor found a scrollable
containing no text at all: not a degraded experience, an absent one.

Flutter offers three ways to put something there, and two of them cannot express
what a text editor needs:

1. **`Semantics` widgets.** They carry a `SemanticsProperties`, which has fields
   for a label, a value, `textField`, `readOnly`, `multiline` and every action —
   but **no field for a text selection**.
2. **`CustomPainter.semanticsBuilder`.** Same `SemanticsProperties`, same gap,
   plus one of its own: it is rebuilt when the painter is replaced, and this
   painter repaints from a `Listenable` without ever rebuilding.
3. **A render object.** `SemanticsConfiguration.textSelection` is public, and it
   is what carries the caret to AT-SPI as `textSelectionBase`/`textSelectionExtent`.
   `RenderEditable` reaches it the same way.

For a writing tool the caret is not a detail. A screen reader that can read the
paragraph but cannot say where in it you are has told you almost nothing.

### Decision

**One leaf render object per visible block** (`editor/surface_semantics.dart`),
positioned over the block it describes, painting nothing and hit-testing never.
Each one declares itself a multiline text field with the element type as its
`label` and the drawn text as its `value`; the block holding the caret also
carries the selection and the cursor-movement, set-selection, set-text and
clipboard actions.

Three details are load-bearing:

* **The label is the element type.** "Character, JOHN" is what a screenwriter
  needs to hear, and it is the thing no generic text field could say. It comes
  from `kindLabel`, the same table the element bar and the palette read.
* **The value is `displayText`, not the model's text.** §5.2 upper-cases scene
  headings and cues on screen only, and what is announced should be what is
  drawn. This is safe because `displayText` never changes a string's length —
  it refuses the upper-casing that would (`ß` → `SS`) — so the selection offsets
  index into the announced string exactly as they index into the model's.
* **Only the focused block offers cursor actions.** There is one caret. A block
  that does not hold it must not offer to move it, or the move would silently
  jump somewhere else first.

### Consequences

* **Nodes are built for the visible band only, and only while
  `SemanticsBinding.semanticsEnabled`.** A feature-length script is some three
  thousand blocks and a semantics tree of that size is one no screen reader wants
  and no frame budget affords. With no assistive technology attached the cost is
  not paid at all: `_blockSemantics` returns an empty list.
* **The surface now rebuilds on scroll — but only when semantics are on.** The
  painter repaints from a `Listenable` and does not rebuild, which is why the
  editor is as cheap as it is; a semantics tree cannot be updated that way, so
  scrolling and editing both queue a post-frame `setState` while something is
  listening. The §1.3 benchmark is measured with semantics off, which is the
  ordinary case, and is unchanged.
* **One node per block rather than one for the document.** A `value` is one
  string and the document's is half a megabyte. Per-block nodes are also what
  lets a screen reader navigate paragraph by paragraph, which is how someone
  actually reads a script.
* `SemanticsAction.setText` goes through `setSelection` + `insertText` rather
  than a command of its own, so an accessibility action takes exactly the path a
  paste takes: one undo step, and the same re-inference afterwards. An assistive
  technology must not be a second way into the document.
* The tests in `app/test/editor/accessibility_test.dart` assert on the
  `SemanticsData` the owner produces, not on the widgets that produce it. What
  reaches AT-SPI is the only thing that matters, and it is the only thing a
  widget-level assertion would not have checked.

---

## ADR 0013 — The crash journal records outcomes, not commands

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4

### Context

§Phase 4 asks for "an append-only **edit journal** … [that] records committed
edit commands between saves", and its exit criterion is that the application can
be killed twenty times while typing without losing a keystroke beyond the last.

Taken literally, a journal of `EditCommand`s replays by re-running every rule
that decided what those commands did: the Enter/Tab tables in `workflow.rs`,
`Document::reinfer`, the validity checks in `edit.rs`, and the caret the writer
happened to have — because `reinfer`'s scope depends on it. Get any of them a
version out of step with the session that crashed, and the recovered script is
quietly not the one the writer was looking at. Recovery is the last place in this
codebase to want cleverness.

Two alternatives were considered and rejected:

* **Journal the serialised document.** Always recoverable, trivially correct, and
  half a megabyte per keystroke on a feature. Doing it per *transaction* instead
  brings it down to once per 600 ms of typing — but a 600 ms window is more than
  "the last keystroke", so it fails the exit criterion by construction.
* **Journal a splice against the previous serialised text.** Small records, but
  computing one costs a full serialise and diff on the keystroke path.

### Decision

**The journal records the `Patch` an edit produced** — the blocks that were
removed, the blocks as they now stand, and the blocks that appeared with the
index they appeared at. `document::recovery` defines the type;
`Document::replay` applies one; `storage::journal` writes and reads them.

Replaying is list surgery with no rules in it. It is also cheap enough to do
after **every** edit rather than every transaction, because one patch is the
blocks one edit touched — a paragraph, for a keystroke — which is what makes the
exit criterion reachable at all.

Three things fall out of the choice and are worth stating:

* **The patch is recorded after `reinfer`**, so the kinds in it are the kinds the
  writer was looking at, not the kinds the command asked for.
* **The header carries a checksum of the file** the journal was opened against.
  Block ids only mean anything against a particular parse, so recovery refuses to
  replay onto a file that changed underneath it rather than applying edits to
  whatever happens to be there now.
* **An undo is journalled like anything else.** A crash after an undo must not
  bring back the text it took away.

### On durability

Appends are written but **not** `fsync`ed, and that is deliberate. The threat
§Phase 4 names is the process dying — `SIGKILL`, a panic, an OOM kill — and a
`write(2)` that has returned has already reached the kernel, so the data survives
all of those whether or not it has reached the platter. `fsync` per keystroke
would be a disk round trip on the hot path to buy protection against power loss
only, and against power loss the last keystroke is unrecoverable anyway. The
atomic save in `storage::atomic` is what protects the *file* against that, and it
does `fsync`, twice.

The measured cost of the append is in the §1.3 benchmark, which now types into a
journalled document as well as an unattached one: p50 0.81 ms against 0.78 ms
without, p99 1.14 ms against a 16 ms budget.

### On the format

Line-delimited JSON, with the record and its newline written in **one**
`write_all`. That single write is the entire integrity scheme: a record followed
by a newline is a record the kernel took whole, and a trailing fragment is a
write that was interrupted. `journal::read` is total in the same sense the
Fountain parser is — no input makes it fail — because it is read at exactly the
moment the user has already lost something, and a recovery path that panics on a
damaged file turns a bad day into a lost script.

JSON rather than a packed binary format because when recovery goes wrong the
writer's text is *in there*, and they must be able to get it out with a text
editor.

### Consequences

* `document` gains `BlockSnapshot`, `Patch`, `Document::replay` and
  `Document::snapshot`. `replay` bypasses the undo history on purpose: the
  transactions it would push invert edits against a process that is gone.
* `storage::journal` mirrors `BlockSnapshot` as a serde struct rather than
  deriving `Serialize` on the model. `document` and `fountain` are the two crates
  §2.5 keeps pure, and a file format is not a thing the model should know about.
  The cost is two conversion functions and a test that walks every `BlockKind`
  through them — element kinds are written as **names**, not numbers, so that
  inserting a variant cannot silently reinterpret every journal on every disk.
* A script that has never been saved is journalled too, keyed by its handle, with
  an empty path in the header. It replays onto `Document::blank()`. That is the
  script a crash costs most.
* Every mutation in `api::doc` ends in `outcome` or `inferring`, and both
  journal. There is no path from Dart to the document that does not pass through
  one of them, which is what lets the journal claim to hold every edit.

---

## ADR 0014 — The autosave clock lives in Dart

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4

### Context

§Phase 4 asks for autosave "debounced after edit inactivity (default 2 s) and on
a hard interval (default 30 s), both configurable", and in the next line: it
"never runs while a modal is open or during an active IME composition".

§2.1 puts "file I/O, autosave, atomic writes, backups" in Rust's column, which
reads at first like an instruction to put the timers there too.

### Decision

**Rust owns the saving. Dart owns the deciding-when.** `AutosaveDriver`
(`editor/autosave.dart`) runs both timers and calls `doc_autosave`; the core has
no timer anywhere.

The reason is the second sentence, not the first. A modal is a widget and a
composition is a state of the platform's input connection — neither fact exists
in Rust, and neither can be sent to it without inventing a protocol whose only
purpose is to tell the core about the UI. §2.1's line is about who *writes the
file*, and that is still Rust: the driver's only power is to ask.

Keeping the clock out of the core also keeps §1.3's 0% idle CPU budget met by
construction rather than by tuning. The actor thread blocks on its channel and
wakes only when something happens; a timer in it would be a wakeup in an idle
process, which is the one thing that budget forbids.

### The two timers, and why both

* **Idle**, restarted on every edit. This is the one that normally fires.
* **Interval**, *not* restarted on every edit. Without it, a writer who never
  pauses for two seconds — which is what a good session looks like — would never
  be saved at all.

Both are cancelled the moment the document is clean, so an idle window costs no
wakeups, and neither is created for a document with nothing to save.

### Consequences

* **A suppression holds a save; it never cancels one.** A save deferred by a
  dialog happens when the dialog closes. §10 does not allow a save to be quietly
  dropped because the timing was awkward, and "the modal closed and the moment
  passed" is exactly that.
* Suppressions are a *set*, not a flag, so a dialog opened over a composition
  cannot un-suppress it by closing. `EditorPage.withModal` pairs every
  suppression with its release in a `finally`.
* **Autosave writes no backup.** A backup per autosave would be a hundred a day
  and would push yesterday's draft out of the retention window by lunchtime.
  §Phase 4's rolling backups are per explicit save.
* A failed autosave leaves the document dirty, so the interval keeps retrying: a
  disk that frees up gets written to without the writer doing anything. The
  failure reaches the status line via `CoreEvent::AutosaveFailed` rather than a
  modal — an autosave is not something the writer asked for — while an explicit
  save that fails is blocking, which is the split §Phase 4 draws.
* The rules are testable without the `.so`, which is where they are tested
  (`app/test/editor/autosave_test.dart`). What a save *does* to a file is Rust's
  and is proved in `cargo test`, per ADR 0011's division.

---

## ADR 0015 — The file chooser is ours, because `file_selector` brings `http`

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4

### Context

Phase 4 needs Open, Save As, New and Rename, and all four need a path from the
user. The obvious answer is `file_selector_linux`, a Flutter-team package that
puts up GTK's own dialog — a better dialog than anything we would write, using
the file manager's bookmarks and the platform's own conventions.

It pulls `file_selector_platform_interface`, which pulls **`http`**.

### Decision

**Write the chooser** (`library/file_chooser.dart`): list a directory, walk into
it, type a name.

§1.2 makes "the application makes **zero** network requests" a *build-time
assertion* (§13). An HTTP client linked into the shipped bundle is a thing that
assertion then has to argue with — and "it is linked but never reached" is
exactly the kind of exception that, once written into a check, stops the check
from meaning anything. The whole `file_selector` umbrella is worse still: eleven
packages, four of them implementations for platforms §1.2 says not to write code
for.

### Consequences

* The chooser is plainer than GTK's. It hides dotfiles and in-flight `.tmp-`
  saves, appends `.fountain` to a name with no extension, and is keyboard-first
  like the rest of the application (§1.1).
* **This is worth revisiting in Phase 10.** Either the §13 assertion is written
  precisely enough to allow a linked-but-unreached client, or the platform
  interface stops needing one. Until one of those happens, a native dialog costs
  more than it is worth.
* No dependency was added for Phase 4 on the Dart side at all.

---

## ADR 0016 — Accepting a recovery rewrites the journal; it does not write the script

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (repaired during the
mid-project remediation) · **Supersedes:** nothing; it states a sequence ADR 0013
left implicit

### Context

Crash recovery is the one moment in this program where the writer's text exists
on disk only as a **journal**. Everywhere else the file is the truth and the
journal is the tail; here the journal is ahead of the file, and it is the only
thing that can reconstruct what was typed.

The sequence Phase 4 shipped was: replay the journal into memory → delete it →
start a new journal whose `base` was a checksum of the recovered *in-memory*
text. At the instant between the second and third steps there was no durable copy
of the recovered edits at all, and after the third there was one whose `base`
matched no file on any disk. Two things followed, and the audit (`REVIEW.md`, F2)
found both:

* A second crash before the writer saved or typed left a journal with **zero
  records**, which startup discards as "nothing was typed since the last save".
  Every recovered edit was gone, silently.
* A second crash *after* the writer typed left a journal `journal::verify`
  refused, because its `base` did not match the file. The recovered edits and the
  new typing became unreachable together, reported as `blocked`.

The doc comment on `recovery_accept` said the opposite: "so that a second crash
during recovery loses nothing either."

### Decision

**The successor journal is written before the old one is removed, and it is based
on the bytes the file still holds.**

Accepting an offer now does this, in order:

1. Read and verify the old journal. Verification returns the file's real bytes —
   still the pre-crash ones, because nothing has written to the script.
2. Replay onto those bytes, counting how many patches actually applied.
3. Open the document and bind it to its file, library entry and watch.
4. Write the successor with [`Journal::rebuild`]: the **same `base`**, plus the
   patches that replayed. It goes through `atomic::save_atomically`, so it either
   exists whole or does not exist.
5. Only now remove the old journal, and only when the successor did not already
   replace it at the same path.

There is no instant at which no journal describes the recovered edits.

A document adopted dirty also arms the autosave clock immediately
(`AutosaveDriver.documentAdopted`). Before, the clock started on the first edit
event, and a recovered document produces none — so nothing was saved until the
writer typed, which is not what a person does while reading recovered text.

### Alternatives considered

**Save the script immediately on accept, then checkpoint a fresh journal against
the written bytes.** This was the audit's first suggestion and it is simpler. It
was rejected because it overwrites the writer's file as a side effect of clicking
"Recover", which contradicts what Phase 4 promises and what the kill test
asserts: recovery never auto-applies, and the document comes back *dirty* so the
writer still has to say yes. It would also write a backup for a state nobody
approved.

**Adopt the old journal file as-is and keep appending.** Tempting — for a titled
script the successor would have the same name anyway — but wrong whenever the
replay stopped early or the journal was damaged. Its later records describe edits
the in-memory document does not have, so a future replay would diverge from what
is on screen. Rebuilding from the patches that actually applied is what keeps a
journal a description of *its own* document.

**Refuse to open when the successor cannot be written.** Safe, but it shows the
writer nothing at the moment they most want their text. `RecoveryOutcome` has a
`Degraded` arm instead: open, with the old journal kept, and a dialog saying that
nothing typed from here is being recorded.

### Consequences

* `recovery_accept` returns `RecoveryOutcome` — `Recovered`, `Degraded` or
  `Failed` — rather than `Option<DocumentHandle>`. A failure is a value with a
  message, per this file's existing convention for saves.
* A journal **none** of whose records replay is refused and left on disk
  untouched. Rebuilding would replace the writer's text with an empty file, and
  an empty journal is discarded at the next startup; `recovery_pending` already
  takes the view that an unreadable journal stays put, because a person can pick
  it apart by hand.
* Recovery still writes nothing to the script. That property is now load-bearing
  in two tests rather than one.
* `Journal::rebuild` is the only place that writes a journal wholesale. It shares
  its record encoder with `Journal::append`, and a test holds the two to
  producing identical bytes, so a rebuilt journal cannot drift into a format the
  reader treats as damage.

### Tests and invariants

In `crates/bridge/tests/persistence.rs`:

* `a_second_crash_straight_after_accepting_recovery_loses_nothing`
* `a_second_crash_after_typing_more_keeps_both`
* `a_failed_successor_leaves_the_offer_where_it_was`
* `the_successor_records_only_the_patches_that_replayed`
* `a_journal_that_cannot_replay_is_left_on_disk_rather_than_emptied`
* `an_untitled_recovery_survives_a_second_crash_too`

In `crates/storage/src/journal.rs`:

* `a_rebuilt_journal_is_what_an_appended_one_would_have_been`
* `rebuilding_replaces_a_journal_whole`
* `a_rebuilt_journal_carries_on_being_written_to`

In `app/test/editor/autosave_test.dart`:

* `a document adopted dirty is saved without waiting for a keystroke`
* `adopting a clean document arms nothing`

The first four fail against the previous sequence, each for the reason F2
describes; that was checked by reinstating it.

---

## ADR 0017 — A default completion does not take Enter from the editor

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 5 (repaired during the
mid-project remediation)

### Context

The completion popup highlights its first item as soon as suggestions appear.
The shipped key routing treated that automatic highlight as a choice: Enter
accepted it before Enter could split the block. Because the incremental entity
index already contained the block being typed, a completed scene heading or cue
was often its own sole suggestion. Accepting it replaced the text with identical
text, so the primary writing gesture appeared dead.

The original specification said Tab or Enter could accept a highlighted item,
but did not distinguish the popup's automatic highlight from a highlight the
writer deliberately moved. Arm ordering silently made the former enough.

### Decision

**Tab accepts the default completion. Enter accepts a completion only after the
writer has navigated the popup with Up or Down; otherwise Enter always splits the
block.**

The controller records whether the current completion list has been navigated.
Refreshing or dismissing the list clears that state. Up and Down retain their
popup navigation behavior even when there is only one candidate, because the key
press itself is the writer's choice.

The bridge also removes a candidate whose replacement text is identical to the
active completion segment. Such a candidate can make no change and, in
particular, must not be the current block offered back to itself after the entity
index updates.

### Alternatives considered

**Always let Enter accept the default.** Rejected because merely displaying a
suggestion then disables block splitting, and an exact candidate can turn Enter
into a no-op.

**Never let Enter accept a completion.** Simpler, and Tab would still provide an
explicit acceptance gesture, but it unnecessarily removes the Enter workflow
already promised by Phase 5. Requiring popup navigation keeps that workflow
without stealing ordinary Enter.

**Only reorder the switch arms.** This fixes splitting but leaves the acceptance
rule accidental and leaves the useless self-suggestion in the popup.

### Consequences

* A writer can always split while the popup is merely showing its default item.
* Tab remains the fastest way to accept that default and still falls through to
  the element workflow when no completion exists.
* Up/Down followed by Enter explicitly accepts the selected item.
* Exact no-op candidates do not appear through the bridge. Ranking within the
  entity index remains unchanged for its other consumers and tests.
* The popup remains read-only until one of those acceptance gestures occurs.

### Tests and invariants

* `app/test/editor/autocomplete_test.dart` proves default Enter splits, Tab
  accepts, navigated Enter accepts, and Escape dismisses without editing.
* `crates/bridge/src/api/doc.rs::a_block_is_not_offered_back_to_itself_as_a_completion`
  proves the active block is not returned as an identical candidate.
* `app/test/editor/element_selector_test.dart` proves the palette takes focus and
  Escape after another panel had focus, even when editor completions are non-empty.
* `app/integration_test/editor_test.dart` and `writing_test.dart` exercise the
  complete real-core paths that originally exposed the failures.

---

## ADR 0018 — The editor is fluid, and its line breaking stays in Dart, pinned to Rust by a test

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (decided during the
mid-project remediation) · **Narrows:** ADR 0005 for 1.0; does not reverse it

### Context

Two questions were answered by the code without ever being written down, and the
audit (`REVIEW.md`, F3 and F10) found them by finding their consequences.

The first is §16's open item: does the editor view show page indication at all?
The editor has been a continuous scrolling surface since Phase 2 and nothing in
it knows what a page is.

The second is sharper. ADR 0005 accepted the custom surface partly on the promise
that "the editor renders the lines the `layout` crate computes rather than
duplicating it", and `metrics.dart` has carried a comment since Phase 2 saying
its numbers were on loan until that crate arrived. The crate arrived in Phase 6.
The editor still wraps its own text — and the two implementations disagree in
five observable ways:

| | `line_layout.dart` | `layout::break_lines` |
| --- | --- | --- |
| counting unit | UTF-16 code units | `char`s (an emoji is 1, not 2) |
| spaces at a wrap point | consumes one | consumes the whole run |
| trailing space at the width boundary | emits a phantom empty row | emits one row |
| tabs | one column | 4-column tab stops |
| hard newlines | none until remediation Phase 2 | splits first, always |

Nothing was testing for agreement, so the drift was free.

### Decision

**The editor view stays fluid and unpaginated through 1.0**, and **the Dart
wrapper stays**, as one implementation of a contract the Rust engine also
implements.

* No page breaks, page numbers, or page gutters in the editing surface. Page
  awareness lives in Phase 7's preview and the PDF, both rendered from the same
  `PaginatedScript`.
* `line_layout.dart` remains the wrap implementation on the keystroke path.
* The behaviour the two must share is written down as a contract (remediation
  Phase 6A) and enforced by a corpus-wide differential test comparing *wrap
  boundaries*, not rendered strings, for every block of every corpus file
  (Phase 6C). Where they must agree, drift fails CI.
* The five divergences are resolved by changing **Dart to match Rust**. The
  paginator is authoritative because it is what the PDF prints, and a writer who
  sees a line break in the editor that the page does not have has been lied to by
  the cheaper of the two.
* This narrows ADR 0005 rather than reversing it: that record's concern is that
  there be **one specification** of screenplay geometry, and the differential
  test is what supplies it. Should the editor ever grow page indication, this
  record is the one to supersede.

### Alternatives considered

**The editor asks Rust for wrap points per keystroke.** The literal reading of
ADR 0005. Rejected: it puts a bridge round trip and a cache-invalidation protocol
on the path with the 16 ms p99 budget (§1.3), and it solves by architecture what
one test pins for free. The bridge would also have to answer for a block that is
mid-composition, which is exactly when the answer is least stable.

**Rust computes every block's wraps on open, and patches them per edit.** No
per-keystroke round trip, but it is a second layout cache living in the bridge,
invalidated by every edit and every width change — strictly more machinery than
the differential test, and a new thing to be wrong.

**Paginate the editor itself.** Rejected by §16's own recommendation: fluid is
faster and simpler, and this would put page-break rules — the part of the
paginator that iterates to a fixed point — on the typing path.

### Consequences

* Two implementations exist on purpose. That is only safe while the differential
  test exists; until remediation Phase 6C lands, agreement is asserted for hard
  newlines alone and assumed everywhere else. Phase 6 is not complete without it.
* `metrics.dart`'s "on loan" framing is wrong and has been corrected in place:
  the numbers stay.
* F10's uppercase divergence must be settled *in the contract*, not left to
  whichever side is read first: the editor refuses length-changing uppercase (ß)
  to keep caret columns honest, and `layout::display_text` uppercases
  unconditionally.
* Emphasis markers count as columns on both sides — see ADR 0019, which is what
  keeps this contract from needing a notion of hidden text.
* If the differential test ever becomes impractical to maintain, the fallback is
  to consume Rust's wraps, not to let the test rot.

### Tests and invariants

This record is a decision; its enforcement is remediation Phase 6B/6C, and the
honest statement today is that most of it is not enforced yet.

* Exists: the hard-newline half, in `app/test/editor/line_layout_test.dart` and
  the reference-fixture case in `app/integration_test/editor_test.dart`.
* Required before Phase 6 closes: a corpus-wide differential test over every
  block of `testdata/`, comparing wrap boundaries, printing source block, width
  and both boundary lists on failure; plus a regression case for each of the five
  divergences above.

---

## ADR 0019 — Emphasis markup is displayed literally in the editor through 1.0

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 2 (recorded during the
mid-project remediation)

### Context

§16 left open whether `*italic*`, `**bold**`, `***bold italic***` and
`_underline_` appear in the editor as typed or are styled with their markers
hidden. The editor has shown them literally since Phase 2, because nothing in it
interprets them; no record said whether that was the decision or the default.

### Decision

**Literal, for 1.0.** Markers are ordinary characters: they are shown, they are
selectable, they are counted as columns for line breaking in the editor *and* in
the paginator. The PDF renderer (Phase 7) is the only thing that interprets them.

### Alternatives considered

**Style the text and hide the markers.** What most editors do, and prettier.
Rejected for 1.0 because it reintroduces exactly the divergence
`metrics.dart::displayText` refuses: display length stops matching model length,
and every caret column, click mapping and selection rectangle needs a second
coordinate space. That is the bug class remediation Phase 2 just spent a phase
removing for hard newlines.

**Style the text and keep the markers visible.** Cheaper — no second coordinate
space — but it is a half-measure that still needs a Fountain emphasis parser in
Dart, which is a screenplay-semantics question and therefore Rust's (§2.1).

### Consequences

* The editor never transforms text except by the length-preserving uppercase in
  `displayText`. Model offsets and display offsets stay equal.
* ADR 0018's differential test stays simple: both sides count the same
  characters, because neither side hides any.
* Fountain stays honest on screen — what is in the file is what is displayed.
* Upgrading later costs nothing that is not already owed: the emphasis parser
  Phase 7's PDF needs is the same one a styled editor would consume.

### Tests and invariants

* `app/test/editor/line_layout_test.dart` measures columns from model text, so a
  marker that stopped counting would move a wrap boundary and fail there.
* `crates/document/tests/element_change_preserves_text.rs` and
  `app/integration_test/writing_test.dart` hold the editor to changing no
  characters it was not asked to change.
* There is no styling code to test the absence of; this record is what says that
  absence is deliberate.

---

## ADR 0020 — Pagination crosses the bridge as an async snapshot job, and the page count is written after a save

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (decided during the
mid-project remediation) · **Implemented by:** remediation Phase 6D/6E

### Context

`crates/layout` is complete, deterministic and golden-tested, and no code outside
its own tests calls it. `crates/bridge/Cargo.toml` has no edge to it,
`ScriptView::page_count` has been a hard zero since Phase 4, the debug dump is a
method with no view, and `repaginate` — the incremental path, with its
checkpoints and its cache (ADR 0022) — has never run in the application at all.
Phase 7 is the phase that consumes pagination, and it was going to have to
integrate it under feature pressure (audit finding F3).

The remaining question was what should *ask* for a pagination, given §2.3: the
actor thread owns the document and must never block, and anything over 2 ms is
async.

### Decision

**Pagination is an asynchronous job over an owned snapshot, and a successful save
is what triggers it.**

* `bridge` depends on `slugline_layout`. It defines its own DTOs for the result;
  internal layout types do not cross the boundary unexamined.
* The actor is visited twice, in the shape `write_document` already uses: take
  `ScriptSnapshot` plus the revision on the actor, let go, paginate on a worker,
  come back to record the result. `ScriptSnapshot` exists precisely to be the
  owned value that can leave (`crates/layout/src/lib.rs`).
* A result is committed only if it still describes the revision it was computed
  from. A stale result is dropped, never merged, and never overwrites a newer
  page count.
* **`page_count` is written after every successful save** — explicit and
  autosave alike — from the snapshot that was saved. It is not recomputed per
  keystroke, and library scan does not paginate unopened scripts: a scan that
  parsed and paginated every script would blow the cold-start budget (§1.3).
* Pagination failure never fails a save. The page count keeps its previous value,
  or stays absent.
* A page count is a **cache**, like everything else in the library index (§the
  storage crate's own rule): an entry never saved by a layout-capable build shows
  nothing, which is what the Phase 4 note already promised.

### Alternatives considered

**Paginate on every edit, or on a debounce.** Rejected: it burns CPU for a number
nobody is reading while typing, and §1.3's idle budget is 0% — a debounce is a
timer, and timers in the core are forbidden (ADR 0014).

**Paginate at library-scan time so every entry has a count.** Rejected on the
cold-start budget: the library must open in the time it takes to `stat` a
directory, not to parse it.

**Paginate on the actor thread and skip the snapshot.** Rejected outright by
§2.3. Full pagination of 120 pages is budgeted at 50 ms; the actor's budget is
2 ms.

**Expose `PaginatedScript` verbatim through FRB.** Tempting, and it is the type
Phase 7 wants. Rejected for now: `Arc<[LayoutLine]>`, checkpoints and cache
statistics are internal machinery, and freezing them into the generated bindings
makes every future engine change an API change.

### Consequences

* Phase 7 starts by consuming an integrated engine. That is the whole point of
  doing this before it rather than during it.
* The library gains a real page count, which is also the first end-to-end proof
  that the paginator runs correctly outside its own tests.
* The incremental path finally runs in the application, which is where its
  checkpoint reuse will actually be exercised (ADR 0022).
* One more worker job exists whose results can arrive out of order; the revision
  guard is what makes that safe, and it is the same discipline the save path
  already uses with `mark_saved_at`.
* A debug pagination surface (remediation Phase 6F) consumes this result rather
  than reimplementing anything in Dart — §Phase 6 permits exactly one UI artifact
  and this is it.

### Tests and invariants

None yet; this is a decision recorded ahead of its implementation. Required
before remediation Phase 6 closes:

* Bridge tests for normal, empty, very long and tolerated-malformed documents.
* A save updates the page count; an autosave does too.
* A pagination that fails leaves the save successful and the count untouched.
* An older pagination result cannot replace a newer one.
* A library scan paginates nothing.
* The page count survives a restart.
* At least one integration test proving the application — not a crate test —
  invokes pagination.

---

## ADR 0021 — Pinned autocomplete entities live in the library index

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 5 (recorded during the
mid-project remediation)

### Context

§16 asked where pinned entities are stored and recommended the library index.
Phase 5 implemented that and recorded nothing, so a §16 open item was closed
silently — one of the drifts the audit's F7 names. The choice is not obvious:
a pin is per-script data, and the obvious per-script place is the script.

### Decision

**Pins live in the library index, keyed by script id, and are never written into
the `.fountain` file.**

* `EntityIndex` holds pins in memory (`pinned: BTreeMap<(EntityKind, String),
  String>`), separately from the frequency aggregates, so a pinned entity
  survives dropping to zero occurrences.
* `doc_set_entity_pinned` writes the session's whole pin set into the script's
  library entry (`ScriptEntry::pinned_entities`) and saves the index; opening a
  script loads them back with `load_pins`.
* An **unsaved script has no entry to write to**, so its pins live in the
  session and become persistent the moment it gains one. Nothing is invented to
  hold them in the meantime: a hidden store for a file the writer has not named
  is what §1.2 forbids.
* Ranking is unchanged by pinning: **exact prefix > frequency > recency >
  alphabetical**, with `pinned` a flag on the candidate rather than a rank. A pin
  guarantees a candidate is *offered*; it does not push it to the top. The
  standard scene components (`DAY`, `NIGHT`, `INT.`, …) are seeded the same way —
  offered when they match, ranked with everything else.

### Alternatives considered

**Store pins in the `.fountain` file**, as a note or a boneyard comment.
Rejected: §1.2 makes the file the user's, and a screenwriting tool that leaves
its own bookkeeping in a plain-text screenplay breaks interchange with every
other Fountain tool. It would also make a pin an *edit* — dirtying the document,
entering the journal, and colliding with round-trip byte-exactness (ADR 0007).

**Store pins in preferences.** Wrong scope: pins are about one script's cast and
locations, and would leak between scripts.

**Rank pins above everything.** Rejected: the writer's own most-frequent
character is the better suggestion nine times in ten, and a pin is a request to
be *remembered*, not to be first. Making it a flag keeps the ranking rule the one
sentence §Phase 5 specifies and unit-tests against a fixed corpus.

### Consequences

* Deleting the library index loses pins and nothing else — consistent with the
  index being a cache the storage crate can rebuild.
* Pins for a script are available the moment it opens, before anything is typed.
* A pin taken on an untitled script is kept for the session and written out with
  the rest once the script is saved.
* The `.fountain` output stays exactly what the writer wrote.

### Tests and invariants

* `crates/storage/src/library.rs::the_index_round_trips` writes a pin through
  `set_pinned` and reads it back out of a reloaded index file.
* `crates/document/src/entities.rs::ranking_is_exact_then_frequency_then_recency_and_deterministic`
  holds the ranking rule this record leaves unchanged, and
  `removing_the_last_occurrence_removes_the_entity_incrementally` holds the
  unpinned half of the drop-out behaviour.
* **Gap, recorded rather than papered over:** nothing tests that a *pinned*
  entity survives losing its last occurrence, which is the one behaviour the pin
  exists for. `EntityIndex::complete` merges the pinned map in unconditionally,
  so it holds by construction — but by construction is not by test. Worth one
  unit test in `entities.rs` next time that file is opened.

---

## ADR 0022 — Repagination is incremental by checkpoint, and validated rather than trusted

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 (recorded during the
mid-project remediation)

### Context

§5.4 requires incremental repagination inside 5 ms after a keystroke, against a
full pagination budget of 50 ms for 120 pages. Phase 6 built the machinery —
`PaginationCheckpoint`, a per-block layout cache, `CacheStats` — and, per §15
rule 6, owed a record of how it works. The audit found none (F7).

The danger with any incremental layout is not speed, it is *divergence*: an
incremental result that differs from what a full pagination would have produced
is a bug the golden tests cannot see, because they only ever run the full path.

### Decision

**Reuse is always proved, never assumed.**

* Every block carries a **fingerprint** — FNV-1a over its text, kind, dual flag
  and wrap width. A cached wrap is reused only when the fingerprint and the
  element layout both match; anything else is re-wrapped. FNV-1a is chosen for
  being stable across Rust versions, which a `DefaultHasher` is not, so a cache
  cannot behave differently on a different toolchain.
* Pagination retains **checkpoints**: page index, page number, the block that
  starts the page, its start line, and any continued character. `repaginate`
  restarts from the nearest checkpoint *before* the changed block, and only from
  one that starts cleanly on a block boundary with no dialogue continuation in
  flight — the two conditions that make a page's layout independent of what
  precedes it.
* A caller's hint about which block changed is **advisory**. Wrapped layout is
  validated for every block regardless, and a prefix of pages is retained only
  after the newly computed output proves it byte-for-byte equal. A wrong hint
  therefore costs time and cannot cost correctness.
* The break-rule loop is a **capped fixed point**; on failing to converge it
  falls back to the naive fill and records `fell_back_to_naive`. A page count is
  never allowed to depend on how many iterations ran.
* `CacheStats` reports hits, misses, reused pages and iterations, so a test can
  assert that the incremental path *was* incremental rather than merely correct.

### Alternatives considered

**Trust the changed-block hint and splice.** Faster, and the standard way to get
this wrong: any caller bug, any missed reinference, any dual-dialogue pairing
change turns into a page that silently differs from what a fresh pagination
would produce.

**Cache nothing and paginate fully every time.** 50 ms per keystroke against a
5 ms budget. Rejected by §1.3.

**Hash whole pages instead of blocks.** Coarser invalidation for no benefit: an
edit invalidates its page anyway, and per-block wraps are what is expensive to
recompute.

### Consequences

* The incremental path is bounded by the full path's correctness. Incremental
  output that differs from full output is a test failure, not a subtle artefact.
* The cache is dropped for blocks that no longer exist on every pagination, so it
  cannot grow past the document.
* Until remediation Phase 6D wires the bridge (ADR 0020), all of this runs only
  in `crates/layout/tests/`. That is the gap the audit named, not a fault in this
  design.

### Tests and invariants

* `crates/layout/tests/incremental.rs::one_edit_invalidates_one_block_and_reuses_a_checkpoint_prefix`
  — one edit misses exactly one block in the cache, at least eight pages are
  reused, and the reused prefix is equal to the previous output page for page.
  `CacheStats` is what proves the run was incremental rather than merely correct.
* `crates/layout/tests/incremental.rs::reference_pagination_is_identical_one_hundred_times`
  — the determinism requirement, over the 120-page reference.
* `crates/layout/tests/golden.rs::every_corpus_file_has_a_stable_letter_layout`
  — committed dumps, one per corpus file.
* `crates/layout/tests/break_rules.rs`: eleven tests, one minimal script per §5.3
  rule, including the pathological convergence case.
* `crates/layout/tests/pagination_is_fast_enough.rs`: the §1.3 budgets.
* **Gap, recorded rather than papered over:** no test compares `repaginate` of an
  edited snapshot against `paginate_snapshot` of that same edited snapshot — the
  one assertion that would catch incremental output diverging from full output.
  The engine validates the reused prefix internally, so the property holds by
  construction; ADR 0025's focused review should turn it into a test.

---

## ADR 0023 — One crash recovery is offered per launch

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (recorded during the
mid-project remediation)

### Context

Startup scans for journals and offers recovery. It opens the first offer the
writer accepts and returns, leaving any other journals on disk. A code comment
called this deliberate; nothing said whether it was acceptable, and the Phase 10
backlog carried "revisit multi-recovery UX" as scheduled work.

### Decision

**One offer per launch stands for 1.0.** Remaining journals are left untouched
and offered again at the next launch. Nothing is discarded, and no journal is
resolved without the writer seeing it.

### Alternatives considered

**Queue the offers and walk the writer through them.** More complete, and mostly
unreachable: the application holds **one open script at a time** (§1.4 rules out
multi-window and tabs for 1.0), so more than one crashed session requires a
crash, a relaunch, a second crash without resolving the first, and a third
launch. The failure mode of the simple design in that case is one extra dialog
on the next launch, which loses nothing.

**Resolve the others automatically.** Never: a journal is unsaved user text, and
discarding it without asking is the P0 §1.2 forbids.

### Consequences

* Recovery UX stays a single yes/no at startup, which is what it should be at the
  moment a writer wants their text back rather than a workflow.
* An unlucky sequence can leave a journal offered a launch later than ideal. It
  is still offered.
* This becomes wrong the day the app gains multi-window or tabbed editing — not
  on the 1.0 roadmap. Supersede this record then, do not stretch it.

### Tests and invariants

* What holds the *safety* half — a journal nobody resolved is never lost — is
  tested: `crates/bridge/tests/persistence.rs::recovery_will_not_replay_onto_a_file_that_moved_on`
  and `::a_journal_that_cannot_replay_is_left_on_disk_rather_than_emptied`, plus
  `app/test/editor/persistence_test.dart`'s "Recover and Discard are both offered,
  and nothing is automatic" and "closing the dialog decides nothing". Only
  `Journal::discard` removes a journal, and only on an accept or an explicit
  discard.
* ADR 0016's tests hold the accept path to losing nothing across a second crash.
* The *one offer* half is accepted by inspection, not by test: it is a `return`
  after the first opened offer in `app/lib/app.dart`, including on the `Degraded`
  path. Reaching a second simultaneous offer needs two crashed sessions, which
  needs two scripts open at once, which the application cannot do. A test would
  have to construct a state the app cannot reach.

---

## ADR 0024 — The interval autosave keeps running while the writer types

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (recorded during the
mid-project remediation) · **Extends:** ADR 0014

### Context

ADR 0014 gave the autosave two timers: idle (2 s after typing stops) and interval
(every 30 s regardless). The interval timer is deliberately *not* restarted by
typing — a writer who never pauses is exactly who it protects.

That is also what makes audit finding F4 reachable. A save renames a file the
watcher is watching, so the app's own save produces a `FileChangedOnDisk` event
about itself. Nothing correlates that event with the save that caused it. If a
keystroke lands between the rename and Dart's handling of the event, the check
finds the document dirty and different, and the writer gets "Something else has
written to this file" — mid-sentence, about their own autosave. "Take theirs"
would then genuinely discard their typing.

The tempting fix is to stop the interval timer during typing. That would remove
the symptom by removing the protection.

### Decision

**The interval save keeps firing during continuous typing. F4 is fixed on the
watcher side, by correlating the app's own writes.**

* The core records each path it has itself written, with a save generation
  counter, in the step of `write_document` that already runs on the actor after a
  successful write.
* The first matching `FileChangedOnDisk` for that generation is swallowed.
* `doc_external_change` remains the backstop: suppression is an optimisation
  against a spurious prompt, never the thing that decides whether the file really
  changed.
* Suppression records are cleared when they go stale, so a genuine external write
  that arrives later is never eaten by an old one.
* Explicitly **not** acceptable as fixes: "do not save while typing", lengthening
  the interval, or making the external-change dialog less alarming. The dialog is
  right for a real external change; it must simply never fire for our own.

### Alternatives considered

**Restart the interval timer on each keystroke.** Turns it into a second idle
timer, and the writer who never pauses — the one case ADR 0014 wrote the second
timer for — goes unsaved indefinitely.

**Compare content instead of correlating writes.** `doc_external_change` already
does, and it is not enough: between our rename and the event, the writer typed,
so the content legitimately differs. Content comparison cannot distinguish "the
file changed because we wrote it, and then more was typed" from "someone else
wrote it".

**Stop watching the file during a save.** The watch is on the directory (a
rename replaces the inode), so the window is not cleanly closable, and closing it
would also miss a genuine external write landing in the same instant.

### Consequences

* The two-timer design of ADR 0014 is unchanged, and this record is why it must
  stay unchanged.
* The core keeps a small amount of per-path state whose lifecycle has to be
  documented where it lives — it is a suppression record, not a lock, and losing
  it costs one spurious prompt rather than any correctness.
* A genuine external write in the same millisecond as our own save could be
  swallowed. `doc_external_change` catches it on the next event or the next save.

### Tests and invariants

Required by remediation Phase 4B, which implements this:

* Save, immediately type, deliver the watcher event caused by that save, assert
  no modal and no lost typing.
* Deliver a genuine later external modification, assert the real path still runs.
* Multiple watcher events from one atomic rename sequence.
* Generation cleanup.

Existing today: `crates/storage/src/watch.rs`'s tests — in particular
`a_save_by_rename_is_reported_too`, which is the very event this record has to
suppress, and `a_change_to_a_neighbour_is_not_reported` — and the external-change
dialog tests in `app/test/editor/persistence_test.dart` ("an unmodified document
reloads without asking", "a modified document prompts with three answers"). None
of them can see F4 today, because nothing yet distinguishes our own write.

---

## ADR 0025 — The paginator's break rules get a focused review before Phase 7

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 6 → 7 (scheduled during
the mid-project remediation)

### Context

The mid-project audit read the whole of `crates/` except the back half of
`crates/layout/src/engine.rs` — the `Paginator` break-rule implementation — and
said so (`REVIEW.md` §10.6, decision D-6). Everything else it left unread is
accepted on the strength of its tests. This one is not, for a specific reason:
its output has never been seen by a human. Golden files prove it is
*deterministic* and that it matches what it produced when the goldens were
written; they do not prove those pages are what §5.3 describes.

Phase 7 is where the output becomes user-visible, and §5.5 calibration is where
the break rules are interrogated against real printed pages.

### Decision

**A focused review of the back half of `engine.rs` is a gate on Phase 7, not a
task inside it.** It traces every page-break rule against §5.3 — orphan
prevention, dialogue splitting with `(MORE)`/`(CONT'D)`, scene-heading handling,
action splitting, the fixed-point cap, A4 derivation, deterministic ordering, and
source identity preservation — and reviews the golden tests for *coverage*
rather than pass status, adding rule-level tests where a rule is asserted only
incidentally.

The paginator is **not** to be rewritten absent concrete defects found by that
review.

### Alternatives considered

**Fold it into Phase 7 as it goes.** What D-6 originally suggested, and the
reason it is being made a gate instead: a rule defect found while building the
preview is found under pressure to ship the preview, and the cheapest resolution
at that moment is to change the golden file.

**Accept it on its tests, like the other unread modules.** Reasonable for
`find.rs` or `backup.rs`, whose behaviour is fully described by their assertions.
Not reasonable here: "this dump is stable" is a much weaker claim than "these
pages are correct", and no human has checked the second.

### Consequences

* Phase 7 begins with the engine either confirmed or corrected, and with any
  golden file that changes doing so as a reviewed decision rather than a fix.
* The review costs no extra calendar — it rides along with the Phase 7 kickoff —
  but it is a checkbox that can block, which is the point.
* Any defect found becomes a rule-level test first, in the style
  `crates/layout/tests/break_rules.rs` already uses.

### Tests and invariants

* Existing: `break_rules.rs` (one minimal script per rule), `golden.rs`
  (committed dumps, determinism over 100 runs), `incremental.rs`.
* Required by the review: a named test for any rule found to be covered only by a
  golden dump, and for any defect it finds.
* Recorded in `REMEDIATION_PLAN.md` Phase 6G; the review is not complete until
  its findings are written there.

---

## ADR 0026 — One save of a script at a time, by a per-session lock

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 4A)

### Context

`write_document` is deliberately three steps (§2.3): plan on the actor thread,
write off it, record back on it. The actor serialises each step. It does not
serialise the *sequence*, and nothing else did either.

So two saves of one script could plan in order and write in reverse. The pair
that reaches this in practice is an autosave already past its due point and an
explicit Ctrl+S: `AutosaveDriver._saving` guards only the driver's own calls, and
Ctrl+S goes through `saveWithDialogs → core.save()` without touching the driver,
while `withModal`'s suppression holds *future* autosaves rather than one already
in flight. With an edit landing between the two plans, the file transiently held
older bytes than the save that had already answered "Saved". Audit finding F5.

`mark_saved_at(min)` made it self-heal at the next autosave and both journal
checkpoints stayed consistent with whatever text won, so no text was lost. But
"the file briefly contains something older than what I was told was saved" is not
a property this codebase tolerates anywhere else.

### Decision

**A `Session` owns an `Arc<Mutex<()>>`, and every writer of that session's file
holds it across all three steps.** `write_document` takes it first, before it
plans; so does `backup_restore`, which is also a write of the document's file.

The lock is taken **off** the actor thread, by code that is already on an FRB
worker. Nothing inside an actor closure may take it — the point is that the actor
stays free while the disk is busy, and the one actor round trip this adds is two
channel sends to fetch the `Arc`.

Three consequences are the decision as much as the lock is:

1. **A second save waits; it is never refused.** §10 does not allow a save to be
   dropped because the timing was awkward.
2. **The plan is made after the wait.** So the save that queued writes whatever
   the document says by then — which is the coalescing, without a queue: if the
   save it waited for already wrote everything, it finds the document clean and
   answers `Unchanged`.
3. **It is per session.** Two scripts still save at the same time, and will still
   do so if the application ever opens more than one at once.

Alongside it, `SaveStateChanged` now carries the document's real dirty state
rather than a hardcoded `false`, and `AutosaveDriver` stops its timers only when
the document actually came back clean. An edit that lands while the file is being
written is genuinely unsaved, and both of those used to say otherwise.

### Alternatives considered

**A "save in flight" boolean, second save refused.** The audit's own first
suggestion. Rejected because refusing needs somewhere to reschedule from, and the
core has no timer and must not grow one (§1.3, ADR 0014) — so the refusal would
have to be handed back to Dart, and an explicit Ctrl+S that answers "busy" is a
worse thing to show a writer than one that takes 30 ms.

**A queue of pending saves on the session.** More machinery for the same result:
the queue can never usefully hold more than one entry, because a second waiter
would plan the same document state as the first. Replanning after the wait gets
that for free.

**One global save lock.** Simpler, and wrong the moment two scripts are open: one
script on a slow disk would stall an unrelated one. `one_script_at_the_disk_does_
not_hold_up_another` exists to stop this being reintroduced.

**Fixing it in Dart, by routing Ctrl+S through `AutosaveDriver`.** Rejected on
the same principle as ADR 0011: the guarantee belongs where the writes are. Dart
would still not cover `backup_restore`, a second window, or anything the bridge
gains later.

### Consequences

* A save can now block an FRB worker thread for the length of another save. That
  is bounded by one file write, saves of one script are rare, and FRB's default
  handler grows its pool rather than starving.
* `doc_save` can answer `Unchanged` where it previously answered `Saved` — when
  it queued behind a save that wrote its bytes for it. `SaveStatus.record`
  already treats `Unchanged` as success, and the status line reads `core.dirty`
  live, so the writer sees "saved".
* The lock is deliberately not held for `library_rename` or `library_duplicate`:
  neither writes the open document's own file through the save path.
* Poisoning is recovered from with `PoisonError::into_inner`. The lock guards
  ordering, not data; refusing to save because an earlier save panicked would be
  the wrong way round.

### Tests and invariants

In `crates/bridge/src/api/files.rs`, against the real save path:

* `an_older_save_cannot_land_after_a_newer_one` — the audit's scenario exactly.
  A `#[cfg(test)]` seam holds the first save between its plan and the disk; the
  second save is started after an edit and given half a second to overtake it.
  It must not, and the file must end with the newest text.
* `an_explicit_save_queued_behind_an_autosave_still_writes_the_newest_text` —
  the overlap that is reachable today.
* `a_save_with_nothing_left_to_write_says_unchanged` — the coalescing.
* `one_script_at_the_disk_does_not_hold_up_another` — the per-session half, and
  the one test here that passes without the lock as well as with it.
* `opening_one_path_twice_over_is_one_document` — the same check-then-act the
  audit found beside F5: `library_open` reads the file off the actor between its
  check and its insert, so `open_source` makes the check again where it is atomic.

In `app/test/editor/autosave_test.dart`:

* `an autosave that collides with one in flight is owed, not dropped`.
* `an edit that lands mid-write does not stop the clock`.

All four Rust save tests and both Dart tests were confirmed to fail with the lock
and the Dart changes reverted, not assumed to.

---

## ADR 0027 — A save rebuilds its journal around what was typed during it

**Date:** 2026-07-25 · **Status:** accepted · **Phase:** 4 (mid-project
remediation, Phase 4A follow-up) · **Extends:** ADR 0013

### Context

`Journal::checkpoint` truncates a journal to a bare header whose `base` is the
bytes just written, and its comment states the reason: "the records before it
describe edits that are now in the file, and replaying them onto it would apply
them twice."

That is true of every record a save covered. It is false of anything typed while
the save was writing. A save plans its bytes on the actor thread, lets go, and
writes off it (§2.3, ADR 0012) — so an edit can land in between, and
`mark_saved_at(plan.revision)` correctly leaves the document dirty for it. But
the checkpoint then threw its journal record away along with the rest.

The result was a window in which a keystroke was in neither the file nor the
journal. Worse than merely unrecorded: at the next launch `recovery_pending`
finds an empty journal, reads it as a session that ended cleanly, and
`discard_at`s it. Nothing is offered and nothing says anything was lost. §1.2
calls losing user text a P0, and the journal exists so that "not a keystroke
beyond the last" is true; this was a gap in exactly that claim. Recorded as F15
while verifying Phase 4A, which neither caused it nor widened it.

### Decision

**A save that had edits land during it rebuilds its journal around them instead
of emptying it.**

`Session::begin_save` arms a buffer *inside the same actor closure that reads the
bytes to be written*, so there is no instant in which an edit is in neither. Each
subsequent `Session::record` appends to the journal as before and then keeps the
patch. Step three takes the buffer:

* **Empty** — the ordinary case, and nothing changes: `checkpoint` as before.
* **Non-empty** — `Journal::rebuild_at` writes a whole successor journal whose
  `base` is the bytes just written and whose records are exactly those patches,
  through `atomic::save_atomically`.

`rebuild_at` is `Journal::rebuild` (ADR 0016) addressed by path rather than by
id, because a Save As has already changed the id by the time step three runs
while the journal file has not moved. Rebuilding by id there would leave the old
file behind, and an unowned journal is a recovery offered for a session that did
not crash.

The buffer is armed only for the length of one write. A session that is not
saving buffers nothing, so the cost falls on the file write and not on typing —
and the patch is *moved* into `record` rather than cloned, so the keystroke path
allocates no more than it did.

### Alternatives considered

**Do not checkpoint at all when the document comes back dirty.** One line. The
journal keeps every record, but its `base` no longer matches the file, so
`journal::verify` refuses it and the next launch reports the offer as `blocked`.
Better than silent loss — the text is in a file a person can read — and much
worse than recovering it, which the rebuild does for the same window.

**Buffer every patch since the last checkpoint, unconditionally.** Simpler: no
arming, no disarming, no early-return discipline in `write_document`. Rejected on
memory: autosave can be turned off entirely (`autosave_enabled: false` is
supported on purpose), and a long session would then hold every patch of every
edit in RAM alongside the same data on disk. Arming for the width of one write
bounds it to what was typed in a few milliseconds.

**Re-append the kept records after `checkpoint` truncates in place.** No new
journal API needed. Rejected for the reason ADR 0016 gave for `rebuild`: a crash
between the truncate and the re-append loses exactly the records this exists to
save. A whole-journal write has to be atomic.

**Keep patch revisions and filter by `plan.revision`.** Considered and dropped as
redundant: arming happens in the same closure that serialises, so everything
buffered is by construction after the planned bytes. A revision field would be a
second source of truth for the same fact.

### Consequences

* Every path out of `write_document` after the plan must disarm — a refused save
  that left the buffer armed would hold patches for a checkpoint that never
  comes. There is one `abandon_save` for all three, and a test that covers each.
* A failed rebuild leaves the journal exactly as it was. Its `base` no longer
  matches the file, so recovery refuses it rather than replaying onto the wrong
  bytes; nothing is destroyed, which is the property that matters. Same shape as
  the failed `checkpoint` this replaces.
* `Session::record` takes its `Patch` by value. The only caller is
  `api::doc::journal`, which built it and dropped it.
* The window is now closed for the save path. It was never open for recovery:
  ADR 0016 already writes a successor journal rather than emptying one.

### Tests and invariants

In `crates/bridge/src/api/files.rs`, driving the real save path with the same
`#[cfg(test)]` seam Phase 4A added:

* `an_edit_typed_during_a_save_is_still_in_the_journal` — the defect. A save is
  held between planning and writing, an edit lands, and after it completes the
  file holds the older bytes, the document is dirty, and *the journal replayed
  onto the file gives back what the writer can see*. That last assertion is the
  invariant; the test states it as `recovers_to() == the document`.
* `a_save_with_nothing_typed_during_it_empties_the_journal` — the ordinary case
  still checkpoints to zero records, so the rebuild is not on every save.
* `a_save_that_writes_nothing_does_not_leave_the_session_buffering` — all three
  abandon paths: clean, unwritable, and no path at all.

Confirmed to fail with the rebuild reverted: the mid-write test reports zero
journalled records where one was typed.
