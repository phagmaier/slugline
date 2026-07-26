# Screenwriting Application — Technical Specification & Build Plan

**Target platform:** Linux (X11 + Wayland), 64-bit
**UI:** Dart / Flutter (Linux desktop embedder, GTK)
**Core:** Rust (compiled as a `cdylib` linked into the Flutter bundle)
**Bridge:** `flutter_rust_bridge` v2
**Canonical format:** Fountain (`.fountain`)
**Status:** Draft 1 — working document, revise as decisions are made

---

## 0. How to Use This Document

This spec is organised into **phases**. Each phase has:

- A **goal** (one sentence — what becomes true when this phase ends)
- **Exit criteria** as checkboxes — these are the things you tick off
- **Tests that must pass** before the phase is considered done

Do not start a phase until the previous phase's exit criteria are all ticked. The phases
are ordered so that each one is independently demoable and each one de-risks the next.

**Where the project is, as of 2026-07-25.** Phases 0–6 are written. Between Phase 6 and
Phase 7 sits a **stabilization gate**: a mid-project audit (`REVIEW.md`) found defects
this document's checkboxes did not reflect, and `REMEDIATION_PLAN.md` works through them
phase by phase. Phase 7 begins only when that plan's Phase 10 authorization gate passes.
A box ticked here means the behaviour is implemented *and* tested; where the remediation
found one that was not, the box has been unticked and says why, with the finding number.
That plan, not this section, is the live tracker.

**If you are handing work to AI agents:** give an agent exactly one phase section, plus
§2 (Architecture) and §3 (Data Model). Do not let an agent work across phase boundaries.
Every phase specifies its tests first — require the agent to write the failing test before
the implementation.

---

## 1. Product Goals & Constraints

### 1.1 What this application is

A fast, keyboard-driven screenplay editor that reads and writes plain Fountain files and
produces submission-quality PDFs. Nothing else.

### 1.2 Hard constraints

| Constraint | Rule |
| --- | --- |
| Platform | Linux is the only supported target. Do not add code for other platforms, but do not *deliberately* break portability either. |
| Dependencies | Every new dependency (Rust crate or pub package) requires a written one-line justification in `docs/DEPENDENCIES.md`. Reject anything that pulls a large transitive tree. |
| Data ownership | Scripts are ordinary files at paths the user chose. No database, no hidden store, no lock files that survive a crash. |
| Network | The application makes **zero** network requests. No telemetry, no update checks, no font downloads. This is a build-time assertion (see §13). |
| Data loss | Losing user text is a P0 bug, always. Every other bug is lower priority. |

### 1.3 Performance budget

These are not aspirations; they are acceptance thresholds. Measure them in CI on a
120-page reference script (`testdata/reference-feature.fountain`, ~19,000 words).

| Metric | Budget |
| --- | --- |
| Cold start → blinking cursor in an empty script | < 500 ms |
| Open 120-page `.fountain` → editable | < 250 ms |
| Keystroke → glyph on screen (p99) | < 16 ms |
| Incremental repagination after one keystroke | < 5 ms |
| Full repagination, 120 pages | < 50 ms |
| PDF export, 120 pages | < 1000 ms |
| Idle CPU (window focused, no input) | 0% (no polling timers, no animation loops) |
| RSS with 120-page script open | < 250 MB |
| Stripped release binary + bundle | < 60 MB |

### 1.4 Explicit non-goals (from the requirements doc, restated as build rules)

No analytics, no productivity metrics, no cloud, no collaboration, no AI generation, no
scheduling, no budgeting, no casting, no revision colours, no mobile sync, no Final Draft
import, no outlining system. **Do not build scaffolding "for later" for any of these.**
Adding a plugin system, an event bus, or an abstraction layer whose only current consumer
is one call site counts as violating this rule.

---

## 2. Architecture

### 2.1 The split

The single most important design decision is where the boundary sits. It sits here:

**Rust owns the document. Flutter owns the caret.**

| Responsibility | Owner |
| --- | --- |
| Canonical document model | Rust |
| Fountain parse / serialise | Rust |
| Undo / redo history | Rust |
| Element type inference | Rust |
| Entity index (characters, locations, times) | Rust |
| Autocomplete candidate ranking | Rust |
| Pagination / line layout | Rust |
| PDF rendering | Rust |
| File I/O, autosave, atomic writes, backups | Rust |
| Spell checking | Rust |
| Script library index | Rust |
| Text input, IME, composition | Flutter |
| Caret rendering, selection painting | Flutter |
| Scrolling, virtualisation | Flutter |
| Keyboard shortcut dispatch | Flutter |
| All widgets, theming, layout | Flutter |

Flutter never derives screenplay semantics on its own. If Flutter needs to know whether a
line is a scene heading, it asks Rust. There is exactly one source of truth.

### 2.2 Process model

Single process. The Rust core is a `cdylib` (`libslugline_bridge.so`) bundled into the
Flutter Linux app and loaded via `dart:ffi` through `flutter_rust_bridge`.

Do **not** use a separate daemon process with IPC. It triples the packaging complexity, adds
serialisation cost on the hot path, and creates a whole category of orphaned-process bugs
for zero benefit here.

### 2.3 Threading

```
Dart UI isolate ──(FRB)──> Rust worker pool ──> Actor thread ──> AppState
                 <──(StreamSink)── event stream
```

- `AppState` lives on **one dedicated Rust thread** (an actor) and is reached through a
  command channel. This makes every mutation serialised and removes a whole class of lock
  ordering bugs. Commands return results via a oneshot channel.
- Long jobs (PDF export, full repagination, spell-check sweep, library scan) run on a
  **separate Rayon/`std::thread` pool** against an immutable snapshot of the document, so
  they never block editing.
- Rust → Dart notifications go over a single `StreamSink<CoreEvent>`. Dart subscribes once
  at startup.

**Rule:** every FRB call that can exceed 2 ms must be `async` on the Dart side.

### 2.4 The offset problem (read this before writing any bridge code)

Dart strings are UTF-16. Rust strings are UTF-8. Getting this wrong produces bugs that only
appear when a user types an em-dash, an accented name, or an emoji in a note — i.e. weeks
after you shipped.

**Rule: the bridge speaks UTF-16 code-unit offsets, always.** Rust stores UTF-8 and converts
at the boundary. Every offset field in the bridge API is named `*_utf16` with no exceptions.
Conversion helpers live in exactly one module (`bridge/src/offsets.rs`) and are unit-tested
against a string containing ASCII, Latin-1 accents, CJK, and an astral-plane emoji.

### 2.5 Repository layout

```
slugline/
├── Cargo.toml                  # workspace
├── crates/
│   ├── fountain/               # parse + serialise. No app deps. Pure.
│   ├── document/               # model, edit commands, undo, entity index
│   ├── layout/                 # line breaking + pagination. Pure, deterministic.
│   ├── render_pdf/             # PDF writer. Consumes layout output.
│   ├── storage/                # atomic write, autosave, journal, backups, library
│   ├── spell/                  # dictionary loading + checking
│   └── bridge/                 # FRB API surface, actor thread, cdylib
├── app/                        # Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── src/rust/           # FRB-generated — never hand-edit
│   │   ├── core/               # client wrapper around the bridge
│   │   ├── editor/
│   │   ├── navigator/
│   │   ├── preview/
│   │   ├── library/
│   │   └── settings/
│   ├── linux/                  # GTK embedder + CMake, bundles the .so
│   └── integration_test/
├── testdata/
│   ├── corpus/                 # .fountain inputs
│   ├── golden/                 # expected layout dumps + PDF hashes
│   └── reference-feature.fountain
├── docs/
│   ├── DECISIONS.md            # ADRs — one per non-obvious choice
│   └── DEPENDENCIES.md
└── tools/                      # build scripts, benchmark runner
```

