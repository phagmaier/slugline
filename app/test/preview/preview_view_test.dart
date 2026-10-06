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
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PreviewView(pagination: pagination, paper: paper, scale: scale),
      ),
    ),
  );

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
