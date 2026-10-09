import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/typography.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

BlockView _block(int id, int lines) => BlockView(
  id: id,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: List.generate(lines, (line) => 'Action line $line.').join('\n'),
  forced: false,
  dual: false,
  readOnly: false,
  inlineRuns: const [],
);

/// A page as the paginator hands it over. [numbered] is whether it carries a
/// page-number line, which by default every page but the first does.
PageView _page(int number, int block, int from, int to, {bool? numbered}) =>
    PageView(
      number: number,
      lines: [
        if (numbered ?? number > 1)
          LayoutLineView(
            row: -3,
            column: 58,
            content: '$number.',
            runs: [
              EmphasisRunView(
                text: '$number.',
                bold: false,
                italic: false,
                underline: false,
              ),
            ],
            sourceLine: null,
            kind: LayoutLineKind.pageNumber,
          ),
        for (var sourceLine = from; sourceLine < to; sourceLine++)
          LayoutLineView(
            row: sourceLine - from,
            column: 0,
            content: 'Action line $sourceLine.',
            runs: [
              EmphasisRunView(
                text: 'Action line $sourceLine.',
                bold: false,
                italic: false,
                underline: false,
              ),
            ],
            block: block,
            sourceLine: sourceLine,
            kind: LayoutLineKind.content,
          ),
      ],
    );

PaginationView _pagination(List<PageView> pages) => PaginationView(
  scenes: const [],
  revision: 1,
  generation: 1,
  pageCount: pages.length,
  pages: pages,
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
  _OutputCore(super.blocks, this.pagination);

  PaginationView pagination;
  final List<PageSetup> setups = [];

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) async {
    setups.add(setup);
    return PaginationOutcome.current(pagination: pagination);
  }

  @override
  Future<SaveOutcome> exportPdf(
    String path, {
    required PageSetup setup,
    bool overwrite = false,
  }) async => SaveOutcome.saved(path: path, bytes: 0, backup: null);
}

