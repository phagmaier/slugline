import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

void main() {
  const channel = MethodChannel('slugline/window');
  const incomplete =
      'Installed command ready. Verified through installed association';

  testWidgets('Ctrl+S waits for native text before taking one save snapshot', (
    tester,
  ) async {
    final barrier = Completer<void>();
    var requests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'flushTextInput');
      requests++;
      await barrier.future;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final core = FakeCore.single(BlockKind.action, incomplete)
      ..filePath = '/scripts/burst.fountain';
    final controller = await pumpEditorPage(tester, core);
    controller.moveToDocumentEdge(start: false);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(core.saves, isEmpty, reason: 'native text is still pending');
    expect(requests, 1);
    final surface = tester.state<EditorSurfaceState>(
      find.byType(EditorSurface),
    );
    surface.updateEditingValue(
      const TextEditingValue(
        text: '$incomplete.',
        selection: TextSelection.collapsed(offset: incomplete.length + 1),
      ),
    );
    barrier.complete();
    await tester.pumpAndSettle();
    expect(core.saves, [('/scripts/burst.fountain', false)]);
    expect(core.onDisk, '$incomplete.');
    expect(core.dirty, isFalse);
  });

  testWidgets('a disposed editor cannot save after the native reply', (
    tester,
  ) async {
    final barrier = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => barrier.future,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final core = FakeCore.single(BlockKind.action, incomplete)
      ..filePath = '/scripts/closed.fountain';
    await pumpEditorPage(tester, core);
    final save = tester.state<EditorPageState>(find.byType(EditorPage)).save();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    barrier.complete();
    await save;
    expect(core.saves, isEmpty);
  });
}
