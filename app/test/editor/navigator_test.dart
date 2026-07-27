import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/navigator_sidebar.dart';

import '../support/fake_core.dart';

BlockView _block(int id, BlockKind kind, String text) => BlockView(
  id: id,
  kind: kind,
  sectionLevel: 0,
  text: text,
  forced: false,
  dual: false,
  readOnly: false,
);

FakeCore _script() {
  final core = FakeCore([
    _block(1, BlockKind.sceneHeading, 'INT. HOUSE - DAY #1#'),
    _block(2, BlockKind.action, List.filled(40, 'Morning action.').join('\n')),
    _block(3, BlockKind.character, 'BOB'),
    _block(4, BlockKind.dialogue, 'Hello.'),
    _block(5, BlockKind.sceneHeading, 'EXT. STREET - NIGHT #12A#'),
    _block(6, BlockKind.action, List.filled(40, 'Night action.').join('\n')),
    _block(7, BlockKind.character, 'BOB (V.O.)'),
    _block(8, BlockKind.dialogue, 'Again.'),
  ]);
  core.navigatorData = const NavigatorView(
    scenes: [
      NavigatorScene(
        block: 1,
        sceneNumber: '1',
        prefix: 'INT.',
        location: 'HOUSE',
        timeOfDay: 'DAY',
      ),
      NavigatorScene(
        block: 5,
        sceneNumber: '12A',
        prefix: 'EXT.',
        location: 'STREET',
        timeOfDay: 'NIGHT',
      ),
    ],
    characters: [
      NavigatorCharacter(name: 'BOB', occurrences: 2, blocks: [3, 7]),
    ],
  );
  return core;
}

Future<EditorController> _pump(
  WidgetTester tester,
  FakeCore core, {
  bool visible = true,
  int initialScrollRow = 0,
  Future<void> Function(bool)? onVisibilityChanged,
}) async {
  final controller = EditorController(core);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 900,
        height: 600,
        child: EditorPage(
          controller: controller,
          navigatorVisible: visible,
          initialScrollRow: initialScrollRow,
          onNavigatorVisibilityChanged: onVisibilityChanged,
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('lists scene parts and entity-index character counts', (
    tester,
  ) async {
    await _pump(tester, _script());

    expect(find.byType(NavigatorSidebar), findsOneWidget);
    expect(find.text('HOUSE'), findsOneWidget);
    expect(find.text('INT. · DAY'), findsOneWidget);
    expect(find.text('12A'), findsOneWidget);

    await tester.tap(find.textContaining('Characters'));
    await tester.pump();
    expect(find.text('BOB'), findsOneWidget);
    expect(find.text('2 occurrences'), findsOneWidget);
  });

  testWidgets('scene and character rows place the caret explicitly', (
    tester,
  ) async {
    final controller = await _pump(tester, _script());

    await tester.tap(find.byKey(const ValueKey('navigator scene 5')));
    await tester.pump();
    expect(
      controller.selection.focus,
      const DocPosition(block: 5, offsetUtf16: 0),
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('navigator scene 5')))
          .selected,
      isTrue,
    );

    await tester.tap(find.textContaining('Characters'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('navigator character BOB')));
    await tester.pump();
    expect(
      controller.selection.focus,
      const DocPosition(block: 7, offsetUtf16: 0),
      reason: 'from scene two, the next BOB occurrence is the second cue',
    );
  });

  testWidgets('the top visible scene is highlighted after a restored scroll', (
    tester,
  ) async {
    final core = _script();
    final probe = EditorController(core);
    final secondSceneRow = probe.layout.firstRowOf(4);
    probe.dispose();

    await _pump(tester, _script(), initialScrollRow: secondSceneRow);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('navigator scene 5')))
          .selected,
      isTrue,
    );
  });

  testWidgets('Ctrl+J opens a filtered keyboard quick jump', (tester) async {
    final visibility = <bool>[];
    final controller = await _pump(
      tester,
      _script(),
      visible: false,
      onVisibilityChanged: (visible) async => visibility.add(visible),
    );
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(NavigatorSidebar), findsOneWidget);
    expect(visibility, [true]);
    tester.testTextInput.enterText('street');
    await tester.pump();
    expect(find.text('HOUSE'), findsNothing);
    expect(find.text('STREET'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      controller.selection.focus,
      const DocPosition(block: 5, offsetUtf16: 0),
    );
  });

  testWidgets('collapse reports the state and leaves a way back', (
    tester,
  ) async {
    final visibility = <bool>[];
    await _pump(
      tester,
      _script(),
      onVisibilityChanged: (visible) async => visibility.add(visible),
    );

    await tester.tap(find.byKey(const ValueKey('collapse navigator')));
    await tester.pump();
    expect(find.byType(NavigatorSidebar), findsNothing);
    expect(find.byKey(const ValueKey('show navigator')), findsOneWidget);
    expect(visibility, [false]);
  });
}
