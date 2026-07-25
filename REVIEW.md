# Slugline — Mid-Project Technical Audit

**Date:** 2026-07-25 · **Reviewed at:** commit `16b6cff` ("phase 6"), branch `dev`

**Scope reviewed:** all of `crates/` (fountain, document, layout, storage, bridge in
full; render_pdf and spell are one-constant placeholders), all of `app/lib/` except a
light skim of the smaller library dialogs, the test suites on both sides, SPEC.md, all
15 ADRs, AGENTS.md, DEPENDENCIES.md, KEYMAP.md, and CI.

**Verification commands run:** `cargo fmt --check`, `cargo clippy --workspace
--all-targets -- -D warnings`, `cargo test --workspace` (332 tests + 2 doctests, all
pass), `tools/check_layering.py` (pass), `flutter analyze` (clean), `flutter test`
(pass). Integration tests requiring the `.so` were not run in this session; three of
them run in CI.

---

## 1. Executive assessment

**Verdict: safe to continue after targeted repairs.** No architectural correction is
needed, and nothing warrants reimplementation.

This is one of the healthiest AI-assisted codebases I have audited. It does not
exhibit the classic failure mode of plausible-but-hollow generated code: the Rust core
is genuinely strong — total parsers, a provenance-tiling invariant that makes
byte-exact round-tripping a *consequence* rather than a maintained feature, an
inverse-carrying undo model that restores provenance, an atomic save implemented
exactly to spec, and property/fuzz/golden tests that test the real invariants rather
than implementation details. The ADR discipline is real and the decisions in it are
defensible.

But the audit found four things that matter before Phase 7, and two of them are
exactly the kind of defect this project defines as its worst case:

1. **The editor cannot correctly render multi-line blocks** (`\n` inside
   Action/Dialogue text, which the parser produces for every multi-line paragraph in
   every real file). The Dart line-wrapper, caret math, and painter all treat `\n` as
   an ordinary character. Opening the project's own 120-page reference script
   misrenders every multi-line paragraph. No test covers this. (F1)
2. **A crash shortly after accepting crash recovery loses everything the recovery
   restored.** The old journal is deleted before the recovered state reaches any
   disk, and the replacement journal is created against a base that does not match
   the file — so it can never be replayed. By the project's own standard ("losing
   user text is a P0 bug, always"), this is the most serious finding. (F2)
3. **Phase 6 is complete as a library and absent as a feature.** The pagination
   engine is excellent in isolation, but the bridge does not even depend on it.
   Meanwhile the Dart editor still runs its own "on loan" line-breaking, which
   disagrees with the Rust engine in at least four observable ways. This is precisely
   the two-sources-of-truth drift that ADR 0005 and §2.1 exist to prevent, and it
   will surface as editor-vs-preview mismatch the day Phase 7 starts. (F3)
4. **The project's documentation of its own state has drifted** — README says
   Phase 1, AGENTS.md says Phase 4, git says Phase 6; AGENTS.md claims CI runs six
   integration tests when it runs three; §13's invariant checklist is stale; Phases 5
   and 6 produced no ADRs despite §15 rule 6. The spec itself says "a spec that
   drifts from the code is worse than no spec." (F7)

Fix F1, F2, and the CI/doc drift now; resolve the F3 integration strategy before
writing a line of Phase 7; the rest can ride along.

---

## 2. Architecture map

The intended architecture and the real one are the same, with one exception noted
below. This is rare and worth saying.

```
Dart UI isolate                      Rust (libslugline_bridge.so)
┌──────────────────────────┐         ┌─────────────────────────────────────┐
│ app.dart (startup,       │  FRB    │ bridge/api/{doc,files,events}       │
│  recovery, session,      │◄───────►│   UTF-16↔UTF-8 via offsets.rs only  │
│  one open script)        │ sync +  │        │ closures                    │
│ editor_page (panels,     │ async   │        ▼                            │
│  autosave suppressions)  │         │ actor.rs — ONE thread owns AppState │
│ editor_surface           │◄────────│ state.rs — Session{Document,        │
│  (TextInputClient, paint,│ events  │   EntityIndex, Journal, path}       │
│   keys, mouse, semantics)│ Stream  │        │                            │
│ editor_controller        │         │        ▼                            │
│  (caret, selection,      │         │ document (blocks, EditCommand,      │
│   patch application,     │         │   History, reinfer, workflow,       │
│   Dart line layout ◄─────┼─DUPE────┼─► layout (UNWIRED: engine,          │
│   line_layout+metrics)   │         │     line_break, metrics))           │
│ library/* (chooser,      │         │ fountain (parse/serialise/infer,    │
│  dialogs, recovery UI)   │         │   provenance tiling)                │
└──────────────────────────┘         │ storage (atomic, journal, backup,   │
                                     │   library index, watch, prefs)      │
                                     │ render_pdf, spell: placeholders     │
                                     └─────────────────────────────────────┘
```

