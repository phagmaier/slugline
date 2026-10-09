import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

/// The scroll offset that parks [row] at the top of the viewport.
double _offsetOfRow(int row) => editorGeometry().yOfRow(row);

BlockView _block(int id) => BlockView(
  id: id,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: 'Action line $id.',
  forced: false,
  dual: false,
  readOnly: false,
  inlineRuns: const [],
);

FakeCore _script(int blocks) =>
    FakeCore([for (var id = 1; id <= blocks; id++) _block(id)]);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    )
    .position;

Future<void> _pumpSurface(
  WidgetTester tester,
  EditorController controller, {
  required int initialScrollRow,
  FocusNode? focusNode,
  ValueChanged<int>? onScrolled,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: editorViewportWidth,
          height: editorViewportHeight,
          child: EditorSurface(
            controller: controller,
            initialScrollRow: initialScrollRow,
            focusNode: focusNode,
            onScrolled: onScrolled,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a saved row is applied after the first layout and survives focus',
    (tester) async {
      final controller = EditorController(_script(100));
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await _pumpSurface(
        tester,
        controller,
        initialScrollRow: 42,
        focusNode: focusNode,
      );

      expect(_position(tester).pixels, _offsetOfRow(42));
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(_position(tester).pixels, _offsetOfRow(42));
    },
  );

  testWidgets('row zero starts at the top', (tester) async {
    final controller = EditorController(_script(100));
    addTearDown(controller.dispose);

    await _pumpSurface(tester, controller, initialScrollRow: 0);

    expect(_position(tester).pixels, 0);
  });

  testWidgets('a row beyond a shortened document clamps and is reported', (
    tester,
  ) async {
    final controller = EditorController(_script(20));
    final reported = <int>[];
    addTearDown(controller.dispose);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 500,
      onScrolled: reported.add,
    );

    final position = _position(tester);
    expect(position.pixels, position.maxScrollExtent);
    expect(reported, isNotEmpty);
    expect(reported.last, lessThan(500));
  });

  testWidgets('restoration runs once and later scrolling remains parked', (
    tester,
  ) async {
    final controller = EditorController(_script(100));
    final reported = <int>[];
    addTearDown(controller.dispose);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 12,
      onScrolled: reported.add,
    );
    final position = _position(tester);
    expect(position.pixels, _offsetOfRow(12));

    position.jumpTo(_offsetOfRow(30));
    await tester.pump();
    expect(reported.last, 30);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 12,
      onScrolled: reported.add,
    );
    expect(_position(tester).pixels, _offsetOfRow(30));
  });

  testWidgets('the scrollbar thumb can be dragged', (tester) async {
    final controller = EditorController(_script(100));
    addTearDown(controller.dispose);

    await _pumpSurface(tester, controller, initialScrollRow: 0);
    final position = _position(tester);
    position.jumpTo(1);
    await tester.pump(const Duration(milliseconds: 300));
    final verticalBar = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollbar &&
          widget.scrollbarOrientation != ScrollbarOrientation.bottom,
    );
    final scrollbar = tester.getRect(verticalBar);
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(of: verticalBar, matching: find.byType(CustomPaint)),
        )
        .map((paint) => paint.foregroundPainter)
        .whereType<ScrollbarPainter>()
        .first;
    Offset? thumb;
    for (var y = 0.0; y < scrollbar.height && thumb == null; y++) {
      for (var x = 0.0; x < scrollbar.width; x++) {
        final candidate = Offset(x, y);
        if (painter.hitTestOnlyThumbInteractive(
          candidate,
          PointerDeviceKind.mouse,
        )) {
          thumb = candidate;
          break;
        }
      }
    }
    expect(thumb, isNotNull);

    await tester.dragFrom(
      scrollbar.topLeft + thumb!,
      const Offset(0, 240),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(
      position.pixels,
      greaterThan(position.maxScrollExtent / 4),
      reason: 'thumb=$thumb scrollbar=$scrollbar',
    );
  });
}
