# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

`app/pubspec.yaml` is the release-version source; `tools/check_version.py` holds
this file and the others to it.

## Unreleased

### Added

- The release process now has automated cold-start, idle wakeup and memory
  regression checks under Xvfb. The separate real-desktop memory budget remains
  a manual verification gate.

### Changed

- Preview and export opens on the page the caret is on instead of always at the
  top. Page 1 still opens at the top, with the title page. The preview's scroll
  bar now reflects the script's real length from the moment it opens.
- New, Browse, Save As, Rename, Export and the font/backup preferences now use
  GTK's local file dialog, with system bookmarks, search, keyboard navigation,
  folder creation and file-type filters. Dialogs start beside the current script
  or remember the last accepted folder during the launch. Extensionless save
  names gain the format's extension; replacement still asks only once in Slugline.

### Fixed

- On Hyprland and other non-GNOME Wayland desktops, the runner no longer adds
  a GTK header bar above Slugline's own bar. GNOME keeps its header bar; other
  desktops leave decoration to their compositor.
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
- Fountain character cues now accept punctuation such as `#`, `&`, `/` and `,`,
  and lowercase parenthesised extensions, without turning their speech into action.
- Emphasised centred lines and title fields now align by printed width, and
  transitions and draft dates end at the right margin. Escaped markers and
  unpaired markup retain their printed widths; wrapping is unchanged.
- Preview now renders Fountain emphasis with the same italic, bold and underline
  interpretation as PDF export, including runs spanning wrapped rows and pages.
  “Bold scene headings” in Preferences applies to editor, preview and PDF;
  it is off by default. Editor inline markers and wrapping are unchanged.
- The Linux writing integration test now opens the navigator through Ctrl+J
  before checking its rows, matching the compact-window drawer behavior.
  Application navigation is unchanged.
- Consecutive lyric lines are single-spaced in the editor, preview and PDF,
  with one blank line before each lyric run instead of before every line.
- Clicking the navigator's Characters tab no longer disables Ctrl+J on Linux.
  The shortcut returns to scene search without clicking back into the editor.
- Sung lines beginning with `~` inside dialogue now print without the tilde and
  in italics in preview and PDF, including wrapped lines and page continuations.
  They remain part of the speech; source text and editor wrapping are unchanged.
- The first page of a script no longer prints `1.`, following the usual
  screenplay convention; numbering starts showing on page 2. “Number the first
  page” in Preferences restores it in page view, preview and PDF. Page counts
  and every other page number are unchanged.
- The committed Dart lockfile is again the one the supported Flutter toolchain
  (3.44.8) resolves, and CI and the release build now refuse one that is not.
  The application is unchanged: those builds were already using these versions.
- The README now sends readers to Preferences → Page defaults, the section's
  actual name, for the heading-weight and first-page-number options.
- The Dart sources are formatted with `dart format` throughout, and CI now
  checks it. No behaviour changed: only whitespace and trailing commas moved.
- Page breaks no longer go wrong after an edit near the top of every fourth
  page. Shortening or lengthening the paragraph, speech or heading that page 5,
  9, 13… begins with, or retyping the line above it as a heading or a lyric,
  could leave that block on the wrong side of the break — in page view, the
  preview, an exported PDF and the saved page count — until the script was
  reopened or a line was added or removed. A blank page made with two forced
  breaks could, at such a page, repeat the script from there on. Repagination
  after an edit now gives exactly the pages a freshly opened script has.

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