**Layering rule (enforced by `python3 tools/check_layering.py` in CI, not by `cargo-deny` —
ADR 0004):** `fountain` depends on nothing in the workspace. `layout` depends only on
`document`. `render_pdf` depends only on `layout`. `storage` depends only on `document`.
`spell` depends on nothing. `bridge` *may* depend on everything — today it depends on
`document` and `storage` only; the missing `layout` edge is audit finding F3, added by
remediation Phase 6D. No cycles, no upward dependencies.

### 2.6 Dependency shortlist

| Need | Choice | Note |
| --- | --- | --- |
| FFI bridge | `flutter_rust_bridge` 2.x | Use its `cargokit` build integration so `flutter build linux` compiles Rust automatically. |
| PDF writing | `printpdf` | Highest-level option with font embedding. `pdf-writer` is the fallback if you need byte-level determinism control. |
| Screenplay font | **Courier Prime** (SIL OFL 1.1) | Free to embed and redistribute. Purpose-built for screenplays. Vendored into `crates/render_pdf/assets/`. |
| Spell checking | `spellbook` (pure Rust, Hunspell-compatible) | Avoids linking libhunspell. Reads system `/usr/share/hunspell/*.aff/.dic`. |
| XDG paths | `directories` | |
| File watching | `notify` | Only for detecting external modification of an open file. |
| Serialisation (prefs, library index) | `serde` + `serde_json` | Human-readable on disk, by design. |
| Property testing | `proptest` | For round-trip invariants. |
| Fuzzing | `cargo-fuzz` | Parser only. |

---

## 3. Data Model

### 3.1 Core types (`crates/document`)

```rust
/// Stable for the lifetime of a loaded document. Never reused after deletion.
/// Flutter uses this as its list key and as the anchor for selections.
pub struct BlockId(pub u64);

pub struct Document {
    pub title_page: TitlePage,
    pub blocks: Vec<Block>,
    next_id: u64,
    /// Byte-for-byte original file content, retained for lossless round-tripping.
    original_source: Option<Arc<str>>,
}

pub struct Block {
    pub id: BlockId,
    pub kind: BlockKind,
    /// The user-visible text, with Fountain markup for emphasis retained inline.
    pub text: String,
    /// Set when the element type was forced by the user or by explicit Fountain
    /// syntax (`.`, `@`, `>`, `!`). Suppresses automatic re-inference.
    pub forced: bool,
    /// Dual-dialogue right column marker (Fountain `^`).
    pub dual: bool,
    /// Byte range in `original_source` this block came from, if unmodified.
    /// `None` once the block has been edited.
    pub provenance: Option<Range<usize>>,
}

pub enum BlockKind {
    SceneHeading,
    Action,
    Character,
    Dialogue,
    Parenthetical,
    Transition,
    Centered,
    Lyric,
    Section { level: u8 },
    Synopsis,
    Note,
    PageBreak,
    /// Anything the parser recognised as valid Fountain but that the editor
    /// does not model. Round-trips verbatim.
    Opaque,
}
```

### 3.2 Lossless round-tripping — the mechanism

Requirement §3 of the features doc ("avoid losing information when opening and resaving")
is the hardest correctness requirement in the project. The mechanism is **provenance
tracking**:

1. On open, retain the entire source file in `original_source`.
2. Every block records the byte range it was parsed from.
3. On save, walk the blocks in order. For any block whose `provenance` is still `Some`,
   **emit the original bytes verbatim** rather than re-serialising. For edited blocks,
   re-serialise from the model.
4. Any construct the parser cannot classify becomes an `Opaque` block, which by definition
   always has provenance and therefore always round-trips exactly.

This turns "don't lose data" from a whole-format-fidelity problem into a much smaller
problem: only the blocks the user actually touched can lose formatting.

### 3.3 Selection & cursor

Flutter owns the caret but expresses it in document coordinates:

```dart
class DocPosition { final int blockId; final int offsetUtf16; }
class DocSelection { final DocPosition anchor; final DocPosition focus; }
```

A selection is normalised (anchor ≤ focus in document order) before it crosses the bridge.

### 3.4 Edit commands

All mutations go through one enum. This is what undo/redo records.

```rust
pub enum EditCommand {
    ReplaceText  { block: BlockId, range_utf16: Range<u32>, with: String },
    SplitBlock   { block: BlockId, at_utf16: u32 },
    MergeBlocks  { first: BlockId },                 // merge first + following
    SetKind      { block: BlockId, kind: BlockKind, forced: bool },
    InsertBlocks { after: Option<BlockId>, blocks: Vec<Block> },
    DeleteRange  { from: DocPosition, to: DocPosition },
    SetDual      { block: BlockId, dual: bool },
    SetTitlePage { field: TitleField, value: String },
}
```

Every command produces an inverse. Undo transactions coalesce by rule:

- Consecutive `ReplaceText` on the same block, same direction, within **600 ms** → one
  transaction.
- Any structural command (split/merge/insert/delete/kind change) always starts a new
  transaction.
- A transaction records selection **before** and **after**, so undo restores the caret.
- Undo depth: unbounded until 5,000 transactions or 64 MB, then drop oldest.

---

## 4. Fountain Specification Notes

The parser is line-based. It runs in two passes: block segmentation, then classification
with one line of lookahead and one of lookbehind.

### 4.1 Recognition rules

| Element | Rule | Forced form |
| --- | --- | --- |
| Title page | `Key: value` pairs at the very top of the file, terminated by a blank line. Values may continue on indented lines. | — |
| Scene heading | Line begins with `INT`, `EXT`, `EST`, `INT./EXT`, `INT/EXT`, `I/E` (case-insensitive), preceded by a blank line. | `.` prefix (but not `..`) |
| Character | All-caps line (letters, digits, `.`, `(`, `)`, `'`, `-`, spaces), preceded by a blank line, **followed by a non-blank line**. | `@` prefix |
| Dialogue | Any line directly following a Character or Parenthetical. | — |
| Parenthetical | Line wrapped in `( )` directly after a Character or Dialogue line. | — |
| Transition | All-caps line ending in `TO:`, blank line before and after. | `>` prefix |
| Centered | `> text <` | — |
| Lyric | Line begins with `~` | — |
| Section | Line begins with 1–6 `#` | — |
| Synopsis | Line begins with `=` (single) | — |
| Note | `[[ ... ]]`, may span lines | — |
| Boneyard | `/* ... */`, may span lines | — |
| Page break | Line of 3 or more `=` | — |
| Dual dialogue | `^` at end of a Character line | — |
| Action | Anything else. | `!` prefix |

Emphasis (`*italic*`, `**bold**`, `***bold italic***`, `_underline_`) is stored inline in
`Block::text` and interpreted at render time by both the editor and the PDF renderer. Do
not build a separate rich-text span model — the whole point of Fountain is that the markup
lives in the text.

### 4.2 Incremental / tolerant parsing

While the user is typing, the document is frequently invalid (a Character line with nothing
after it yet, an unclosed `[[`). The parser must never fail; it classifies best-effort and
never throws.

Re-inference is scoped: after an edit to block *N*, reclassify blocks *N−1* through *N+1*
only, and only if `forced == false`. Never reclassify a forced block. Never reclassify a
block the user is not currently in *and* did not just leave — this prevents text jumping
around under the caret.

### 4.3 Round-trip test corpus

Build `testdata/corpus/` with at least:

1. A minimal script (one scene, one line of dialogue)
2. Every element type, one of each
3. Dual dialogue
4. Nested/adjacent notes and boneyard comments
5. Title page with all fields, including multi-line values
6. A file using Windows line endings
7. A file with a UTF-8 BOM
8. A file with non-ASCII names (accents, CJK)
9. A file with unusual-but-valid whitespace (trailing spaces, tabs)
10. A malformed/truncated file
11. The 120-page reference feature

---

## 5. Layout & Pagination Specification

### 5.1 The key simplification

Screenplay typography is a **fixed monospace grid**: 12 pt Courier at 10 characters per inch
and 6 lines per inch. Line breaking is therefore a pure character-count operation — no font
metrics, no shaping, no platform text engine. This is why the pagination engine can live in
Rust as a pure function and produce bit-identical results everywhere.

