# Slugline UI — Implementation Checklist

Tasks are ordered so that later ones don't get invalidated by earlier ones. Hand Claude Code
**one task at a time**, verify visually, then move on. Each task is written to be pasteable as-is.

---

## Priority 1 — Correctness

These are cases where the app is measurably wrong, not just unpolished. Both affect page count,
which is the unit of screen time in screenwriting, so they should be fixed and validated together.

### [ ] 1. Fix dialogue column width

> The dialogue element is wrapping too narrow. Measured against the current render, action lines
> span the full content column but dialogue wraps at roughly 42% of that width. The industry
> standard is 3.5 inches of dialogue within a 6.0 inch content column, i.e. **58%**.
>
> In `ScreenplayMetrics` (or wherever the element geometry constants live), verify and correct:
> - Dialogue: left indent 1.0", **width 3.5"**
> - Parenthetical: left indent 1.6", width 2.0"
> - Character: left indent 2.2"
> - Action: left indent 0", width 6.0"
>
> The character and parenthetical indents currently look correct — the bug is specifically the
> dialogue width constant, which appears to be set closer to 2.5". Express all of these as
> fractions of the content column width so they scale with zoom rather than as fixed pixels.
>
> Verification: the line "Okay so this is one of my favorites." should fit on a single dialogue
> line after the fix.

### [x] 2. Line height and element spacing

*(finish this, then run the validation test in task 3.)*

> Set the script editor's line height to 1.0–1.1 relative to font size. Courier Prime's natural
> metrics already include adequate leading — do not add more. Within a paragraph, wrapped lines
> must be single-spaced with no extra leading.
>
> Element separation must be exactly one blank line, implemented as a bottom margin equal to one
> line height — not a hardcoded pixel value, and not an extra `\n` in the document model. Check
> that padding on the paragraph widget isn't stacking on top of that margin.

### [x] 3. Add a pagination validation test

> Write a widget test that renders 55 single lines of action text using the standard metrics and
> asserts the rendered height equals exactly one page height. Add a second test asserting that a
> dialogue block of known length wraps to the expected number of lines at the 3.5" width.
>
> This turns "does the spacing look right" into something checkable so it can't silently drift
> again.

### [x] 4. Confirm editor and exporter agree on pagination

> Verify that the PDF/export pipeline and the editor's on-screen page counter derive page breaks
> from the same metrics source. If they compute independently, unify them so a change to
> `ScreenplayMetrics` propagates to both. Add a test asserting that a fixture script reports the
> same page count in the editor status bar and in the exported PDF.

---

## Priority 2 — Functional gaps

### [x] 5. Sync the navigator to the cursor position

> The navigator currently keeps scene 1 selected regardless of where the user is in the script.
> Make the outline track the reader's position, which is most of what makes an outline pane
> useful rather than just a jump list.
>
> - On scroll, highlight the topmost visible scene.
> - On edit or caret move, highlight the scene containing the caret.
> - Auto-scroll the navigator so the active row stays visible.
> - Add a suppression flag so that when the user clicks a navigator row to jump, the resulting
>   editor scroll does not feed back and re-trigger navigator scrolling.
> - Debounce the scroll handler (~100ms) so this doesn't thrash during fast scrolling.

### [x] 6. Page break indicators in continuous mode

> The status bar already reports "Page 52 of 89". Show where those breaks actually fall: render a
> hairline rule (use the `border` token) across the content column at each page boundary, with the
> page number in small `textTertiary` type in the right gutter.
>
> This is what makes the page count useful while writing rather than only at export time.

### [ ] 7. Empty state for the opening screen

> When there are no recent scripts, the screen is currently blank. Add a centered empty state
> within the content column: a document icon in `textTertiary`, a one-line explanation, and the
> "New script" button as the focal point, with "Open" as a secondary text button beneath it.

---

## Priority 3 — Layout and polish

### [ ] 8. Fix file paths on the opening screen

> Three bugs in the recent-files path line:
> - `home/phagmaier/cross.fountain/` is missing its leading slash and has a spurious trailing
>   slash. Find the join/split logic producing this and fix it.
> - Collapse the user's home directory to `~` for display.
> - Long paths (e.g. the `/tmp/claude-.../scratchpad/demo.fountain` entry) blow out the row.
>   Truncate from the middle, always preserving the filename, and show the full path in a tooltip
>   on hover.

### [ ] 9. Constrain the opening screen content column

> Rows currently stretch nearly the full window width, leaving the title and the overflow menu far
> apart at wide window sizes. Wrap the recent list in a centered column with a max width of
> ~960px, matching the horizontal rhythm of the "RECENT" label.

### [ ] 10. Fix the editor gutters

> The content column is not truly centered: there is roughly 278px of space to its left and 210px
> to its right. Center the column within the space between the navigator panel edge and the
> scrollbar, accounting for scrollbar width so it doesn't shift when the bar appears.

### [ ] 11. Bold scene headings

> Render scene headings in bold within the editor. This is conventional formatting and makes
> vertical scanning of the script substantially faster. Keep them uppercase and at the 0" indent.

### [ ] 12. Audit spacing before scene headings

> The gap before `EXT. VAL'S BACKYARD - LATER` is visibly larger than other paragraph gaps. Find
> out whether that's a double blank line in the source document or an extra top margin on the
> scene heading element.
>
> Extra space before a slug is defensible — but make it an explicit, consistent rule in
> `ScreenplayMetrics` (e.g. slug top margin = 2 line heights) applied to every scene heading,
> rather than an artifact of one document's source text.

### [ ] 13. Reveal drag handles on hover

> All nine visible navigator rows show their drag handle at all times, which reads as visual
> noise. Show the handle only on row hover (and on keyboard focus, for accessibility). Reserve the
> horizontal space so rows don't shift when it appears.

### [ ] 14. Align scene numbers to the title line

> Scene numbers in the navigator are baseline-aligned to the bottom of the two-line block. Align
> each number to the baseline of the scene name on the first line instead. Keep the fixed-width
> number column so names stay aligned.

### [ ] 15. De-emphasize segmented control counts

> In the "Scenes 55 / Characters 26" control, render the counts in `textTertiary` at a slightly
> smaller size so the labels read first and the numbers are secondary.

---

## Priority 4 — Window chrome and identity

### [ ] 16. Add minimize and maximize to the custom title bar

> The custom title bar currently offers only a close button. Add minimize and maximize/restore
> controls, and make the bar draggable for window movement and double-click-to-maximize. Follow
> the platform's button ordering.

### [ ] 17. Resolve the duplicated app name

> The app name appears twice with inconsistent capitalization — "slugline" in the title bar and
> "Slugline" in the opening screen header. Pick one canonical capitalization and define it in a
> single constant.
>
> Then remove the in-app header text on the opening screen entirely: the title bar already
> identifies the app, so that space can go to the "RECENT" section instead. Keep the toolbar
> buttons where they are.

---

## Verification pass

After the above, check each of these by hand:

- [ ] A dialogue block that should fit on one line does.
- [ ] 55 lines fill exactly one page; the test passes.
- [ ] Editor page count matches exported PDF page count on a fixture script.
- [ ] Scrolling to page 52 highlights the correct scene in the navigator.
- [ ] Clicking a navigator row jumps correctly without the selection bouncing.
- [ ] Opening screen with zero recent files shows the empty state.
- [ ] All paths display as `~/...` with no doubled or missing slashes.
- [ ] Resizing the window keeps both content columns centered.
- [ ] Every toolbar icon has a tooltip with its keyboard shortcut.
- [ ] Tab-navigating the UI shows a visible focus ring on every interactive element.
