import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/commands.dart';
import 'package:slugline/editor/elements.dart';

import '../support/fake_core.dart';

BlockView block(int id, BlockKind kind, String text) => BlockView(
  id: id,
  kind: kind,
  sectionLevel: 0,
  text: text,
  forced: false,
  dual: false,
  readOnly: kind == BlockKind.opaque,
  inlineRuns: const [],
);

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> palette(WidgetTester tester, String label) async {
  await key(tester, LogicalKeyboardKey.keyK, control: true);
  await tester.enterText(
    find.widgetWithText(TextField, 'Element or command'),
    label,
  );
  await tester.pumpAndSettle();
  await key(tester, LogicalKeyboardKey.enter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'palette omission and restoration apply structural patches and exact undo selections',
    (tester) async {
      final core = FakeCore([
        block(1, BlockKind.character, 'BOB'),
        block(2, BlockKind.dialogue, 'Before 😀 café after.'),
        block(3, BlockKind.action, 'Untouched.'),
      ]);
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      const selection = DocSelection(
        anchor: DocPosition(block: 2, offsetUtf16: 14),
        focus: DocPosition(block: 2, offsetUtf16: 7),
      );
      controller.setSelection(selection);
      const commentSelection = DocSelection(
        anchor: DocPosition(block: 4, offsetUtf16: 0),
        focus: DocPosition(block: 4, offsetUtf16: 0),
      );
      core.omitSelectionPatch = EditResult(
        changed: [block(2, BlockKind.dialogue, 'Before ')],
        removed: [],
        inserted: [
          InsertedBlock(
            index: 2,
            block: block(
              4,
              BlockKind.opaque,
              'A core-supplied read-only record',
            ),
          ),
          InsertedBlock(
            index: 3,
            block: block(5, BlockKind.dialogue, ' after.'),
          ),
        ],
        selection: commentSelection,
        blockCount: 5,
      );
      core.restoreOmittedPatch = EditResult(
        changed: [block(2, BlockKind.dialogue, 'Before 😀 café after.')],
        removed: [4, 5],
        inserted: [],
        selection: const DocSelection(
          anchor: DocPosition(block: 2, offsetUtf16: 0),
          focus: DocPosition(block: 2, offsetUtf16: 0),
        ),
        blockCount: 3,
      );
      await tester.pumpWidget(
        MaterialApp(home: EditorPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      final untouched = controller.blocks.last;
      await palette(tester, omitSelectionLabel);
      expect(controller.blocks[1].text, 'Before ');
      expect(controller.blocks[2].readOnly, isTrue);
      expect(core.omissionCalls.single, ('selection', selection));
      expect(controller.blocks[3].text, ' after.');
      expect(controller.blocks.last, untouched);
      final comment = controller.selection;
      expect(comment.focus.block, controller.blocks[2].id);
      expect(core.journalState.$1, 1);
      await key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.blocks.map((b) => b.text), [
        'BOB',
        'Before 😀 café after.',
        'Untouched.',
      ]);
      expect(controller.selection, selection);
      controller.redo();
      await tester.pumpAndSettle();
      expect(controller.selection, comment);
      await palette(tester, restoreOmittedLabel);
      expect(controller.blocks.map((b) => b.text), [
        'BOB',
        'Before 😀 café after.',
        'Untouched.',
      ]);
      expect(core.omissionCalls.last, ('restore', commentSelection));
      expect(controller.blocks[1].kind, BlockKind.dialogue);
      expect(controller.blocks[1].readOnly, isFalse);
      expect(controller.blocks.last, untouched);
      controller.undo();
      expect(controller.blocks[2].readOnly, isTrue);
      expect(controller.selection, comment);
      controller.redo();
      expect(controller.blocks[1].text, 'Before 😀 café after.');
      controller.insertText('Editable ');
      expect(controller.blocks[1].text, 'Editable Before 😀 café after.');
    },
  );

  testWidgets(
    'restore refusal leaves the omission intact and explains the safe refusal',
    (tester) async {
      final core = FakeCore([
        block(1, BlockKind.opaque, 'Supplied read-only record'),
      ]);
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      const at = DocSelection(
        anchor: DocPosition(block: 1, offsetUtf16: 0),
        focus: DocPosition(block: 1, offsetUtf16: 0),
      );
      controller.setSelection(at);
      final before = controller.blocks.toList();
      core.refuseWith = EditRejection.cannotRestoreOmission;
      await tester.pumpWidget(
        MaterialApp(home: EditorPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await palette(tester, restoreOmittedLabel);
      expect(controller.blocks, before);
      expect(controller.selection, at);
      expect(controller.lastRejection, EditRejection.cannotRestoreOmission);
      expect(
        find.text(
          'Omitted text cannot be restored safely: its record or neighboring context changed.',
        ),
        findsOneWidget,
      );
    },
  );

  test('a refusal leaves blocks, caret, layout and undo untouched', () {
    final core = FakeCore.single(BlockKind.action, 'Before SELECT after.')
      ..refuseWith = EditRejection.notEditable;
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    const selection = DocSelection(
      anchor: DocPosition(block: 1, offsetUtf16: 7),
      focus: DocPosition(block: 1, offsetUtf16: 13),
    );
    controller.setSelection(selection);
    final before = controller.blocks.toList();
    final rows = controller.layout.totalRows;
    controller.omitSelection();
    expect(controller.lastRejection, EditRejection.notEditable);
    expect(controller.blocks, before);
    expect(controller.selection, selection);
    expect(controller.layout.totalRows, rows);
    expect(core.dirty, isFalse);
    expect(core.undo(), isNull);
  });

  test(
    'scene palette command uses supplied core scene bounds and one undo step',
    () {
      final core = FakeCore([
        block(1, BlockKind.sceneHeading, 'INT. ONE - DAY'),
        block(2, BlockKind.action, 'First scene.'),
        block(3, BlockKind.sceneHeading, 'EXT. TWO - NIGHT'),
        block(4, BlockKind.action, 'Second scene.'),
      ]);
      core.omitScenePatch = EditResult(
        changed: [],
        removed: [1, 2],
        inserted: [
          InsertedBlock(
            index: 0,
            block: block(5, BlockKind.opaque, 'Supplied scene record'),
          ),
        ],
        selection: const DocSelection(
          anchor: DocPosition(block: 5, offsetUtf16: 0),
          focus: DocPosition(block: 5, offsetUtf16: 0),
        ),
        blockCount: 3,
      );
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      const selection = DocSelection(
        anchor: DocPosition(block: 2, offsetUtf16: 4),
        focus: DocPosition(block: 2, offsetUtf16: 4),
      );
      controller.setSelection(selection);
      final commands = editorCommands(controller: controller, openFind: () {});
      expect(
        commands.any((command) => command.label == omitSelectionLabel),
        isFalse,
      );
      commands.firstWhere((command) => command.label == omitSceneLabel).run();
      expect(controller.blocks.first.readOnly, isTrue);
      expect(core.omissionCalls.single, ('scene', selection));
      expect(controller.blocks.skip(1).map((b) => b.id), [3, 4]);
      controller.undo();
      expect(controller.blocks.map((b) => b.id), [1, 2, 3, 4]);
      expect(controller.selection, selection);
      expect(core.undo(), isNull);
    },
  );
}
