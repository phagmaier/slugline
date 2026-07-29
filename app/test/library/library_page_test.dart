import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/theme.dart';

class _FakeLibraryCore implements LibraryCore {
  _FakeLibraryCore(this.scripts);

  final List<ScriptView> scripts;

  @override
  Future<List<ScriptView>> library() async => scripts;

  @override
  Future<ScriptView?> duplicate(String id) => throw UnimplementedError();

  @override
  Future<bool> forget(String id, {required bool deleteFile}) =>
      throw UnimplementedError();

  @override
  Future<SaveOutcome> rename(String id, String newPath) =>
      throw UnimplementedError();
}

ScriptView _script({
  String id = 'heat',
  String path = '/home/writer/projects/features/heat/heat.fountain',
  String title = 'Heat',
  required int modifiedMillis,
  int pageCount = 12,
}) => ScriptView(
  id: id,
  path: path,
  title: title,
  modifiedMillis: modifiedMillis,
  bytes: 1024,
  pageCount: pageCount,
  missing: false,
  open: false,
  scrollRow: 0,
);

Future<List<String>> _pump(
  WidgetTester tester,
  List<ScriptView> scripts,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);

  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: sluglineTheme(Brightness.light),
      home: LibraryPage(
        core: _FakeLibraryCore(scripts),
        onOpen: (path) async => opened.add(path),
      ),
    ),
  );
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('recent scripts use a centred, full-row opening target', (
    tester,
  ) async {
    final modified = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    final script = _script(modifiedMillis: modified);
    final opened = await _pump(tester, [script]);

    final content = find.byKey(const ValueKey('library-content'));
    expect(tester.getSize(content).width, 960);
    expect(tester.getCenter(content).dx, 600);

    final header = tester.widget<Text>(find.text('RECENT'));
    expect(header.style?.fontSize, 10);
    expect(header.style?.color, SluglineColors.light.textTertiary);
    expect(tester.getTopLeft(find.text('RECENT')).dy, greaterThan(120));

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('library-title-heat')),
    );
    expect(title.style?.fontSize, 15);
    expect(find.text('2 hours ago'), findsOneWidget);
    expect(find.text('12 pages'), findsOneWidget);

    final path = tester.widget<Text>(
      find.byKey(const ValueKey('library-path-heat')),
    );
    expect(path.overflow, TextOverflow.ellipsis);
    expect(path.style?.color, SluglineColors.light.textTertiary);

    final row = find.byKey(const ValueKey('library-row-heat'));
    final ink = tester.widget<InkWell>(row);
    expect(ink.hoverColor, SluglineColors.light.surfaceRaised);
    expect(ink.mouseCursor, SystemMouseCursors.click);

    await tester.tap(row);
    await tester.pump();
    expect(opened, [script.path]);
  });

  testWidgets('empty library makes New script the focal action', (
    tester,
  ) async {
    await _pump(tester, const []);

    final icon = find.byKey(const ValueKey('library-empty-icon'));
    expect(icon, findsOneWidget);
    expect(tester.getCenter(icon).dx, 600);
    expect(
      find.text('No scripts yet. Create a new script to start writing.'),
      findsOneWidget,
    );

    expect(
      find.widgetWithText(FilledButton, 'New script'),
      findsNWidgets(2),
      reason: 'the app bar and empty state both use the primary action',
    );
    expect(
      find.widgetWithText(TextButton, 'Open'),
      findsNWidgets(2),
      reason: 'Open stays visually secondary in both action groups',
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