`layout::paginate(&Document, &PageConfig) -> PaginatedScript` must be **deterministic and
side-effect free**. No I/O, no clock, no locale, no floating point in break decisions.

### 5.2 Metrics — US Letter (default)

Page 8.5" × 11". Grid origin at the top-left of the text area.

| Property | Value |
| --- | --- |
| Characters per inch | 10 |
| Lines per inch | 6 |
| Top margin | 1.0" |
| Bottom margin | 1.0" |
| Text lines per page | 54 |
| Page number position | 0.5" from top, right edge at 7.5" from left |

| Element | Left edge from page left | Width (chars) | Blank lines before |
| --- | --- | --- | --- |
| Scene heading | 1.5" | 60 | 2 (1 at top of page) |
| Action | 1.5" | 60 | 1 |
| Character | 3.7" | 33 | 1 |
| Parenthetical | 3.1" | 26 | 0 |
| Dialogue | 2.5" | 35 | 0 |
| Transition | right-aligned to 7.5" | 60 | 1 |
| Centered | centred within 1.5"–7.5" | 60 | 1 |
| Lyric | 2.5" (as dialogue) or 1.5" | 35 | 1 |

**These values are starting points, not gospel.** Different houses differ by a tenth of an
inch. Put every one of them in a single `layout::metrics` module as named constants with a
source comment, then calibrate against reference PDFs (see §5.5) before Phase 7 exits.

A4 (210 × 297 mm) uses the same character grid with a reduced line count per page; derive it
rather than hardcoding, and add a golden test for it.

Sections, synopses, and notes are **not rendered** in paginated output or PDF. They are
editor-only. Boneyard comments are likewise invisible.

### 5.3 Break rules

Applied in order after naive fill:

1. An explicit Fountain page break (`===`) always forces a break.
2. A scene heading may not be the last line on a page. If it lands there, push it — and it
   must be followed by at least **2 lines** of its scene on the same page.
3. A Character cue may not be the last line on a page. Push the cue with its dialogue.
4. Dialogue may be split across pages **only** if at least 2 lines remain on the first page
   and at least 2 lines carry to the next. Otherwise push the whole speech.
5. When dialogue is split: emit `(MORE)` at the character indent on the last line of the
   first page, and `CHARACTER (CONT'D)` at the character indent at the top of the next.
6. A parenthetical is never split internally, and a page may not break immediately after a
   parenthetical (it must carry at least one dialogue line with it).
7. Action paragraphs may split freely, but never leave a single orphan line — carry a
   minimum of 2 lines on each side.

Rules 2–7 can cascade. Implement as a fixed-point loop with a hard iteration cap (e.g. 8)
that falls back to naive fill if it fails to converge, so a pathological script can never
hang the app.

### 5.4 Incremental repagination

Full repagination of 120 pages must be under 50 ms, so a naive full re-run on every
keystroke is *almost* acceptable — but not at p99. Optimise as follows:

- Cache per-block line layout keyed by `(BlockId, text_hash, kind)`. An edit invalidates
  exactly one block's cache entry.
- Track a "pagination checkpoint" every N pages: page start block + carried state. On edit,
  re-run only from the nearest checkpoint before the edited block.
- Repagination is a background job on a document snapshot; the editor never waits on it.

### 5.5 Calibration procedure

Before Phase 7 exits: produce the same short script in a known-good reference tool, export
its PDF, and overlay it against yours. Every element's left edge and every baseline must
land on the same grid position. Record the comparison in `docs/DECISIONS.md`. This is the
one thing you cannot verify by unit test alone.

---

## 6. Bridge API Surface

Keep this small. Every function here is a maintenance liability.

```rust
// ---- Lifecycle ----
async fn init(config_dir: String, state_dir: String) -> Result<()>;
fn events() -> Stream<CoreEvent>;

// ---- Library ----
async fn library_list() -> Vec<ScriptEntry>;
async fn library_open(path: String) -> Result<DocumentHandle>;
async fn library_create(path: String) -> Result<DocumentHandle>;
async fn library_rename(id: ScriptId, new_path: String) -> Result<()>;
async fn library_duplicate(id: ScriptId) -> Result<ScriptEntry>;
async fn library_remove(id: ScriptId, delete_file: bool) -> Result<()>;
async fn session_restore() -> Vec<ScriptId>;

// ---- Document read ----
fn doc_block_count(h: DocumentHandle) -> u32;
fn doc_blocks(h: DocumentHandle, from: u32, to: u32) -> Vec<BlockView>;
fn doc_title_page(h: DocumentHandle) -> TitlePage;
fn doc_outline(h: DocumentHandle) -> Vec<OutlineEntry>;   // navigator
fn doc_dirty(h: DocumentHandle) -> bool;

// ---- Document write ----
fn doc_apply(h: DocumentHandle, cmd: EditCommand) -> EditResult;
fn doc_undo(h: DocumentHandle) -> Option<EditResult>;
fn doc_redo(h: DocumentHandle) -> Option<EditResult>;
async fn doc_save(h: DocumentHandle) -> Result<()>;
async fn doc_export_fountain(h: DocumentHandle, path: String) -> Result<()>;

// ---- Assistive ----
fn complete(h: DocumentHandle, block: BlockId, prefix: String) -> Vec<Completion>;
fn find(h: DocumentHandle, query: FindQuery) -> Vec<Match>;
fn replace_all(h: DocumentHandle, query: FindQuery, with: String) -> EditResult;
async fn spell_check_block(h: DocumentHandle, block: BlockId) -> Vec<Misspelling>;
fn spell_suggest(word: String) -> Vec<String>;

// ---- Output ----
async fn paginate(h: DocumentHandle, cfg: PageConfig) -> PaginatedScript;
async fn export_pdf(h: DocumentHandle, cfg: PageConfig, path: String) -> Result<()>;

// ---- Preferences ----
fn prefs_get() -> Preferences;
async fn prefs_set(p: Preferences) -> Result<()>;
```

`EditResult` carries: the ids of blocks that changed, blocks removed, blocks inserted, and
the post-edit selection. Flutter applies this as a patch — it does **not** refetch the
document.

`CoreEvent` covers: `SaveStateChanged`, `AutosaveFailed`, `PaginationReady`,
`EntityIndexUpdated`, `FileChangedOnDisk`, `BackupWritten`.

---

# BUILD PLAN

Twelve phases. Roughly ordered by risk: the things most likely to kill the project come
first.

---

## Phase 0 — Foundation, Toolchain, and the Editor Spike

**Goal:** The build works end to end, and you have decided how text editing will actually be
implemented in Flutter.

This phase exists because of one risk: **a multi-block rich text editor is the single
hardest thing in this project.** Flutter's built-in `TextField` is designed for form inputs,
not for a 120-page structured document with per-paragraph indentation and selection that
spans paragraphs. Do not discover this in Phase 3.

### Setup

- [ ] Rust workspace created with all seven crates, each with a passing placeholder test
- [ ] Flutter Linux desktop app created; `flutter run -d linux` opens a window
- [ ] `flutter_rust_bridge` v2 wired via `cargokit`; `flutter build linux` compiles Rust
      automatically with no manual step
