// Line breaking and the element grid.
//
// These are the numbers §5.2 specifies, asserted where they are used. The
// editor keeps its own wrapping for 1.0 rather than rendering rows computed in
// Rust (ADR 0018), so this file is one half of a contract: the other half is
// `layout::break_lines`, and `line_break_differential_test.dart` is what pins
// the two together over the whole corpus. A case added here that the Rust engine
// would answer differently is a divergence, not a preference — and one this file
// does not cover, the differential test will.

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
      expect(wrapText('', 60).single.columns, 0);
    });

    test('breaks on a space and drops it', () {
      final lines = wrapText('aaa bbb ccc', 7);
      expect(
        [for (final l in lines) 'aaa bbb ccc'.substring(l.start, l.end)],
        ['aaa bbb', 'ccc'],
      );
    });

    test('never breaks mid-word when a space is available', () {
      const text = 'the quick brown fox jumps';
      final lines = wrapText(text, 12);
      for (final line in lines) {
        final slice = text.substring(line.start, line.end);
        expect(slice.trim(), slice);
        expect(line.columns, lessThanOrEqualTo(12));
      }
    });

    test('a word longer than the column is broken rather than dropped', () {
      const text = 'supercalifragilistic';
      final lines = wrapText(text, 8);
      expect(lines.map((l) => text.substring(l.start, l.end)).join(), text);
      expect(lines.first.columns, 8);
    });

    test('a hard break never splits a surrogate pair', () {
      // Nine ASCII characters then a clapperboard: breaking at column 10 would
      // land between the emoji's two code units, which is an offset the bridge
      // refuses outright (ADR 0001).
      const text = 'aaaaaaaaa🎬aaaaaaaaaa';
      final lines = wrapText(text, 10);
      for (final line in lines) {
        expect(
          _isLowSurrogate(text.codeUnitAt(line.start)),
          isFalse,
          reason: 'line starts inside a surrogate pair',
        );
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

  // Every case below is asserted verbatim in `layout::line_break`'s tests. They
  // are the shared contract in `docs/LINE_BREAKING.md`, so an expectation that
  // changes here has to change there in the same commit. They are kept as
  // readable prose about the contract; the generated fixture the differential
  // test consumes is what proves it over text nobody wrote down here.
  group('the shared contract with layout::break_lines', () {
    test('one scalar is one column, including astral planes', () {
      // Nine characters and a clapperboard fill ten columns. Counting UTF-16
      // code units wrapped the emoji onto the next line; Rust never did.
      expect(_rendered('aaaaaaaaa🎬bbb', 10), ['aaaaaaaaa🎬', 'bbb']);
      expect(_rendered('🎬🎬🎬', 2), ['🎬🎬', '🎬']);
      expect(_rendered('e\u{301}xy', 2), ['e\u{301}', 'xy']);
    });

    test('a whole space run is consumed at a wrap point', () {
      expect(_rendered('one    two', 4), ['one ', 'two']);
      expect(_rendered('one   twothree', 4), ['one ', 'twot', 'hree']);
      expect(_rendered('a  b cd', 5), ['a  b', 'cd']);
    });

    test('a leading space run is not a wrap opportunity', () {
      expect(_rendered('   abcdef', 3), ['   ', 'abc', 'def']);
    });

    test('trailing spaces never make a phantom line', () {
      expect(_rendered('abc ', 3), ['abc']);
      expect(_rendered('abc  ', 3), ['abc']);
      expect(_rendered('abc     ', 3), ['abc']);
      expect(_rendered('ab ', 4), ['ab ']);
      expect(_rendered('ab  ', 4), ['ab  ']);
    });

    test('tab stops are four columns from the start of a hard line', () {
      expect(_rendered('\tx', 20), ['    x']);
      expect(_rendered('a\tx', 20), ['a   x']);
      expect(_rendered('abc\tx', 20), ['abc x']);
      expect(_rendered('abcd\tx', 20), ['abcd    x']);
      expect(_rendered('abcd\n\tx', 20), ['abcd', '    x']);
      expect(_rendered('ab\tcd\tef', 8), ['ab  cd ', 'ef']);
    });

    test('a wrap inside a tab expansion consumes it', () {
      expect(_rendered('\t\tabc', 3), ['   ', 'abc']);
    });

    test('hard lines are kept, including empty ones', () {
      expect(_rendered('', 10), ['']);
      expect(_rendered('\n', 10), ['', '']);
      expect(_rendered('one\n', 10), ['one', '']);
      expect(_rendered('\ntwo', 10), ['', 'two']);
      expect(_rendered('one\n\n\ntwo', 10), ['one', '', '', 'two']);
      expect(_rendered('abc \ndef', 3), ['abc', 'def']);
    });

    test('a width below one is one column', () {
      expect(_rendered('abc', 0), ['a', 'b', 'c']);
    });
  });

  group('model offsets under the contract', () {
    test('a consumed space run is the gap between two rows', () {
      const text = 'one    two';
      final lines = wrapText(text, 4);
      // The row keeps the space that fitted; the other three are the gap.
      expect(_ranges(lines), [(0, 4), (7, 10)]);
      expect(lines.first.columns, 4);
    });

    test('a row split inside a tab points at neither half of it', () {
      const text = '\t\tabc';
      final lines = wrapText(text, 3);
      // Three cells of the first tab are drawn, and both tabs land in the gap:
      // an indivisible source character cannot be half on a row.
      expect(_ranges(lines), [(0, 0), (2, 5)]);
      expect(lines.first.columns, 3);
      expect(lines.first.offsetAtColumn(1), 0);
      expect(lines.last.offsetAtColumn(0), 2);
    });

    test('a tab is one offset and up to four columns', () {
      const text = 'a\tbc';
      final line = wrapText(text, 20).single;
      expect((line.start, line.end), (0, 4));
      // The tab starts at column 1 and runs to the stop at column 4.
      expect(line.columns, 6);
      expect(line.textIn(text), 'a   bc');
      // Every cell of the expansion answers with the tab itself, so a click in
      // the middle of it puts the caret before the tab, never inside it.
      expect(
        [for (var c = 0; c <= 6; c++) line.offsetAtColumn(c)],
        [0, 1, 1, 1, 2, 3, 4],
      );
      expect(
        [for (var o = 0; o <= 4; o++) line.columnAtOffset(o)],
        [0, 1, 4, 5, 6],
      );
    });

    test('an astral scalar is two offsets and one column', () {
      const text = 'a🎬b';
      final line = wrapText(text, 20).single;
      expect((line.start, line.end), (0, 4));
      expect(line.columns, 3);
      expect(line.columnAtOffset(3), 2, reason: 'the b, after the emoji');
      expect(line.offsetAtColumn(2), 3);
      // A column inside the surrogate pair is not addressable: column 1 is the
      // whole emoji.
      expect(line.offsetAtColumn(1), 1);
    });

    test('capitals leave every offset where it was', () {
      const model = 'int. café - jour';
      final display = displayText(BlockKind.sceneHeading, model);
      expect(display, 'INT. CAFÉ - JOUR');
      expect(display.length, model.length);
      expect(_ranges(wrapText(display, 12)), _ranges(wrapText(model, 12)));
    });

    test('a scalar that refuses capitals keeps its column', () {
      // `ß` upper-cases to `SS`, so it alone stays as the writer typed it and
      // the rest of the block is still capitals. `layout::engine`'s
      // `display_text` answers this block identically.
      const model = 'straße to:';
      final display = displayText(BlockKind.transition, model);
      expect(display, 'STRAßE TO:');
      expect(display.length, model.length);
      expect(_ranges(wrapText(display, 6)), _ranges(wrapText(model, 6)));
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
      expect(metricsFor(BlockKind.parenthetical).width, 20);
      expect(metricsFor(BlockKind.dialogue).width, 35);
    });

    test('dialogue and parentheticals sit under their cue with no gap', () {
      expect(metricsFor(BlockKind.character).blankLinesBefore, 1);
      expect(metricsFor(BlockKind.dialogue).blankLinesBefore, 0);
      expect(metricsFor(BlockKind.parenthetical).blankLinesBefore, 0);
      expect(metricsFor(BlockKind.sceneHeading).blankLinesBefore, 1);
    });

    test('headings, cues and transitions are shown in capitals', () {
      expect(
        displayText(BlockKind.sceneHeading, 'int. house - day'),
        'INT. HOUSE - DAY',
      );
      expect(displayText(BlockKind.character, 'john'), 'JOHN');
      expect(displayText(BlockKind.transition, 'cut to:'), 'CUT TO:');
      expect(displayText(BlockKind.action, 'john enters'), 'john enters');
    });

    test('every Latin letter with a capital is shown with one', () {
      // A heading is shown in capitals, and that is not negotiable. Across the
      // whole Latin range — ASCII, the accented Latin-1 letters, and Latin
      // Extended-A and B — `displayText` returns the capital of every letter
      // that has one, so nothing a script is written in is ever left in lower
      // case.
      for (var scalar = 0; scalar <= 0x024F; scalar++) {
        final source = String.fromCharCode(scalar);
        expect(
          displayText(BlockKind.sceneHeading, source),
          source.toUpperCase(),
          reason: 'U+${scalar.toRadixString(16).padLeft(4, '0')}',
        );
      }
      // The three letters Dart's own upper-casing declines are the three whose
      // capital is more than one scalar, which is the set `layout::engine`'s
      // `every_latin_letter_with_a_capital_gets_one` pins on the Rust side.
      for (final letter in ['ß', 'ŉ', 'ǰ']) {
        expect(letter.toUpperCase(), letter);
        expect(displayText(BlockKind.sceneHeading, letter), letter);
      }
    });

    test('capitalising is refused for a scalar that would change length', () {
      // Full-Unicode 'ß' upper-cases to 'SS'. One code unit longer means every
      // caret column after it would be drawn in the wrong place, so that one
      // scalar is left as the writer wrote it and the rest is capitalised.
      expect(displayText(BlockKind.character, 'straße'), 'STRAßE');
      expect(displayText(BlockKind.character, 'STRAßE'), 'STRAßE');
      expect(
        displayText(BlockKind.sceneHeading, 'int. ﬁnca - day'),
        'INT. ﬁNCA - DAY',
      );
    });
  });

  group('document rows', () {
    test('lyric runs keep one leading blank and consecutive rows', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'Opening.', id: 1),
        block(BlockKind.lyric, 'First lyric.', id: 2),
        block(BlockKind.lyric, 'Second lyric.', id: 3),
        block(BlockKind.lyric, 'Third lyric.', id: 4),
        block(BlockKind.action, 'Interlude.', id: 5),
        block(BlockKind.lyric, 'Next verse.', id: 6),
      ]);
      expect(
        [for (var i = 0; i < 6; i++) layout.firstRowOf(i)],
        [0, 2, 3, 4, 6, 8],
      );
      expect(layout.totalRows, 9);
      expect(layout.blockAtRow(3), 2);
      expect(layout.rowAt(3, 0), 4);
    });

    test('changing a lyric predecessor reindexes an unchanged successor', () {
      final blocks = [
        block(BlockKind.lyric, 'First.', id: 1),
        block(BlockKind.lyric, 'Second.', id: 2),
        block(BlockKind.lyric, 'Third.', id: 3),
      ];
      final layout = DocumentLayout(blocks);
      expect([for (var i = 0; i < 3; i++) layout.firstRowOf(i)], [0, 1, 2]);

      blocks[1] = block(BlockKind.action, 'Interlude.', id: 2);
      layout.rewrap(1);
      layout.reindex();
      expect([for (var i = 0; i < 3; i++) layout.firstRowOf(i)], [0, 2, 4]);

      blocks.removeAt(1);
      layout.removeAt(1);
      layout.reindex();
      expect(layout.firstRowOf(1), 1);
      expect(layout.totalRows, 2);
    });

    test('blank rows come from the element that follows them', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'One.', id: 1),
        block(BlockKind.sceneHeading, 'INT. HOUSE - DAY', id: 2),
        block(BlockKind.character, 'JOHN', id: 3),
        block(BlockKind.dialogue, 'Hello.', id: 4),
      ]);

      expect(layout.firstRowOf(0), 0, reason: 'nothing above the first block');
      expect(layout.firstRowOf(1), 2, reason: '1 row of action + 1 blank');
      expect(layout.firstRowOf(2), 4, reason: '+1 heading row +1 blank');
      expect(layout.firstRowOf(3), 5, reason: 'dialogue follows its cue');
      expect(layout.totalRows, 6);
    });

    test('a row maps back to the block that owns it', () {
      final layout = DocumentLayout([
        block(BlockKind.action, 'One.', id: 1),
        block(BlockKind.sceneHeading, 'INT. HOUSE - DAY', id: 2),
      ]);
      expect(layout.blockAtRow(0), 0);
      // Row 1 is the heading's blank row and belongs to it.
      expect(layout.blockAtRow(1), 1);
      expect(layout.blockAtRow(2), 1);
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
      final layout = DocumentLayout([block(BlockKind.dialogue, 'a' * 40)]);
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

/// What the rows draw — the same shape `layout::break_lines` returns, so its
/// expectations can be asserted here character for character.
List<String> _rendered(String text, int width) => [
  for (final line in wrapText(text, width)) line.textIn(text),
];

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
