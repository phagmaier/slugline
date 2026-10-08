import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

void main() {
  FakeCore core() => FakeCore([
    const BlockView(
      id: 1,
      kind: BlockKind.action,
      sectionLevel: 0,
      text: 'Installed command ready.',
      forced: false,
      dual: false,
      readOnly: false,
    ),
  ]);

  List<MethodCall> editingStates(WidgetTester tester) => tester
      .testTextInput
      .log
      .where((call) => call.method == 'TextInput.setEditingState')
      .toList();

  testWidgets(
    'a platform typing burst is committed without stale state echoes',
    (tester) async {
      final controller = await pumpEditor(tester, core());
      controller.moveToDocumentEdge(start: false);
      await tester.pump();
      tester.testTextInput.log.clear();
      final surface = tester.state<EditorSurfaceState>(
        find.byType(EditorSurface),
      );
      var text = controller.focusedBlock.text;
      for (final character in ' Verified through installed association.'.split(
        '',
      )) {
        text += character;
        surface.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
      }
      await tester.pump();
      expect(controller.focusedBlock.text, text);
      expect(controller.selection.focus.offsetUtf16, text.length);
      expect(
        editingStates(tester),
        isEmpty,
        reason:
            'echoes can replace newer input in the asynchronous platform model',
      );

      // An application caret move still has to update the platform.
      controller.moveHorizontal(-1);
      await tester.pump();
      expect(editingStates(tester), hasLength(1));
      expect(editingStates(tester).single.arguments['text'], text);
      expect(
        editingStates(tester).single.arguments['selectionExtent'],
        text.length - 1,
      );
    },
  );

  testWidgets('composition replacement sends no intermediate pre-edit text', (
    tester,
  ) async {
    final controller = await pumpEditor(tester, core());
    controller.moveToDocumentEdge(start: false);
    await tester.pump();
    final surface = tester.state<EditorSurfaceState>(
      find.byType(EditorSurface),
    );
    for (final replacement in ['n', 'ni', '你好', '😀']) {
      tester.testTextInput.log.clear();
      final text = 'Installed command ready.$replacement';
      surface.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange(start: 24, end: text.length),
        ),
      );
      await tester.pump();
      expect(controller.focusedBlock.text, text);
      expect(editingStates(tester), isEmpty);
    }
    tester.testTextInput.log.clear();
    surface.updateEditingValue(
      TextEditingValue(
        text: controller.focusedBlock.text,
        selection: TextSelection.collapsed(
          offset: controller.focusedBlock.text.length,
        ),
      ),
    );
    await tester.pump();
    expect(editingStates(tester), isEmpty);
    expect(surface.currentTextEditingValue.composing, TextRange.empty);
  });

  testWidgets('a platform newline sends only the final new-block state', (
    tester,
  ) async {
    final controller = await pumpEditor(tester, core());
    controller.moveToDocumentEdge(start: false);
    await tester.pump();
    tester.testTextInput.log.clear();
    tester
        .state<EditorSurfaceState>(find.byType(EditorSurface))
        .updateEditingValue(
          const TextEditingValue(
            text: 'Installed command ready.\nNext.',
            selection: TextSelection.collapsed(offset: 30),
          ),
        );
    await tester.pump();
    expect(controller.blocks.map((block) => block.text), [
      'Installed command ready.',
      'Next.',
    ]);
    expect(editingStates(tester), hasLength(1));
    expect(editingStates(tester).single.arguments['text'], 'Next.');
    expect(editingStates(tester).single.arguments['selectionExtent'], 5);
  });

  testWidgets('a refused platform edit restores only the core result', (
    tester,
  ) async {
    final fake = FakeCore.single(BlockKind.action, 'Protected text');
    final controller = await pumpEditor(tester, fake);
    controller.moveToDocumentEdge(start: false);
    await tester.pump();
    tester.testTextInput.log.clear();
    fake.refuseWith = EditRejection.notEditable;
    tester
        .state<EditorSurfaceState>(find.byType(EditorSurface))
        .updateEditingValue(
          const TextEditingValue(
            text: 'Protected textx',
            selection: TextSelection.collapsed(offset: 15),
          ),
        );
    await tester.pump();
    expect(controller.focusedBlock.text, 'Protected text');
    expect(editingStates(tester), hasLength(1));
    expect(editingStates(tester).single.arguments['text'], 'Protected text');
    expect(editingStates(tester).single.arguments['selectionExtent'], 14);
  });
}