- [ ] A round-trip proof: Dart calls a Rust function, gets a struct back, renders it
- [ ] A `StreamSink` proof: Rust pushes an event, Dart receives it
- [ ] Non-ASCII proof: Dart sends `"café 日本 🎬"` to Rust and back unchanged
- [ ] `docs/DECISIONS.md` and `docs/DEPENDENCIES.md` created
- [ ] CI on `ubuntu-latest`: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`,
      `flutter analyze`, `flutter test`, full `flutter build linux --release`
- [ ] Layering enforced in CI (no upward crate dependencies)

### The editor spike (timebox: 1 week, hard stop)

Build three throwaway prototypes. Each must load a synthetic 3,000-paragraph document and
support: typing in any paragraph, arrow-key navigation across paragraph boundaries, and a
selection that spans four paragraphs which can be copied as text.

- [ ] **Prototype A — per-block `EditableText` in a `ListView.builder`.** Each paragraph is
      its own focusable editable widget. Measure: scroll smoothness, focus transfer latency,
      how bad cross-paragraph selection is.
- [ ] **Prototype B — `super_editor`** with custom node types for the screenplay elements.
      This package is purpose-built for structured document editing and already solves
      multi-node selection and IME. Measure: bundle size cost, how much you have to fight it.
- [ ] **Prototype C — single custom editing surface**: one `TextInputClient` for the whole
      document, custom painting of lines, you own everything. Measure: how far you get in
      the timebox.
- [ ] Results recorded in `docs/DECISIONS.md` with numbers, not impressions
- [ ] **Decision made and written down.** All later phases depend on it.

> **Guidance:** "Bloat-free" is a property of the shipped binary and the runtime behaviour,
> not of the dependency count. A well-scoped editor package that saves you three months and
> adds 2 MB is not bloat. Writing your own IME-correct text editor when you wanted to write
> a screenwriting app is how this project dies. Let the measurements decide, but weight
> "will I still be working on this in six months" heavily.

### Exit criteria

- [ ] `git clone && flutter build linux --release` works on a clean machine with only
      Flutter + Rust installed
- [ ] Editor implementation approach chosen and documented
- [ ] CI green

---

## Phase 1 — Fountain Core (Rust only, no UI)

**Goal:** A pure Rust library that can parse any Fountain file into the document model and
write it back out without losing anything.

Do all of this with `cargo test`. Do not open Flutter this phase.

### Parser

- [x] Line segmentation with LF / CRLF / BOM handling
- [x] Title page parsing, including multi-line values and unknown keys
- [x] All element rules from §4.1 implemented
- [x] All forced-syntax prefixes (`.`, `@`, `>`, `!`, `~`, `#`, `=`) implemented
- [x] Dual dialogue (`^`)
- [x] Notes `[[ ]]` and boneyard `/* */`, including multi-line
- [x] Explicit page breaks (`===`)
- [x] Unclassifiable-but-valid content becomes `Opaque` blocks
- [x] Parser never panics and never returns an error — it always produces a document
- [x] Provenance byte ranges recorded on every block

### Serialiser

- [x] Emits verbatim source for blocks with intact provenance
- [x] Re-serialises edited blocks correctly, including re-adding forced prefixes where the
      element type would otherwise be misread on reparse
- [x] Title page emitted in canonical order
- [x] Output always ends with a single newline

### Tests

- [x] Every file in `testdata/corpus/` satisfies: `serialise(parse(f)) == f` **byte for byte**
- [x] `proptest`: for a generated random document, `parse(serialise(d))` has the same block
      kinds and text as `d`
- [x] `proptest`: applying a random edit then serialising then reparsing preserves all
      untouched blocks exactly
- [x] `cargo-fuzz` target for the parser runs 1M+ iterations with no panic
- [x] Parse of the 120-page reference file completes in < 100 ms (`criterion` benchmark)

### Exit criteria

- [x] `crates/fountain` and `crates/document` are feature-complete for §3–§5 of the
      requirements doc, with zero Flutter code written

---

## Phase 2 — Minimum Viable Editor

**Goal:** You can type a screenplay in a window. Nothing is saved yet.

### Bridge

- [x] Actor thread + command channel + `AppState` established
- [x] `offsets.rs` with UTF-8 ↔ UTF-16 conversion and its full unit test suite
- [x] `doc_blocks`, `doc_block_count`, `doc_apply` wired
- [x] `EditResult` patch application implemented on the Dart side (no full refetch)

### Editor surface

- [x] Virtualised block list — only visible blocks are built
- [x] Each element kind renders with its correct indent and casing:
      scene headings and character cues upper-case, dialogue indented, etc.
- [x] Typing inserts text and commits to Rust
- [x] Enter splits a block; Backspace at offset 0 merges with the previous block
- [x] Caret and selection render; click-to-place-caret works
- [x] Arrow keys, Home/End, PageUp/PageDown navigate across block boundaries
- [x] Shift + navigation extends selection across blocks
- [x] Select all
- [x] Copy, cut, paste (as Fountain-aware blocks)
- [x] Paste as plain text (`Ctrl+Shift+V`) — inserts as Action, no element inference
- [x] Automatic scroll keeps the caret in view with a comfortable margin
- [x] Undo / redo with correct caret restoration
- [ ] Editing works with an IME active (test with `ibus` and a CJK input method)
      — **built and tested through the platform interface, still not verified
      against `ibus` itself.** Phase 3 finished the one-block editing session: it
      now belongs to a block and ends when the caret leaves it, so a composing
      range can never describe text the platform is no longer looking at.
      `app/integration_test/ime_test.dart` drives the same `TextInputClient`
      interface `ibus` reaches us through — composition, dead keys, an emoji, a
      composition the caret leaves, a newline from the input method, and a
      clipboard round trip — against the real `.so`. The manual `ibus` + CJK check
      is still the one thing no test can stand in for, and it has not been run.

### Tests

- [x] Widget test table for Enter/Backspace behaviour in every element type
- [x] Integration test: type 500 characters, verify the Rust document matches
- [x] Benchmark: keystroke-to-frame p99 < 16 ms on the reference script

### Exit criteria

- [ ] You can write a scene, with dialogue, using only the keyboard, and it looks like a
      screenplay — **half true, by design.** Everything above is done, and a
      *parsed* script renders and edits as a screenplay. But nothing in Phase 2's
      list infers an element type or binds a key to one: "automatic detection on
      the current block as you type", the element shortcuts and the element
      selector are all Phase 3's list, so a script typed from nothing is Action
      throughout until Phase 3 lands. The command underneath (`SetKind`) is wired
      and covered end to end.

---

## Phase 3 — Editing Semantics & the Keyboard Workflow

**Goal:** Writing feels correct. You stop thinking about the software.

Requirements §5, §6.

### Element type control

- [x] Automatic detection on the current block as you type
- [x] Keyboard shortcuts for each element type (`Ctrl+1..9` or similar — document the map)
      — `Ctrl+1`…`Ctrl+0`, in `docs/KEYMAP.md`
- [x] Visible element selector in the UI showing the current block's type
- [x] Searchable command palette (`Ctrl+K`) covering every element type and command
- [x] Setting a type explicitly sets `forced = true` and suppresses re-inference
- [x] **Changing an element type never alters the text.** This is a dedicated test.

### Enter / Tab semantics

Define the full table in `docs/KEYMAP.md`. Baseline:

| Current element | Enter creates | Tab does |
| --- | --- | --- |
| Scene heading | Action | — |
| Action | Action | Cycle to Character |
| Character | Dialogue | Accept completion, else Parenthetical |
| Parenthetical | Dialogue | — |
| Dialogue | Action (or Character on double-Enter) | Cycle to Parenthetical |
| Transition | Scene heading | — |

- [x] Table implemented and covered by a parameterised widget test — with one
      division. The table's **content** is `crates/document/src/workflow.rs`'s and
      is proved by parameterised tests there and in `crates/bridge/src/api/doc.rs`;
      §2.1 does not allow a second copy of it in Dart, and a copy in the widget
      double could disagree with the one the application uses. The parameterised
      widget test in `app/test/editor/keyboard_workflow_test.dart` covers the
      **wiring** for every element type: that the key reaches the core with the
      caret the writer had, and that a kind change moves no text and no caret.
- [x] `Shift+Tab` reverses the Tab cycle
- [x] `Escape` dismisses completion / palette / dialog, and never loses text
- [x] Every automatic behaviour is overridable: an immediate element-type shortcut after an
      automatic change reverts and forces the user's choice
- [x] `INT.` / `EXT.` typed at the start of an Action block promotes it to Scene heading
- [x] Typing an existing character name in an Action-position block suggests Character
      — shown in the element bar as `Tab: Character — JOHN`. A suggestion only:
      `Document::character_suggestion` never changes the block, because an
      all-capitals line of action that happens to match a name is still action.