Data flow on a keystroke: `TextInputClient.updateEditingValue` → diff →
`EditorController` → sync FRB call → actor closure → `Session.editing()` (coalescing
clock) → `Document::apply` → `reinfer` → journal append → entity-index refresh →
`EditResult` patch back → controller applies patch in place (never refetches) →
painter repaints from a `Listenable`. This chain is faithful to ADR 0009/0011/0013
and is covered end-to-end by tests.

The one divergence from the intended architecture: **screenplay geometry currently
lives in Dart** (`editor/metrics.dart` + `line_layout.dart`), acknowledged as "on
loan", while the Rust `layout` crate — nominally the Phase 6 replacement — is
complete but consumed by nothing (not even a `Cargo.toml` edge from `bridge`).

---

## 3. Specification coverage

| Requirement (spec §) | Status | Where | Notes |
|---|---|---|---|
| Fountain parse/serialise, lossless round-trip (§3–4, Ph 1) | **Implemented and credible** | `crates/fountain` | Tiling invariant (ADR 0007), proptest, fuzz, byte-exact corpus. The strongest subsystem. |
| Document model, EditCommand, undo (§3, Ph 1) | **Implemented and credible** | `crates/document` | Inverse-splice undo restores provenance; group transactions; validated commands. |
| Bridge actor, UTF-16 offsets, patches (§2.3–2.4, §6, Ph 2) | **Implemented and credible** | `crates/bridge` | Offsets fallible per ADR 0001, tested against astral-plane text. |
| Minimum viable editor (Ph 2) | **Implemented but needs verification** | `app/lib/editor` | Typing/selection/clipboard solid, **but multi-line blocks misrender (F1)** — a core Phase 2 behaviour ("open a parsed script and edit it") is broken for real files. |
| Editing semantics, keyboard workflow (Ph 3) | **Implemented and credible** | `workflow.rs`, `doc.rs::enter/tab`, KEYMAP.md | Table proven in Rust; wiring proven in widget tests; the division is documented and honest. |
| IME (Ph 2/3 gate) | **Implemented but needs verification** | `editor_surface.dart`, `ime_test.dart` | Honestly documented as unverified against real `ibus`; the manual gate in ADR 0005 has not been run. |
| Accessibility (Ph 3, ADR 0012) | **Implemented but needs verification** | `surface_semantics.dart` | Tested at the `SemanticsData` level; never against Orca (documented). |
| Atomic save, distinct failure UX (Ph 4) | **Implemented and credible** | `storage/atomic.rs`, `save_dialogs.dart` | Exact 5-step sequence, read-only refusal, good tests. |
| Journal + crash recovery (Ph 4) | **Partially implemented** | `journal.rs`, `files.rs::recovery_*` | Journal/replay excellent; **the accept-recovery path has a data-loss window (F2)**, and its own "second crash during recovery loses nothing" comment is false. |
| Backups + restore (Ph 4) | Implemented and credible | `backup.rs`, `backups_dialog.dart` | Restore-backs-up-first implemented as specced. |
| External modification (Ph 4) | **Implemented but needs verification** | `watch.rs`, `editor_page.dart` | Correct in the steady state; **no suppression of the app's own save events → spurious prompt race (F4)**. |
| Library, session restore (Ph 4) | **Partially implemented** | `library.rs`, `app.dart` | Scroll row is *persisted* and round-trip-tested, but **never applied on reopen** (F6) — the checked spec item overstates. Page count permanently 0 (layout unwired). |
| Full-disk test with real tmpfs (Ph 4) | **Partially implemented** | CI | Spec says "Give CI a tmpfs to make this the real thing" — CI does not set `SLUGLINE_FULL_DISK_DIR`, so only the classification fallback runs. |
| Entity index + autocomplete (§7, Ph 5) | **Implemented and credible** | `entities.rs`, bridge, `_CompletionPopup` | Incremental, explicit-acceptance-only (tested), pins persisted in library index. No ADR recorded for the §16 pinned-entities decision it silently made. |
| Pagination engine (§5, Ph 6) | **Implemented but needs verification** | `crates/layout` | Deterministic, golden-tested, break rules each tested, capped fixed point, A4 derived. **But unintegrated (F3)**: no bridge edge, no app consumer, no debug dump *view*, incremental path exercised only by its own tests. |
| PDF export, preview, title page (Ph 7) | Missing | placeholders | As planned. |
| Navigator (Ph 8), spell (Ph 9), prefs UI (Ph 10), packaging (Ph 11) | Missing | — | As planned. `prefs_get/set` wired; nothing edits them (documented). |
| §13 named invariant tests | **Partially implemented** | various | `element_change_preserves_text` ✔; `roundtrip_is_byte_exact`, `parser_never_panics` exist but the checklist is unticked (stale); `never_loses_unsaved_changes` exists in spirit across several tests; others belong to later phases. |

---

## 4. Findings

Ranked by the order I'd worry about them.

---

### F1 — The editor cannot render or address multi-line blocks

- **Severity:** High · **Confidence:** High · **Category:** correctness (editor)
- **Where:** `app/lib/editor/line_layout.dart` (`wrapText`, `DocumentLayout`),
  `editor_surface.dart` (`_SurfacePainter.paint`, caret/selection math)
