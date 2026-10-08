import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/line_layout.dart';
import 'package:slugline/editor/metrics.dart';

import '../support/fake_core.dart';

BlockView _block(int id, BlockKind kind, String text, {bool dual = false}) =>
    BlockView(
      id: id,
      kind: kind,
      sectionLevel: 0,
      text: text,
      forced: false,
      dual: dual,
      readOnly: false,
    );

List<BlockView> _pair({bool dual = true}) => [
  _block(1, BlockKind.character, 'A' * 25),
  _block(2, BlockKind.parenthetical, '(${'p' * 23})'),
  _block(3, BlockKind.dialogue, 'a' * 31),
  _block(4, BlockKind.character, 'B' * 25, dual: dual),
  _block(5, BlockKind.parenthetical, '(${'q' * 23})'),
  _block(6, BlockKind.dialogue, 'b' * 31),
];

List<String> _rows(DocumentLayout layout, List<BlockView> blocks, int index) =>
    [for (final line in layout.linesOf(index)) line.textIn(blocks[index].text)];

DocSelection _caret(int block, int offset) {
  final position = DocPosition(block: block, offsetUtf16: offset);
  return DocSelection(anchor: position, focus: position);
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _dualPalette(WidgetTester tester) async {
  await _key(tester, LogicalKeyboardKey.keyK, control: true);
  await tester.enterText(
    find.widgetWithText(TextField, 'Element or command'),
    'Toggle dual dialogue',
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dual cue command', () {
    testWidgets(
      'palette toggles the cue flag and undo/redo preserves the caret',
      (tester) async {
        final core = FakeCore(_pair(dual: false));
        final controller = EditorController(core);
        addTearDown(controller.dispose);
        controller.setSelection(_caret(4, 7));
        final selection = controller.selection;
        final texts = controller.blocks.map((block) => block.text).toList();
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.pumpAndSettle();

        await _dualPalette(tester);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(find.byType(CommandPalette), findsNothing);
        expect(controller.blocks[3].dual, isTrue);
        expect(controller.blocks.map((block) => block.text), texts);
        expect(controller.selection, selection);
        expect(find.text('Character · Dual dialogue'), findsOneWidget);
        expect(_rows(controller.layout, controller.blocks, 0), [
          'A' * 20,
          'A' * 5,
        ]);
        expect(_rows(controller.layout, controller.blocks, 2), [
          'a' * 28,
          'a' * 3,
        ]);

        await _key(tester, LogicalKeyboardKey.keyZ, control: true);
        expect(controller.blocks[3].dual, isFalse);
        expect(controller.selection, selection);
        expect(controller.blocks.map((block) => block.text), texts);
        expect(controller.layout.linesOf(0).length, 1);
        expect(controller.layout.linesOf(2).length, 1);
        expect(find.text('Character · Dual dialogue'), findsNothing);

        controller.redo();
        await tester.pumpAndSettle();
        expect(controller.blocks[3].dual, isTrue);
        expect(controller.selection, selection);
        expect(controller.blocks.map((block) => block.text), texts);
        expect(controller.layout.linesOf(0).length, 2);
        expect(controller.layout.linesOf(2).length, 2);

        await _dualPalette(tester);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(controller.blocks[3].dual, isFalse);
        expect(controller.selection, selection);
        expect(controller.blocks.map((block) => block.text), texts);
      },
    );

    testWidgets(
      'non-cue palette omits the command and direct invocation is inert',
      (tester) async {
        final core = FakeCore.single(BlockKind.action, 'Unchanged text.');
        final controller = EditorController(core);
        addTearDown(controller.dispose);
        controller.setSelection(_caret(1, 4));
        final selection = controller.selection;
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        await _dualPalette(tester);
        expect(find.text('No matching command'), findsOneWidget);
        await _key(tester, LogicalKeyboardKey.escape);
        controller.toggleDual();
        expect(core.dirty, isFalse);
        expect(controller.selection, selection);
        expect(controller.blocks.single.text, 'Unchanged text.');
        expect(controller.blocks.single.dual, isFalse);
        expect(core.undo(), isNull);
      },
    );

    testWidgets(
      'a refused cue command preserves text, caret and partner wraps',
      (tester) async {
        final core = FakeCore(_pair(dual: false))
          ..refuseWith = EditRejection.notEditable;
        final controller = EditorController(core);
        addTearDown(controller.dispose);
        controller.setSelection(_caret(4, 9));
        final selection = controller.selection;
        final before = controller.blocks.toList();
        final partnerRows = _rows(controller.layout, controller.blocks, 2);
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.pumpAndSettle();
        await _dualPalette(tester);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(controller.lastRejection, EditRejection.notEditable);
        expect(controller.blocks, before);
        expect(controller.selection, selection);
        expect(_rows(controller.layout, controller.blocks, 2), partnerRows);
        expect(core.dirty, isFalse);
        expect(core.undo(), isNull);
      },
    );

    test(
      'toggle preserves a cue text selection as well as a collapsed caret',
      () {
        final controller = EditorController(
          FakeCore.single(BlockKind.character, 'MARTHA'),
        );
        addTearDown(controller.dispose);
        const selection = DocSelection(
          anchor: DocPosition(block: 1, offsetUtf16: 1),
          focus: DocPosition(block: 1, offsetUtf16: 5),
        );
        controller.setSelection(selection);
        controller.toggleDual();
        expect(controller.selection, selection);
        expect(controller.blocks.single.text, 'MARTHA');
        expect(controller.blocks.single.dual, isTrue);
        controller.undo();
        expect(controller.selection, selection);
        expect(controller.blocks.single.dual, isFalse);
        controller.redo();
        expect(controller.selection, selection);
        expect(controller.blocks.single.dual, isTrue);
      },
    );
  });

  group('paired-width linear layout', () {
    test('both lanes wrap exactly by kind while keeping ordinary indents', () {
      final blocks = _pair();
      final layout = DocumentLayout(blocks);
      expect(_rows(layout, blocks, 0), ['A' * 20, 'A' * 5]);
      expect(_rows(layout, blocks, 1), ['(${'p' * 19}', '${'p' * 4})']);
      expect(_rows(layout, blocks, 2), ['a' * 28, 'a' * 3]);
      expect(_rows(layout, blocks, 3), ['B' * 20, 'B' * 5]);
      expect(_rows(layout, blocks, 4), ['(${'q' * 19}', '${'q' * 4})']);
      expect(_rows(layout, blocks, 5), ['b' * 28, 'b' * 3]);
      for (var i = 0; i < blocks.length; i++) {
        expect(layout.columnOf(i, 0), metricsFor(blocks[i].kind).indent);
        if (i > 0) {
          expect(layout.firstRowOf(i), greaterThan(layout.endRowOf(i - 1) - 1));
        }
      }
      expect(blocks[3].text, 'B' * 25);
      expect(blocks[3].dual, isTrue);
    });

    test('orphan markers and cues with no body retain ordinary widths', () {
      final blocks = [
        _block(1, BlockKind.character, 'A' * 25, dual: true),
        _block(2, BlockKind.dialogue, 'a' * 31),
        _block(3, BlockKind.character, 'B' * 25),
        _block(4, BlockKind.dialogue, 'b' * 31),
        _block(5, BlockKind.character, 'C' * 25, dual: true),
      ];
      final layout = DocumentLayout(blocks);
      for (var i = 0; i < blocks.length; i++) {
        expect(layout.linesOf(i).length, 1);
      }
      expect(blocks.first.dual, isTrue);
      expect(blocks.last.dual, isTrue);
    });

    test('a bodyless first cue does not steal a later eligible pair', () {
      final blocks = [
        _block(1, BlockKind.character, 'A' * 25),
        _block(2, BlockKind.character, 'B' * 25, dual: true),
        _block(3, BlockKind.dialogue, ''),
        _block(4, BlockKind.character, 'C' * 25, dual: true),
        _block(5, BlockKind.parenthetical, '(together)'),
      ];
      final layout = DocumentLayout(blocks);
      expect(layout.linesOf(0).length, 1);
      expect(layout.linesOf(1).length, 2);
      expect(layout.linesOf(3).length, 2);
    });

    for (final firstMarked in [false, true]) {
      test('greedy A${firstMarked ? '^' : ''} B^ C^ pairs only A and B', () {
        final blocks = [
          _block(1, BlockKind.character, 'A' * 25, dual: firstMarked),
          _block(2, BlockKind.dialogue, 'a' * 31),
          _block(3, BlockKind.character, 'B' * 25, dual: true),
          _block(4, BlockKind.dialogue, 'b' * 31),
          _block(5, BlockKind.character, 'C' * 25, dual: true),
          _block(6, BlockKind.dialogue, 'c' * 31),
        ];
        final layout = DocumentLayout(blocks);
        expect(
          [for (var i = 0; i < 6; i++) layout.linesOf(i).length],
          [2, 2, 2, 2, 1, 1],
        );
        expect(blocks.last.text, 'c' * 31);
        expect(blocks[4].dual, isTrue);
      });
    }

    for (final kind in BlockKind.values.where(
      (kind) =>
          kind != BlockKind.character &&
          kind != BlockKind.dialogue &&
          kind != BlockKind.parenthetical,
    )) {
      test('$kind interrupts even when it does not print', () {
        final blocks = _pair()..insert(3, _block(7, kind, ''));
        final layout = DocumentLayout(blocks);
        expect(layout.linesOf(0).length, 1);
        expect(layout.linesOf(2).length, 1);
        expect(layout.linesOf(4).length, 1);
        expect(layout.linesOf(6).length, 1);
      });
    }

    test(
      'flag changes reflow unchanged partners and shifted chain memberships',
      () {
        final blocks = [
          _block(1, BlockKind.character, 'A' * 25),
          _block(2, BlockKind.dialogue, 'a' * 31),
          _block(3, BlockKind.character, 'B' * 25, dual: true),
          _block(4, BlockKind.dialogue, 'b' * 31),
          _block(5, BlockKind.character, 'C' * 25, dual: true),
          _block(6, BlockKind.dialogue, 'c' * 31),
          _block(7, BlockKind.character, 'D' * 25, dual: true),
          _block(8, BlockKind.dialogue, 'd' * 31),
        ];
        final layout = DocumentLayout(blocks);
        expect([
          for (var i = 0; i < 8; i++) layout.linesOf(i).length,
        ], List.filled(8, 2));
        blocks[2] = _block(3, BlockKind.character, 'B' * 25);
        layout.rewrap(2);
        layout.reindex();
        expect(
          [for (var i = 0; i < 8; i++) layout.linesOf(i).length],
          [1, 1, 2, 2, 2, 2, 1, 1],
        );
        blocks[2] = _block(3, BlockKind.character, 'B' * 25, dual: true);
        layout.rewrap(2);
        layout.reindex();
        expect([
          for (var i = 0; i < 8; i++) layout.linesOf(i).length,
        ], List.filled(8, 2));
      },
    );

    test(
      'inserting and removing partners and interruptions reconciles cached wraps',
      () {
        final blocks = _pair().sublist(0, 3);
        final layout = DocumentLayout(blocks);
        expect(layout.linesOf(0).length, 1);
        for (final partner in _pair().sublist(3)) {
          blocks.add(partner);
          layout.insertAt(blocks.length - 1);
        }
        layout.reindex();
        expect(layout.linesOf(0).length, 2);
        expect(layout.linesOf(2).length, 2);

        blocks.insert(3, _block(7, BlockKind.note, 'Hidden interruption.'));
        layout.insertAt(3);
        layout.reindex();
        expect(layout.linesOf(0).length, 1);
        expect(layout.linesOf(2).length, 1);
        expect(layout.linesOf(4).length, 1);
        expect(layout.linesOf(6).length, 1);
        blocks.removeAt(3);
        layout.removeAt(3);
        layout.reindex();
        expect(layout.linesOf(0).length, 2);
        expect(layout.linesOf(2).length, 2);
        for (var i = blocks.length - 1; i >= 3; i--) {
          blocks.removeAt(i);
          layout.removeAt(i);
        }
        layout.reindex();
        expect(layout.linesOf(0).length, 1);
        expect(layout.linesOf(2).length, 1);
      },
    );

    test('kind patches and their undo/redo update untouched speech widths', () {
      final controller = EditorController(FakeCore(_pair()));
      addTearDown(controller.dispose);
      controller.setSelection(_caret(4, 4));
      controller.setKind(BlockKind.action);
      expect(controller.layout.linesOf(0).length, 1);
      expect(controller.layout.linesOf(2).length, 1);
      controller.undo();
      expect(controller.layout.linesOf(0).length, 2);
      expect(controller.layout.linesOf(2).length, 2);
      controller.redo();
      expect(controller.layout.linesOf(0).length, 1);
      expect(controller.layout.linesOf(2).length, 1);
    });

    test(
      'deleting a partner and undoing its insertion reflows retained blocks',
      () {
        final controller = EditorController(FakeCore(_pair()));
        addTearDown(controller.dispose);
        controller.setSelection(
          const DocSelection(
            anchor: DocPosition(block: 3, offsetUtf16: 31),
            focus: DocPosition(block: 6, offsetUtf16: 31),
          ),
        );
        controller.deleteBackward();
        expect(controller.blocks.map((block) => block.id), [1, 2, 3]);
        expect(controller.layout.linesOf(0).length, 1);
        expect(controller.layout.linesOf(2).length, 1);
        controller.undo();
        expect(controller.blocks.map((block) => block.id), [1, 2, 3, 4, 5, 6]);
        expect(controller.layout.linesOf(0).length, 2);
        expect(controller.layout.linesOf(2).length, 2);
        expect(controller.layout.linesOf(3).length, 2);
        expect(controller.layout.linesOf(5).length, 2);
        controller.redo();
        expect(controller.blocks.map((block) => block.id), [1, 2, 3]);
        expect(controller.layout.linesOf(0).length, 1);
        expect(controller.layout.linesOf(2).length, 1);
      },
    );

    test(
      'paired source lines map reversibly to linear editor page anchors',
      () {
        final controller = EditorController(FakeCore(_pair()));
        addTearDown(controller.dispose);
        for (var block = 0; block < 6; block++) {
          for (var sourceLine = 0; sourceLine < 2; sourceLine++) {
            final row = controller.rowOfLine(block, sourceLine);
            expect(controller.pageAnchorAtRow(row), (
              block: controller.blocks[block].id,
              sourceLine: sourceLine,
            ));
            final offset = controller.layout.linesOf(block)[sourceLine].start;
            expect(controller.layout.rowAt(block, offset), row);
          }
        }
      },
    );
  });
}
