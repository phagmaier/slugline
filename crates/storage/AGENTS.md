# storage — scoped agent notes

Scope: persistence. Atomic save, crash journal, backups, preferences,
library index. Depends only on `document`. This is where "losing user text
is a P0 bug" is cashed out.

Key files: `src/journal.rs`, `src/atomic.rs`, `src/backup.rs`,
`src/watch.rs` (`DiskState`), `src/library.rs`, `src/prefs.rs`,
`src/paths.rs`.

Invariants:

- A write either happened or did not; a read never fails on bad input.
  Corrupt journals, truncated indexes and mangled preferences each yield
  what could be read.
- Every file this project writes goes through `atomic::save_atomically`,
  including the ones it writes about itself.
- The journal records the outcome of an edit (a `Patch`), never the
  command; replay is list surgery with no inference. Appends are not
  `fsync`ed on purpose (ADR 0013).
- Saved checkpoints translate live block identities into the saved base's
  source-order identities, including buffered outcomes and subsequent inserts.
  The translation is session bookkeeping; records keep their existing format
  and recovery needs no persisted mapping (ADR 0063).
- A journal file's absence says the session ended cleanly. Only
  `Journal::discard` removes it; live journals hold a kernel `flock` the
  startup scan respects (ADR 0042). Report every journal-less outcome via
  `JournalBroken`; never fail the open over it.
- The watcher only asks early; the save path protects the file by comparing
  against `DiskState` immediately before replacing it (ADR 0038).
- Save As moves the session; an export copies text and moves nothing
  (ADR 0029). Backups and the library index are caches: deleting them costs
  only convenience (ADR 0043).
- `storage` uses `libc::flock`, not `File::try_lock`, because the workspace
  floor is Rust 1.85 (ADR 0042).

Verification follows the [root policy](../../AGENTS.md#verification): run the
relevant `cargo test -p slugline_storage` filter or test target, covering affected
save/recovery/error cases. Use the whole crate only when warranted. The full-disk
test is only the real thing with a small filesystem in `SLUGLINE_FULL_DISK_DIR`
(CI mounts a 4 MB tmpfs); otherwise it proves error classification alone. It is
not a mandatory test for unrelated storage edits.

Governing ADRs: 0013, 0026, 0027, 0028, 0029, 0038, 0042, 0043, 0063. Full rules
in `AGENTS.md`; the layer map in `docs/ARCHITECTURE.md`. Update these notes
only when their invariants or pointers change.
