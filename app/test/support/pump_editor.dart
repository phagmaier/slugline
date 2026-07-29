import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';

/// The viewport every helper here pumps the editor into.
///
/// It is the test view's own size, and it has to be: the surface derives the
/// script's size from the width it is laid out into, so a helper that asked for
/// a wider box than the view can give — as this one used to ask for 900 — would
/// compute its pixels against a viewport the surface never saw.
const double editorViewportWidth = 800;
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
  // `EditorSurface.pageView` defaults to true, and the fit is wider in page
  // view — the sheet has to cross the viewport, not just the measure — so this
  // default has to match the widget's or every pixel here is off by the
  // difference between 6 inches and 8.5.
  bool pageView = true,
}) {
  // The same derivation the surface runs, and deliberately not a second copy of
  // it: the size follows the viewport, so a helper that measured a font — as
  // this one used to — would name a pixel the surface never drew at.
  return EditorGeometry(
    metrics: ScreenplayMetrics.forFontSize(
      ScreenplayMetrics.fittedFontSize(
        preferredFontSize: textSize.clamp(12, 24).toDouble(),
        viewportWidth: viewportWidth,
        pageView: pageView,
      ),
    ),
    viewportWidth: viewportWidth,
    totalRows: totalRows,
    pageView: pageView,
    scrollbarWidth: kMinInteractiveDimension,
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
          width: editorViewportWidth,
          height: editorViewportHeight,
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
        width: editorViewportWidth,
        height: editorViewportHeight,
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
