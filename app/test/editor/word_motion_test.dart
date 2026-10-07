// Word-wise motion and deletion, and the multi-click selections.
//
// ADR 0005 lists both as Phase 3 work: they are the part of the input surface the
// spike did not implement, and `EditableText` would have provided free. They are
// plain text editing, not screenplay semantics, so they live in the controller and
// are proved here.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

const _line = "John enters the café. He doesn't speak.";

FakeCore twoBlocks() => FakeCore([
  const BlockView(
    id: 1,
    kind: BlockKind.action,
    sectionLevel: 0,
    text: _line,
    forced: false,
    dual: false,
    readOnly: false,
  ),
  const BlockView(
    id: 2,
    kind: BlockKind.action,
    sectionLevel: 0,
    text: 'Second paragraph.',
    forced: false,
    dual: false,
    readOnly: false,
  ),
]);

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  group('word boundaries:', () {
    test('a word ends where the word characters do', () {
      expect(wordEndAfter(_line, 0), 4, reason: 'John');
      expect(wordEndAfter(_line, 4), 11, reason: ' enters');
      // An accented letter is a letter, which `\w` would not have agreed with.
      expect(wordEndAfter(_line, 15), 20, reason: ' café');
      // An apostrophe holds a word together.
      expect(wordEndAfter(_line, 24), 32, reason: " doesn't");
      expect(wordEndAfter(_line, _line.length), _line.length);
    });

    test('and starts where they begin', () {
      expect(wordStartBefore(_line, _line.length), 33, reason: 'speak');
      expect(wordStartBefore(_line, 4), 0, reason: 'John');
      expect(wordStartBefore(_line, 0), 0);
      // From inside a word, back to the front of it.
      expect(wordStartBefore(_line, 2), 0);
      expect(wordStartBefore(_line, 20), 16, reason: 'café');
    });

    test('punctuation and space are skipped, never landed on', () {
      // From the '.' after "café" — it and the space are skipped, then "He".
      expect(wordEndAfter(_line, 20), 24);
      expect(wordStartBefore(_line, 23), 22);
    });

    // F12. A word was classified one UTF-16 code unit at a time, and half a
    // surrogate pair is not a character: `\p{L}` matches neither half, so every
    // letter outside the BMP read as punctuation and Ctrl+arrow stepped over it
    // as if it were a comma. Offsets are still UTF-16 (ADR 0008) — only what
    // counts as a letter is now asked per whole character.
    test('a letter outside the BMP is a letter', () {
      // 'Hi ' then three mathematical bold capitals, two code units each.
      const line = 'Hi 𝐁𝐎𝐁 there.';
      expect(line.length, 16, reason: 'UTF-16 code units, not characters');

      expect(wordEndAfter(line, 2), 9, reason: 'over 𝐁𝐎𝐁, and no further');
      expect(wordStartBefore(line, 9), 3, reason: 'back to the start of it');
      expect(wordEndAfter(line, 0), 2, reason: 'Hi');
      expect(wordEndAfter(line, 9), 15, reason: ' there');

      // And an astral letter still holds a word together across an apostrophe.
      const cue = "𝐁𝐎𝐁's hat";
      expect(wordEndAfter(cue, 0), 8);
      expect(wordStartBefore(cue, 8), 0);
    });

    test('an emoji is punctuation, and is stepped over whole', () {
      const line = 'A 🎬 slate';
      expect(line.length, 10);
      expect(wordEndAfter(line, 1), 10, reason: 'skipped, then "slate"');
      expect(wordStartBefore(line, 10), 5, reason: 'slate');
      // From between the halves of the pair — where no caret may rest, but
      // where a clamped offset can still arrive — the step is over the whole
      // character rather than round and round one half of it.
      expect(wordEndAfter(line, 3), 10);
      expect(wordStartBefore(line, 3), 0);
    });
  });

  group('Ctrl+arrow:', () {
    testWidgets('moves one word at a time', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      caretAt(controller, 0, 0);

      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.offsetUtf16, 4);
      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.offsetUtf16, 11);
      await press(tester, LogicalKeyboardKey.arrowLeft, control: true);
      expect(controller.selection.focus.offsetUtf16, 5);
    });

    testWidgets('stops at the end of a block before crossing it', (
      tester,
    ) async {
      final controller = await pumpEditor(tester, twoBlocks());
      // Inside the last word, "speak".
      caretAt(controller, 0, 35);

      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.block, 1);
      expect(
        controller.selection.focus.offsetUtf16,
        38,
        reason: 'past "speak"',
      );

      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.block, 1);
      expect(
        controller.selection.focus.offsetUtf16,
        _line.length,
        reason: 'past the full stop, and no further',
      );

      // Only the next press crosses.
      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.block, 2);
      expect(controller.selection.focus.offsetUtf16, 0);
    });

    testWidgets('goes nowhere at the ends of the script', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      caretAt(controller, 0, 0);
      await press(tester, LogicalKeyboardKey.arrowLeft, control: true);
      expect(controller.selection.focus.block, 1);
      expect(controller.selection.focus.offsetUtf16, 0);

      caretAt(controller, 1, 17);
      await press(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selection.focus.block, 2);
      expect(controller.selection.focus.offsetUtf16, 17);
    });

    testWidgets('with Shift it extends the selection', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      caretAt(controller, 0, 0);

      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        control: true,
        shift: true,
      );
      expect(controller.hasSelection, isTrue);
      expect(controller.selection.anchor.offsetUtf16, 0);
      expect(controller.selection.focus.offsetUtf16, 4);
    });
  });

  group('Ctrl+Backspace and Ctrl+Delete:', () {
    testWidgets('delete a word in one command', (tester) async {
      final core = twoBlocks();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 11);

      await press(tester, LogicalKeyboardKey.backspace, control: true);

      expect(
        core.commands.single,
        isA<EditCommand_ReplaceText>()
            .having((c) => c.startUtf16, 'startUtf16', 5)
            .having((c) => c.endUtf16, 'endUtf16', 11)
            .having((c) => c.with_, 'with', ''),
      );
      // The word goes; the spaces either side of it are not part of it.
      expect(controller.blocks[0].text, "John  the café. He doesn't speak.");
    });

    testWidgets('forwards, the same', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      caretAt(controller, 0, 4);

      await press(tester, LogicalKeyboardKey.delete, control: true);

      expect(controller.blocks[0].text, "John the café. He doesn't speak.");
    });

    testWidgets('at offset 0 it joins the block above instead', (tester) async {
      final core = twoBlocks();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 0);

      await press(tester, LogicalKeyboardKey.backspace, control: true);

      expect(core.commands.single, isA<EditCommand_MergeBlocks>());
      expect(controller.blocks, hasLength(1));
    });

    testWidgets('over a selection it deletes the selection', (tester) async {
      final core = twoBlocks();
      final controller = await pumpEditor(tester, core);
      selectFromTo(controller, 0, 0, 0, 4);

      await press(tester, LogicalKeyboardKey.backspace, control: true);

      expect(controller.blocks[0].text, " enters the café. He doesn't speak.");
    });
  });

  group('selecting by grid position:', () {
    // Action sits at indent 0 (§5.2), so on its first row a column *is* an
    // offset — which is what lets these name exact positions rather than
    // depending on where the page happens to be centred.
    testWidgets('a word, from a point inside it', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());

      controller.selectWordAt(0, 13); // inside "the"
      expect(controller.selectedText(), 'the');

      controller.selectWordAt(0, 0); // the first letter of "John"
      expect(controller.selectedText(), 'John');

      controller.selectWordAt(0, 27); // inside "doesn't"
      expect(controller.selectedText(), "doesn't");

      controller.selectWordAt(0, 17); // inside "café"
      expect(controller.selectedText(), 'café');
    });

    testWidgets('a point on a space reaches the word after it', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      controller.selectWordAt(0, 4); // the space before "enters"
      expect(controller.selectedText(), ' enters');
    });

    testWidgets('the whole element, from anywhere in it', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      controller.selectBlockAt(0, 13);
      expect(controller.selectedText(), _line);
    });

    testWidgets('a word written outside the BMP', (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'Hi 𝐁𝐎𝐁 there.'),
      );

      controller.selectWordAt(0, 4); // the second character of 𝐁𝐎𝐁
      expect(controller.selectedText(), '𝐁𝐎𝐁');
    });

    // The probe used to be one code unit clamped to `text.length - 1`, which on
    // an empty block is -1 — and `clamp(0, -1)` throws. A blank action line
    // between two paragraphs is not an unusual thing to double-click on.
    testWidgets('nothing at all, on an empty block', (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, ''),
      );

      controller.selectWordAt(0, 0);
      expect(controller.hasSelection, isFalse);
      expect(controller.selection.focus.offsetUtf16, 0);
    });
  });

  group('clicking:', () {
    /// A click on the first row of the first block, [times] times, [gap] apart.
    ///
    /// The timestamps are explicit because a synthetic pointer event's default is
    /// `Duration.zero` — every click would look simultaneous, and the surface
    /// counts clicks by the clock.
    Future<void> click(
      WidgetTester tester, {
      int times = 1,
      Duration at = const Duration(milliseconds: 100),
      Duration gap = const Duration(milliseconds: 30),
    }) async {
      final surface = tester.getTopLeft(find.byType(EditorSurface));
      // A little in from the left of the page and onto the first row.
      final where = surface + const Offset(300, 32);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      var now = at;
      for (var i = 0; i < times; i++) {
        await gesture.down(where, timeStamp: now);
        await gesture.up(timeStamp: now);
        now += gap;
        await tester.pump();
      }
    }

    testWidgets('once places the caret in the block that was clicked', (
      tester,
    ) async {
      final controller = await pumpEditor(tester, twoBlocks());
      await click(tester);

      expect(controller.hasSelection, isFalse);
      expect(controller.selection.focus.block, 1);
    });

    testWidgets('twice selects one word of it', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      await click(tester, times: 2);

      final selected = controller.selectedText();
      expect(selected, isNotNull);
      expect(selected, isNot(_line), reason: 'a word, not the paragraph');
      expect(selected!.trim(), isNotEmpty);
      expect(_line, contains(selected));
    });

    testWidgets('three times selects the whole element', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      await click(tester, times: 3);

      expect(controller.selectedText(), _line);
    });

    testWidgets('two slow clicks are two single clicks', (tester) async {
      final controller = await pumpEditor(tester, twoBlocks());
      await click(tester, at: const Duration(milliseconds: 100));
      // Well outside the 400 ms window.
      await click(tester, at: const Duration(milliseconds: 900));

      expect(controller.hasSelection, isFalse);
    });
  });
}
