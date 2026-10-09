// The vertical grid: one row is one line, and one line is a sixth of an inch.
//
// `line_layout_test.dart` covers where a line breaks; this covers how tall it
// is once it has. The two questions meet in `ScreenplayMetrics.lineHeightRatio`,
// which is the only number on the surface that can put a screenplay out of
// proportion without moving a single character sideways — so it is asserted
// here against the sheet it is derived from rather than against itself.

import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/line_layout.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';

/// A script size with nothing special about it. Every assertion below is a
/// ratio or a row count, so the size is arbitrary and only has to be real.
const _fontSize = 12.0;
final _metrics = ScreenplayMetrics.forFontSize(_fontSize);

BlockView _block(BlockKind kind, String text, {int id = 1}) => BlockView(
  id: id,
  kind: kind,
  sectionLevel: 0,
  text: text,
  forced: false,
  dual: false,
  readOnly: false,
  inlineRuns: const [],
);

/// The geometry a document of [totalRows] rows is drawn through, in continuous
/// view — no `pageStarts`, so no sheet gaps land inside a measurement.
EditorGeometry _geometry(int totalRows) => EditorGeometry(
  metrics: _metrics,
  viewportWidth: 1600,
  totalRows: totalRows,
);

/// Text that wraps to exactly [lines] full lines of the measure: each word is
/// the measure wide, so each takes a line of its own and the space between them
/// is dropped at the break.
String _wrappingTo(int lines) =>
    List.filled(lines, 'x' * ScreenplayMetrics.textColumns).join(' ');

