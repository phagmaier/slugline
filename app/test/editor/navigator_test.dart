import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/navigator_sidebar.dart';
import 'package:slugline/theme.dart';

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
    // The second scene runs long on purpose. The restored-scroll test below
    // scrolls until scene two is the top row, and a scrollable will not move
    // past its last line — so the tail has to be deeper than the viewport or
    // the scroll clamps short and the test measures the clamp instead of the
    // highlight. It is sized off the rows, not off pixels: the script grid is
    // `ScreenplayMetrics.lineHeightRatio` tall and this fixture is not the
    // place to encode that.
    _block(6, BlockKind.action, List.filled(80, 'Night action.').join('\n')),
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

  testWidgets('scene rows use the compact hierarchy and subtle selection', (
    tester,
  ) async {
    await _pump(tester, _script());

    final first = find.byKey(const ValueKey('navigator scene 1'));
    expect(tester.getSize(first).height, 52);
    expect(tester.widget<Text>(find.text('HOUSE')).style?.fontSize, 13);
    final meta = tester.widget<Text>(find.text('INT. · DAY'));
    expect(meta.style?.fontSize, 11);
    expect(meta.style?.color, SluglineColors.light.textTertiary);
    expect(find.text('NAVIGATOR'), findsOneWidget);

    final selected = tester.widget<Material>(
      find.byKey(const ValueKey('navigator scene background 1')),
    );
    expect(selected.color, SluglineColors.light.surfaceOverlay);
    final tile = tester.widget<ListTile>(first);
    final border = tile.shape! as Border;
    expect(border.left.width, 2);
    expect(border.left.color, SluglineColors.light.accent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('navigator scene 5'))),
    );
    await tester.pump();
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('navigator scene background 5')),
          )
          .color,
      isNot(Colors.transparent),
    );
  });

  testWidgets(
    'segmented control, context menu, and drag handle are interactive',
    (tester) async {
      final controller = await _pump(tester, _script());

      final indicator = find.byKey(
        const ValueKey('navigator segment indicator'),
      );
      expect(
        tester
            .widget<AnimatedAlign>(
              find.ancestor(
                of: indicator,
                matching: find.byType(AnimatedAlign),
              ),
            )
            .alignment,
        Alignment.centerLeft,
      );
      await tester.tap(find.textContaining('Characters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedAlign>(
              find.ancestor(
                of: indicator,
                matching: find.byType(AnimatedAlign),
              ),
            )
            .alignment,
        Alignment.centerRight,
      );

      await tester.tap(find.textContaining('Scenes'));
      await tester.pumpAndSettle();
      final second = find.byKey(const ValueKey('navigator scene 5'));
      await tester.tapAt(
        tester.getCenter(second),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Jump to scene'), findsOneWidget);
      expect(find.text('Copy heading'), findsOneWidget);
      expect(find.text('Move scene up'), findsOneWidget);
      await tester.tap(find.text('Move scene up'));
      await tester.pumpAndSettle();
      expect(controller.blocks.first.id, 5);

      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.blocks.first.id, 1);

      await tester.drag(
        find.byKey(const ValueKey('drag scene 1')),
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();
      expect(controller.blocks.first.id, 5);
    },
  );

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
