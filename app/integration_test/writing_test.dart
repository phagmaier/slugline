// §Phase 3's exit criteria, against the real `libslugline_bridge.so`:
//
//   * "You can write a full scene without touching the mouse."
//   * "Element-type changes are provably non-destructive."
//
// Run with:
//
//     flutter test integration_test/writing_test.dart -d linux
//
// The widget tests in `test/editor/` prove the wiring against a double, and
// `cargo test` proves the tables and the inference rules. What only this can
// prove is the whole chain at once: keystroke → EditCommand → re-classification →
// patch → Fountain, and that the Fountain reads back as the scene that was typed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Core.init();
  });

  Future<EditorController> open(WidgetTester tester, [String? source]) async {
    final controller = EditorController(
      source == null ? RustDocumentCore.create() : RustDocumentCore.parse(source),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: EditorPage(controller: controller)));
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    return controller;
  }

  /// Types [text] a character at a time, as a writer does — so that automatic
  /// classification is asked the same question on every keystroke that it will be
  /// asked in the application.
  Future<void> type(WidgetTester tester, EditorController controller, String text) async {
    for (final character in text.characters) {
      controller.insertText(character);
    }
    await tester.pump();
  }

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

  List<BlockKind> kinds(EditorController controller) =>
      controller.blocks.map((block) => block.kind).toList();

  // --- the exit criterion ------------------------------------------------

  testWidgets('a whole scene, keyboard only, with nothing set by hand',
      (tester) async {
    final controller = await open(tester);

    // The slug line promotes itself as it is typed.
    await type(tester, controller, 'INT. HOUSE - DAY');
    expect(kinds(controller), [BlockKind.sceneHeading]);
    expect(controller.blocks.single.forced, isFalse,
        reason: 'inference never pins; only the writer does');

    // Enter after a heading gives action.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await type(tester, controller, 'John enters, holding a letter.');

    // A cue: type the name, Tab.
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, controller, 'JOHN');
    await press(tester, LogicalKeyboardKey.tab);
    expect(kinds(controller).last, BlockKind.character);

    // Enter after a cue gives dialogue, and Tab in the empty dialogue block that
    // appears turns it into the parenthetical — the standard "cue, Tab, wryly".
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.dialogue);
    await press(tester, LogicalKeyboardKey.tab);
    expect(kinds(controller).last, BlockKind.parenthetical);
    await type(tester, controller, '(quietly)');

    // Enter after a parenthetical gives dialogue again.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.dialogue);
    await type(tester, controller, 'It came.');

    // Enter after dialogue gives action; a transition writes itself.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await type(tester, controller, 'CUT TO:');
    expect(kinds(controller).last, BlockKind.transition);

    expect(kinds(controller), [
      BlockKind.sceneHeading,
      BlockKind.action,
      BlockKind.character,
      BlockKind.parenthetical,
      BlockKind.dialogue,
      BlockKind.transition,
    ]);

    // The file it writes: the cue carries `@` because Tab pinned it, and nothing
    // else needs a marker at all.
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\n'
      'John enters, holding a letter.\n\n'
      '@JOHN\n'
      '(quietly)\n'
      'It came.\n\n'
      'CUT TO:\n',
    );

    // And reopening that file gives back the same elements, which is the whole
    // point of inference agreeing with the parser.
    final reopened = EditorController(RustDocumentCore.parse(controller.source));
    addTearDown(reopened.dispose);
    expect(kinds(reopened), kinds(controller));
  });

  testWidgets('double-Enter after a speech asks for the next cue', (tester) async {
    final controller = await open(tester, 'JOHN\nHello.\n');
    final dialogue = controller.blocks[1];
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: dialogue.id, offsetUtf16: dialogue.text.length),
      focus: DocPosition(block: dialogue.id, offsetUtf16: dialogue.text.length),
    ));

    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await press(tester, LogicalKeyboardKey.enter);

    expect(controller.blocks.length, 3, reason: 'no fourth block');
    expect(kinds(controller).last, BlockKind.character);
    await type(tester, controller, 'MARY');
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, controller, 'Hello yourself.');

    expect(controller.source, 'JOHN\nHello.\n\n@MARY\nHello yourself.\n');
  });

  // --- element-type changes are non-destructive ---------------------------

  testWidgets('every element shortcut leaves the text and the caret alone',
      (tester) async {
    const text = 'The café is quiet. 日本 🎬';
    final controller = await open(tester, '!$text\n');
    final id = controller.blocks.single.id;
    // Mid-text, and after the astral-plane character, so that a caret the core
    // moved would be obvious.
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: id, offsetUtf16: 4),
      focus: DocPosition(block: id, offsetUtf16: 4),
    ));

    for (final digit in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit0,
    ]) {
      await press(tester, digit, control: true);
      expect(controller.blocks.single.text, text,
          reason: 'Ctrl+${digit.keyLabel} changed the text');
      expect(controller.blocks.single.forced, isTrue);
      expect(controller.selection.focus.offsetUtf16, 4,
          reason: 'Ctrl+${digit.keyLabel} moved the caret');
      // Whatever the type, the bytes come back: the text survives a round trip
      // through Fountain in every one of these element types.
      final written = controller.source;
      final reopened = EditorController(RustDocumentCore.parse(written));
      addTearDown(reopened.dispose);
      expect(reopened.blocks.single.text, text, reason: 'in $written');
    }
  });

  testWidgets('a shortcut straight after an automatic change overrules it',
      (tester) async {
    final controller = await open(tester);
    await type(tester, controller, 'INT. HOUSE');
    expect(kinds(controller), [BlockKind.sceneHeading]);

    // §Phase 3: "an immediate element-type shortcut after an automatic change
    // reverts and forces the user's choice".
    await press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(kinds(controller), [BlockKind.action]);

    // And it stays action however much more of the slug line is typed.
    await type(tester, controller, ' - DAY');
    expect(kinds(controller), [BlockKind.action]);
    expect(controller.blocks.single.text, 'INT. HOUSE - DAY');
    expect(controller.source, '!INT. HOUSE - DAY\n');
  });

  testWidgets('an automatic promotion is undone with the typing that caused it',
      (tester) async {
    final controller = await open(tester);
    await type(tester, controller, 'INT. HOUSE - DAY');
    expect(kinds(controller), [BlockKind.sceneHeading]);

    controller.undo();
    await tester.pump();

    expect(controller.blocks.single.text, isEmpty);
    expect(kinds(controller), [BlockKind.action]);
  });

  testWidgets('a paragraph that stops being a cue takes its speech with it',
      (tester) async {
    final controller = await open(tester, 'JOHN\nHello.\n');
    expect(kinds(controller), [BlockKind.character, BlockKind.dialogue]);

    // Lower-case letters take the line out of §4.1's cue character set.
    final cue = controller.blocks.first;
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: cue.id, offsetUtf16: cue.text.length),
      focus: DocPosition(block: cue.id, offsetUtf16: cue.text.length),
    ));
    await type(tester, controller, 'ny');

    expect(kinds(controller), [BlockKind.action, BlockKind.action]);
    expect(controller.source, 'JOHNny\n\nHello.\n');
  });

  testWidgets('a plain paste is still inferred from nothing', (tester) async {
    final controller = await open(tester);
    await Clipboard.setData(const ClipboardData(text: 'INT. HOUSE - DAY\nCUT TO:'));
    await controller.paste(plain: true);
    await tester.pump();

    expect(kinds(controller), [BlockKind.action, BlockKind.action]);
    expect(controller.source, '!INT. HOUSE - DAY\n\n!CUT TO:\n');
  });

  // --- find and replace --------------------------------------------------

  testWidgets('find, replace and replace all, through the real core',
      (tester) async {
    const script = 'INT. HOUSE - DAY\n\nJohn leaves the house. The house is quiet.\n';
    final controller = await open(tester, script);
    controller.moveToDocumentEdge(start: true);

    // Case-insensitive by default, so the slug line counts too.
    controller.search(const FindQuery(
      text: 'house',
      caseSensitive: false,
      wholeWord: false,
      kinds: [],
    ));
    await tester.pump();
    expect(controller.matches, hasLength(3));
    expect(controller.matchIndex, 0);
    // The match is the selection, and taking it back out gives the matched text.
    expect(controller.selectedText(), 'HOUSE');

    controller.search(const FindQuery(
      text: 'house',
      caseSensitive: true,
      wholeWord: false,
      kinds: [],
    ));
    await tester.pump();
    expect(controller.matches, hasLength(2), reason: 'HOUSE is not house');

    controller.search(const FindQuery(
      text: 'house',
      caseSensitive: false,
      wholeWord: true,
      kinds: [],
    ));
    await tester.pump();
    expect(controller.matches, hasLength(3),
        reason: 'all three sit against non-word characters');

    controller.search(const FindQuery(
      text: 'hous',
      caseSensitive: false,
      wholeWord: true,
      kinds: [],
    ));
    await tester.pump();
    expect(controller.matches, isEmpty, reason: '"hous" is inside a word');

    // Restricted to one element type.
    controller.search(const FindQuery(
      text: 'house',
      caseSensitive: false,
      wholeWord: false,
      kinds: [BlockKind.action],
    ));
    await tester.pump();
    expect(controller.matches, hasLength(2));

    controller.replaceAll('cabin');
    await tester.pump();
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\nJohn leaves the cabin. The cabin is quiet.\n',
    );

    // One undo takes all of it back, and the untouched slug line comes back from
    // its own bytes.
    controller.undo();
    await tester.pump();
    expect(controller.source, script);
  });

  testWidgets('replacing inside a scene heading keeps it readable', (tester) async {
    final controller = await open(tester, 'INT. HOUSE - DAY\n');
    controller.search(const FindQuery(
      text: 'INT.',
      caseSensitive: true,
      wholeWord: false,
      kinds: [],
    ));
    await tester.pump();
    controller.replaceAll('A ROOM IN');
    await tester.pump();

    // The block is still a scene heading, and the serialiser protects it with the
    // marker §4.1 gives it, so nothing is lost either way.
    expect(controller.blocks.single.kind, BlockKind.sceneHeading);
    expect(controller.blocks.single.text, 'A ROOM IN HOUSE - DAY');
    final reopened = EditorController(RustDocumentCore.parse(controller.source));
    addTearDown(reopened.dispose);
    expect(reopened.blocks.single.text, 'A ROOM IN HOUSE - DAY');
    expect(reopened.blocks.single.kind, BlockKind.sceneHeading);
  });

  // --- suggestions -------------------------------------------------------

  testWidgets('an existing cue is suggested but never applied', (tester) async {
    final controller = await open(tester, 'JOHN\nHello.\n\nAction.\n');
    final last = controller.blocks.last;
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: last.id, offsetUtf16: 0),
      focus: DocPosition(block: last.id, offsetUtf16: last.text.length),
    ));
    await type(tester, controller, 'JOHN');
    await tester.pump();

    expect(controller.characterSuggestion, 'JOHN');
    expect(controller.blocks.last.kind, BlockKind.action,
        reason: 'a suggestion is not a change');
    expect(find.byKey(const Key('tab-hint')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('tab-hint'))).data,
      'Tab: Character — JOHN',
    );

    // Tab is what accepts it.
    await press(tester, LogicalKeyboardKey.tab);
    expect(controller.blocks.last.kind, BlockKind.character);
  });

  // --- Escape ------------------------------------------------------------

  testWidgets('Escape closes each panel and never changes the document',
      (tester) async {
    const script = 'INT. HOUSE - DAY\n\nJohn enters.\n';
    final controller = await open(tester, script);

    await press(tester, LogicalKeyboardKey.keyF, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Find'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Find'), findsNothing);
    expect(controller.source, script);

    await press(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Element or command'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Element or command'), findsNothing);
    expect(controller.source, script);

    // With no panel open it collapses the selection, and that is all.
    controller.selectAll();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.escape);
    expect(controller.hasSelection, isFalse);
    expect(controller.source, script);
  });
}
