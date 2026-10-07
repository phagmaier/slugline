import 'dart:async';

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/go_to_page_dialog.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/editor/autosave.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

const _lines = 140;
final _text = List.generate(
  _lines,
  (line) => '😀 Action line $line.',
).join('\n');

PageView _page(int number, int sourceLine) => PageView(
  number: number,
  lines: [
    if (number > 1)
      const LayoutLineView(
        row: 0,
        column: 22,
        content: "(CONT'D)",
        runs: [],
        block: 20,
        sourceLine: null,
        kind: LayoutLineKind.continued,
      ),
    LayoutLineView(
      row: 0,
      column: 0,
      content: '😀 Action line $sourceLine.',
      runs: const [],
      block: 20,
      sourceLine: sourceLine,
      kind: LayoutLineKind.content,
    ),
  ],
);

PaginationView _pagination() => PaginationView(
  revision: 1,
  generation: 1,
  pageCount: 3,
  pages: [_page(1, 0), _page(2, 55), _page(3, 100)],
  stats: const PaginationStats(
    blockHits: 0,
    blockMisses: 1,
    reusedPages: 0,
    reusedTailPages: 0,
    breakRuleIterations: 1,
    fellBackToNaive: false,
  ),
);

class _OutputCore extends FakeCore implements ScreenplayOutput {
  _OutputCore()
    : output = FakeOutput(_pagination()),
      super([
        const BlockView(
          id: 10,
          kind: BlockKind.note,
          sectionLevel: 0,
          text: 'A source-only opening note.',
          forced: false,
          dual: false,
          readOnly: false,
        ),
        BlockView(
          id: 20,
          kind: BlockKind.action,
          sectionLevel: 0,
          text: _text,
          forced: false,
          dual: false,
          readOnly: false,
        ),
      ]);

  final FakeOutput output;
  Completer<PaginationOutcome>? pending;

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) =>
      pending?.future ?? output.paginate(setup);

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
  await tester.pumpAndSettle();
}

