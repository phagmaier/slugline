import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/page_indicator.dart';

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
);

PageView _page(int number, int block, int from, int to) => PageView(
  number: number,
  lines: [
    LayoutLineView(
      row: -3,
      column: 58,
      content: '$number.',
      sourceLine: null,
      kind: LayoutLineKind.pageNumber,
    ),
    for (var sourceLine = from; sourceLine < to; sourceLine++)
      LayoutLineView(
        row: sourceLine - from,
        column: 0,
        content: 'Action line $sourceLine.',
        block: block,
        sourceLine: sourceLine,
        kind: LayoutLineKind.content,
      ),
  ],
);

PaginationView _pagination(List<PageView> pages) => PaginationView(
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

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) async =>
      PaginationOutcome.current(pagination: pagination);

  @override
  Future<SaveOutcome> exportPdf(
    String path, {
    required PageSetup setup,
    bool overwrite = false,
  }) async => SaveOutcome.saved(path: path, bytes: 0, backup: null);
}

void main() {
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
    expect(find.text('Page 2 of 2'), findsOneWidget);

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(EditorSurface),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(find.text('Page 1 of 2'), findsOneWidget);
  });
}