void main() {
  group('the row is a sixth of an inch', () {
    test('a row and a column measure the same inch', () {
      // The one assertion the ratio cannot be wrong and still pass. A row is
      // 1/6 inch and a column is 1/10, so a sheet 85 columns across and 66 rows
      // down is US Letter *only* if lineHeight/advance is exactly 10/6. At the
      // old 1.4 this came out at 1.81 — a page a third taller than paper.
      expect(
        _metrics.paperHeight / _metrics.paperWidth,
        closeTo(
          ScreenplayMetrics.paperHeightInches /
              ScreenplayMetrics.paperWidthInches,
          1e-9,
        ),
      );
      expect(
        _metrics.lineHeight / _metrics.advance,
        closeTo(
          ScreenplayMetrics.charactersPerInch / ScreenplayMetrics.linesPerInch,
          1e-9,
        ),
      );
    });

    test('the script is set solid — no leading on top of the face', () {
      // Courier Prime's own metrics carry the leading; the grid does not add a
      // second helping. A row is the size, to within the sixth of a percent
      // that separates the face's 1228/2048 advance from a round 0.6.
      expect(ScreenplayMetrics.lineHeightRatio, greaterThan(0.99));
      expect(ScreenplayMetrics.lineHeightRatio, lessThanOrEqualTo(1.1));
      expect(_metrics.lineHeight, closeTo(_fontSize, 0.01));
    });

    test('the editor and the preview agree about a row', () {
      // `PreviewGeometry.row` is `scale * 10 / 6` against a column of `scale`.
      // The editor reaches the same place from the other side, and this is what
      // says so: the two surfaces draw one page.
      final column = _metrics.advance;
      expect(_metrics.lineHeight, closeTo(column * 10 / 6, 1e-9));
    });
  });

  group('within a paragraph', () {
    test('wrapped lines are single spaced', () {
      // Nothing between line two and line three of an action paragraph but the
      // row pitch — no per-line padding, no leading that accumulates down a
      // long paragraph.
      final layout = DocumentLayout([_block(BlockKind.action, _wrappingTo(8))]);
      expect(layout.linesOf(0).length, 8);

      final geometry = _geometry(layout.totalRows);
      for (var row = 1; row < 8; row++) {
        expect(
          geometry.yOfRow(row) - geometry.yOfRow(row - 1),
          closeTo(_metrics.lineHeight, 1e-9),
        );
      }
    });

    test('a paragraph is exactly as tall as its lines', () {
      final layout = DocumentLayout([
        _block(BlockKind.action, _wrappingTo(12)),
      ]);
      final geometry = _geometry(layout.totalRows);
      expect(
        geometry.yOfRow(layout.endRowOf(0)) - geometry.yOfRow(0),
        closeTo(12 * _metrics.lineHeight, 1e-9),
      );
    });
  });

  group('between elements', () {
    test('separation is exactly one line height', () {
      // §5.2's blank line, measured as a distance rather than trusted as a
      // count: the top of the second paragraph sits one line below the bottom
      // of the first, and the blank row is the whole of the gap.
      final layout = DocumentLayout([
        _block(BlockKind.action, 'First.', id: 1),
        _block(BlockKind.action, 'Second.', id: 2),
      ]);
      final geometry = _geometry(layout.totalRows);

      final firstEnds = geometry.yOfRow(layout.firstRowOf(0) + 1);
      final secondBegins = geometry.yOfRow(layout.firstRowOf(1));
      expect(secondBegins - firstEnds, closeTo(_metrics.lineHeight, 1e-9));
    });

    test(
      'between elements a scene heading takes one and dialogue takes none',
      () {
        // Element separation is exactly one blank line — a bottom margin equal
        // to one line height. Dialogue and parentheticals carry zero because
        // a cue must not come apart from the line it introduces.
        final layout = DocumentLayout([
          _block(BlockKind.action, 'She waits.', id: 1),
          _block(BlockKind.sceneHeading, 'INT. HALL - DAY', id: 2),
          _block(BlockKind.character, 'ANNA', id: 3),
          _block(BlockKind.dialogue, 'Not yet.', id: 4),
        ]);
        final geometry = _geometry(layout.totalRows);

        double gapAbove(int index) =>
            geometry.yOfRow(layout.firstRowOf(index)) -
            geometry.yOfRow(layout.endRowOf(index - 1));

        expect(gapAbove(1), closeTo(_metrics.lineHeight, 1e-9));
        expect(gapAbove(2), closeTo(_metrics.lineHeight, 1e-9));
        expect(gapAbove(3), 0);
      },
    );
  });

  group('a page holds its lines', () {
    test('the body of a page is the rows between the margins', () {
      // 11 inches less an inch of margin at each end, at six lines to the inch.
      // This is where the fifty-four comes from, and why it is not the
      // fifty-five a page is usually said to hold: that count includes the page
      // number, which sits three rows up in the *top margin* and so is not one
      // of the rows a paginator may fill. `layout::metrics` derives the same
      // number the same way.
      expect(
        ScreenplayMetrics.linesPerPage,
        ScreenplayMetrics.rowsIn(
          ScreenplayMetrics.paperHeightInches -
              ScreenplayMetrics.topMarginInches -
              ScreenplayMetrics.bottomMarginInches,
        ),
      );
      expect(ScreenplayMetrics.linesPerPage, 54);
      expect(ScreenplayMetrics.pageNumberRow, lessThan(0));
    });

    test('a full page of text is exactly one page tall', () {
      // The validation the grid exists for: lay out a page's worth of single
      // lines and measure what was rendered, rather than multiplying the row
      // count by the row height and asserting arithmetic. At the old 1.4 this
      // came out at 907 against a page of 648.
      const lines = ScreenplayMetrics.linesPerPage;
      final layout = DocumentLayout([
        _block(BlockKind.action, _wrappingTo(lines)),
      ]);
      expect(layout.totalRows, lines);

      final geometry = _geometry(layout.totalRows);
      final rendered = geometry.yOfRow(layout.totalRows) - geometry.yOfRow(0);

      expect(rendered, closeTo(_metrics.pageBodyHeight, 1e-9));
      expect(rendered, closeTo(_metrics.down(9), 1e-9));
    });

    test('one more line does not fit on the page', () {
      // The other half of the same statement: 54 fills the body, so 55 overruns
      // it. Without this the assertion above would still pass if the page grew.
      final geometry = _geometry(ScreenplayMetrics.linesPerPage + 1);
      final rendered =
          geometry.yOfRow(ScreenplayMetrics.linesPerPage + 1) -
          geometry.yOfRow(0);
      expect(rendered, greaterThan(_metrics.pageBodyHeight));
      expect(
        rendered - _metrics.pageBodyHeight,
        closeTo(_metrics.lineHeight, 1e-9),
      );
    });
  });
}
