import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

Completion alice() => const Completion(
  kind: CompletionKind.character,
  value: 'ALICE',
  startUtf16: 0,
  endUtf16: 2,
  frequency: 3,
  pinned: false,
);

void main() {
  testWidgets('a completion never inserts without an explicit acceptance key', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.character, 'AL')
      ..completions = [alice()];
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 2);
    await tester.pump();

    expect(find.byKey(const ValueKey('completion-popup')), findsOneWidget);
    expect(controller.blocks.single.text, 'AL');
    expect(
      core.commands,
      isEmpty,
      reason: 'showing and highlighting a candidate are read-only',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.blocks.single.text, 'ALICE');
    expect(core.commands, hasLength(1));
    expect(core.commands.single, isA<EditCommand_ReplaceText>());
  });

  testWidgets('Enter splits while the default completion is showing', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.character, 'AL')
      ..completions = [alice()];
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(core.enters, hasLength(1));
    expect(controller.blocks, hasLength(2));
    expect(controller.blocks.first.text, 'AL');
    expect(
      core.commands.whereType<EditCommand_ReplaceText>(),
      isEmpty,
      reason: 'an automatically highlighted completion was not chosen',
    );
  });

  testWidgets('Enter accepts after the writer navigates the completion popup', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.character, 'AL')
      ..completions = [alice()];
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 0, 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.blocks.single.text, 'ALICE');
    expect(core.enters, isEmpty);
    expect(core.commands.single, isA<EditCommand_ReplaceText>());
  });

  testWidgets(
    'Escape dismisses and suppresses that candidate for the session',
    (tester) async {
      final core = FakeCore.single(BlockKind.character, 'AL')
        ..completions = [alice()];
      final controller = await pumpEditor(tester, core);
      caretAt(controller, 0, 2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byKey(const ValueKey('completion-popup')), findsNothing);
      expect(core.commands, isEmpty);
      controller.setSelection(controller.selection);
      await tester.pump();
      expect(find.byKey(const ValueKey('completion-popup')), findsNothing);
    },
  );
}
