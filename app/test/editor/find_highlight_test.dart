// W8: while the find bar is open, every match on screen is tinted.
//
// What a match *is* belongs to `crates/document/src/find.rs`; the double here
// finds a plain substring. What is Dart's, and what these tests hold, is where
// the tint lands: on the grid cells of each match, on every row a wrapped match
// touches, under the text and under the selection, only for the rows on screen,
// and only while the bar is open.
//
// The rectangles are read off the surface's own painter with a recording
// canvas rather than out of a screenshot. A widget test has no script face —
// every glyph is a filled box an em wide — so the pixels under the text say
// nothing about what is behind it. `integration_test/editor_test.dart` reads
// the real pixels, in the real face, over the real core.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/editor/page_geometry.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

const _action = 'John leaves the house and the house is quiet.';

BlockView _block(int id, BlockKind kind, String text, {bool forced = false}) =>
    BlockView(
      id: id,
      kind: kind,
      sectionLevel: 0,
      text: text,
      forced: forced,
      dual: false,
      readOnly: false,
      inlineRuns: const [],
    );

FakeCore _script() => FakeCore([
  _block(1, BlockKind.sceneHeading, 'INT. HOUSE - DAY'),
  _block(2, BlockKind.action, _action),
]);

/// A core whose search heeds "Match case", as the real one does: the double's
/// is a plain `indexOf`, which cannot make a toggle change what is found.
class _CaseCore extends FakeCore {
  _CaseCore(super.blocks);

  @override
  List<FindMatch> find(FindQuery query) {
    queries.add(query);
    if (query.text.isEmpty) return const [];
    String fold(String text) => query.caseSensitive ? text : text.toLowerCase();
    return [
      for (final block in blocks(0, blockCount))
        for (final hit in fold(query.text).allMatches(fold(block.text)))
          FindMatch(block: block.id, startUtf16: hit.start, endUtf16: hit.end),
    ];
  }
}

