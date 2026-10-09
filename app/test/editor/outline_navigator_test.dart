import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/page_indicator.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

const _nodes = [
  NavigatorNode(block: 1, kind: BlockKind.synopsis, text: 'Opening', depth: 0),
  NavigatorNode(block: 2, kind: BlockKind.section, text: 'Act One', depth: 0),
  NavigatorNode(
    block: 3,
    kind: BlockKind.synopsis,
    text: 'Act summary',
    parent: 2,
    depth: 1,
  ),
  NavigatorNode(
    block: 4,
    kind: BlockKind.section,
    text: 'Sequence',
    parent: 2,
    depth: 1,
  ),
  NavigatorNode(
    block: 5,
    kind: BlockKind.sceneHeading,
    text: 'INT. HOUSE - DAY',
    parent: 4,
    depth: 2,
  ),
  NavigatorNode(
    block: 6,
    kind: BlockKind.synopsis,
    text: 'House summary',
    parent: 5,
    depth: 3,
  ),
  NavigatorNode(
    block: 7,
    kind: BlockKind.sceneHeading,
    text: 'EXT. STREET - NIGHT',
    parent: 4,
    depth: 2,
  ),
];
const _data = NavigatorView(
  outline: _nodes,
  scenes: [
    NavigatorScene(
      block: 5,
      prefix: 'INT.',
      location: 'HOUSE',
      timeOfDay: 'DAY',
    ),
    NavigatorScene(
      block: 7,
      prefix: 'EXT.',
      location: 'STREET',
      timeOfDay: 'NIGHT',
    ),
  ],
  characters: [],
);

List<BlockView> _blocks() => [
  for (final node in _nodes)
    BlockView(
      id: node.block,
      kind: node.kind,
      sectionLevel: node.kind == BlockKind.section ? node.depth + 1 : 0,
      text: node.text,
      forced: false,
      dual: false,
      readOnly: false,
      inlineRuns: const [],
    ),
];

class _OutputCore extends FakeCore implements ScreenplayOutput {
  _OutputCore() : super(_blocks()) {
    navigatorData = _data;
  }

  final requests = <Completer<PaginationOutcome>>[];

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) {
    final request = Completer<PaginationOutcome>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<SaveOutcome> exportPdf(
    String path, {
    required PageSetup setup,
    bool overwrite = false,
  }) async => SaveOutcome.saved(path: path, bytes: 0, backup: null);
}

PaginationView _pagination(int page, int length, {int revision = 42}) {
  final base = samplePagination(titlePage: false);
  return PaginationView(
    revision: revision,
    generation: revision,
    pageCount: base.pageCount,
    pages: base.pages,
    stats: base.stats,
    scenes: [ScenePaginationView(block: 5, page: page, lengthEighths: length)],
  );
}

