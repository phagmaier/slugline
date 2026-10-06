import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/preview_view.dart';
import 'package:slugline/theme.dart';
import 'package:slugline/typography.dart';

import '../support/fake_output.dart';

const _geometry = PreviewGeometry(paper: PaperSize.usLetter, scale: 7.2);

TextStyle _style({
  bool bold = false,
  bool italic = false,
  bool underline = false,
}) => TextStyle(
  fontFamily: scriptFontFamily,
  fontSize: 12,
  height: 1,
  color: SluglineColors.light.onPaper,
  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  decoration: underline ? TextDecoration.underline : TextDecoration.none,
);

Future<List<int>> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(612, 792);
  final data = await image.toByteData();
  final bytes = data!.buffer.asUint8List().toList();
  image.dispose();
  picture.dispose();
  return bytes;
}

void _reference(Canvas canvas, String text, TextStyle style, {int column = 0}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(
      _geometry.left + column * _geometry.column,
      _geometry.top + (_geometry.row - painter.height) / 2,
    ),
  );
  painter.dispose();
}

Future<CustomPainter> _preview(
  WidgetTester tester,
  String content,
  List<EmphasisRunView> runs,
) async {
  final base = samplePagination(titlePage: false, pages: 1);
  final line = LayoutLineView(
    row: 0,
    column: 0,
    content: content,
    runs: runs,
    block: 1,
    sourceLine: 0,
    kind: LayoutLineKind.content,
  );
  final pagination = PaginationView(
    revision: base.revision,
    generation: base.generation,
    pageCount: 1,
    pages: [
      PageView(number: 1, lines: [line]),
    ],
    stats: base.stats,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PreviewView(
          pagination: pagination,
          paper: PaperSize.usLetter,
          scale: 7.2,
        ),
      ),
    ),
  );
  return tester
      .widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('preview-page-1')),
          matching: find.byType(CustomPaint),
        ),
      )
      .painter!;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader(scriptFontFamily);
    for (final face in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      loader.addFont(rootBundle.load('fonts/CourierPrime-$face.ttf'));
    }
    await loader.load();
  });

  testWidgets('preview paints italic text without paired markers', (
    tester,
  ) async {
    final painter = await _preview(tester, '*quietly*', const [
      EmphasisRunView(
        text: 'quietly',
        bold: false,
        italic: true,
        underline: false,
      ),
    ]);
    await tester.runAsync(() async {
      final actual = await _pixels(
        (canvas) => painter.paint(canvas, const Size(612, 792)),
      );
      expect(
        actual,
        await _pixels(
          (canvas) => _reference(canvas, 'quietly', _style(italic: true)),
        ),
      );
      expect(
        actual,
        isNot(
          await _pixels((canvas) => _reference(canvas, 'quietly', _style())),
        ),
        reason: 'The bundled italic face must be distinguishable from regular.',
      );
    });
  });

  testWidgets('resolved mixed runs close up markers on the scalar grid', (
    tester,
  ) async {
    final painter = await _preview(
      tester,
      'A **bold** *tilt* _under_ ***both*** 😀!',
      const [
        EmphasisRunView(
          text: 'A ',
          bold: false,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: 'bold',
          bold: true,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: ' ',
          bold: false,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: 'tilt',
          bold: false,
          italic: true,
          underline: false,
        ),
        EmphasisRunView(
          text: ' ',
          bold: false,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: 'under',
          bold: false,
          italic: false,
          underline: true,
        ),
        EmphasisRunView(
          text: ' ',
          bold: false,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: 'both',
          bold: true,
          italic: true,
          underline: false,
        ),
        EmphasisRunView(
          text: ' 😀',
          bold: false,
          italic: false,
          underline: false,
        ),
        EmphasisRunView(
          text: '!',
          bold: false,
          italic: false,
          underline: false,
        ),
      ],
    );
    await tester.runAsync(() async {
      expect(
        await _pixels((canvas) => painter.paint(canvas, const Size(612, 792))),
        await _pixels((canvas) {
          _reference(canvas, 'A ', _style());
          _reference(canvas, 'bold', _style(bold: true), column: 2);
          _reference(canvas, ' ', _style(), column: 6);
          _reference(canvas, 'tilt', _style(italic: true), column: 7);
          _reference(canvas, ' ', _style(), column: 11);
          _reference(canvas, 'under', _style(underline: true), column: 12);
          _reference(canvas, ' ', _style(), column: 17);
          _reference(
            canvas,
            'both',
            _style(bold: true, italic: true),
            column: 18,
          );
          _reference(canvas, ' 😀', _style(), column: 22);
          _reference(canvas, '!', _style(), column: 24);
        }),
      );
    });
  });

  for (final bold in [false, true]) {
    testWidgets('preview paints scene heading with bold=$bold', (tester) async {
      final painter = await _preview(tester, 'INT. LIBRARY - DAY', [
        EmphasisRunView(
          text: 'INT. LIBRARY - DAY',
          bold: bold,
          italic: false,
          underline: false,
        ),
      ]);
      await tester.runAsync(() async {
        final actual = await _pixels(
          (canvas) => painter.paint(canvas, const Size(612, 792)),
        );
        expect(
          actual,
          await _pixels(
            (canvas) =>
                _reference(canvas, 'INT. LIBRARY - DAY', _style(bold: bold)),
          ),
        );
        expect(
          actual,
          isNot(
            await _pixels(
              (canvas) =>
                  _reference(canvas, 'INT. LIBRARY - DAY', _style(bold: !bold)),
            ),
          ),
          reason:
              'The bundled regular and bold faces must paint different pixels.',
        );
      });
    });
  }
}
