import 'dart:math' as math;

import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_indicator.dart';

/// How the editor's rows and columns become pixels.
///
/// Everything that has to turn a grid position into a coordinate goes through
/// this: the painter, the hit testing, the caret scrolling, the semantics band
/// and the completion popup. That is the whole reason it exists. The row-to-y
/// arithmetic used to be spelled out at each of those call sites, and page view
/// needs to put a gap between one page and the next — a change that is one line
/// here and six subtly different lines if the arithmetic stays scattered.
///
/// [ScreenplayMetrics] owns the printed grid; this owns where that grid lands in
/// the viewport. No pixel measurement below is a literal: each one is an inch of
/// page, so the whole surface scales with the text-size preference.
class EditorGeometry {
  EditorGeometry({
    required this.metrics,
    required this.viewportWidth,
    required this.totalRows,
    this.pageStarts = const [],
    this.pageView = false,
  });

  final ScreenplayMetrics metrics;
  final double viewportWidth;
  final int totalRows;

  /// Where the paginator put each page break, in editor rows, ascending.
  ///
  /// Empty until Rust has paginated — and in a widget test with no pagination at
  /// all, which then simply draws no page furniture.
  final List<PageStart> pageStarts;

  /// Whether to draw discrete sheets. Continuous scroll is the default and is
  /// the mode this geometry degrades to when there are no [pageStarts].
  final bool pageView;

  double get advance => metrics.advance;
  double get lineHeight => metrics.lineHeight;

  /// Whether sheets are actually being drawn, as opposed to merely asked for.
  /// Page view with nothing paginated yet is continuous scroll until the first
  /// snapshot lands.
  bool get sheeted => pageView && pageStarts.isNotEmpty;

  /// The width of the content column: 6.0 inches of text and never more.
  ///
  /// The measure is fixed by the grid, so this does not stretch on a wide
  /// monitor. The clamp is the backstop [ScreenplayMetrics.maxColumnWidth]
  /// describes, and the second one keeps the column inside a viewport too narrow
  /// to hold it rather than letting it run off the edge.
  double get columnWidth => math.min(
    math.min(metrics.textWidth, ScreenplayMetrics.maxColumnWidth),
    math.max(advance, viewportWidth - 2 * minimumSideMargin),
  );

  /// The narrowest strip of air left beside the column before it is allowed to
  /// start shrinking. A quarter of an inch of page.
  double get minimumSideMargin => metrics.across(0.25);

  /// The left edge of the text column, centred in the viewport.
  double get columnLeft => ((viewportWidth - columnWidth) / 2)
      .clamp(0.0, math.max(0.0, viewportWidth - columnWidth));

  /// The right edge of the text column — the 6.0-inch mark.
  double get columnRight => columnLeft + columnWidth;

  /// The sheet's left edge, 1.5 inches to the left of the text column. Only
  /// meaningful when [sheeted]; in continuous view there is no sheet.
  double get sheetLeft => columnLeft - metrics.leftMargin;

  double get sheetWidth => metrics.paperWidth;

  /// Air above the first row. One inch of page in page view, so the first sheet
  /// has its top margin; half an inch otherwise.
  double get topPadding => metrics.down(sheeted ? 1 : 0.5);

  /// The space between two sheets, and the bottom and top margins they bring
  /// with them. Two inches of margin plus half an inch of shadowed air.
  double get pageGap => metrics.down(sheeted ? 2.5 : 1.5);

  /// The y coordinate of the top of a visual row.
  double yOfRow(int row) =>
      topPadding + row * lineHeight + _breaksBefore(row) * pageGap;

  /// The visual row containing a y coordinate. The inverse of [yOfRow], and it
  /// has to be exact: this is what a click becomes.
  ///
  /// A point in the margin between two sheets is in no row at all, and goes to
  /// whichever line it is nearer.
  int rowAtY(double y) => _rowAt(
    y,
    inGap: (start, over) => over < pageGap / 2 ? start.row - 1 : start.row,
  );

