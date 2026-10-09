# Managed script library: implementation plan and agent brief

**Status:** all six implementation phases complete.
**Prepared:** 2026-10-09, against local commit `14d1b3f`.
**Scope:** replace editing arbitrary source files with a directory-backed,
managed library. Complete the phases below as one feature batch.

The owner agreed to a library directory, one folder per script, creation inside
the library, imports that leave their sources untouched, and exports that do not
move the working session. The remaining product choices in this brief are
implementation defaults. Use them without another approval round; resolve
routine details autonomously and record material deviations.

This document authorizes feature implementation when handed to an implementing
agent. Its preparation does not authorize committing, pushing, installing, or
publishing. Follow the implementation session's explicit Git boundary.

## Implementation result — 2026-10-09

The storage format, managed sessions, import/duplicate operations, explicit
legacy migration, user workflows and final documentation are implemented.
[ADR 0068](DECISIONS.md#adr-0068--editable-scripts-are-portable-managed-projects)
records the durable ownership and migration rules. Bridge bindings were
regenerated with the pinned toolchain; dependencies and lockfiles are unchanged.

Full Rust formatting, workspace Clippy and workspace tests passed. Full Flutter
formatting, analysis and all 848 widget tests passed. Selected native bridge
(4), persistence (26), export (18), editor (11) and input-method (9) tests passed
against isolated temporary roots. The writing suite passed 34 scenarios;
its two Go to page cases subsequently passed with an explicitly small viewport
that puts the target off screen, retaining the original scroll assertions.
Focused checks additionally passed for root-alias initialization and immutable
exports. Docs, link, layering and diff checks passed.

Native persistence covers exact read-only BOM/CRLF import, autosave/source
isolation, managed save/reopen, versions and version-copy bytes, cache loss,
rename, active unsaved duplication and archive/restore. Rust tests cover
metadata damage, exclusive publication, aliases, unavailable roots, legacy
history retries and predecessor/live-successor recovery ownership. Interrupted
staging remains visible for rescue; partial history migration remains usable and
reports a retryable status. Export conservatively refuses multiply linked files
as well as canonical managed destinations.

A real full-filesystem ENOSPC write was not exercised; error classification and
failure retention are covered. The retained writing diagnostic is
`/tmp/slugline-managed-go-page-diagnostic.log`. Release builds, packaging,
installation, hosted CI and real-desktop manual gates remain outside this batch.
The owner subsequently authorized committing and pushing this validated batch.

## 1. Outcome and scope

Slugline's normal editable documents live inside the selected library. An
external screenplay is input to an import, never the file subsequently saved
by the editor. A writer can export a snapshot at any time without changing the
library copy's identity or destination.

The library consists of ordinary directories and Fountain files. It must be
usable through the filesystem and recoverable without a central index. A
future feature can associate more files with a script without changing where
that script lives.

Implement the storage model, workflows, compatibility migration, relevant
documentation, and verification together. Do not stop after adding a folder
preference or changing button labels while legacy entry points still edit
external files.

### Explicit non-goals

- Git integration, branches, collaboration, cloud sync, or source synchronization.
- Notes, research, attachments, or a new project-settings interface.
- A database, opaque project archive, background polling, or new core timers.
- Multiple simultaneously active libraries or an in-app library relocation tool.
- Importing arbitrary directory trees or scanning the user's home for scripts.
- Permanent project deletion; provide reversible archive/restore instead.
- Release builds, packaging, installers, publishing, or hosted-CI watching.

Do not refactor unrelated editor, syntax, pagination, or rendering behavior.

## 2. Product contract

| Action | Required behavior |
| --- | --- |
| New / `Ctrl+N` | Create a complete new project in the active library and open it. No destination chooser. Use a default name such as Untitled; naming can be changed afterward. |
| Open / `Ctrl+O` | Choose an existing library script, with keyboard search and activation. A Browse/Import action may lead to external import, clearly labeled. |
| Import Fountain | Copy exact source bytes into a fresh library project, then open the library copy. Do not parse and reserialize merely to import. |
| Import FDX | Decode with the existing Rust converter, obtain approval for conversion warnings, then commit a native Fountain project. Preserve an exact copy of the imported FDX as reference material in that project. |
| Save / `Ctrl+S` | Save the current managed `script.fountain` using existing persistence guarantees. New and accepted imported scripts already have a destination. |
| Autosave | Save that same library file under the existing Dart timing and suppression rules. Honor the user's autosave preference. |
| Export a copy / `Ctrl+Shift+S` | Replace the user-facing Save As action with a Fountain copy export. Keep the current session, path, dirty flag, history, watcher, and journal unchanged. |
| Existing PDF/FDX export | Continue to export copies under their existing conversion and replacement rules. |
| Rename | Change the library display name. Do not relocate the project, regenerate its ID, or edit its screenplay title page. |
| Duplicate | Create a new project with a fresh identity from a captured script snapshot. Do not alias files or share version history. |
| Previous version: Open as copy | Create a new managed project from the selected version, rather than opening an externally saved working file. Preserve the original session until switching is confirmed. |
| Previous version: Restore | Preserve the existing explicit restore semantics and protections, targeting the current library script. |
| Archive / Restore archived | Persist an archive flag in project metadata. Hide archived projects from the normal list, provide an Archived view and Restore action, and retain their files/history. |
| Choose library folder | Switch to another validated library after safely resolving the current editor. Leave the old library's files in place. |
| Reveal library/project folder | Expose the actual location so users can inspect, copy, and back up their work. |

New, import, duplicate, restore-as-copy, and library switching must retain the
current document until their destination is ready and adoption is safe. Keep
the existing input/autosave holds and dirty-close confirmation. Canceling a
warning or close confirmation must not leave a published import or change the
current document.

### External file entry points

Apply one policy to Import, Browse, command-line paths, and desktop file
association launches:

1. A validated managed `script.fountain` in the active library opens its existing
   project, including when reached through a canonical alias.
2. A screenplay outside that library is imported as a new independent project.
3. A missing external path produces an error; opening a missing path must no
   longer create a new arbitrary file there.
4. A file from another library is an external import while this library is active.
   Selecting that other library through Preferences is a separate operation.
5. An archived managed project offers restoration before editing.

An import is a deliberate fork. Explain once in the import UI that Slugline
edits a library copy and leaves the selected source untouched. Record origin
information for identification, never as a save or watcher destination.

If an origin already has a managed copy, offer **Open existing copy** or
**Import another copy**. Never synchronize, merge, or replace automatically.
Identical names and identical content are allowed; neither proves identity.

Source preservation applies to import and subsequent library operations. A
writer may deliberately export over an existing external file, including an
import origin, only through the explicit destination and replacement-confirmation
flow. That does not establish a binding or enable later autosaves to that file.

## 3. Library location and project format

### Root selection

- Default to a `Slugline` folder in the user's platform Documents directory.
  If Documents cannot be determined, use a visible `Slugline` folder under the
  user's home. Use the existing directory-discovery dependency where practical.
- Store the selected root in preferences. Missing fields in older preferences
  select the default; a configured but unavailable root is an error, not a
  reason to silently select another root.
- Create a new default root lazily when the first project is created. Merely
  discovering paths must not create directories.
- Distinguish a deliberately selected new folder from a formerly available
  library that has disappeared. Do not silently recreate a missing mounted
  library or replace a missing script with a blank file.
- Preferences should identify the current folder and offer Choose and Reveal.
  Explain that choosing another folder switches libraries and does not move
  existing projects. Do not implement automatic copying of whole libraries.
- Validate a prospective root and persist the preference before completing a
  switch. Preference-write failure must leave the old active root coherent;
  report failure rather than claiming a switch that will reverse at restart.
- Make test roots explicit. Tests using temporary config/data/state directories
  must never discover, create, scan, or write the real user's Documents library.

Canonicalize the root for session/storage comparisons. A root may itself be
selected through a symlink; child project contents must not provide a route for
saving outside that resolved root.

### Recommended initial layout

```text
<library>/
  <initial-name>--<project-id>/
    script.fountain
    project.json
    versions/
      <existing timestamp-based version filenames>
    imports/
      source.fdx                 # only for an FDX import
```

The ID is generated once with enough randomness to avoid collisions; creation
and publication must also be exclusive, rather than trusting probability.
Validate IDs before using them in paths. The name prefix is sanitized only for
the directory name. Display names retain the user's Unicode text.

Keep the folder and `script.fountain` names stable after creation. The directory
prefix may consequently differ from a later display name; show the actual path
in Reveal. Do not let user-controlled names introduce separators or `..`.

Use a small versioned JSON sidecar. At minimum it contains:

- Format version and immutable project ID.
- Library display name and archive flag.
- User-pinned autocomplete entities, transferred from the existing index when
  importing legacy entries. These are project-associated user choices.
- Optional import/migration origin information and the completion marker needed
  to make legacy migration resumable.

Keep paths to required contents fixed and relative; metadata must not nominate
an arbitrary external working file. The screenplay title page remains part of
Fountain and is edited through the existing title-page workflow. A library
rename does not mutate it.

Do not add speculative feature fields. Preserve unknown fields when updating
supported metadata. A future unsupported format must be reported and must not
be overwritten. Corrupt or absent metadata must not prevent accessing readable
script bytes: recover identity from a valid folder ID where possible, show a
repairable entry, and preserve the damaged sidecar before an explicit repair.
Do not invent a new identity on every scan.

Duplicate IDs in one root must be visible as a conflict and must not share
mutable state. An explicit app Duplicate gets a fresh ID. Do not silently
rewrite identities in folders the user copied by hand.

Archive an active project only after resolving its current editor; failure to
write the archive metadata leaves it active. An archived project must not be
silently session-restored. Pending recovery remains actionable even when its
project is archived, and restoring an archive flag must not consume a journal.

### Authority and portability

- `script.fountain` is the saved screenplay authority.
- `project.json` holds project identity and associated user metadata.
- Version files hold previous readable screenplay snapshots.
- The central `library.json` remains a disposable cache for listing, recency,
  page counts, and reading/session position. It is rebuilt from projects.
- Recovery journals stay in the application's state directory; they protect
  live sessions and are not version files or a project manifest.
- Unknown files placed in a project are left untouched. Scanning, archive,
  duplication, migration, and retention must never delete them.

Discovery is a bounded directory scan off the actor thread. List committed
projects, ignore staging directories, and report damaged recognized projects.
Avoid parsing every script, paginating unopened scripts, or walking reference
subtrees on startup. Readable scripts remain available if the cache is absent
or corrupt; losing a cache may lose convenience, never text or project identity.

## 4. Creation/import transactions and source preservation

Introduce a small storage-level project helper, with bridge orchestration.
Do not scatter directory construction, metadata writes, and ID rules in Dart.

For a new project or import:

1. Validate the destination root and selected source, if any. Capture the import
   source once on a worker; validation and later writing use that snapshot.
2. Decode/prepare an isolated candidate where conversion is needed. Complete
   warning approval and current-document close confirmation before publication.
3. Allocate an exclusively owned staging directory inside the destination root.
4. Write required files through the atomic-save machinery. For Fountain, write
   the original byte buffer; preserve BOM, CRLF, trailing whitespace, unknown
   regions, and source case. Reject unsupported encoding with a useful error
   instead of silently decoding lossily. For FDX, preserve captured raw FDX
   bytes separately and write the Rust-produced native Fountain representation.
5. Publish a complete project without overwriting an existing directory. Use a
   tested no-clobber publication operation and sync the parent as required for
   durable publication. Do not assume ordinary directory rename is no-clobber.
6. Only after publication succeeds bind a session to the final library path,
   establish the correct DiskState, initialize/checkpoint its journal, and
   publish the library entry. Do not leave a session pointed at staging.
7. Adopt the new editor after rechecking mount/exit/switch state. An exit after
   publication may leave a complete new project in the library; it must not
   cause the project to be erased or the old document to be disposed twice.

No text entry reaches an uncommitted new project. A failed operation must leave
the previous session usable and the source unchanged. Cleanup may remove only
the staging directory that operation owns; do not purge arbitrary incomplete
folders. Retain/surface incomplete projects with useful text after a crash.
If publication happened but final synchronization or response delivery failed,
report that state honestly and reconcile the existing project on retry rather
than overwriting it or generating endless duplicate projects.

Never hard-link the source into a project. The imported copy must be independently
writable even when the source was read-only. Preserve source bytes, not source
permissions that would make the managed copy unwritable. Do not import by
temporarily opening the source and letting existing autosave run against it.

Keep the existing isolated FDX-candidate warning flow. Until a candidate has a
published library file, retain its complete initial recovery outcome against
the blank untitled base. After publication, checkpoint/rebuild against the exact
native bytes and source-order identities. Do not replace the live Document just
to mark it saved, manufacture an import Undo transaction, or bind the FDX path.

## 5. Identity, save, recovery, and versions

### Separate project identity from session location

The present `journal::script_id(path)` is a path hash, and existing library,
journal, and backup code uses it for several purposes. Introduce an explicit
managed-project identity/context; do not globally replace path hashes with a
bare project ID and assume every caller has the same ownership needs.

A display rename must preserve the project ID, file path, history, journal,
pins, and reading position. Journal/storage ownership must still distinguish
independent copies of a library and normalize aliases to the same live file.
A key scoped to the resolved library location plus project ID, or the existing
normalized file locator with a separate durable project ID, can satisfy this.
Choose the smallest sound implementation and document the distinction.

Manually relocating an entire library with pending recovery is not an automatic
relocation feature in this batch. Existing recovery evidence must remain
discoverable and retained if an old path cannot be resolved; do not guess a new
base by matching title or project ID alone.

### Save and export boundaries

- Normal public edit/open/create/save routes must validate managed destinations
  in Rust. A UI-only restriction is insufficient.
- Remove or narrow arbitrary-path Save As for managed sessions. Internal
  compatibility/candidate operations may use a dedicated validated commit
  helper; do not retain a user-facing escape that rebinds outside the library.
- Preserve save serialization, edits arriving during a save, checkpoint identity
  translation, byte-preserving provenance, and Undo/Redo behavior.
- Preserve last-known disk comparison and external-change prompts. Ordinary
  files remain externally editable even though Slugline manages them.
- Keep permission, unavailable-path, and no-space failures distinct. On a save
  failure, retain dirty state and the journal; offer Retry and Export a copy.
  Export can rescue current text but does not mark the library script saved.
  A subsequent close must still require explicit resolution/discard of unsaved
  library edits. Never silently discard them because an export succeeded.
- Export destinations must not replace any recognized managed project's script,
  metadata, imported source, or version file, including a closed project. Add a
  distinct library-destination refusal where necessary, retaining existing
  AlreadyExists confirmation and ScriptIsOpen refusal. Check aliases as well.
- Project discovery/open/save must reject child symlinks that escape the root,
  ambiguous IDs, and metadata-driven path traversal. Test this at the bridge,
  not only in a chooser.

### Recovery and application lifecycle

Retain outcome replay, ownership by kernel `flock`, inode checks, and
successor-before-predecessor-removal. Do not add persisted lock files or use a
project manifest as a recovery lock. A journal failure retains the existing
sticky warning without making a successfully stored project unusable.

Recovery takes precedence over session restore and importing the same source.
An undecided offer must not be bypassed by creating a new clean session over
its file. Accepting managed recovery must continue to recover into a dirty
session without silently saving it. Preserve ordinary quit parking, explicit
put-away, saved reading positions, and protections against late open/adopt/quit
callbacks.

### Previous versions

New managed projects store previous versions under their own `versions/`
directory. Adapt the existing backup implementation; avoid a new versioning
engine. Preserve the accepted opening baseline, explicit-save snapshots,
bounded autosave age gate, and retention policy.

Stop using the global backup-location preference for new managed writes.
Keep its old value readable as a legacy migration source, and explain that
future versions live with each script. Preserve retention preferences. Remove
the managed backup-folder chooser in favor of the library-folder preference.
Do not delete or run retention against old global/custom backup directories.

Archive keeps versions intact. Duplicate starts independent history with its
copied current snapshot; it does not copy the parent's previous versions or
pretend to continue that project's identity. For a closed project, duplicate
the saved file. For the active project, capture its current actor snapshot so
unsaved edits are included, while leaving the original session unchanged.
Copy user pins as independent metadata values. Do not copy arbitrary reference
files or an imported FDX archive as though they described the new snapshot.

## 6. Existing installations and migration

Migration is **copy-based, explicit, restartable, and non-destructive**.
Do not automatically move or rewrite existing files on startup.

1. Read the old index as compatibility input, without deleting or immediately
   rewriting it. Present a one-time **Bring existing scripts into the library**
   action with selectable entries and a concise explanation that originals
   remain unchanged. Dismissal leaves a usable managed library and a way to
   return to migration later.
2. Preserve old index entries, cache values, and custom backup locations as
   migration input before replacing the cache format. Use an atomic retained
   compatibility copy if needed. An absent/corrupt legacy index is not a reason
   to scan unrelated folders; ordinary file import remains available.
3. Resolve pending legacy recovery before migrating a source's saved disk copy.
   Do not silently choose older disk bytes over newer recorded edits.
4. For a legacy source with no pending recovery, import its captured exact file
   bytes. Carry over pins and useful reading position. Copy recognized previous
   versions into the project's version store without changing their contents or
   overwriting name collisions. Preserve the old originals and history store.
5. For accepted legacy recovery, produce an isolated recovered candidate using
   the existing verified base and outcome replay. Do not bind it to the old
   external source or allow autosave to write there. A user-confirmed migration
   commit creates the managed destination and establishes its exact saved base
   and successor protection before the old recovery journal can be retired.
6. If that successor cannot be established, retain the old journal and report
   the unresolved protection/migration state. Cancellation or failure must not
   consume an old recovery offer. Ownership checks still apply to live writers.
7. A previously restored external script must go through this migration/import
   policy before it becomes editable. Declining migration shows the library,
   rather than restoring an externally bound autosaving editor.
8. Save per-project completion/origin information so retrying a batch resumes
   completed entries without recopying them. Origin paths and old path hashes
   are compatibility information, not the new project's identity.
9. Missing/unreadable sources and history failures get per-entry status. A
   successfully imported current file may remain usable while history migration
   needs retry; do not claim its entire migration succeeded. Keep partial
   history copies and source evidence, and resume without overwriting them.

Metadata/cache write failure, interruption after project publication, duplicate
display names, two simultaneous import requests, and old live processes need
explicit behavior. A resumable operation must reconcile durable completion
before deciding to publish another project. Do not use a central migration
index as the only evidence that a project already exists.

## 7. Current implementation map

These pointers were inspected on the prepared commit. Reconfirm the tree and
relevant symbols before editing; line numbers and APIs can change.

| Area | Starting point / significance |
| --- | --- |
| Filesystem locations | [paths.rs](../crates/storage/src/paths.rs): config/data/state discovery; the user library is an additional location, not a replacement for all XDG roots. |
| Preferences | [prefs.rs](../crates/storage/src/prefs.rs) and [preferences_dialog.dart](../app/lib/settings/preferences_dialog.dart): add library selection and migrate backup-location UI. |
| Library/index | [library.rs](../crates/storage/src/library.rs): currently caches arbitrary paths and derives IDs from them; add managed discovery/cache and compatibility loading. |
| Atomic files | [atomic.rs](../crates/storage/src/atomic.rs): reuse writes; extend carefully if bytes/no-clobber project publication need helpers. |
| Versions | [backup.rs](../crates/storage/src/backup.rs): currently derives a version directory from a source path; adapt storage location without changing snapshot policy. |
| Journals | [journal.rs](../crates/storage/src/journal.rs): path IDs, verified bases, ownership, replay, checkpoint/rebuild, and safe removal. |
| Session identity/lifecycle | [state.rs](../crates/bridge/src/state.rs): `Session`, file identity, park/close, and storage state. |
| Bridge orchestration | [files.rs](../crates/bridge/src/api/files.rs): `library_open/create/rename/duplicate/remove`, `open_source`, `rebind`, `write_document`, imports, exports, backups, recovery, and preference views. |
| Dart seams | [core.dart](../app/lib/core/core.dart) and [document_core.dart](../app/lib/core/document_core.dart): replace `openDocument`'s open-or-create fallback with explicit managed open/create/import operations. |
| App adoption | [app.dart](../app/lib/app.dart): `_newScript`, `_quickOpen`, `_importScript`, `_importFdx`, `_switchPath`, `_adopt`, startup restore, and quit races. Fountain Import currently goes through ordinary source-file opening; fix that. |
| External launch | [main.dart](../app/lib/main.dart): preserve argument parsing while routing resolved external paths through import. |
| Library UI | [library_page.dart](../app/lib/library/library_page.dart) and [quick_open_dialog.dart](../app/lib/library/quick_open_dialog.dart): New/Open/Import, rename, duplicate, archive, discovery failures, and keyboard behavior. |
| Save/error UI | [save_dialogs.dart](../app/lib/library/save_dialogs.dart), [commands.dart](../app/lib/editor/commands.dart), and [editor_page.dart](../app/lib/editor/editor_page.dart): replace managed Save As, preserve dirty-close and failure choices. |
| Version UI | [backups_dialog.dart](../app/lib/library/backups_dialog.dart): list/read/restore versions and make Open as copy a managed creation. |
| Exports | [export_dialog.dart](../app/lib/preview/export_dialog.dart): share existing copy-export and replacement behavior, including destination protections. |

Read root and scoped AGENTS.md before implementation. Consult accepted decisions
only as touched: 0013/0016/0042 for recovery; 0014/0026/0027/0028/0038/0063 for
save; 0021 for pins; 0029 for export versus Save As; 0043 for versions;
0055/0062 for FDX; 0064/0067 for quit and reading position. The records are in
[DECISIONS.md](DECISIONS.md); archived SPEC/REVIEW are provenance.

Add the next unused ADR for this managed-library decision. Precisely name which
parts of the accepted records it supersedes/refines: arbitrary-path Save As,
untitled import adoption, pin storage, and version location where applicable.
Keep export-copy semantics, journal safety, retention, and saved checkpoint
identity guarantees. Only add allowed historical annotations to old records;
do not rewrite their accepted decisions. Update the decision index accordingly.

## 8. Implementation phases

These are ordered parts of one requested feature batch, not permission gates.
Keep phases reviewable and avoid exposing a partially converted workflow as
finished. If committing is authorized, use focused commits that build coherently.

### Phase 1 — Storage format, root, and discovery

- Add the project helper/type, immutable ID, sidecar format, and root preference.
- Implement exclusive staging/publication and exact-byte file copying.
- Implement bounded discovery, damaged-project reporting, archive filtering,
  and rebuildable caches scoped to the active root.
- Add isolated tests for format round-trip, publication failure, corruption,
  identity collisions, root selection, aliases, and cache reconstruction.
- Establish the new ADR and update only contracts actually established here.

**Exit:** storage can create/list/reopen temporary projects without involving
the real library or relying on a central index.

### Phase 2 — Managed sessions, save, recovery, and history

- Thread project context through bridge/session state and explicit open/create.
- Separate durable project identity from mutable/legacy storage locators.
- Bind only final paths and adapt DiskState, watchers, journalling, session
  parking, reading position, pins, and project version paths.
- Narrow legacy arbitrary-path save APIs and add export destination guards.
- Cover edits during save, checkpoint identity translation, failure retention,
  accepted recovery, second crash, and shared-root multi-process ownership.

**Exit:** a managed document saves and recovers with the existing guarantees;
rename cannot detach it from metadata/history, and external writes stay guarded.

### Phase 3 — Import and duplicate operations

- Add explicit Fountain-copy import and FDX prepare/commit handling.
- Preserve raw Fountain and archived raw FDX; initialize native semantics only
  in Rust. Preserve candidate warnings, cancellation, and empty import Undo.
- Add origin/dedup choices and new-ID duplicate/version-copy operations.
- Handle cancellation before publication and app exit after publication.

**Exit:** every accepted import has a complete independent library project;
source files are byte-identical afterward, including failed/canceled imports.

### Phase 4 — Existing installation migration

- Implement the retained compatibility input and resumable selective migration.
- Transfer metadata/history and account for missing/failed entries.
- Add legacy pending-recovery routing without external autosave or premature
  journal retirement. Handle old restored paths and interrupted migrations.
- Keep migration accessible after dismissal; ordinary startup remains usable.

**Exit:** old saved work, recorded unsaved work, and previous versions have
safe paths into the library without modifying their external originals.

### Phase 5 — User workflows and command parity

- Replace New's path chooser; keep keyboard-first library navigation.
- Route all external entry points through the same import policy.
- Change Save As to Export a copy and adapt save-failure/external-change dialogs.
- Add library folder controls, Reveal, display rename, Archive/Archived/Restore,
  and managed Open as copy. Keep current-document switching safe.
- Update widget doubles for transport/list surgery only; do not duplicate
  project/screenplay semantics in Dart test code.
- Update existing bridge/native fixtures and affected development harnesses
  that assume arbitrary-path open-or-create. Seed explicit temporary managed
  roots or exercise intentional external import, as appropriate. Preserve the
  original failure/round-trip/history assertions rather than weakening them to
  accommodate the new ownership rules.
- Update palette, shortcuts, F1 help, and documentation together.

**Exit:** normal user workflows cannot create or rebind an external working
file; their labels and keyboard behavior match the implemented persistence model.

### Phase 6 — Native integration, documentation, and final review

- Regenerate bridge bindings when public APIs/types change; include generated
  Rust/Dart, never hand-edit them. Batch generation sensibly.
- Finish README, KEYMAP, relevant scoped guides, architecture, changelog, and
  decision annotations. Remove descriptions of direct-source editing and
  arbitrary managed Save As without erasing historical results.
- Run the focused scenario matrix below and then full development validation
  once, as this is a substantial cross-layer feature boundary.
- Review the diff for accidental lockfile/toolchain changes, unrelated cleanup,
  unvalidated legacy paths, and unsafe deletion of evidence or user files.

**Exit:** all feature acceptance criteria have evidence; any unrelated failure
or external blocker is reported narrowly without claiming an unchecked pass.

## 9. Acceptance and verification matrix

Start with existing coverage and add meaningful regression scenarios. Test
filesystem behavior in temporary roots; test native behavior through the real
bridge. Widget evidence alone cannot prove file isolation or journal safety.

| Scenario | Required observation |
| --- | --- |
| New on fresh installation | Complete project is created under the lazy default/test root; typing and Save need no destination picker; real reopen succeeds. |
| Fountain import | Raw bytes, including BOM/CRLF/unknown text/trailing whitespace, match at initial publication. Subsequent edit/save affects only the copy. |
| FDX import | Warning approval/cancel behavior remains; published Fountain reopens with expected semantics, archived FDX matches input, and original FDX is unchanged. |
| Source isolation | Save, autosave, exports to other destinations, version restore, close, and reopen leave the imported source unchanged. Include a read-only source. Deliberate export over an origin needs replacement confirmation and never rebinds the session. |
| Immediate crash | Crash after accepted import, before typing or first user Save, retains the script; crash after unsaved editing offers correct recovery. |
| Checkpoint and second crash | Save with an edit arriving during the write, recover, edit again, crash again, recover again; ordered text/title and identities remain correct. |
| Export snapshot | Export captures unsaved current text; later library edits do not change the export; session/dirty/history/journal remain unchanged. |
| Export refusals | Existing destination needs confirmation; any managed project contents and open scripts are protected, including aliases and closed projects. |
| Rename and duplicate | Rename changes only the display name; ID/path/history/pins/row remain. Duplicate has a fresh ID and includes current unsaved text when invoked on the active script. |
| Archive/restore | Files and versions remain; cache deletion cannot unarchive or lose the project; restoration makes it available again. |
| Version operations | Original baseline and bounded autosave/manual snapshots still work; Restore protects current work; Open as copy creates an independent managed project. |
| Cache loss | Delete/corrupt the new cache; scripts, identities, labels, archive state, and pins are rebuilt from project data. Reading/recency caches may reset. |
| Metadata damage | Missing/truncated/future metadata reports a repairable or unsupported project, retains raw files, and does not block export/access to readable screenplay text. |
| Creation/import failures | Unreadable source, root permission/no-space failure, ID collision, and publication interruption leave original/current work intact; no half-project is listed as healthy. |
| Library unavailable | Missing configured library/mount is reported; no fallback creates a second silent working copy, and an open dirty session stays recoverable/exportable. |
| Library switch | Old files stay put; new root is validated before activation; cache/session state does not leak across roots; cancellation preserves the old editor. |
| Legacy migration | Original bytes, old versions, pins, row, and pending recovery survive; retries are idempotent; missing/history-failed entries are truthful. |
| Legacy recovery migration | Unsaved recorded edits reach the managed successor; original file is never autosaved; cancel/failure/live-owner refusal retains the old journal. |
| Concurrency and aliases | Same managed file reached by aliases does not gain independent in-process histories; another process cannot steal/discard its journal; duplicate IDs cannot collide in mutable storage. |
| External launch | CLI/desktop paths outside the active library import; known managed paths reopen; nonexistent external paths fail without creating files. |
| Keyboard/quit races | New/Open/Import/Export/put-away work from keyboard; warning cancellation, switch-unmount, ordinary quit/restore, and late adoption preserve focus/text/ownership. |

Use existing targets as starting points:

- Storage unit modules for project format, library, atomic writes, backup,
  preferences, and journals; add a dedicated managed-project module/target if
  that makes ownership and failure injection clearer.
- Bridge tests in `files.rs` and
  [persistence.rs](../crates/bridge/tests/persistence.rs).
- [file_workflow_test.dart](../app/test/file_workflow_test.dart),
  [startup_test.dart](../app/test/startup_test.dart),
  [arguments_test.dart](../app/test/arguments_test.dart), and library/settings/
  export/keyboard/close-race widget tests.
- Native [persistence_test.dart](../app/integration_test/persistence_test.dart),
  [bridge_test.dart](../app/integration_test/bridge_test.dart), and
  [export_test.dart](../app/integration_test/export_test.dart). Extend the
  selected suites for managed create/import/migration/save/reopen cases.

Examples of focused commands, selecting actual implemented tests/targets:

```sh
./tools/agent.sh quick storage <relevant-test-filter>
./tools/agent.sh quick bridge <relevant-test-filter-or-target>
./tools/agent.sh native persistence
./tools/agent.sh native bridge
./tools/agent.sh native export
python3 tools/check_docs.py
```

Run Dart format, affected widget files, and analysis from `app/` while iterating.
Confirm filters run tests. Test real write failures where practical; an injected
ENOSPC result only proves failure handling, not a real full-disk atomic write.
Preserve useful failing artifacts for any unresolved defect. Never mask a
failure with sleeps, slower input, retries, weakened assertions, or forced exit.

At the end of this feature batch, run the root policy's complete applicable
Rust and Flutter development checks once:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

From `app/`:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Select the affected native suites rather than automatically running all native
workflows. A normal development build needed by those checks is allowed. Do
not perform release compilation/packaging to complete this feature. Measure
startup/discovery against BUDGETS if the scan materially changes startup cost;
do not relax budgets. Runner clean-close checks apply if the runner/shutdown
implementation or Flutter toolchain changes, not as a ritual for storage work.
For any process-level ordinary-close smoke, inspect the actual exit status.

Follow the pinned toolchain: Rust minimum 1.85, Flutter 3.44.8, and matching FRB
2.12.0. Preserve `app/pubspec.lock` unless deliberately changing dependencies.
New dependencies require a same-change justification in DEPENDENCIES. Do not
add network behavior. Fetch current library API documentation with Context7
when implementing library-specific calls; use the codebase-memory skill for
structural exploration with coverage checks and source fallback.

## 10. Completion and handoff instructions

The implementing agent should proceed through all phases without asking the
owner to settle routine choices. This is direct feature work, not an instruction
to select the next unrelated backlog item. A new backlog entry is optional;
do not renumber, tick, or rewrite historical work to make room for this feature.

Done means all product contracts and acceptance scenarios are met, relevant
checks pass, documentation reflects the final behavior, and the diff has been
reviewed. Partial migration, UI-only ownership enforcement, or an import that
still edits its source is not completion. Record material choices and unresolved
limitations briefly. Keep commit/push status truthful and stop at the requested
Git boundary. Do not start adjacent feature work.

### Copyable agent task

> Implement `docs/MANAGED_LIBRARY_PLAN.md` in full. Read current root and scoped
> AGENTS.md first and recheck the relevant source/ADR contracts. Treat the plan's
> managed library, per-script folders, copy imports, copy exports, and safe
> migration as the authorized product direction. Use its defaults and decide
> routine implementation details autonomously. Complete all phases as one
> coherent feature batch, with focused checks while iterating and full Rust /
> Flutter development validation once at the final cross-layer boundary.
> Preserve original files, pending recovery, exact Fountain bytes, associated
> metadata, and existing version-history evidence. Update affected docs and add
> the next unused ADR with precise supersession annotations. Keep unrelated
> work separate. Do not commit or push unless the current implementation request
> authorizes it; do not run release, packaging, installation, publishing, or
> hosted-CI work. Finish with the actual implemented behavior, validation,
> material limitations, and Git status.