Future<EditorController> _editor(
  WidgetTester tester,
  FakeCore core, {
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = EditorController(core);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(controller: controller, navigatorVisible: true),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets(
    'structure-only outlines remain usable and keyboard jumps to synopsis',
    (tester) async {
      final core = FakeCore(_blocks().take(4).toList())
        ..navigatorData = NavigatorView(
          outline: _nodes.take(4).toList(),
          scenes: const [],
          characters: const [],
        );
      final controller = await _editor(tester, core);
      expect(find.text('No scenes'), findsNothing);
      expect(find.text('Opening'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('navigator filter')),
        'act summary',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.selection.focus.block, 3);
    },
  );

  testWidgets('empty script has no invented outline or page metadata', (
    tester,
  ) async {
    await _editor(tester, FakeCore.single(BlockKind.action, ''));
    expect(find.text('No scenes'), findsOneWidget);
    expect(find.textContaining('length …'), findsNothing);
  });

  for (final width in [800.0, 1100.0]) {
    testWidgets(
      'all outline nodes jump in sidebar or drawer at $width',
      (tester) async {
        final core = FakeCore(_blocks())..navigatorData = _data;
        final controller = await _editor(tester, core, width: width);
        final source = controller.source;
        for (final node in _nodes) {
          if (width < 900) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await tester.pumpAndSettle();
          }
          final key = node.kind == BlockKind.sceneHeading
              ? 'navigator scene ${node.block}'
              : 'navigator outline ${node.block}';
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(
            controller.selection.focus,
            DocPosition(block: node.block, offsetUtf16: 0),
          );
          expect(controller.source, source);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'hierarchy keeps source order, accessible headers and filter context',
    (tester) async {
      final core = FakeCore(_blocks())..navigatorData = _data;
      final controller = await _editor(tester, core);
      double y(int block) => tester
          .getTopLeft(
            find.byKey(
              ValueKey(
                block == 5 || block == 7
                    ? 'navigator scene $block'
                    : 'navigator outline $block',
              ),
            ),
          )
          .dy;
      for (var block = 1; block < 7; block++) {
        expect(y(block), lessThan(y(block + 1)));
      }
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('outline semantics 2')))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      semantics.dispose();

      await tester.enterText(
        find.byKey(const ValueKey('navigator filter')),
        'street',
      );
      await tester.pump();
      expect(find.text('Act One'), findsOneWidget);
      expect(find.text('Sequence'), findsOneWidget);
      expect(find.text('HOUSE'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        controller.selection.focus.block,
        7,
        reason: 'quick search activates the matching scene, not context',
      );
      await tester.enterText(
        find.byKey(const ValueKey('navigator filter')),
        'act one',
      );
      await tester.pump();
      expect(find.text('Act summary'), findsOneWidget);
      expect(find.text('House summary'), findsOneWidget);
      expect(find.text('HOUSE'), findsOneWidget);
      expect(find.text('STREET'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('navigator filter')),
        'house summary',
      );
      await tester.pump();
      expect(
        find.text('HOUSE'),
        findsOneWidget,
        reason: 'the scene remains as context',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        controller.selection.focus.block,
        6,
        reason: 'activate the matching synopsis, not its scene ancestor',
      );
    },
  );

  testWidgets(
    'scene menu reorders scenes among outline rows and undo restores source',
    (tester) async {
      final core = FakeCore(_blocks())..navigatorData = _data;
      final controller = await _editor(tester, core);
      final source = controller.source;
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('navigator scene 7'))),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move scene up'));
      await tester.pumpAndSettle();
      expect(controller.blocks.map((block) => block.id), [1, 2, 3, 4, 7, 5, 6]);
      expect(
        tester.getTopLeft(find.text('STREET')).dy,
        lessThan(tester.getTopLeft(find.text('HOUSE')).dy),
      );
      controller.undo();
      await tester.pump(const Duration(milliseconds: 130));
      await tester.pump();
      expect(controller.source, source);
    },
  );

  testWidgets(
    'current pagination is displayed, then immediately becomes pending on edit',
    (tester) async {
      final core = _OutputCore();
      final controller = await _editor(tester, core);
      expect(find.text('p. … · length …'), findsNWidgets(2));
      core.requests[0].complete(
        PaginationOutcome.current(pagination: _pagination(3, 11)),
      );
      await tester.pump();
      expect(find.text('p. 3 · 11/8 p'), findsOneWidget);
      controller.jumpToBlock(5);
      controller.insertText('X');
      await tester.pump();
      expect(find.text('p. 3 · 11/8 p'), findsNothing);
      expect(find.text('p. … · length …'), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 130));
      core.requests.last.complete(
        PaginationOutcome.current(pagination: _pagination(4, 12)),
      );
      await tester.pump();
      expect(find.text('p. 4 · 12/8 p'), findsOneWidget);
    },
  );

  testWidgets(
    'title commits invalidate in-flight metadata without a body edit',
    (tester) async {
      final core = _OutputCore();
      final controller = await _editor(tester, core);
      final epoch = controller.documentRevision;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title page…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('title-field-Title')),
        'New cover',
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      core.requests[0].complete(
        PaginationOutcome.current(pagination: _pagination(9, 99)),
      );
      await tester.pump();
      expect(controller.documentRevision, epoch);
      expect(find.text('p. 9 · 99/8 p'), findsNothing);
      expect(find.text('p. … · length …'), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 130));
      core.requests.last.complete(
        PaginationOutcome.current(pagination: _pagination(1, 4)),
      );
      await tester.pump();
      expect(find.text('p. 1 · 4/8 p'), findsOneWidget);
    },
  );

  test(
    'pagination rejects late current answers and stale undo revisions',
    () async {
      final core = _OutputCore();
      final controller = EditorController(core);
      final indicator = PageIndicator(
        controller: controller,
        output: core,
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
      final old = indicator.refresh();
      controller.jumpToBlock(5);
      controller.insertText('X');
      final newer = indicator.refresh();
      core.requests[1].complete(
        PaginationOutcome.current(pagination: _pagination(4, 12)),
      );
      await newer;
      expect(indicator.scenePagination[5]!.page, 4);
      core.requests[0].complete(
        PaginationOutcome.current(pagination: _pagination(1, 1)),
      );
      await old;
      expect(indicator.scenePagination[5]!.page, 4);
      controller.undo();
      expect(indicator.scenePagination, isEmpty);
      final stale = indicator.refresh();
      core.requests[2].complete(
        PaginationOutcome.stale(pagination: _pagination(9, 99, revision: 0)),
      );
      await stale;
      expect(indicator.scenePagination, isEmpty);
      final restored = indicator.refresh();
      core.requests[3].complete(
        PaginationOutcome.current(pagination: _pagination(2, 8, revision: 0)),
      );
      await restored;
      expect(indicator.scenePagination[5]!.page, 2);
    },
  );
}
