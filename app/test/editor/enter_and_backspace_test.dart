// The Phase 2 table: what Enter and Backspace do, in every element type.
//
// What is under test here is the editor's half of the contract — which command
// the keystroke turns into, and where the caret ends up once the patch comes
// back. What the command then *means* is the core's, and `cargo test` covers it.
// Asserting on the command rather than only on the resulting text is deliberate:
// it is the thing Phase 3 will change, element type by element type.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

/// Every element type a caret can be in. `opaque` is absent because §3.2 makes
/// it verbatim and uneditable, and it has its own test below.
const editableKinds = [
  BlockKind.sceneHeading,
  BlockKind.action,
  BlockKind.character,
  BlockKind.dialogue,
  BlockKind.parenthetical,
  BlockKind.transition,
  BlockKind.centered,
  BlockKind.lyric,
  BlockKind.section,
  BlockKind.synopsis,
  BlockKind.note,
  BlockKind.pageBreak,
];

FakeCore twoBlocks(BlockKind kind) => FakeCore([
      BlockView(
        id: 1,
        kind: kind,
        sectionLevel: kind == BlockKind.section ? 1 : 0,
        text: 'Hello world',
        forced: false,
        dual: false,
        readOnly: false,
      ),
      const BlockView(
        id: 2,
        kind: BlockKind.action,
        sectionLevel: 0,
        text: 'Second.',
        forced: false,
        dual: false,
        readOnly: false,
      ),
    ]);

void main() {
  for (final kind in editableKinds) {
    group('${kind.name}:', () {
      testWidgets('Enter splits the block at the caret', (tester) async {
        final core = twoBlocks(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(
          core.commands.last,
          isA<EditCommand_SplitBlock>()
              .having((c) => c.block, 'block', 1)
              .having((c) => c.atUtf16, 'atUtf16', 5),
        );
        expect(controller.blocks.length, 3);
        expect(controller.blocks[0].text, 'Hello');
        expect(controller.blocks[1].text, ' world');
        // The caret follows the text it split off, as it does in every editor.
        expect(controller.selection.focus.block, controller.blocks[1].id);
        expect(controller.selection.focus.offsetUtf16, 0);
      });

      testWidgets('Enter at the end of a block leaves an empty one after it',
          (tester) async {
        final core = twoBlocks(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 11);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(controller.blocks.length, 3);
        expect(controller.blocks[0].text, 'Hello world');
        expect(controller.blocks[1].text, isEmpty);
        expect(controller.selection.focus.block, controller.blocks[1].id);
      });

      testWidgets('Backspace at offset 0 merges with the block above',
          (tester) async {
        final core = FakeCore([
          const BlockView(
            id: 1,
            kind: BlockKind.action,
            sectionLevel: 0,
            text: 'Above.',
            forced: false,
            dual: false,
            readOnly: false,
          ),
          BlockView(
            id: 2,
            kind: kind,
            sectionLevel: kind == BlockKind.section ? 1 : 0,
            text: 'Hello world',
            forced: false,
            dual: false,
            readOnly: false,
          ),
        ]);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 1, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(
          core.commands.last,
          isA<EditCommand_MergeBlocks>().having((c) => c.first, 'first', 1),
        );
        expect(controller.blocks.length, 1);
        expect(controller.blocks[0].text, 'Above.Hello world');
        // The caret lands at the join, not at the start or the end.
        expect(controller.selection.focus.offsetUtf16, 'Above.'.length);
      });

      testWidgets('Backspace inside the text deletes one character',
          (tester) async {
        final core = twoBlocks(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(
          core.commands.last,
          isA<EditCommand_ReplaceText>()
              .having((c) => c.startUtf16, 'startUtf16', 4)
              .having((c) => c.endUtf16, 'endUtf16', 5)
              .having((c) => c.with_, 'with', ''),
        );
        expect(controller.blocks[0].text, 'Hell world');
        expect(controller.selection.focus.offsetUtf16, 4);
      });

      testWidgets('Delete at the end of a block pulls the next one up',
          (tester) async {
        final core = twoBlocks(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 11);

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(
          core.commands.last,
          isA<EditCommand_MergeBlocks>().having((c) => c.first, 'first', 1),
        );
        expect(controller.blocks.length, 1);
        expect(controller.blocks[0].text, 'Hello worldSecond.');
      });
    });
  }

  testWidgets('Backspace at the very start of the script does nothing',
      (tester) async {
    final core = FakeCore.single(BlockKind.action, 'Only.');
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(core.commands, isEmpty, reason: 'nothing to ask the core for');
    expect(controller.blocks[0].text, 'Only.');
  });

  testWidgets('Delete at the very end of the script does nothing',
      (tester) async {
    final core = FakeCore.single(BlockKind.action, 'Only.');
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 5);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(core.commands, isEmpty);
    expect(controller.blocks[0].text, 'Only.');
  });

  testWidgets('a refused edit leaves the document alone and says so',
      (tester) async {
    final core = FakeCore.single(BlockKind.action, 'Verbatim.');
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 3);
    core.refuseWith = EditRejection.notEditable;

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.blocks[0].text, 'Verbatim.');
    expect(controller.lastRejection, EditRejection.notEditable);
  });

  testWidgets('Enter over a selection replaces it and then splits',
      (tester) async {
    final core = twoBlocks(BlockKind.action);
    final controller = await pumpEditor(tester, core);
    selectFromTo(controller, 0, 5, 0, 11);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.blocks.length, 3);
    expect(controller.blocks[0].text, 'Hello');
    expect(controller.blocks[1].text, isEmpty);
  });

  testWidgets('Backspace over a selection deletes it in one command',
      (tester) async {
    final core = twoBlocks(BlockKind.action);
    final controller = await pumpEditor(tester, core);
    selectFromTo(controller, 0, 5, 1, 6);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(core.commands.last, isA<EditCommand_DeleteRange>());
    expect(controller.blocks.length, 1);
    expect(controller.blocks[0].text, 'Hello.');
  });
}
