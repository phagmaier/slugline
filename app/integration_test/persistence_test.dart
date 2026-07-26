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

import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
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
      if (event case CoreEvent_FileChangedOnDisk(:final path)
          when path == file) {
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
    expect(
      await core.externalChange(),
      (true, true),
      reason: 'and it is a real one',
    );
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

    await tester.pumpWidget(SluglineApp(core: Core.instance));
    await tester.pumpAndSettle();

    expect(find.byType(EditorSurface), findsOneWidget);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, 28 + 42 * 21);

    await tester.pumpWidget(const SizedBox.shrink());
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
      autosaveIdleMs: 750,
      autosaveIntervalMs: 15000,
      backupDir: null,
      backupKeepVersions: 4,
      backupKeepDays: 2,
    );
    expect(await Core.instance.setPreferences(changed), isTrue);
    expect(Core.instance.preferences().autosaveIdleMs, 750);
    expect(
      File('${root.path}/config/preferences.json').existsSync(),
      isTrue,
      reason: 'human-readable on disk, by design (§2.6)',
    );
    await Core.instance.setPreferences(defaults);
  });
}
