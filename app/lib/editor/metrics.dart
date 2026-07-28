import 'package:slugline/core/document_core.dart';

/// The printed page, as the editor has to draw it.
///
/// US Letter at 12 pt Courier. Screenplay typography is a fixed monospace grid
/// (§5.1): ten characters to the inch across and six lines to the inch down, so
/// every measurement here is exact and an inch is a count of cells rather than a
/// number of pixels. That is what makes the whole page scale with the text size
/// preference without a single hard-coded pixel anywhere: pick an [advance] and
/// a [lineHeight] and the rest of the sheet follows.
///
/// **The inch constants are the source of truth and the columns are derived from
/// them.** `ElementMetrics` below reads its indents out of this class, which is
/// what stops a "2.2 inches" in a comment from drifting away from a `22` in a
/// table. The derived columns are the same numbers `layout::metrics` holds in
/// Rust, and `test/editor/line_break_differential_test.dart` is what keeps the
/// two copies honest — see ADR 0018 for why there are two.
class ScreenplayMetrics {
  const ScreenplayMetrics({required this.advance, required this.lineHeight});

  /// The width of one character cell, measured from the editor's own font.
  final double advance;

  /// The height of one grid row on screen.
  final double lineHeight;

  // --- the grid ------------------------------------------------------------

  /// §5.1: ten characters to the inch.
  static const double charactersPerInch = 10;

  /// §5.1: six lines to the inch.
  static const double linesPerInch = 6;

  // --- the sheet, in inches ------------------------------------------------

  static const double paperWidthInches = 8.5;
  static const double paperHeightInches = 11;

  /// §5.2: the text area begins 1.5 inches from the page's left edge and ends
  /// 7.5 inches across it, one inch from the right.
  static const double leftMarginInches = 1.5;
  static const double rightMarginInches = 1;
  static const double topMarginInches = 1;
  static const double bottomMarginInches = 1;

  /// The measure every element is laid out against: 8.5 − 1.5 − 1.0 inches.
  static const double textWidthInches =
      paperWidthInches - leftMarginInches - rightMarginInches;

  /// The measure in cells — 60 columns, the width every element wraps within.
  static const int textColumns = 60;

  /// `layout::metrics::US_LETTER_LINES_PER_PAGE`, derived there from the sheet
  /// and its margins rather than written down: (11 − 1 − 1) inches × 6 lines.
  ///
  /// Fifty-four, not the fifty-five a page is often said to hold; the extra line
  /// in that count is the page number, which sits in the top margin.
  static const int linesPerPage = 54;

  /// §5.2: the page number sits half an inch above the text area — three grid
  /// rows up — and is right-aligned to the measure's right edge.
  static const int pageNumberRow = -3;

  // --- inches to cells -----------------------------------------------------

  /// Columns spanned by [inches] of text. Exact: ten cells to the inch.
  static int columnsIn(double inches) => (inches * charactersPerInch).round();

  /// Rows spanned by [inches] of page. Exact: six rows to the inch.
  static int rowsIn(double inches) => (inches * linesPerInch).round();

  // --- cells to pixels -----------------------------------------------------

  /// The width of [inches] of text on screen.
  double across(double inches) => columnsIn(inches) * advance;

  /// The height of [inches] of page on screen.
  double down(double inches) => rowsIn(inches) * lineHeight;

  /// The content column: 6.0 inches of text, and nothing wider.
  double get textWidth => textColumns * advance;

  /// The whole sheet, for the paper surface page view draws.
  double get paperWidth => paperWidthInches * charactersPerInch * advance;
  double get paperHeight => paperHeightInches * linesPerInch * lineHeight;

  /// Where the text area sits within the sheet.
  double get leftMargin => across(leftMarginInches);
  double get topMargin => down(topMarginInches);

  /// The body of one page: the rows a paginated page can hold.
  double get pageBodyHeight => linesPerPage * lineHeight;

  /// Air around the content column in continuous view, and between sheets in
  /// page view. Half an inch of page, so it scales with the text size like
  /// everything else.
  double get gutter => down(0.5);

  /// The widest the content column is ever allowed to become.
  ///
  /// The measure is already fixed — 60 cells of a monospace face — so this is
  /// not what stops the text stretching on a wide monitor; the grid is. It is a
  /// backstop for the other direction: a font whose fallback resolves to
  /// something much wider than Courier would otherwise push the column past the
  /// viewport and take the caret arithmetic off screen with it.
  static const double maxColumnWidth = 1100;

