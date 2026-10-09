import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/typography.dart';

import '../support/fake_core.dart';

void main() {
  testWidgets('editor scene headings default to the regular painted face', (
    tester,
  ) async {
    final loader = FontLoader(scriptFontFamily)
      ..addFont(rootBundle.load('fonts/CourierPrime-Regular.ttf'))
      ..addFont(rootBundle.load('fonts/CourierPrime-Bold.ttf'));
    await loader.load();
    final controller = EditorController(
      FakeCore.single(BlockKind.sceneHeading, 'INT. LIBRARY - DAY'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorSurface(controller: controller)),
      ),
    );
    final paint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(EditorSurface),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere(
          (paint) => paint.painter.runtimeType.toString() == '_SurfacePainter',
        );
    final dynamic delegate = paint.painter!;
    final recorder = ui.PictureRecorder();
    delegate.paint(Canvas(recorder), const Size(800, 600));
    recorder.endRecording().dispose();
    final hits = delegate.lineCache.hits as int;
    delegate.lineCache.line(
      'INT. LIBRARY - DAY',
      TextStyle(
        fontFamily: scriptFontFamily,
        fontSize: delegate.fontSize as double,
        height: 1,
        color: delegate.colours.text as Color,
      ),
    );
    expect(
      delegate.lineCache.hits,
      hits + 1,
      reason:
          'The actual painter must cache the plain heading in the regular face.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorSurface(controller: controller, boldSceneHeadings: true),
        ),
      ),
    );
    final boldPaint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(EditorSurface),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere(
          (paint) => paint.painter.runtimeType.toString() == '_SurfacePainter',
        );
    expect(
      boldPaint.painter!.shouldRepaint(paint.painter!),
      isTrue,
      reason: 'A live preference change must repaint without an edit.',
    );
    final dynamic boldDelegate = boldPaint.painter!;
    final boldRecorder = ui.PictureRecorder();
    boldDelegate.paint(Canvas(boldRecorder), const Size(800, 600));
    boldRecorder.endRecording().dispose();
    final boldHits = boldDelegate.lineCache.hits as int;
    final boldPainter =
        boldDelegate.lineCache.line(
              'INT. LIBRARY - DAY',
              TextStyle(
                fontFamily: scriptFontFamily,
                fontSize: boldDelegate.fontSize as double,
                height: 1,
                color: boldDelegate.colours.text as Color,
                fontWeight: FontWeight.bold,
              ),
            )
            as TextPainter;
    expect(
      boldDelegate.lineCache.hits,
      boldHits + 1,
      reason:
          'The actual painter must cache the plain heading in the bold face.',
    );
    final regularPainter =
        delegate.lineCache.line(
              'INT. LIBRARY - DAY',
              TextStyle(
                fontFamily: scriptFontFamily,
                fontSize: delegate.fontSize as double,
                height: 1,
                color: delegate.colours.text as Color,
              ),
            )
            as TextPainter;
    Future<List<int>> pixels(TextPainter painter) async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Offset(10, 10));
      final picture = recorder.endRecording();
      final image = await picture.toImage(600, 50);
      final bytes = (await image.toByteData())!.buffer.asUint8List().toList();
      image.dispose();
      picture.dispose();
      return bytes;
    }

    await tester.runAsync(() async {
      expect(
        await pixels(boldPainter),
        isNot(await pixels(regularPainter)),
        reason:
            'The bundled bold and regular heading faces must be distinguishable.',
      );
    });
  });
}