Future<void> _pressFind(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens the find bar with the caret at the top of the script and searches for
/// [text], waiting out the keystroke debounce.
Future<void> _find(
  WidgetTester tester,
  EditorController controller,
  String text,
) async {
  caretAt(controller, 0, 0);
  await tester.pump();
  await _pressFind(tester);
  await tester.enterText(
    find.ancestor(of: find.text('Find'), matching: find.byType(TextField)),
    text,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// How far down the surface the find bar reaches. The rows sit that much lower
/// while it is up, so that none of them is stuck under it.
double _barBottom(WidgetTester tester) =>
    tester.getBottomLeft(find.byType(FindBar)).dy -
    tester.getTopLeft(find.byType(EditorSurface)).dy;

/// The surface's painter, as installed right now.
dynamic _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byType(CustomPaint),
      ),
    )
    .firstWhere(
      (paint) => paint.painter.runtimeType.toString() == '_SurfacePainter',
    )
    .painter!;

/// What the surface would draw now, call by call.
List<Invocation> _calls(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  _painter(
    tester,
  ).paint(canvas, const Size(editorViewportWidth, editorViewportHeight));
  return [for (final call in canvas.invocations) call.invocation];
}

/// Whether [call] fills a rectangle in [colour].
///
/// Compared as the 32 bits that reach the screen: a `Paint` keeps its colour in
/// single precision, so a translucent one does not come back equal to itself.
bool _fills(Invocation call, Color colour) =>
    call.memberName == #drawRect &&
    (call.positionalArguments[1] as Paint).color.toARGB32() ==
        colour.toARGB32();

/// Every rectangle the surface fills that is neither the selection nor the
/// caret. Those two are all it filled before W8, so what is left is the tint —
/// and a tint in the selection's own colour would be no tint at all.
List<Rect> _tints(WidgetTester tester) {
  final dynamic painter = _painter(tester);
  final selection = painter.colours.selection as Color;
  final caret = painter.colours.caret as Color;
  bool isCaret(Invocation call) =>
      _fills(call, caret) &&
      ((call.positionalArguments[0] as Rect).width - 2.0).abs() < 0.01;
  return [
    for (final call in _calls(tester))
      if (call.memberName == #drawRect &&
          !_fills(call, selection) &&
          !isCaret(call))
        call.positionalArguments[0] as Rect,
  ];
}

List<Rect> _selected(WidgetTester tester) {
  final selection = _painter(tester).colours.selection as Color;
  return [
    for (final call in _calls(tester))
      if (_fills(call, selection)) call.positionalArguments[0] as Rect,
  ];
}

/// The cells of [blockIndex] from [from] to [to], which must share a row, as
/// the rectangle the surface's own geometry puts them at.
Rect _cells(
  WidgetTester tester,
  EditorController controller,
  int blockIndex,
  int from,
  int to,
) {
  final geometry = _painter(tester).geometry as EditorGeometry;
  final layout = controller.layout;
  final lineIndex = layout.lineIndexAt(blockIndex, from);
  final line = layout.linesOf(blockIndex)[lineIndex];
  final column = layout.columnOf(blockIndex, lineIndex);
  final left = column + line.columnAtOffset(from);
  final right = column + line.columnAtOffset(to);
  return Rect.fromLTWH(
    geometry.columnLeft + left * geometry.advance,
    geometry.yOfRow(layout.firstRowOf(blockIndex) + lineIndex),
    (right - left) * geometry.advance,
    geometry.lineHeight,
  );
}

Matcher _closeTo(Rect expected) => predicate<Rect>(
  (rect) =>
      (rect.left - expected.left).abs() < 0.01 &&
      (rect.top - expected.top).abs() < 0.01 &&
      (rect.width - expected.width).abs() < 0.01 &&
      (rect.height - expected.height).abs() < 0.01,
  'a rectangle at $expected',
);

void main() {
  testWidgets(
    'forced cue find and hit testing stay on authored Unicode cells',
    (tester) async {
      const text = 'éßMcClane😀';
      final core = _CaseCore([
        _block(1, BlockKind.character, text, forced: true),
      ]);
      final controller = await pumpEditorPage(tester, core);
      await _find(tester, controller, 'McClane');
      final expected = _cells(tester, controller, 0, 2, 9);
      expect(_tints(tester).single, _closeTo(expected));
      expect(_selected(tester).single, _closeTo(expected));
      final geometry = _painter(tester).geometry as EditorGeometry;
      final row = controller.layout.firstRowOf(0);
      final column = controller.layout.columnOf(0, 0);
      final surface = tester.getTopLeft(find.byType(EditorSurface));
      await tester.tapAt(
        surface +
            Offset(
              geometry.columnLeft + (column + 9) * geometry.advance,
              geometry.yOfRow(row) + geometry.lineHeight / 2,
            ),
      );
      await tester.pump();
      expect(
        controller.selection.focus.offsetUtf16,
        9,
        reason:
            'the emoji starts after nine scalars and consumes two UTF-16 units',
      );
      expect(_tints(tester).single, _closeTo(expected));
      expect(controller.blocks.single.text, text);
      expect(core.commands, isEmpty);
    },
  );

  testWidgets('every match on screen is tinted while the find bar is open', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, _script());
    expect(_tints(tester), isEmpty, reason: 'nothing to find yet');

    await _find(tester, controller, 'house');
    expect(controller.matches, hasLength(2));

    // The grid, named independently of the layout the painter reads: the
    // action is the block under the heading and starts at the left margin, so
    // its sixteenth and thirtieth cells are where the two words begin.
    final row = controller.layout.firstRowOf(1);
    final geometry = editorGeometry(
      totalRows: controller.layout.totalRows,
      topInset: _barBottom(tester),
    );
    Rect word(int column) => Rect.fromLTWH(
      geometry.columnLeft + column * geometry.advance,
      geometry.yOfRow(row),
      5 * geometry.advance,
      geometry.lineHeight,
    );

    expect(_tints(tester), [_closeTo(word(16)), _closeTo(word(30))]);
    expect(
      _selected(tester),
      [_closeTo(word(16))],
      reason: 'the match the caret is on is still the selection',
    );
  });

  testWidgets('the tint lies under the selection and under the text', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, _script());
    await _find(tester, controller, 'house');

    final dynamic painter = _painter(tester);
    final selection = painter.colours.selection as Color;
    final calls = _calls(tester);
    final row = _cells(tester, controller, 1, 16, 21).top;
    bool onRow(Invocation call) =>
        call.memberName == #drawRect &&
        (call.positionalArguments[0] as Rect).top == row;
    final tint = calls.indexWhere(
      (call) => onRow(call) && !_fills(call, selection),
    );
    final selected = calls.indexWhere(
      (call) => onRow(call) && _fills(call, selection),
    );
    final text = calls.lastIndexWhere(
      (call) => call.memberName == #drawParagraph,
    );

    expect(tint, isNonNegative, reason: 'the row has a tint');
    expect(tint, lessThan(selected), reason: 'the selection reads over it');
    expect(selected, lessThan(text), reason: 'and the text over both');
    expect(
      (calls[tint].positionalArguments[1] as Paint).color.a,
      lessThan(1.0),
      reason: 'a tint, not a block of colour: the sheet shows through',
    );
  });

  testWidgets('closing the bar takes the tint away and keeps the selection', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, _script());
    await _find(tester, controller, 'house');
    expect(_tints(tester), hasLength(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_tints(tester), isEmpty);
    expect(controller.matches, hasLength(2), reason: 'Ctrl+G still has them');
    expect(_selected(tester), [
      _closeTo(_cells(tester, controller, 1, 16, 21)),
    ]);

    // Find next, with the bar closed, moves the selection and tints nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.matchIndex, 1);
    expect(_tints(tester), isEmpty);
  });

  testWidgets('a match that wraps is tinted on both of its rows', (
    tester,
  ) async {
    const text =
        'alpha bravo charlie delta echo foxtrot golf hotel india juliet '
        'kilo lima mike november oscar papa quebec romeo sierra tango';
    final controller = await pumpEditorPage(
      tester,
      FakeCore.single(BlockKind.action, text),
    );
    final lines = controller.layout.linesOf(0);
    expect(lines.length, greaterThan(1), reason: 'the fixture has to wrap');
    // The last word of the first row, the space the wrap swallowed, and the
    // first word of the second.
    final from = text.lastIndexOf(' ', lines[0].end - 1) + 1;
    final to = text.indexOf(' ', lines[1].start);

    await _find(tester, controller, text.substring(from, to));
    expect(controller.matches, hasLength(1));

    expect(_tints(tester), [
      _closeTo(_cells(tester, controller, 0, from, lines[0].end)),
      _closeTo(_cells(tester, controller, 0, lines[1].start, to)),
    ]);
  });

  testWidgets('a tint is measured in grid cells, not code units', (
    tester,
  ) async {
    // The clapperboard is two code units in one cell and the tab one code unit
    // in several, so the word starts at offset 5 and at some other column.
    const text = '🎬 a\thouse';
    final controller = await pumpEditorPage(
      tester,
      FakeCore.single(BlockKind.action, text),
    );
    await _find(tester, controller, 'house');

    final line = controller.layout.linesOf(0).single;
    final column = line.columnAtOffset(5);
    expect(column, isNot(5), reason: 'the fixture has to tell the two apart');
    final geometry = _painter(tester).geometry as EditorGeometry;
    expect(_tints(tester), [
      _closeTo(
        Rect.fromLTWH(
          geometry.columnLeft + column * geometry.advance,
          geometry.yOfRow(0),
          5 * geometry.advance,
          geometry.lineHeight,
        ),
      ),
    ]);
  });

  testWidgets('the tint follows the text when an edit moves a match', (
    tester,
  ) async {
    final controller = await pumpEditorPage(tester, _script());
    await _find(tester, controller, 'house');

    // Delete "John " from the front of the paragraph, in the document itself.
    selectFromTo(controller, 1, 0, 1, 5);
    controller.deleteSelection();
    await tester.pump();

    expect(
      controller.blocks[1].text,
      'leaves the house and the house is quiet.',
    );
    expect(_tints(tester), [
      _closeTo(_cells(tester, controller, 1, 11, 16)),
      _closeTo(_cells(tester, controller, 1, 25, 30)),
    ]);
  });

  testWidgets('the surface tints only when told to, and repaints when told', (
    tester,
  ) async {
    // The surface on its own, with no page and no bar: whether Find is open is
    // the page's to know, and a query outlives the bar that made it.
    final controller = EditorController(_script());
    addTearDown(controller.dispose);
    controller.search(
      const FindQuery(
        text: 'house',
        caseSensitive: false,
        wholeWord: false,
        kinds: [],
      ),
    );
    Future<void> pump({required bool highlight}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorSurface(
            controller: controller,
            highlightMatches: highlight,
          ),
        ),
      ),
    );

    await pump(highlight: false);
    expect(controller.matches, hasLength(2));
    expect(_tints(tester), isEmpty);
    final quiet = _painter(tester) as CustomPainter;

    await pump(highlight: true);
    expect(_tints(tester), hasLength(2));
    expect(
      (_painter(tester) as CustomPainter).shouldRepaint(quiet),
      isTrue,
      reason: 'nothing else changed, and the tints have to appear',
    );
  });

  testWidgets('a toggle that drops matches and keeps the selection redraws', (
    tester,
  ) async {
    final core = _CaseCore([
      _block(1, BlockKind.sceneHeading, 'INT. HOUSE - DAY'),
      _block(2, BlockKind.action, _action),
    ]);
    final controller = await pumpEditorPage(tester, core);
    await _find(tester, controller, 'house');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.matches, hasLength(3));
    expect(controller.matchIndex, 1, reason: 'the first one in the action');
    final selection = controller.selection;
    final heading = _cells(tester, controller, 0, 5, 10);
    expect(_tints(tester), contains(_closeTo(heading)));

    final surface = tester.renderObject<RenderCustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_SurfacePainter',
      ),
    );
    expect(surface.debugNeedsPaint, isFalse);
    await tester.tap(find.text('Match case'));

    // The match in the heading is gone and the caret has not moved. Nothing
    // about the selection changed, and the surface still has to be told.
    expect(controller.matches, hasLength(2));
    expect(controller.selection, selection);
    expect(
      surface.debugNeedsPaint,
      isTrue,
      reason: 'or HOUSE stays tinted until something else repaints',
    );

    await tester.pumpAndSettle();
    expect(_tints(tester), [
      _closeTo(_cells(tester, controller, 1, 16, 21)),
      _closeTo(_cells(tester, controller, 1, 30, 35)),
    ]);
    expect(
      tester.widget<Text>(find.byKey(const Key('find-match-count'))).data,
      '1 of 2',
    );
  });

  testWidgets('only the rows on screen are tinted, however many match', (
    tester,
  ) async {
    final core = FakeCore([
      for (var id = 1; id <= 3000; id++)
        _block(id, BlockKind.action, 'line $id'),
    ]);
    final controller = await pumpEditorPage(tester, core);
    await _find(tester, controller, 'line');
    expect(controller.matches, hasLength(3000));

    final tints = _tints(tester);
    expect(tints, isNotEmpty);
    expect(
      tints.length,
      lessThan(100),
      reason: 'the band on screen, not the document',
    );
    for (final rect in tints) {
      expect(rect.top, lessThan(editorViewportHeight));
    }
  });

  test(
    'matchesIn answers per block, in order, and never from a stale list',
    () {
      final controller = EditorController(_script());
      addTearDown(controller.dispose);
      expect(controller.matchesIn(2), isEmpty);

      controller.search(
        const FindQuery(
          text: 'house',
          caseSensitive: false,
          wholeWord: false,
          kinds: [],
        ),
      );
      expect(
        controller.matchesIn(1),
        isEmpty,
        reason: 'HOUSE is not house here',
      );
      expect(
        [for (final match in controller.matchesIn(2)) match.startUtf16],
        [16, 30],
      );
      expect(controller.matchesIn(99), isEmpty, reason: 'no such block');

      selectFromTo(controller, 1, 0, 1, 5);
      controller.deleteSelection();
      expect(
        [for (final match in controller.matchesIn(2)) match.startUtf16],
        [11, 25],
        reason: 'an edit moved them',
      );

      controller.search(
        const FindQuery(
          text: '',
          caseSensitive: false,
          wholeWord: false,
          kinds: [],
        ),
      );
      expect(controller.matchesIn(2), isEmpty);
    },
  );

  test('a search that lands on the selection already in force still tells '
      'its listeners', () {
    final controller = EditorController(
      _CaseCore([
        _block(1, BlockKind.sceneHeading, 'INT. HOUSE - DAY'),
        _block(2, BlockKind.action, _action),
      ]),
    );
    addTearDown(controller.dispose);
    FindQuery house({required bool caseSensitive}) => FindQuery(
      text: 'house',
      caseSensitive: caseSensitive,
      wholeWord: false,
      kinds: const [],
    );
    caretAt(controller, 1, 0);
    controller.search(house(caseSensitive: false));
    expect(controller.matchIndex, 1);
    final selection = controller.selection;

    var told = 0;
    controller.addListener(() => told++);
    controller.search(house(caseSensitive: true));

    expect(controller.selection, selection, reason: 'the caret did not move');
    expect(controller.matches, hasLength(2), reason: 'and the list did');
    expect(controller.matchIndex, 0, reason: 'and so did its place in it');
    expect(told, 1);
  });

  group('the find bar does not cover the match the caret is on', () {
    ScrollPosition scroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(EditorSurface),
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          ),
        )
        .position;

    /// Where [row] is drawn, measured down from the top of the surface.
    double rowTop(WidgetTester tester, int row) =>
        (_painter(tester).geometry as EditorGeometry).yOfRow(row) -
        scroll(tester).pixels;

    FakeCore long() => FakeCore([
      for (var n = 1; n <= 120; n++)
        _block(n, BlockKind.action, 'Line $n of the house.'),
    ]);

    testWidgets('at the top of the script, where there is nowhere to scroll', (
      tester,
    ) async {
      final controller = await pumpEditorPage(tester, _script());
      expect(scroll(tester).maxScrollExtent, 0);
      await _find(tester, controller, 'house');

      expect(
        rowTop(tester, controller.caretRow),
        greaterThanOrEqualTo(_barBottom(tester)),
      );
      expect(_selected(tester), isNotEmpty, reason: 'and it is painted there');
    });

    testWidgets('walking back up through the matches', (tester) async {
      final controller = await pumpEditorPage(tester, long());
      await _find(tester, controller, 'house');
      for (var step = 0; step < 60; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pumpAndSettle();
      expect(scroll(tester).pixels, greaterThan(0));

      for (var step = 0; step < 59; step++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        final top = rowTop(tester, controller.caretRow);
        expect(top, greaterThanOrEqualTo(_barBottom(tester)), reason: '$step');
        expect(top, lessThan(editorViewportHeight));
      }
      expect(controller.matchIndex, 1);
    });

    testWidgets('when Find opens on a match that is under it', (tester) async {
      final controller = await pumpEditorPage(tester, _script());
      // The first "house" of the action, selected: the search Find opens on.
      selectFromTo(controller, 1, 16, 1, 21);
      await tester.pump();
      final row = controller.caretRow;

      await _pressFind(tester);

      expect(controller.matchIndex, 0);
      expect(controller.caretRow, row);
      expect(rowTop(tester, row), greaterThanOrEqualTo(_barBottom(tester)));
    });

    // Nothing to search for, so no match is chosen and nothing is a reason to
    // move: not a caret well clear of the bar, and not a bare caret under it,
    // which nobody is looking at while the keyboard is in the bar. The short
    // script is the one with nowhere to scroll until the bar is up.
    for (final (name, blocks, caret) in [
      ('long', 120, 60),
      ('short', 14, 13),
      ('short, with the caret under the bar', 14, 0),
    ]) {
      testWidgets('opening and closing Find leaves a script where it was: '
          '$name', (tester) async {
        final controller = await pumpEditorPage(
          tester,
          FakeCore([
            for (var n = 1; n <= blocks; n++)
              _block(n, BlockKind.action, 'Line $n of the house.'),
          ]),
        );
        caretAt(controller, caret, 0);
        await tester.pumpAndSettle();
        final row = controller.caretRow;
        final before = rowTop(tester, row);
        final offset = scroll(tester).pixels;
        expect(offset > 0, name == 'long');

        await _pressFind(tester);
        expect(find.byType(FindBar), findsOneWidget);
        expect(before < _barBottom(tester), caret == 0);
        // To a rounding: the rows and the view have both moved by the bar.
        expect(rowTop(tester, row), closeTo(before, 0.001));

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(FindBar), findsNothing);
        expect(rowTop(tester, row), closeTo(before, 0.001));
        expect(scroll(tester).pixels, closeTo(offset, 0.001));
      });
    }
  });
}
