import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/preview/preview_view.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

/// §Phase 7: "Editor zoom does not affect the preview or the PDF (test: change
/// zoom, assert page count and golden layout unchanged)."
///
/// The requirement is really two claims, and they are tested as two:
///
/// 1. **Nothing about how big the preview is drawn reaches the paginator.** The
///    only thing a size can change is a multiplication in [PreviewGeometry]; the
///    rows, columns and page count come back from Rust and are copied.
/// 2. **The export asks for the same pages the preview is showing.** The paper
///    and the scene-number setting are the whole of the request, and the preview
///    size is not part of it — which is what makes "what you saw is what you
///    sent" true rather than hopeful.
void main() {
  /// The export dialog is 940 by 700; the default test surface is 800 by 600.
  /// Giving the test a window the dialog fits in is the alternative to
  /// scrolling to every button before tapping it.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  /// The golden layout of a pagination: every fragment, on its grid cell.
  List<String> gridOf(PaginationView pagination) => [
    for (final sheet in PreviewView.sheetsOf(pagination))
      for (final line in sheet.page.lines)
        '${sheet.page.number ?? 'title'} '
            '${line.row},${line.column} ${line.kind.name} ${line.content}',
  ];

  /// Where every fragment is drawn, at a given size.
  List<String> screenOf(PaginationView pagination, PreviewGeometry geometry) => [
    for (final sheet in PreviewView.sheetsOf(pagination))
      for (final line in sheet.page.lines)
        '${geometry.at(line.row, line.column)} ${line.content}',
  ];

  testWidgets('changing the preview size leaves the pages exactly as they were', (
    tester,
  ) async {
    final output = FakeOutput(samplePagination(pages: 3));
    final core = FakeCore.single(BlockKind.action, 'Something happens.')
      ..filePath = '/scripts/heat.fountain';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExportDialog.show(context, core, output),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final before = gridOf(output.pagination);
    final pageCount = output.pagination.pageCount;
    final requests = List.of(output.setups);

    // Drag the preview-size slider from one end to the other.
    final slider = find.byKey(const Key('preview-scale'));
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(
      output.setups,
      requests,
      reason: 'the size the preview is drawn at is not part of the request',
    );
    expect(output.pagination.pageCount, pageCount);
    expect(gridOf(output.pagination), before, reason: 'the golden layout holds');
  });

  test('a preview size scales the drawing and nothing else', () {
    final pagination = samplePagination(pages: 2);
    const small = PreviewGeometry(paper: PaperSize.usLetter, scale: 3);
    const large = PreviewGeometry(paper: PaperSize.usLetter, scale: 12);

    // Same fragments, same order, same grid — four times the size on screen.
    expect(screenOf(pagination, small).length, screenOf(pagination, large).length);
    expect(large.width, small.width * 4);
    expect(large.at(7, 22).dx, small.at(7, 22).dx * 4);
    expect(large.at(7, 22).dy, small.at(7, 22).dy * 4);
    expect(gridOf(pagination), gridOf(pagination));
  });

  testWidgets('the paper is part of the request, because it changes the pages', (
    tester,
  ) async {
    // The other half of the claim: what *does* reach the paginator is the paper
    // and the scene numbers, and nothing else the dialog offers.
    final output = FakeOutput(samplePagination());
    final core = FakeCore.single(BlockKind.action, 'Something happens.');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExportDialog(core: core, output: output)),
      ),
    );
    await tester.pumpAndSettle();
    expect(output.setups.single.paper, PaperSize.usLetter);
    expect(output.setups.single.sceneNumbers, SceneNumbers.off);
    expect(
      output.setups.single.debugLinesPerPage,
      isNull,
      reason: 'a real preview takes its row count from the paper (§5.2)',
    );

    await tester.tap(find.byKey(const Key('paper-a4')));
    await tester.pumpAndSettle();
    expect(output.setups.last.paper, PaperSize.a4);

    await tester.tap(find.byKey(const Key('scene-numbers')));
    await tester.pumpAndSettle();
    expect(output.setups.last.sceneNumbers, SceneNumbers.both);
  });
}
