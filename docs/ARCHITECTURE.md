# Architecture map

A one-page index for agents and humans: which crate owns what, what may
depend on what, and how a keystroke becomes a file, a page and a PDF. For
rationale read the ADR each row names; the index at the top of
[DECISIONS.md](DECISIONS.md) says which files each record governs. For rules
and verification commands read [AGENTS.md](../AGENTS.md).

## Layers

Allowed intra-workspace edges are enforced by
[check_layering.py](../tools/check_layering.py) (ADR 0004). Update its tables
together with `Cargo.toml` when adding a crate or an edge.

| Crate | Owns | May depend on |
| --- | --- | --- |
| [fountain](../crates/fountain/) | Syntax: `BlockKind`, `TitlePage`, `Element`, parse, serialise, `infer_kind` | Nothing (ADR 0008) |
| [document](../crates/document/) | Identity and history: `BlockId`, `Block`, `Document`, `EditCommand`, undo, find/replace, Enter/Tab tables | `fountain` (ADR 0008, ADR 0011) |
| [layout](../crates/layout/) | Pagination engine; incremental repagination by checkpoint | `document`, `fountain` (ADR 0022, ADR 0049) |
| [render_pdf](../crates/render_pdf/) | PDF bytes: subsetter, sfnt writer, object writer, SHA-256 | `layout`, `fountain` (ADR 0032) |
| [storage](../crates/storage/) | Atomic save, crash journal, backups, preferences, library index | `document` (ADR 0013) |
| [spell](../crates/spell/) | Pure Hunspell-compatible checker over immutable snapshots | Nothing (ADR 0036) |
| [bridge](../crates/bridge/) | Actor thread and the API surface under `src/api/`; generated Dart is `app/lib/src/rust/` | All (ADR 0009) |
| [app](../app/) | Editor, keyboard workflow, preview, export, navigator, library | The bridge only; Dart never re-derives screenplay semantics (ADR 0018) |

## Data flow

- **Keystroke:** Dart sends an `EditCommand` with UTF-16 offsets; only
  `crates/bridge/src/offsets.rs` converts them. The edit goes through
  `outcome` or `inferring` in `crates/bridge/src/api/doc.rs`, which appends
  the resulting `Patch` to the crash journal and returns it. Dart applies the
  patch in place and never refetches the document (ADR 0009, ADR 0013).
- **Save:** the actor hands bytes and path to a worker; the file is replaced
  atomically after comparing against what the session last knew was on disk.
  Every successful save paginates the exact saved snapshot and caches its
  page count in the library (ADR 0020, ADR 0038).
- **Pagination:** `doc_paginate` runs the engine as an async snapshot job.
  Preview and PDF share the paginated snapshot and resolved emphasis runs;
  the renderer makes no layout decisions (ADR 0045, ADR 0049).
- **Export:** an export copies text elsewhere and moves nothing; Save As
  rebinds the session. Both refuse `AlreadyExists` and `ScriptIsOpen`
  (ADR 0029).

## Working here

- The planned fixes live in [BACKLOG.md](BACKLOG.md), in priority order. Find
  the next workable item with `python3 tools/backlog.py next` (first unticked,
  non-blocked). One item per change; reproduce before changing.
- Environment pre-flight: `./tools/doctor.sh`. Scoped checks:
  `./tools/agent.sh quick <crate>`, `./tools/agent.sh docs`,
  `./tools/agent.sh lint`. See the Verification section of AGENTS.md for the
  full list and the budgets in [BUDGETS.md](BUDGETS.md).
- Bridge offsets are UTF-16 code units named `*_utf16`; offsets inside
  `document` are UTF-8 bytes. Never round or clamp an invalid boundary.
- There is no timer anywhere in the core; the autosave clock is Dart's.
- `docs/archive/SPEC.md` and `docs/archive/REVIEW.md` are provenance, not instructions.
