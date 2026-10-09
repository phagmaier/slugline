import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/library/quick_open_dialog.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/navigator_sidebar.dart';

import 'support/fake_core.dart';
import 'support/pending_file_choice.dart';

const _preferences = PreferencesView(
  autosaveEnabled: false,
  autocompleteEnabled: true,
  navigatorVisible: false,
  spellEnabled: false,
  spellLanguage: 'en_US',
  appearance: 'system',
  editorTextSize: 15,
  defaultPaper: 'us_letter',
  sceneNumbers: 'off',
  pdfFontPath: null,
  boldSceneHeadings: false,
  numberFirstPage: false,
  distractionFree: false,
  pageView: false,
  autosaveIdleMs: 2000,
  autosaveIntervalMs: 30000,
  backupDir: null,
  backupKeepVersions: 10,
  backupKeepDays: 7,
);

ScriptView _script(String id, int modified, {int scrollRow = 0}) => ScriptView(
  id: id,
  path: '/scripts/$id.fountain',
  title: id,
  modifiedMillis: modified,
  bytes: 10,
  pageCount: 1,
  missing: false,
  open: false,
  scrollRow: scrollRow,
);

class _AppCore implements Core {
  final opened = <FakeCore>[];
  final requests = <String>[];
  bool failOpen = false;
  String? documentText;
  final scrollRows = <String, int>{};
  List<ScriptView> restoredSession = [];
  Completer<void>? holdOpen;
  Completer<List<ScriptView>>? holdLibrary;
  PreferencesView currentPreferences = _preferences;
  final preferenceWrites = <PreferencesView>[];
  bool failPreferences = false;
  final importRequests = <String>[];
  FdxImportResult importResult = const FdxImportFailed(message: 'Invalid XML');
  Completer<void>? holdImport;
  final eventBus = StreamController<CoreEvent>.broadcast();

  @override
  Stream<CoreEvent> get events => eventBus.stream;
  @override
  PreferencesView preferences() => currentPreferences;
  @override
  Future<bool> setPreferences(PreferencesView value) async {
    preferenceWrites.add(value);
    if (failPreferences) return false;
    currentPreferences = value;
    return true;
  }

  @override
  SpellStatus spellStatus() => const SpellStatus(
    enabled: false,
    language: null,
    languages: [],
    message: 'Spell checking is off.',
  );
  @override
  Future<List<RecoveryOffer>> pendingRecoveries() async => [];
  @override
  Future<List<ScriptView>> sessionToRestore() async => restoredSession;
  @override
  Future<List<ScriptView>> library() async {
    if (holdLibrary case final held?) return held.future;
    return [
      _script('alpha', 2, scrollRow: scrollRows['alpha'] ?? 0),
      _script('beta', 1, scrollRow: scrollRows['beta'] ?? 0),
    ];
  }

  /// One entry per shutdown: how many opens were still unanswered at it.
  final shutdowns = <int>[];
  int _opening = 0;

  /// One entry per shutdown: the scripts the core still held open at it.
  final openAtShutdown = <List<String?>>[];

  /// How often the session was written down without a shutdown.
  int parks = 0;

  @override
  Future<void> shutdown() async {
    shutdowns.add(_opening);
    openAtShutdown.add([
      for (final script in opened)
        if (script.closes == 0) script.filePath,
    ]);
  }

  @override
  Future<void> parkSession() async => parks += 1;

  @override
  Future<DocumentCore?> openDocument(String path) async {
    requests.add(path);
    _opening += 1;
    try {
      await holdOpen?.future;
    } finally {
      _opening -= 1;
    }
    if (failOpen) return null;
    final core =
        FakeCore.single(BlockKind.action, documentText ?? 'Text from $path.')
          ..eventHandle = opened.length + 1
          ..filePath = path;
    core.onDisk = core.source();
    opened.add(core);
    return core;
  }

