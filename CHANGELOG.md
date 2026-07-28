# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

`app/pubspec.yaml` is the release-version source; `tools/check_version.py` holds
this file and the others to it.

## 1.0.0 - 2026-07-27

First release.

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
