import 'dart:async';

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/preview/preview_view.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

/// W5: the preview opens on the page the caret is on.
///
/// The document is a note, one Action paragraph long enough to cross three
/// pages, another note, a last paragraph on a fourth page, and a closing note.
/// One block over three pages is the case that matters: the caret's *block*
/// says nothing about its page, only its wrapped line does. The notes print
/// nothing, so a caret in one has no line of its own to be found by.
const _opening = 10;
const _long = 20;
const _aside = 30;
const _last = 40;
const _closing = 50;

const _lineCount = 140;
final _lines = List.generate(_lineCount, (line) => '😀 Action line $line.');

/// The first wrapped line of [_long] on each page, as the paginator would say.
const _firstLineOfPage = {1: 0, 2: 55, 3: 100};

LayoutLineView _line(int block, int sourceLine, int row, String content) =>
    LayoutLineView(
      row: row,
      column: 0,
      content: content,
      runs: const [],
      block: block,
      sourceLine: sourceLine,
      kind: LayoutLineKind.content,
    );

PageView _page(int number) {
  final first = _firstLineOfPage[number];
  final end = _firstLineOfPage[number + 1] ?? _lineCount;
  return PageView(
    number: number,
    lines: [
      if (number > 1)
        LayoutLineView(
          row: -3,
          column: 57,
          content: '$number.',
          runs: const [],
          sourceLine: null,
          kind: LayoutLineKind.pageNumber,
        ),
      if (first == null)
        _line(_last, 0, 0, 'The last paragraph.')
      else
        for (var line = first; line < end; line++)
          _line(_long, line, line - first, _lines[line]),
    ],
  );
}

PaginationView _pagination({bool titlePage = false}) => PaginationView(
  scenes: const [],
  revision: 1,
  generation: 1,
  pageCount: 4,
  titlePage: titlePage
      ? const PageView(
          number: null,
          lines: [
            LayoutLineView(
              row: 18,
              column: 21,
              content: 'READER NOTES',
              runs: [],
              sourceLine: null,
              kind: LayoutLineKind.title,
            ),
          ],
        )
      : null,
  pages: [for (var number = 1; number <= 4; number++) _page(number)],
  stats: const PaginationStats(
    blockHits: 0,
    blockMisses: 2,
    reusedPages: 0,
    reusedTailPages: 0,
    breakRuleIterations: 1,
    fellBackToNaive: false,
  ),
);

BlockView _block(int id, BlockKind kind, String text) => BlockView(
  id: id,
  kind: kind,
  sectionLevel: 0,
  text: text,
  forced: false,
  dual: false,
  readOnly: false,
  inlineRuns: const [],
);

class _OutputCore extends FakeCore implements ScreenplayOutput {
  _OutputCore({bool titlePage = false})
    : output = FakeOutput(_pagination(titlePage: titlePage)),
      super([
        _block(_opening, BlockKind.note, 'A source-only opening note.'),
        _block(_long, BlockKind.action, _lines.join('\n')),
        _block(_aside, BlockKind.note, 'An aside that prints nothing.'),
        _block(_last, BlockKind.action, 'The last paragraph.'),
        _block(_closing, BlockKind.note, 'A closing note.'),
      ]);

  final FakeOutput output;

