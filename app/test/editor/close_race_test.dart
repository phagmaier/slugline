import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';

import '../support/fake_core.dart';

void main() {
  for (final editDuringSave in [false, true]) {
    testWidgets('close after saving, with later edit: $editDuringSave', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'First draft.')
        ..filePath = '/scripts/draft.fountain';
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      controller.insertText('Saved edit. ');
      await tester.pumpWidget(
        MaterialApp(home: EditorPage(controller: controller)),
      );
      final page = tester.state<EditorPageState>(find.byType(EditorPage));
      final closing = page.confirmClose();
      await tester.pumpAndSettle();

      final write = Completer<void>();
      core.holdWrites = write;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(core.saves, hasLength(1));
      if (editDuringSave) controller.insertText('Still unsaved. ');

      write.complete();
      await tester.pump();
      expect(await closing, !editDuringSave);
      expect(core.dirty, editDuringSave);
      if (editDuringSave) {
        expect(controller.source, contains('Still unsaved.'));
        expect(core.onDisk, isNot(contains('Still unsaved.')));
      }
    });
  }
}
