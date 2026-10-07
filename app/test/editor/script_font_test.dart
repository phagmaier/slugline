import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/editor/metrics.dart';

/// The script face and the grid derived from it, held to each other.
///
/// [ScreenplayMetrics.advanceRatio] is a literal, and every pixel on the editing
/// surface is derived from it: the column is sixty advances wide, the caret sits
/// at a multiple of one, and a click becomes a column by dividing by one. If the
/// number stopped describing the bundled face, nothing would fail — the script
/// would just quietly stop sitting on its own grid, by a fraction of a character
/// that only shows up sixty columns later.
///
/// So it is not trusted. The TTFs in `fonts/` are the same bytes `render_pdf`
/// compiles in (they are symlinks into `crates/render_pdf/fonts/`), and this
/// reads the advance back out of them.
void main() {
  const faces = [
    'CourierPrime-Regular.ttf',
    'CourierPrime-Bold.ttf',
    'CourierPrime-Italic.ttf',
    'CourierPrime-BoldItalic.ttf',
  ];

  group('the bundled script face', () {
    for (final face in faces) {
      test('$face advances exactly ScreenplayMetrics.advanceRatio', () {
        final file = File('fonts/$face');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'pubspec.yaml declares fonts/$face. A missing file here is a '
              'script drawn in whatever the system resolves instead.',
        );

        final font = _Sfnt(file.readAsBytesSync());
        expect(
          font.advanceRatio,
          ScreenplayMetrics.advanceRatio,
          reason:
              'The face advances ${font.advance}/${font.unitsPerEm} of an em. '
              'Either the font was replaced — in which case the PDF goldens '
              'need regenerating too — or advanceRatio has drifted from it.',
        );
      });
    }

    test('is monospaced: every glyph takes the same advance', () {
      final font = _Sfnt(File('fonts/${faces.first}').readAsBytesSync());
      // Zero is a mark glyph — .notdef and friends — and is not a cell.
      expect(font.advances.difference({0}), {font.advance});
    });
  });

  group('the grid derived from it', () {
    test('sixty characters span the measure exactly', () {
      for (final size in [12.0, 15.0, 18.5, 24.0]) {
        final metrics = ScreenplayMetrics.forFontSize(size);
        expect(
          metrics.textWidth,
          closeTo(ScreenplayMetrics.columnWidthForFontSize(size), 1e-9),
        );
        expect(
          ScreenplayMetrics.fontSizeForColumn(metrics.textWidth),
          closeTo(size, 1e-9),
        );
      }
    });

    test('a column width becomes the size that spans it', () {
      for (final width in [420.0, 540.0, 864.0]) {
        final metrics = ScreenplayMetrics.forColumnWidth(width);
        expect(metrics.textWidth, closeTo(width, 1e-9));
        expect(metrics.fontSize, closeTo(metrics.advance / _ratio, 1e-9));
      }
    });

    test(
      'the preference is a ceiling, and a wide window does not exceed it',
      () {
        expect(
          ScreenplayMetrics.fittedFontSize(
            preferredFontSize: 15,
            viewportWidth: 4000,
            pageView: false,
          ),
          15,
        );
      },
    );

    test('a narrow window shrinks the script instead of clipping it', () {
      const viewport = 400.0;
      final size = ScreenplayMetrics.fittedFontSize(
        preferredFontSize: 24,
        viewportWidth: viewport,
        pageView: false,
      );
      expect(size, lessThan(24));
      // The measure and the quarter inch of air either side, inside the window.
      final metrics = ScreenplayMetrics.forFontSize(size);
      expect(
        metrics.textWidth + 2 * metrics.across(ScreenplayMetrics.airInches),
        closeTo(viewport, 1e-9),
      );
    });

    test('page view fits the sheet, not just the measure', () {
      const viewport = 700.0;
      final size = ScreenplayMetrics.fittedFontSize(
        preferredFontSize: 24,
        viewportWidth: viewport,
        pageView: true,
      );
      final metrics = ScreenplayMetrics.forFontSize(size);
      expect(metrics.paperWidth, lessThanOrEqualTo(viewport));
      // And it is smaller than the same window would give the column alone.
      expect(
        size,
        lessThan(
          ScreenplayMetrics.fittedFontSize(
            preferredFontSize: 24,
            viewportWidth: viewport,
            pageView: false,
          ),
        ),
      );
    });

    test('shrinking stops rather than running to nothing', () {
      expect(
        ScreenplayMetrics.fittedFontSize(
          preferredFontSize: 15,
          viewportWidth: 20,
          pageView: false,
        ),
        ScreenplayMetrics.minimumFontSize,
      );
    });
  });
}

const double _ratio = ScreenplayMetrics.advanceRatio;

/// Just enough of a TrueType file to read one number out of it.
///
/// `render_pdf::sfnt` is the real parser and this is not a second one: it reads
/// three fields from three tables and has no opinion about anything else in the
/// file.
class _Sfnt {
  _Sfnt(Uint8List bytes) : _data = ByteData.sublistView(bytes) {
    final tableCount = _data.getUint16(4);
    for (var i = 0; i < tableCount; i++) {
      final record = 12 + 16 * i;
      final tag = String.fromCharCodes(
        Uint8List.sublistView(bytes, record, record + 4),
      );
      _tables[tag] = _data.getUint32(record + 8);
    }
  }

  final ByteData _data;
  final Map<String, int> _tables = {};

  /// `head.unitsPerEm` — the em, in the font's own units.
  int get unitsPerEm => _data.getUint16(_tables['head']! + 18);

  /// `hhea.numberOfHMetrics` — how many entries `hmtx` states outright.
  int get _metricCount => _data.getUint16(_tables['hhea']! + 34);

  /// The first glyph's advance. In a monospaced face it is every glyph's.
  int get advance => _data.getUint16(_tables['hmtx']!);

  Set<int> get advances => {
    for (var i = 0; i < _metricCount; i++)
      _data.getUint16(_tables['hmtx']! + 4 * i),
  };

  double get advanceRatio => advance / unitsPerEm;
}