### Find and replace

- [x] Find with live match count and next/previous
- [x] Case-sensitive toggle
- [x] Whole-word toggle
- [x] Replace and Replace All (Replace All is one undo transaction)
- [x] Optional: restrict search to element types (dialogue only, etc.)

### Exit criteria

- [x] You can write a full scene without touching the mouse
      (`app/integration_test/writing_test.dart`)
- [x] Element-type changes are provably non-destructive
- [x] ADR 0005's input-surface gate, as far as an automated test can reach it:
      composition, dead-key accents, an astral-plane composition, a composition
      the caret leaves, and a clipboard round trip, all against the real `.so`
      (`app/integration_test/ime_test.dart`). Word-wise motion and deletion and
      the multi-click selections — the rest of what ADR 0005 assigns to this
      phase — are in `app/test/editor/word_motion_test.dart`.
- [ ] The **manual** half of ADR 0005's gate: `ibus` with a CJK input method, on a
      real desktop session. Still not run. No automated test can stand in for it —
      it is a property of the session, not of this code — and the automated tests
      above drive the same `TextInputClient` interface `ibus` reaches us through.
- [x] Accessibility — ADR 0005's last outstanding item, and ADR 0012 records how
      it was closed. Each visible block is a semantics node: a multiline text
      field whose label is the element type, whose value is the text as drawn,
      and — on the block holding the caret — whose selection reaches AT-SPI as
      `textSelectionBase`/`Extent`, with the cursor-movement, set-selection,
      set-text and clipboard actions. It is a render object rather than a
      `Semantics` widget because `SemanticsProperties` has no field for a text
      selection, and for a writing tool the caret is most of the point.
      `app/test/editor/accessibility_test.dart` asserts on the `SemanticsData`
      the owner produces rather than on the widgets. Nodes are built for the
      visible band only, and only while something is listening, so with no
      assistive technology attached the cost is not paid.

      **Not verified against a real screen reader.** The tests prove what arrives
      in the semantics tree; whether Orca reads a screenplay *well* from it is a
      question about a session, like the `ibus` check above, and it has not been
      asked.

---

## Phase 4 — Persistence, Safety, and the Library

**Goal:** The application cannot lose your work. This is the phase you do not rush.

Requirements §2, §10.

### Atomic save

Implement precisely this sequence, in `crates/storage`:

1. Write to `<name>.fountain.tmp-<pid>-<nonce>` in the **same directory** as the target
2. `fsync` the temp file
3. `rename(2)` the temp file over the target — atomic on Linux, same filesystem
4. `fsync` the containing **directory**
5. Preserve the original file's mode and ownership where permitted

- [x] Implemented exactly as above — `storage/src/atomic.rs`. Step 5 runs
      *before* the rename, because the file that will exist at the path is the
      temp file; after it there would be a window in which the new file is
      visible with the umask's permissions. Ownership is best effort by
      specification ("where permitted"): `chown` needs `CAP_CHOWN`, and a save
      must not fail because a script the writer copied in belongs to someone
      else.
- [x] Save failure surfaces a blocking, explicit error to the user — never a
      silent toast. `showSaveFailure` is `barrierDismissible: false`, because
      clicking a dialog away *is* the silent version.
- [x] Read-only file, full disk, and permission-denied are each handled with a
      distinct message and a "Save As" escape hatch. `SaveFailure` is one variant
      per message and `saveWithDialogs` is the single path every save in the
      application takes. A read-only file is refused **up front** rather than
      overwritten: `rename(2)` asks nothing of the target, so without the check
      the read-only bit would be silently defeated.

### Autosave & journal

- [x] Autosave debounced after edit inactivity (default 2 s) and on a hard
      interval (default 30 s), both configurable — `editor/autosave.dart`,
      `storage::prefs`. The clock is in Dart and ADR 0014 says why: the two
      suppression rules below are facts about a widget and about the platform's
      input connection, neither of which exists in Rust.
- [x] Autosave never runs while a modal is open or during an active IME
      composition. A suppression **holds** the save rather than cancelling it, so
      the save happens when the dialog closes — §10 does not allow a save to be
      dropped because the timing was awkward.
- [ ] **Two saves of one script cannot interleave.** They can today: the save is
      plan-on-actor → write-off-actor → record-on-actor, and nothing serialises
      an explicit Ctrl+S against an autosave already past its due point, so with
      an edit between the two plans the writes can land in reverse order and the
      file transiently holds older bytes than the save that already reported
      "Saved". Audit finding F5; remediation Phase 4A.
- [x] An append-only **edit journal** in
      `$XDG_STATE_HOME/slugline/journal/<script-id>.log` records committed edits
      between saves. It records the **outcome** of each edit rather than the
      command; ADR 0013 explains why, and why that is what makes "not a keystroke
      beyond the last" reachable. Measured cost on the keystroke path: p50
      0.81 ms against 0.78 ms without it, p99 1.14 ms against a 16 ms budget
      (`keystroke_benchmark_test.dart`).
- [x] On startup, an un-truncated journal means the previous session crashed →
      offer recovery. The journal's *absence* is what says a session ended
      cleanly: `Journal::discard` removes it and nothing else does.
- [x] Recovery presents a diff summary ("14 edits since last save") and Recover /
      Discard, never auto-applies. `recovery_pending` reads and counts; nothing
      is applied to any file until the writer answers, and a recovered document
      arrives **dirty** — the file on disk is still the one from before the
      crash, so even Recover still has to be confirmed by saving.

### Backups

- [x] Rolling backups written to a configurable location (default
      `$XDG_STATE_HOME/slugline/backups/`) — `storage/src/backup.rs`. Whole
      copies, not diffs: a diff chain is only as good as its weakest link and
      this is the thing that exists for when something has gone wrong.
- [x] Retention policy: last N versions plus one per day for M days (defaults:
      10 / 7). A day bucket is `millis / 86_400_000`, so no calendar is needed.
- [x] "Restore previous version" UI listing backups with timestamps and sizes —
      `library/backups_dialog.dart`.
- [x] Restoring a backup writes the current state to a new backup first, which is
      what turns a restore from a decision into an experiment. The dialog says so.

### External modification

- [x] `notify` watcher on open files — `storage/src/watch.rs`. It watches the
      **directory** and filters by name, not the file: an inotify watch follows
      the inode, so a watch on the file stops firing the first time anything
      saves over it by rename — which is how every careful editor on this
      platform saves, ours included.
- [x] If a file changes on disk while open and unmodified in the app → reload
      silently. The silence is deliberate: a writer who has changed nothing has
      nothing to lose and nothing to decide.
- [x] If it changes while there are unsaved edits → prompt (Keep Mine / Take
      Theirs / Save As). "Take theirs" says that it discards the undo history
      too, because it does.
- [ ] **The prompt never fires for our own save.** It can today: the watcher
      reports the app's own atomic rename, nothing correlates that event with the
      save that caused it, and the 30-second interval autosave fires mid-typing
      by design — so a keystroke landing in the window produces the full
      external-change modal about the app's own write. Audit finding F4;
      ADR 0024 records the fix, and remediation Phase 4B implements it. The check
      itself also reads the disk on the actor thread, which §2.3 forbids (F8,
      remediation Phase 4C).

### Library

- [x] Create, open, rename, duplicate, remove-from-library, delete-file. Remove
      and delete are two commands in two places in the menu, and only one of them
      asks twice.
- [x] Recent scripts list with path, last-modified, page count. The page count is
      still zero for every entry, and the library shows nothing rather than
      guessing. `layout` can compute one, but nothing calls it (F3); ADR 0020
      writes it after a successful save, in remediation Phase 6E.
- [x] Library index is a plain JSON file in `$XDG_DATA_HOME` — it is a *cache*,
      and the app works correctly if it is deleted. `Library::load` cannot fail:
      a missing, truncated or hand-mangled index is an empty one, and an
      integration test deletes it mid-session and opens a script anyway.