  @override
  Future<FdxImportResult> importFdx(String path) async {
    importRequests.add(path);
    await holdImport?.future;
    return importResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<_AppCore> _pump(WidgetTester tester, {bool open = true}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
  final core = _AppCore();
  addTearDown(core.eventBus.close);
  await tester.pumpWidget(SluglineApp(core: core));
  await tester.pumpAndSettle();
  if (open) await _key(tester, LogicalKeyboardKey.enter);
  return core;
}

EditorPage _editor(WidgetTester tester) =>
    tester.widget<EditorPage>(find.byType(EditorPage));

Future<void> _chooseBeta(WidgetTester tester) async {
  await _key(tester, LogicalKeyboardKey.keyO, control: true);
  await tester.enterText(find.byKey(const Key('quick-open-search')), 'beta');
  await _key(tester, LogicalKeyboardKey.enter);
}

Future<void> _runPalette(WidgetTester tester, String label) async {
  await _key(tester, LogicalKeyboardKey.keyK, control: true);
  await tester.enterText(
    find.widgetWithText(TextField, 'Element or command'),
    label,
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.descendant(
        of: find.byType(CommandPalette),
        matching: find.byType(ListView),
      ),
      matching: find.text(label),
    ),
    findsOneWidget,
  );
  await _key(tester, LogicalKeyboardKey.enter);
  expect(find.byType(CommandPalette), findsNothing);
}

void main() {
  testWidgets('library and quick open restore each script at its saved row', (
    tester,
  ) async {
    final core = await _pump(tester, open: false);
    core.documentText = List.generate(200, (i) => 'Action line $i.').join('\n');
    core.scrollRows.addAll({'alpha': 42, 'beta': 68});

    void expectRow(int row) {
      expect(core.opened.last.scrollRow, row);
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(EditorSurface),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable && widget.axis == Axis.vertical,
              ),
            ),
          )
          .position;
      expect(position.pixels, greaterThan(0));
    }

