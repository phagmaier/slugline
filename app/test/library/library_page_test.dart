import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/identity.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/theme.dart';

import '../support/pending_file_choice.dart';

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
  bool missing = false,
}) => ScriptView(
  id: id,
  path: path,
  title: title,
  modifiedMillis: modifiedMillis,
  bytes: 1024,
  pageCount: pageCount,
  missing: missing,
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
  testWidgets('the library filters and opens a script without a pointer', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final opened = await _pump(tester, [
      _script(
        id: 'heat',
        title: 'Heat',
        path: '/scripts/heat.fountain',
        modifiedMillis: now,
      ),
      _script(
        id: 'night',
        title: 'Night',
        path: '/scripts/night.fountain',
        modifiedMillis: now - 1,
      ),
    ]);
    final field = tester.widget<TextField>(
      find.byKey(const Key('library-search')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('library-search')), 'night');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['/scripts/night.fountain']);
  });

  testWidgets('Ctrl+N works when the library is empty', (tester) async {
    final choice = pendingFileChoice(tester);
    final opened = await _pump(tester, []);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    choice.complete('/scripts/first.fountain');
    await tester.pumpAndSettle();
    expect(opened, ['/scripts/first.fountain']);
  });

  testWidgets('keyboard selection scrolls through a long library', (
    tester,
  ) async {
    final opened = await _pump(
      tester,
      List.generate(
        30,
        (n) => _script(
          id: '$n',
          path: '/scripts/$n.fountain',
          title: 'Script $n',
          modifiedMillis: 100 - n,
        ),
      ),
    );
    for (var n = 0; n < 29; n++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const ValueKey('library-row-29')).hitTestable(),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['/scripts/29.fountain']);
  });

  testWidgets('Enter leaves a missing script alone', (tester) async {
    final opened = await _pump(tester, [
      _script(id: 'gone', modifiedMillis: 2, missing: true),
      _script(
        id: 'available',
        modifiedMillis: 1,
        path: '/scripts/available.fountain',
      ),
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['/scripts/available.fountain']);
  });

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
    // Below the search/sort row, which sits above the list.
    expect(tester.getTopLeft(find.text('RECENT')).dy, lessThan(200));
    expect(find.text(applicationName), findsNothing);

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

  testWidgets('search filters the list by title or path', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _pump(tester, [
      _script(
        id: 'heat',
        path: '/scripts/heat.fountain',
        title: 'Heat',
        modifiedMillis: now,
      ),
      _script(
        id: 'night',
        path: '/scripts/city-night.fountain',
        title: 'City Night',
        modifiedMillis: now,
      ),
    ]);
    expect(find.byKey(const ValueKey('library-row-heat')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-row-night')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      'heat',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('library-row-heat')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-row-night')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      'city-night',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('library-row-night')),
      findsOneWidget,
      reason: 'the path is searched too',
    );

    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      'nothing called this',
    );
    await tester.pump();
    expect(find.byKey(const Key('library-no-matches')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-clear-search')));
    await tester.pump();
    expect(find.byKey(const ValueKey('library-row-heat')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-row-night')), findsOneWidget);
  });

  testWidgets('sort orders the list by title or page count', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _pump(tester, [
      _script(
        id: 'b',
        path: '/scripts/b.fountain',
        title: 'Zulu',
        modifiedMillis: now,
        pageCount: 40,
      ),
      _script(
        id: 'a',
        path: '/scripts/a.fountain',
        title: 'Alpha',
        modifiedMillis: now,
        pageCount: 5,
      ),
    ]);

    List<String> order() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('library-content')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  (widget.data == 'Zulu' || widget.data == 'Alpha'),
            ),
          ),
        )
        .map((text) => text.data!)
        .toList();

    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    expect(order(), ['Alpha', 'Zulu']);
    expect(find.text('BY TITLE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page count').last);
    await tester.pumpAndSettle();
    // Page order disagrees with title order by construction: most pages first.
    expect(order(), ['Zulu', 'Alpha']);
    expect(find.text('BY PAGES'), findsOneWidget);
  });
}