- [x] Missing files shown as missing, not silently dropped. A drive that is not
      mounted this morning is not a script the writer threw away.
- [ ] Session restore: reopen the scripts that were open last time, with scroll
      positions. **Half done, and the half that shows is the missing one.** The
      scroll row is parked in the index on every scroll, so a crash preserves it
      as well as a clean exit does, and `integration_test/persistence_test.dart`
      round-trips it — but nothing outside the generated bindings ever *reads*
      `ScriptView::scroll_row`, so a reopened script starts at the top. Audit
      finding F6; remediation Phase 5 applies it.

### Tests — these are the important ones

- [x] **Kill test:** `SIGKILL` the process mid-typing, relaunch, verify recovery
      offers the correct edits. `crates/bridge/tests/persistence.rs`
      (`sigkill_mid_typing_loses_nothing`) really does spawn a child, wait until
      it says it has typed, `kill -9` it, and replay what survived. It runs in
      `cargo test`, so CI runs it on every commit rather than only in the
      integration step.
- [x] **Interrupted write test:** the rename is made impossible (the target path
      is a directory), so the temp file is written and synced and the rename is
      what fails — which is exactly the window. The original is untouched and no
      temp file is left behind.
- [x] **Full disk test:** `a_full_filesystem_is_a_clear_error_and_no_truncated_file`.
      Mounting a tmpfs needs root, which a test run does not have; the test uses
      one when `SLUGLINE_FULL_DISK_DIR` names a small filesystem, and otherwise
      proves the part that can actually be wrong — that `ENOSPC` is classified as
      its own failure rather than a generic one, and that a failed save leaves
      the old bytes. **Give CI a tmpfs to make this the real thing.**
- [x] Fuzz the journal: truncated, corrupt, and partially-written records must
      not crash recovery. `storage`'s `no_byte_sequence_makes_the_reader_panic`
      sweeps every truncation of a real journal and every single-byte corruption
      of it; `a_damaged_journal_never_yields_a_patch_that_was_not_written_whole`
      is the stronger half — whatever survives must be a *prefix* of what was
      recorded. Recovery that invents an edit is worse than recovery that loses
      one.

### Exit criteria

- [x] You have deliberately killed the app 20 times while typing and never lost a
      keystroke beyond the last one — **as an automated equivalent, not as
      twenty runs by hand.** What varies between one kill and the next is *where*
      the journal was cut, so that is what
      `every_way_a_kill_can_cut_the_journal_loses_only_the_tail` varies: every
      truncation of a real journal is replayed, each must yield a prefix of what
      was typed, and the whole journal must still recover everything. Twenty
      manual kills would be the same assertion twenty times with less coverage.
      The by-hand version has not been run.
- [x] Requirement §10's "must never silently discard unsaved changes" is verified
      by test, not by inspection: `showUnsavedChanges` on every close path, and
      `EditorPageState.confirmClose` returns false when the save the writer chose
      did not happen — an abandoned save is not consent to lose the work.
      `app/test/editor/persistence_test.dart` covers the prompt and its defaults.

The window's close button goes through `AppLifecycleListener.onExitRequested`:
it asks about unsaved work, cancels the quit if the writer cancels, and discards
every journal on the way out — a clean exit must not leave a journal behind, or
the next launch offers a recovery for edits that are already in the file, and a
prompt that cries wolf is a prompt that gets dismissed the one time it matters.

### Still open at the end of Phase 4

- [ ] **Preferences UI.** `prefs_get`/`prefs_set` are wired and the file is
      read and written; nothing in the application edits it yet. §Phase 4 says
      the autosave numbers must be configurable, and they are — by hand, in
      `$XDG_CONFIG_HOME/slugline/preferences.json`. The settings pane is Phase 10.
- [ ] **A native file dialog.** ADR 0015: `file_selector_linux` brings `http`
      transitively and §1.2 makes "zero network requests" a build-time assertion.
      The chooser we wrote works and is keyboard-first, but GTK's is better.
      Revisit in Phase 10.

---

## Phase 5 — Entity Index & Autocomplete

**Goal:** The app knows who is in your script and where it happens.

Requirement §7.

### Index

- [x] Incrementally maintained index of: characters, scene locations, INT/EXT prefixes,
      times of day, transitions
- [x] Rebuilt incrementally on edit — never a full document scan on the hot path
- [x] Character extension normalisation: `(V.O.)`, `(O.S.)`, `(O.C.)`, `(CONT'D)`,
      `(SUBTITLE)` stripped for the index key, retained for display
- [x] Entities that no longer appear drop out of normal suggestions
- [x] Pinned entities persist regardless of occurrence count (stored per-script, in the
      library index — **not** written into the `.fountain` file)

### Completion

- [x] Character suggestions in Character-position blocks
- [x] Location suggestions after `INT. ` / `EXT. `
- [x] Time-of-day suggestions after ` - `
- [x] Standard scene-heading component suggestions (DAY, NIGHT, CONTINUOUS, LATER, …)
- [x] Transition suggestions
- [x] Ranking: exact prefix > frequency > recency. Deterministic, unit-tested with a fixed
      corpus.
- [x] **Nothing is ever inserted without an explicit keypress** (Tab accepts the
      default item; Enter accepts only after Up/Down explicitly navigates the popup).
      No inline ghost-text auto-acceptance. This is a hard requirement (ADR 0017).
- [x] `Escape` dismisses; a preference disables autocomplete entirely
- [x] Dismissing a specific suggestion suppresses it for the session

### Exit criteria

- [x] Completion latency < 5 ms at p99 on a script with 60 characters and 200 locations
- [x] A test proves no code path inserts completion text without a user keystroke

---

## Phase 6 — Pagination Engine

**Goal:** Rust can tell you exactly what every page looks like, as a pure function.

Requirement §12. No UI work in this phase beyond a debug dump view.

- [x] `layout::metrics` module with every constant from §5.2, each with a source comment
- [x] Monospace line breaking with correct whitespace handling (break on spaces, never
      mid-word unless a single word exceeds the column width)
- [x] Element indents and widths applied
- [x] Blank-line spacing rules
- [x] Naive page fill
- [x] All break rules from §5.3, as a capped fixed-point loop
- [x] `(MORE)` / `(CONT'D)` insertion on split dialogue
- [x] Explicit page breaks honoured
- [x] Scene numbering (left and right gutters) when enabled
- [x] Sections, synopses, notes, and boneyard excluded from output
- [x] Title page laid out (and **not** counted as page 1)
- [x] A4 config derived, not hardcoded
- [x] Per-block layout cache + checkpointing for incremental repagination

### Tests

- [x] Golden tests: each corpus file produces a stable text dump of
      `page → line → (column, content)`, committed to `testdata/golden/`
- [x] Determinism test: paginate the reference script 100 times, assert identical output
- [x] Break-rule tests, one per rule, with a minimal script that triggers it
- [x] Convergence test: a pathological script (alternating one-line scenes at page
      boundaries) terminates within the iteration cap
- [x] Benchmark: full pagination of 120 pages < 50 ms; incremental < 5 ms

### Exit criteria

- [x] Page count and every line position are reproducible and covered by golden files
- [ ] **Reachable from the application.** The crate paginates and nothing calls it: the
      bridge has no dependency on `slugline_layout`, `ScriptView::page_count` is always
      zero, the debug dump exists as a method with no view, and `repaginate` has never run
      outside `crates/layout/tests/`. Audit finding F3. Remediation Phase 6 wires it as an
      async snapshot job (ADR 0020), writes the page count after a successful save, and
      pins the Dart editor's own line breaking to `layout::break_lines` with a
      corpus-wide differential test (ADR 0018).

---

## Phase 7 — PDF Export, Title Page, and Preview

