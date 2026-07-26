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