  /// Set to leave the first pagination asked for — the status line's, made as
  /// the editor opens — unanswered for the whole test.
  bool holdFirst = false;
  int _asked = 0;

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) =>
      _asked++ == 0 && holdFirst
      ? Completer<PaginationOutcome>().future
      : output.paginate(setup);

  @override
  Future<SaveOutcome> exportPdf(
    String path, {
    required PageSetup setup,
    bool overwrite = false,
  }) => output.exportPdf(path, setup: setup, overwrite: overwrite);
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<EditorController> _open(
  WidgetTester tester, {
  bool titlePage = false,
  bool topBar = false,
  _OutputCore? core,
}) async {
  final controller = EditorController(
    core ?? _OutputCore(titlePage: titlePage),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(
        controller: controller,
        // The top bar is the application's, drawn only for a script that can
        // be closed back to the library.
        onClosed: topBar ? () async {} : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// Puts the caret at the start of wrapped line [line] of the long paragraph.
void _caretOnLine(EditorController controller, int line) {
  final offset = line == 0 ? 0 : _lines.take(line).join('\n').length + 1;
  final position = DocPosition(block: _long, offsetUtf16: offset);
  controller.setSelection(DocSelection(anchor: position, focus: position));
}

void _caretIn(EditorController controller, int block) {
  final position = DocPosition(block: block, offsetUtf16: 0);
  controller.setSelection(DocSelection(anchor: position, focus: position));
}

final _sheets = find.byKey(const Key('preview-sheets'));

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _sheets, matching: find.byType(Scrollable)),
    )
    .position;

/// How far below the top of the preview pane a sheet's top edge is.
double _topOf(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy - tester.getTopLeft(_sheets).dy;

/// The distance from one sheet's top to the next: a sheet and the gap under it.
double _pitch(WidgetTester tester) {
  final preview = tester.widget<PreviewView>(find.byType(PreviewView));
  return PreviewGeometry(paper: preview.paper, scale: preview.scale).height +
      24;
}

void main() {
  /// The export dialog is 940 by 700; the default test surface is 800 by 600.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1280, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('Ctrl+P opens the preview on the page the caret is on', (
    tester,
  ) async {
    final controller = await _open(tester);
    // Line 60 is five lines into the second page of a block that began on the
    // first: found by its line, where its block alone would say page 1.
    _caretOnLine(controller, 60);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(find.byType(ExportDialog), findsOneWidget);
    expect(_scroll(tester).pixels, _pitch(tester));
    expect(
      _topOf(tester, 'preview-page-2'),
      24,
      reason: 'page 2 sits where page 1 sits in a preview opened at the top',
    );
  });

  testWidgets('the caret is the focus of a selection, not its anchor', (
    tester,
  ) async {
    final controller = await _open(tester);
    final offset = _lines.take(110).join('\n').length + 1;
    controller.setSelection(
      DocSelection(
        anchor: const DocPosition(block: _long, offsetUtf16: 0),
        focus: DocPosition(block: _long, offsetUtf16: offset),
      ),
    );
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, 2 * _pitch(tester));
    expect(_topOf(tester, 'preview-page-3'), 24);
  });

  testWidgets('a title page is a sheet above page 1 and is counted as one', (
    tester,
  ) async {
    final controller = await _open(tester, titlePage: true);
    _caretOnLine(controller, 60);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, 2 * _pitch(tester));
    expect(_topOf(tester, 'preview-page-2'), 24);
  });

  testWidgets('a caret in something that prints nothing opens where the '
      'text before it ends', (tester) async {
    final controller = await _open(tester);
    // The aside follows a paragraph that began on page 1 and ended on page 3.
    _caretIn(controller, _aside);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, 2 * _pitch(tester));
    expect(_topOf(tester, 'preview-page-3'), 24);
  });

  testWidgets('and it is the nearest text before it that is asked', (
    tester,
  ) async {
    final controller = await _open(tester);
    // Two paragraphs printed before the closing note, on different pages. The
    // one directly above it is on page 4; the long one ended a page earlier.
    _caretIn(controller, _closing);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, greaterThan(2 * _pitch(tester)));
    expect(_scroll(tester).pixels, _scroll(tester).maxScrollExtent);
    expect(find.byKey(const Key('preview-page-4')), findsOneWidget);
  });

  testWidgets('the last page opens at the end of the preview, already there', (
    tester,
  ) async {
    final controller = await _open(tester);
    _caretIn(controller, _last);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    // One frame for the route, one for the pagination to arrive: the preview is
    // where it will stay the first time it is drawn, with nothing to settle.
    await tester.pump();
    await tester.pump();

    final scroll = _scroll(tester);
    expect(scroll.maxScrollExtent, greaterThan(0));
    expect(
      scroll.maxScrollExtent,
      lessThan(3 * _pitch(tester)),
      reason: 'the fixture has to ask for more than the list can scroll',
    );
    expect(scroll.pixels, scroll.maxScrollExtent);
    expect(scroll.isScrollingNotifier.value, isFalse);
    await tester.pumpAndSettle();
    expect(_scroll(tester).pixels, _scroll(tester).maxScrollExtent);
    expect(find.byKey(const Key('preview-page-4')), findsOneWidget);
  });

  testWidgets('the palette and the toolbar button open it the same way', (
    tester,
  ) async {
    final controller = await _open(tester, topBar: true);
    _caretOnLine(controller, 100);

    await _key(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Element or command'),
      'Preview and export',
    );
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_scroll(tester).pixels, 2 * _pitch(tester));
    expect(_topOf(tester, 'preview-page-3'), 24);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportDialog), findsNothing);

    _caretOnLine(controller, 55);
    await tester.tap(find.byKey(const ValueKey('open preview')));
    await tester.pumpAndSettle();
    expect(_scroll(tester).pixels, _pitch(tester));
    expect(_topOf(tester, 'preview-page-2'), 24);
  });

  for (final titlePage in [false, true]) {
    testWidgets(
      'page 1 opens at the top of the preview, titlePage=$titlePage',
      (tester) async {
        final controller = await _open(tester, titlePage: titlePage);
        // Well into the first page, and still the top: the title page has no
        // caret of its own to be opened from, and page 1 follows it directly.
        _caretOnLine(controller, 40);
        await _key(tester, LogicalKeyboardKey.keyP, control: true);
        await tester.pumpAndSettle();

        expect(_scroll(tester).pixels, 0);
        expect(
          _topOf(tester, titlePage ? 'preview-title-page' : 'preview-page-1'),
          24,
        );
      },
    );
  }

  testWidgets('a caret above everything that prints opens at the top', (
    tester,
  ) async {
    final controller = await _open(tester, titlePage: true);
    _caretIn(controller, _opening);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, 0);
    expect(_topOf(tester, 'preview-title-page'), 24);
  });

  testWidgets('the page comes from the preview\'s own pagination, not the '
      'status line\'s', (tester) async {
    final core = _OutputCore()..holdFirst = true;
    final controller = await _open(tester, core: core);
    expect(
      find.textContaining('Pages …'),
      findsOneWidget,
      reason: 'the editor has no snapshot, and so no page number to pass on',
    );
    _caretOnLine(controller, 60);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, _pitch(tester));
    expect(_topOf(tester, 'preview-page-2'), 24);
  });

  testWidgets('a pagination that came back stale is still opened on its page', (
    tester,
  ) async {
    final core = _OutputCore()..output.stale = true;
    final controller = await _open(tester, core: core);
    _caretOnLine(controller, 100);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();

    expect(_scroll(tester).pixels, 2 * _pitch(tester));
  });

  testWidgets(
    'it opens there once: repaginating does not pull the reader back',
    (tester) async {
      final core = _OutputCore();
      final controller = await _open(tester, core: core);
      _caretOnLine(controller, 100);
      await _key(tester, LogicalKeyboardKey.keyP, control: true);
      await tester.pumpAndSettle();
      expect(_scroll(tester).pixels, 2 * _pitch(tester));

      // The reader goes back to the top, then asks for a different paper. That
      // is a new pagination into the same view, and it is not the view opening.
      _scroll(tester).jumpTo(0);
      await tester.pump();
      final asked = core.output.setups.length;
      await tester.tap(find.byKey(const Key('paper-a4')));
      await tester.pumpAndSettle();
      expect(core.output.setups.length, asked + 1);
      expect(core.output.setups.last.paper, PaperSize.a4);
      expect(_scroll(tester).pixels, 0);

      await tester.ensureVisible(find.byKey(const Key('preview-actual-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preview-actual-size')));
      await tester.pumpAndSettle();
      expect(_scroll(tester).pixels, 0);
    },
  );

  testWidgets('opening the preview leaves the caret and the text alone', (
    tester,
  ) async {
    final core = _OutputCore();
    final controller = await _open(tester, core: core);
    _caretOnLine(controller, 60);
    final selection = controller.selection;
    final revision = controller.documentRevision;
    final source = controller.source;
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(controller.selection, selection);
    expect(controller.documentRevision, revision);
    expect(controller.source, source);
    expect(core.commands, isEmpty);
  });
}