  /// The rows to paint for a viewport spanning [top] to [bottom], with a row of
  /// margin either side so a partially scrolled row is never half-drawn.
  ///
  /// Painting and the semantics band both ask for this, and neither may work it
  /// out from [rowAtY]. The gap between two sheets belongs to no row, so a naive
  /// `rowAtY(bottom)` answers with a row well above the fold and the rows in
  /// between — which are on screen, above the gap — go unpainted until the
  /// scroll moves the edge off the gap again.
  ({int first, int last}) rowBand(double top, double bottom) => (
    // A point in a gap resolves *backwards* at the top edge and *forwards* at
    // the bottom edge, so the band always errs outwards and never clips.
    first: math.max(0, _rowAt(top, inGap: (start, _) => start.row - 1) - 1),
    last: math.min(
      totalRows,
      _rowAt(bottom, inGap: (start, _) => start.row) + 2,
    ),
  );

  /// Walks the breaks above [y]. [inGap] is consulted only when [y] lands in the
  /// margin between two sheets, and is given the break and how far into its gap
  /// the point is.
  int _rowAt(double y, {required int Function(PageStart, double) inGap}) {
    var breaks = 0;
    if (sheeted) {
      // Ascending, so the first break that starts below the point ends the
      // search. At most a few hundred entries.
      for (final start in pageStarts) {
        final gapTop = topPadding + start.row * lineHeight + breaks * pageGap;
        if (y < gapTop) break;
        breaks++;
        if (y < gapTop + pageGap) return inGap(start, y - gapTop);
      }
    }
    return ((y - topPadding - breaks * pageGap) / lineHeight).floor();
  }

  /// The total height of the scrollable content.
  double get contentHeight =>
      yOfRow(totalRows) + (sheeted ? metrics.down(1) : metrics.down(0.5));

  int _breaksBefore(int row) {
    if (!sheeted) return 0;
    var count = 0;
    for (final start in pageStarts) {
      if (start.row > row) break;
      count++;
    }
    return count;
  }

  /// The sheets to paint, as `(top, bottom, page number)` in content
  /// coordinates. Empty unless [sheeted].
  ///
  /// A sheet runs from one page break to the next, with its one-inch margins
  /// around the rows between them. Its height therefore follows the text rather
  /// than being a rigid eleven inches, and that is deliberate: the editor is
  /// fluid, sections and synopses occupy editor rows that never reach paper, and
  /// a fixed sheet would have to either clip them or lie about where they sit.
  Iterable<({double top, double bottom, int number})> sheets() sync* {
    if (!sheeted) return;
    final margin = metrics.down(1);
    var startRow = 0;
    var number = pageStarts.first.number - 1;
    for (final start in pageStarts) {
      yield (
        top: yOfRow(startRow) - margin,
        bottom: yOfRow(start.row) - pageGap + margin,
        number: number,
      );
      startRow = start.row;
      number = start.number;
    }
    yield (
      top: yOfRow(startRow) - margin,
      bottom: yOfRow(totalRows) + margin,
      number: number,
    );
  }

  /// The page breaks to rule, as `(y, page number)`, where the number is the
  /// page **beginning** at that line. Empty in page view, where the gap between
  /// sheets says the same thing.
  Iterable<({double y, int number})> rules() sync* {
    if (sheeted || pageStarts.isEmpty) return;
    for (final start in pageStarts) {
      yield (y: yOfRow(start.row) - lineHeight / 2, number: start.number);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EditorGeometry &&
      other.metrics == metrics &&
      other.viewportWidth == viewportWidth &&
      other.totalRows == totalRows &&
      other.pageView == pageView &&
      _sameStarts(other.pageStarts, pageStarts);

  @override
  int get hashCode => Object.hash(
    metrics,
    viewportWidth,
    totalRows,
    pageView,
    pageStarts.length,
    pageStarts.isEmpty ? 0 : pageStarts.last.row,
  );

  static bool _sameStarts(List<PageStart> a, List<PageStart> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
