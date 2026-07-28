// §Phase 3's "visible element selector in the UI showing the current block's
// type", and the `Ctrl+K` command palette.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/commands.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/element_bar.dart';
import 'package:slugline/editor/elements.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

FakeCore oneBlock(BlockKind kind, {String text = 'Hello world', bool readOnly = false}) =>
    FakeCore([
      BlockView(
        id: 1,
        kind: kind,
        sectionLevel: kind == BlockKind.section ? 2 : 0,
        text: text,
        forced: false,
        dual: false,
        readOnly: readOnly,
      ),
    ]);

Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  group('the element bar:', () {
    testWidgets('names the element the caret is in', (tester) async {
      await pumpEditorPage(tester, oneBlock(BlockKind.parenthetical));
      expect(find.text('Parenthetical'), findsOneWidget);
    });

    testWidgets('a section shows its level', (tester) async {
      await pumpEditorPage(tester, oneBlock(BlockKind.section));
      expect(find.text('Section 2'), findsOneWidget);
    });

    testWidgets('follows the caret across blocks', (tester) async {
      final controller = await pumpEditorPage(
        tester,
        FakeCore([
          const BlockView(
            id: 1,
            kind: BlockKind.sceneHeading,
            sectionLevel: 0,
            text: 'INT. HOUSE - DAY',
            forced: false,
            dual: false,
            readOnly: false,
          ),
          const BlockView(
            id: 2,
            kind: BlockKind.dialogue,
            sectionLevel: 0,
            text: 'Hello.',
            forced: false,
            dual: false,
            readOnly: false,
          ),
        ]),
      );
      caretAt(controller, 0, 0);
      await tester.pump();
      expect(find.text('Scene heading'), findsOneWidget);

      caretAt(controller, 1, 0);
      await tester.pump();

      expect(find.text('Dialogue'), findsOneWidget);
      expect(find.text('Scene heading'), findsNothing);
    });

    testWidgets('sets the element type when one is picked', (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditorPage(tester, core);
      caretAt(controller, 0, 5);

      await tester.tap(find.byKey(const Key('element-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transition').last);
      await tester.pumpAndSettle();

      expect(
        core.commands.single,
        isA<EditCommand_SetKind>()
            .having((c) => c.kind, 'kind', BlockKind.transition)
            .having((c) => c.forced, 'forced', isTrue),
      );
      expect(controller.blocks[0].text, 'Hello world',
          reason: 'changing an element type never alters the text');
    });

    testWidgets('offers nothing for a block that round-trips verbatim',
        (tester) async {
      final core = oneBlock(BlockKind.opaque, text: '/* hidden */', readOnly: true);
      await pumpEditorPage(tester, core);

      await tester.tap(find.byKey(const Key('element-selector')));
      await tester.pumpAndSettle();

      expect(find.text('Transition'), findsNothing);
      expect(core.commands, isEmpty);
    });

    testWidgets('shows what Tab would do next', (tester) async {
      final core = oneBlock(BlockKind.action);
      core.tabAnswer = BlockKind.character;
      await pumpEditorPage(tester, core);

      expect(
        tester.widget<Text>(find.byKey(const Key('tab-hint'))).data,
        'Tab: Character',
      );
    });

    testWidgets('shows the cue the core suggests, without applying it',
        (tester) async {
      final core = oneBlock(BlockKind.action, text: 'JOHN');
      core.suggestion = 'JOHN';
      final controller = await pumpEditorPage(tester, core);

      expect(
        tester.widget<Text>(find.byKey(const Key('tab-hint'))).data,
        'Tab: Character — JOHN',
      );
      expect(controller.blocks[0].kind, BlockKind.action);
      expect(core.commands, isEmpty);
    });
  });

  group('the command palette:', () {
    testWidgets('Ctrl+K opens it and Escape closes it, losing no text',
        (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditorPage(tester, core);

      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(find.text('Element or command'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Element or command'), findsNothing);
      expect(controller.blocks[0].text, 'Hello world');
      expect(core.commands, isEmpty);
    });

    testWidgets('Escape closes it after another panel had focus', (tester) async {
      final core = oneBlock(BlockKind.action)
        ..completions = const [
          Completion(
            kind: CompletionKind.character,
            value: 'HELLO WORLD',
            startUtf16: 0,
            endUtf16: 5,
            frequency: 1,
            pinned: false,
          ),
        ];
      final controller = await pumpEditorPage(tester, core);

      await pressCtrl(tester, LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      expect(find.text('Element or command'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Element or command'), findsNothing);
      expect(controller.blocks.single.text, 'Hello world');
      expect(core.commands, isEmpty);
    });

    testWidgets('reaches every element type', (tester) async {
      // The list is longer than the panel, so each one is asked for by name —
      // which is how a writer reaches the ones below the fold too.
      await pumpEditorPage(tester, oneBlock(BlockKind.action));
      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      for (final choice in elementChoices) {
        await tester.enterText(find.byType(TextField), choice.label);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text(choice.label),
          ),
          findsOneWidget,
          reason: '${choice.label} is not in the palette',
        );
      }
    });

    testWidgets('filtering then Enter runs the highlighted command',
        (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditorPage(tester, core);
      caretAt(controller, 0, 3);

      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'transition');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        core.commands.single,
        isA<EditCommand_SetKind>()
            .having((c) => c.kind, 'kind', BlockKind.transition),
      );
      // The palette closes itself out of the way first, so the caret comes back
      // to the surface.
      expect(find.text('Element or command'), findsNothing);
      expect(controller.blocks[0].text, 'Hello world');
    });

    testWidgets('a click outside dismisses it', (tester) async {
      await pumpEditorPage(tester, oneBlock(BlockKind.action));
      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 560));
      await tester.pumpAndSettle();

      expect(find.text('Element or command'), findsNothing);
    });

    testWidgets('closing it gives the keyboard back to the editor',
        (tester) async {
      final core = oneBlock(BlockKind.action);
      final controller = await pumpEditorPage(tester, core);
      caretAt(controller, 0, 5);

      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // A key the surface owns has to work again straight away.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.selection.focus.offsetUtf16, 4,
          reason: 'the surface never got the focus back');
    });

    testWidgets('a query that matches nothing says so', (tester) async {
      await pumpEditorPage(tester, oneBlock(BlockKind.action));
      await pressCtrl(tester, LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('No matching command'), findsOneWidget);
    });
  });

  group('the command list:', () {
    List<EditorCommand> commands() => editorCommands(
          controller: EditorController(oneBlock(BlockKind.action)),
          openFind: () {},
        );

    test('an empty query keeps the declared order', () {
      final all = commands();
      expect(filterCommands(all, ''), all);
      expect(filterCommands(all, '   '), all);
    });

    test('a subsequence matches, not just a substring', () {
      // `sh` is not a substring of "Scene heading"; the letters are in order.
      expect(filterCommands(commands(), 'sh').first.label, 'Scene heading');
      final paste = filterCommands(commands(), 'pas').map((c) => c.label);
      expect(paste, containsAllInOrder(['Paste', 'Paste as plain text']));
    });

    test('a match at the start of a word beats one in the middle of one', () {
      // `pb` is in "Page break" at two word starts, and in "Paste as plain
      // text" only mid-word.
      expect(filterCommands(commands(), 'pb').first.label, 'Page break');
    });

    test('a query nothing matches gives nothing', () {
      expect(filterCommands(commands(), 'qqqq'), isEmpty);
    });

    test('every element type and every editing command is reachable', () {
      final labels = commands().map((c) => c.label).toSet();
      for (final choice in elementChoices) {
        expect(labels, contains(choice.label));
      }
      expect(
        labels,
        containsAll([
          'Undo',
          'Redo',
          'Cut',
          'Copy',
          'Paste',
          'Paste as plain text',
          'Select all',
          'Find and replace',
          'Next element type',
          'Previous element type',
        ]),
      );
    });
  });

  group('refusals:', () {
    test('the two a writer can act on get a sentence of their own', () {
      expect(rejectionMessage(EditRejection.notEditable), contains('verbatim'));
      expect(rejectionMessage(EditRejection.noBlockAfter), contains('join'));
      expect(rejectionMessage(EditRejection.badOffset), 'That edit was refused.');
    });
  });

  group('a narrow window:', () {
    // The bar is one `Row` holding a refusal sentence and a Tab hint, either of
    // which is wider than a tiled window. It used to overflow, and an
    // overflowing `Row` does not shrink — it paints its children off the edge
    // and drops the rest, so the counts on the right went missing rather than
    // getting shorter. Both long labels ellipsize now.
    Future<void> pumpAt(WidgetTester tester, double width) async {
      final core = oneBlock(BlockKind.action);
      core.refuseWith = EditRejection.notEditable;
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      controller.insertText('x');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: ElementBar(controller: controller, sceneCount: 1),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('does not overflow the element bar', (tester) async {
      for (final width in [1280.0, 800.0, 480.0, 320.0, 200.0]) {
        await pumpAt(tester, width);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the element bar overflowed at ${width}px',
        );
      }
    });

    testWidgets('keeps the counts, which are the shortest thing on it',
        (tester) async {
      await pumpAt(tester, 480);
      expect(find.textContaining('1 scene'), findsOneWidget);
    });
  });
}
