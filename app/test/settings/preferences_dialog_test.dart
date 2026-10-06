import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/widgets/escape_dismissible.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1280, 960);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  const preferences = PreferencesView(
    autosaveEnabled: true,
    autocompleteEnabled: true,
    navigatorVisible: false,
    spellEnabled: true,
    spellLanguage: 'en_US',
    appearance: 'system',
    editorTextSize: 15,
    defaultPaper: 'us_letter',
    sceneNumbers: 'off',
    pdfFontPath: null,
    boldSceneHeadings: false,
    distractionFree: false,
    pageView: false,
    autosaveIdleMs: 2000,
    autosaveIntervalMs: 30000,
    backupDir: null,
    backupKeepVersions: 10,
    backupKeepDays: 7,
  );
  const spelling = SpellStatus(
    enabled: true,
    language: 'en_US',
    languages: [
      SpellLanguage(code: 'en_US', label: 'English (United States)'),
      SpellLanguage(code: 'de_DE', label: 'German (Germany)'),
    ],
    message: 'Checking with English (United States).',
  );

  testWidgets('the complete preference view is returned from one surface', (
    tester,
  ) async {
    PreferencesView? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await PreferencesDialog.show(
                context,
                preferences: preferences,
                spelling: spelling,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appearance preference')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('distraction free preference')));
    await tester.drag(
      find.byKey(const ValueKey('editor text size')),
      const Offset(100, 0),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('autosave idle')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('autosave idle')), '0.5');
    await tester.enterText(
      find.byKey(const ValueKey('autosave interval')),
      '12',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('bold scene headings preference')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('bold scene headings preference')),
    );

    await tester.tap(find.byKey(const ValueKey('save preferences')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.appearance, 'light');
    expect(result!.distractionFree, isTrue);
    expect(result!.autosaveIdleMs, 500);
    expect(result!.autosaveIntervalMs, 12000);
    expect(result!.editorTextSize, greaterThan(15));
    expect(result!.spellLanguage, 'en_US');
    expect(result!.boldSceneHeadings, isTrue);
  });

  testWidgets('a custom PDF face carries the grid-fidelity warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PreferencesDialog(preferences: preferences, spelling: spelling),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pdf font preference')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('pdf font preference')),
      '/usr/share/fonts/example.ttf',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('font fidelity warning')), findsOneWidget);
  });

  testWidgets('Escape dismisses both Phase 10 dialogs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => PreferencesDialog.show(
                  context,
                  preferences: preferences,
                  spelling: spelling,
                ),
                child: const Text('Preferences'),
              ),
              TextButton(
                onPressed: () => ShortcutsDialog.show(context),
                child: const Text('Shortcuts'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PreferencesDialog), findsNothing);

    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsDialog), findsNothing);
  });

  testWidgets('Escape dismisses serious dialogs without enabling click-away', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => const EscapeDismissible(
                child: AlertDialog(title: Text('Save failed')),
              ),
            ),
            child: const Text('Open blocking dialog'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open blocking dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsNothing);
  });
}
