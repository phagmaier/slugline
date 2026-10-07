import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/command_palette.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

Future<void> shiftEnter(
  WidgetTester tester, [
  LogicalKeyboardKey key = LogicalKeyboardKey.enter,
]) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  for (final kind in [BlockKind.action, BlockKind.dialogue, BlockKind.note]) {
    testWidgets('Shift+Enter types two lines in ${kind.name}', (tester) async {
      final core = FakeCore.single(kind, '');
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 0);
      tester.testTextInput.enterText('First line.');
      await tester.pump();

      await shiftEnter(tester);

      expect(controller.blocks, hasLength(1));
      expect(controller.blocks.single.text, 'First line.\n');
      expect(controller.selection.focus.offsetUtf16, 12);
      controller.undo();
      expect(controller.blocks.single.text, 'First line.');
      controller.redo();
      tester.testTextInput.enterText('First line.\nSecond line.');
      await tester.pump();
      expect(controller.blocks.single.text, 'First line.\nSecond line.');
    });
  }

  testWidgets(
    'numpad Shift+Enter replaces a selection and undo restores the text',
    (tester) async {
      final core = FakeCore.single(BlockKind.action, 'a🎬b tail');
      final controller = await pumpEditor(tester, core);
      selectFromTo(controller, 0, 4, 0, 3);
      await shiftEnter(tester, LogicalKeyboardKey.numpadEnter);
      expect(core.lineBreaks.single, core.priorSelections.single);
      expect(controller.blocks.single.text, 'a🎬\n tail');
      expect(controller.selection.focus.offsetUtf16, 4);
      expect(core.enters, isEmpty);
      controller.undo();
      expect(controller.blocks.single.text, 'a🎬b tail');
    },
  );

  testWidgets('Shift+Enter edits instead of accepting a navigated suggestion', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'Draft');
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 5);
    core.completions = const [
      Completion(
        kind: CompletionKind.character,
        value: 'DRAFTER',
        startUtf16: 0,
        endUtf16: 5,
        frequency: 1,
        pinned: false,
      ),
    ];
    controller.showCompletions();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await shiftEnter(tester);
    expect(controller.blocks.single.text, 'Draft\n');
    expect(controller.completions, isEmpty);
  });

  testWidgets('an input-method newline still splits while Shift is held', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'First.');
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 6);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    tester.testTextInput.enterText('First.\nSecond.');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(core.lineBreaks, isEmpty);
    expect(core.enters, hasLength(1));
    expect(controller.blocks.map((block) => block.text), ['First.', 'Second.']);
  });

  testWidgets('the palette inserts the same break and returns editor focus', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'First.Second.');
    final controller = await pumpEditorPage(tester, core);
    caretAt(controller, 0, 6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    tester.testTextInput.enterText('Insert line break');
    await tester.pump();
    expect(find.text('Shift+Enter'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(CommandPalette), findsNothing);
    expect(core.lineBreaks, hasLength(1));
    expect(controller.blocks.single.text, 'First.\nSecond.');
    tester.testTextInput.enterText('First.\nMore Second.');
    await tester.pump();
    expect(controller.blocks.single.text, 'First.\nMore Second.');
  });
}
