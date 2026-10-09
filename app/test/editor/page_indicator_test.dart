import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/page_geometry.dart';
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

  /// Set to keep a pagination from landing until it completes, the way the
  /// worker's answer arrives some frames after the script is on screen.
  Completer<void>? hold;

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) async {
    setups.add(setup);
    await hold?.future;
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
          expect(indicator.firstPage, isNull);
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
      expect(indicator.firstPage, 1);
      expect(indicator.pageStarts, isNotEmpty);
      expect(indicator.positionForPage(2), isNotNull);
      output.pagination = _pagination([]);
      await indicator.refresh();
      expect(indicator.current, isNull);
      expect(indicator.total, 0);
      expect(indicator.words, 0);
      expect(indicator.label, 'No printed pages');
      expect(indicator.firstPage, isNull);
      expect(indicator.pageStarts, isEmpty);
      expect(indicator.positionForPage(2), isNull);
      output.pagination = _pagination([_page(1, 1, 0, 80)]);
      await indicator.refresh();
      expect(indicator.label, 'Page 1 of 1');
      expect(indicator.firstPage, 1);
      expect(indicator.pageStarts, isEmpty);
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

  test(
    'a block that prints nothing is on the page the text above ends on',
    () async {
      final controller = EditorController(
        FakeCore([
          _block(1, 80),
          BlockView(
            id: 2,
            kind: BlockKind.note,
            sectionLevel: 0,
            text: 'A private note.',
            forced: false,
            dual: false,
            readOnly: false,
            inlineRuns: const [],
          ),
          _block(3, 5),
        ]),
      );
      addTearDown(controller.dispose);
      final indicator = PageIndicator(
        controller: controller,
        // The paragraph runs from page 1 to page 3; the note under it reaches
        // no page, and the paragraph after it follows on page 3.
        output: FakeOutput(
          _pagination([
            _page(1, 1, 0, 30),
            _page(2, 1, 30, 60),
            PageView(
              number: 3,
              lines: [..._page(3, 1, 60, 80).lines, ..._page(3, 3, 0, 5).lines],
            ),
          ]),
        ),
        setup: const PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        ),
      );
      addTearDown(indicator.dispose);
      await indicator.refresh();

      final note = controller.layout.firstRowOf(1);
      indicator.updateVisibleRow(note - 1);
      expect(indicator.label, 'Page 3 of 3');
      indicator.updateVisibleRow(note);
      expect(indicator.label, 'Page 3 of 3');
      indicator.updateVisibleRow(controller.layout.firstRowOf(2));
      expect(indicator.label, 'Page 3 of 3');
      // The block that prints keeps its own lines' pages.
      indicator.updateVisibleRow(0);
      expect(indicator.label, 'Page 1 of 3');
      indicator.updateVisibleRow(45);
      expect(indicator.label, 'Page 2 of 3');
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
      expect(indicator.firstPage, isNull);
    });

    test('a script of one page has a first page and no starts', () async {
      final controller = EditorController(FakeCore([_block(1, 5)]));
      addTearDown(controller.dispose);
      final output = FakeOutput(_pagination([_page(1, 1, 0, 5)]));
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
      );
      addTearDown(indicator.dispose);

      await indicator.refresh();
      expect(indicator.firstPage, 1);
      expect(indicator.pageStarts, isEmpty);

      // The blank sheet an empty script prints: a page no line of the document
      // reached is a page all the same.
      output.pagination = _pagination([const PageView(number: 1, lines: [])]);
      await indicator.refresh();
      expect(indicator.firstPage, 1);
      expect(indicator.label, 'Page 1 of 1');

      output.closed = true;
      await indicator.refresh();
      expect(indicator.firstPage, isNull, reason: 'no snapshot, no claim');
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

  group('page view draws a sheet per page once a pagination lands', () {
    Finder surfacePaint() => find.descendant(
      of: find.byType(EditorSurface),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_SurfacePainter',
      ),
    );

    EditorGeometry geometry(WidgetTester tester) =>
        (tester.widget<CustomPaint>(surfacePaint()).painter! as dynamic)
                .geometry
            as EditorGeometry;

    /// The paper of [sheet], as the painter draws it.
    RRect paper(
      EditorGeometry geometry,
      ({double top, double bottom, int number}) sheet,
    ) => RRect.fromRectAndRadius(
      Rect.fromLTRB(
        geometry.sheetLeft,
        sheet.top,
        geometry.sheetLeft + geometry.sheetWidth,
        sheet.bottom,
      ),
      const Radius.circular(4),
    );

    /// An editor whose pagination has been asked for and has not landed: the
    /// script is on screen, settled, with nothing further to rebuild it.
    Future<(_OutputCore, EditorController)> open(
      WidgetTester tester,
      List<PageView> pages, {
      int lines = 5,
      bool pageView = true,
    }) async {
      final core = _OutputCore([_block(1, lines)], _pagination(pages))
        ..hold = Completer<void>();
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(controller: controller, pageView: pageView),
        ),
      );
      await tester.pumpAndSettle();
      expect(geometry(tester).sheeted, isFalse);
      expect(geometry(tester).sheets(), isEmpty);
      expect(surfacePaint(), isNot(paints..rrect()), reason: 'a plain column');
      return (core, controller);
    }

    testWidgets('a script of one page', (tester) async {
      final (core, _) = await open(tester, [_page(1, 1, 0, 5)]);
      final before = geometry(tester).yOfRow(0);

      core.hold!.complete();
      await tester.pump();
      await tester.pump();

      final drawn = geometry(tester);
      expect(find.textContaining('Page 1 of 1'), findsOneWidget);
      expect(drawn.sheeted, isTrue);
      final sheet = drawn.sheets().single;
      expect(sheet.number, 1);
      expect(surfacePaint(), paints..rrect(rrect: paper(drawn, sheet)));
      // The sheet brings its inch of top margin; the column had half of one.
      expect(drawn.yOfRow(0), greaterThan(before));
    });

    testWidgets('an empty script, which prints one blank page', (tester) async {
      final (core, _) = await open(tester, [
        const PageView(number: 1, lines: []),
      ], lines: 0);

      core.hold!.complete();
      await tester.pump();
      await tester.pump();

      final drawn = geometry(tester);
      expect(drawn.sheets().single.number, 1);
      expect(
        surfacePaint(),
        paints..rrect(rrect: paper(drawn, drawn.sheets().single)),
      );
    });

    testWidgets('a script of several, left alone while its pages arrive', (
      tester,
    ) async {
      final (core, _) = await open(tester, [
        _page(1, 1, 0, 3),
        _page(2, 1, 3, 5),
      ]);

      core.hold!.complete();
      await tester.pump();
      await tester.pump();

      final drawn = geometry(tester);
      final sheets = drawn.sheets().toList();
      expect(sheets.map((sheet) => sheet.number), [1, 2]);
      // Each sheet is its paper and then its edge.
      expect(
        surfacePaint(),
        paints
          ..rrect(rrect: paper(drawn, sheets[0]))
          ..rrect(rrect: paper(drawn, sheets[0]))
          ..rrect(rrect: paper(drawn, sheets[1]))
          ..rrect(rrect: paper(drawn, sheets[1])),
      );
    });

    testWidgets('and follows the script from one page to two and back', (
      tester,
    ) async {
      final (core, controller) = await open(tester, [_page(1, 1, 0, 5)]);
      core.hold!.complete();
      core.hold = null;
      await tester.pumpAndSettle();
      expect(geometry(tester).sheets().map((sheet) => sheet.number), [1]);

      core.pagination = _pagination([_page(1, 1, 0, 3), _page(2, 1, 3, 5)]);
      controller.insertText('More. ');
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(geometry(tester).sheets().map((sheet) => sheet.number), [1, 2]);

      core.pagination = _pagination([_page(1, 1, 0, 5)]);
      controller.undo();
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(geometry(tester).sheets().map((sheet) => sheet.number), [1]);
    });

    testWidgets('but none for a script that prints nothing', (tester) async {
      final (core, _) = await open(tester, []);

      core.hold!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No printed pages'), findsOneWidget);
      expect(geometry(tester).sheeted, isFalse);
      expect(surfacePaint(), isNot(paints..rrect()));
    });

    testWidgets('and none in the continuous view', (tester) async {
      final (core, _) = await open(tester, [
        _page(1, 1, 0, 5),
      ], pageView: false);

      core.hold!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Page 1 of 1'), findsOneWidget);
      expect(geometry(tester).sheeted, isFalse);
      expect(geometry(tester).rules(), isEmpty);
      expect(surfacePaint(), isNot(paints..rrect()));
    });
  });

  group('pages that land leave the view on the text it was on', () {
    EditorGeometry geometry(WidgetTester tester) =>
        (tester
                        .widget<CustomPaint>(
                          find.descendant(
                            of: find.byType(EditorSurface),
                            matching: find.byWidgetPredicate(
                              (widget) =>
                                  widget is CustomPaint &&
                                  widget.painter.runtimeType.toString() ==
                                      '_SurfacePainter',
                            ),
                          ),
                        )
                        .painter!
                    as dynamic)
                .geometry
            as EditorGeometry;

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

    const letter = PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    );

    /// Three hundred rows in three pages, on screen and settled with the
    /// pagination asked for and not yet landed: a plain column.
    Future<_OutputCore> open(
      WidgetTester tester, {
      required int initialScrollRow,
      PageSetup setup = letter,
      _OutputCore? reopen,
    }) async {
      final core =
          reopen ??
                _OutputCore(
                  [_block(1, 300)],
                  _pagination([
                    _page(1, 1, 0, 100),
                    _page(2, 1, 100, 200),
                    _page(3, 1, 200, 300),
                  ]),
                )
            ..hold = Completer<void>();
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            controller: controller,
            initialScrollRow: initialScrollRow,
            initialPageSetup: setup,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(geometry(tester).sheeted, isFalse);
      return core;
    }

    Future<void> land(WidgetTester tester, _OutputCore core) async {
      core.hold!.complete();
      core.hold = null;
      await tester.pump();
      await tester.pump();
      expect(geometry(tester).sheeted, isTrue);
    }

    testWidgets('a restored row is still at the top when the sheets arrive', (
      tester,
    ) async {
      final core = await open(tester, initialScrollRow: 250);
      expect(scroll(tester).pixels, geometry(tester).yOfRow(250));

      await land(tester, core);

      // Two page breaks above it, each with its margins and the gap between
      // the sheets: the row is that much further down the scroll extent.
      expect(geometry(tester).rowAtY(scroll(tester).pixels), 250);
      expect(scroll(tester).pixels, geometry(tester).yOfRow(250));
      expect(find.textContaining('Page 3 of 3'), findsOneWidget);
      expect(core.scrollRow, 250, reason: 'and that is the row parked');
    });

    testWidgets('a view part of the way into a row keeps the part', (
      tester,
    ) async {
      final core = await open(tester, initialScrollRow: 0);
      final position = scroll(tester);
      position.jumpTo(geometry(tester).yOfRow(150) + 5);
      await tester.pump();

      await land(tester, core);

      expect(position.pixels, closeTo(geometry(tester).yOfRow(150) + 5, 1e-6));
    });

    testWidgets('a break landing under a sliver of a row moves the sliver', (
      tester,
    ) async {
      // All but five pixels of row 199 are above the view and row 200 is the
      // first whole one. Page 3 turns out to start there: what was being read
      // stays put, and the last of page 2 goes up with its sheet.
      final core = await open(tester, initialScrollRow: 0);
      final position = scroll(tester);
      final before = geometry(tester);
      position.jumpTo(before.yOfRow(200) - 5);
      await tester.pump();

      await land(tester, core);

      expect(position.pixels, closeTo(geometry(tester).yOfRow(200) - 5, 1e-6));
    });

    testWidgets('a script at its top stays at its top', (tester) async {
      final core = await open(tester, initialScrollRow: 0);
      expect(scroll(tester).pixels, 0);

      await land(tester, core);

      // The first sheet's top margin is taller than the column's was, and it
      // is shown, not scrolled past to keep the first row where it sat.
      expect(scroll(tester).pixels, 0);
    });

    testWidgets('and pages that move later leave it there too', (tester) async {
      final core = await open(tester, initialScrollRow: 250);
      await land(tester, core);
      final controller = tester
          .widget<EditorPage>(find.byType(EditorPage))
          .controller;

      // Another paper: every break is somewhere else, and there are more.
      core.pagination = _pagination([
        for (var page = 0; page < 6; page++)
          _page(page + 1, 1, page * 50, (page + 1) * 50),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            controller: controller,
            initialScrollRow: 250,
            initialPageSetup: const PageSetup(
              paper: PaperSize.a4,
              sceneNumbers: SceneNumbers.off,
              boldSceneHeadings: false,
              numberFirstPage: false,
              debugLinesPerPage: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(geometry(tester).pageStarts, hasLength(5));
      expect(scroll(tester).pixels, geometry(tester).yOfRow(250));
      expect(find.textContaining('Page 6 of 6'), findsOneWidget);
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
