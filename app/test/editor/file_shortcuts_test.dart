import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'dart:async';

import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';

void main() {
  for (final key in [LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO]) {
    testWidgets('${key.keyLabel} holds autosave until the file action ends', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'Draft.')
        ..filePath = '/scripts/draft.fountain';
      final controller = EditorController(core);
      final driver = AutosaveDriver(
        core: core,
        changes: controller,
        idle: const Duration(seconds: 1),
        interval: const Duration(seconds: 3),
        onOutcome: (_) {},
      );
      addTearDown(() {
        driver.dispose();
        controller.dispose();
      });
      final action = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            controller: controller,
            autosave: driver,
            onNewScript: () => action.future,
            onOpenScript: () => action.future,
          ),
        ),
      );
      await tester.pump();
      controller.insertText('Unsaved. ');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(seconds: 4));
      expect(core.saves, isEmpty);
      action.complete();
      await tester.pumpAndSettle();
      expect(core.saves, [('/scripts/draft.fountain', true)]);
      expect(core.onDisk, controller.source);
    });
  }

  testWidgets('Ctrl+W returns to the library in distraction-free mode', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'Keep this text.');
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          distractionFree: true,
          onClosed: () async => closed++,
        ),
      ),
    );
    await tester.tap(find.byType(EditorSurface));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(closed, 1);
    expect(controller.source, contains('Keep this text.'));
  });
}
