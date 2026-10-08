// §Phase 3's find and replace: a live match count, next and previous, replace
// and replace all, and the toggles.
//
// The *rules* of matching — case folding, word boundaries, the element filter —
// are `crates/document/src/find.rs`'s and are proved there; the double here does
// a plain case-sensitive `indexOf` and nothing more, which is why every fixture
// below spells the word it searches for the same way each time. What is Dart's,
// and what these tests cover, is everything around the match list: that the count
// is live, that next and previous wrap, that a match becomes the selection, that
// Escape closes the bar without touching the document, and that the toggles reach
// the core as part of the query.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/find_bar.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

const _action = 'John leaves the house and the house is quiet.';

FakeCore script() => FakeCore([
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
    kind: BlockKind.action,
    sectionLevel: 0,
    text: _action,
    forced: false,
    dual: false,
    readOnly: false,
  ),
]);

/// A core that finds without regard to case, as the real one does unless told
/// otherwise — for the one test where what was found and what was typed have
/// to be spelled differently.
class _FoldingCore extends FakeCore {
  _FoldingCore(super.blocks);

  @override
  List<FindMatch> find(FindQuery query) {
    queries.add(query);
    final needle = query.text.toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final block in blocks(0, blockCount))
        for (final hit in needle.allMatches(block.text.toLowerCase()))
          FindMatch(block: block.id, startUtf16: hit.start, endUtf16: hit.end),
    ];
  }
}

/// Opens the find bar with the caret at the top of the script.
///
/// The caret matters: a search starts from where the writer is, so a test that
/// wants "1 of 2" has to say where "1" is counted from.
Future<void> openFind(WidgetTester tester, EditorController controller) async {
  caretAt(controller, 0, 0);
  await tester.pump();
  await pressFind(tester);
}

