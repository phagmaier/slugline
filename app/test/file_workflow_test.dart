import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/library/quick_open_dialog.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/navigator_sidebar.dart';

import 'support/fake_core.dart';

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

ScriptView _script(String id, int modified) => ScriptView(
  id: id,
  path: '/scripts/$id.fountain',
  title: id,
  modifiedMillis: modified,
  bytes: 10,
  pageCount: 1,
  missing: false,
  open: false,
  scrollRow: 0,
);

class _AppCore implements Core {
  final opened = <FakeCore>[];
  final requests = <String>[];
  bool failOpen = false;
  Completer<void>? holdOpen;
  PreferencesView currentPreferences = _preferences;
  final preferenceWrites = <PreferencesView>[];
  bool failPreferences = false;

  @override
  Stream<CoreEvent> get events => const Stream.empty();
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
  Future<List<ScriptView>> sessionToRestore() async => [];
  @override
  Future<List<ScriptView>> library() async => [
    _script('alpha', 2),
    _script('beta', 1),
  ];
  @override
  Future<DocumentCore?> openDocument(String path) async {
    requests.add(path);
    await holdOpen?.future;
    if (failOpen) return null;
    final core = FakeCore.single(BlockKind.action, 'Text from $path.')
      ..filePath = path;
    core.onDisk = core.source();
    opened.add(core);
    return core;
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
      expect(find.byType(FileChooser), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'File name'),
        '/scripts/new.fountain',
      );
      await _key(tester, LogicalKeyboardKey.enter);
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
    testWidgets('${key.keyLabel} works in the library; Escape cancels it', (
      tester,
    ) async {
      final core = await _pump(tester, open: false);
      await _key(tester, key, control: true);
      expect(
        find.byType(
          key == LogicalKeyboardKey.keyN ? FileChooser : QuickOpenDialog,
        ),
        findsOneWidget,
      );
      await _key(tester, LogicalKeyboardKey.escape);
      expect(core.requests, isEmpty);
      expect(find.byType(LibraryPage), findsOneWidget);
    });
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
        await tester.enterText(
          find.widgetWithText(TextField, 'File name'),
          '/scripts/new.fountain',
        );
        await _key(tester, LogicalKeyboardKey.enter);
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
    final controller = _editor(tester).controller;
    core.holdOpen = Completer<void>();
    await _chooseBeta(tester);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await _key(tester, LogicalKeyboardKey.keyN, control: true);
    expect(find.byType(FileChooser), findsNothing);
    core.holdOpen!.complete();
    await tester.pumpAndSettle();
    expect(_editor(tester).controller, isNot(same(controller)));
    expect(tester.testTextInput.hasAnyClients, isTrue);
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
      await _key(tester, LogicalKeyboardKey.keyK, control: true);
      await tester.enterText(
        find.widgetWithText(TextField, 'Element or command'),
        label,
      );
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(CommandPalette), findsNothing);
      expect(
        find.byType(
          label == 'New script…'
              ? FileChooser
              : label == 'Open script…'
              ? QuickOpenDialog
              : LibraryPage,
        ),
        findsOneWidget,
      );
      if (label != 'Back to the library') {
        await _key(tester, LogicalKeyboardKey.escape);
      }
    });
  }

  testWidgets('Browse is keyboard reachable even with no matches', (
    tester,
  ) async {
    await _pump(tester);
    await _key(tester, LogicalKeyboardKey.keyO, control: true);
    await tester.enterText(
      find.byKey(const Key('quick-open-search')),
      'no matching script',
    );
    await _key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(QuickOpenDialog), findsNothing);
    expect(find.byType(FileChooser), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.escape);
  });
}