> **Gate.** Phase 7 does not begin until `REMEDIATION_PLAN.md`'s Phase 10 authorization
> gate passes — in particular until pagination is already integrated through the bridge,
> so that preview and PDF start by consuming an engine rather than integrating one under
> feature pressure, and until the back half of `crates/layout/src/engine.rs` has had the
> focused review ADR 0025 requires.

**Goal:** You can send the output to a production company without embarrassment.

Requirements §11, §13.

### Title page

- [ ] Fields: Title, Credit ("Written by"), Author(s), Source ("Based on…"), Contact, Draft
      date, plus free-form additional text
- [ ] Editable in the app, stored in the Fountain title page block
- [ ] Rendered as the first PDF page, not numbered, not counted as page 1

### PDF renderer

- [ ] Courier Prime vendored and embedded, with the OFL licence file shipped in the bundle
- [ ] Consumes `PaginatedScript` and places characters on the fixed grid — the renderer
      makes **no layout decisions of its own**
- [ ] US Letter default, A4 option
- [ ] Correct page numbering (`1.` style, top right, starting after the title page)
- [ ] Scene numbers when enabled
- [ ] Emphasis rendered: italic, bold, bold-italic, underline
- [ ] Text is selectable and searchable in `evince`, `okular`, Firefox, and Chrome
- [ ] Font subsetting to keep file size reasonable
- [ ] **Deterministic output:** fixed document `/ID`, timestamp overridable via
      `SOURCE_DATE_EPOCH`, no dependence on hash-map iteration order

### Preview

- [ ] Paginated preview view showing page boundaries, page numbers, real line wrapping,
      dialogue splits, explicit breaks, and the title page
- [ ] Preview is rendered from the **same** `PaginatedScript` the PDF uses — never a second
      layout implementation
- [ ] Editor zoom does not affect the preview or the PDF (test: change zoom, assert page
      count and golden layout unchanged)
- [ ] Preview-before-export flow in the export dialog

### Tests

- [ ] Golden hash test: reference script → PDF → SHA-256 matches a committed value
- [ ] Text-extraction test: `pdftotext` output matches expected content and reading order
- [ ] Visual calibration completed per §5.5 and recorded in `docs/DECISIONS.md`
- [ ] Benchmark: 120-page export < 1000 ms

### Exit criteria

- [ ] A printed page overlaid on a reference-tool page matches on every element indent

---

## Phase 8 — Navigator

**Goal:** You can move around a long script instantly.

Requirement §8.

- [ ] Sidebar listing scene headings in document order
- [ ] Each entry shows: scene number (when enabled), INT/EXT, location, time of day
- [ ] Character list derived from the entity index, with occurrence counts
- [ ] Clicking a scene scrolls the editor to it and places the caret
- [ ] Current scene highlighted as you scroll or type
- [ ] Keyboard navigation within the navigator; `Ctrl+P`-style quick jump to scene
- [ ] Filter/search within the navigator
- [ ] Collapsible; hidden state persists

**Deferred (explicitly out of scope for 1.0):** drag-and-drop scene reordering. When it is
built, it must be a single `EditCommand` producing a single undo transaction, with a golden
round-trip test proving the Fountain source stays valid.

---

## Phase 9 — Spell Checking

**Goal:** Typos are visible and correctable, and the script is never modified behind your
back.

Requirement §9.

- [ ] `spellbook` integrated; dictionaries loaded from system Hunspell paths
- [ ] Language selection listing installed dictionaries; clear message when none are found
- [ ] Checking runs on a background thread, per block, debounced, cached by block hash
- [ ] Misspelling underlines rendered in the editor
- [ ] Context menu: suggestions, Replace, Ignore Once, Ignore All, Add to Personal
      Dictionary, Add to Project Dictionary
- [ ] Personal dictionary in `$XDG_CONFIG_HOME/slugline/personal.dic`
- [ ] Project dictionary as a sidecar file beside the script; the script remains fully
      usable if it is missing or deleted
- [ ] Character names and scene locations from the entity index are automatically accepted
- [ ] Spell checking can be disabled entirely
- [ ] **No code path modifies text without an explicit user action** — dedicated test
- [ ] Checking a 120-page script does not drop a single frame in the editor

---

## Phase 10 — Preferences, Theming, and Polish

Requirement §14.

- [ ] Preferences stored as readable JSON in `$XDG_CONFIG_HOME/slugline/prefs.json`
- [ ] Light and dark appearance, plus follow-system
- [ ] Editor zoom / text size
- [ ] Spell-check language
- [ ] Autosave interval and enable/disable
- [ ] Default paper size
- [ ] Default PDF font (Courier Prime + any system monospace, with a warning that
      non-standard fonts break grid fidelity)
- [ ] Scene number visibility
- [ ] Autocomplete on/off
- [ ] Backup location and retention
- [ ] **Test: for every appearance-only preference, changing it leaves the golden pagination
      output byte-identical.** This is requirement §14's core constraint and it deserves a
      dedicated test file.
- [ ] Full-screen / distraction-free mode
- [ ] Keyboard shortcut reference sheet in-app
- [ ] Empty states, first-run experience, and a sensible default new-script template
- [ ] Every dialog dismissible with `Escape`; every destructive action confirmable and, where
      possible, undoable

---

## Phase 11 — Packaging & 1.0

- [ ] `.desktop` entry, icon set, MIME association for `text/x-fountain`
- [ ] Release build with LTO, `codegen-units = 1`, `panic = "abort"`, stripped symbols
- [ ] Flatpak manifest (primary distribution)
- [ ] AppImage (secondary)
- [ ] Plain tarball with a `README` install note
- [ ] Wayland and X11 both verified, including HiDPI and fractional scaling
- [ ] Tested on at least two distributions with different GTK versions
- [ ] `--version`, `--help`, and opening a file passed as `argv[1]`
- [ ] All performance budgets from §1.3 verified in CI on the reference script
- [ ] Licence compliance: Courier Prime OFL text shipped; `cargo-about` / `cargo-deny`
      report generated and reviewed
- [ ] Network-isolation assertion: the release build runs correctly with all network syscalls
      blocked (`unshare -rn`) — this is the proof of the zero-network claim
- [ ] `CHANGELOG.md`, tagged release, reproducible build instructions

---

## 12. Requirements Traceability

Every requirement from `features.md` maps to a phase. Use this to check nothing was dropped.

| Req § | Requirement | Phase |
| --- | --- | --- |
| 1 | Application goals & priorities | All |
| 2 | Script library and file management | 4 |
| 3 | Fountain file support, lossless round-trip | 1 |
| 4 | Screenplay editor (edit, undo, selection, find/replace, zoom) | 2, 3 |
| 5 | Screenplay elements & element switching | 1, 3 |
| 6 | Keyboard-driven writing workflow | 3 |
| 7 | Autocomplete and entity index | 5 |
| 8 | Scene and character navigation | 8 |
| 9 | Spell checking | 9 |
| 10 | Autosave, backups, recovery | 4 |
| 11 | Title page | 7 |
| 12 | Paginated preview | 6, 7 |
| 13 | Professional PDF export | 6, 7 |
| 14 | Preferences | 10 |
| 15 | Non-goals | §1.4 |

---

## 13. Testing Strategy

### Layers

| Layer | Tool | What it covers |
| --- | --- | --- |
| Unit | `cargo test` | Parser rules, edit commands, undo inverses, offset conversion, ranking |
| Property | `proptest` | Round-trip invariants, edit/undo/redo identity |
| Fuzz | `cargo-fuzz` | Parser and journal recovery against arbitrary bytes |
| Golden | committed fixtures | Pagination dumps, PDF hashes, Fountain round-trips |
| Widget | `flutter test` | Enter/Tab/Backspace tables, element switching non-destructiveness |
| Integration | `integration_test` | Open → edit → save → reopen; crash recovery; export |
| Benchmark | `criterion` + a Flutter frame-timing harness | The §1.3 budgets, run in CI |

### Invariants that must have a dedicated, named test

These are the requirements phrased as "must never". Each gets its own test file so a
failure is unambiguous.

