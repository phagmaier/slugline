import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/preview_view.dart';

import '../support/fake_output.dart';

/// §Phase 7's preview, which shows what the paginator decided and decides
/// nothing itself.
void main() {
  Future<void> pump(
    WidgetTester tester,
    PaginationView pagination, {
    PaperSize paper = PaperSize.usLetter,
    double scale = 4.0,
    PreviewAnchor? opensAt,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PreviewView(
          pagination: pagination,
          paper: paper,
          scale: scale,
          opensAt: opensAt,
        ),
      ),
    ),
  );

  ScrollPosition scroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('preview-sheets')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  group('sheets', () {
    testWidgets('the title page comes first and is not page one', (
      tester,
    ) async {
      await pump(tester, samplePagination());

      final sheets = PreviewView.sheetsOf(samplePagination());
      expect(sheets.first.isTitlePage, isTrue);
      expect(sheets.first.page.number, isNull, reason: 'and is not numbered');
      expect(sheets[1].page.number, 1, reason: 'the screenplay starts at one');
      expect(find.byKey(const Key('preview-title-page')), findsOneWidget);
      expect(find.byKey(const Key('preview-page-1')), findsOneWidget);
      expect(
        find.byKey(const Key('preview-page-number-null')),
        findsNothing,
        reason: 'the title page remains unnumbered',
      );
    });

    testWidgets('a page is numbered exactly where the paginator numbered it', (
      tester,
    ) async {
      // Small enough for both sheets to be built at once.
      await pump(tester, samplePagination(titlePage: false), scale: 2.4);
      expect(find.byKey(const Key('preview-page-1')), findsOneWidget);
      expect(
        find.byKey(const Key('preview-page-number-1')),
        findsNothing,
        reason: 'page one arrives without a number line and is drawn without',
      );
      expect(
        find.byKey(const Key('preview-page-number-2')),
        findsOneWidget,
        reason: 'the paginator-provided page number is visibly rendered',
      );

      await pump(
        tester,
        samplePagination(titlePage: false, numberFirstPage: true),
        scale: 2.4,
      );
      expect(
        find.byKey(const Key('preview-page-number-1')),
        findsOneWidget,
        reason: 'the option is a line in the snapshot, not a preview rule',
      );
      expect(find.byKey(const Key('preview-page-number-2')), findsOneWidget);
    });

    testWidgets('a script with no title page has none in the preview', (
      tester,
    ) async {
      final pagination = samplePagination(titlePage: false);
      await pump(tester, pagination);

      expect(PreviewView.sheetsOf(pagination).first.isTitlePage, isFalse);
      expect(find.byKey(const Key('preview-title-page')), findsNothing);
      expect(find.byKey(const Key('preview-page-1')), findsOneWidget);
    });

    testWidgets('every page the pagination has is a sheet, in order', (
      tester,
    ) async {
      final pagination = samplePagination(pages: 3);
      await pump(tester, pagination, scale: 2.4);

      final numbers = [
        for (final sheet in PreviewView.sheetsOf(pagination)) sheet.page.number,
      ];
      expect(numbers, [null, 1, 2, 3]);
    });
  });

  group('the list of sheets', () {
    testWidgets('is exactly as long as its sheets, from the first frame', (
      tester,
    ) async {
      // Title page and four pages on the 800 by 600 test surface.
      await pump(tester, samplePagination(pages: 4));
      const geometry = PreviewGeometry(paper: PaperSize.usLetter, scale: 4);
      final position = scroll(tester);

      // A list that measures its children can only guess at the ones it has
      // not built, and from the top it has built two of five.
      expect(
        position.maxScrollExtent,
        closeTo(24 + 5 * (geometry.height + 24) - 600, 1e-9),
      );
      final title = find.byKey(const Key('preview-title-page'));
      expect(tester.getTopLeft(title).dy, 24);
      expect(tester.getSize(title), Size(geometry.width, geometry.height));
      expect(
        tester.getTopLeft(find.byKey(const Key('preview-page-1'))).dy,
        closeTo(24 + geometry.height + 24, 1e-9),
        reason: 'one gap between two sheets',
      );

      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      final last = find.byKey(const Key('preview-page-4'));
      expect(tester.getSize(last), Size(geometry.width, geometry.height));
      expect(
        tester.getBottomLeft(last).dy,
        closeTo(600 - 24, 1e-9),
        reason: 'the last sheet has the margin under it the first has above',
      );
    });
  });

  // `samplePagination` gives page N a heading (block N0), a cue (N1) and a
  // speech (N2), each one wrapped line long. Page 1's speech ends in a
  // `(MORE)`, and the cue on every later page is a `CONT'D` — furniture that
  // names a block and is none of its lines.
  group('the sheet a place in the script is on', () {
    test('is the one carrying that line of that block', () {
      const speech = PreviewAnchor(block: 22, sourceLine: 0);
      expect(PreviewView.sheetOf(samplePagination(), speech), 2);
      expect(
        PreviewView.sheetOf(samplePagination(titlePage: false), speech),
        1,
        reason: 'a sheet is counted from the title page when there is one',
      );
      expect(
        PreviewView.sheetOf(
          samplePagination(pages: 4),
          const PreviewAnchor(block: 40, sourceLine: 0),
        ),
        4,
      );
    });

    test('falls to the nearest line above in the same block', () {
      // The pagination has one line of this block and the editor now has six:
      // the place is somewhere after line 0, and line 0 is what there is.
      expect(
        PreviewView.sheetOf(
          samplePagination(),
          const PreviewAnchor(block: 22, sourceLine: 5),
        ),
        2,
      );
    });

    test('does not count furniture as a line of the block it names', () {
      // Block 21 is page 2's `NADIA (CONT'D)` and nothing else, so it has no
      // line to be found by and the text before it answers instead.
      expect(
        PreviewView.sheetOf(
          samplePagination(),
          const PreviewAnchor(
            block: 21,
            sourceLine: 0,
            earlierBlocks: [20, 12, 11, 10],
          ),
        ),
        2,
      );
      // Block 12's `(MORE)` is on page 1 and so is its one real line. Taken
      // alone the furniture would say nothing different — which is the point
      // of asking a block that has it for the sheet its text ends on.
      expect(
        PreviewView.sheetOf(
          samplePagination(pages: 3),
          const PreviewAnchor(
            block: 99,
            sourceLine: 0,
            earlierBlocks: [21, 12],
          ),
        ),
        1,
        reason: 'the cue that was only ever a CONT\'D is passed over too',
      );
    });

    test(
      'is where the text before it ends, for a block that prints nothing',
      () {
        expect(
          PreviewView.sheetOf(
            samplePagination(pages: 3),
            const PreviewAnchor(
              block: 99,
              sourceLine: 0,
              // Nearest first: another silent block, then page 3's speech.
              earlierBlocks: [98, 32, 30, 22],
            ),
          ),
          3,
        );
      },
    );

    test('is nowhere when nothing at or before it reached a page', () {
      expect(
        PreviewView.sheetOf(
          samplePagination(),
          const PreviewAnchor(block: 99, sourceLine: 0),
        ),
        isNull,
      );
      expect(
        PreviewView.sheetOf(
          samplePagination(),
          const PreviewAnchor(
            block: 99,
            sourceLine: 0,
            earlierBlocks: [98, 97],
          ),
        ),
        isNull,
      );
    });
  });

  group('where the preview opens', () {
    testWidgets('at the top, when it is not told otherwise', (tester) async {
      await pump(tester, samplePagination(pages: 4));
      expect(scroll(tester).pixels, 0);
    });

    for (final paper in PaperSize.values) {
      testWidgets('at the sheet it is told, on ${paper.name} at any scale', (
        tester,
      ) async {
        for (final scale in [4.0, 6.5]) {
          // A new key each time: where a preview opens is read once.
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PreviewView(
                  key: ValueKey(scale),
                  pagination: samplePagination(pages: 4),
                  paper: paper,
                  scale: scale,
                  opensAt: const PreviewAnchor(block: 30, sourceLine: 0),
                ),
              ),
            ),
          );
          final sheet = PreviewGeometry(paper: paper, scale: scale).height;
          // Title page, page 1, page 2, then page 3: three sheets down.
          expect(scroll(tester).pixels, closeTo(3 * (sheet + 24), 1e-9));
          expect(
            tester.getTopLeft(find.byKey(const Key('preview-page-3'))).dy,
            closeTo(24, 1e-9),
          );
          // There in the first frame, at rest: nothing is carrying it there.
          expect(scroll(tester).isScrollingNotifier.value, isFalse);
          await tester.pumpAndSettle();
          expect(scroll(tester).pixels, closeTo(3 * (sheet + 24), 1e-9));
        }
      });
    }

    testWidgets('at the top when every sheet already fits in the pane', (
      tester,
    ) async {
      // Two sheets of 264 with their margins are the 600 of the test surface.
      await pump(
        tester,
        samplePagination(titlePage: false),
        scale: 2.4,
        opensAt: const PreviewAnchor(block: 20, sourceLine: 0),
      );
      expect(scroll(tester).maxScrollExtent, 0);
      expect(scroll(tester).pixels, 0);
      expect(find.byKey(const Key('preview-page-2')), findsOneWidget);
    });

    testWidgets('once: a later place, pagination or scale is not a reason '
        'to go back there', (tester) async {
      const third = PreviewAnchor(block: 30, sourceLine: 0);
      await pump(tester, samplePagination(pages: 4), opensAt: third);
      expect(scroll(tester).pixels, greaterThan(0));

      // The reader goes back to the top, and then everything a rebuild can
      // bring arrives. None of it is the preview opening.
      scroll(tester).jumpTo(0);
      await tester.pump();
      await pump(
        tester,
        samplePagination(pages: 4),
        opensAt: const PreviewAnchor(block: 20, sourceLine: 0),
      );
      expect(scroll(tester).pixels, 0);
      await pump(
        tester,
        samplePagination(pages: 4, numberFirstPage: true),
        opensAt: third,
      );
      expect(scroll(tester).pixels, 0);
      await pump(tester, samplePagination(pages: 4), scale: 6, opensAt: third);
      expect(scroll(tester).pixels, 0);
      await pump(
        tester,
        samplePagination(pages: 4),
        paper: PaperSize.a4,
        opensAt: third,
      );
      expect(scroll(tester).pixels, 0);
    });
  });

  group('geometry', () {
    test('a sheet is the paper it was paginated for', () {
      const letter = PreviewGeometry(paper: PaperSize.usLetter, scale: 10);
      // 8.5 by 11 inches, at ten columns and six rows to the inch.
      expect(letter.width, 850);
      expect(letter.height, 1100);

      const a4 = PreviewGeometry(paper: PaperSize.a4, scale: 10);
      expect(a4.width, lessThan(letter.width), reason: 'A4 is narrower');
      expect(a4.height, greaterThan(letter.height), reason: 'and taller');
    });

    test('column zero is the text area, an inch and a half in', () {
      const geometry = PreviewGeometry(paper: PaperSize.usLetter, scale: 10);
      expect(geometry.at(0, 0), const Offset(150, 100));
      // Sixty columns is the right-hand edge, at 7.5 inches.
      expect(geometry.at(0, 60).dx, 750);
      // Six rows to the inch.
      expect(geometry.at(6, 0).dy - geometry.at(0, 0).dy, 100);
    });

    test('a page number sits above the text area, not in it', () {
      const geometry = PreviewGeometry(paper: PaperSize.usLetter, scale: 10);
      // Row -3 is half an inch above the origin — §5.2's page number position.
      expect(geometry.at(-3, 0).dy, geometry.at(0, 0).dy - 50);
      expect(geometry.at(-3, 0).dy, greaterThan(0), reason: 'still on paper');
    });
  });
}
