import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

BlockView _denseBlock() => BlockView(
  id: 1,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: List.filled(30, '***x***').join(' '),
  forced: true,
  dual: false,
  readOnly: false,
  inlineRuns: [
    for (var i = 0; i < 30; i++) ...[
      InlineRunView(
        startUtf16: i * 8,
        endUtf16: i * 8 + 3,
        bold: false,
        italic: false,
        underline: false,
        hidden: true,
      ),
      InlineRunView(
        startUtf16: i * 8 + 3,
        endUtf16: i * 8 + 4,
        bold: true,
        italic: true,
        underline: false,
        hidden: false,
      ),
      InlineRunView(
        startUtf16: i * 8 + 4,
        endUtf16: i * 8 + 7,
        bold: false,
        italic: false,
        underline: false,
        hidden: true,
      ),
    ],
  ],
);

ScrollPosition _horizontal(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    )
    .position;

void main() {
  for (final pageView in [false, true]) {
    testWidgets(
      'dense syntax remains editable without rewrapping (sheets: $pageView)',
      (tester) async {
        final block = _denseBlock();
        final controller = EditorController(FakeCore([block]));
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EditorSurface(controller: controller, pageView: pageView),
            ),
          ),
        );
        await tester.pump();
        final geometry = editorGeometry(pageView: pageView);
        final line = controller.layout.linesOf(0).single;
        expect(line.columns, 59);
        final rowY = geometry.yOfRow(0) + geometry.lineHeight / 2;
        await tester.tapAt(
          Offset(geometry.columnLeft + geometry.advance, rowY),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(controller.selection.focus.offsetUtf16, block.text.length);
        final scroll = _horizontal(tester);
        final endX =
            geometry.columnLeft +
            line.displayColumnAtOffset(line.end) * geometry.advance -
            scroll.pixels;
        expect(
          endX,
          inInclusiveRange(0, editorViewportWidth - kMinInteractiveDimension),
        );

        // Each trailing marker boundary, not just the word, remains hit-testable.
        for (
          var offset = block.text.length - 3;
          offset <= block.text.length;
          offset++
        ) {
          final x =
              geometry.columnLeft +
              line.displayColumnAtOffset(offset) * geometry.advance -
              scroll.pixels;
          final pointer = await tester.createGesture();
          final timestamp = Duration(seconds: offset);
          await pointer.down(Offset(x, rowY), timeStamp: timestamp);
          await pointer.up(timeStamp: timestamp);
          await tester.pump();
          expect(controller.selection.focus.offsetUtf16, offset);
          expect(controller.hasSelection, isFalse);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        final startX = geometry.columnLeft - scroll.pixels;
        expect(
          startX,
          inInclusiveRange(0, editorViewportWidth - kMinInteractiveDimension),
        );
        expect(controller.selection.focus.offsetUtf16, 0);
        expect(controller.layout.linesOf(0).single.columns, 59);
        expect(controller.focusedBlock.text, block.text);
      },
    );
  }

  testWidgets('edits and undo update horizontal access', (tester) async {
    final controller = EditorController(FakeCore([_denseBlock()]));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorSurface(controller: controller)),
      ),
    );
    await tester.pump();
    final scroll = _horizontal(tester);
    expect(scroll.maxScrollExtent, greaterThan(0));
    controller.setSelection(
      DocSelection(
        anchor: const DocPosition(block: 1, offsetUtf16: 0),
        focus: DocPosition(
          block: 1,
          offsetUtf16: controller.focusedBlock.text.length,
        ),
      ),
    );
    controller.insertText('short');
    await tester.pumpAndSettle();
    expect(scroll.maxScrollExtent, 0);
    controller.undo();
    await tester.pumpAndSettle();
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: 1, offsetUtf16: _denseBlock().text.length),
        focus: DocPosition(block: 1, offsetUtf16: _denseBlock().text.length),
      ),
    );
    await tester.pumpAndSettle();
    final geometry = editorGeometry();
    final line = controller.layout.linesOf(0).single;
    final endX =
        geometry.columnLeft +
        line.displayColumnAtOffset(line.end) * geometry.advance -
        scroll.pixels;
    expect(
      endX,
      inInclusiveRange(0, editorViewportWidth - kMinInteractiveDimension),
    );
  });
}
