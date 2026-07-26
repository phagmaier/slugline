// Line breaking and the element grid.
//
// These are the numbers §5.2 specifies, asserted where they are used. When the
// `layout` crate lands in Phase 6 and the editor starts rendering the rows Rust
// computes (ADR 0005), this file is what says whether the two agree.

import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/line_layout.dart';
import 'package:slugline/editor/metrics.dart';

BlockView block(BlockKind kind, String text, {int id = 1}) => BlockView(
      id: id,
      kind: kind,
      sectionLevel: 0,
      text: text,
      forced: false,
      dual: false,
      readOnly: false,
    );

void main() {
  group('wrapping', () {
    test('short text is one line', () {
      final lines = wrapText('Hello.', 60);
      expect(lines.length, 1);
      expect(lines.single.start, 0);
      expect(lines.single.end, 6);
    });

    test('empty text still occupies a line', () {
      // Otherwise an empty block has no row, and no row means nowhere to put
      // the caret the user just pressed Enter to create.
      expect(wrapText('', 60).length, 1);
      expect(wrapText('', 60).single.length, 0);
    });

    test('breaks on a space and drops it', () {
      final lines = wrapText('aaa bbb ccc', 7);
      expect([for (final l in lines) 'aaa bbb ccc'.substring(l.start, l.end)],
          ['aaa bbb', 'ccc']);
    });

    test('never breaks mid-word when a space is available', () {
      const text = 'the quick brown fox jumps';
      final lines = wrapText(text, 12);
      for (final line in lines) {
        final slice = text.substring(line.start, line.end);
        expect(slice.trim(), slice);
        expect(line.length, lessThanOrEqualTo(12));
      }
    });

    test('a word longer than the column is broken rather than dropped', () {
      const text = 'supercalifragilistic';
      final lines = wrapText(text, 8);
      expect(lines.map((l) => text.substring(l.start, l.end)).join(), text);
      expect(lines.first.length, 8);
    });

    test('a hard break never splits a surrogate pair', () {
      // Nine ASCII characters then a clapperboard: breaking at column 10 would
      // land between the emoji's two code units, which is an offset the bridge
      // refuses outright (ADR 0001).
      const text = 'aaaaaaaaa🎬aaaaaaaaaa';
      final lines = wrapText(text, 10);
      for (final line in lines) {
        expect(_isLowSurrogate(text.codeUnitAt(line.start)), isFalse,
            reason: 'line starts inside a surrogate pair');
      }
    });

    test('embedded newlines are mandatory visual breaks', () {
      final twoLines = wrapText('One.\nTwo.', 60);
      expect(_ranges(twoLines), [(0, 4), (5, 9)]);
      expect(twoLines.first.hardBreakOffsetUtf16, 4);
      expect(twoLines.last.hardBreakOffsetUtf16, isNull);
      expect(_ranges(wrapText('One.\nTwo.\nThree.', 60)), [
        (0, 4),
        (5, 9),
        (10, 16),
      ]);
    });

    test('leading, trailing, and consecutive newlines keep empty lines', () {
      expect(_ranges(wrapText('\nTwo.', 60)), [(0, 0), (1, 5)]);
      expect(_ranges(wrapText('One.\n', 60)), [(0, 4), (5, 5)]);
      expect(_ranges(wrapText('One.\n\nThree.', 60)), [
        (0, 4),
        (5, 5),
        (6, 12),
      ]);
    });

    test('soft wrapping is applied independently on both hard lines', () {
      const text = 'aaaa bbbb\ncccc dddd';
      final lines = wrapText(text, 5);
      expect(_ranges(lines), [(0, 4), (5, 9), (10, 14), (15, 19)]);
      expect(
        [for (final line in lines) text.substring(line.start, line.end)],
        ['aaaa', 'bbbb', 'cccc', 'dddd'],
      );
    });

    test('a newline next to a wrap boundary creates no phantom row', () {
      final atBoundary = wrapText('abc\n', 3);
      expect(_ranges(atBoundary), [(0, 3), (4, 4)]);
      expect(atBoundary.first.hardBreakOffsetUtf16, 3);

      final afterWrapSpace = wrapText('abc \ndef', 3);
      expect(_ranges(afterWrapSpace), [(0, 3), (5, 8)]);
      expect(afterWrapSpace.first.hardBreakOffsetUtf16, 4);
    });

    test('Unicode offsets remain UTF-16 offsets across a newline', () {
      const text = '🎬One\nDeux🎬';
      expect(_ranges(wrapText(text, 60)), [(0, 5), (6, 12)]);
    });

    test('tabs and spaces next to a newline remain in the model slices', () {
      const text = '\t One \n Two\t';
      final lines = wrapText(text, 60);
      expect(_ranges(lines), [(0, 6), (7, 12)]);
      expect(
        [for (final line in lines) text.substring(line.start, line.end)],
        ['\t One ', ' Two\t'],
      );
    });
  });

  group('the element grid (§5.2)', () {
    test('indents are the spec\'s inches at ten characters to the inch', () {
      // 1.5" is column zero; everything else is measured from there.
      expect(metricsFor(BlockKind.sceneHeading).indent, 0); // 1.5"
      expect(metricsFor(BlockKind.action).indent, 0); // 1.5"
      expect(metricsFor(BlockKind.dialogue).indent, 10); // 2.5"
      expect(metricsFor(BlockKind.parenthetical).indent, 16); // 3.1"
      expect(metricsFor(BlockKind.character).indent, 22); // 3.7"
    });

    test('widths are the spec\'s', () {
      expect(metricsFor(BlockKind.sceneHeading).width, 60);
      expect(metricsFor(BlockKind.action).width, 60);
      expect(metricsFor(BlockKind.character).width, 33);
      expect(metricsFor(BlockKind.parenthetical).width, 26);
      expect(metricsFor(BlockKind.dialogue).width, 35);
    });

    test('dialogue and parentheticals sit under their cue with no gap', () {
      expect(metricsFor(BlockKind.character).blankLinesBefore, 1);
      expect(metricsFor(BlockKind.dialogue).blankLinesBefore, 0);
      expect(metricsFor(BlockKind.parenthetical).blankLinesBefore, 0);
      expect(metricsFor(BlockKind.sceneHeading).blankLinesBefore, 2);
    });

    test('headings, cues and transitions are shown in capitals', () {
      expect(displayText(BlockKind.sceneHeading, 'int. house - day'),
          'INT. HOUSE - DAY');
      expect(displayText(BlockKind.character, 'john'), 'JOHN');
      expect(displayText(BlockKind.transition, 'cut to:'), 'CUT TO:');
      expect(displayText(BlockKind.action, 'john enters'), 'john enters');
    });

    test('capitalising is refused when it would change the length', () {
      // 'ß'.toUpperCase() is 'SS'. One code unit longer means every caret
      // column after it would be drawn in the wrong place, so the text is left
      // as the writer wrote it.
      expect(displayText(BlockKind.character, 'STRAßE'), 'STRAßE');
    });
  });

  group('document rows', () {
    test('blank rows come from the element that follows them', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'One.', id: 1),
        block(BlockKind.sceneHeading, 'INT. HOUSE - DAY', id: 2),
        block(BlockKind.character, 'JOHN', id: 3),
        block(BlockKind.dialogue, 'Hello.', id: 4),
      ]);

      expect(layout.firstRowOf(0), 0, reason: 'nothing above the first block');
      expect(layout.firstRowOf(1), 3, reason: '1 row of action + 2 blank');
      expect(layout.firstRowOf(2), 5, reason: '+1 heading row +1 blank');
      expect(layout.firstRowOf(3), 6, reason: 'dialogue follows its cue');
      expect(layout.totalRows, 7);
    });

    test('a row maps back to the block that owns it', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'One.', id: 1),
        block(BlockKind.sceneHeading, 'INT. HOUSE - DAY', id: 2),
      ]);
      expect(layout.blockAtRow(0), 0);
      // Rows 1 and 2 are the heading's blank rows and belong to it.
      expect(layout.blockAtRow(1), 1);
      expect(layout.blockAtRow(3), 1);
      expect(layout.blockAtRow(99), 1, reason: 'past the end clamps');
    });

    test('a transition is right-aligned to the page edge', () {
      final layout = DocumentLayout([block(BlockKind.transition, 'CUT TO:')]);
      // 60 columns wide, 7 characters of text.
      expect(layout.columnOf(0, 0), 53);
    });

    test('centred text is centred in the text area', () {
      final layout = DocumentLayout([block(BlockKind.centered, 'THE END')]);
      expect(layout.columnOf(0, 0), (60 - 7) ~/ 2);
    });

    test('a wrapped block reports the line an offset is on', () {
      final layout = DocumentLayout([
        block(BlockKind.dialogue, 'a' * 40),
      ]);
      // 35 columns for dialogue, so this is two lines.
      expect(layout.linesOf(0).length, 2);
      expect(layout.lineIndexAt(0, 10), 0);
      expect(layout.lineIndexAt(0, 38), 1);
      expect(layout.rowAt(0, 38), 1);
    });

    test('the newline belongs to the line it terminates', () {
      final layout = DocumentLayout([block(BlockKind.action, 'One.\nTwo.')]);

      expect(layout.lineIndexAt(0, 4), 0, reason: 'before the newline');
      expect(layout.lineIndexAt(0, 5), 1, reason: 'after the newline');
      expect(layout.rowAt(0, 4), 0);
      expect(layout.rowAt(0, 5), 1);
      expect(layout.totalRows, 2);
    });

    test('hard lines increase every downstream block row', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'One.\nTwo.', id: 1),
        block(BlockKind.action, 'Three.', id: 2),
      ]);

      expect(layout.firstRowOf(1), 3, reason: 'two text rows and one blank');
      expect(layout.totalRows, 4);
    });
  });
}

List<(int, int)> _ranges(List<VisualLine> lines) => [
      for (final line in lines) (line.start, line.end),
    ];

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
