# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

`app/pubspec.yaml` is the release-version source; `tools/check_version.py` holds
this file and the others to it.

## Unreleased

### Fixed

- Launching another window no longer deletes or offers a running session's
  crash journal. Recovery and atomic journal replacement preserve its lock.
- Previous versions now include changed-text autosave snapshots at ten-minute
  intervals and changed files on opening. Explicit saves always record a version,
  and hourly retention protects recent history from bursts of manual saves.
- Find's element filter can be reset to "Every element" and remembers the reset
  when Find is reopened; cancelling the menu leaves the filter unchanged.
- Page-view sheets are centred within the editor's scrollbar reserve, without
  left-edge clipping or a horizontal jump when pagination first arrives.
- The README now lists Ctrl+K for the command palette and Ctrl+P for Preview and
  export, and omits test counts that become stale.

## 1.0.2 - 2026-09-13

### Improved

- Smoother scrolling and editing on long scripts: laid-out text is cached
  across frames in the editor and the preview.
- The status bar shows the caret position and the text size, with zoom controls.
- The library gains search and sorting by recent, title, or page count.
- The export dialog shows the preview size as a percent of actual size, with
  Fit width and Actual size shortcuts, and shrinks to small windows.
- Keyboard focus gets its own visible ring on icon buttons.
- Newer local Flutter toolchains keep working; CI still builds with the exact
  supported toolchain (3.44.8).

### Fixed

- The element bar no longer crosses the bridge on every caret move.
- Find waits for a typing pause before scanning the document.
- A theme switch repaints the editor at once instead of on the next edit.
- Library load failures show a retry instead of a spinner.

## 1.0.1 - 2026-09-06

### Improved

- Suggestions stay closed while opening and navigating scripts. Typing or
  Ctrl+Space opens a compact popup that keeps the selected candidate visible.
- Narrow windows use a temporary navigator drawer, preserving the preference
  for a docked navigator in wider windows.
- Find fits the available window space and remembers the element filter.
- More readable secondary interface text, better text scaling, and a visible
  Commands button with updated shortcut help.

### Fixed

- Clipboard operations no longer apply stale selections after asynchronous work.
- Closing during a save preserves edits made while the save is in progress.
- Autosave handles lifecycle transitions and modal dialogs consistently.
- Find results and autocomplete no longer retain stale edit ranges.
- Suggestion pinning preserves the caret, popup, and keyboard focus.
- External-change watcher registration handles replaced documents safely.

## 1.0.0 - 2026-07-27

First release.

### Distribution

- Versioned Linux x86_64 tarball with user-prefix installer and uninstaller.
- Self-contained Linux x86_64 AppImage.
- Tag-gated GitHub Release automation with SHA-256 checksums.

### The editor

- A single custom editing surface for the whole script, not a widget per block,
  with its own caret, selection and line breaking on the keystroke path.
- Screenplay elements classify themselves as you type, and Tab and Enter move
  between them the way screenwriting software has always done. Nothing is ever
  pinned automatically — a forced element is one a person asked for, and it is
  visible in the file as Fountain's own `.`, `@`, `>` or `!`.
- Undo and redo, find and replace, word motion, and a command palette.
- Autocomplete for character cues and scene headings, which never inserts
  without an explicit acceptance key.
- A scene and character navigator, and spell-check that never corrects anything
  by itself.
- Full keyboard operation: a whole scene can be written without the mouse.

### Files

- Reads and writes plain Fountain. An unedited file saves back byte for byte
  identically, including line endings and trailing whitespace.
- Every save is atomic: the file on disk is always either the complete old
  version or the complete new one, never half of either.
- Every keystroke is appended to a crash journal. A session that ends in a
  `SIGKILL` is offered back on the next launch rather than mourned.
- Rolling backups: the last ten saves, plus one per day for a week, with a
  "Restore previous version" that backs up the current text first.
- A file changed on disk by something else is noticed and never silently
  overwritten — the save path checks immediately before replacing, so the check
  holds even where the watcher cannot run.
- Read-only files, full disks and permission failures each get their own message
  and a Save As escape hatch.
- The library index, the session and the backups' bookkeeping are caches:
  deleting any of them costs nothing but convenience.

### Output

- Pagination in standard screenplay format, with a live preview.
- PDF export with the bytes written by this project — deterministic, so the same
  script always exports to the same file. Courier Prime is embedded and
  subsetted; A4 and US Letter are both supported.
- An editable title page, which reaches both the Fountain file and the PDF.
- Export writes a copy and moves nothing: it is not a Save As, and it refuses to
  overwrite a file or to write a script open in this session unless told to.

### Privacy

- No network connections of any kind. No telemetry, no update check, no account,
  no font download, no database and no lock files. `tools/check_no_network.sh`
  runs the release build with networking removed and proves it.
