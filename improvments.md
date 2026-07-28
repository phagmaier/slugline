- [x] See below 
## 1. Page geometry and element indentation (do this first)

> Refactor the editor so the script renders inside a fixed-measure page column, not full-width. Model it on US Letter at 12pt Courier (10 chars/inch, 60 characters per line):
> - Content column = 6.0 inches of text width, centered horizontally in the editor viewport, with a max width so it never stretches on wide monitors.
> - Compute all indents as fractions of that column so it scales with zoom. Relative to the left text margin: **Action** 0", full 6.0" width. **Character** +2.2". **Parenthetical** +1.6", width ~2.0". **Dialogue** +1.0", width 3.5". **Transition** right-aligned to the 6.0" edge. **Scene heading** 0", uppercase.
> - One blank line between elements, single-spaced within them. Target ~55 lines per page.
> - Add a `ScreenplayMetrics` class holding these constants; no magic numbers scattered in widgets.
>
> Add a user setting for page view (visible page breaks / paper-like surface) vs. continuous scroll, defaulting to continuous with a subtle page-break rule and page number in the gutter.


- [ ] See below 
## 2. Typography split

> Establish two type systems and stop mixing them. Script body: Courier Prime (bundle the font, don't rely on system fallback) at a size that makes 60 characters fit the 6" column exactly — derive size from column width rather than hardcoding. UI chrome: a single sans (Inter or the platform default) at 13–14px, never Courier. The script font is currently too large relative to its container; sizing it off the column width fixes this automatically.

- [ ] See below 
## 3. Design tokens and elevation

> Replace all hardcoded colors with a token set in a single theme file, wired through `ThemeData`/`ColorScheme`. Define at least: `surface` (app background), `surfaceRaised` (sidebar, bars), `surfaceOverlay` (menus, dialogs), `border` (a low-contrast hairline, ~8–12% white), `textPrimary`, `textSecondary`, `textTertiary`, and one `accent`.
>
> Right now the sidebar, the editor, and the top bar are all effectively the same near-black, so nothing reads as a distinct region. Give the sidebar a slightly different surface value and separate regions with 1px hairline borders, not shadows. Use the accent color for exactly one thing at a time — selected state and primary buttons only.

- [ ] See below 
## 4. Top bar

> The top bar is eight identical-weight icons in a row with no grouping, which reads as unfinished. Restructure it:
> - Keep only frequent actions visible: outline/navigator toggle, find, export/PDF, and settings.
> - Move history, save, keyboard shortcuts, and spellcheck into an overflow `...` menu or into the settings sheet.
> - Group remaining icons into 2–3 clusters separated by a vertical hairline divider with 12px padding either side.
> - Reduce icon stroke weight and size to 18–20px, color them `textSecondary`, and shift to `textPrimary` on hover. Add tooltips with keyboard shortcuts to every one.
> - Minimum 40×40 hit targets even though the icon is smaller.
> - The filename "cross.fountain" should show as the title with the extension in `textTertiary`, plus an unobtrusive saved-state indicator next to it.

- [ ] See below 
## 5. Sidebar density and hierarchy

> The scene list rows are too tall and the two lines compete. Tighten it:
> - Row height ~52px, 8px vertical padding, scene name at 13px `textPrimary`, the "INT. · DAY" meta at 11px `textTertiary`.
> - Add a scene number in a fixed-width `textTertiary` column on the left so names align.
> - Selected state: subtle `surfaceOverlay` fill plus a 2px accent bar on the left edge, not a large saturated block.
> - Add hover state, drag handles for reordering, and a right-click context menu.
> - Make the search field sticky at the top of the list and give the "Scenes / Characters" control a proper segmented-control treatment (equal-width segments, same corner radius, sliding indicator).
> - Panel header "Navigator" should be small, uppercase, letter-spaced, `textTertiary` — a section label, not a heading competing with the script.

- [ ] See below 
## 6. Status bar

> "2141 blocks" is internal jargon — no writer thinks in blocks. Replace the status bar contents with: current element type (as a proper dropdown control with a border and chevron, not bare text), page count ("Page 12 of 88"), scene count, word count, and a small dot + relative timestamp for save state. Reduce to 11px `textTertiary`, height ~28px, hairline top border.

- [ ] See below 
## 7. Opening screen

> The opening screen is 95% empty space with one row floating at the top left. Rework it:
> - Constrain content to a centered max-width column (~900px) with generous top padding.
> - Section header "Recent" above the list, `textTertiary`, uppercase, small.
> - Each row: title at 15px, then a metadata line with relative time ("2 hours ago"), page count, and the file path truncated from the left in `textTertiary`. Add hover background and make the whole row a click target, not just the title.
> - Design a real empty state for when there are no scripts: centered icon, one-line explanation, and the "New script" button as the focal point.
> - "New script" and "Open" are currently competing — make "New script" the filled accent button and "Open" a plain text button.


- [ ] See below 
## 8. Interaction polish

> Add: 120–180ms ease-out transitions on hover/selection (no bounce, no scale), a visible focus ring on keyboard navigation, a typewriter/focus mode that keeps the caret vertically centered and dims non-active paragraphs, and a caret that's 2px and accent-colored so it's findable in a wall of monospace.

If you only have appetite for two of these, do **1 and 3**. Page geometry is what makes it read as a screenwriting tool, and the token system is what stops future Claude Code sessions from drifting back into inconsistency — every subsequent instruction can then just say "use `surfaceRaised` and `textTertiary`" instead of re-litigating colors.

One meta-tip: give Claude Code the pro-app screenshot as a reference for *layout structure* when working on the editor, and tell it explicitly what you're not copying (the beats/outline tabs, the floating toolbar) so it doesn't drift into cloning.
