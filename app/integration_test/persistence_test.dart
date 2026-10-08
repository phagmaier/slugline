// Phase 4's proofs, against the real `libslugline_bridge.so` and real files.
//
//     flutter test integration_test/persistence_test.dart -d linux
//
// `cargo test` covers the mechanisms — the atomic write sequence, the journal
// format, the retention policy, the kill test — where they are, in Rust. The
// widget tests in `test/editor/` cover the dialogs and the autosave clock, in
// Dart. What only this can prove is that the whole chain agrees: a keystroke in
// the editor reaches a file at a path the user chose, through the bridge, and
// comes back when the file is opened again.
//
// Everything here happens under a temporary XDG root, so the run cannot see or
// write the library index, journals or backups of the person running it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/library/backups_dialog.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/src/rust/api/files.dart' as files;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory scripts;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('slugline-phase4-');
    scripts = await Directory('${root.path}/scripts').create(recursive: true);
    await Core.init(
      configDir: '${root.path}/config',
      dataDir: '${root.path}/data',
      stateDir: '${root.path}/state',
    );
  });

  tearDownAll(() async {
    await Core.instance.shutdown();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String path(String name) => '${scripts.path}/$name';

  Future<EditorController> openEditor(
    WidgetTester tester,
    DocumentCore core,
  ) async {
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorSurface(controller: controller)),
      ),
    );
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    return controller;
  }

  /// Pumps for `duration` in real time, so that anything the core pushes over
  /// the event stream has somewhere to land. `pumpAndSettle` cannot serve: a
  /// filesystem event owes the framework no frame, and the interesting answer is
  /// usually that nothing arrives at all.
  Future<void> settleFor(WidgetTester tester, Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// The same, until `ready` or five seconds — generous, because a wrong answer
  /// here should mean a broken watcher rather than a busy machine.
  Future<void> settleUntil(WidgetTester tester, bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a new script is a real file, and typing into it saves', (
    tester,
  ) async {
    final file = path('new.fountain');
    final handle = await files.libraryCreate(path: file);
    expect(handle, isNotNull, reason: 'create writes the file immediately');
    expect(File(file).existsSync(), isTrue);

    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    final controller = await openEditor(tester, core);

    controller.insertText('INT. HOUSE - DAY');
    await tester.pump();
    expect(core.dirty, isTrue);

    final outcome = await core.save();
    expect(outcome, isA<SaveOutcome_Saved>());
    expect(core.dirty, isFalse);
    expect(File(file).readAsStringSync(), contains('INT. HOUSE - DAY'));
    final entry = (await files.libraryList()).singleWhere(
      (script) => script.path == file,
    );
    expect(
      entry.pageCount,
      1,
      reason: 'a successful save paginates the saved snapshot for the library',
    );
  });

  testWidgets(
    'a platform burst is journalled before an immediate save and reopens exactly',
    (tester) async {
      const source =
          'INT. INSTALLATION CHECK - DAY\n\nInstalled command ready.\n';
      const burst = ' Verified through installed association.';
      final file = path('platform-burst.fountain');
      File(file).writeAsStringSync(source);
      final core = (await Core.instance.openDocument(file))!;
      addTearDown(core.close);
      final controller = await openEditor(tester, core);
      controller.moveToDocumentEdge(start: false);
      final surface = tester.state<EditorSurfaceState>(
        find.byType(EditorSurface),
      );
      var text = controller.focusedBlock.text;
      for (final character in burst.split('')) {
        text += character;
        surface.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
      }
      final expected = '${source.trimRight()}$burst\n';
      expect(controller.source, expected);
      expect(core.source(), expected);
      expect(core.journalState.$1, burst.length);
      expect(core.journalState.$2, isFalse);
      expect(File(file).readAsStringSync(), source);
      expect(await core.save(), isA<SaveOutcome_Saved>());
      expect(File(file).readAsStringSync(), expected);
      expect(core.dirty, isFalse);

      controller.undo();
      expect(controller.source, source);
      controller.redo();
      expect(controller.source, expected);
      await tester.pumpWidget(const SizedBox.shrink());
      core.close();
      final reopened = (await Core.instance.openDocument(file))!;
      addTearDown(reopened.close);
      expect(reopened.source(), expected);
    },
  );

  testWidgets('a save writes atomically and leaves no temp file behind', (
    tester,
  ) async {
    final file = path('atomic.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final handle = await files.libraryOpen(path: file);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);

    final controller = await openEditor(tester, core);
    controller.insertText('X');
    await tester.pump();
    await core.save();

    final leftovers = scripts
        .listSync()
        .map((entry) => entry.path)
        .where((name) => name.contains('.tmp-'))
        .toList();
    expect(
      leftovers,
      isEmpty,
      reason: 'the temp file is renamed, never orphaned',
    );
  });

  /// F9, end to end: the two operations that used to be one. Export writes a
  /// copy and the writer carries on where they were; Save As takes the session
  /// with it (ADR 0029). `cargo test` proves what happens to the journal and the
  /// library; what this adds is that the generated binding carries the
  /// distinction — including the `overwrite` argument a Phase 7 dialog has to
  /// pass to replace anything.
  testWidgets('an export writes a copy and Save As moves the session', (
    tester,
  ) async {
    final file = path('export.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final handle = await files.libraryOpen(path: file);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);

    final controller = await openEditor(tester, core);
    controller.insertText('X');
    await tester.pump();
    final typed = core.source();

    final copy = path('export-copy.fountain');
    expect(await core.exportFountain(copy), isA<SaveOutcome_Saved>());
    expect(File(copy).readAsStringSync(), typed);
    expect(core.path, file, reason: 'the session did not follow the copy');
    expect(core.dirty, isTrue, reason: 'a copy is not where this script lives');
    expect(
      File(file).readAsStringSync(),
      'INT. HOUSE - DAY\n',
      reason: 'and the script itself is still unsaved',
    );

    // The copy exists now, so exporting there again has to be told to replace it.
    final refused = await core.exportFountain(copy);
    expect(refused, isA<SaveOutcome_Failed>());
    expect((refused as SaveOutcome_Failed).failure, SaveFailure.alreadyExists);
    expect(
      await core.exportFountain(copy, overwrite: true),
      isA<SaveOutcome_Saved>(),
    );

    // The script being edited is never a destination, however firmly asked.
    final onto = await core.exportFountain(file, overwrite: true);
    expect((onto as SaveOutcome_Failed).failure, SaveFailure.scriptIsOpen);

    // Save As answers the same two refusals, and for the same reasons: it
    // reaches the same atomic replacement through the same chooser.
    final occupied = path('export-occupied.fountain');
    File(occupied).writeAsStringSync('Somebody else.\n');
    final wouldReplace = await core.saveAs(occupied);
    expect(
      (wouldReplace as SaveOutcome_Failed).failure,
      SaveFailure.alreadyExists,
    );
    expect(
      File(occupied).readAsStringSync(),
      'Somebody else.\n',
      reason: 'a refused Save As writes nothing',
    );
    expect(core.path, file, reason: 'and moves nothing either');

    // Save As, by contrast to an export, moves the session onto the file it
    // writes — and an unoccupied destination needs no confirmation at all.
    final moved = path('export-moved.fountain');
    expect(await core.saveAs(moved), isA<SaveOutcome_Saved>());
    expect(core.path, moved);
    expect(core.dirty, isFalse);
    expect(File(moved).readAsStringSync(), typed);

    // Saving again onto the file this session now *is* is a save, not a
    // replacement, so it is not asked about.
    expect(await core.saveAs(moved), isA<SaveOutcome_Saved>());
  });

  testWidgets('what was typed comes back when the file is opened again', (
    tester,
  ) async {
    final file = path('roundtrip.fountain');
    final created = await files.libraryCreate(path: file);
    final core = RustDocumentCore.of(created!);
    final controller = await openEditor(tester, core);

    controller.insertText('INT. HOUSE - DAY');
    controller.splitBlock();
    await tester.pump();
    controller.insertText('John enters. café 日本 🎬');
    await tester.pump();
    final written = core.source();
    await core.save();
    core.close();

    final reopened = await files.libraryOpen(path: file);
    final second = RustDocumentCore.of(reopened!);
    addTearDown(second.close);
    expect(
      second.source(),
      written,
      reason: 'byte for byte, non-ASCII and all (§3.2)',
    );
  });

  testWidgets(
    'a read-only file is refused with the reason, and stays as it was',
    (tester) async {
      final file = path('readonly.fountain');
      File(file).writeAsStringSync('INT. HOUSE - DAY\n');
      final handle = await files.libraryOpen(path: file);
      final core = RustDocumentCore.of(handle!);
      addTearDown(core.close);

      final controller = await openEditor(tester, core);
      controller.insertText('X');
      await tester.pump();

      await Process.run('chmod', ['444', file]);
      final outcome = await core.save();
      expect(outcome, isA<SaveOutcome_Failed>());
      expect((outcome as SaveOutcome_Failed).failure, SaveFailure.readOnly);
      expect(
        outcome.path,
        file,
        reason: 'the path the writer chose, not the temp one',
      );
      expect(File(file).readAsStringSync(), 'INT. HOUSE - DAY\n');
      expect(
        core.dirty,
        isTrue,
        reason: 'nothing was written, so nothing is saved',
      );

      await Process.run('chmod', ['644', file]);
    },
  );

  testWidgets('a save leaves a backup that can be restored', (tester) async {
    final file = path('backups.fountain');
    final created = await files.libraryCreate(path: file);
    final core = RustDocumentCore.of(created!);
    addTearDown(core.close);
    final controller = await openEditor(tester, core);

    controller.insertText('FIRST DRAFT');
    await tester.pump();
    await core.save();

    final first = await core.backups();
    expect(first, isNotEmpty, reason: 'every save writes one (§Phase 4)');

    controller.insertText(' — SECOND');
    await tester.pump();
    await core.save();
    expect(File(file).readAsStringSync(), contains('SECOND'));

    // Restoring rolls the file back — and writes the current state first, so
    // there is now one more backup than there was.
    final before = (await core.backups()).length;
    final outcome = await core.restoreBackup(first.first.path);
    expect(outcome, isA<SaveOutcome_Saved>());
    expect(File(file).readAsStringSync(), isNot(contains('SECOND')));
    expect(
      (await core.backups()).length,
      greaterThan(before),
      reason:
          '§Phase 4: restoring writes the current state to a new backup first',
    );
  });

  for (final fromView in [false, true]) {
    testWidgets('restore refreshes the editor, fromView=$fromView', (
      tester,
    ) async {
      final file = path('restore-refresh-$fromView.fountain');
      const earlier = 'Earlier words.\n';
      File(file).writeAsStringSync(earlier);
      final handle = await files.libraryOpen(path: file);
      final core = RustDocumentCore.of(handle!);
      addTearDown(core.close);
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      controller.insertText('Current draft has more words. ');
      controller.splitBlock();
      controller.insertText('Another paragraph.');
      final current = core.source();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(controller: controller, onClosed: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('editor overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous versions…'));
      await tester.pumpAndSettle();
      expect(find.text('Restore'), findsOneWidget);
      if (fromView) {
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();
        expect(find.text(earlier), findsOneWidget);
      }
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.byType(BackupsDialog), findsNothing);
      expect(File(file).readAsStringSync(), earlier);
      expect(controller.blocks.single.text, 'Earlier words.');
      expect(controller.selection.focus.block, controller.blocks.single.id);
      expect(controller.selection.focus.offsetUtf16, 0);
      expect(core.dirty, isFalse);
      final preserved = await core.backups();
      expect(
        preserved.any(
          (backup) => File(backup.path).readAsStringSync() == current,
        ),
        isTrue,
        reason: 'the replaced unsaved draft remains recoverable',
      );
      await settleUntil(
        tester,
        () => find.textContaining('2 words').evaluate().isNotEmpty,
      );
      expect(find.textContaining('2 words'), findsOneWidget);
      controller.insertText('Edited ');
      await tester.pump();
      expect(controller.lastRejection, isNull);
      expect(core.source(), 'Edited Earlier words.\n');
      expect(controller.blocks.single.text, 'Edited Earlier words.');
      expect(await core.save(), isA<SaveOutcome_Saved>());
      expect(File(file).readAsStringSync(), 'Edited Earlier words.\n');
    });
  }

  testWidgets('the journal grows with typing and is cleared by a save', (
    tester,
  ) async {
    final file = path('journal.fountain');
    final created = await files.libraryCreate(path: file);
    final core = RustDocumentCore.of(created!);
    addTearDown(core.close);
    final controller = await openEditor(tester, core);

    for (final letter in 'FADE IN:'.split('')) {
      controller.insertText(letter);
      await tester.pump();
    }
    final (recorded, broken) = core.journalState;
    expect(broken, isFalse);
    expect(
      recorded,
      greaterThanOrEqualTo(8),
      reason: 'every keystroke is on disk before the next one arrives',
    );

    await core.save();
    expect(core.journalState.$1, 0, reason: 'the file holds it all now');
  });

  testWidgets(
    'a file changed on disk is noticed, with the two facts that decide',
    (tester) async {
      final file = path('external.fountain');
      File(file).writeAsStringSync('INT. HOUSE - DAY\n');
      final handle = await files.libraryOpen(path: file);
      final core = RustDocumentCore.of(handle!);
      addTearDown(core.close);
      await openEditor(tester, core);

      expect(await core.externalChange(), (false, false), reason: 'in step');

      File(file).writeAsStringSync('EXT. STREET - NIGHT\n');
      expect(
        await core.externalChange(),
        (false, true),
        reason: 'unmodified here and different there — reload silently',
      );

      await core.reload();
      expect(core.source(), 'EXT. STREET - NIGHT\n');
      expect(await core.externalChange(), (false, false));
    },
  );

  // The other half of the same rule, and the one the watcher cannot be trusted
  // with: what happens if nobody acts on the event. A machine out of inotify
  // descriptors never gets one at all, and this is what stands there instead —
  // proved here through the real bridge, real files and a real save.
  testWidgets('a save does not replace an edit made by something else', (
    tester,
  ) async {
    final file = path('conflict.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final handle = await files.libraryOpen(path: file);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    final controller = await openEditor(tester, core);

    controller.insertText('X');
    await tester.pump();
    expect(await core.save(), isA<SaveOutcome_Saved>());

    File(file).writeAsStringSync('EXT. STREET - NIGHT\n');
    controller.insertText('Y');
    await tester.pump();

    final refused = await core.save();
    expect(
      (refused as SaveOutcome_Failed).failure,
      SaveFailure.changedOnDisk,
      reason: "the save replaced another program's edit",
    );
    expect(File(file).readAsStringSync(), 'EXT. STREET - NIGHT\n');
    expect(core.dirty, isTrue, reason: 'and the writer keeps their text');

    // "Keep mine": the writer has seen it and chosen their own version.
    expect(await core.acceptDiskState(), isTrue);
    expect(await core.save(), isA<SaveOutcome_Saved>());
    expect(File(file).readAsStringSync(), core.source());
  });

  // F4, end to end and against real inotify: nothing else in this repository can
  // prove it. The watcher event that a save causes is delivered by `notify`'s
  // own thread, minutes of code away from the save that caused it, and the whole
  // defect is that the two were never connected. The Rust tests prove the
  // correlation; this proves that the event a real rename really produces is the
  // one it correlates with.
  //
  // The two halves belong in one test. Without the second, a machine with no
  // inotify would pass the first by never reporting anything at all.
  testWidgets('our own save is not reported as somebody else writing the file', (
    tester,
  ) async {
    final file = path('own-save.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final handle = await files.libraryOpen(path: file);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    final controller = await openEditor(tester, core);

    final reported = <String>[];
    final watching = Core.instance.events.listen((event) {
      if (event case CoreEvent_FileChangedOnDisk(
        :final path,
      ) when path == file) {
        reported.add(path);
      }
    });
    addTearDown(watching.cancel);

    controller.insertText('X');
    await tester.pump();
    expect(await core.save(), isA<SaveOutcome_Saved>());

    // The keystroke that turns the echo into a modal: it lands between our
    // rename and the event about it, so the check that follows finds the
    // document dirty and the file different — which is what
    // `handleExternalChange` shows the "Something else has written to this file"
    // dialog for.
    controller.insertText('Y');
    await tester.pump();
    await settleFor(tester, const Duration(seconds: 2));

    expect(
      reported,
      isEmpty,
      reason: 'the app was told another program had written its own save',
    );
    expect(core.dirty, isTrue, reason: 'and the keystroke after it survived');
    expect(core.source(), contains('Y'));

    // A genuine write by something else still arrives, which is the property
    // suppression must not buy at any price.
    File(file).writeAsStringSync('EXT. STREET - NIGHT\n');
    await settleUntil(tester, () => reported.isNotEmpty);
    expect(
      reported,
      isNotEmpty,
      reason: 'suppression swallowed a real external change',
    );
    expect(await core.externalChange(), (
      true,
      true,
    ), reason: 'and it is a real one');
  });

  testWidgets(
    'the library lists what has been opened, and remembers a session',
    (tester) async {
      final file = path('library.fountain');
      File(file).writeAsStringSync('INT. HOUSE - DAY\n');
      final handle = await files.libraryOpen(path: file);
      final core = RustDocumentCore.of(handle!);

      final listed = await Core.instance.library();
      final entry = listed.firstWhere((script) => script.path == file);
      expect(entry.title, 'library');
      expect(entry.missing, isFalse);
      expect(entry.bytes, 17);
      expect(entry.open, isTrue);

      core.setScrollRow(42);
      final session = await Core.instance.sessionToRestore();
      final restored = session.firstWhere((script) => script.path == file);
      expect(restored.scrollRow, 42);
      core.close();
    },
  );

  testWidgets('session restore applies the parked row to the editor viewport', (
    tester,
  ) async {
    final file = path('scroll-restore.fountain');
    File(file).writeAsStringSync(
      [for (var i = 1; i <= 100; i++) 'Action line $i.\n\n'].join(),
    );
    final handle = await files.libraryOpen(path: file);
    expect(handle, isNotNull);
    files.docSetScroll(handle: handle!, row: 42);

    // Reopen through the session restore path to prove the parked row
    // survives, then drive the editor directly instead of through SluglineApp's
    // async startup — that flow's complexity makes the scroll timing fragile
    // under pumpAndSettle.
    final session = await Core.instance.sessionToRestore();
    final restored = session.firstWhere((script) => script.path == file);
    final reopened = await files.libraryOpen(path: file);
    expect(reopened, isNotNull);
    final core = RustDocumentCore.of(reopened!);
    addTearDown(core.close);
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorSurface(
            controller: controller,
            initialScrollRow: restored.scrollRow,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(EditorSurface), findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(EditorSurface),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(
      position.pixels,
      greaterThan(0),
      reason:
          'the editor should be scrolled past the top after session restore',
    );
  });

  testWidgets('a script whose file has gone is shown as missing, not dropped', (
    tester,
  ) async {
    final file = path('vanishing.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final handle = await files.libraryOpen(path: file);
    RustDocumentCore.of(handle!).close();

    File(file).deleteSync();
    final listed = await Core.instance.library();
    final entry = listed.firstWhere((script) => script.path == file);
    expect(entry.missing, isTrue);
  });

  testWidgets('the library index is a cache: deleting it costs only the list', (
    tester,
  ) async {
    final index = File('${root.path}/data/library.json');
    expect(index.existsSync(), isTrue);
    final file = path('cache.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');

    index.deleteSync();
    // The script still opens, by path, exactly as before.
    final handle = await files.libraryOpen(path: file);
    expect(handle, isNotNull);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    expect(core.source(), 'INT. HOUSE - DAY\n');
    // And the index rebuilds itself around what is opened afterwards.
    final listed = await Core.instance.library();
    expect(listed.any((script) => script.path == file), isTrue);
  });

  testWidgets('opening the same file twice is one document', (tester) async {
    final file = path('once.fountain');
    File(file).writeAsStringSync('INT. HOUSE - DAY\n');
    final first = await files.libraryOpen(path: file);
    final second = await files.libraryOpen(path: file);
    expect(
      first!.id,
      second!.id,
      reason: 'two undo histories over one file is a race',
    );
    RustDocumentCore.of(first).close();
  });

  testWidgets('preferences round-trip through the config directory', (
    tester,
  ) async {
    final defaults = Core.instance.preferences();
    expect(defaults.autosaveIdleMs, 2000);
    expect(defaults.autosaveIntervalMs, 30000);

    final changed = PreferencesView(
      autosaveEnabled: true,
      autocompleteEnabled: false,
      navigatorVisible: false,
      spellEnabled: defaults.spellEnabled,
      spellLanguage: defaults.spellLanguage,
      appearance: 'light',
      editorTextSize: 18,
      defaultPaper: 'a4',
      sceneNumbers: 'right',
      boldSceneHeadings: true,
      numberFirstPage: true,
      pdfFontPath: null,
      distractionFree: false,
      pageView: false,
      autosaveIdleMs: 750,
      autosaveIntervalMs: 15000,
      backupDir: null,
      backupKeepVersions: 4,
      backupKeepDays: 2,
    );
    expect(await Core.instance.setPreferences(changed), isTrue);
    expect(Core.instance.preferences().autosaveIdleMs, 750);
    expect(Core.instance.preferences().navigatorVisible, isFalse);
    expect(Core.instance.preferences().boldSceneHeadings, isTrue);
    expect(Core.instance.preferences().numberFirstPage, isTrue);
    expect(
      Core.instance.preferences().pageView,
      isFalse,
      reason: 'turning page view off is what has to survive; it is the default',
    );
    expect(
      File('${root.path}/config/prefs.json').existsSync(),
      isTrue,
      reason: 'human-readable on disk, by design (§2.6)',
    );
    await Core.instance.setPreferences(defaults);
  });
}
