import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';

import '../support/fake_core.dart';

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester, String label) async {
  await _key(tester, LogicalKeyboardKey.keyK, control: true);
  await tester.enterText(
    find.widgetWithText(TextField, 'Element or command'),
    label,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the palette omits actions with no attached handler or output', (
    tester,
  ) async {
    final controller = EditorController(
      FakeCore.single(BlockKind.action, 'Draft text.'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Preferences…',
      'Keyboard shortcuts',
      'Enter distraction-free mode',
      'Use continuous view',
      'Increase text size',
      'Preview and export…',
      'Go to page…',
      'Pagination debug',
    ]) {
      await _filter(tester, label);
      expect(find.text('No matching command'), findsOneWidget);
    }
    await _key(tester, LogicalKeyboardKey.escape);
    expect(controller.source, 'Draft text.');
  });

  for (final size in [12.0, 24.0]) {
    testWidgets('text-size commands respect the $size limit', (tester) async {
      final controller = EditorController(
        FakeCore.single(BlockKind.action, 'Draft text.'),
      );
      addTearDown(controller.dispose);
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            controller: controller,
            textSize: size,
            onTextSizeChanged: (size) async => changes.add(size),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _filter(
        tester,
        size == 12 ? 'Decrease text size' : 'Increase text size',
      );
      expect(find.text('No matching command'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      await _filter(
        tester,
        size == 12 ? 'Increase text size' : 'Decrease text size',
      );
      await _key(tester, LogicalKeyboardKey.enter);
      expect(changes, [size == 12 ? 13 : 23]);
      expect(controller.source, 'Draft text.');
    });
  }

  for (final label in [
    'Preferences…',
    'Keyboard shortcuts',
    'Spell checking…',
  ]) {
    testWidgets('$label holds autosave until its modal closes', (tester) async {
      final core = FakeCore.single(BlockKind.action, 'Draft text.')
        ..filePath = '/scripts/draft.fountain';
      final controller = EditorController(core);
      final autosave = AutosaveDriver(
        core: core,
        changes: controller,
        onOutcome: (_) {},
      );
      addTearDown(controller.dispose);
      addTearDown(autosave.dispose);
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return EditorPage(
                controller: controller,
                autosave: autosave,
                onOpenPreferences: () => showDialog<void>(
                  context: pageContext,
                  builder: (_) =>
                      const AlertDialog(title: Text('Preferences test dialog')),
                ),
                onShowShortcuts: () => ShortcutsDialog.show(pageContext),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.insertText('Unsaved ');
      final source = controller.source;
      await _filter(tester, label);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(CommandPalette), findsNothing);
      expect(autosave.suppressed, isTrue);
      if (label == 'Spell checking…') {
        expect(find.byType(SpellDialog), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(core.saves, isEmpty);
      expect(core.dirty, isTrue);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(autosave.suppressed, isFalse);
      expect(core.saves, [('/scripts/draft.fountain', true)]);
      expect(core.onDisk, source);
      expect(controller.source, source);
    });
  }

  for (final label in [
    'Preferences…',
    'Spell checking…',
    'Keyboard shortcuts',
    'Show navigator',
    'Enter distraction-free mode',
    'Use continuous view',
    'Increase text size',
    'Decrease text size',
  ]) {
    testWidgets('the palette reaches $label', (tester) async {
      final controller = EditorController(
        FakeCore.single(BlockKind.action, 'Draft text.'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            controller: controller,
            onOpenPreferences: () async {},
            onShowShortcuts: () async {},
            onDistractionFreeChanged: (_) async {},
            onTextSizeChanged: (_) async {},
            onPageViewChanged: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _filter(tester, label);
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(CommandPalette),
            matching: find.byType(ListView),
          ),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    });
  }
}
