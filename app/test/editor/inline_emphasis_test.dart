import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/line_layout.dart';

import '../support/fake_core.dart';

InlineRunView run(
  int start,
  int end, {
  bool hidden = false,
  bool bold = false,
  bool italic = false,
  bool underline = false,
}) => InlineRunView(
  startUtf16: start,
  endUtf16: end,
  hidden: hidden,
  bold: bold,
  italic: italic,
  underline: underline,
);

BlockView block(String text, List<InlineRunView> runs) => BlockView(
  id: 1,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: text,
  forced: true,
  dual: false,
  readOnly: false,
  inlineRuns: runs,
);

const mixedSource = 'A **🎬** _B_ *C*';
List<InlineRunView> mixedRuns() => [
  run(2, 4, hidden: true),
  run(4, 6, bold: true),
  run(6, 8, hidden: true),
  run(9, 10, hidden: true),
  run(10, 11, underline: true),
  run(11, 12, hidden: true),
  run(13, 14, hidden: true),
  run(14, 15, italic: true),
  run(15, 16, hidden: true),
];

void main() {
  test('printed wraps retain dim markers at consumed-space boundaries', () {
    final lines = wrapText(mixedSource, 4, inlineRuns: mixedRuns());
    expect(
      [
        for (final line in lines) [line.start, line.end, line.columns],
      ],
      [
        [0, 8, 3],
        [9, 16, 3],
      ],
    );
    expect(
      [for (final line in lines) line.textIn(mixedSource)],
      ['A 🎬', 'B C'],
    );
    expect(lines.first.displayColumnAtOffset(8), 5);
    expect(lines.first.offsetAtDisplayColumn(3), 4);
    expect(lines.first.offsetAtDisplayColumn(4.5), 7);
  });

  test('every scalar boundary including markers is independently editable', () {
    final line = wrapText(mixedSource, 60, inlineRuns: mixedRuns()).single;
    expect(line.columns, 7);
    expect(line.textIn(mixedSource), 'A 🎬 B C');
    for (final offset in [
      0,
      1,
      2,
      3,
      4,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
    ]) {
      expect(
        line.offsetAtDisplayColumn(line.displayColumnAtOffset(offset)),
        offset,
      );
    }
    expect(line.displayColumnAtOffset(mixedSource.length), 11);
  });

  test('escapes, literals, tab stops and hard lines use printed columns', () {
    final escaped = wrapText(
      r'\*A',
      2,
      inlineRuns: [run(0, 1, hidden: true)],
    ).single;
    expect(escaped.textIn(r'\*A'), '*A');
    expect(escaped.columns, 2);
    expect(wrapText('*A', 2).single.textIn('*A'), '*A');
    final source = '**A**\tB\n_C_\n';
    final lines = wrapText(
      source,
      60,
      inlineRuns: [
        run(0, 2, hidden: true),
        run(2, 3, bold: true),
        run(3, 5, hidden: true),
        run(8, 9, hidden: true),
        run(9, 10, underline: true),
        run(10, 11, hidden: true),
      ],
    );
    expect(lines.map((line) => line.columns), [5, 1, 0]);
    expect(lines.map((line) => line.textIn(source)), ['A   B', 'C', '']);
    expect(lines.map((line) => line.hardBreakOffsetUtf16), [7, 11, null]);
  });

  testWidgets('IME operates on exact source despite the projected display', (
    tester,
  ) async {
    final core = FakeCore([
      block('**🎬**', [
        run(0, 2, hidden: true),
        run(2, 4, bold: true),
        run(4, 6, hidden: true),
      ]),
    ]);
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorSurface(controller: controller)),
      ),
    );
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    final surface = tester.state<EditorSurfaceState>(
      find.byType(EditorSurface),
    );
    controller.setSelection(
      DocSelection(
        anchor: const DocPosition(block: 1, offsetUtf16: 4),
        focus: const DocPosition(block: 1, offsetUtf16: 2),
      ),
    );
    expect(surface.currentTextEditingValue.text, '**🎬**');
    expect(
      surface.currentTextEditingValue.selection,
      const TextSelection(baseOffset: 4, extentOffset: 2),
    );
    surface.updateEditingValue(
      const TextEditingValue(
        text: '**🎬!**',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 4, end: 5),
      ),
    );
    await tester.pump();
    expect(controller.focusedBlock.text, '**🎬!**');
    expect(controller.selection.focus.offsetUtf16, 5);
    controller.undo();
    expect(controller.focusedBlock.text, '**🎬**');
    expect(controller.layout.linesOf(0).single.columns, 1);
  });
}
