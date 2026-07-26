import 'package:slugline/core/document_core.dart';

/// Where each element sits on the screenplay grid, in characters.
///
/// **These numbers are a copy, and the copy stays.** §5.2 puts them in the Rust
/// `layout::metrics` module, which now exists; ADR 0005 expected the editor to
/// render the lines that crate computes, and ADR 0018 revisits that for 1.0. The
/// editor is fluid and unpaginated, its wrapping sits on the keystroke path, and
/// a bridge round trip per keystroke is not a price worth paying to avoid two
/// copies of nine constants. So these are the same values §5.2 lists, held in
/// one file, and the corpus-wide differential test against `layout::break_lines`
/// (remediation Phase 6C) is what keeps them from drifting.
///
/// Screenplay typography is a fixed monospace grid (§5.1) — 10 characters per
/// inch — so an inch is ten columns and every measurement below is exact.
class ElementMetrics {
  const ElementMetrics({
    required this.indent,
    required this.width,
    required this.blankLinesBefore,
    this.alignment = ColumnAlignment.left,
    this.upperCase = false,
  });

  /// Columns from the left edge of the text area (1.5" on the page).
  final int indent;

  /// Columns of text before the line wraps.
  final int width;

  /// Empty rows above this element (§5.2).
  final int blankLinesBefore;

  final ColumnAlignment alignment;

  /// Displayed in capitals. **Display only** — the model's text is never
  /// touched, which is what keeps element changes non-destructive (§13).
  final bool upperCase;
}

enum ColumnAlignment { left, right, centre }

/// §5.2's table, converted from inches at 10 characters per inch and with the
/// left margin (1.5") taken as column zero.
///
/// Sections, synopses and notes are not in §5.2 because they are never printed.
/// They are editor-only, and sit at the left margin so that they read as
/// scaffolding rather than as script.
const Map<BlockKind, ElementMetrics> elementMetrics = {
  // Scene heading — 1.5", 60 wide, 2 blank lines before.
  BlockKind.sceneHeading: ElementMetrics(
    indent: 0,
    width: 60,
    blankLinesBefore: 2,
    upperCase: true,
  ),
  // Action — 1.5", 60 wide.
  BlockKind.action: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
  // Character — 3.7", 33 wide.
  BlockKind.character: ElementMetrics(
    indent: 22,
    width: 33,
    blankLinesBefore: 1,
    upperCase: true,
  ),
  // Dialogue — 2.5", 35 wide, no blank line: it follows its cue.
  BlockKind.dialogue: ElementMetrics(indent: 10, width: 35, blankLinesBefore: 0),
  // Parenthetical — 3.1", 26 wide.
  BlockKind.parenthetical:
      ElementMetrics(indent: 16, width: 26, blankLinesBefore: 0),
  // Transition — right-aligned to 7.5".
  BlockKind.transition: ElementMetrics(
    indent: 0,
    width: 60,
    blankLinesBefore: 1,
    alignment: ColumnAlignment.right,
    upperCase: true,
  ),
  // Centered — centred within 1.5"–7.5".
  BlockKind.centered: ElementMetrics(
    indent: 0,
    width: 60,
    blankLinesBefore: 1,
    alignment: ColumnAlignment.centre,
  ),
  // Lyric — as dialogue.
  BlockKind.lyric: ElementMetrics(indent: 10, width: 35, blankLinesBefore: 1),
  BlockKind.section: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
  BlockKind.synopsis: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
  BlockKind.note: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
  BlockKind.pageBreak: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
  BlockKind.opaque: ElementMetrics(indent: 0, width: 60, blankLinesBefore: 1),
};

ElementMetrics metricsFor(BlockKind kind) =>
    elementMetrics[kind] ?? elementMetrics[BlockKind.action]!;

/// How a block's text is drawn.
///
/// A scalar is capitalised only when its upper case is exactly one scalar of
/// the same UTF-16 width. `ß` would become `SS`, and a display string one code
/// unit longer than the model's would put every caret column after it in the
/// wrong place, so it stays as written while the rest of the heading is still
/// capitals. `layout::engine`'s `display_text` applies the same rule scalar by
/// scalar, which is what lets the paginator wrap the columns the editor draws
/// (`docs/LINE_BREAKING.md`).
///
/// Dart's `toUpperCase` already refuses exactly those scalars, so the whole
/// string is the fast path — but the walk below proves the offsets line up
/// rather than assuming it, and falls back to the text as written if they ever
/// do not.
String displayText(BlockKind kind, String text) {
  if (!metricsFor(kind).upperCase) return text;
  final upper = text.toUpperCase();
  if (upper.length != text.length) return text;
  // Equal totals are not enough on their own: the scalars have to line up one
  // for one, so that every model offset is the same offset in the display.
  final source = text.runes.iterator;
  final mapped = upper.runes.iterator;
  while (source.moveNext()) {
    if (!mapped.moveNext() || mapped.rawIndex != source.rawIndex) return text;
  }
  return mapped.moveNext() ? text : upper;
}

/// The label the UI shows for an element type.
String kindLabel(BlockKind kind, int sectionLevel) => switch (kind) {
      BlockKind.sceneHeading => 'Scene heading',
      BlockKind.action => 'Action',
      BlockKind.character => 'Character',
      BlockKind.dialogue => 'Dialogue',
      BlockKind.parenthetical => 'Parenthetical',
      BlockKind.transition => 'Transition',
      BlockKind.centered => 'Centred',
      BlockKind.lyric => 'Lyric',
      BlockKind.section => 'Section $sectionLevel',
      BlockKind.synopsis => 'Synopsis',
      BlockKind.note => 'Note',
      BlockKind.pageBreak => 'Page break',
      BlockKind.opaque => 'Verbatim',
    };