void main() {
  group('zero printed pages', () {
    const setup = PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    );

    for (final (kind, text) in [
      (BlockKind.action, ''),
      (BlockKind.note, 'Private note.'),
      (BlockKind.section, 'Private section'),
      (BlockKind.synopsis, 'Private synopsis.'),
    ]) {
      test(
        '$kind has no current page when the snapshot prints nothing',
        () async {
          final controller = EditorController(
            FakeCore([
              BlockView(
                id: 1,
                kind: kind,
                sectionLevel: 1,
                text: text,
                forced: false,
                dual: false,
                readOnly: false,
                inlineRuns: const [],
              ),
            ]),
          );
          addTearDown(controller.dispose);
          final indicator = PageIndicator(
            controller: controller,
            output: FakeOutput(_pagination([])),
            setup: setup,
          );
          addTearDown(indicator.dispose);
          var notifications = 0;
          indicator.addListener(() => notifications++);
          expect(indicator.label, 'Pages …');
          await indicator.refresh();
          expect(indicator.current, isNull);
          expect(indicator.total, 0);
          expect(indicator.words, 0);
          expect(indicator.label, 'No printed pages');
          expect(indicator.pageStarts, isEmpty);
          expect(indicator.positionForPage(1), isNull);
          expect(notifications, 1);
          indicator.updateVisibleRow(10);
          expect(indicator.current, isNull);
          expect(notifications, 1);
        },
      );
    }

    test('zero/nonzero transitions clear the old page and notify', () async {
      final controller = EditorController(FakeCore([_block(1, 80)]));
      addTearDown(controller.dispose);
      final output = FakeOutput(_pagination([]));
      final indicator = PageIndicator(
        controller: controller,
        output: output,
        setup: setup,
        initialRow: 45,
      );
      addTearDown(indicator.dispose);
      var notifications = 0;
      indicator.addListener(() => notifications++);
      await indicator.refresh();
      expect(indicator.label, 'No printed pages');
      output.pagination = _pagination([
        _page(1, 1, 0, 40),
        _page(2, 1, 40, 80),
      ]);
      await indicator.refresh();
      expect(indicator.label, 'Page 2 of 2');
      expect(indicator.pageStarts, isNotEmpty);
      expect(indicator.positionForPage(2), isNotNull);
      output.pagination = _pagination([]);
      await indicator.refresh();
      expect(indicator.current, isNull);
      expect(indicator.total, 0);
      expect(indicator.words, 0);
      expect(indicator.label, 'No printed pages');
      expect(indicator.pageStarts, isEmpty);
      expect(indicator.positionForPage(2), isNull);
      output.pagination = _pagination([_page(1, 1, 0, 80)]);
      await indicator.refresh();
      expect(indicator.label, 'Page 1 of 1');
      expect(notifications, 4);
    });
  });

  test(
    'a split block uses its wrapped source line, not scroll percentage',
    () async {
      final core = FakeCore([_block(1, 80)]);
      final controller = EditorController(core);
      final output = FakeOutput(
        _pagination([_page(1, 1, 0, 40), _page(2, 1, 40, 80)]),
      );
      final indicator = PageIndicator(
        controller: controller,
        output: output,
        setup: const PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        ),
        initialRow: 45,
      );
      addTearDown(indicator.dispose);
      addTearDown(controller.dispose);

      await indicator.refresh();

      expect(indicator.current, 2);
      expect(indicator.total, 2);
      expect(indicator.label, 'Page 2 of 2');
    },
  );

  group('page starts', () {
    PageIndicator indicatorOver(
      EditorController controller,
      PaginationView pagination,
    ) {
      final indicator = PageIndicator(
        controller: controller,
        output: FakeOutput(pagination),
        setup: const PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        ),
      );
      addTearDown(indicator.dispose);
      return indicator;
    }

    test('are empty until a pagination has arrived', () {
      final controller = EditorController(FakeCore([_block(1, 80)]));
      addTearDown(controller.dispose);
      final indicator = indicatorOver(
        controller,
        _pagination([_page(1, 1, 0, 40), _page(2, 1, 40, 80)]),
      );

      expect(
        indicator.pageStarts,
        isEmpty,
        reason: 'an unpaginated editor draws no page furniture',
      );
    });

    test('name the editor row each page opens on, page one excepted', () async {
      final controller = EditorController(FakeCore([_block(1, 80)]));
      addTearDown(controller.dispose);
      final indicator = indicatorOver(
        controller,
        _pagination([
          _page(1, 1, 0, 40),
          _page(2, 1, 40, 70),
          _page(3, 1, 70, 80),
        ]),
      );

      await indicator.refresh();

      expect(indicator.pageStarts, [
        // One block, so a wrapped line index is its row: page two's first
        // printable line is source line 40, and page three's is 70.
        const PageStart(row: 40, number: 2),
        const PageStart(row: 70, number: 3),
      ]);
    });

    test('count the blocks above the page break', () async {
      final controller = EditorController(
        FakeCore([_block(10, 20), _block(20, 40)]),
      );
      addTearDown(controller.dispose);
      final indicator = indicatorOver(
        controller,
        _pagination([_page(1, 10, 0, 20), _page(2, 20, 0, 40)]),
      );

      await indicator.refresh();

      expect(indicator.pageStarts, [
        PageStart(row: controller.layout.firstRowOf(1), number: 2),
      ]);
    });

    test('re-resolve against the layout as it is now, not as it was', () async {
      final core = FakeCore([_block(10, 20), _block(20, 40)]);
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      final indicator = indicatorOver(
        controller,
        _pagination([_page(1, 10, 0, 20), _page(2, 20, 0, 40)]),
      );

      await indicator.refresh();
      final before = indicator.pageStarts.single.row;

      // Typing above a page break moves the text under it. The break belongs to
      // the same line of the same block, so its row has to move with it — the
      // alternative is a rule that drifts up the page between snapshots.
      final start = DocPosition(block: 10, offsetUtf16: 0);
      controller.setSelection(DocSelection(anchor: start, focus: start));
      controller.insertText('A new opening line.\n\n');

      expect(indicator.pageStarts.single.row, greaterThan(before));
      expect(indicator.pageStarts.single.number, 2);
    });
  });

  group('printed page numbers', () {
    const setup = PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    );

    test(
      'are the paginator\'s page-number lines, not a rule kept here',
      () async {
        final controller = EditorController(FakeCore([_block(1, 80)]));
        addTearDown(controller.dispose);
        final output = FakeOutput(
          _pagination([_page(1, 1, 0, 40), _page(2, 1, 40, 80)]),
        );
        final indicator = PageIndicator(
          controller: controller,
          output: output,
          setup: setup,
        );
        addTearDown(indicator.dispose);

        expect(
          indicator.printsNumber(1),
          isTrue,
          reason: 'nothing is unnumbered until a snapshot says so',
        );

        await indicator.refresh();
        expect(indicator.printsNumber(1), isFalse);
        expect(indicator.printsNumber(2), isTrue);

        // The option arrives as a line on page one of the next snapshot. The
        // indicator is told only that something changed, and repaints.
        var notified = 0;
        indicator.addListener(() => notified++);
        output.pagination = _pagination([
          _page(1, 1, 0, 40, numbered: true),
          _page(2, 1, 40, 80),
        ]);
        await indicator.refresh();
        expect(indicator.printsNumber(1), isTrue);
        expect(indicator.printsNumber(2), isTrue);
        expect(notified, greaterThan(0));

        output.closed = true;
        await indicator.refresh();
        expect(
          indicator.printsNumber(1),
          isTrue,
          reason: 'no snapshot, no claim',
        );
      },
    );

    /// Whether the surface's painter drew [label] as a sheet's page number,
    /// asked of the painter's own text cache after a paint.
    Future<bool> paintsSheetNumber(
      WidgetTester tester,
      String label, {
      required bool firstPageNumbered,
    }) async {
      final controller = EditorController(FakeCore([_block(1, 30)]));
      addTearDown(controller.dispose);
      // A short first page keeps both sheets inside the test viewport.
      final indicator = PageIndicator(
        controller: controller,
        output: FakeOutput(
          _pagination([
            _page(1, 1, 0, 5, numbered: firstPageNumbered),
            _page(2, 1, 5, 30),
          ]),
        ),
        setup: setup,
      );
      addTearDown(indicator.dispose);
      await indicator.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSurface(
              controller: controller,
              pageView: true,
              pageIndicator: indicator,
            ),
          ),
        ),
      );
      final paint = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(EditorSurface),
              matching: find.byType(CustomPaint),
            ),
          )
          .firstWhere(
            (paint) =>
                paint.painter.runtimeType.toString() == '_SurfacePainter',
          );
      final dynamic delegate = paint.painter!;
      expect(delegate.geometry.sheeted, isTrue, reason: 'page view is drawn');
      final recorder = ui.PictureRecorder();
      delegate.paint(Canvas(recorder), const Size(800, 600));
      recorder.endRecording().dispose();

      final hits = delegate.lineCache.hits as int;
      delegate.lineCache.line(
        label,
        chromeLabelStyle(delegate.colours.gutter as Color),
      );
      return delegate.lineCache.hits == hits + 1;
    }

    testWidgets('page view leaves the first sheet unnumbered by default', (
      tester,
    ) async {
      expect(
        await paintsSheetNumber(tester, '1.', firstPageNumbered: false),
        isFalse,
      );
    });

    testWidgets('page view still numbers the second sheet', (tester) async {
      expect(
        await paintsSheetNumber(tester, '2.', firstPageNumbered: false),
        isTrue,
      );
    });

    testWidgets('page view numbers the first sheet when the paginator did', (
      tester,
    ) async {
      expect(
        await paintsSheetNumber(tester, '1.', firstPageNumbered: true),
        isTrue,
      );
    });
  });

  testWidgets('the writing view displays current and total output pages', (
    tester,
  ) async {
    final blocks = [_block(10, 40), _block(20, 40)];
    final core = _OutputCore(
      blocks,
      _pagination([_page(1, 10, 0, 40), _page(2, 20, 0, 40)]),
    );
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    final secondBlockRow = controller.layout.firstRowOf(1);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 900,
          height: 320,
          child: EditorPage(
            controller: controller,
            initialScrollRow: secondBlockRow,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-page-indicator')), findsOneWidget);
    // The page count shares its line with the scene and word counts now, so it
    // is looked for inside the label rather than as the whole of it.
    expect(find.textContaining('Page 2 of 2'), findsOneWidget);
    expect(core.setups.last.boldSceneHeadings, isFalse);
    expect(core.setups.last.numberFirstPage, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 900,
          height: 320,
          child: EditorPage(
            controller: controller,
            initialScrollRow: secondBlockRow,
            initialPageSetup: const PageSetup(
              paper: PaperSize.usLetter,
              sceneNumbers: SceneNumbers.off,
              boldSceneHeadings: true,
              numberFirstPage: true,
              debugLinesPerPage: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      core.setups.last.boldSceneHeadings,
      isTrue,
      reason: 'A live heading preference change repaginates output.',
    );
    expect(
      core.setups.last.numberFirstPage,
      isTrue,
      reason: 'So does numbering the first page.',
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(find.textContaining('Page 1 of 2'), findsOneWidget);
  });
}
