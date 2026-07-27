## Findings

- [ ] See Below
1. **Critical — “Decide later” can erase a pending crash recovery.**

   When the recovery dialog returns no choice, startup continues into session restoration in [app.dart](/home/phagmaier/Code/slugline/app/lib/app.dart:108). The previously open script is reopened, which calls `restart_journal` in [files.rs](/home/phagmaier/Code/slugline/crates/bridge/src/api/files.rs:1916). `Journal::create` then opens that script’s existing journal with `truncate(true)` in [journal.rs](/home/phagmaier/Code/slugline/crates/storage/src/journal.rs:235).

   Therefore, pressing Escape or “Decide later” can replace the journal containing unsaved edits with an empty journal. The next launch cannot offer those edits again.

   Required fix:

   - Never session-restore a script that has a pending recovery.
   - Make normal journal creation refuse to truncate an existing journal; only explicit recovery/discard logic should replace it.
   - Add a regression test: crash with dirty text → choose “Decide later” → journal remains byte-identical → next launch offers it again.

- [x] See Below
2. **High — Save As silently overwrites existing files.**

   `_askAndSave` calls `core.saveAs(path)` without an overwrite confirmation in [save_dialogs.dart](/home/phagmaier/Code/slugline/app/lib/library/save_dialogs.dart:228). `doc_save_as` passes the destination directly to the atomic replacement path in [files.rs](/home/phagmaier/Code/slugline/crates/bridge/src/api/files.rs:542).

   Selecting another existing screenplay therefore destroys it without the standard “Replace?” confirmation. Export already has the correct `AlreadyExists`/explicit-overwrite behavior.

   Required fix:

   - Enforce this in Rust, not only in the dialog.
   - Refuse existing destinations unless they are the session’s current path or an explicit `overwrite: true` retry.
   - Refuse paths held by another open session.
   - Test that an occupied destination remains byte-identical until overwrite is explicitly confirmed.

- [ ] See Below
3. **High — initial journal creation failure is completely silent.**

   `restart_journal` converts `Journal::create` failure to `None` with `.ok()` in [files.rs](/home/phagmaier/Code/slugline/crates/bridge/src/api/files.rs:1931). When the session has no journal, `Session::record` simply returns `false` in [state.rs](/home/phagmaier/Code/slugline/crates/bridge/src/state.rs:411), which is indistinguishable from success to the caller.

   If the state directory is full, unwritable, or out of file descriptors, the editor remains usable but nothing typed is crash-protected—and the existing `JournalBroken` warning is never emitted.

   Required fix:

   - Return and retain journal initialization status.
   - Mark the session as unprotected and show the persistent warning already used for append failures.
   - Add tests for an unwritable/full journal directory before opening or creating a script.
   - Also stop ignoring the `false` returned by `files.init` in [core.dart](/home/phagmaier/Code/slugline/app/lib/core/core.dart:82); currently the app can start without storage initialized.

- [ ] See Below
4. **Medium — external-change protection silently disappears if file watching fails.**

   Watcher construction is reduced to `.ok()` in [files.rs](/home/phagmaier/Code/slugline/crates/bridge/src/api/files.rs:248), and per-file `watch` errors are discarded in [files.rs](/home/phagmaier/Code/slugline/crates/bridge/src/api/files.rs:1937). Ordinary saves do not independently revalidate the file’s on-disk contents.

   Exhausted inotify limits, unsupported filesystems, or watcher initialization failure can therefore leave the app able to overwrite external edits without warning.

   At minimum, expose a persistent degraded-safety warning. For stronger protection, compare the last-known disk fingerprint/content before replacement so the watcher is a prompt mechanism rather than the sole correctness boundary.

- [ ] See Below
5. **Low — one production write bypasses the atomic-write invariant.**

   The backup `origin` metadata is written through ignored `fs::write` in [backup.rs](/home/phagmaier/Code/slugline/crates/storage/src/backup.rs:87). It is not screenplay text, but it contradicts the project rule that every Slugline-owned file is atomic and may leave truncated or missing provenance. Use `save_atomically` and define whether failure should fail the backup or produce an explicit degraded result.

- [ ] See Below
6. **Low — dependency and documentation cleanup is needed.**

   - `cupertino_icons` is unused in [pubspec.yaml](/home/phagmaier/Code/slugline/app/pubspec.yaml:36) and absent from `docs/DEPENDENCIES.md`. Remove it.
   - [README.md](/home/phagmaier/Code/slugline/README.md:6) still says Phase 10 is next, reports obsolete test counts, and references a `REMEDIATION_PLAN.md` that is not present.
   - [SPEC.md](/home/phagmaier/Code/slugline/SPEC.md:1380) still marks the appearance-preference test incomplete and elsewhere describes six integration suites although CI now has seven.
   - The large stock Flutter comments in `pubspec.yaml` can be trimmed; they obscure the few settings that matter.

## Packaging/release blockers

These are expected because Phase 11 has not been done, but they must be resolved before distribution:

- No top-level GPL `LICENSE`/`COPYING` file despite `GPL-3.0-or-later` metadata.
- No desktop entry, icons, MIME metadata, Flatpak/AppImage/tarball, or changelog.
- No `--help`, `--version`, or argv file-opening behavior; the GTK runner forwards arguments, but Dart’s `main()` ignores them.
- The native runner reports as “not stripped”; the Rust `.so` is stripped.
- Phase 0 handshake APIs and `spike/` remain.
- No network-isolation gate.
- Rust reports version `0.1.0` while the Flutter application reports `1.0.0+1`; choose one release-version source.
- The spec requests `panic = "abort"`, while [Cargo.toml](/home/phagmaier/Code/slugline/Cargo.toml:35) deliberately uses unwind for bridge panic translation. Resolve this through a superseding decision rather than changing it blindly.
- Manual real `ibus`/CJK, X11, HiDPI/fractional scaling, two-distribution, browser PDF, and printer checks remain outstanding.

## Verification performed

Everything else was green:

- Clean worktree and `git diff --check`
- Rust formatting and Clippy with warnings denied
- 518 Rust tests plus 2 doc tests
- Layering and generated-reference checks
- Flutter analysis with no issues
- All 363 Flutter unit/widget tests
- All seven integration files: 55 tests
- Release Linux build
- Release bundle: 29,908,564 bytes, below the 60 MiB budget
- Keystroke p99: 3.85 ms; journalled-keystroke p99: 1.40 ms
- PDF extraction and deterministic goldens

Not reproduced locally: the real tmpfs ENOSPC path, fuzz jobs, network isolation, or the manual platform/input checks.

Recommended fix order: pending-recovery truncation, Save As overwrite protection, silent journal failure, then watcher degradation and cleanup. No files were modified during this review.
