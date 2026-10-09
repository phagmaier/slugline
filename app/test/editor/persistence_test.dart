import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/app.dart' show scriptToRestore;
import 'package:slugline/core/core.dart' show RecoveryOffer, ScriptView;
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/library/backups_dialog.dart'
    show formatBytes, formatTimestamp;
import 'package:slugline/library/recovery_dialog.dart';
import 'package:slugline/library/save_dialogs.dart';

import '../support/fake_core.dart';

/// The Dart half of §Phase 4: what the writer is told, and what they are asked.
///
/// The rules being checked here are §Phase 4's own words:
///
/// * a save failure is "a blocking, explicit error … never a silent toast";
/// * read-only, full disk and permission-denied each get "a distinct message and
///   a Save As escape hatch";
/// * a file that changed on disk while unmodified reloads silently, and one that
///   changed with unsaved edits prompts;
/// * §10's "must never silently discard unsaved changes".
void main() {
  Future<void> pumpWith(
    WidgetTester tester,
    Widget Function(BuildContext) body,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: body)),
      ),
    );
  }

  group('save failures', () {
    for (final (failure, expected) in const [
      (SaveFailure.readOnly, 'read-only'),
      (SaveFailure.noSpace, 'disk is full'),
      (SaveFailure.permissionDenied, 'No permission'),
      (SaveFailure.noSuchDirectory, 'not there'),
    ]) {
      testWidgets('$failure says "$expected" and offers Export a copy', (
        tester,
      ) async {
        SaveFailureChoice? choice;
        await pumpWith(
          tester,
          (context) => TextButton(
            onPressed: () async {
              choice = await showSaveFailure(
                context,
                SaveOutcome.failed(
                      failure: failure,
                      path: '/scripts/heat.fountain',
                      message: 'os said no',
                    )
                    as SaveOutcome_Failed,
              );
            },
            child: const Text('save'),
          ),
        );
        await tester.tap(find.text('save'));
        await tester.pumpAndSettle();

        expect(find.textContaining(expected, findRichText: true), findsWidgets);
        expect(
          find.text('/scripts/heat.fountain'),
          findsNothing,
          reason: 'the path is in a sentence, not on its own',
        );
        expect(find.textContaining('/scripts/heat.fountain'), findsWidgets);

        // Every failure offers the escape hatch.
        expect(find.text('Export a copy…'), findsOneWidget);
        await tester.tap(find.text('Export a copy…'));
        await tester.pumpAndSettle();
        expect(choice, SaveFailureChoice.exportCopy);
      });
    }

    testWidgets('the dialog cannot be dismissed by clicking away', (
      tester,
    ) async {
      // §Phase 4: "blocking, explicit … never a silent toast". Clicking the
      // barrier away would be the silent version.
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () => showSaveFailure(
            context,
            SaveOutcome.failed(
                  failure: SaveFailure.noSpace,
                  path: '/x.fountain',
                  message: 'ENOSPC',
                )
                as SaveOutcome_Failed,
          ),
          child: const Text('save'),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'still there');
    });

    testWidgets('the writer is told their work is not lost', (tester) async {
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () => showSaveFailure(
            context,
            SaveOutcome.failed(
                  failure: SaveFailure.noSpace,
                  path: '/x.fountain',
                  message: 'ENOSPC',
                )
                as SaveOutcome_Failed,
          ),
          child: const Text('save'),
        ),
      );
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing has been lost'), findsOneWidget);
    });
  });

  group('Save As never replaces a file without asking', () {
    /// Starts a real [saveWithDialogs] with the chooser replaced by `answers` —
    /// one destination per time the writer is put in front of it, `null` for a
    /// chooser they closed — and hands back what it eventually said.
    ///
    /// The save is still running when this returns: it is waiting on whatever
    /// dialog the core's refusal put up, which is the thing under test.
    Future<ValueGetter<SaveOutcome?>> saveAsking(
      WidgetTester tester,
      FakeCore core,
      List<String?> answers,
    ) async {
      SaveOutcome? outcome;
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () async {
            outcome = await saveWithDialogs(
              context,
              core,
              forcePath: true,
              chooseFile:
                  (
                    context, {
                    required directory,
                    required suggestedName,
                  }) async => answers.removeAt(0),
            );
          },
          child: const Text('save as'),
        ),
      );
      await tester.tap(find.text('save as'));
      await tester.pumpAndSettle();
      return () => outcome;
    }

    testWidgets('an occupied destination is confirmed before it is replaced', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..existingFiles.add('/scripts/other.fountain');

      final saved = await saveAsking(tester, core, ['/scripts/other.fountain']);

      // The first attempt was refused by the core, and the writer is being
      // asked rather than told.
      expect(core.exportAttempts, [('/scripts/other.fountain', false)]);
      expect(find.text('There is already a file there'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(
        core.exportAttempts,
        [('/scripts/other.fountain', false), ('/scripts/other.fountain', true)],
        reason: 'replacing is the same call said again, explicitly',
      );
      expect(saved(), isA<SaveOutcome_Saved>());
      expect(core.filePath, '/scripts/heat.fountain');
    });

    testWidgets('declining goes back to the chooser and writes nothing', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..onDisk = 'John enters.\n'
        ..existingFiles.add('/scripts/other.fountain');

      final saved = await saveAsking(tester, core, [
        '/scripts/other.fountain',
        '/scripts/new.fountain',
      ]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No `overwrite: true` was ever sent, so the occupied file was never
      // written — and the writer ended up somewhere else rather than out of
      // Save As altogether.
      expect(core.exportAttempts, [
        ('/scripts/other.fountain', false),
        ('/scripts/new.fountain', false),
      ]);
      expect(core.saves, isEmpty);
      expect(core.exportAttempts.last, ('/scripts/new.fountain', false));
      expect(saved(), isA<SaveOutcome_Saved>());
      expect(core.filePath, '/scripts/heat.fountain');
    });

    testWidgets('closing the chooser at the replace question saves nothing', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..existingFiles.add('/scripts/other.fountain');

      final saved = await saveAsking(tester, core, [
        '/scripts/other.fountain',
        null,
      ]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(core.saves, isEmpty);
      expect(core.filePath, '/scripts/heat.fountain');
      expect(
        (saved() as SaveOutcome_Failed).failure,
        SaveFailure.noPath,
        reason: 'a closed chooser is not a failure to report',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a script open here is refused, and not by asking', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..existingFiles.add('/scripts/open.fountain')
        ..openScripts.add('/scripts/open.fountain');

      final saved = await saveAsking(tester, core, ['/scripts/open.fountain']);

      // Not the replace question: this one has no yes.
      expect(find.text('There is already a file there'), findsNothing);
      expect(find.text('That script is open here'), findsOneWidget);
      expect(
        find.textContaining('Save that script rather than writing this one'),
        findsOneWidget,
      );

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(core.saves, isEmpty);
      expect(core.filePath, '/scripts/heat.fountain');
      expect((saved() as SaveOutcome_Failed).failure, SaveFailure.scriptIsOpen);
    });
  });

  group('unsaved changes', () {
    testWidgets('closing with unsaved work asks, and Cancel means cancel', (
      tester,
    ) async {
      UnsavedChoice? choice;
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () async {
            choice = await showUnsavedChanges(context, 'heat.fountain');
          },
          child: const Text('close'),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes to heat.fountain?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(choice, UnsavedChoice.cancel);
    });

    testWidgets('discarding is a deliberate choice, not the default', (
      tester,
    ) async {
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () => showUnsavedChanges(context, 'heat.fountain'),
          child: const Text('close'),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      // Save is the filled button; Discard is not.
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Discard'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
    });
  });

  group('external modification', () {
    testWidgets('an unmodified document reloads without asking', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..onDisk = 'Somebody else wrote this.\n';
      // Not dirty: nothing has been typed.
      final (dirty, differs) = (await core.externalChange())!;
      expect(dirty, isFalse);
      expect(differs, isTrue);
      // The page's rule: not dirty and different → reload, no dialog. The dialog
      // is only reached in the other case, which the next test covers.
    });

    testWidgets('a modified document prompts with three answers', (
      tester,
    ) async {
      ExternalChangeChoice? choice;
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () async {
            choice = await showExternalChange(
              context,
              '/scripts/heat.fountain',
            );
          },
          child: const Text('changed'),
        ),
      );
      await tester.tap(find.text('changed'));
      await tester.pumpAndSettle();

      expect(find.text('Keep mine'), findsOneWidget);
      expect(find.text('Take theirs'), findsOneWidget);
      expect(find.text('Export a copy…'), findsOneWidget);
      // The one that loses work says so.
      expect(
        find.textContaining('discards your unsaved changes'),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();
      expect(choice, ExternalChangeChoice.keepMine);
    });

    /// A save the core refused because the file is not the one it last read
    /// must not put up the generic failure dialog: the core pushed the same
    /// `FileChangedOnDisk` the watcher would have, so the external-modification
    /// prompt — the one with the three answers that fit — is already coming.
    testWidgets(
      'a refusal over an external edit does not stack a second dialog',
      (tester) async {
        final core = FakeCore.single(BlockKind.action, 'John enters.')
          ..filePath = '/scripts/heat.fountain'
          ..refuseSaveWith = SaveFailure.changedOnDisk;
        core.apply(
          EditCommand.replaceText(
            block: 1,
            startUtf16: 0,
            endUtf16: 0,
            with_: 'a',
          ),
        );

        SaveOutcome? outcome;
        await pumpWith(
          tester,
          (context) => TextButton(
            onPressed: () async {
              outcome = await saveWithDialogs(context, core);
            },
            child: const Text('save'),
          ),
        );
        await tester.tap(find.text('save'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          (outcome as SaveOutcome_Failed).failure,
          SaveFailure.changedOnDisk,
          reason: 'and the caller is told, so the status line can say it',
        );
      },
    );

    /// "Keep mine leaves the file alone until you next save" — so the core is
    /// told the writer has seen this version of the file, and the next save is
    /// allowed to replace it. Without that the save path, which refuses a file
    /// it does not recognise, would refuse for ever and there would be no way
    /// to write the text the writer chose to keep.
    testWidgets('keeping mine tells the core the file has been decided about', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..onDisk = 'Somebody else wrote this.\n'
        ..refuseSaveWith = SaveFailure.changedOnDisk;
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'a',
        ),
      );
      expect((await core.save()) is SaveOutcome_Failed, isTrue);

      expect(await core.acceptDiskState(), isTrue);
      expect(core.diskStateAccepted, 1);
      expect(
        await core.save(),
        isA<SaveOutcome_Saved>(),
        reason: 'the decision is what lets the writer keep their text',
      );
    });
  });

  group('crash recovery', () {
    RecoveryOffer offer({
      int edits = 14,
      bool damaged = false,
      String script = '/scripts/heat.fountain',
      String? blocked,
    }) => RecoveryOffer(
      journal: '/state/journal/abc.log',
      script: script,
      title: script.isEmpty ? 'Untitled' : 'heat.fountain',
      edits: edits,
      damaged: damaged,
      blocked: blocked,
    );

    test('the summary is §Phase 4\'s "14 edits since last save"', () {
      expect(
        RecoveryDialog.summaryOf(offer()),
        '14 edits since the last save.',
      );
      expect(
        RecoveryDialog.summaryOf(offer(edits: 1)),
        '1 edit since the last save.',
      );
      expect(
        RecoveryDialog.summaryOf(offer(script: '')),
        '14 edits in a script never saved.',
      );
      expect(
        RecoveryDialog.summaryOf(offer(damaged: true)),
        contains('last keystroke was not written in full'),
      );
    });

    testWidgets(
      'Recover and Discard are both offered, and nothing is automatic',
      (tester) async {
        Map<String, RecoveryChoice>? chosen;
        await pumpWith(
          tester,
          (context) => TextButton(
            onPressed: () async {
              chosen = await RecoveryDialog.show(context, [offer()]);
            },
            child: const Text('start'),
          ),
        );
        await tester.tap(find.text('start'));
        await tester.pumpAndSettle();

        expect(find.textContaining('closed unexpectedly'), findsOneWidget);
        expect(
          find.textContaining('Nothing has been written to any of your files'),
          findsOneWidget,
        );
        expect(find.text('Recover'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);

        await tester.tap(find.text('Recover'));
        await tester.pumpAndSettle();
        expect(chosen, {'/state/journal/abc.log': RecoveryChoice.recover});
      },
    );

    testWidgets('closing the dialog decides nothing', (tester) async {
      // The safe answer. A journal left alone is offered again next launch; a
      // journal discarded is gone.
      Map<String, RecoveryChoice>? chosen;
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () async {
            chosen = await RecoveryDialog.show(context, [offer()]);
          },
          child: const Text('start'),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decide later'));
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);
    });

    testWidgets('an offer that cannot be taken says why and is not offered', (
      tester,
    ) async {
      await pumpWith(
        tester,
        (context) => TextButton(
          onPressed: () => RecoveryDialog.show(context, [
            offer(blocked: 'heat.fountain has changed since it was last open'),
          ]),
          child: const Text('start'),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('has changed since it was last open'),
        findsOneWidget,
      );
      final recover = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Recover'),
      );
      expect(recover.onPressed, isNull, reason: 'and it cannot be pressed');
    });

    // The other half of "closing the dialog decides nothing", and the one that
    // used to be false. Startup fell through to the session restore, which
    // reopened the very script the offer named — and a new session wants a
    // journal at exactly that name, which is where the offer's records went.
    group('the session restore and an undecided offer', () {
      ScriptView script(String path) => ScriptView(
        projectId: 'test-project',
        archived: false,
        id: path,
        path: path,
        title: path,
        modifiedMillis: 0,
        bytes: 0,
        pageCount: 0,
        missing: false,
        open: true,
        scrollRow: 0,
      );

      test('a script with a pending offer is not reopened', () {
        expect(
          scriptToRestore(
            session: [script('/scripts/heat.fountain')],
            offers: [offer()],
            resolved: const {},
          ),
          isNull,
          reason: 'the library is a better answer than an erased journal',
        );
      });

      test('a discarded offer frees its script again', () {
        final restored = scriptToRestore(
          session: [script('/scripts/heat.fountain')],
          offers: [offer()],
          resolved: const {'/state/journal/abc.log'},
        );
        expect(restored?.path, '/scripts/heat.fountain');
      });

      test('the next script in the session is restored instead', () {
        final restored = scriptToRestore(
          session: [
            script('/scripts/heat.fountain'),
            script('/scripts/b.fountain'),
          ],
          offers: [offer()],
          resolved: const {},
        );
        expect(restored?.path, '/scripts/b.fountain');
      });

      test('an untitled offer blocks nothing: it names no file', () {
        final restored = scriptToRestore(
          session: [script('/scripts/heat.fountain')],
          offers: [offer(script: '')],
          resolved: const {},
        );
        expect(restored?.path, '/scripts/heat.fountain');
      });
    });
  });

  group('the status line', () {
    testWidgets('says what would survive a crash right now', (tester) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain';
      final status = SaveStatus(core: core);

      expect(status.label, 'saved');
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'a',
        ),
      );
      expect(status.label, 'not saved · 1 edits recorded');

      await core.save();
      expect(status.label, 'saved');
    });

    testWidgets('a failure outranks an earlier success', (tester) async {
      final core = FakeCore.single(BlockKind.action, 'x')
        ..filePath = '/scripts/heat.fountain';
      final status = SaveStatus(core: core);
      status.record(await core.save());
      expect(status.isError, isFalse);

      core.refuseSaveWith = SaveFailure.noSpace;
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'a',
        ),
      );
      status.record(await core.save());
      expect(status.isError, isTrue);
      expect(status.label, contains('disk is full'));
    });

    testWidgets('a script that has never been saved says so', (tester) async {
      final core = FakeCore.single(BlockKind.action, 'x');
      expect(SaveStatus(core: core).label, 'never saved');
    });

    /// A session the core could not journal — an unwritable state directory, a
    /// journal name a pending recovery still holds — is unprotected from the
    /// moment it opens, with nothing typed and nothing to save. The warning
    /// used to appear only while there was unsaved text, so the writer heard
    /// about it after the risk started rather than before, and stopped hearing
    /// about it every time an autosave landed.
    testWidgets('a session that is not being recorded says so in every state', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'John enters.')
        ..filePath = '/scripts/heat.fountain'
        ..journalUnavailable = true;
      final status = SaveStatus(core: core);

      expect(status.label, 'saved · recovery record unavailable');
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'a',
        ),
      );
      expect(status.label, 'not saved · recovery record unavailable');

      await core.save();
      expect(
        status.label,
        'saved · recovery record unavailable',
        reason: 'the save covered the last few seconds, not the next ones',
      );

      final untitled = FakeCore.single(BlockKind.action, 'x')
        ..journalUnavailable = true;
      expect(
        SaveStatus(core: untitled).label,
        'never saved · recovery record unavailable',
      );
    });

    /// The degraded-safety warning. A machine with no inotify left cannot be
    /// told when another program writes the script, and the loss used to be
    /// completely invisible: the watcher's construction went into an `.ok()`
    /// and every `watch` call into a `let _`. Saving is still safe — the core
    /// checks the file before replacing it — so the wording is about warning
    /// rather than about danger.
    testWidgets(
      'a session whose file cannot be watched says so in every state',
      (tester) async {
        final core = FakeCore.single(BlockKind.action, 'John enters.')
          ..filePath = '/scripts/heat.fountain'
          ..watchUnavailable = true;
        final status = SaveStatus(core: core);

        expect(status.label, 'saved · external changes not watched');
        core.apply(
          EditCommand.replaceText(
            block: 1,
            startUtf16: 0,
            endUtf16: 0,
            with_: 'a',
          ),
        );
        expect(
          status.label,
          'not saved · 1 edits recorded · external changes not watched',
        );

        await core.save();
        expect(status.label, 'saved · external changes not watched');

        // And it survives a failure, which outranks everything else it says.
        core.refuseSaveWith = SaveFailure.noSpace;
        core.apply(
          EditCommand.replaceText(
            block: 1,
            startUtf16: 0,
            endUtf16: 0,
            with_: 'b',
          ),
        );
        status.record(await core.save());
        expect(status.label, contains('disk is full'));
        expect(status.label, contains('external changes not watched'));
      },
    );

    /// The refusal the save path answers with when the file is not the one it
    /// last read. Short, because the modal that is already on its way says the
    /// rest — and present, because a writer who dismisses that modal without
    /// deciding must still see that their text is not on disk.
    testWidgets('a save refused over an external edit says why', (
      tester,
    ) async {
      final core = FakeCore.single(BlockKind.action, 'x')
        ..filePath = '/scripts/heat.fountain'
        ..refuseSaveWith = SaveFailure.changedOnDisk;
      final status = SaveStatus(core: core);
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'a',
        ),
      );

      status.record(await core.save());
      expect(status.isError, isTrue);
      expect(status.label, 'not saved · the file changed on disk');
    });
  });

  group('formatting', () {
    test('sizes are human', () {
      expect(formatBytes(512), '512 bytes');
      expect(formatBytes(2048), '2.0 kB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('today and yesterday are named rather than dated', () {
      final now = DateTime.now();
      expect(
        formatTimestamp(now.millisecondsSinceEpoch),
        startsWith('Today at '),
      );
      final yesterday = now.subtract(const Duration(days: 1));
      expect(
        formatTimestamp(yesterday.millisecondsSinceEpoch),
        startsWith('Yesterday at '),
      );
      final old = DateTime(2024, 3, 7, 9, 5);
      expect(
        formatTimestamp(old.millisecondsSinceEpoch),
        '2024-03-07 at 09:05',
      );
    });
  });
}
