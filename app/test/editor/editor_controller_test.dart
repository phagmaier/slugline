// Navigation, selection, clipboard and patch application.
//
// Everything here is the editor's own responsibility under §2.1: where the caret
// goes, what the selection covers, and how a patch from the core is folded into
// the copy Flutter paints. Nothing here decides what a screenplay element is.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

BlockView _block(int id, BlockKind kind, String text) => BlockView(
      id: id,
      kind: kind,
      sectionLevel: 0,
      text: text,
      forced: false,
      dual: false,
      readOnly: false,
    );

FakeCore scene() => FakeCore([
      _block(1, BlockKind.sceneHeading, 'INT. HOUSE - DAY'),
      _block(2, BlockKind.action, 'John enters.'),
      _block(3, BlockKind.character, 'JOHN'),
      _block(4, BlockKind.dialogue, 'Hello.'),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('navigation', () {
    testWidgets('the left arrow crosses into the block above', (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 1, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(controller.selection.focus.block, 1);
      expect(controller.selection.focus.offsetUtf16, 'INT. HOUSE - DAY'.length);
    });

    testWidgets('the right arrow crosses into the block below', (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 0, 16);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(controller.selection.focus.block, 2);
      expect(controller.selection.focus.offsetUtf16, 0);
    });

    testWidgets('the down arrow crosses the blank rows between elements',
        (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 0, 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // Two blank rows sit between a heading and the action under it; Down must
      // land on the text, not in the gap.
      expect(controller.selection.focus.block, 2);
      expect(controller.selection.focus.offsetUtf16, 4);
    });

    testWidgets('a horizontal move keeps a column for later vertical moves',
        (tester) async {
      final core = FakeCore([
        _block(1, BlockKind.action, 'a very long first line of action'),
        _block(2, BlockKind.action, 'short'),
        _block(3, BlockKind.action, 'another long line of action here'),
      ]);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 20);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 5, reason: 'clamped');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.selection.focus.block, 3);
      expect(controller.selection.focus.offsetUtf16, 20,
          reason: 'the original column survives the short line');
    });

    testWidgets('the caret after a newline is on the next visual row',
        (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'One.\nTwo.'),
      );
      caretAt(controller, 0, 5);

      expect(controller.caretRow, 1);
    });

    testWidgets('vertical movement reaches the start of a hard line',
        (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'One.\nTwo.'),
      );
      caretAt(controller, 0, 0);

      controller.moveVertical(1);
      await tester.pump();

      expect(controller.selection.focus.offsetUtf16, 5);
      expect(controller.caretRow, 1);
    });

    testWidgets('Home and End move within the visual line', (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 1, 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 'John enters.'.length);
    });

    testWidgets('Ctrl+Home and Ctrl+End reach the ends of the script',
        (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 1, 5);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(controller.selection.focus.block, 4);
      expect(controller.selection.focus.offsetUtf16, 'Hello.'.length);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(controller.selection.focus.block, 1);
      expect(controller.selection.focus.offsetUtf16, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('PageDown and PageUp move by a screen and stop at the ends',
        (tester) async {
      final core = FakeCore([
        for (var i = 1; i <= 60; i++) _block(i, BlockKind.action, 'Line $i.'),
      ]);
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(controller.selection.focus.block, greaterThan(1));

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pump();
      }
      expect(controller.selection.focus.block, 1,
          reason: 'PageUp stops at the top rather than running off it');
    });

    testWidgets('the caret steps over an emoji rather than into it',
        (tester) async {
      // 'a🎬b' is four UTF-16 code units; offset 2 is inside the surrogate pair,
      // and an offset the core would refuse (ADR 0001).
      final core = FakeCore.single(BlockKind.action, 'a🎬b');
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 1);
    });

    testWidgets('Backspace deletes a whole emoji', (tester) async {
      final core = FakeCore.single(BlockKind.action, 'a🎬b');
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.blocks[0].text, 'ab');
    });
  });

  group('selection', () {
    testWidgets('Shift with an arrow extends across blocks', (tester) async {
      final controller = await pumpEditor(tester, scene());
      caretAt(controller, 1, 12);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.hasSelection, isTrue);
      expect(controller.selection.anchor.block, 2, reason: 'the anchor stays');
      expect(controller.selection.focus.block, 4);
    });

    testWidgets('Ctrl+A selects the whole script', (tester) async {
      final controller = await pumpEditor(tester, scene());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final (start, end) = controller.orderedSelection;
      expect(start.block, 1);
      expect(start.offsetUtf16, 0);
      expect(end.block, 4);
      expect(end.offsetUtf16, 'Hello.'.length);
    });

    testWidgets('an unshifted arrow collapses the selection to its edge',
        (tester) async {
      final controller = await pumpEditor(tester, scene());
      selectFromTo(controller, 1, 4, 3, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(controller.hasSelection, isFalse);
      expect(controller.selection.focus.block, controller.blocks[1].id);
      expect(controller.selection.focus.offsetUtf16, 4);
    });

    testWidgets('no click lands inside an emoji', (tester) async {
      // One scalar is one column (`docs/LINE_BREAKING.md`), so the emoji is
      // column 1 whole and no column addresses the middle of its surrogate
      // pair. The caret cannot come to rest on an offset the core refuses
      // (ADR 0001) because no click can name one.
      final controller = await pumpEditor(tester, FakeCore.single(BlockKind.action, 'a\u{1F3AC}b'));

      controller.placeCaretAt(0, 1);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 1, reason: 'before it');

      controller.placeCaretAt(0, 2);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 3, reason: 'after it');

      controller.placeCaretAt(0, 3);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 4, reason: 'end of line');
    });

    testWidgets('a click inside a tab expansion is still a model offset',
        (tester) async {
      // The tab is one character of the model and four columns of the grid.
      // Clicking any of them puts the caret before the tab: a click resolves to
      // a model offset, never to a column the document does not have.
      final controller = await pumpEditor(
          tester, FakeCore.single(BlockKind.action, '\tabc'));

      for (final column in [0, 1, 2, 3]) {
        controller.placeCaretAt(0, column);
        await tester.pump();
        expect(controller.selection.focus.offsetUtf16, 0,
            reason: 'column $column is inside the tab');
      }

      controller.placeCaretAt(0, 4);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 1, reason: 'the a');

      controller.placeCaretAt(0, 7);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 4, reason: 'end of line');
    });

    testWidgets('a caret in a combining sequence steps off the cluster',
        (tester) async {
      // A cluster is one column per scalar, so a click can land between the
      // letter and its mark. Grapheme safety is the editor's, not the grid's.
      final controller = await pumpEditor(
          tester, FakeCore.single(BlockKind.action, 'ae\u{301}b'));

      controller.placeCaretAt(0, 2);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 1,
          reason: 'back to the start of the cluster');
    });

    testWidgets('a click places the caret and a drag extends from it',
        (tester) async {
      final controller = await pumpEditor(tester, scene());
      final surface = tester.getTopLeft(find.byType(EditorSurface));

      final gesture = await tester.startGesture(surface + const Offset(40, 40));
      await tester.pump();
      final anchor = controller.selection.anchor;

      await gesture.moveTo(surface + const Offset(200, 160));
      await tester.pump();
      await gesture.up();

      expect(controller.selection.anchor, anchor, reason: 'the anchor is the click');
      expect(controller.hasSelection, isTrue);
    });

    testWidgets('a click on the second hard line maps into that line',
        (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'One.\nTwo.'),
      );
      final surface = tester.getTopLeft(find.byType(EditorSurface));

      await tester.tapAt(surface + editorCell(1, 0));
      await tester.pump();

      expect(controller.selection.focus.offsetUtf16, 5);
    });

    testWidgets('selection extends across a hard newline', (tester) async {
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'One.\nTwo.'),
      );
      final surface = tester.getTopLeft(find.byType(EditorSurface));

      final gesture = await tester.startGesture(surface + editorCell(0, 0));
      await gesture.moveTo(surface + editorCell(1, 0));
      await tester.pump();
      await gesture.up();

      expect(controller.selection.anchor.offsetUtf16, 0);
      expect(controller.selection.focus.offsetUtf16, 5);
      expect(controller.caretRow, 1);
    });

    testWidgets('selection crosses hard and soft wraps', (tester) async {
      final first = 'a' * 65;
      final second = 'b' * 65;
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, '$first\n$second'),
      );
      caretAt(controller, 0, 2);

      controller.moveVertical(3, extend: true);
      await tester.pump();

      expect(controller.layout.linesOf(0).length, 4);
      expect(controller.selection.anchor.offsetUtf16, 2);
      expect(controller.selection.focus.offsetUtf16, 128);
      expect(controller.caretRow, 3);
    });
  });

  group('applying what the core says', () {
    testWidgets('an edit patches the editor rather than refetching',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      final readsAfterLoad = core.blockReads;
      caretAt(controller, 1, 5);

      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      }
      await tester.pump();

      expect(core.blockReads, readsAfterLoad,
          reason: 'the document is never read back (§6)');
      expect(controller.blocks[1].text, 'enters.');
    });

    testWidgets('inserted blocks land at the index the core gave them',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.blocks.map((b) => b.text), [
        'INT.',
        ' HOUSE - DAY',
        'John enters.',
        'JOHN',
        'Hello.',
      ]);
      // And the row index was rebuilt, so the new block has somewhere to be.
      expect(controller.layout.totalRows, greaterThan(0));
      expect(controller.caretRow, controller.layout.rowAt(1, 0));
    });

    testWidgets('undo puts the caret back where the edit started',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.blocks[1].text, 'Joh enters.');

      // The selection the editor handed over is the one the core stores for the
      // undo — the caret before the edit, not after it.
      expect(core.priorSelections.last?.focus.offsetUtf16, 4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.blocks[1].text, 'John enters.');
    });

    testWidgets('an incremental edit inserts and lays out a hard newline',
        (tester) async {
      final core = FakeCore.single(BlockKind.action, 'One.Two.');
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 4);

      controller.insertText('\n');
      await tester.pump();

      expect(controller.blocks.single.text, 'One.\nTwo.');
      expect(controller.layout.linesOf(0).length, 2);
      expect(controller.caretRow, 1);
      expect(core.blockReads, 1, reason: 'the patch is applied in place');
    });

    testWidgets('an incremental edit removes and relays out a hard newline',
        (tester) async {
      final core = FakeCore.single(BlockKind.action, 'One.\nTwo.');
      final controller = await pumpEditor(tester, core);
      expect(controller.layout.linesOf(0).length, 2);
      caretAt(controller, 0, 5);

      controller.deleteBackward();
      await tester.pump();

      expect(controller.blocks.single.text, 'One.Two.');
      expect(controller.layout.linesOf(0).length, 1);
      expect(controller.layout.totalRows, 1);
      expect(core.blockReads, 1, reason: 'the patch is applied in place');
    });
  });

  group('clipboard', () {
    testWidgets('copy and paste preserve an embedded hard newline',
        (tester) async {
      final clipboard = _FakeClipboard(tester);
      final controller = await pumpEditor(
        tester,
        FakeCore.single(BlockKind.action, 'One.\nTwo.'),
      );
      selectFromTo(controller, 0, 0, 0, 9);

      await controller.copy();
      expect(clipboard.text, 'One.\nTwo.');

      caretAt(controller, 0, 5);
      clipboard.text = 'X';
      await controller.paste(plain: true);
      await tester.pump();

      expect(controller.blocks.single.text, 'One.\nXTwo.');
      expect(controller.layout.linesOf(0).length, 2);
      expect(controller.caretRow, 1);
    });

    testWidgets('copy asks the core for the selection as Fountain',
        (tester) async {
      final clipboard = _FakeClipboard(tester);
      final controller = await pumpEditor(tester, scene());
      selectFromTo(controller, 2, 0, 3, 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboard.text, 'JOHN\n\nHello.');
      expect(controller.blocks.length, 4, reason: 'copy changes nothing');
    });

    testWidgets('cut copies and then deletes', (tester) async {
      final clipboard = _FakeClipboard(tester);
      final controller = await pumpEditor(tester, scene());
      selectFromTo(controller, 0, 5, 0, 10);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(clipboard.text, 'HOUSE');
      expect(controller.blocks[0].text, 'INT.  - DAY');
    });

    testWidgets('paste sends the clipboard to the core as Fountain',
        (tester) async {
      final clipboard = _FakeClipboard(tester)..text = 'CUT TO:';
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(core.pastes.single.$2, 'CUT TO:');
      expect(core.pastes.single.$3, isFalse, reason: 'Fountain-aware');
      expect(clipboard.text, 'CUT TO:');
      expect(controller.blocks[1].text, 'CUT TO:John enters.');
    });

    testWidgets('Ctrl+Shift+V pastes as plain text', (tester) async {
      _FakeClipboard(tester).text = 'INT. OTHER - NIGHT';
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(core.pastes.single.$3, isTrue, reason: 'no element inference');
      expect(controller.blocks.length, 4);
    });
  });

  group('typing', () {
    testWidgets('a character from the platform becomes one ReplaceText',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 4);

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'JohnX enters.',
        selection: TextSelection.collapsed(offset: 5),
      ));
      await tester.pump();

      expect(
        core.commands.last,
        isA<EditCommand_ReplaceText>()
            .having((c) => c.startUtf16, 'startUtf16', 4)
            .having((c) => c.endUtf16, 'endUtf16', 4)
            .having((c) => c.with_, 'with', 'X'),
      );
      expect(controller.blocks[1].text, 'JohnX enters.');
    });

    testWidgets('typing over a cross-block selection is one paste',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      selectFromTo(controller, 1, 4, 3, 4);

      controller.insertText('!');
      await tester.pump();

      expect(core.pastes.single.$2, '!');
      expect(core.pastes.single.$3, isTrue,
          reason: 'a typed character is text, not Fountain');
      expect(controller.blocks.length, 2, reason: 'two blocks were absorbed');
      expect(controller.blocks[1].text, 'John!o.');
    });

    testWidgets('a newline from the platform splits rather than being stored',
        (tester) async {
      final core = scene();
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 1, 4);

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'John\n enters.',
        selection: TextSelection.collapsed(offset: 5),
      ));
      await tester.pump();

      expect(controller.blocks.map((b) => b.text),
          ['INT. HOUSE - DAY', 'John', ' enters.', 'JOHN', 'Hello.']);
      for (final block in controller.blocks) {
        expect(block.text, isNot(contains('\n')));
      }
    });
  });

  // F12. An id the editor no longer has used to resolve to index 0, so a stale
  // caret aimed its edit at the first block of the script — silently, and in the
  // one program where the first block of the script is somebody's screenplay.
  group('a block id this document does not have', () {
    /// A controller with no surface attached, so that the caret can be left on
    /// a block that does not exist. With one attached the repair below happens
    /// on the very next repaint, which is the point of it but leaves nothing to
    /// observe.
    EditorController ghostCaret(FakeCore core) {
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      const ghost = DocPosition(block: 9999, offsetUtf16: 0);
      controller.setSelection(
        const DocSelection(anchor: ghost, focus: ghost),
      );
      core.commands.clear();
      return controller;
    }

    test('an edit is refused rather than aimed at block 0', () {
      final core = scene();
      final controller = ghostCaret(core);
      final before = [for (final block in controller.blocks) block.text];

      for (final edit in [
        controller.deleteForward,
        controller.deleteBackward,
        () => controller.deleteWord(forward: true),
        () => controller.deleteWord(forward: false),
      ]) {
        controller.lastRejection = null;
        // A debug build stops here — drift between the editor and the core is a
        // bug, not a mode of operation. The refusal is recorded first, so both
        // halves of the behaviour are visible from one call.
        expect(edit, throwsAssertionError);
        expect(controller.lastRejection, EditRejection.unknownBlock);
      }

      expect(core.commands, isEmpty, reason: 'the core was never asked');
      expect([for (final block in controller.blocks) block.text], before);
    });

    test('moving the caret puts it somewhere that exists', () {
      final core = scene();
      final controller = ghostCaret(core);

      expect(() => controller.moveHorizontal(1), throwsAssertionError);

      // The assertion fired on the way out, but the repair happened first: the
      // caret names a block that is here, so the next keystroke — and the IME,
      // which writes into the focused block by id — cannot reach one that is
      // not.
      expect(controller.selection.focus.block, controller.blocks.first.id);
      expect(controller.selection.focus.offsetUtf16, 0);
      expect(controller.focusedBlock.id, controller.blocks.first.id);
      expect(core.commands, isEmpty);
    });
  });

  group('the session', () {
    test('is closed exactly once when the editor goes away', () {
      final core = scene();
      final controller = EditorController(core);

      expect(core.closes, 0);
      controller.dispose();
      // Closing ends an actor thread. Two closes were harmless only while
      // closing did nothing at all (F12).
      expect(core.closes, 1);
    });
  });
}

/// Records what the app puts on the clipboard, and answers what it asks for.
class _FakeClipboard {
  _FakeClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            text = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return {'text': text};
          default:
            return null;
        }
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  String? text;
}
