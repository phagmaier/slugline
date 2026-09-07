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

/// Opens the find bar with the caret at the top of the script.
///
/// The caret matters: a search starts from where the writer is, so a test that
/// wants "1 of 2" has to say where "1" is counted from.
Future<void> openFind(WidgetTester tester, EditorController controller) async {
  caretAt(controller, 0, 0);
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Finder findField() =>
    find.ancestor(of: find.text('Find'), matching: find.byType(TextField));

Finder replaceField() => find.ancestor(
  of: find.text('Replace with'),
  matching: find.byType(TextField),
);

String? count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('find-match-count'))).data;

void main() {
  testWidgets('reopening Find preserves its element filter', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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

    await tester.enterText(findField(), 'house');
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(2));
    expect(count(tester), '1 of 2');

    await tester.enterText(findField(), 'houses');
    await tester.pumpAndSettle();
    expect(count(tester), 'No matches');
  });

  testWidgets('a match becomes the selection', (tester) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await tester.enterText(findField(), 'house');
    await tester.pumpAndSettle();

    final match = controller.matches.first;
    expect(controller.selection.anchor.block, match.block);
    expect(controller.selection.anchor.offsetUtf16, match.startUtf16);
    expect(controller.selection.focus.offsetUtf16, match.endUtf16);
  });

  testWidgets('next and previous walk the matches and wrap', (tester) async {
    final controller = await pumpEditorPage(tester, script());
    await openFind(tester, controller);
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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

  testWidgets('the element filter reaches the core', (tester) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await tester.enterText(findField(), 'house');
    await tester.pumpAndSettle();
    expect(core.queries.last.kinds, isEmpty);

    await tester.tap(find.text('Every element'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dialogue').last);
    await tester.pumpAndSettle();

    expect(core.queries.last.kinds, [BlockKind.dialogue]);
  });

  testWidgets('Replace changes one match and moves to the next', (
    tester,
  ) async {
    final core = script();
    final controller = await pumpEditorPage(tester, core);
    await openFind(tester, controller);
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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
    await tester.enterText(findField(), 'house');
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
}
