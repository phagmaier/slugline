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
  inlineRuns: const [],
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
    outline: [
      NavigatorNode(
        block: 1,
        kind: BlockKind.sceneHeading,
        text: 'INT. HOUSE - DAY #1#',
        depth: 0,
      ),
      NavigatorNode(
        block: 5,
        kind: BlockKind.sceneHeading,
        text: 'EXT. STREET - NIGHT #12A#',
        depth: 0,
      ),
    ],
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
  double viewportWidth = 1000,
  int initialScrollRow = 0,
  Future<void> Function(bool)? onVisibilityChanged,
}) async {
  tester.view.physicalSize = Size(viewportWidth, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

    final titleRow = tester.widget<Row>(
      find.ancestor(of: find.text('HOUSE'), matching: find.byType(Row)).first,
    );
    expect(titleRow.crossAxisAlignment, CrossAxisAlignment.baseline);
    expect(titleRow.textBaseline, TextBaseline.alphabetic);
    expect(
      tester.getSize(find.byKey(const ValueKey('scene number column 1'))).width,
      30,
    );

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

  testWidgets('drag handles appear on row hover and keyboard focus', (
    tester,
  ) async {
    await _pump(tester, _script());

    final first = find.byKey(const ValueKey('navigator scene 1'));
    final visibility = find.byKey(const ValueKey('drag scene 1 visibility'));
    final titleX = tester.getTopLeft(find.text('HOUSE')).dx;
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(first));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 1);
    expect(tester.getTopLeft(find.text('HOUSE')).dx, titleX);

    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('navigator filter'))),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 0);

    tester.widget<ListTile>(first).onFocusChange!(true);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(visibility).opacity, 1);
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
      final scenesLabel = tester.widget<AnimatedDefaultTextStyle>(
        find.byKey(const ValueKey('navigator Scenes label style')),
      );
      final scenesCount = tester.widget<AnimatedDefaultTextStyle>(
        find.byKey(const ValueKey('navigator Scenes count style')),
      );
      expect(scenesLabel.style.fontSize, 11);
      expect(scenesCount.style.fontSize, 10);
      expect(scenesCount.style.color, SluglineColors.light.textTertiary);
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

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('drag scene 1'))),
      );
      await tester.pumpAndSettle();
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

  for (final width in [800.0, 1000.0]) {
    testWidgets(
      'Ctrl+J returns from Characters to scene search at $width px',
      (tester) async {
        final controller = await _pump(
          tester,
          _script(),
          visible: false,
          viewportWidth: width,
        );
        final originalSource = controller.source;
        await tester.tap(find.byType(EditorSurface));
        await tester.pump();

        Future<void> quickJump() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
        }

        await quickJump();
        await tester.tap(find.textContaining('Characters'));
        await tester.pumpAndSettle();
        expect(find.text('BOB'), findsOneWidget);

        await quickJump();
        tester.testTextInput.enterText('street');
        await tester.pump();
        expect(find.text('HOUSE'), findsNothing);
        expect(find.text('STREET'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          controller.selection.focus,
          const DocPosition(block: 5, offsetUtf16: 0),
        );
        expect(
          controller.source,
          originalSource,
          reason: 'quick-jump input is not a screenplay edit',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'Ctrl+J does not steal input from a modal dialog',
    (tester) async {
      final controller = await _pump(tester, _script(), visible: false);
      final originalSource = controller.source;
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      final dialog = showDialog<void>(
        context: tester.element(find.byType(EditorPage)),
        builder: (context) => AlertDialog(
          content: const TextField(
            key: ValueKey('modal input'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('Dialog text');
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(NavigatorSidebar), findsNothing);
      expect(find.text('Dialog text'), findsOneWidget);
      expect(controller.source, originalSource);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await dialog;
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

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