- **What:** The parser deliberately merges adjacent lines into one block: dialogue
  `"One.\nTwo."` and every multi-line action paragraph carry `\n` inside
  `Block::text` (`parse.rs::append`, and `validate_block_state` explicitly permits
  `\n` in multiline kinds). `wrapText` has no `\n` handling — it counts the newline
  as one column and wraps purely by width. The painter then hands `TextPainter` a
  string containing `\n`, which lays out as *two* text lines painted inside one grid
  row, overlapping the row below; caret/column arithmetic, click mapping, and
  selection rects are correspondingly wrong for every offset past the `\n`.
- **Evidence:** `wrapText` (line_layout.dart:32–55) never inspects `\n`; contrast
  `crates/layout/src/line_break.rs:10–13`, which splits on hard newlines first.
  `testdata/reference-feature.fountain` contains multi-line dialogue ("NADIA
  (CONT'D)\nWe agreed…\nYou never mention…") — so the project's own reference file
  triggers it. `line_layout_test.dart` has zero `\n` cases; the keystroke benchmark
  opens the reference script but asserts timing, not geometry; every
  widget/integration editor test types content that is single-line per block (Enter
  always splits, so *editor-authored* content never exposes it).
- **Symptoms:** open any normal Fountain file → overlapping text in every multi-line
  paragraph, caret in the wrong place, clicks landing at wrong offsets. A paste of
  Fountain containing a multi-line paragraph hits it too (`parse_blocks` produces
  one block).
- **Fix direction:** `wrapText` should split on `\n` first (mirroring Rust
  `break_lines`) and `DocumentLayout` should map offsets across the hard breaks;
  alternatively, resolve F3 by making the Rust layout the source of visual lines.
  Either way, add `\n` cases to `line_layout_test.dart`.
- **When:** **Now.** It's user-visible today and every Phase 7+ feature builds on
  this geometry.

---

### F2 — Accepting crash recovery destroys the only durable copy of the recovered edits

- **Severity:** High · **Confidence:** High · **Category:** data safety
- **Where:** `crates/bridge/src/api/files.rs::recovery_accept` (~line 840–894),
  `app/lib/editor/autosave.dart::_onChanged`
- **What:** The sequence is: replay the journal into memory →
  `journal::discard_at(old)` → `restart_journal(base = serialise(recovered
  document))`. At this moment the *file on disk still holds pre-crash bytes*, the
  recovered edits exist only in memory, and the new journal's `base` checksum
  matches neither the file nor anything on disk. Two consequences: (a) a second
  crash before the first save loses every recovered edit — with zero records the
  journal is silently discarded at next startup (`recovery_pending`, "not worth a
  dialog"); (b) if the user typed *after* recovering and then crashed,
  `journal::verify` fails (`base` ≠ file checksum) and the offer comes back
  `blocked` — recovered edits *and* new typing both unrecoverable. The doc comment
  "so that a second crash during recovery loses nothing either" claims the opposite
  of what the code does.
- **Aggravator:** `AutosaveDriver._onChanged` only arms on controller change events.
  A recovered document arrives dirty but no edit event fires, so **no autosave
  happens until the user types**. The window is not "2 seconds" — it is "until the
  user edits or manually saves", which can be minutes of reading the recovered text.
- **Evidence:** `recovery_accept` at files.rs:886 (`discard_at`) then :889
  (`restart_journal` with in-memory serialisation); `journal::verify` at
  journal.rs:475–488 reads the *file* and compares checksums; `recovery_pending`
  discards empty journals at files.rs:804–809; `autosave.dart:107–120` arms only
  from the `changes` listener.
- **Fix direction:** keep the old journal until the recovered state has reached
  disk. Cleanest: after replay, either (a) require/perform an immediate save (or
  save-as for untitled) before discarding, checkpointing the new journal against the
  written bytes; or (b) write the recovered patches into the new journal against the
  file's true base before discarding the old one. Also arm the autosave driver
  whenever a document is adopted dirty.
- **When:** **Now** — this sits inside the subsystem whose exit criterion is "never
  lost a keystroke beyond the last one," and the kill test cannot see it because it
  never crashes *twice*.

---

### F3 — Phase 6 is unintegrated, and the Dart editor still runs a divergent second layout implementation

- **Severity:** High (as pre-Phase-7 integration debt) · **Confidence:** High ·
  **Category:** architecture / two sources of truth
- **Where:** `crates/bridge/Cargo.toml` (no `slugline_layout` edge),
  `app/lib/editor/line_layout.dart` + `metrics.dart` vs
  `crates/layout/{line_break,metrics,engine}.rs`
- **What:** The bridge exposes no `paginate`, the library `page_count` is
  permanently 0, there is no debug dump view in the app (the spec's one permitted
  Phase 6 UI artifact — `debug_dump()` exists only as a method used by Rust golden
  tests), and the incremental repagination machinery (checkpoints, cache,
  `repaginate`) has never run outside its own test suite. Meanwhile the Dart
  wrapper — which ADR 0005 says "must be replaced by the Rust layout crate's output
  rather than duplicated" — remains the thing the user actually sees, and it
  observably disagrees with `layout::break_lines`: **(1)** units — Dart counts
  UTF-16 code units, Rust counts `char`s (an emoji is 2 vs 1); **(2)** spaces at a
  wrap point — Dart consumes exactly one, Rust consumes the whole run; **(3)** a
  trailing space at the width boundary — Dart emits a phantom empty visual line
  (`wrapText("abc ", 3)` → 2 lines), Rust emits one; **(4)** tabs — Rust expands to
  4-column stops, Dart counts `\t` as one column; **(5)** hard newlines (F1). Also
  `layout::display_text` uppercases unconditionally (ß→SS) where the editor's
  `displayText` deliberately refuses length-changing uppercasing.
- **Why it matters:** Phase 7's core promise is "preview is rendered from the *same*
  `PaginatedScript` the PDF uses — never a second layout implementation." The
  second implementation already exists and is load-bearing. Every keystroke of
  Phase 7 work done before this is resolved deepens the divergence.
- **Fix direction:** decide the integration model *first* (see §8 and D-1): either
  the editor consumes Rust-computed visual lines (bridge call returning wrap points
  per block, cached), or the Dart wrapper is kept for the fluid editor view but is
  differentially tested against `break_lines` over the whole corpus so the drift is
  pinned to zero where they must agree. Wire `paginate` into the bridge as a
  background job per §5.4 and populate the library page count.
- **When:** **Before Phase 7 begins.** Not urgent for today's editing, existential
  for the preview/PDF phase.

---

### F4 — The app's own saves can trigger the "file changed on disk" prompt

- **Severity:** Medium · **Confidence:** Medium (race window reasoned, not
  reproduced) · **Category:** correctness / race
- **Where:** `storage/watch.rs` (no self-save correlation),
  `bridge/files.rs::write_document`, `editor_page.dart::handleExternalChange`
- **What:** The watcher deliberately watches the directory and reports
  save-by-rename — including *our own* atomic saves. Nothing on either side
  correlates a `FileChangedOnDisk` event with an in-flight own save. The masking
  relies on `doc_external_change` finding `dirty == false` or `differs == false`;
  but the 30-second *interval* autosave fires mid-typing by design, and any
  keystroke landing between the rename and Dart's handling of the event yields
  `dirty=true, differs=true` → the full "Something else has written to this file…
  Take theirs discards your unsaved changes" modal, mid-sentence, about the app's
  own save. "Take theirs" would then genuinely discard the keystrokes since that
  save plus the undo history.
- **Fix direction:** record the path+mtime (or a generation counter) of writes the
  app performed and swallow the first matching watcher event; or debounce/verify in
  `handleExternalChange` by comparing against the just-saved revision.
- **When:** before Phase 7 (it degrades trust in exactly the dialogs Phase 4 worked
  hardest on).

---

### F5 — Concurrent saves of one document can interleave

- **Severity:** Medium · **Confidence:** Medium · **Category:** async correctness
- **Where:** `bridge/files.rs::write_document`
- **What:** The save is deliberately three steps (plan on actor → write off actor →
  record on actor), which is right, but nothing serialises two overlapping saves of
  the same document. `AutosaveDriver._saving` guards only the driver's own calls; an
  explicit Ctrl+S (`saveWithDialogs → core.save()`) can run concurrently with an
  in-flight autosave (`withModal`'s suppression holds *future* autosaves, not one
  already past `_due`). If an edit lands between their plans, the writes can land in
  reverse order and the file transiently holds the older bytes while the newer save
  has already reported "Saved". `mark_saved_at(min)` makes it self-heal at the next
  autosave, and both journal checkpoints happen to stay consistent with whatever
  text won — but "the file briefly contains something older than what I was told
  was saved" is not a property this codebase tolerates anywhere else. A similar
  unguarded check-then-act exists in `library_open` (two concurrent opens of one
  path can both pass `handle_for`).
- **Fix direction:** a per-session "save in flight" flag (or queued saves) in
  `AppState`, checked in step one; reject/queue the second plan.
- **When:** before Phase 7; small fix, closes a whole class.

---

### F6 — Session scroll position is persisted but never restored

- **Severity:** Medium · **Confidence:** High · **Category:** incomplete feature
  marked done
- **Where:** `app/lib/app.dart::_openPath`, `editor_surface.dart`
- **What:** `doc_set_scroll` → library index round-trips (tested in
  `integration_test/persistence_test.dart:275`), and `ScriptView.scrollRow` comes
  back — and is then read by nothing in `app/lib` outside generated code.
  `EditorSurface` has no initial-scroll mechanism. The Phase 4 checkbox "Session
  restore: reopen the scripts that were open last time, **with scroll positions**"
  is ticked but only half true: the persistence half exists, the restore half
  doesn't.
- **Fix direction:** pass the restored row into `EditorSurface` and
  `jumpTo(row * lineHeight)` after first layout; widget-test it.
- **When:** stabilization batch; cheap.

---

### F7 — Status documentation, CI coverage, and decision log have drifted from the code

- **Severity:** Medium · **Confidence:** High · **Category:** process / spec drift
- **What:**
  - `README.md`: "Status: Phase 1 complete… There is still no editor." Five phases
    stale.
  - `AGENTS.md`: "Phases 0–4 are complete… `layout`/`render_pdf`/`spell` are
    intentional placeholders" — layout is no longer a placeholder; Phases 5–6 are
    committed. Also claims "CI runs them [six integration tests] after the release
    build" — **`ci.yml` runs only `bridge_test`, `editor_test`, and
    `keystroke_benchmark_test`**; `writing_test`, `ime_test`, and
    `persistence_test` — the strongest Dart-side proofs of Phases 3 and 4 — do not
    gate anything.
  - SPEC §13's named-invariant checklist is stale (files exist for
    `roundtrip_is_byte_exact` and `parser_never_panics`, boxes unticked).
  - **No ADRs for Phases 5 or 6** despite §15 rule 6 and real decisions taken
    (pinned-entity storage — resolving §16's open item silently; the layout crate's
    checkpoint/fingerprint design; the decision *not* to wire layout into the bridge
    yet). §16 also still shows "editor page indication" and "emphasis display"
    undecided — the editor has de facto decided both (fluid, literal markers)
    without recording it.
  - Minor: `crates/document/src/document.rs:219–221` comment says "Re-anchoring
    provenance… belongs to `storage`, in Phase 4" — Phase 4 shipped and did not do
    it (saved documents keep serialising from the original source; correct, but the
    comment now points at a phase that has passed).
- **Why it matters:** this project's agent workflow (§15) leans on the docs being
  the ground truth handed to each agent. The spec's own words: "a spec that drifts
  from the code is worse than no spec."
- **When:** **Now** — it's an hour of editing and it de-risks every future agent
  task. Add the three missing integration tests to CI (xvfb is already set up) and
  give CI the tmpfs (`SLUGLINE_FULL_DISK_DIR`) the Phase 4 test explicitly asks for
  in bold.

---

### F8 — `doc_external_change` does disk I/O and a full-document serialise on the actor thread, synchronously

- **Severity:** Low–Medium · **Confidence:** High · **Category:** threading
  discipline
- **What:** `files.rs:618–629`: a `#[frb(sync)]` function whose actor closure calls
  `fs::read_to_string` and `document.serialise()` (half a megabyte for a feature).
  This violates the file's own header rule ("the actor is never blocked on a disk")
  and §2.3's "anything over 2 ms must be async". It runs on every watcher event,
  including the echo of every save (see F4). A cold-cache read on spinning rust or a
  network-adjacent FS stalls every keystroke behind it.
- **Fix direction:** make it async and split it like `write_document`: snapshot
  text+dirty on the actor, read and compare off it.
- **When:** with F4, same code path.

---

### F9 — `doc_export_fountain` semantics conflated with Save As

- **Severity:** Low · **Confidence:** High · **Category:** spec mismatch
- **What:** `doc_save_as` documents itself as also being §6's
  `doc_export_fountain`, but it *rebinds* the session (path, journal, library entry
  follow). An "export a copy while continuing to edit the original" operation
  therefore doesn't exist. Fine today (no UI offers export); will bite in Phase 7
  when "export" becomes a real verb.
- **When:** before Phase 7's export dialog.

---

### F10 — Uppercasing rules differ between editor display and layout engine

- **Severity:** Low · **Confidence:** High · **Category:** future divergence
- **What:** `metrics.dart::displayText` refuses length-changing uppercase (ß) to
  keep caret columns honest; `layout/engine.rs::display_text` uppercases
  unconditionally. When preview lands, a scene heading containing ß will read
  differently in editor vs page. Also relevant to F3's differential test.

---

### F11 — `normalize_character` byte-slices using lengths derived from an uppercased copy

- **Severity:** Low · **Confidence:** Medium · **Category:** robustness
- **What:** `entities.rs:300–312`: `trimmed.to_uppercase().ends_with(extension)`
  then `trimmed[..trimmed.len() - extension.len()]`. Safe for ASCII extensions in
  practice, but the check and the slice are done on different strings; it is also
  `to_uppercase()` per loop iteration. A char-boundary panic here would take down
  the actor thread. Cheap to harden with a case-insensitive suffix check on
  `trimmed` itself.

---

### F12 — Miscellaneous, Informational

- `_OpenScript.dispose()` (app.dart:255–261) closes the core twice —
  `controller.dispose()` already calls `core.close()`. Idempotent today; a trap if
  close gains side effects.
- `EditorController._indexOf` silently maps an unknown block id to index 0
  (editor_controller.dart:95) — a stale-id bug elsewhere would manifest as edits
  landing on block 0 rather than an assertion.
- `entities.rs::replace` does unchecked `frequency -= 1` — an index-desync bug
  would panic the actor rather than degrade; out of character for a codebase that
  is otherwise total on internal state.
- Word-motion classifies per UTF-16 code unit (`String.fromCharCode` on a surrogate
  half never matches `\p{L}`), so astral-plane letters break word-jump granularity.
  Grapheme boundaries protect the caret, so no corruption — cosmetic.
- Phase 0's handshake surface (`handshake.rs`, `proofEvents`, `spike/`) still ships
  in the production `.so`/app. Intentional per ADRs; note it's on the Phase 11
  cleanup list implicitly, not explicitly.

---

## 5. Hidden-risk review

**Verified (ran, or covered by tests I read and executed):** Rust parser/serialiser
round-tripping, undo/redo inverses, provenance tiling, journal fuzz/truncation
behaviour, atomic save semantics, kill test (really spawns and SIGKILLs a child),
entity index incrementality and ranking, layout break rules and golden determinism,
clippy/fmt/layering cleanliness.

**Inferred from code, not demonstrated:** patch application in Dart against the
*real* core under structural churn (covered by integration tests that CI doesn't
run — F7); autosave suppression interactions (widget-tested with fakes, plausible);
backup retention behaviour under a year of real saves.

**Unverified, known and honestly documented:** real `ibus`+CJK input (ADR 0005's
manual gate — still the project's single largest open risk, and Phase 3 closed
without it; the fallback to `super_editor` gets more expensive every phase); Orca
screen-reader experience; §5.5 print calibration (Phase 7); the full-disk test as a
real ENOSPC (CI lacks the tmpfs).

**Cannot currently work as specified:** multi-line block rendering (F1);
crash-during-recovery safety (F2); scroll restore (F6); anything in the app that
would need pagination (page counts — displayed as nothing, correctly, per the
Phase 4 note).

---

## 6. Test-gap analysis (priority order)

1. **Dart layout with embedded newlines** — `wrapText`/`DocumentLayout`/caret math
   over blocks containing `\n` (unit + widget). Catches F1 and guards the fix.
   **Add before continuing.**
2. **Second-crash-after-recovery** — extend `crates/bridge/tests/persistence.rs`:
   type, kill, accept recovery, kill again before any save; assert the recovered
   edits are still offered. Catches F2 and documents the intended contract. **Add
   with the F2 fix.**
3. **Differential wrap test** — for every corpus file and every block, assert Dart
   `wrapText` and Rust `break_lines` produce identical wrap points (run in an
   integration test where both are available; or export Rust's wraps as a fixture).
   Pins F3's drift to zero and is the safety net for whichever integration strategy
   is chosen. **Add before Phase 7.**
4. **CI gaps** — run `writing_test`, `ime_test`, `persistence_test` in CI (harness
   already exists); set `SLUGLINE_FULL_DISK_DIR` on a small tmpfs. Not new tests —
   new *enforcement*. **Now; near-zero cost.**
5. **Own-save watcher echo** — integration: save, immediately edit, deliver the
   watcher event, assert no external-change prompt. Catches F4.
6. **Concurrent save serialisation** — two overlapping `write_document` calls with
   an edit between the plans; assert the file ends at the newer revision. Catches
   F5.
7. **Scroll restore applied** — widget test that a restored `scrollRow` actually
   positions the viewport. Catches F6.
8. **Journal-broken UX path** — nothing exercises `JournalBroken` end-to-end
   (event → snackbar → status). Low priority.

---

## 7. Technical-debt register

| Item | Classification |
|---|---|
| F2 recovery data-loss window | **Must repair now** |
| F1 multi-line block rendering | **Must repair now** |
| F7 doc/CI/ADR drift (incl. CI test gaps, tmpfs) | **Must repair now** (cheap, compounding) |
| F3 layout unintegrated / duplicate Dart geometry | **Repair before Phase 7 expands** (the related feature *is* Phase 7) |
| F4 own-save watcher echo | Repair before Phase 7 |
| F5 concurrent save guard | Repair before Phase 7 |
| F8 sync disk I/O on actor in `doc_external_change` | Repair before Phase 7 (same code as F4) |
| F6 scroll restore | Repair before the related feature expands (session UX) |
| F9 export-vs-save-as semantics | Repair before Phase 7's export dialog |
| F10 uppercase divergence, F11 normalize_character | Safe to defer (fold into F3 work) |
| F12 items (double close, `_indexOf` fallback, etc.) | Cosmetic only |
| Phase 0 handshake surface + `spike/` in tree | Safe to defer (Phase 11 cleanup; ADR says spike stays until the IME gate passes) |

---

## 8. Recommended remediation order

**Immediate blockers (before any new feature work):**

1. **F2** — reorder recovery so the old journal survives until the recovered state
   is durably on disk; arm autosave for dirty-on-adopt documents. Add test-gap #2.
2. **F1** — teach the Dart layout hard newlines (mirror `break_lines`' split-first
   structure). Add test-gap #1. (Doing F1 first also makes the F3 decision
   better-informed, since it touches the exact seam.)
3. **F7** — update README/AGENTS/SPEC checklists, write the two missing ADRs
   (pinned entities; layout-integration status and intent), add the three missing
   integration tests + tmpfs to CI.

**Stabilization (short batch, order-independent):**

4. F5 per-session save guard → then F4 own-save suppression → F8 async
   `doc_external_change` (same files, do together).
5. F6 scroll restore.

**Architecture (the Phase 7 gate):**

6. **Execute the F3 integration model per decision D-1 below** (record it as an
   ADR): keep the Dart wrapper for the fluid editor view, make it provably
   identical to `layout::line_break` via the differential test, wire `paginate`
   through the bridge as an async snapshot job now, surface page count in the
   library and a debug dump behind a flag — so Phase 7 starts by consuming an
   already-integrated engine instead of integrating one under feature pressure.
7. Split `doc_export_fountain` from `doc_save_as` (F9).

**Test additions:** gaps #5–7 land with their fixes above; #3 lands with step 6.

**Later cleanup:** F10/F11/F12, retire handshake/spike at Phase 11, revisit the file
chooser per ADR 0015.

**Also still owed from Phase 3, unchanged in priority:** the manual `ibus`+CJK
session. Every phase completed before running it raises the cost of the ADR 0005
fallback. Schedule it as a task, not a footnote.

---

## 9. What should not be rewritten

Preserve these; they are the project's assets, and none of the findings above
indict them:

- **`crates/fountain` in its entirety.** The tiling-provenance design (ADR 0007) is
  genuinely elegant, the tolerance decisions are argued and tested, and the
  canonical-form stability tests are exactly right.
- **`crates/document`** — the inverse-splice history (provenance-restoring undo),
  `apply_group` atomic transactions, `reinfer`'s scoping, and the workflow tables.
  The `Merged` patch-cancellation logic is subtle and correct.
- **`crates/storage/atomic.rs` and `journal.rs`** — textbook implementations with
  the right tests; the un-fsynced-append reasoning in ADR 0013 is sound.
- **The actor model and bridge conventions** — single-thread ownership,
  closures-in, patches-out, refusals-as-values, `offsets.rs` as the single
  conversion point. Fix the two threading findings *within* this model; do not
  replace it.
- **The Dart patch-application pipeline** (`EditorController._applyResult` +
  `DocumentLayout` incremental rewrap/reindex) — the never-refetch discipline is
  intact and asserted (`block_count` check).
- **The single-surface editor decision itself** (ADR 0005) — the measurements were
  real, the risk is documented, and nothing found here suggests reversing it. F1 is
  a bug in the surface, not an argument against it.
- **The test *style*** — behaviour-named tests asserting invariants
  ("`a_damaged_journal_never_yields_a_patch_that_was_not_written_whole`") rather
  than implementation details. Keep writing them this way.

---

## 10. Questions and uncertain assumptions

> Each question below has been **resolved by decision** — see §11. The questions are
> retained as the audit record of what was ambiguous at review time.

1. **Is the editor meant to remain "fluid" (unpaginated) for 1.0?** §16 lists it as
   open and recommends fluid; the code has de facto committed to fluid. The F3
   strategy depends on the answer. → **Resolved: D-1.**
2. **Emphasis rendering** (§16): the editor currently shows markers literally (the
   recommended option), but no decision is recorded and no code interprets
   `*italic*` yet — Phase 7's PDF must. → **Resolved: D-2.**
3. **What is `page_count` in the library supposed to update on** — every save, or a
   background pagination? The field exists on both sides but no writer was ever
   planned in code I can find. → **Resolved: D-3.**
4. **Was the interval autosave intended to run mid-typing?** ADR 0014 says yes ("a
   writer who never pauses… would never be saved"). That intent is what makes F4
   reachable; the fix should preserve it. → **Resolved: D-4.**
5. **Recovery of multiple crashed sessions** recovers only the first per launch
   (documented in a comment as deliberate). Acceptable UX, or should Phase 10 queue
   them? → **Resolved: D-5.**
6. **Not fully read during this audit:** `find.rs`, `backup.rs`, `library.rs`,
   `prefs.rs` internals, the back half of `layout/engine.rs` (the `Paginator`
   break-rule implementation), the smaller library dialogs, and `frb_generated.*`
   (generated, per §15 rule 5). All are covered by passing tests and nothing in
   their call sites raised flags, but findings there are limited to what their
   interfaces and tests show. → **Resolved: D-6.**
7. **Assumption to verify cheaply:** the app was not executed during this audit;
   F1's visual symptom is derived from `TextPainter` semantics rather than
   observed. → **Resolved: D-7.**

---

## 11. Decisions on the open questions

The calls below were delegated to the reviewer and are hereby made. Each should be
carried into `docs/DECISIONS.md` as a proper ADR (or a spec edit) by whoever picks
up the F7 documentation task — this section is the source of intent, not a
substitute for the ADR.

---

**D-1 · DECISION — The editor stays fluid (unpaginated) for 1.0, and the Dart
wrapper stays, pinned to the Rust engine by a differential test.**

The editor view remains a continuous, unpaginated surface through 1.0; page
awareness lives exclusively in the Phase 7 preview and the PDF, both rendered from
`PaginatedScript`. Consequently the F3 integration model is: **keep
`line_layout.dart` as the editor's wrap implementation** (it is on the keystroke
path and its cheapness is why the editor meets its budgets), but make its agreement
with `layout::break_lines` a *tested invariant*, not a hope — fix the five known
divergences (units, space-run consumption, trailing-space phantom line, tab
expansion, hard newlines) on the Dart side to match Rust, and add the corpus-wide
differential test (test-gap #3) so any future drift fails CI. Wire
`layout::paginate` through the bridge now as an async snapshot job (page count in
the library, debug dump behind a flag). *Rationale:* fetching wrap geometry from
Rust per keystroke would put a bridge round-trip and cache-invalidation protocol on
the hot path to solve a problem a test can pin down; and the spec itself
(§16) recommends fluid as faster and simpler. The differential test is the
mechanism that makes "two implementations" safe: they are two implementations of
one *tested* specification, not two opinions.

---

**D-2 · DECISION — Emphasis markup is displayed literally in the editor for 1.0.**

`*italic*`, `**bold**`, `***bold italic***`, and `_underline_` appear in the editor
exactly as typed, with no styling and no hidden markers. The PDF renderer
(Phase 7) interprets them; the editor never does. *Rationale:* the spec recommends
it ("literal is simpler and more honest to Fountain"), it keeps the editor's
column arithmetic trivially correct (a styled-with-hidden-markers editor would
reintroduce the display-length-vs-model-length divergence that `displayText`
carefully refuses), and it costs nothing to upgrade later. One consequence to
respect in Phase 6/7 work: emphasis markers **do** count as columns for line
breaking in both the editor and the paginator — which is what the layout engine
already does — so this decision also keeps D-1's differential test simple.

---

**D-3 · DECISION — `page_count` is updated on every successful save, computed from
the pagination snapshot as a background job.**

The write path: after `write_document` succeeds (explicit save *and* autosave), a
background pagination of the saved snapshot runs on a worker thread and its page
count is written into the library entry (best-effort, like the rest of the index —
it is a cache). It is *not* recomputed on every keystroke, and it is *not* computed
at library-scan time for unopened scripts (a scan that parses and paginates every
script in the library would violate the cold-start budget). An entry that has never
been saved by a layout-capable build keeps showing nothing, exactly as the Phase 4
note intended. *Rationale:* "pages as of the last save" is the honest meaning of a
page count in a file list, the save path already ends on the actor with the library
in hand, and per §2.3 pagination belongs on a worker against a snapshot — this is
also the natural first consumer that forces the F3 bridge wiring to exist.

---

**D-4 · DECISION — The interval autosave keeps firing mid-typing; F4 is fixed by
own-save suppression, not by weakening the timer.**

ADR 0014's two-timer design is correct and stands: the 30-second interval save is
the only thing protecting a writer who never pauses, and it must keep running
during continuous typing. The F4 fix is therefore on the watcher side: the core
records each path it has itself just written (path + a save generation counter,
recorded in step three of `write_document`) and swallows the first matching
`FileChangedOnDisk` for that generation. `doc_external_change` remains the backstop
for anything the suppression misses. Under no circumstances is the fix "don't save
while typing" or "make the external-change dialog less scary" — the dialog is right
for real external changes; it must simply never fire for our own.

---

**D-5 · DECISION — One recovery per launch stands for 1.0.**

The current behaviour — recover the first accepted offer, leave the remaining
journals on disk to be offered again next launch — is acceptable and ships as-is.
Multiple simultaneous crashed sessions require multiple scripts open at a crash,
and the app holds one open script at a time, so the multi-offer case is close to
unreachable today; the failure mode of the current design is a second dialog on the
*next* launch, which loses nothing. Revisit only if the app ever gains multi-window
or tabbed editing (not on the 1.0 roadmap, §1.4). The Phase 10 backlog item is
downgraded to "note in the ADR", not scheduled work.

---

**D-6 · DECISION — The unread modules are accepted on the strength of their test
suites; no follow-up deep-read is scheduled, with one exception.**

`find.rs`, `backup.rs`, `library.rs`, `prefs.rs`, the library dialogs, and the
generated bindings are accepted as reviewed-by-interface: their observable
behaviour is what their (passing, well-named) tests assert, and no call site raised
a flag. The **exception** is the back half of `layout/engine.rs` (the `Paginator`
break-rule implementation): it must get a focused review *as part of the Phase 7
kickoff*, because Phase 7 is where its output becomes user-visible and where §5.5
calibration will interrogate exactly those rules. That review rides along with
work already scheduled, so it costs no extra calendar.

---

**D-7 · DECISION — F1 is confirmed by inspection and scheduled without waiting for
a manual reproduction; the manual check happens as step zero of the fix.**

The static case is airtight (the wrapper demonstrably never inspects `\n`;
`TextPainter` demonstrably breaks on it; the reference fixture demonstrably
contains multi-line blocks), so the fix is scheduled now rather than gated on a
reproduction. The implementer's first action is still `flutter run -d linux`, open
`testdata/reference-feature.fountain`, and screenshot the misrender — thirty
seconds that turns the finding into a before/after record and confirms the blast
radius. If — against expectation — the render looks correct, stop and report back
before changing code, per the review standard that behaviour is never assumed from
compilation alone.

---

*End of review.*
