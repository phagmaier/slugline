import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/library/backups_dialog.dart';
import 'package:slugline/theme.dart';

import '../support/fake_core.dart';
import '../support/pending_file_choice.dart';

const _old = 'Title: Earlier draft\n\nINT. ROOM - DAY\n\nOld words.\n';
const _backup = BackupView(
  path: '/backups/old.fountain',
  writtenMillis: 1000,
  bytes: 55,
);

class _Backups extends FakeCore {
  _Backups()
    : super(FakeCore.single(BlockKind.action, 'Current words').blocks(0, 1)) {
    filePath = '/scripts/current.fountain';
  }

  Future<BackupReadOutcome> read = Future.value(
    const BackupReadOutcome.read(source: _old),
  );
  SaveOutcome copyOutcome = const SaveOutcome.saved(
    path: '/scripts/copy.fountain',
    bytes: 55,
    backup: null,
  );
  int copies = 0;

  @override
  Future<List<BackupView>> backups() async => [_backup];

  @override
  Future<BackupReadOutcome> readBackup(String backupPath) => read;

  @override
  Future<SaveOutcome> restoreBackup(String backupPath) async =>
      const SaveOutcome.failed(
        failure: SaveFailure.io,
        path: '/scripts/current.fountain',
        message: 'Version disappeared',
      );

  @override
  Future<SaveOutcome> copyBackup(String source, String path) async {
    copies++;
    return copyOutcome;
  }
}

Future<void> _show(
  WidgetTester tester,
  _Backups core, {
  Future<void> Function(String)? openCopy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: sluglineTheme(Brightness.light),
      home: const Scaffold(body: SizedBox()),
    ),
  );
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          BackupsDialog(core: core, openCopy: openCopy ?? (_) async {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'closing after viewing or failed restore retains text and caret',
    (tester) async {
      final core = _Backups();
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      const position = DocPosition(block: 1, offsetUtf16: 7);
      const selection = DocSelection(anchor: position, focus: position);
      controller.setSelection(selection);
      await tester.pumpWidget(
        MaterialApp(
          theme: sluglineTheme(Brightness.light),
          home: EditorPage(controller: controller, onClosed: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous versions…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(controller.selection, selection);
      expect(controller.blocks.single.text, 'Current words');
      await tester.tap(find.byKey(const ValueKey('editor overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous versions…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('Version disappeared'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(controller.selection, selection);
      expect(controller.blocks.single.text, 'Current words');
      expect(core.commands, isEmpty);
    },
  );

  testWidgets('view is selectable but not editable; Back returns to the list', (
    tester,
  ) async {
    final core = _Backups();
    await _show(tester, core);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text(_old), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).readOnly,
      isTrue,
    );
    await tester.tap(find.text(_old));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(find.text(_old), findsOneWidget);
    expect(core.blocks(0, 1).single.text, 'Current words');
    expect(core.commands, isEmpty);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('View'), findsOneWidget);
    expect(find.text(_old), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BackupsDialog), findsNothing);
  });

  testWidgets(
    'an unavailable backup stays in the list with a retryable error',
    (tester) async {
      final core = _Backups()
        ..read = Future.value(
          const BackupReadOutcome.failed(message: 'Version disappeared'),
        );
      await _show(tester, core);
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Version disappeared'), findsOneWidget);
      expect(find.text('Open as copy…'), findsNothing);
      core.read = Future.value(const BackupReadOutcome.read(source: _old));
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text(_old), findsOneWidget);
      expect(find.text('Version disappeared'), findsNothing);
    },
  );

  testWidgets(
    'canceling the copy chooser leaves the version view and script alone',
    (tester) async {
      final core = _Backups();
      var launched = false;
      final choice = pendingFileChoice(tester);
      await _show(
        tester,
        core,
        openCopy: (_) async {
          launched = true;
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open as copy…'));
      await tester.pump();
      choice.complete(null);
      await tester.pumpAndSettle();
      expect(find.text(_old), findsOneWidget);
      expect(core.copies, 0);
      expect(launched, isFalse);
      expect(core.path, '/scripts/current.fountain');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'a refused destination is reported without launching or closing the view',
    (tester) async {
      final core = _Backups()
        ..copyOutcome = const SaveOutcome.failed(
          failure: SaveFailure.alreadyExists,
          path: '/scripts/copy.fountain',
          message: 'Choose a new filename',
        );
      var launched = false;
      final choice = pendingFileChoice(tester);
      await _show(
        tester,
        core,
        openCopy: (_) async {
          launched = true;
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open as copy…'));
      await tester.pump();
      choice.complete('/scripts/copy.fountain');
      await tester.pumpAndSettle();
      expect(find.text('Choose a new filename'), findsOneWidget);
      expect(find.text(_old), findsOneWidget);
      expect(launched, isFalse);
      expect(find.text('Open as copy…'), findsOneWidget);
    },
  );

  testWidgets(
    'launch failure keeps the saved path; retry opens without writing again',
    (tester) async {
      final core = _Backups();
      var launches = 0;
      final choice = pendingFileChoice(tester);
      await _show(
        tester,
        core,
        openCopy: (path) async {
          launches++;
          if (launches == 1) {
            throw ProcessException('slugline', [path], 'Launch refused');
          }
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open as copy…'));
      await tester.pump();
      choice.complete('/scripts/copy.fountain');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The copy is saved at /scripts/copy.fountain'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open saved copy'));
      await tester.pumpAndSettle();
      expect(core.copies, 1);
      expect(launches, 2);
      expect(find.byType(BackupsDialog), findsNothing);
      expect(core.path, '/scripts/current.fountain');
    },
  );

  testWidgets('Escape cannot abandon a version read in flight', (tester) async {
    final read = Completer<BackupReadOutcome>();
    final core = _Backups()..read = read.future;
    await _show(tester, core);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(BackupsDialog), findsOneWidget);
    read.complete(const BackupReadOutcome.read(source: _old));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BackupsDialog), findsNothing);
  });
}
