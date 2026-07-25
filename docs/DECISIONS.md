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
  `libscreenplay_bridge.so` into `bundle/lib/`. Verified; CI asserts the file
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
* Verified by construction: adding `screenplay_layout` to `fountain`'s
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