  @override
  bool operator ==(Object other) =>
      other is ScreenplayMetrics &&
      other.advance == advance &&
      other.lineHeight == lineHeight;

  @override
  int get hashCode => Object.hash(advance, lineHeight);
}

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

  /// The same element, written the way §5.2 writes it: as a fraction of the
  /// 6-inch measure, relative to the left text margin.
  ///
  /// [indentInches] and [widthInches] go through [ScreenplayMetrics.columnsIn],
  /// so the table below reads as inches and every consumer still gets exact
  /// cells. There is no rounding to worry about — at ten characters to the inch
  /// each of these lands on a whole column — but the conversion lives in one
  /// place regardless, so a change to the grid cannot leave a stale column count
  /// behind in a widget.
  ElementMetrics.inches({
    required double indentInches,
    required double widthInches,
    required this.blankLinesBefore,
    this.alignment = ColumnAlignment.left,
    this.upperCase = false,
  })  : indent = ScreenplayMetrics.columnsIn(indentInches),
        width = ScreenplayMetrics.columnsIn(widthInches);

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

/// §5.2's table, in inches relative to the left text margin.
///
/// Every indent is a fraction of [ScreenplayMetrics.textWidthInches], so the
/// whole layout is one measure and a set of offsets into it. Column zero is the
/// left margin (1.5" on the page) and 6.0" is its right edge.
///
/// The blank-line counts are **not** uniform, and the two exceptions are the
/// point rather than an oversight: dialogue and a parenthetical follow their cue
/// with no gap, because a blank line there would break the block apart, and a
/// scene heading takes two so that a scene reads as a new one. Everything else
/// takes one. `layout::metrics` holds the same counts and the goldens are
/// pinned to them.
///
/// Sections, synopses and notes are not in §5.2 because they are never printed.
/// They are editor-only, and sit at the left margin so that they read as
/// scaffolding rather than as script.
final Map<BlockKind, ElementMetrics> elementMetrics = {
  // Scene heading — at the margin, the full measure, two blank lines before.
  BlockKind.sceneHeading: ElementMetrics.inches(
    indentInches: 0,
    widthInches: ScreenplayMetrics.textWidthInches,
    blankLinesBefore: 2,
    upperCase: true,
  ),
  // Action — at the margin, the full measure.
  BlockKind.action: ElementMetrics.inches(
    indentInches: 0,
    widthInches: ScreenplayMetrics.textWidthInches,
    blankLinesBefore: 1,
  ),
  // Character — 2.2" in, 3.3" wide.
  BlockKind.character: ElementMetrics.inches(
    indentInches: 2.2,
    widthInches: 3.3,
    blankLinesBefore: 1,
    upperCase: true,
  ),
  // Dialogue — 1.0" in, 3.5" wide, no blank line: it follows its cue.
  BlockKind.dialogue: ElementMetrics.inches(
    indentInches: 1,
    widthInches: 3.5,
    blankLinesBefore: 0,
  ),
  // Parenthetical — 1.6" in, 2.6" wide, tucked under the cue with no gap.
  BlockKind.parenthetical: ElementMetrics.inches(
    indentInches: 1.6,
    widthInches: 2.6,
    blankLinesBefore: 0,
  ),
  // Transition — right-aligned to the measure's 6.0" edge.
  BlockKind.transition: ElementMetrics.inches(
    indentInches: 0,
    widthInches: ScreenplayMetrics.textWidthInches,
    blankLinesBefore: 1,
    alignment: ColumnAlignment.right,
    upperCase: true,
  ),
  // Centered — centred within the measure.
  BlockKind.centered: ElementMetrics.inches(
    indentInches: 0,
    widthInches: ScreenplayMetrics.textWidthInches,
    blankLinesBefore: 1,
    alignment: ColumnAlignment.centre,
  ),
  // Lyric — as dialogue, but set off by a blank line.
  BlockKind.lyric: ElementMetrics.inches(
    indentInches: 1,
    widthInches: 3.5,
    blankLinesBefore: 1,
  ),
  BlockKind.section: _scaffolding,
  BlockKind.synopsis: _scaffolding,
  BlockKind.note: _scaffolding,
  BlockKind.pageBreak: _scaffolding,
  BlockKind.opaque: _scaffolding,
};

/// The editor-only elements: at the margin, across the whole measure.
final ElementMetrics _scaffolding = ElementMetrics.inches(
  indentInches: 0,
  widthInches: ScreenplayMetrics.textWidthInches,
  blankLinesBefore: 1,
);

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
