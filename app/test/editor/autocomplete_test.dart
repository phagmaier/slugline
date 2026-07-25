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
