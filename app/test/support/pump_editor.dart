import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';

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
