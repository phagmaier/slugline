import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/library/quick_open_dialog.dart';
import 'package:slugline/theme.dart';

import '../support/pending_file_choice.dart';

class _Library implements LibraryCore {
  _Library(this.scripts);
  final Future<List<ScriptView>> scripts;
  @override
  Future<List<ScriptView>> library() => scripts;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ScriptView _script(int n, {bool missing = false}) => ScriptView(
  projectId: 'test-project',
  archived: false,
  id: '$n',
  path: '/scripts/file-$n.fountain',
  title: 'Script $n',
  modifiedMillis: 100 - n,
  bytes: 10,
  pageCount: 1,
  missing: missing,
  open: false,
  scrollRow: 0,
);

void main() {
  testWidgets(
    'typing a path filters out missing files; arrows choose a script',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sluglineTheme(Brightness.light),
          home: Builder(builder: (_) => const SizedBox()),
        ),
      );
      final context = tester.element(find.byType(SizedBox).last);
      final chosen = QuickOpenDialog.show(
        context,
        _Library(
          Future.value([_script(0, missing: true), _script(1), _script(2)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-open-0')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await chosen, '/scripts/file-2.fountain');
    },
  );

  testWidgets('the highlight scrolls to Browse after a long recent list', (
    tester,
  ) async {
    final choice = pendingFileChoice(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: sluglineTheme(Brightness.light),
        home: Builder(builder: (_) => const SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox).last);
    final chosen = QuickOpenDialog.show(
      context,
      _Library(Future.value(List.generate(30, _script))),
    );
    await tester.pumpAndSettle();
    // Up wraps from the first script to Browse and scrolls it into view.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('quick-open-browse')).hitTestable(),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    choice.complete(null);
    await tester.pumpAndSettle();
    expect(await chosen, isNull);
  });

  testWidgets('a failed library still offers Browse', (tester) async {
    final choice = pendingFileChoice(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: sluglineTheme(Brightness.light),
        home: Builder(builder: (_) => const SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox).last);
    final failure = Completer<List<ScriptView>>();
    final chosen = QuickOpenDialog.show(context, _Library(failure.future));
    await tester.pump();
    failure.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load recent scripts. Import a screenplay copy.'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    choice.complete('/scripts/browsed.fountain');
    await tester.pumpAndSettle();
    expect(await chosen, '/scripts/browsed.fountain');
  });

  testWidgets('Escape during a library load leaves no late state update', (
    tester,
  ) async {
    final scripts = Completer<List<ScriptView>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: sluglineTheme(Brightness.light),
        home: Builder(builder: (_) => const SizedBox()),
      ),
    );
    final context = tester.element(find.byType(SizedBox).last);
    final chosen = QuickOpenDialog.show(context, _Library(scripts.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await chosen, isNull);
    scripts.complete([_script(1)]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
