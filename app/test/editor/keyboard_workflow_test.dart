// The keyboard half of §Phase 3: the Enter and Tab wiring, and the element
// shortcuts, in every element type.
//
// The **content** of the Enter and Tab tables lives in
// `crates/document/src/workflow.rs` and is proved there and in
// `crates/bridge/src/api/doc.rs` — a copy of it in this double would be a copy
// that can disagree with the one the application actually uses (§2.1). What these
// tests prove is the part that is genuinely Dart's: that the key reaches the core
// at all, with the caret the writer had, for every element type; that Tab does
// nothing when the core says there is nothing; and that a kind change leaves the
// text and the caret exactly where they were.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/elements.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

/// Every element type a caret can be in. `opaque` is verbatim and uneditable
/// (§3.2) and has its own tests.
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

FakeCore oneBlock(BlockKind kind) => FakeCore([
      BlockView(
        id: 1,
        kind: kind,
        sectionLevel: kind == BlockKind.section ? 1 : 0,
        text: 'Hello world',
        forced: false,
        dual: false,
        readOnly: false,
      ),
    ]);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
    {bool control = false, bool shift = false}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  for (final kind in editableKinds) {
    group('${kind.name}:', () {
      testWidgets('Enter asks the core, with the caret the writer had',
          (tester) async {
        final core = oneBlock(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);

        await press(tester, LogicalKeyboardKey.enter);

        expect(core.enters, hasLength(1));
        expect(core.enters.single.focus.block, 1);
        expect(core.enters.single.focus.offsetUtf16, 5);
      });

      testWidgets('Tab asks the core, and does nothing when it answers nothing',
          (tester) async {
        final core = oneBlock(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);
        // The default: no next element type at this position.
        core.tabAnswer = null;

        await press(tester, LogicalKeyboardKey.tab);

        expect(core.tabs, hasLength(1));
        expect(core.tabs.single.$2, isFalse, reason: 'not Shift+Tab');
        expect(core.commands, isEmpty, reason: 'nothing to change');
        expect(controller.blocks[0].kind, kind);
        expect(controller.selection.focus.offsetUtf16, 5);
      });

      testWidgets('Shift+Tab asks the core the other way', (tester) async {
        final core = oneBlock(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);

        await press(tester, LogicalKeyboardKey.tab, shift: true);

        expect(core.tabs.single.$2, isTrue);
      });

      testWidgets('Tab that moves keeps the text and the caret', (tester) async {
        final core = oneBlock(kind);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);
        core.tabAnswer = BlockKind.character;

        await press(tester, LogicalKeyboardKey.tab);

        expect(controller.blocks[0].kind, BlockKind.character);
        expect(controller.blocks[0].text, 'Hello world');
        expect(controller.blocks[0].forced, isTrue, reason: 'Tab pins the choice');
        expect(controller.selection.focus.offsetUtf16, 5,
            reason: 'the caret does not jump to the end of the block');
      });
    });
  }

  group('element shortcuts:', () {
    for (final choice in elementChoices.where((c) => c.digit != null)) {
      testWidgets('Ctrl+${choice.digit} sets ${choice.label} and pins it',
          (tester) async {
        final core = oneBlock(BlockKind.action);
        final controller = await pumpEditor(tester, core);
        caretAt(controller, 0, 5);

        final key = elementShortcuts.entries
            .firstWhere((entry) => entry.value.digit == choice.digit)
            .key;
        await press(tester, key, control: true);

        expect(
          core.commands.single,
          isA<EditCommand_SetKind>()
              .having((c) => c.block, 'block', 1)
              .having((c) => c.kind, 'kind', choice.kind)
              .having((c) => c.forced, 'forced', isTrue),
        );
        // The dedicated §Phase 3 requirement: changing an element type never
        // alters the text.
        expect(controller.blocks[0].text, 'Hello world');
        expect(controller.blocks[0].kind, choice.kind);
        expect(controller.selection.focus.offsetUtf16, 5);
      });
    }

    testWidgets('the number pad reaches the same element types', (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 0);

      await press(tester, LogicalKeyboardKey.numpad1, control: true);

      expect(controller.blocks[0].kind, BlockKind.sceneHeading);
    });

    testWidgets('a digit without Ctrl is text, not a shortcut', (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 0);

      await press(tester, LogicalKeyboardKey.digit1);

      expect(core.commands, isEmpty, reason: 'a bare digit is not our key');
      expect(controller.blocks[0].kind, BlockKind.action);
    });

    testWidgets('a refused kind change leaves the caret alone', (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 5);
      core.refuseWith = EditRejection.notEditable;

      await press(tester, LogicalKeyboardKey.digit1, control: true);

      expect(controller.lastRejection, EditRejection.notEditable);
      expect(controller.blocks[0].kind, BlockKind.action);
      expect(controller.blocks[0].text, 'Hello world');
    });
  });

  group('Escape:', () {
    testWidgets('collapses the selection and changes no text', (tester) async {
      final core = FakeCore([
        const BlockView(
          id: 1,
          kind: BlockKind.action,
          sectionLevel: 0,
          text: 'Hello world',
          forced: false,
          dual: false,
          readOnly: false,
        ),
      ]);
      final controller = await pumpEditor(tester, core);
      selectFromTo(controller, 0, 2, 0, 8);

      await press(tester, LogicalKeyboardKey.escape);

      expect(controller.hasSelection, isFalse);
      expect(controller.selection.focus.offsetUtf16, 8);
      expect(controller.blocks[0].text, 'Hello world');
      expect(core.commands, isEmpty, reason: 'Escape is never an edit');
    });

    testWidgets('with nothing selected it is still not an edit', (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 4);

      await press(tester, LogicalKeyboardKey.escape);

      expect(core.commands, isEmpty);
      expect(controller.blocks[0].text, 'Hello world');
      expect(controller.selection.focus.offsetUtf16, 4);
    });
  });
}
