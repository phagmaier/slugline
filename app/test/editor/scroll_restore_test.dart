import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';

BlockView _block(int id) => BlockView(
  id: id,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: 'Action line $id.',
  forced: false,
  dual: false,
  readOnly: false,
);

FakeCore _script(int blocks) =>
    FakeCore([for (var id = 1; id <= blocks; id++) _block(id)]);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

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
          width: 900,
          height: 600,
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

      expect(_position(tester).pixels, 28 + 42 * 21);
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(_position(tester).pixels, 28 + 42 * 21);
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
    expect(position.pixels, 28 + 12 * 21);

    position.jumpTo(28 + 30 * 21);
    await tester.pump();
    expect(reported.last, 30);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 12,
      onScrolled: reported.add,
    );
    expect(_position(tester).pixels, 28 + 30 * 21);
  });
}