/// `Ctrl+F`, with the selection left as the test made it.
Future<void> pressFind(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Finder findField() =>
    find.ancestor(of: find.text('Find'), matching: find.byType(TextField));

/// What the find field holds.
String findText(WidgetTester tester) =>
    tester.widget<TextField>(findField()).controller!.text;

/// Types into the find field and waits out the keystroke debounce. Searches
/// from typing run 150 ms after the last keystroke — a full-document scan per
/// keystroke janks a feature — so a test that asserts without advancing the
/// clock asserts on the query from before the typing.
Future<void> typeFind(WidgetTester tester, String text) async {
  await tester.enterText(findField(), text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// A platform text insertion respects the field's current selection; enterText
/// replaces the whole value and would hide an opening-query selection bug.
Future<void> insertFind(WidgetTester tester, String text) async {
  final value = tester.widget<TextField>(findField()).controller!.value;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Finder replaceField() => find.ancestor(
  of: find.text('Replace with'),
  matching: find.byType(TextField),
);

String? count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('find-match-count'))).data;

void main() {
  for (final seeded in [true, false]) {
    testWidgets(
      'typing replaces the ${seeded ? 'seeded' : 'resumed'} opening Find query',
      (tester) async {
        final core = script();
        final controller = await pumpEditorPage(tester, core);
        if (seeded) {
          selectFromTo(controller, 0, 13, 0, 16);
          await tester.pump();
          await pressFind(tester);
          expect(findText(tester), 'DAY');
        } else {
          await openFind(tester, controller);
          await typeFind(tester, 'quiet');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await openFind(tester, controller);
          expect(findText(tester), 'quiet');
        }

        await insertFind(tester, 'house');
        expect(findText(tester), 'house');
        expect(count(tester), '1 of 2');
        expect(controller.selectedText(), 'house');

        // The initial selection must not reset after typing or a rebuild.
        await insertFind(tester, 's');
        expect(findText(tester), 'houses');
        expect(count(tester), 'No matches');
        expect(core.commands, isEmpty, reason: 'query input edits no script');
      },
    );
  }

  testWidgets('Right keeps the opening query for deliberate amendment', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    selectFromTo(controller, 1, 16, 1, 21);
    await tester.pump();
    await pressFind(tester);
    expect(findText(tester), 'house');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await insertFind(tester, 's');
    expect(findText(tester), 'houses');
    expect(count(tester), 'No matches');
  });

  testWidgets('typing waits for a pause before scanning the document', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    final scanned = core.queries.length;

    // A full-document scan per keystroke janks a feature, so keystrokes wait
    // 150 ms for the next one. Toggles and match navigation search at once.
    await tester.enterText(findField(), 'house');
    await tester.pump();
    expect(
      core.queries,
      hasLength(scanned),
      reason: 'the scan waits out the keystroke',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(core.queries, hasLength(scanned + 1));
    expect(controller.matches, hasLength(2));
  });

  testWidgets('reopening Find preserves its element filter', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.tap(find.text('Every element'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dialogue').last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await openFind(tester, controller);
    expect(core.queries.last.kinds, [BlockKind.dialogue]);
    expect(find.text('Dialogue'), findsWidgets);
  });

  testWidgets('reload refreshes match ranges before Replace can use them', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(2));

    // A disk reload replaces core state without an editor patch.
    core.apply(
      EditCommand.replaceText(
        block: 2,
        startUtf16: 0,
        endUtf16: _action.length,
        with_: 'A completely different action paragraph.',
      ),
    );
    controller.reloadFromCore();
    await tester.pump();

    expect(controller.matches, isEmpty);
    expect(count(tester), 'No matches');
    controller.replaceCurrent('cabin');
    expect(
      controller.blocks[1].text,
      'A completely different action paragraph.',
    );
  });

  testWidgets('Ctrl+F opens the bar; Escape closes it and changes no text', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);

    await openFind(tester, controller);
    expect(findField(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(findField(), findsNothing);
    expect(core.commands, isEmpty);
    expect(controller.blocks[1].text, _action);
  });

  testWidgets('closing the bar gives the keyboard back to the editor', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // The selection is the match the bar left behind; Left collapses it, which
    // only the surface's own key handling does.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(
      controller.hasSelection,
      isFalse,
      reason: 'the surface never got the focus back',
    );
  });

  testWidgets('the match count is live', (tester) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    expect(count(tester), isEmpty);

    await typeFind(tester, 'house');
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(2));
    expect(count(tester), '1 of 2');

    await typeFind(tester, 'houses');
    await tester.pumpAndSettle();
    expect(count(tester), 'No matches');
  });

  testWidgets('a match becomes the selection', (tester) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();

    final match = controller.matches.first;
    expect(controller.selection.anchor.block, match.block);
    expect(controller.selection.anchor.offsetUtf16, match.startUtf16);
    expect(controller.selection.focus.offsetUtf16, match.endUtf16);
  });

  testWidgets('next and previous walk the matches and wrap', (tester) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();
    expect(controller.matchIndex, 0);

    controller.nextMatch();
    await tester.pump();
    expect(controller.matchIndex, 1);
    expect(count(tester), '2 of 2');

    controller.nextMatch();
    await tester.pump();
    expect(controller.matchIndex, 0, reason: 'it wraps');

    controller.previousMatch();
    await tester.pump();
    expect(controller.matchIndex, 1, reason: 'and wraps backwards');
  });

  testWidgets('Enter and Shift+Enter in the bar step through the matches', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.matchIndex, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.matchIndex, 0);
  });

  testWidgets('the toggles reach the core as part of the query', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();
    expect(core.queries.last.caseSensitive, isFalse);
    expect(core.queries.last.wholeWord, isFalse);

    await tester.tap(find.text('Match case'));
    await tester.pumpAndSettle();
    expect(core.queries.last.caseSensitive, isTrue);

    await tester.tap(find.text('Whole word'));
    await tester.pumpAndSettle();
    expect(core.queries.last.wholeWord, isTrue);
    expect(core.queries.last.caseSensitive, isTrue, reason: 'both stay set');
  });

  testWidgets('the element filter resets and menu cancellation preserves it', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    final everyLabel = find.descendant(
      of: find.byType(FindBar),
      matching: find.text('Every element'),
    );
    final dialogueLabel = find.descendant(
      of: find.byType(FindBar),
      matching: find.text('Dialogue'),
    );
    expect(controller.query.kinds, isEmpty);
    expect(core.queries.last.kinds, isEmpty);
    expect(everyLabel, findsOneWidget);

    await tester.tap(everyLabel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dialogue').last);
    await tester.pumpAndSettle();
    expect(controller.query.kinds, [BlockKind.dialogue]);
    expect(core.queries.last.kinds, [BlockKind.dialogue]);
    expect(dialogueLabel, findsOneWidget);
    expect(everyLabel, findsNothing);

    // Dismissing the menu is not a request to search every element.
    final scansBeforeCancel = core.queries.length;
    await tester.tap(dialogueLabel);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(core.queries, hasLength(scansBeforeCancel));
    expect(controller.query.kinds, [BlockKind.dialogue]);
    expect(core.queries.last.kinds, [BlockKind.dialogue]);
    expect(dialogueLabel, findsOneWidget);
    expect(everyLabel, findsNothing);

    await tester.tap(dialogueLabel);
    await tester.pumpAndSettle();
    final everyItem = find.ancestor(
      of: find.text('Every element'),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    // The active Dialogue entry positions Every element offscreen at 800x600.
    await tester.ensureVisible(everyItem);
    await tester.pumpAndSettle();
    await tester.tap(everyItem);
    await tester.pumpAndSettle();
    expect(core.queries, hasLength(scansBeforeCancel + 1));
    expect(controller.query.kinds, isEmpty);
    expect(core.queries.last.kinds, isEmpty);
    expect(everyLabel, findsOneWidget);
    expect(dialogueLabel, findsNothing);

    await tester.tap(find.byTooltip('Close (Escape)'));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsNothing);
    await openFind(tester, controller);
    expect(controller.query.kinds, isEmpty);
    expect(core.queries.last.kinds, isEmpty);
    expect(everyLabel, findsOneWidget);
    expect(dialogueLabel, findsNothing);
  });

  testWidgets('Replace changes one match and moves to the next', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.enterText(replaceField(), 'cabin');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(
      controller.blocks[1].text,
      'John leaves the cabin and the house is quiet.',
      reason: 'only the match the caret was on',
    );
    expect(core.commands.last, isA<EditCommand_ReplaceText>());
    expect(controller.matches, hasLength(1));
    expect(count(tester), '1 of 1');
  });

  testWidgets('Replace All is one command and one undo step', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.enterText(replaceField(), 'cabin');
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(core.replacements, hasLength(1));
    expect(core.replacements.single.$1.text, 'house');
    expect(core.replacements.single.$2, 'cabin');
    expect(
      controller.blocks[1].text,
      'John leaves the cabin and the cabin is quiet.',
    );
    expect(count(tester), 'No matches');

    controller.undo();
    await tester.pump();
    expect(controller.blocks[1].text, _action);
  });

  testWidgets('Replace All leaves the caret where the writer left it', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.enterText(replaceField(), 'cabin');
    await tester.pumpAndSettle();
    // Finding a match moved the caret; put it back where a writer would have it.
    caretAt(controller, 1, 4);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(controller.selection.focus.block, 2);
    expect(controller.selection.focus.offsetUtf16, 4);
  });

  testWidgets('an edit outside the bar keeps the match list honest', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(2));

    // Delete one of them from the document itself.
    selectFromTo(controller, 1, 16, 1, 21);
    controller.deleteSelection();
    await tester.pump();

    expect(
      controller.blocks[1].text,
      'John leaves the  and the house is quiet.',
    );
    expect(
      controller.matches,
      hasLength(1),
      reason: 'the count is stale the moment the text under it changes',
    );
    expect(count(tester), '1 of 1');
  });

  testWidgets('replacing with nothing to replace does nothing', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await tester.enterText(replaceField(), 'cabin');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(core.commands, isEmpty);
    expect(core.replacements, isEmpty);
    expect(controller.blocks[1].text, _action);
  });

  // W8: Find opened over a selection inside one block starts with that text.

  testWidgets('Find opened over a selection starts with the selected text', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    // The second "house" of the two.
    selectFromTo(controller, 1, 30, 1, 35);
    await tester.pump();

    await pressFind(tester);

    expect(findText(tester), 'house');
    expect(core.queries.last.text, 'house');
    expect(controller.matches, hasLength(2));
    expect(count(tester), '2 of 2', reason: 'it is on the one that was chosen');
    expect(controller.selection.anchor.block, 2);
    expect(controller.selection.anchor.offsetUtf16, 30);
    expect(controller.selection.focus.offsetUtf16, 35);
    expect(core.commands, isEmpty, reason: 'opening Find edits nothing');
  });

  testWidgets('a selection made backwards starts Find with the same text', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    selectFromTo(controller, 1, 35, 1, 30);
    await tester.pump();

    await pressFind(tester);

    expect(findText(tester), 'house');
    expect(count(tester), '2 of 2');
  });

  testWidgets('the seeded search has run before the bar is first drawn', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(2));

    selectFromTo(controller, 1, 39, 1, 44);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // No frame has been drawn since the key. A bar that searched after its
    // first one would draw it over the last search's matches.
    expect(controller.query.text, 'quiet');
    expect(controller.matches.single.startUtf16, 39);

    await tester.pumpAndSettle();
    expect(findText(tester), 'quiet');
    expect(count(tester), '1 of 1');
  });

  testWidgets('the seed is the text of the script, not its display capitals', (
    tester,
  ) async {
    final core = FakeCore([
      const BlockView(
        id: 1,
        kind: BlockKind.sceneHeading,
        sectionLevel: 0,
        text: 'int. house - day',
        forced: false,
        dual: false,
        readOnly: false,
      ),
    ]);
    final controller = await pumpEditorPage(tester, core);
    selectFromTo(controller, 0, 5, 0, 10);
    await tester.pump();

    await pressFind(tester);

    // The heading is drawn as INT. HOUSE - DAY and stored as it was typed; a
    // match-case search has to be for what is stored.
    expect(findText(tester), 'house');
  });

  testWidgets('with no selection, or one across blocks, Find resumes the '
      'last search', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'quiet');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openFind(tester, controller);
    expect(findText(tester), 'quiet', reason: 'a bare caret');
    expect(count(tester), '1 of 1');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // From inside the heading to inside the action: no query matches across
    // a block boundary, so there is nothing here to search for.
    selectFromTo(controller, 0, 5, 1, 4);
    await tester.pump();
    await pressFind(tester);
    expect(findText(tester), 'quiet', reason: 'a selection across two blocks');
    expect(core.queries.last.text, 'quiet');
  });

  testWidgets('reopening over the match a search stopped on keeps the query '
      'as it was typed', (tester) async {
    final core = _FoldingCore([
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
        kind: BlockKind.action,
        sectionLevel: 0,
        text: _action,
        forced: false,
        dual: false,
        readOnly: false,
      ),
    ]);
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    expect(count(tester), '1 of 3');
    expect(controller.selectedText(), 'HOUSE');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The selection is the match in the heading. That is the last search, not
    // a new one, and it is still for what the writer typed.
    await pressFind(tester);
    expect(findText(tester), 'house');
    expect(count(tester), '1 of 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Selected by hand, a different match than the one the search stopped on
    // is still that search — and the count says which of them it is, where it
    // used to go on showing the place the search had stopped.
    await openFind(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count(tester), '2 of 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    selectFromTo(controller, 0, 5, 0, 10);
    await tester.pump();
    await pressFind(tester);
    expect(findText(tester), 'house');
    expect(count(tester), '1 of 3');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Any other selection in the heading is a new search.
    selectFromTo(controller, 0, 13, 0, 16);
    await tester.pump();
    await pressFind(tester);
    expect(findText(tester), 'DAY');
  });

  testWidgets('a selection across a line break inside a block does not seed', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'first line\nsecond line');
    final controller = await pumpEditorPage(tester, core);
    selectFromTo(controller, 0, 6, 0, 17);
    await tester.pump();

    await pressFind(tester);
    // The find field is one line, and "line⏎second" is not something it can
    // show or a writer can retype in it.
    expect(findText(tester), isEmpty);
    expect(core.queries, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Either side of the break is an ordinary selection.
    selectFromTo(controller, 0, 11, 0, 17);
    await tester.pump();
    await pressFind(tester);
    expect(findText(tester), 'second');
    expect(count(tester), '1 of 1');
  });

  testWidgets('a seeded search keeps the toggles and the element filter', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await typeFind(tester, 'house');
    await tester.tap(find.text('Match case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every element'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action').last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    selectFromTo(controller, 1, 39, 1, 44);
    await tester.pump();
    await pressFind(tester);

    expect(findText(tester), 'quiet');
    expect(core.queries.last.text, 'quiet');
    expect(core.queries.last.caseSensitive, isTrue);
    expect(core.queries.last.wholeWord, isFalse);
    expect(core.queries.last.kinds, [BlockKind.action]);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Match case'))
          .selected,
      isTrue,
    );
  });

  testWidgets('Find reached through the command palette is seeded too', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, script());
    selectFromTo(controller, 1, 39, 1, 44);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Element or command'),
      'Find and replace',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(findText(tester), 'quiet');
    expect(count(tester), '1 of 1');
  });
}