    await _key(tester, LogicalKeyboardKey.enter);
    expectRow(42);
    await _chooseBeta(tester);
    expectRow(68);
  });

  testWidgets('a saved row beyond the end clamps to the shortened script', (
    tester,
  ) async {
    final core = await _pump(tester, open: false);
    core.scrollRows['alpha'] = 999;
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_editor(tester).initialScrollRow, 999);
    expect(core.opened.single.scrollRow, 0);
  });

  testWidgets('an explicit session row of zero overrides the library row', (
    tester,
  ) async {
    final core = _AppCore()
      ..documentText = List.generate(200, (i) => 'Action line $i.').join('\n')
      ..restoredSession = [_script('alpha', 2)];
    core.scrollRows['alpha'] = 42;
    addTearDown(core.eventBus.close);
    await tester.pumpWidget(SluglineApp(core: core));
    await tester.pumpAndSettle();
    expect(core.opened.single.scrollRow, 0);
    expect(_editor(tester).initialScrollRow, 0);
  });

  for (final quit in [false, true]) {
    testWidgets(
      '${quit ? 'quitting' : 'unmounting'} during the saved-row lookup adopts nothing',
      (tester) async {
        final core = await _pump(tester, open: false);
        final lookup = core.holdLibrary = Completer<List<ScriptView>>();
        await _key(tester, LogicalKeyboardKey.enter);
        expect(core.opened, hasLength(1));
        expect(find.byType(EditorPage), findsNothing);
        if (quit) {
          final exit = tester.binding.handleRequestAppExit();
          await tester.pumpAndSettle();
          expect(await exit, AppExitResponse.exit);
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        lookup.complete([_script('alpha', 2, scrollRow: 42)]);
        await tester.pumpAndSettle();
        expect(core.opened.single.closes, 1);
        expect(find.byType(EditorPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [640.0, 1200.0]) {
    testWidgets(
      'palette navigator actions work at width $width and keep the draft',
      (tester) async {
        final core = await _pump(tester);
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        final controller = _editor(tester).controller;
        final source = controller.source;
        await _runPalette(tester, 'Show navigator');
        expect(find.byType(NavigatorSidebar), findsOneWidget);
        if (width >= 900) {
          await _runPalette(tester, 'Hide navigator');
          expect(find.byType(NavigatorSidebar), findsNothing);
          expect(core.preferenceWrites.map((p) => p.navigatorVisible), [
            true,
            false,
          ]);
        } else {
          // Ctrl+K also works from the drawer's search field. Opening the palette
          // closes that temporary drawer without changing the docked preference.
          await _key(tester, LogicalKeyboardKey.keyJ, control: true);
          await _key(tester, LogicalKeyboardKey.keyK, control: true);
          expect(find.byType(CommandPalette), findsOneWidget);
          expect(find.byType(NavigatorSidebar), findsNothing);
          await tester.enterText(
            find.widgetWithText(TextField, 'Element or command'),
            'Keyboard shortcuts',
          );
          await _key(tester, LogicalKeyboardKey.enter);
          expect(find.byType(ShortcutsDialog), findsOneWidget);
          await _key(tester, LogicalKeyboardKey.escape);
          expect(core.preferenceWrites, isEmpty);
        }
        expect(controller.source, source);
        expect(controller.core.dirty, isFalse);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(controller.selection.focus.offsetUtf16, 1);
      },
    );
  }

  testWidgets(
    'palette view changes persist without changing the draft or output setup',
    (tester) async {
      const channel = MethodChannel('slugline/window');
      final fullscreen = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        fullscreen.add(call.arguments as bool);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final core = await _pump(tester);
      final controller = _editor(tester).controller;
      final source = controller.source;
      final selection = controller.selection;
      final setup = _editor(tester).initialPageSetup;
      await _runPalette(tester, 'Use page view');
      expect(_editor(tester).pageView, isTrue);
      expect(core.currentPreferences.pageView, isTrue);
      await _runPalette(tester, 'Use continuous view');
      expect(_editor(tester).pageView, isFalse);
      await _runPalette(tester, 'Increase text size');
      expect(_editor(tester).textSize, 16);
      await _runPalette(tester, 'Decrease text size');
      expect(_editor(tester).textSize, 15);
      await _runPalette(tester, 'Enter distraction-free mode');
      expect(_editor(tester).distractionFree, isTrue);
      await _runPalette(tester, 'Leave distraction-free mode');
      expect(_editor(tester).distractionFree, isFalse);
      expect(core.preferenceWrites, hasLength(6));
      expect(fullscreen, [true, false]);
      expect(controller.source, source);
      expect(controller.selection, selection);
      expect(controller.core.dirty, isFalse);
      expect(_editor(tester).initialPageSetup, setup);
      expect(
        core.currentPreferences.autosaveIdleMs,
        _preferences.autosaveIdleMs,
      );
      expect(
        core.currentPreferences.autosaveIntervalMs,
        _preferences.autosaveIntervalMs,
      );
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(
        controller.selection.focus.offsetUtf16,
        1,
        reason: 'typing focus returns to the script',
      );
    },
  );

  testWidgets(
    'a failed palette display preference keeps the saved view and reports failure',
    (tester) async {
      final core = await _pump(tester);
      core.failPreferences = true;
      await _runPalette(tester, 'Use page view');
      expect(_editor(tester).pageView, isFalse);
      expect(core.currentPreferences.pageView, isFalse);
      expect(
        find.text('The display preference could not be saved.'),
        findsOneWidget,
      );
    },
  );

  for (final entry in <(String, Type)>[
    ('Preferences…', PreferencesDialog),
    ('Keyboard shortcuts', ShortcutsDialog),
    ('Spell checking…', SpellDialog),
  ]) {
    testWidgets(
      'the palette opens ${entry.$1} and Escape returns to the draft',
      (tester) async {
        await _pump(tester);
        final controller = _editor(tester).controller;
        final source = controller.source;
        await _key(tester, LogicalKeyboardKey.arrowRight);
        final selection = controller.selection;
        await _runPalette(tester, entry.$1);
        expect(find.byType(entry.$2), findsOneWidget);
        await _key(tester, LogicalKeyboardKey.escape);
        expect(find.byType(entry.$2), findsNothing);
        expect(controller.source, source);
        expect(controller.selection, selection);
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(controller.selection.focus.offsetUtf16, 0);
      },
    );
  }

  testWidgets(
    'library to script to another script to new script needs no pointer',
    (tester) async {
      final choice = pendingFileChoice(tester);
      final core = await _pump(tester, open: false);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await _key(tester, LogicalKeyboardKey.arrowUp);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(core.requests, ['/scripts/alpha.fountain']);
      expect(_editor(tester).controller.core.path, '/scripts/alpha.fountain');
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await _chooseBeta(tester);
      expect(_editor(tester).controller.core.path, '/scripts/beta.fountain');
      expect(core.opened.first.closes, 1);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await _key(tester, LogicalKeyboardKey.keyN, control: true);
      expect(find.byType(QuickOpenDialog), findsNothing);
      choice.complete('/scripts/new.fountain');
      await tester.pumpAndSettle();
      expect(_editor(tester).controller.core.path, '/scripts/new.fountain');
      expect(core.opened[1].closes, 1);
      await _key(tester, LogicalKeyboardKey.keyW, control: true);
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(core.opened.last.closes, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('library-search')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );

  for (final key in [LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO]) {
    testWidgets(
      '${key.keyLabel} works in the library; cancellation leaves it open',
      (tester) async {
        final core = await _pump(tester, open: false);
        final choice = key == LogicalKeyboardKey.keyN
            ? pendingFileChoice(tester)
            : null;
        await _key(tester, key, control: true);
        if (choice != null) {
          choice.complete(null);
          await tester.pumpAndSettle();
        } else {
          await _key(tester, LogicalKeyboardKey.escape);
        }
        expect(core.requests, isEmpty);
        expect(find.byType(LibraryPage), findsOneWidget);
      },
    );
  }

  for (final key in [
    LogicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyW,
  ]) {
    testWidgets('${key.keyLabel} preserves unsaved text when cancelled', (
      tester,
    ) async {
      final core = await _pump(tester);
      final choice = key == LogicalKeyboardKey.keyN
          ? pendingFileChoice(tester)
          : null;
      final controller = _editor(tester).controller;
      controller.insertText('Unsaved words. ');
      final source = controller.source;
      await _key(tester, key, control: true);
      if (key == LogicalKeyboardKey.keyO) {
        await tester.enterText(
          find.byKey(const Key('quick-open-search')),
          'beta',
        );
        await _key(tester, LogicalKeyboardKey.enter);
      } else if (key == LogicalKeyboardKey.keyN) {
        choice!.complete('/scripts/new.fountain');
        await tester.pumpAndSettle();
      }
      expect(find.text('Save changes to alpha.fountain?'), findsOneWidget);
      // A second shortcut belongs to the modal, not to the editor below it.
      await _key(tester, LogicalKeyboardKey.keyO, control: true);
      expect(find.byType(QuickOpenDialog), findsNothing);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(_editor(tester).controller, same(controller));
      expect(controller.source, source);
      expect(controller.core.dirty, isTrue);
      expect(core.requests, ['/scripts/alpha.fountain']);
      expect(core.opened.single.closes, 0);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    });
  }

  for (final discard in [false, true]) {
    testWidgets(
      'switch after ${discard ? 'Discard' : 'Save'} uses confirmClose',
      (tester) async {
        final core = await _pump(tester);
        _editor(tester).controller.insertText('Latest draft. ');
        final source = core.opened.single.source();
        await _chooseBeta(tester);
        await tester.tap(
          find.widgetWithText(
            discard ? TextButton : FilledButton,
            discard ? 'Discard' : 'Save',
          ),
        );
        await tester.pumpAndSettle();
        expect(_editor(tester).controller.core.path, '/scripts/beta.fountain');
        expect(core.opened.first.closes, 1);
        if (!discard) expect(core.opened.first.onDisk, source);
      },
    );
  }

  testWidgets(
    'a failed save cancels Ctrl+W without closing the dirty session',
    (tester) async {
      final core = await _pump(tester);
      _editor(tester).controller.insertText('Still here. ');
      core.opened.single.refuseSaveWith = SaveFailure.noSpace;
      await _key(tester, LogicalKeyboardKey.keyW, control: true);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('The disk is full'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(core.opened.single.closes, 0);
      expect(core.opened.single.dirty, isTrue);
      expect(_editor(tester).controller.source, contains('Still here.'));
    },
  );

  testWidgets(
    'an edit during the confirmation save keeps the original session',
    (tester) async {
      final core = await _pump(tester);
      final controller = _editor(tester).controller;
      controller.insertText('Saved words. ');
      await _chooseBeta(tester);
      final write = Completer<void>();
      core.opened.single.holdWrites = write;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      controller.insertText('Later words. ');
      write.complete();
      await tester.pumpAndSettle();
      expect(_editor(tester).controller, same(controller));
      expect(controller.core.dirty, isTrue);
      expect(controller.source, contains('Later words.'));
      expect(core.requests, ['/scripts/alpha.fountain']);
      expect(core.opened.single.closes, 0);
    },
  );

  testWidgets(
    'a quit during the startup open waits for it and adopts nothing',
    (tester) async {
      final core = _AppCore()..holdOpen = Completer<void>();
      addTearDown(core.eventBus.close);
      await tester.pumpWidget(
        SluglineApp(core: core, initialPath: '/scripts/alpha.fountain'),
      );
      await tester.pumpAndSettle();
      expect(core.requests, ['/scripts/alpha.fountain']);
      final exit = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(core.shutdowns, isEmpty, reason: 'the open has not answered yet');
      core.holdOpen!.complete();
      await tester.pumpAndSettle();
      expect(await exit, AppExitResponse.exit);
      expect(core.shutdowns, [0]);
      expect(core.opened.single.closes, 1);
      expect(find.byType(EditorPage), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('a quit tells the core while the script is still open', (
    tester,
  ) async {
    // The core marks what it still holds at shutdown as the session to come
    // back to. A script closed first is one the writer put away.
    final core = await _pump(tester);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(core.openAtShutdown, [
      ['/scripts/alpha.fountain'],
    ]);
    expect(core.opened.single.closes, 0);
    await tester.pumpWidget(const SizedBox());
    expect(core.opened.single.closes, 1, reason: 'let go with the app');
  });

  testWidgets('frames built after a quit is agreed still have their script', (
    tester,
  ) async {
    // The window stays for a few frames after the answer, and the page with
    // it. Anything that rebuilds or resizes it then reads the controller.
    final core = await _pump(tester);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);

    tester.view.physicalSize = const Size(700, 800);
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pump(const Duration(seconds: 31));

    expect(tester.takeException(), isNull);
    expect(find.byType(EditorPage), findsOneWidget);
    expect(core.opened.single.closes, 0, reason: 'let go with the app');
  });

  testWidgets('a script put away is not open at the quit that follows', (
    tester,
  ) async {
    final core = await _pump(tester);
    await _key(tester, LogicalKeyboardKey.keyW, control: true);
    expect(find.byType(EditorPage), findsNothing);
    expect(core.parks, 1, reason: 'written down as put away, for a crash');
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(core.openAtShutdown, [<String?>[]]);
  });

  testWidgets('nothing is opened once a quit is under way', (tester) async {
    final core = await _pump(tester, open: false);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(core.requests, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed open keeps the existing session', (tester) async {
    final core = await _pump(tester);
    final controller = _editor(tester).controller;
    core.failOpen = true;
    await _chooseBeta(tester);
    expect(_editor(tester).controller, same(controller));
    expect(core.opened.single.closes, 0);
    expect(
      find.text('The script could not be opened or created.'),
      findsOneWidget,
    );
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('switching holds input while the destination loads', (
    tester,
  ) async {
    final core = await _pump(tester);
    final choice = pendingFileChoice(tester);
    final controller = _editor(tester).controller;
    core.holdOpen = Completer<void>();
    await _chooseBeta(tester);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await _key(tester, LogicalKeyboardKey.keyN, control: true);
    choice.complete('/scripts/new.fountain');
    await tester.pumpAndSettle();
    core.holdOpen!.complete();
    await tester.pumpAndSettle();
    expect(_editor(tester).controller, isNot(same(controller)));
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(core.requests, [
      '/scripts/alpha.fountain',
      '/scripts/beta.fountain',
    ]);
  });

  testWidgets(
    'choosing the current path preserves its dirty session and history',
    (tester) async {
      final core = await _pump(tester);
      final controller = _editor(tester).controller;
      controller.insertText('Unsaved. ');
      await _key(tester, LogicalKeyboardKey.keyO, control: true);
      await tester.enterText(
        find.byKey(const Key('quick-open-search')),
        'alpha',
      );
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_editor(tester).controller, same(controller));
      expect(core.requests, hasLength(1));
      expect(controller.core.dirty, isTrue);
      controller.undo();
      expect(controller.source, isNot(contains('Unsaved.')));
    },
  );

  for (final panel in [LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyK]) {
    testWidgets('quick-open replaces ${panel.keyLabel}; Escape never edits', (
      tester,
    ) async {
      await _pump(tester);
      final controller = _editor(tester).controller;
      final source = controller.source;
      await _key(tester, panel, control: true);
      await _key(tester, LogicalKeyboardKey.keyO, control: true);
      expect(find.byType(CommandPalette), findsNothing);
      expect(find.byType(FindBar), findsNothing);
      expect(find.byType(QuickOpenDialog), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(controller.source, source);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    });
  }

  for (final label in ['New script…', 'Open script…', 'Back to the library']) {
    testWidgets('the palette runs $label', (tester) async {
      await _pump(tester);
      final choice = label == 'New script…' ? pendingFileChoice(tester) : null;
      await _key(tester, LogicalKeyboardKey.keyK, control: true);
      await tester.enterText(
        find.widgetWithText(TextField, 'Element or command'),
        label,
      );
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(CommandPalette), findsNothing);
      if (choice != null) {
        choice.complete('/scripts/palette-new.fountain');
        await tester.pumpAndSettle();
        expect(
          _editor(tester).controller.core.path,
          '/scripts/palette-new.fountain',
        );
      } else if (label == 'Open script…') {
        await tester.enterText(
          find.byKey(const Key('quick-open-search')),
          'beta',
        );
        await _key(tester, LogicalKeyboardKey.enter);
        expect(_editor(tester).controller.core.path, '/scripts/beta.fountain');
      } else {
        expect(find.byType(LibraryPage), findsOneWidget);
      }
    });
  }

  testWidgets('Browse is keyboard reachable even with no matches', (
    tester,
  ) async {
    await _pump(tester);
    final choice = pendingFileChoice(tester);
    await _key(tester, LogicalKeyboardKey.keyO, control: true);
    await tester.enterText(
      find.byKey(const Key('quick-open-search')),
      'no matching script',
    );
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(QuickOpenDialog), findsNothing);
    choice.complete('/scripts/browsed.fountain');
    await tester.pumpAndSettle();
    expect(_editor(tester).controller.core.path, '/scripts/browsed.fountain');
  });

  Future<FakeCore> prepareImport(_AppCore core, {bool warnings = true}) async {
    final candidate = FakeCore.single(BlockKind.action, '')..eventHandle = 999;
    candidate.apply(
      EditCommand.replaceText(
        block: 1,
        startUtf16: 0,
        endUtf16: 0,
        with_: 'Imported screenplay words.',
      ),
    );
    core.importResult = FdxImported(
      document: candidate,
      warnings: warnings ? ['Custom margins were not retained.'] : [],
    );
    return candidate;
  }

  Future<void> chooseImport(WidgetTester tester) async {
    final choice = pendingFileChoice(tester);
    await _runPalette(tester, 'Import FDX…');
    choice.complete('/scripts/source.fdx');
    await tester.pumpAndSettle();
  }

  testWidgets('Library Import FDX chooser cancellation opens nothing', (
    tester,
  ) async {
    final core = await _pump(tester, open: false);
    final choice = pendingFileChoice(tester);
    await tester.tap(find.byKey(const Key('import-fdx')));
    await tester.pumpAndSettle();
    choice.complete(null);
    await tester.pumpAndSettle();
    expect(core.importRequests, isEmpty);
    expect(core.requests, isEmpty);
    expect(find.byType(LibraryPage), findsOneWidget);
  });

  testWidgets(
    'FDX decode failure leaves dirty editor and close prompt untouched',
    (tester) async {
      final core = await _pump(tester);
      final controller = _editor(tester).controller;
      controller.insertText('Keep these unsaved words. ');
      final source = controller.source;
      await chooseImport(tester);
      expect(
        find.textContaining('Could not import FDX: Invalid XML'),
        findsOneWidget,
      );
      expect(find.text('Save changes to alpha.fountain?'), findsNothing);
      expect(_editor(tester).controller, same(controller));
      expect(controller.source, source);
      expect(core.opened.single.closes, 0);
      expect(core.opened.single.saves, isEmpty);
    },
  );

  testWidgets('declining FDX warnings closes only the isolated candidate', (
    tester,
  ) async {
    final core = await _pump(tester);
    final candidate = await prepareImport(core);
    final controller = _editor(tester).controller;
    controller.insertText('Still my draft. ');
    final source = controller.source;
    await chooseImport(tester);
    expect(find.text('Save changes to alpha.fountain?'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(candidate.closes, 1);
    expect(core.opened.single.closes, 0);
    expect(core.opened.single.saves, isEmpty);
    expect(_editor(tester).controller, same(controller));
    expect(controller.source, source);
  });

  testWidgets(
    'accepted FDX warnings still require consent to close the old draft',
    (tester) async {
      final core = await _pump(tester);
      final candidate = await prepareImport(core);
      final controller = _editor(tester).controller;
      controller.insertText('My current draft. ');
      final source = controller.source;
      await chooseImport(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes to alpha.fountain?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(candidate.closes, 1);
      expect(core.opened.single.closes, 0);
      expect(_editor(tester).controller, same(controller));
      expect(controller.source, source);
    },
  );

  testWidgets(
    'adopted FDX is unsaved and Save asks for a Fountain destination',
    (tester) async {
      final core = await _pump(tester);
      final candidate = await prepareImport(core, warnings: false);
      await chooseImport(tester);
      expect(_editor(tester).controller.core, same(candidate));
      expect(core.opened.single.closes, 1);
      expect(candidate.path, isNull);
      expect(candidate.dirty, isTrue);
      expect(_editor(tester).title, 'Untitled');
      const channel = MethodChannel('slugline/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => '/scripts/imported.fountain',
      );
      await _key(tester, LogicalKeyboardKey.keyS, control: true);
      expect(candidate.path, '/scripts/imported.fountain');
      expect(candidate.dirty, isFalse);
      expect(_editor(tester).title, 'imported.fountain');
      expect(find.text('Untitled', findRichText: true), findsNothing);
    },
  );

  testWidgets('Save As renames the script in the bar and the close prompt', (
    tester,
  ) async {
    final core = await _pump(tester);
    final choice = pendingFileChoice(tester);
    expect(_editor(tester).title, 'alpha.fountain');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _key(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    choice.complete('/scripts/gamma.fountain');
    await tester.pumpAndSettle();
    expect(core.opened.single.saveAsCalls, [
      ('/scripts/gamma.fountain', false),
    ]);
    expect(_editor(tester).title, 'gamma.fountain');
    expect(find.text('gamma', findRichText: true), findsOneWidget);
    expect(find.text('alpha', findRichText: true), findsNothing);
    _editor(tester).controller.insertText('More. ');
    await _key(tester, LogicalKeyboardKey.keyW, control: true);
    expect(find.text('Save changes to gamma.fountain?'), findsOneWidget);
  });

  testWidgets(
    'candidate journal failure is not attributed to the old session',
    (tester) async {
      final core = await _pump(tester);
      final candidate = await prepareImport(core);
      candidate.journalUnavailable = true;
      core.holdImport = Completer<void>();
      await chooseImport(tester);
      core.eventBus.add(const CoreEvent.journalBroken(handle: 999));
      await tester.pump();
      expect(
        find.textContaining('crash-recovery record for this script'),
        findsNothing,
      );
      core.holdImport!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(
        _editor(tester).saveStatus!.label,
        contains('recovery record unavailable'),
      );
      expect(
        find.textContaining('crash-recovery record for this script'),
        findsOneWidget,
      );
      expect(core.opened.single.journalUnavailable, isFalse);
    },
  );

  testWidgets('unmount during FDX decode closes the candidate once', (
    tester,
  ) async {
    final core = await _pump(tester);
    final candidate = await prepareImport(core, warnings: false);
    core.holdImport = Completer<void>();
    await chooseImport(tester);
    await tester.pumpWidget(const SizedBox());
    core.holdImport!.complete();
    await tester.pumpAndSettle();
    expect(candidate.closes, 1);
    expect(core.opened.single.closes, 1);
  });

  testWidgets(
    'failed close-confirmation save rejects FDX adoption and closes candidate',
    (tester) async {
      final core = await _pump(tester);
      final candidate = await prepareImport(core, warnings: false);
      final controller = _editor(tester).controller;
      controller.insertText('Current unsaved words. ');
      final source = controller.source;
      core.opened.single.refuseSaveWith = SaveFailure.noSpace;
      await chooseImport(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('The disk is full'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(_editor(tester).controller, same(controller));
      expect(controller.source, source);
      expect(core.opened.single.closes, 0);
      expect(candidate.closes, 1);
    },
  );

  testWidgets('editor overflow Import FDX cancellation retains session', (
    tester,
  ) async {
    final core = await _pump(tester);
    final choice = pendingFileChoice(tester);
    await tester.tap(find.byKey(const ValueKey('editor overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import FDX…'));
    await tester.pumpAndSettle();
    choice.complete(null);
    await tester.pumpAndSettle();
    expect(core.importRequests, isEmpty);
    expect(core.opened.single.closes, 0);
    expect(_editor(tester).controller.core, same(core.opened.single));
  });

  testWidgets(
    'late cancelled-candidate journal event cannot mark the old editor unprotected',
    (tester) async {
      final core = await _pump(tester);
      final candidate = await prepareImport(core);
      candidate.journalUnavailable = true;
      await chooseImport(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      core.eventBus.add(CoreEvent.journalBroken(handle: candidate.eventHandle));
      await tester.pumpAndSettle();
      expect(candidate.closes, 1);
      expect(
        _editor(tester).saveStatus!.label,
        isNot(contains('recovery record unavailable')),
      );
      expect(
        find.textContaining('crash-recovery record for this script'),
        findsNothing,
      );
      core.opened.single.journalUnavailable = true;
      core.eventBus.add(
        CoreEvent.journalBroken(handle: core.opened.single.eventHandle),
      );
      await tester.pumpAndSettle();
      expect(
        _editor(tester).saveStatus!.label,
        contains('recovery record unavailable'),
      );
      expect(
        find.textContaining('crash-recovery record for this script'),
        findsOneWidget,
      );
    },
  );
}
