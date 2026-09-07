import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/editor/navigator_sidebar.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/theme.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reading stays quiet; typing and Ctrl+Space offer suggestions',
    (tester) async {
      final core = FakeCore.single(BlockKind.character, 'A')
        ..completions = const [
          Completion(
            kind: CompletionKind.character,
            value: 'ALICE',
            startUtf16: 0,
            endUtf16: 2,
            frequency: 1,
            pinned: false,
          ),
        ];
      final controller = await pumpEditor(tester, core);
      final popup = find.byKey(const ValueKey('completion-popup'));
      expect(popup, findsNothing);
      caretAt(controller, 0, 1);
      await tester.pump();
      expect(popup, findsNothing);
      controller.insertText('L');
      await tester.pump();
      expect(popup, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(popup, findsNothing);
      await shortcut(tester, LogicalKeyboardKey.space);
      expect(popup, findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(controller.completionWasNavigated, isFalse);
      expect(popup, findsNothing);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'compact suggestions reveal every keyboard-highlighted candidate',
    (tester) async {
      final core = FakeCore.single(BlockKind.character, '')
        ..completions = [
          for (var i = 0; i < 12; i++)
            Completion(
              kind: CompletionKind.character,
              value: 'PERSON $i',
              startUtf16: 0,
              endUtf16: 0,
              frequency: 1,
              pinned: false,
            ),
        ];
      final controller = await pumpEditor(tester, core);
      await shortcut(tester, LogicalKeyboardKey.space);
      expect(
        tester.getSize(find.byKey(const ValueKey('completion-popup'))).height,
        lessThan(210),
      );
      for (var i = 1; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(find.byKey(ValueKey('completion-PERSON $i')), findsOneWidget);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.blocks.single.text, 'PERSON 11');
    },
  );

  for (final width in [640.0, 800.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('writing tools fit a $width window at $scale text scaling', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = EditorController(
          FakeCore.single(BlockKind.sceneHeading, 'INT. QUIET ROOM - DAY')
            ..navigatorData = const NavigatorView(
              scenes: [
                NavigatorScene(
                  block: 1,
                  sceneNumber: '1',
                  prefix: 'INT.',
                  location: 'QUIET ROOM',
                  timeOfDay: 'DAY',
                ),
              ],
              characters: [],
            ),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: sluglineTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: EditorPage(
              controller: controller,
              navigatorVisible: true,
              onClosed: () async {},
              title: 'A screenplay with a long working title',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.getRect(find.byType(EditorSurface));
        expect(
          surface.width,
          greaterThanOrEqualTo(width < 900 ? width : width - 290),
        );
        await tester.tap(find.byKey(const ValueKey('open find')));
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(FindBar));
        expect(bar.left, greaterThanOrEqualTo(surface.left));
        expect(bar.right, lessThanOrEqualTo(surface.right));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open commands')));
        await tester.pumpAndSettle();
        expect(find.text('Element or command'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (width < 900) {
          expect(find.byType(NavigatorSidebar), findsNothing);
          await tester.tap(find.byKey(const ValueKey('toggle navigator')));
          await tester.pumpAndSettle();
          expect(find.byType(NavigatorSidebar), findsOneWidget);
          await tester.tap(find.text('QUIET ROOM'));
          await tester.pumpAndSettle();
          expect(find.byType(NavigatorSidebar), findsNothing);
          expect(controller.selection.focus.block, 1);
        }
        final context = tester.element(find.byType(EditorPage));
        final dialog = ShortcutsDialog.show(context);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Ctrl+Space'),
          160,
          scrollable: find.descendant(
            of: find.byType(ShortcutsDialog),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Ctrl+Space'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await dialog;
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('resizing preserves the docked preference and the current text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EditorController(
      FakeCore.single(BlockKind.action, 'A room.'),
    );
    addTearDown(controller.dispose);
    final preferences = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          navigatorVisible: true,
          onClosed: () async {},
          onNavigatorVisibilityChanged: (visible) async =>
              preferences.add(visible),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigatorSidebar), findsOneWidget);
    tester.view.physicalSize = const Size(640, 480);
    await tester.pumpAndSettle();
    expect(find.byType(NavigatorSidebar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toggle navigator')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigatorSidebar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 700);
    await tester.pumpAndSettle();
    expect(find.byType(NavigatorSidebar), findsOneWidget);
    expect(preferences, isEmpty);
    expect(controller.blocks.single.text, 'A room.');
  });
}
