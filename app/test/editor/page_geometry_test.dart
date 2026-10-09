import 'package:flutter/material.dart' show kMinInteractiveDimension;
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';
import 'package:slugline/editor/page_indicator.dart';

const _metrics = ScreenplayMetrics(advance: 9, lineHeight: 21);

EditorGeometry _geometry({
  double viewportWidth = 900,
  int totalRows = 300,
  int? firstPage,
  List<PageStart> pageStarts = const [],
  bool pageView = false,
  double topInset = 0,
}) => EditorGeometry(
  metrics: _metrics,
  viewportWidth: viewportWidth,
  totalRows: totalRows,
  firstPage: firstPage,
  pageStarts: pageStarts,
  pageView: pageView,
  topInset: topInset,
);

/// A script of three pages, as the indicator hands it over: the page it opens
/// on, and where the other two begin.
const _first = 1;
const _starts = [PageStart(row: 54, number: 2), PageStart(row: 110, number: 3)];

void main() {
  test('a top inset moves every row down by itself and nothing else', () {
    // What the find bar covers while it is up. A click still has to land on
    // the row it was aimed at, sheets and all.
    for (final pageView in [false, true]) {
      final plain = _geometry(
        firstPage: _first,
        pageStarts: _starts,
        pageView: pageView,
      );
      final inset = _geometry(
        firstPage: _first,
        pageStarts: _starts,
        pageView: pageView,
        topInset: 150,
      );
      for (final row in [0, 53, 54, 109, 110, 299]) {
        expect(inset.yOfRow(row), plain.yOfRow(row) + 150);
        expect(inset.rowAtY(inset.yOfRow(row) + 1), row);
      }
      expect(inset.contentHeight, plain.contentHeight + 150);
      expect(inset.sheets().map((sheet) => sheet.top), [
        for (final sheet in plain.sheets()) sheet.top + 150,
      ]);
      expect(inset.columnLeft, plain.columnLeft);
      expect(inset, isNot(plain));
    }
  });

  group('the measure', () {
    test('is six inches of text and does not stretch with the viewport', () {
      // Sixty columns is the whole point: a wider window buys more margin, not
      // a wider line. A screenplay page holds the same words at any window size.
      for (final width in [700.0, 900.0, 1600.0, 3840.0]) {
        expect(_geometry(viewportWidth: width).columnWidth, 60 * 9);
      }
    });

    test('is centred in the viewport', () {
      final geometry = _geometry(viewportWidth: 1600);
      expect(geometry.columnLeft, (1600 - 540) / 2);
      expect(geometry.columnRight, geometry.columnLeft + 540);
    });

    test('stays inside a viewport too narrow to hold it', () {
      final geometry = _geometry(viewportWidth: 300);
      expect(geometry.columnLeft, greaterThanOrEqualTo(0));
      expect(geometry.columnRight, lessThanOrEqualTo(300));
    });

    test('is capped so a fallback face cannot push it off screen', () {
      final geometry = EditorGeometry(
        // A face three times Courier's width, which no grid should honour.
        metrics: const ScreenplayMetrics(advance: 40, lineHeight: 21),
        viewportWidth: 4000,
        totalRows: 10,
      );
      expect(geometry.columnWidth, ScreenplayMetrics.maxColumnWidth);
    });
  });

  group('continuous scroll', () {
    test('keeps fitted horizontal placement with a scrollbar reserve', () {
      for (final width in [640.0, 800.0, 812.0, 900.0, 1280.0, 3840.0]) {
        final metrics = ScreenplayMetrics.forFontSize(
          ScreenplayMetrics.fittedFontSize(
            preferredFontSize: 15,
            viewportWidth: width,
            pageView: false,
          ),
        );
        for (final starts in [const <PageStart>[], _starts]) {
          final geometry = EditorGeometry(
            metrics: metrics,
            viewportWidth: width,
            totalRows: 300,
            firstPage: starts.isEmpty ? null : _first,
            pageStarts: starts,
            scrollbarWidth: kMinInteractiveDimension,
          );
          final usable = width - kMinInteractiveDimension;
          final expectedLeft = ((usable - geometry.columnWidth) / 2).clamp(
            0.0,
            usable - geometry.columnWidth,
          );
          expect(geometry.columnLeft, expectedLeft, reason: 'width $width');
          expect(geometry.sheeted, isFalse);
          expect(geometry.topPadding, metrics.down(0.5));
          expect(geometry.pageGap, metrics.down(1.5));
        }
      }
    });

    test('rows are evenly spaced whatever the pagination says', () {
      final geometry = _geometry(firstPage: _first, pageStarts: _starts);
      expect(geometry.sheeted, isFalse);
      for (final row in [0, 1, 53, 54, 55, 200]) {
        expect(
          geometry.yOfRow(row) - geometry.yOfRow(0),
          row * 21,
          reason: 'row $row',
        );
      }
    });

    test('a page break is a rule, and the first page has none above it', () {
      final rules = _geometry(
        firstPage: _first,
        pageStarts: _starts,
      ).rules().toList();
      expect(rules.map((rule) => rule.number), [2, 3]);
      expect(rules.first.y, closeTo(_geometry().yOfRow(54) - 10.5, 0.001));
      expect(
        _geometry(firstPage: _first, pageStarts: _starts).sheets(),
        isEmpty,
      );
    });

    test('draws nothing at all before the first pagination arrives', () {
      expect(_geometry().rules(), isEmpty);
      expect(_geometry().sheets(), isEmpty);
    });

    test('a script of one page has nothing to rule', () {
      final geometry = _geometry(firstPage: _first);
      expect(geometry.sheeted, isFalse);
      expect(geometry.rules(), isEmpty);
      expect(geometry.sheets(), isEmpty);
      expect(geometry.topPadding, _metrics.down(0.5));
    });
  });

  group('page view', () {
    for (final preferredSize in [15.0, 24.0]) {
      for (final width in [640.0, 800.0, 812.0, 900.0, 1280.0, 3840.0]) {
        test('centres fitted sheets at width $width, size $preferredSize', () {
          const tolerance = 1e-7;
          final metrics = ScreenplayMetrics.forFontSize(
            ScreenplayMetrics.fittedFontSize(
              preferredFontSize: preferredSize,
              viewportWidth: width,
              pageView: true,
            ),
          );
          final before = EditorGeometry(
            metrics: metrics,
            viewportWidth: width,
            totalRows: 300,
            pageView: true,
            scrollbarWidth: kMinInteractiveDimension,
          );
          final after = EditorGeometry(
            metrics: metrics,
            viewportWidth: width,
            totalRows: 300,
            firstPage: _first,
            pageStarts: _starts,
            pageView: true,
            scrollbarWidth: kMinInteractiveDimension,
          );
          final leftGap = after.sheetLeft;
          final rightGap = width - after.sheetLeft - after.sheetWidth;
          expect(after.sheetWidth, lessThanOrEqualTo(width + tolerance));
          expect(leftGap, greaterThanOrEqualTo(-tolerance));
          expect(rightGap, greaterThanOrEqualTo(-tolerance));
          expect(
            (leftGap - rightGap).abs(),
            lessThanOrEqualTo(kMinInteractiveDimension + tolerance),
          );
          expect(
            after.columnLeft,
            closeTo(leftGap + metrics.leftMargin, tolerance),
          );
          expect(after.sheetLeft, before.sheetLeft);
          expect(after.columnLeft, before.columnLeft);
          expect(after.columnRight, before.columnRight);
          expect(before.sheeted, isFalse);
          expect(after.sheeted, isTrue);
          // Pagination changes vertical furniture only, not the grid's x origin.
          expect(before.topPadding, metrics.down(0.5));
          expect(after.topPadding, metrics.down(1));
        });
      }
    }

    test('retains narrow and fallback column bounds', () {
      for (final (metrics, width) in [
        (_metrics, 300.0),
        (_metrics, 100.0),
        (const ScreenplayMetrics(advance: 40, lineHeight: 21), 4000.0),
      ]) {
        final geometry = EditorGeometry(
          metrics: metrics,
          viewportWidth: width,
          totalRows: 10,
          pageView: true,
          scrollbarWidth: kMinInteractiveDimension,
        );
        expect(geometry.columnLeft, greaterThanOrEqualTo(0));
        expect(
          geometry.columnRight,
          lessThanOrEqualTo(width - kMinInteractiveDimension),
        );
        expect(
          geometry.columnWidth,
          lessThanOrEqualTo(ScreenplayMetrics.maxColumnWidth),
        );
      }
    });

    test('falls back to continuous until there is a pagination to draw', () {
      final geometry = _geometry(pageView: true);
      expect(geometry.sheeted, isFalse);
      expect(geometry.yOfRow(54) - geometry.yOfRow(0), 54 * 21);
    });

    test('a script of one page is one sheet, with no break in it', () {
      // Every new script: a first page and no page starts. The sheet is the
      // rows with an inch of margin either side, as any other sheet is.
      final geometry = _geometry(
        firstPage: _first,
        pageView: true,
        totalRows: 12,
      );
      expect(geometry.sheeted, isTrue);
      expect(geometry.topPadding, _metrics.down(1));
      final sheet = geometry.sheets().single;
      expect(sheet.number, 1);
      expect(sheet.top, 0);
      expect(sheet.bottom, geometry.yOfRow(12) + _metrics.down(1));
      expect(geometry.contentHeight, sheet.bottom);
      expect(geometry.rules(), isEmpty);
      for (var row = 0; row < 12; row++) {
        expect(geometry.yOfRow(row) - geometry.yOfRow(0), row * 21);
        expect(geometry.rowAtY(geometry.yOfRow(row) + 1), row);
      }
      // What the surface rebuilds on when the pagination lands.
      expect(geometry, isNot(_geometry(pageView: true, totalRows: 12)));
    });

    test('every page break costs exactly one gap', () {
      final geometry = _geometry(
        firstPage: _first,
        pageStarts: _starts,
        pageView: true,
      );
      expect(geometry.sheeted, isTrue);
      final gap = geometry.pageGap;
      expect(geometry.yOfRow(53) - geometry.yOfRow(0), 53 * 21);
      expect(geometry.yOfRow(54) - geometry.yOfRow(0), 54 * 21 + gap);
      expect(geometry.yOfRow(109) - geometry.yOfRow(0), 109 * 21 + gap);
      expect(geometry.yOfRow(110) - geometry.yOfRow(0), 110 * 21 + 2 * gap);
    });

    test('a sheet per page, in order, with the first numbered one', () {
      final sheets = _geometry(
        firstPage: _first,
        pageStarts: _starts,
        pageView: true,
      ).sheets().toList();
      expect(sheets.map((sheet) => sheet.number), [1, 2, 3]);
      for (final sheet in sheets) {
        expect(sheet.bottom, greaterThan(sheet.top));
      }
      for (var i = 1; i < sheets.length; i++) {
        expect(sheets[i].top, greaterThan(sheets[i - 1].bottom));
      }
      expect(
        _geometry(
          firstPage: _first,
          pageStarts: _starts,
          pageView: true,
        ).rules(),
        isEmpty,
      );
    });
  });

  group('the paint band', () {
    // The regression this group exists for: a viewport edge that lands in the
    // margin between two sheets is in no row at all, and resolving it as if it
    // were one put the band's bottom well above the fold. Every row still
    // visible above that gap went unpainted — text vanished at the bottom of a
    // page and came back a scroll later.
    for (final (name, geometry) in [
      ('continuous', _geometry(totalRows: 200)),
      (
        'continuous with breaks',
        _geometry(totalRows: 200, firstPage: _first, pageStarts: _starts),
      ),
      (
        'page view',
        _geometry(
          totalRows: 200,
          firstPage: _first,
          pageStarts: _starts,
          pageView: true,
        ),
      ),
    ]) {
      test('$name covers every row on screen, at every scroll offset', () {
        const viewportHeight = 600.0;
        for (var top = 0.0; top < geometry.contentHeight; top += 3) {
          final bottom = top + viewportHeight;
          final band = geometry.rowBand(top, bottom);
          for (var row = 0; row < 200; row++) {
            final rowTop = geometry.yOfRow(row);
            if (rowTop + geometry.lineHeight <= top || rowTop >= bottom) {
              continue;
            }
            expect(
              row,
              inInclusiveRange(band.first, band.last),
              reason: 'row $row is on screen at offset $top but outside $band',
            );
          }
        }
      });
    }

    test('stays a band and does not become the whole document', () {
      final geometry = _geometry(
        totalRows: 5000,
        firstPage: _first,
        pageStarts: [
          for (var page = 2; page <= 90; page++)
            PageStart(row: (page - 1) * 54, number: page),
        ],
        pageView: true,
      );
      final band = geometry.rowBand(20000, 20600);
      expect(
        band.last - band.first,
        lessThan(80),
        reason: 'a 120-page script must still cost one screen to paint',
      );
    });
  });

  group('rowAtY inverts yOfRow', () {
    // This is the one that matters: `rowAtY` is what a click becomes, and a
    // gap between sheets that the forward mapping knows about and the reverse
    // does not is a caret that lands on the wrong line.
    for (final (name, geometry) in [
      ('continuous', _geometry()),
      (
        'continuous with breaks',
        _geometry(firstPage: _first, pageStarts: _starts),
      ),
      (
        'page view',
        _geometry(firstPage: _first, pageStarts: _starts, pageView: true),
      ),
    ]) {
      test(name, () {
        for (var row = 0; row < 200; row++) {
          final top = geometry.yOfRow(row);
          expect(geometry.rowAtY(top), row, reason: 'top of row $row');
          expect(geometry.rowAtY(top + 20.9), row, reason: 'end of row $row');
        }
      });
    }
  });

  test('rowAtY inverts yOfRow at the sizes a window fits the script to', () {
    // A fitted row is not a whole number of pixels, and neither is a gap. The
    // top of a row, as a double, can then come back a hair short of itself —
    // and the row a view is parked on is asked for at exactly that point.
    for (final width in [640.0, 800.0, 1280.0, 1400.0, 1920.0]) {
      for (final preferred in [12.0, 15.0, 18.0, 24.0]) {
        for (final pageView in [false, true]) {
          final geometry = EditorGeometry(
            metrics: ScreenplayMetrics.forFontSize(
              ScreenplayMetrics.fittedFontSize(
                preferredFontSize: preferred,
                viewportWidth: width,
                pageView: pageView,
              ),
            ),
            viewportWidth: width,
            totalRows: 6600,
            firstPage: 1,
            pageStarts: [
              for (var page = 2; page <= 120; page++)
                PageStart(row: (page - 1) * 54, number: page),
            ],
            pageView: pageView,
            scrollbarWidth: kMinInteractiveDimension,
          );
          for (var row = 0; row < 6600; row++) {
            expect(
              geometry.rowAtY(geometry.yOfRow(row)),
              row,
              reason: 'row $row at width $width, size $preferred, $pageView',
            );
          }
        }
      }
    }
  });

  group('the element table', () {
    // The inch measurements §5.2 gives, and the columns they must come to.
    // `layout::metrics` holds the same numbers in Rust and the corpus-wide
    // differential test compares the wrapping; this compares the table itself,
    // so a mistyped inch value fails here rather than as a mysterious wrap.
    const expected = {
      BlockKind.sceneHeading: (0, 60),
      BlockKind.action: (0, 60),
      BlockKind.character: (22, 33),
      BlockKind.parenthetical: (16, 20),
      BlockKind.dialogue: (10, 35),
      BlockKind.transition: (0, 60),
      BlockKind.lyric: (10, 35),
    };

    expected.forEach((kind, columns) {
      test('$kind sits at ${columns.$1} and is ${columns.$2} wide', () {
        final metrics = metricsFor(kind);
        expect((metrics.indent, metrics.width), columns);
      });
    });

    test('every element fits inside the six-inch measure', () {
      for (final metrics in elementMetrics.values) {
        expect(
          metrics.indent + metrics.width,
          lessThanOrEqualTo(ScreenplayMetrics.textColumns),
          reason: 'an element that overhangs the measure would print off page',
        );
      }
    });

    test('an inch is ten columns and a page is fifty-four rows', () {
      expect(ScreenplayMetrics.columnsIn(1), 10);
      expect(ScreenplayMetrics.columnsIn(2.2), 22);
      expect(ScreenplayMetrics.rowsIn(1), 6);
      expect(
        ScreenplayMetrics.textWidthInches,
        ScreenplayMetrics.textColumns / ScreenplayMetrics.charactersPerInch,
      );
      // `layout::metrics::US_LETTER_LINES_PER_PAGE`, derived there from
      // (11 − 1 − 1) inches at six lines to the inch.
      expect(ScreenplayMetrics.linesPerPage, 54);
    });
  });
}