- [ ] `never_loses_unsaved_changes` — no code path discards edits without user
      confirmation. **Held today, but in pieces, so the box stays empty.** The
      close paths are covered by `app/test/editor/persistence_test.dart` (every
      close prompts; an abandoned save is not consent), the crash paths by
      `crates/bridge/tests/persistence.rs` — `sigkill_mid_typing_loses_nothing`,
      `every_way_a_kill_can_cut_the_journal_loses_only_the_tail`, and the
      double-crash pair ADR 0016 lists — and journal damage by
      `crates/storage/src/journal.rs`. What does not exist is the one file this
      section asks for, whose failure would name the invariant rather than a
      symptom of it.
- [x] `element_change_preserves_text` — changing element type never alters characters
      (`crates/document/tests/element_change_preserves_text.rs`, and through the
      whole chain in `app/integration_test/writing_test.dart`)
- [x] `autocomplete_requires_explicit_action` — no insertion without a keypress
      (`app/test/editor/autocomplete_test.dart`, "a completion never inserts
      without an explicit acceptance key", with the Tab/Enter rule of ADR 0017 in
      the tests beside it; against the real core in
      `app/integration_test/writing_test.dart`, "an existing cue is suggested but
      never applied")
- [ ] `spellcheck_never_modifies` — no automatic correction (Phase 9; `spell` is a
      placeholder)
- [ ] `appearance_prefs_dont_affect_pagination` — zoom/theme leave golden layout
      identical (Phase 10; nothing edits preferences yet)
- [x] `roundtrip_is_byte_exact` — unedited files resave identically
      (`crates/fountain/tests/roundtrip_is_byte_exact.rs` over every corpus file
      and the 120-page reference, plus the `roundtrip` fuzz target)
- [ ] `pdf_output_is_deterministic` — same input, same bytes (Phase 7;
      `render_pdf` is a placeholder. The pagination underneath it *is* pinned:
      `crates/layout/tests/golden.rs` and its determinism test)
- [x] `parser_never_panics` — fuzz-backed
      (`crates/fountain/tests/parser_never_panics.rs`, plus the `parse` fuzz
      target, which CI runs on every commit)
- [ ] `no_network_syscalls` — release build runs under `unshare -rn`. Not written.
      §1.2 calls this a build-time assertion and there is no such assertion in
      `.github/workflows/ci.yml`; it belongs with Phase 11 packaging. Until it
      exists, "zero network requests" rests on `docs/DEPENDENCIES.md` review and
      ADR 0015, not on a test.

### CI gates

A pull request cannot merge unless: all tests pass, `clippy -D warnings` is clean, the
release build succeeds, and every performance budget in §1.3 is met on the reference script.

What `.github/workflows/ci.yml` actually runs, as of the remediation:

| Job | Steps |
| --- | --- |
| `rust` | `cargo fmt --check`, `clippy -D warnings`, `cargo test --workspace` — with a 4 MB tmpfs mounted and named in `SLUGLINE_FULL_DISK_DIR`, so the full-disk test is the real thing — `tools/check_layering.py`, `tools/make_reference.py --check` |
| `fuzz` | `parse` and `roundtrip`, 200k iterations each, as a smoke run rather than the 1M-iteration gate |
| `flutter` | `flutter analyze`, `flutter test`, the release build, the bundled-`.so` and 60 MB bundle assertions, then **all six** integration tests under `xvfb-run`: `bridge_test`, `editor_test`, `writing_test`, `ime_test`, `persistence_test`, `keystroke_benchmark_test` |

Three of those six integration tests did not run in CI until remediation Phase 3, and
`SLUGLINE_FULL_DISK_DIR` was never set — the audit's F7 and test-gap #4. Both are closed.
CI still triggers on `main` and on pull requests only, so work on a long-lived branch is
not gated until it is proposed.

---

## 14. Risk Register

| # | Risk | Severity | Mitigation |
| --- | --- | --- | --- |
| 1 | **The Flutter text editor.** Multi-block editing with correct IME, selection, and accessibility is a genuinely hard problem, and Flutter's built-in widgets do not solve it. | Critical | Phase 0 spike with a hard timebox. Be willing to adopt `super_editor`. Treat "write my own text editor" as a project-ending choice unless the spike says otherwise. |
| 2 | Lossless Fountain round-tripping | High | Provenance tracking (§3.2) + byte-exact corpus tests in Phase 1, before any UI exists. |
| 3 | PDF fidelity vs. professional expectations | High | Fixed monospace grid removes font-metric variability; calibrate against reference output (§5.5); golden hashes. |
| 4 | UTF-8/UTF-16 offset bugs | High | One conversion module, one naming convention, non-ASCII tests from Phase 0. |
| 5 | Pagination performance at p99 | Medium | Per-block layout cache + checkpointing; pagination is always off the UI thread. |
| 6 | Scope creep from the non-goals list | Medium | §1.4 is a build rule, not a preference. Reject "just a small hook for later". |
| 7 | Data loss on crash or interrupted save | Critical | Atomic rename + fsync + journal; automated kill-testing in CI (Phase 4). |
| 8 | FRB codegen churn between versions | Low | Pin the FRB version exactly; regenerate deliberately, never automatically. |
| 9 | AI agents making cross-cutting changes that break layering | Medium | One phase per agent; CI enforces crate layering; golden files fail loudly. |

---

## 15. Working With AI Agents on This Project

Since you plan to use agents, a few rules that make the difference between agents helping and
agents producing a codebase you cannot reason about:

1. **One phase per task, one crate per task where possible.** The layering in §2.5 exists
   partly so an agent can be given `crates/fountain` with no context about Flutter at all.
2. **Give the tests first.** Every phase above lists its tests. Hand the agent the failing
   test and the spec section, not a prose description.
3. **Golden files are your safety net.** They catch the specific failure mode agents are
   worst at: plausible-looking changes that quietly alter behaviour. Commit them early and
   never let an agent regenerate one without you reading the diff.
4. **Forbid new dependencies without approval.** Agents add crates freely. `DEPENDENCIES.md`
   with a required justification line is a cheap gate.
5. **Forbid edits to `app/lib/src/rust/`.** It is generated. If it is wrong, the Rust
   signature is wrong.
6. **Require an ADR for any deviation.** If an agent solves a problem differently from this
   spec, it writes a paragraph in `docs/DECISIONS.md` explaining why. Then you update this
   document — a spec that drifts from the code is worse than no spec.

---

## 16. Open Decisions

Resolve these and record them in `docs/DECISIONS.md`.

- [x] **Editor implementation approach** (Phase 0 spike) — one custom editing
      surface (ADR 0005)
- [x] Exact keyboard shortcut map — `docs/KEYMAP.md` (Phase 3, ADR 0011)
- [x] Application name, binary name, and reverse-DNS app ID — **Slugline**, `slugline`,
      `com.phagmaier.slugline` (ADR 0006)
- [ ] Licence for the project itself
- [x] Whether the editor view shows any page indication at all, or is purely fluid —
      **purely fluid through 1.0**; page awareness lives only in the Phase 7 preview and
      the PDF (ADR 0018)
- [x] Whether emphasis markup (`*italic*`) is displayed literally in the editor or rendered
      with the markers hidden — **literally**, markers counting as columns in both the
      editor and the paginator (ADR 0019)
- [ ] Scene number gutter style (left, right, or both). `layout` implements all three and
      defaults to none; which the application offers is Phase 7's to settle, with §5.5.
- [x] Where pinned autocomplete entities are stored — **the library index**, keyed by
      script id, never written into the `.fountain` file (ADR 0021)

---

## 17. Suggested Order of Attack

If you want a shorter path to something you can actually write in:

**Phases 0 → 1 → 2 → 4** gets you a real, safe editor you can draft in daily. Everything
after that is quality of life and output.

The temptation will be to do Phase 7 (PDF) early because it is the most visible result.
Resist it. A beautiful PDF exporter attached to an editor that eats your work is worthless;
the reverse is merely inconvenient.
