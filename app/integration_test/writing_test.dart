// §Phase 3's exit criteria, against the real `libslugline_bridge.so`:
//
//   * "You can write a full scene without touching the mouse."
//   * "Element-type changes are provably non-destructive."
//
// Run with:
//
//     flutter test integration_test/writing_test.dart -d linux
//
// The widget tests in `test/editor/` prove the wiring against a double, and
// `cargo test` proves the tables and the inference rules. What only this can
// prove is the whole chain at once: keystroke → EditCommand → re-classification →
// patch → Fountain, and that the Fountain reads back as the scene that was typed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/pagination_debug_dialog.dart';
import 'package:slugline/editor/go_to_page_dialog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('slugline-writing-');
    await Core.init(
      configDir: '${scratch.path}/config',
      dataDir: '${scratch.path}/data',
      stateDir: '${scratch.path}/state',
    );
  });
  tearDownAll(() async {
    await Core.instance.shutdown();
    scratch.deleteSync(recursive: true);
  });

  Future<EditorController> open(WidgetTester tester, [String? source]) async {
    final controller = EditorController(
      source == null
          ? RustDocumentCore.create()
          : RustDocumentCore.parse(source),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(controller: controller, navigatorVisible: true),
      ),
    );
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    return controller;
  }

  /// Types [text] a character at a time, as a writer does — so that automatic
  /// classification is asked the same question on every keystroke that it will be
  /// asked in the application.
  Future<void> type(
    WidgetTester tester,
    EditorController controller,
    String text,
  ) async {
    for (final character in text.characters) {
      controller.insertText(character);
    }
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  List<BlockKind> kinds(EditorController controller) =>
      controller.blocks.map((block) => block.kind).toList();

  for (final pageView in [false, true]) {
    testWidgets('go to page uses real pagination, pageView=$pageView', (
      tester,
    ) async {
      final source =
          '\uFEFFTitle: Reader notes\r\n\r\n'
          '[[A private opening note.]]\r\n\r\n'
          '${List.generate(150, (line) => 'Action line $line with 🎬.').join('\r\n')}\r\n';
      final file = File('${scratch.path}/go-to-page-$pageView.fountain')
        ..writeAsStringSync(source);
      final bytes = file.readAsBytesSync();
      final core = (await Core.instance.openDocument(file.path))!;
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(controller: controller, pageView: pageView),
        ),
      );
      await tester.pumpAndSettle();
      final snapshot = switch (await (core as ScreenplayOutput).paginate(
        const PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        ),
      )) {
        PaginationOutcome_Current(:final pagination) => pagination,
        _ => throw StateError(
          'An unedited document must have current pagination',
        ),
      };
      expect(snapshot.pageCount, greaterThanOrEqualTo(3));
      expect(snapshot.titlePage, isNotNull);
      final journal = core.journalState;
      final revision = controller.documentRevision;
      final before = controller.source;
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(EditorSurface),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      for (final page in [2, snapshot.pageCount]) {
        // Exercise the palette and shortcut independently against the same Rust
        // snapshot that supplies Preview and PDF, including an intra-block page.
        if (page == 2) {
          await press(tester, LogicalKeyboardKey.keyK, control: true);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Element or command'),
            'Go to page',
          );
          await press(tester, LogicalKeyboardKey.enter);
        } else {
          await press(tester, LogicalKeyboardKey.keyL, control: true);
        }
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Page number'),
          '$page',
        );
        await press(tester, LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(GoToPageDialog), findsNothing);
        final first = snapshot.pages[page - 1].lines.firstWhere(
          (line) => line.block != null && line.sourceLine != null,
        );
        final index = controller.blocks.indexWhere(
          (block) => block.id == first.block,
        );
        final offset = controller.layout
            .linesOf(index)[first.sourceLine!]
            .start;
        expect(
          controller.selection.focus,
          DocPosition(block: first.block!, offsetUtf16: offset),
        );
        expect(controller.hasSelection, isFalse);
        expect(scroll.pixels, greaterThan(0));
      }
      await press(tester, LogicalKeyboardKey.keyL, control: true);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Page number'),
        '1',
      );
      await press(tester, LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(
        controller.selection.focus,
        DocPosition(block: controller.blocks.first.id, offsetUtf16: 0),
      );
      expect(scroll.pixels, 0);
      expect(controller.source, before);
      expect(controller.documentRevision, revision);
      expect(core.journalState, journal);
      expect(core.dirty, isFalse);
      expect(file.readAsBytesSync(), bytes);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.focus.offsetUtf16, 1);
    });
  }

  for (final (kind, source, index, expected) in [
    (BlockKind.action, 'Seed.\n', 0, 'First 🎬 line.\nSecond line.\n'),
    (
      BlockKind.dialogue,
      'JOHN\nSeed.\n',
      1,
      'JOHN\nFirst 🎬 line.\nSecond line.\n',
    ),
    (
      BlockKind.note,
      '[[Seed.]]\n\nAnchor.\n',
      0,
      '[[First 🎬 line.\nSecond line.]]\n\nAnchor.\n',
    ),
  ]) {
    testWidgets(
      'Shift+Enter saves adjacent lines in ${kind.name} and reopens',
      (tester) async {
        final file = File('${scratch.path}/line-break-${kind.name}.fountain')
          ..writeAsStringSync(source);
        final core = (await Core.instance.openDocument(file.path))!;
        final controller = EditorController(core);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.tap(find.byType(EditorSurface));
        await tester.pump();
        final block = controller.blocks[index];
        final blockCount = controller.blocks.length;
        controller.setSelection(
          DocSelection(
            anchor: DocPosition(block: block.id, offsetUtf16: 0),
            focus: DocPosition(block: block.id, offsetUtf16: block.text.length),
          ),
        );
        await tester.pump();
        await type(tester, controller, 'First 🎬 line.');
        final before = controller.source;
        final selection = controller.selection;
        final journalled = core.journalState.$1;

        await press(tester, LogicalKeyboardKey.enter, shift: true);
        expect(controller.blocks, hasLength(blockCount));
        expect(controller.blocks[index].kind, kind);
        expect(controller.blocks[index].text, 'First 🎬 line.\n');
        expect(core.journalState, (journalled + 1, false));
        controller.undo();
        expect(controller.source, before);
        expect(controller.selection, selection);
        controller.redo();
        await tester.pump();
        await type(tester, controller, 'Second line.');
        expect(controller.source, expected);
        expect(await core.save(), isA<SaveOutcome_Saved>());
        expect(file.readAsStringSync(), expected);

        await tester.pumpWidget(const SizedBox());
        core.close();
        final reopened = (await Core.instance.openDocument(file.path))!;
        expect(reopened.source(), expected);
        expect(
          reopened.blocks(index, index + 1).single.text,
          'First 🎬 line.\nSecond line.',
        );
        expect(reopened.blocks(index, index + 1).single.kind, kind);
        reopened.close();
      },
    );
  }

  testWidgets(
    'palette display and dialog commands preserve native source and persist preferences',
    (tester) async {
      final file = File('${scratch.path}/palette.fountain')
        ..writeAsStringSync(
          '\uFEFFTitle: Palette\r\n\r\nINT. ROOM - DAY\r\n\r\nDraft **text**.  \r\n',
        );
      final bytes = file.readAsBytesSync();
      final originalPreferences = Core.instance.preferences();
      await tester.pumpWidget(
        SluglineApp(core: Core.instance, initialPath: file.path),
      );
      await tester.pumpAndSettle();
      EditorPage current() =>
          tester.widget<EditorPage>(find.byType(EditorPage));
      final controller = current().controller;
      final source = controller.source;
      final selection = controller.selection;
      final setup = current().initialPageSetup;
      Future<void> run(String label) async {
        await press(tester, LogicalKeyboardKey.keyK, control: true);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Element or command'),
          label,
        );
        await press(tester, LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(CommandPalette), findsNothing);
      }

      final pageView = current().pageView;
      await run(pageView ? 'Use continuous view' : 'Use page view');
      expect(current().pageView, !pageView);
      expect(Core.instance.preferences().pageView, !pageView);
      final stored = File(
        '${scratch.path}/config/prefs.json',
      ).readAsStringSync();
      expect(stored, contains('"page_view": ${!pageView}'));
      await run(pageView ? 'Use page view' : 'Use continuous view');
      final textSize = current().textSize;
      final increase = textSize < 24;
      await run(increase ? 'Increase text size' : 'Decrease text size');
      expect(current().textSize, textSize + (increase ? 1 : -1));
      await run(increase ? 'Decrease text size' : 'Increase text size');
      final distractionFree = current().distractionFree;
      await run(
        distractionFree
            ? 'Leave distraction-free mode'
            : 'Enter distraction-free mode',
      );
      expect(current().distractionFree, !distractionFree);
      await run(
        distractionFree
            ? 'Enter distraction-free mode'
            : 'Leave distraction-free mode',
      );
      for (final entry in <(String, Type)>[
        ('Preferences…', PreferencesDialog),
        ('Keyboard shortcuts', ShortcutsDialog),
        ('Spell checking…', SpellDialog),
        ('Pagination debug', PaginationDebugDialog),
      ]) {
        await run(entry.$1);
        expect(find.byType(entry.$2), findsOneWidget);
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(entry.$2), findsNothing);
      }
      expect(controller.source, source);
      expect(controller.selection, selection);
      expect(controller.core.dirty, isFalse);
      expect(current().initialPageSetup, setup);
      expect(file.readAsBytesSync(), bytes);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        controller.selection.focus.offsetUtf16,
        selection.focus.offsetUtf16 + 1,
      );
      await press(tester, LogicalKeyboardKey.keyW, control: true);
      await tester.pumpAndSettle();
      expect(await Core.instance.setPreferences(originalPreferences), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'keyboard script switching saves the native draft before leaving',
    (tester) async {
      final alpha = File('${scratch.path}/alpha.fountain')
        ..writeAsStringSync('Original draft.\n');
      final beta = File('${scratch.path}/beta.fountain')
        ..writeAsStringSync('Another draft.\n');
      for (final file in [alpha, beta]) {
        final document = await Core.instance.openDocument(file.path);
        expect(document, isNotNull);
        document!.close();
      }
      await tester.pumpWidget(SluglineApp(core: Core.instance));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('library-search')),
        'alpha.fountain',
      );
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      EditorController current() =>
          tester.widget<EditorPage>(find.byType(EditorPage)).controller;
      expect(current().core.path, alpha.path);
      expect(
        tester
            .widget<EditorSurface>(find.byType(EditorSurface))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      // The integration binding does not register TestTextInput. Deliver the
      // input value directly to our client, as the IME suite does.
      tester
          .state<EditorSurfaceState>(find.byType(EditorSurface))
          .updateEditingValue(
            const TextEditingValue(
              text: 'Native unsaved words.',
              selection: TextSelection.collapsed(offset: 21),
            ),
          );
      await tester.pump();
      expect(current().core.dirty, isTrue);
      await press(tester, LogicalKeyboardKey.keyO, control: true);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-open-search')),
        'beta.fountain',
      );
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Save changes to alpha.fountain?'), findsOneWidget);
      // Tab traverses the modal's controls; Enter activates Save.
      bool saveFocused() {
        final button = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>();
        return button?.child is Text && (button!.child as Text).data == 'Save';
      }

      for (var n = 0; n < 6 && !saveFocused(); n++) {
        await press(tester, LogicalKeyboardKey.tab);
      }
      expect(saveFocused(), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(current().core.path, beta.path);
      expect(alpha.readAsStringSync(), 'Native unsaved words.\n');
      await press(tester, LogicalKeyboardKey.keyN, control: true);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'File name'),
        '${scratch.path}/new.fountain',
      );
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(current().core.path, '${scratch.path}/new.fountain');
      await press(tester, LogicalKeyboardKey.keyW, control: true);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  // --- the exit criterion ------------------------------------------------

  testWidgets('a whole scene, keyboard only, with nothing set by hand', (
    tester,
  ) async {
    final controller = await open(tester);

    // The slug line promotes itself as it is typed.
    await type(tester, controller, 'INT. HOUSE - DAY');
    expect(kinds(controller), [BlockKind.sceneHeading]);
    expect(
      controller.blocks.single.forced,
      isFalse,
      reason: 'inference never pins; only the writer does',
    );

    // Enter after a heading gives action.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await type(tester, controller, 'John enters, holding a letter.');

    // A cue: type the name, Tab.
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, controller, 'JOHN');
    await press(tester, LogicalKeyboardKey.tab);
    expect(kinds(controller).last, BlockKind.character);

    // Enter after a cue gives dialogue, and Tab in the empty dialogue block that
    // appears turns it into the parenthetical — the standard "cue, Tab, wryly".
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.dialogue);
    await press(tester, LogicalKeyboardKey.tab);
    expect(kinds(controller).last, BlockKind.parenthetical);
    await type(tester, controller, '(quietly)');

    // Enter after a parenthetical gives dialogue again.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.dialogue);
    await type(tester, controller, 'It came.');

    // Enter after dialogue gives action; a transition writes itself.
    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await type(tester, controller, 'CUT TO:');
    expect(kinds(controller).last, BlockKind.transition);

    expect(kinds(controller), [
      BlockKind.sceneHeading,
      BlockKind.action,
      BlockKind.character,
      BlockKind.parenthetical,
      BlockKind.dialogue,
      BlockKind.transition,
    ]);

    // The file it writes: the cue carries `@` because Tab pinned it, and nothing
    // else needs a marker at all.
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\n'
      'John enters, holding a letter.\n\n'
      '@JOHN\n'
      '(quietly)\n'
      'It came.\n\n'
      'CUT TO:\n',
    );

    // And reopening that file gives back the same elements, which is the whole
    // point of inference agreeing with the parser.
    final reopened = EditorController(
      RustDocumentCore.parse(controller.source),
    );
    addTearDown(reopened.dispose);
    expect(kinds(reopened), kinds(controller));
  });

  testWidgets('the real entity index and scene parser drive the navigator', (
    tester,
  ) async {
    final controller = await open(
      tester,
      'INT. HOUSE - DAY #1#\n\n'
      'BOB (V.O.)\nHello.\n\n'
      'EXT. STREET - NIGHT #2A#\n\n'
      'BOB (O.S.)\nAgain.\n',
    );

    // The saved docked preference does not open the narrow-window drawer.
    // Use the writer's shortcut, which also works when already docked.
    await press(tester, LogicalKeyboardKey.keyJ, control: true);
    await tester.pumpAndSettle();

    expect(find.text('HOUSE'), findsOneWidget);
    expect(find.text('INT. · DAY'), findsOneWidget);
    expect(find.text('2A'), findsOneWidget);

    await tester.tap(find.textContaining('Characters'));
    await tester.pump();
    expect(find.text('BOB'), findsOneWidget);
    expect(find.text('2 occurrences'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyJ, control: true);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('street');
    await tester.pump();
    expect(find.text('HOUSE'), findsNothing);
    expect(find.text('STREET'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final street = controller.blocks.firstWhere(
      (block) => block.text.contains('STREET'),
    );
    expect(controller.selection.focus.block, street.id);
  });

  testWidgets('double-Enter after a speech asks for the next cue', (
    tester,
  ) async {
    final controller = await open(tester, 'JOHN\nHello.\n');
    final dialogue = controller.blocks[1];
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(
          block: dialogue.id,
          offsetUtf16: dialogue.text.length,
        ),
        focus: DocPosition(
          block: dialogue.id,
          offsetUtf16: dialogue.text.length,
        ),
      ),
    );

    await press(tester, LogicalKeyboardKey.enter);
    expect(kinds(controller).last, BlockKind.action);
    await press(tester, LogicalKeyboardKey.enter);

    expect(controller.blocks.length, 3, reason: 'no fourth block');
    expect(kinds(controller).last, BlockKind.character);
    await type(tester, controller, 'MARY');
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, controller, 'Hello yourself.');

    expect(controller.source, 'JOHN\nHello.\n\n@MARY\nHello yourself.\n');
  });

  // --- element-type changes are non-destructive ---------------------------

  testWidgets('every element shortcut leaves the text and the caret alone', (
    tester,
  ) async {
    const text = 'The café is quiet. 日本 🎬';
    final controller = await open(tester, '!$text\n');
    final id = controller.blocks.single.id;
    // Mid-text, and after the astral-plane character, so that a caret the core
    // moved would be obvious.
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: id, offsetUtf16: 4),
        focus: DocPosition(block: id, offsetUtf16: 4),
      ),
    );

    for (final digit in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit0,
    ]) {
      await press(tester, digit, control: true);
      expect(
        controller.blocks.single.text,
        text,
        reason: 'Ctrl+${digit.keyLabel} changed the text',
      );
      expect(controller.blocks.single.forced, isTrue);
      expect(
        controller.selection.focus.offsetUtf16,
        4,
        reason: 'Ctrl+${digit.keyLabel} moved the caret',
      );
      // Whatever the type, the bytes come back: the text survives a round trip
      // through Fountain in every one of these element types.
      final written = controller.source;
      final reopened = EditorController(RustDocumentCore.parse(written));
      addTearDown(reopened.dispose);
      expect(reopened.blocks.single.text, text, reason: 'in $written');
    }
  });

  testWidgets('a shortcut straight after an automatic change overrules it', (
    tester,
  ) async {
    final controller = await open(tester);
    await type(tester, controller, 'INT. HOUSE');
    expect(kinds(controller), [BlockKind.sceneHeading]);

    // §Phase 3: "an immediate element-type shortcut after an automatic change
    // reverts and forces the user's choice".
    await press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(kinds(controller), [BlockKind.action]);

    // And it stays action however much more of the slug line is typed.
    await type(tester, controller, ' - DAY');
    expect(kinds(controller), [BlockKind.action]);
    expect(controller.blocks.single.text, 'INT. HOUSE - DAY');
    expect(controller.source, '!INT. HOUSE - DAY\n');
  });

  testWidgets(
    'an automatic promotion is undone with the typing that caused it',
    (tester) async {
      final controller = await open(tester);
      await type(tester, controller, 'INT. HOUSE - DAY');
      expect(kinds(controller), [BlockKind.sceneHeading]);

      controller.undo();
      await tester.pump();

      expect(controller.blocks.single.text, isEmpty);
      expect(kinds(controller), [BlockKind.action]);
    },
  );

  testWidgets('a paragraph that stops being a cue takes its speech with it', (
    tester,
  ) async {
    final controller = await open(tester, 'JOHN\nHello.\n');
    expect(kinds(controller), [BlockKind.character, BlockKind.dialogue]);

    // Lower-case letters take the line out of §4.1's cue character set.
    final cue = controller.blocks.first;
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: cue.id, offsetUtf16: cue.text.length),
        focus: DocPosition(block: cue.id, offsetUtf16: cue.text.length),
      ),
    );
    await type(tester, controller, 'ny');

    expect(kinds(controller), [BlockKind.action, BlockKind.action]);
    expect(controller.source, 'JOHNny\n\nHello.\n');
  });

  testWidgets('a plain paste is still inferred from nothing', (tester) async {
    final controller = await open(tester);
    await Clipboard.setData(
      const ClipboardData(text: 'INT. HOUSE - DAY\nCUT TO:'),
    );
    await controller.paste(plain: true);
    await tester.pump();

    expect(kinds(controller), [BlockKind.action, BlockKind.action]);
    expect(controller.source, '!INT. HOUSE - DAY\n\n!CUT TO:\n');
  });

  // --- find and replace --------------------------------------------------

  testWidgets('find, replace and replace all, through the real core', (
    tester,
  ) async {
    const script =
        'INT. HOUSE - DAY\n\nJohn leaves the house. The house is quiet.\n';
    final controller = await open(tester, script);
    controller.moveToDocumentEdge(start: true);

    // Case-insensitive by default, so the slug line counts too.
    controller.search(
      const FindQuery(
        text: 'house',
        caseSensitive: false,
        wholeWord: false,
        kinds: [],
      ),
    );
    await tester.pump();
    expect(controller.matches, hasLength(3));
    expect(controller.matchIndex, 0);
    // The match is the selection, and taking it back out gives the matched text.
    expect(controller.selectedText(), 'HOUSE');

    controller.search(
      const FindQuery(
        text: 'house',
        caseSensitive: true,
        wholeWord: false,
        kinds: [],
      ),
    );
    await tester.pump();
    expect(controller.matches, hasLength(2), reason: 'HOUSE is not house');

    controller.search(
      const FindQuery(
        text: 'house',
        caseSensitive: false,
        wholeWord: true,
        kinds: [],
      ),
    );
    await tester.pump();
    expect(
      controller.matches,
      hasLength(3),
      reason: 'all three sit against non-word characters',
    );

    controller.search(
      const FindQuery(
        text: 'hous',
        caseSensitive: false,
        wholeWord: true,
        kinds: [],
      ),
    );
    await tester.pump();
    expect(controller.matches, isEmpty, reason: '"hous" is inside a word');

    // Restricted to one element type.
    controller.search(
      const FindQuery(
        text: 'house',
        caseSensitive: false,
        wholeWord: false,
        kinds: [BlockKind.action],
      ),
    );
    await tester.pump();
    expect(controller.matches, hasLength(2));

    controller.replaceAll('cabin');
    await tester.pump();
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\nJohn leaves the cabin. The cabin is quiet.\n',
    );

    // One undo takes all of it back, and the untouched slug line comes back from
    // its own bytes.
    controller.undo();
    await tester.pump();
    expect(controller.source, script);
  });

  testWidgets('replacing inside a scene heading keeps it readable', (
    tester,
  ) async {
    final controller = await open(tester, 'INT. HOUSE - DAY\n');
    controller.search(
      const FindQuery(
        text: 'INT.',
        caseSensitive: true,
        wholeWord: false,
        kinds: [],
      ),
    );
    await tester.pump();
    controller.replaceAll('A ROOM IN');
    await tester.pump();

    // The block is still a scene heading, and the serialiser protects it with the
    // marker §4.1 gives it, so nothing is lost either way.
    expect(controller.blocks.single.kind, BlockKind.sceneHeading);
    expect(controller.blocks.single.text, 'A ROOM IN HOUSE - DAY');
    final reopened = EditorController(
      RustDocumentCore.parse(controller.source),
    );
    addTearDown(reopened.dispose);
    expect(reopened.blocks.single.text, 'A ROOM IN HOUSE - DAY');
    expect(reopened.blocks.single.kind, BlockKind.sceneHeading);
  });

  // --- suggestions -------------------------------------------------------

  testWidgets('an existing cue is suggested but never applied', (tester) async {
    final controller = await open(tester, 'JOHN\nHello.\n\nAction.\n');
    final last = controller.blocks.last;
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: last.id, offsetUtf16: 0),
        focus: DocPosition(block: last.id, offsetUtf16: last.text.length),
      ),
    );
    await type(tester, controller, 'JOHN');
    await tester.pump();

    expect(controller.characterSuggestion, 'JOHN');
    expect(
      controller.blocks.last.kind,
      BlockKind.action,
      reason: 'a suggestion is not a change',
    );
    expect(find.byKey(const Key('tab-hint')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('tab-hint'))).data,
      'Tab: Character — JOHN',
    );

    // Tab is what accepts it.
    await press(tester, LogicalKeyboardKey.tab);
    expect(controller.blocks.last.kind, BlockKind.character);
  });

  // --- Escape ------------------------------------------------------------

  testWidgets('Escape closes each panel and never changes the document', (
    tester,
  ) async {
    const script = 'INT. HOUSE - DAY\n\nJohn enters.\n';
    final controller = await open(tester, script);

    await press(tester, LogicalKeyboardKey.keyF, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Find'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Find'), findsNothing);
    expect(controller.source, script);

    await press(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Element or command'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Element or command'), findsNothing);
    expect(controller.source, script);

    // With no panel open it collapses the selection, and that is all.
    controller.selectAll();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.escape);
    expect(controller.hasSelection, isFalse);
    expect(controller.source, script);
  });
}