Future<EditorController> _open(
  WidgetTester tester, {
  _OutputCore? core,
  bool pageView = true,
  int initialScrollRow = 0,
  AutosaveDriver? autosave,
}) async {
  final controller = EditorController(core ?? _OutputCore());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(
        controller: controller,
        pageView: pageView,
        initialScrollRow: initialScrollRow,
        autosave: autosave,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _submit(WidgetTester tester, String page) async {
  await tester.enterText(find.widgetWithText(TextField, 'Page number'), page);
  await _key(tester, LogicalKeyboardKey.enter);
}

void main() {
  testWidgets('the palette offers Go to page', (tester) async {
    final controller = await _open(tester);
    await _key(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.enterText(
      find.widgetWithText(TextField, 'Element or command'),
      'Go to page',
    );
    await tester.pumpAndSettle();
    expect(find.text('Go to page…'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.enterText(find.widgetWithText(TextField, 'Page number'), '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(GoToPageDialog), findsNothing);
    expect(controller.selection.focus.block, 20);
  });

  testWidgets('Ctrl+L opens the page-number prompt', (tester) async {
    await _open(tester);
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    expect(find.widgetWithText(TextField, 'Page number'), findsOneWidget);
  });

  for (final pageView in [false, true]) {
    testWidgets(
      'snapshot lines place and reveal the caret, pageView=$pageView',
      (tester) async {
        final core = _OutputCore();
        final controller = await _open(tester, core: core, pageView: pageView);
        final source = controller.source;
        for (final (page, line) in [(2, 55), (3, 100)]) {
          await _key(tester, LogicalKeyboardKey.keyL, control: true);
          await _submit(tester, '$page');
          expect(find.byType(GoToPageDialog), findsNothing);
          expect(controller.selection.focus.block, 20);
          expect(
            controller.selection.focus.offsetUtf16,
            _text.split('\n').take(line).join('\n').length + 1,
          );
          expect(controller.hasSelection, isFalse);
          expect(_scroll(tester).pixels, greaterThan(0));
        }
        await _key(tester, LogicalKeyboardKey.keyL, control: true);
        await _submit(tester, '1');
        expect(
          controller.selection.focus,
          const DocPosition(block: 10, offsetUtf16: 0),
        );
        expect(_scroll(tester).pixels, 0);
        expect(controller.source, source);
        expect(core.dirty, isFalse);
        expect(core.commands, isEmpty);
        // The dialog's field must release the keyboard back to the surface.
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(controller.selection.focus.offsetUtf16, 1);
      },
    );

    testWidgets(
      'page one reveals the top with an unchanged caret, pageView=$pageView',
      (tester) async {
        final controller = await _open(
          tester,
          pageView: pageView,
          initialScrollRow: 80,
        );
        final selection = controller.selection;
        expect(_scroll(tester).pixels, greaterThan(0));
        await _key(tester, LogicalKeyboardKey.keyL, control: true);
        await _submit(tester, '1');
        expect(controller.selection, selection);
        expect(_scroll(tester).pixels, 0);
      },
    );
  }

  for (final input in [
    '0',
    '4',
    '-1',
    'oops',
    '1.5',
    '',
    '999999999999999999999',
  ]) {
    testWidgets('invalid page "$input" keeps the script and caret', (
      tester,
    ) async {
      final controller = await _open(tester);
      final selection = controller.selection;
      final source = controller.source;
      await _key(tester, LogicalKeyboardKey.keyL, control: true);
      await _submit(tester, input);
      expect(
        find.text('Enter a whole page number from 1 to 3.'),
        findsOneWidget,
      );
      expect(find.byType(GoToPageDialog), findsOneWidget);
      expect(controller.selection, selection);
      expect(controller.source, source);
      await _submit(tester, '2');
      expect(controller.selection.focus.block, 20);
    });
  }

  testWidgets('Escape preserves a selection and restores the keyboard', (
    tester,
  ) async {
    final controller = await _open(tester);
    const selection = DocSelection(
      anchor: DocPosition(block: 20, offsetUtf16: 20),
      focus: DocPosition(block: 20, offsetUtf16: 8),
    );
    controller.setSelection(selection);
    await tester.pump();
    final source = controller.source;
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    await tester.enterText(find.widgetWithText(TextField, 'Page number'), '2');
    // Editor-page shortcuts must not reach the script while the modal owns focus.
    await _key(tester, LogicalKeyboardKey.keyK, control: true);
    expect(find.widgetWithText(TextField, 'Element or command'), findsNothing);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GoToPageDialog), findsNothing);
    expect(controller.selection, selection);
    expect(controller.source, source);
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.hasSelection, isFalse);
    expect(controller.selection.focus.offsetUtf16, 8);
  });

  testWidgets('a pending snapshot disables navigation until it arrives', (
    tester,
  ) async {
    final core = _OutputCore()..pending = Completer<PaginationOutcome>();
    final controller = await _open(tester, core: core);
    final selection = controller.selection;
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    expect(find.text('Pages are not available yet.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Go'))
          .onPressed,
      isNull,
    );
    await _key(tester, LogicalKeyboardKey.enter);
    expect(controller.selection, selection);
    core.pending!.complete(
      PaginationOutcome.current(pagination: core.output.pagination),
    );
    core.pending = null;
    await tester.pumpAndSettle();
    await _submit(tester, '2');
    expect(controller.selection.focus.block, 20);
    expect(find.byType(GoToPageDialog), findsNothing);
  });

  testWidgets('the page dialog holds autosave until Cancel', (tester) async {
    final core = _OutputCore()..filePath = '/scripts/draft.fountain';
    final controller = EditorController(core);
    final autosave = AutosaveDriver(
      core: core,
      changes: controller,
      onOutcome: (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(autosave.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(controller: controller, autosave: autosave),
      ),
    );
    await tester.pumpAndSettle();
    controller.insertText('Unsaved ');
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    expect(autosave.suppressed, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(core.saves, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(autosave.suppressed, isFalse);
    expect(core.onDisk, controller.source);
  });

  testWidgets('a refreshed snapshot updates the valid page range', (
    tester,
  ) async {
    final core = _OutputCore();
    final controller = await _open(tester, core: core);
    final before = controller.selection;
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    core.output.pagination = PaginationView(
      revision: 2,
      generation: 2,
      pageCount: 1,
      pages: [_page(1, 0)],
      stats: core.output.pagination.stats,
    );
    await tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .pageIndicator!
        .refresh();
    await tester.pumpAndSettle();
    await _submit(tester, '2');
    expect(find.text('Enter a whole page number from 1 to 1.'), findsOneWidget);
    expect(controller.selection, before);
    await _submit(tester, '1');
    expect(find.byType(GoToPageDialog), findsNothing);
  });

  testWidgets('an unavailable source line keeps the prompt and caret', (
    tester,
  ) async {
    final core = _OutputCore();
    final controller = await _open(tester, core: core);
    // The last snapshot can name a block absent from the current document.
    core.output.pagination = PaginationView(
      revision: 1,
      generation: 1,
      pageCount: 2,
      pages: [
        _page(1, 0),
        const PageView(
          number: 2,
          lines: [
            LayoutLineView(
              row: 0,
              column: 0,
              content: 'Removed.',
              runs: [],
              block: 999,
              sourceLine: 0,
              kind: LayoutLineKind.content,
            ),
          ],
        ),
      ],
      stats: core.output.pagination.stats,
    );
    await tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .pageIndicator!
        .refresh();
    final before = controller.selection;
    await _key(tester, LogicalKeyboardKey.keyL, control: true);
    await _submit(tester, '2');
    expect(
      find.text('That page is not available yet. Try again.'),
      findsOneWidget,
    );
    expect(controller.selection, before);
    expect(find.byType(GoToPageDialog), findsOneWidget);
  });

  test(
    'page targets use wrapped UTF-16 starts and refuse removed lines',
    () async {
      final core = _OutputCore();
      final controller = EditorController(core);
      final indicator = PageIndicator(
        controller: controller,
        output: core.output,
        setup: const PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(indicator.dispose);
      expect(indicator.positionForPage(1), isNull);
      // A long paragraph makes sourceLine 1 a soft wrap, not the second hard line.
      controller.jumpToBlock(20);
      controller.insertText(List.filled(40, '😀 word ').join());
      core.output.pagination = PaginationView(
        revision: 2,
        generation: 2,
        pageCount: 2,
        pages: [_page(1, 0), _page(2, 1)],
        stats: core.output.pagination.stats,
      );
      await indicator.refresh();
      final start = controller.layout.linesOf(1)[1].start;
      expect(
        indicator.positionForPage(2),
        DocPosition(block: 20, offsetUtf16: start),
      );
      controller.setSelection(
        DocSelection(
          anchor: const DocPosition(block: 20, offsetUtf16: 0),
          focus: DocPosition(
            block: 20,
            offsetUtf16: controller.blocks[1].text.length,
          ),
        ),
      );
      controller.insertText('Short.');
      expect(indicator.positionForPage(2), isNull);
      expect(indicator.positionForPage(0), isNull);
      expect(indicator.positionForPage(3), isNull);
    },
  );
}
