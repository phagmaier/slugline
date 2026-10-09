import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/preview/preview_view.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

/// W11: the preview keeps its page when its sheets change size.
///
/// A scroll offset is a number of pixels, and how many pixels a sheet is tall
/// is exactly what a new preview size or a new paper changes. Left alone, the
/// offset that shows page 47 at 58% shows page 28 at actual size.
///
/// What this holds is the half that is Dart's: where the list is scrolled to.
/// The pages are a pagination built by hand, the same one whatever is asked
/// for — which sheet a line is on is Rust's answer and is not re-derived here.
const _pages = 60;
const _page = 47;

final _sheets = find.byKey(const Key('preview-sheets'));

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _sheets, matching: find.byType(Scrollable)),
    )
    .position;

PreviewView _preview(WidgetTester tester) =>
    tester.widget<PreviewView>(find.byType(PreviewView));

/// The distance from one sheet's top to the next: a sheet and the gap under it.
double _pitch(WidgetTester tester) {
  final preview = _preview(tester);
  return PreviewGeometry(paper: preview.paper, scale: preview.scale).height +
      24;
}

/// The first sheet with any of itself in the pane, and how far below the top
/// of the pane its top edge is — negative once it has been scrolled past.
(int, double) _top(WidgetTester tester) {
  final pane = tester.getRect(_sheets);
  for (var number = 1; number <= _pages; number++) {
    final sheet = find.byKey(Key('preview-page-$number'));
    if (sheet.evaluate().isEmpty) continue;
    final rect = tester.getRect(sheet);
    if (rect.bottom <= pane.top) continue;
    return (number, ((rect.top - pane.top) * 1000).round() / 1000);
  }
  fail('no sheet is in the pane');
}

Future<FakeOutput> _open(
  WidgetTester tester, {
  int page = _page,
  bool titlePage = false,
}) async {
  final output = FakeOutput(
    samplePagination(pages: _pages, titlePage: titlePage),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExportDialog(
          core: FakeCore.single(BlockKind.action, 'Something happens.'),
          output: output,
          // `samplePagination` prints block `10 × n` at the top of page n.
          opensAt: PreviewAnchor(block: page * 10, sourceLine: 0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return output;
}

/// The page setup is a list of its own beside the preview, and builds only
/// what shows: a control is scrolled to before it is pressed — [by] a negative
/// step for one above where the list has been left.
Future<void> _tap(WidgetTester tester, String key, {double by = 120}) async {
  await _reach(tester, key, by: by);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, String key, {double by = 120}) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    by,
    scrollable: find
        .descendant(
          of: find.byType(ExportDialog),
          matching: find.byType(Scrollable),
        )
        .last,
  );
  await tester.pumpAndSettle();
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

  testWidgets('a preview opened on page 47 stays on it at every size and on '
      'either paper', (tester) async {
    await _open(tester);
    expect(find.text('58%'), findsOneWidget, reason: 'the default size');
    expect(_top(tester), (_page, 24.0));

    // Each from where the last one left it, as a reader would press them.
    final seen = <String, (int, double)>{};
    await _tap(tester, 'preview-actual-size');
    expect(_preview(tester).scale, 7.2);
    seen['Actual size'] = _top(tester);

    await _tap(tester, 'preview-fit-width');
    expect(_preview(tester).scale, isNot(anyOf(4.2, 7.2)));
    seen['Fit width'] = _top(tester);

    await _tap(tester, 'paper-a4', by: -120);
    expect(_preview(tester).paper, PaperSize.a4);
    seen['A4'] = _top(tester);

    // The page it opened on, where page 1 sits in a preview opened at the top.
    expect(seen, {
      'Actual size': (_page, 24.0),
      'Fit width': (_page, 24.0),
      'A4': (_page, 24.0),
    });
  });

  testWidgets('a place part of the way down a sheet is kept as that, and a '
      'fresh pagination alone moves nothing', (tester) async {
    final output = await _open(tester);
    // Half a sheet on from where it opened: the middle of page 47 at the top.
    _scroll(tester).jumpTo((_page - 0.5) * _pitch(tester));
    await tester.pump();
    final sheets = _scroll(tester).pixels / _pitch(tester);

    // In the frame the size changes, with nothing left to settle.
    await _reach(tester, 'preview-actual-size');
    await tester.tap(find.byKey(const Key('preview-actual-size')));
    await tester.pump();
    expect(_preview(tester).scale, 7.2);
    expect(_scroll(tester).pixels / _pitch(tester), closeTo(sheets, 1e-9));
    expect(_top(tester).$1, _page);
    expect(_scroll(tester).isScrollingNotifier.value, isFalse);

    // The same sheets again from the paginator: not a reason to move at all.
    final pixels = _scroll(tester).pixels;
    final asked = output.setups.length;
    await _tap(tester, 'scene-numbers', by: -120);
    await tester.tap(find.text('Both margins').last);
    await tester.pumpAndSettle();
    expect(output.setups.length, asked + 1);
    expect(_scroll(tester).pixels, pixels);
  });

  testWidgets('dragging the size slider never leaves the sheet, with a title '
      'page above it', (tester) async {
    await _open(tester, titlePage: true);
    expect(find.byKey(const Key('preview-title-page')), findsNothing);
    expect(_top(tester), (_page, 24.0));

    await _reach(tester, 'preview-scale');
    final slider = find.byKey(const Key('preview-scale'));
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(_preview(tester).scale, lessThan(4.2));
    expect(_top(tester), (_page, 24.0));

    await tester.drag(slider, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(_preview(tester).scale, greaterThan(7.2));
    expect(_top(tester), (_page, 24.0));
  });

  testWidgets('smaller sheets on the last page end where the list ends, at '
      'rest', (tester) async {
    await _open(tester, page: _pages);
    expect(_scroll(tester).pixels, _scroll(tester).maxScrollExtent);

    // Fewer pixels of list below the pane than the same sheets down would
    // need: the end of the list, reached in that frame and not sprung back to.
    await _reach(tester, 'preview-scale');
    await tester.drag(
      find.byKey(const Key('preview-scale')),
      const Offset(-200, 0),
    );
    await tester.pump();
    final scroll = _scroll(tester);
    expect(_preview(tester).scale, lessThan(4.2));
    expect(scroll.maxScrollExtent, greaterThan(0));
    expect(scroll.pixels, scroll.maxScrollExtent);
    expect(scroll.isScrollingNotifier.value, isFalse);
    expect(find.byKey(const Key('preview-page-$_pages')), findsOneWidget);
  });
}
