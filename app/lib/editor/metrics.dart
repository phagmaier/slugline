import 'dart:math' as math;

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
///
/// **The size follows the measure, not the other way round.** The advance used
/// to be measured off whatever face the system resolved `monospace` to, and the
/// column was then sixty of those wide — so the width of the script was a
/// consequence of a font nobody had chosen, and on a window too narrow to hold
/// the result the column was clamped while the text went on being drawn at its
/// old size and ran off the edge. Now the script face is bundled and its advance
/// is a known fraction of the size ([advanceRatio]), so the arithmetic runs the
/// other way: [fittedFontSize] picks the largest size whose measure fits the
/// viewport, and [ScreenplayMetrics.forColumnWidth] turns a width into the grid
/// that spans it exactly.
class ScreenplayMetrics {
  const ScreenplayMetrics({required this.advance, required this.lineHeight});

  /// The grid the script face draws at [fontSize].
  ScreenplayMetrics.forFontSize(double fontSize)
      : advance = fontSize * advanceRatio,
        lineHeight = fontSize * lineHeightRatio;

  /// The grid whose measure — sixty characters — is exactly [columnWidth] wide.
  ScreenplayMetrics.forColumnWidth(double columnWidth)
      : this.forFontSize(fontSizeForColumn(columnWidth));

  /// The width of one character cell, measured from the editor's own font.
  final double advance;

  /// The height of one grid row on screen.
  final double lineHeight;

  // --- the script face -----------------------------------------------------

  /// The width of one character in the script face, as a fraction of its size.
  ///
  /// Courier Prime advances 1228 units of its 2048-unit em, so a character is
  /// 0.5996 of the point size and the sixty-column measure is 35.977 times it.
  /// `render_pdf` *declares* 600/1000 instead and scales the glyphs onto it,
  /// because a PDF viewer positions text by the widths in the font dictionary
  /// and §5.2 asks for exactly ten characters to the inch on paper. On screen
  /// there is no such indirection — Flutter advances by what the file says — so
  /// this is the file's own number, and `test/editor/script_font_test.dart`
  /// reads it back out of the bundled TTF rather than trusting this line.
  static const double advanceRatio = 1228 / 2048;

  /// Rows to size: one grid row, and not a pixel more.
  ///
  /// This is derived, not chosen. A row is a sixth of an inch and a column is a
  /// tenth, so a row measures ten sixths of a column — and a column is
  /// [advanceRatio] of the size. That is the whole of it: 10/6 × 1228/2048 =
  /// 0.9993, a script set solid. Courier Prime carries a typewriter face's own
  /// leading in its metrics, and a grid row *is* that leading rather than room
  /// to add more on top of it.
  ///
  /// **The number used to be 1.4, and that was not a matter of taste.** Four
  /// tenths of a line added here stretched the sheet: a page is 8.5 × 11 inches
  /// only while a row and a column measure the same inch, and at 1.4 the editor
  /// drew a page half again as tall as the paper it stands for. Everything
  /// downstream inherited it, because everything downstream is [down] — the one
  /// blank line §5.2 puts above an element read as nearly two, and
  /// `PreviewGeometry`, which has always taken a row as ten sixths of a column,
  /// disagreed with the editor about the size of the same page.
  /// `metrics_test.dart` holds the derivation to the sheet rather than to this
  /// line.
  static const double lineHeightRatio =
      advanceRatio * charactersPerInch / linesPerInch;

  /// The size below which the script stops shrinking to fit.
  ///
  /// A window narrow enough to need this is narrower than the editor is usable
  /// at, and the honest answer there is a column that overflows — which
  /// `EditorGeometry.columnWidth` still clamps — rather than a script nobody
  /// can read.
  static const double minimumFontSize = 9;

  /// The size at which sixty characters span [columnWidth] exactly.
  static double fontSizeForColumn(double columnWidth) =>
      columnWidth / (textColumns * advanceRatio);

  /// The inverse: the measure sixty characters span at [fontSize].
  static double columnWidthForFontSize(double fontSize) =>
      textColumns * advanceRatio * fontSize;

  /// The size the script is drawn at in a viewport [viewportWidth] wide.
  ///
  /// [preferredFontSize] is the text-size preference — the largest the writer
  /// asked for. What comes back is that size or the largest one whose page still
  /// fits across the viewport, whichever is smaller, so the size is never a
  /// number that draws the script wider than the window it is in.
  ///
  /// What has to fit is the whole sheet in page view and the measure alone
  /// otherwise, plus [airInches] of margin on each side in both cases — the
  /// column is centred, and a measure that ends exactly at the window edge reads
  /// as clipped whether or not it is.
  ///
  /// [pageView] is the *preference*, not `EditorGeometry.sheeted`. Sheets do not
  /// appear until Rust's first paginated snapshot lands, and keying the size on
  /// that would resize the whole script a moment after the file opened. Page
  /// view reserves the sheet's width from the first frame and the sheets arrive
  /// into a page already the right size.
  static double fittedFontSize({
    required double preferredFontSize,
    required double viewportWidth,
    required bool pageView,
  }) {
    // Counted in whole cells, not in inches then rounded once at the end: the
    // air is `EditorGeometry.minimumSideMargin`, which is itself a whole number
    // of columns, and a fit computed off 6.5 inches would leave the column half
    // a cell wider than that margin allows for.
    final across =
        columnsIn(pageView ? paperWidthInches : textWidthInches) +
        2 * columnsIn(airInches);
    final fits = viewportWidth / (across * advanceRatio);
    return math.max(minimumFontSize, math.min(preferredFontSize, fits));
  }

  /// The air kept beside the script before it starts shrinking. A quarter inch,
  /// the same measure `EditorGeometry.minimumSideMargin` leaves it.
  static const double airInches = 0.25;

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

  /// The size the script face has to be drawn at for [advance] to be its
  /// advance. The inverse of [ScreenplayMetrics.forFontSize], and what every
  /// painter on the surface asks for rather than keeping its own copy.
  double get fontSize => advance / advanceRatio;

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
  /// The measure is already fixed — 60 cells of the script face — so this is not
  /// what stops the text stretching on a wide monitor; the grid is. Nor is it
  /// any longer the backstop against a fallback face wider than Courier, which
  /// is what it was written for: the face is bundled now and [fittedFontSize] is
  /// what keeps the column inside the window. It stays as the last clamp in
  /// `EditorGeometry`, so that a caller which builds metrics by hand — a test,
  /// or a future call site that skips the fit — still cannot take the caret
  /// arithmetic off screen.
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
/// Element separation is exactly one blank line — a bottom margin equal to one
/// line height, not a hardcoded pixel. Dialogue and a parenthetical follow their
/// cue with no gap because a blank line there would break the block apart.
/// `layout::metrics` holds the same counts and the goldens are pinned to them.
///
/// Sections, synopses and notes are not in §5.2 because they are never printed.
/// They are editor-only, and sit at the left margin so that they read as
/// scaffolding rather than as script.
final Map<BlockKind, ElementMetrics> elementMetrics = {
  // Scene heading — at the margin, the full measure, one blank line before.
  BlockKind.sceneHeading: ElementMetrics.inches(
    indentInches: 0,
    widthInches: ScreenplayMetrics.textWidthInches,
    blankLinesBefore: 1,
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
  // Parenthetical — 1.6" in, 2.0" wide, tucked under the cue with no gap.
  BlockKind.parenthetical: ElementMetrics.inches(
    indentInches: 1.6,
    widthInches: 2.0,
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
