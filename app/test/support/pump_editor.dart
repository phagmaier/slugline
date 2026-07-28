import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';

/// The viewport every helper here pumps the editor into.
const double editorViewportWidth = 900;
const double editorViewportHeight = 600;

/// The surface's own geometry, for a test that has to name a pixel.
///
/// A test that wants "the middle of row three" must not spell out the padding
/// and the line height itself: those are inches of page now, they move with the
/// text size, and a literal here is a test that passes for the wrong reason
/// until the day it fails for one. Ask the same object the surface asks.
EditorGeometry editorGeometry({
  double textSize = 15,
  double viewportWidth = editorViewportWidth,
  int totalRows = 1 << 20,
}) {
  final fontSize = textSize.clamp(12, 24).toDouble();
  final painter = TextPainter(
    text: TextSpan(
      text: 'MMMMMMMMMM',
      style: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier New', 'DejaVu Sans Mono'],
        fontSize: fontSize,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return EditorGeometry(
    metrics: ScreenplayMetrics(
      advance: painter.width / 10,
      lineHeight: fontSize * 1.4,
    ),
    viewportWidth: viewportWidth,
    totalRows: totalRows,
  );
}

/// The point at grid cell (row, column), relative to the surface's top left.
Offset editorCell(int row, int column, {double textSize = 15}) {
  final geometry = editorGeometry(textSize: textSize);
  return Offset(
    geometry.columnLeft + column * geometry.advance,
    geometry.yOfRow(row) + geometry.lineHeight / 2,
  );
}

/// Puts a focused editor on screen over [core] and hands back its controller.
Future<EditorController> pumpEditor(WidgetTester tester, DocumentCore core) async {
  final controller = EditorController(core);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: EditorSurface(controller: controller),
        ),
      ),
    ),
  );
  // The surface takes focus on a pointer down, as it does for a real click.
  await tester.tap(find.byType(EditorSurface));
  await tester.pump();
  return controller;
}

/// The same, but the whole page: the surface, the element bar, and the two
/// panels `Ctrl+K` and `Ctrl+F` open. For anything that involves them.
Future<EditorController> pumpEditorPage(WidgetTester tester, DocumentCore core) async {
  final controller = EditorController(core);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 900,
        height: 600,
        child: EditorPage(controller: controller),
      ),
    ),
  );
  await tester.tap(find.byType(EditorSurface));
  await tester.pump();
  return controller;
}

/// Puts the caret in [blockIndex] at [offset], with no selection.
void caretAt(EditorController controller, int blockIndex, int offset) {
  final position =
      DocPosition(block: controller.blocks[blockIndex].id, offsetUtf16: offset);
  controller.setSelection(DocSelection(anchor: position, focus: position));
}

/// Selects from one position to another.
void selectFromTo(
  EditorController controller,
  int fromBlock,
  int fromOffset,
  int toBlock,
  int toOffset,
) {
  controller.setSelection(
    DocSelection(
      anchor: DocPosition(
        block: controller.blocks[fromBlock].id,
        offsetUtf16: fromOffset,
      ),
      focus: DocPosition(
        block: controller.blocks[toBlock].id,
        offsetUtf16: toOffset,
      ),
    ),
  );
}
