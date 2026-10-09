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

import 'dart:convert';
import 'dart:io';
import 'managed_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/pagination_debug_dialog.dart';
import 'package:slugline/editor/go_to_page_dialog.dart';

// Native bridge work can be pending even when no Flutter frame is scheduled.
// Synchronize script switches with the visible document and its input focus.
Future<void> _waitForScript(WidgetTester tester, String path) async {
  final deadline = tester.binding.clock.fromNowBy(const Duration(seconds: 10));
  while (true) {
    final pages = find.byType(EditorPage);
    final surfaces = find.byType(EditorSurface);
    if (pages.evaluate().length == 1 && surfaces.evaluate().length == 1) {
      final current = tester.widget<EditorPage>(pages).controller.core.path;
      final focused = tester
          .widget<EditorSurface>(surfaces)
          .focusNode!
          .hasFocus;
      if (current == path && focused) return;
    }
    if (tester.binding.clock.now().isAfter(deadline)) {
      throw TestFailure(
        'The editor did not open and focus $path; '
        'focus: ${FocusManager.instance.primaryFocus}',
      );
    }
    await tester.pump();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  late ManagedFixtures managed;
  var fixtureNumber = 0;
  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('slugline-writing-');
    managed = ManagedFixtures(scratch);
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
    final file = managed.path('writing-${fixtureNumber++}.fountain');
    File(file).writeAsStringSync(source ?? '');
    final controller = EditorController(
      (await Core.instance.openDocument(file))!,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          navigatorVisible: true,
          onShowShortcuts: () =>
              ShortcutsDialog.show(tester.element(find.byType(EditorPage))),
        ),
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

  Future<void> omissionCommand(WidgetTester tester, String label) async {
    await press(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Element or command'),
      label,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, label));
    await tester.pumpAndSettle();
  }

  for (final selected in ['café', '😀 café']) {
    testWidgets(
      'native X7 exact partial $selected Save reopen and directed history',
      (tester) async {
        final source =
            '\uFEFF!Untouched.\t  \r\n\r\nJOHN\r\nHello $selected friend.\r\n';
        final controller = await open(tester, source);
        final body = controller.blocks.last;
        final before = DocSelection(
          anchor: DocPosition(block: body.id, offsetUtf16: 6 + selected.length),
          focus: DocPosition(block: body.id, offsetUtf16: 6),
        );
        controller.setSelection(before);
        await omissionCommand(tester, 'Omit selection');
        expect(controller.lastRejection, isNull);
        final omittedSource = controller.source;
        final comment = controller.selection;
        expect(controller.focusedBlock.kind, BlockKind.opaque);
        expect(controller.blocks.last.kind, BlockKind.action);
        expect(controller.blocks.last.text, ' friend.');
        final decoded = RustDocumentCore.parse(omittedSource);
        expect(
          decoded
              .blocks(0, decoded.blockCount)
              .map((b) => (b.kind, b.text, b.dual)),
          controller.blocks.map((b) => (b.kind, b.text, b.dual)),
        );
        decoded.close();
        final file = controller.core.path!;
        expect(await controller.core.save(), isA<SaveOutcome_Saved>());
        final bytes = File(file).readAsBytesSync();
        expect(bytes, utf8.encode('\uFEFF$omittedSource'));
        expect(controller.selection, comment);
        controller.undo();
        expect(controller.selection, before);
        expect(controller.source, source.substring(1));
        expect(controller.core.undo(), isNull);
        controller.redo();
        expect(controller.selection, comment);
        expect(controller.source, omittedSource);
        final reopenedFile = managed.path('reopen-${selected.length}.fountain');
        File(reopenedFile).writeAsBytesSync(bytes);
        final reopenedCore = (await Core.instance.openDocument(reopenedFile))!;
        final reopened = EditorController(reopenedCore);
        addTearDown(reopened.dispose);
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: reopened)),
        );
        final opaque = reopened.blocks.firstWhere(
          (b) => b.kind == BlockKind.opaque,
        );
        reopened.setSelection(
          DocSelection(
            anchor: DocPosition(block: opaque.id, offsetUtf16: 0),
            focus: DocPosition(block: opaque.id, offsetUtf16: 0),
          ),
        );
        final restoreBefore = reopened.selection;
        await omissionCommand(tester, 'Restore omitted text');
        expect(reopened.lastRejection, isNull);
        expect(reopened.blocks.last.kind, BlockKind.dialogue);
        expect(reopened.blocks.last.text, 'Hello $selected friend.');
        expect(reopened.source, source.substring(1));
        expect(await reopened.core.save(), isA<SaveOutcome_Saved>());
        expect(File(reopenedFile).readAsBytesSync(), utf8.encode(source));
        reopened.undo();
        expect(reopened.selection, restoreBefore);
        expect(reopened.source, omittedSource);
        expect(reopened.core.undo(), isNull);
        reopened.redo();
        expect(reopened.source, source.substring(1));
      },
    );
  }

  testWidgets(
    'native X7 foreign boneyards and changed or corrupt witnesses refuse safely',
    (tester) async {
      for (final source in [
        '/* Hidden. */\n',
        '/* outer /* inner */ end */\n',
        '/* unfinished to EOF',
        '/* */\n',
      ]) {
        final controller = await open(tester, source);
        await omissionCommand(tester, 'Restore omitted text');
        expect(controller.lastRejection, isNull);
        expect(controller.source, isNot(source));
        controller.undo();
        expect(controller.source, source);
        expect(controller.core.undo(), isNull);
        controller.redo();
      }
      final controller = await open(tester, 'JOHN\nHello café friend.\n');
      final body = controller.blocks.last.id;
      controller.setSelection(
        DocSelection(
          anchor: DocPosition(block: body, offsetUtf16: 10),
          focus: DocPosition(block: body, offsetUtf16: 6),
        ),
      );
      await omissionCommand(tester, 'Omit selection');
      final comment = controller.selection;
      final right = controller.blocks.last.id;
      controller.jumpToBlock(right);
      controller.insertText('Changed ');
      controller.setSelection(comment);
      final changed = controller.source;
      final changedBlocks = controller.blocks
          .map((b) => (b.id, b.kind, b.text, b.forced, b.dual))
          .toList();
      await omissionCommand(tester, 'Restore omitted text');
      expect(controller.lastRejection, EditRejection.cannotRestoreOmission);
      expect(controller.source, changed);
      expect(
        controller.blocks.map((b) => (b.id, b.kind, b.text, b.forced, b.dual)),
        changedBlocks,
      );
      for (final header in ['Slugline omission v9', 'xlugline omission v2']) {
        final corrupt = changed.replaceFirst('Slugline omission v2', header);
        final damaged = await open(tester, corrupt);
        damaged.jumpToBlock(
          damaged.blocks.firstWhere((b) => b.kind == BlockKind.opaque).id,
        );
        final before = damaged.source;
        await omissionCommand(tester, 'Restore omitted text');
        expect(damaged.lastRejection, EditRejection.cannotRestoreOmission);
        expect(damaged.source, before);
        expect(damaged.core.undo(), isNull);
      }
      final whitespace = await open(tester, '.INT. ROOM - DAY\n\nOutside.\n');
      final heading = whitespace.blocks.first.id;
      whitespace.setSelection(
        DocSelection(
          anchor: DocPosition(block: heading, offsetUtf16: 5),
          focus: DocPosition(block: heading, offsetUtf16: 9),
        ),
      );
      await omissionCommand(tester, 'Omit selection');
      final omittedWhitespace = whitespace.selection;
      whitespace.setSelection(
        DocSelection(
          anchor: DocPosition(block: heading, offsetUtf16: 4),
          focus: DocPosition(block: heading, offsetUtf16: 5),
        ),
      );
      whitespace.insertText('');
      whitespace.setSelection(omittedWhitespace);
      final beforeRefusal = whitespace.source;
      await omissionCommand(tester, 'Restore omitted text');
      expect(whitespace.lastRejection, EditRejection.cannotRestoreOmission);
      expect(whitespace.source, beforeRefusal);
      expect(whitespace.selection, omittedWhitespace);
      whitespace.undo();
      expect(whitespace.blocks.first.text, 'INT. ');
      final changedSaved = whitespace.source.replaceFirst('INT. \n', 'INT.\n');
      expect(changedSaved, isNot(whitespace.source));
      final reopenedWhitespace = await open(tester, changedSaved);
      reopenedWhitespace.jumpToBlock(
        reopenedWhitespace.blocks
            .firstWhere((b) => b.kind == BlockKind.opaque)
            .id,
      );
      final reopenedSelection = reopenedWhitespace.selection;
      await omissionCommand(tester, 'Restore omitted text');
      expect(
        reopenedWhitespace.lastRejection,
        EditRejection.cannotRestoreOmission,
      );
      expect(reopenedWhitespace.source, changedSaved);
      expect(reopenedWhitespace.selection, reopenedSelection);
      expect(reopenedWhitespace.core.undo(), isNull);
      await press(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      for (final label in [
        'Omit selection',
        'Omit scene',
        'Restore omitted text',
      ]) {
        await tester.scrollUntilVisible(
          find.text('Ctrl+K → $label'),
          200,
          scrollable: find.descendant(
            of: find.byType(ShortcutsDialog),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Ctrl+K → $label'), findsOneWidget);
      }
    },
  );

  for (final width in [1100.0, 800.0]) {
    testWidgets(
      'native X5 hierarchy, current lengths, jumps and reorder at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = await open(
          tester,
          'Title: Outline cover\n\n= Opening\n\n# Act One\n\n= Act summary\n\n'
          '### Sequence\n\nINT. HOUSE - DAY\n\nAction.\n\n= House summary\n\n'
          'EXT. STREET - NIGHT\n\nMore action.\n',
        );
        final core = controller.core;
        final source = controller.source;
        final view = core.navigator();
        expect(view.outline.map((node) => node.text), [
          'Opening',
          'Act One',
          'Act summary',
          'Sequence',
          'INT. HOUSE - DAY',
          'House summary',
          'EXT. STREET - NIGHT',
        ]);
        expect(view.outline.map((node) => node.depth), [0, 0, 1, 1, 2, 3, 2]);
        final first = view.scenes.first.block;
        final second = view.scenes.last.block;
        final synopsis = view.outline.firstWhere(
          (node) => node.text == 'House summary',
        );
        const setup = PageSetup(
          paper: PaperSize.usLetter,
          sceneNumbers: SceneNumbers.off,
          boldSceneHeadings: false,
          numberFirstPage: false,
          debugLinesPerPage: null,
        );
        final pagination = switch (await (core as ScreenplayOutput).paginate(
          setup,
        )) {
          PaginationOutcome_Current(:final pagination) => pagination,
          final other => throw TestFailure('$other'),
        };
        expect(pagination.titlePage, isNotNull);
        Future<void> showNavigator() async {
          if (width < 900) {
            await press(tester, LogicalKeyboardKey.keyJ, control: true);
            await tester.pumpAndSettle();
          }
        }

        await showNavigator();
        for (final scene in pagination.scenes) {
          final label = 'p. ${scene.page} · ${scene.lengthEighths}/8 p';
          final deadline = tester.binding.clock.fromNowBy(
            const Duration(seconds: 10),
          );
          while (find.text(label).evaluate().isEmpty) {
            if (tester.binding.clock.now().isAfter(deadline)) {
              throw TestFailure('Missing current label $label');
            }
            await tester.pump();
          }
          final text = tester.widget<Text>(
            find.byKey(ValueKey('scene pagination ${scene.block}')),
          );
          expect(text.data, label);
        }
        expect(find.text('Act One'), findsOneWidget);
        expect(find.text('House summary'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('navigator filter')),
          'house summary',
        );
        await tester.pump();
        expect(find.text('Act One'), findsOneWidget);
        expect(find.text('HOUSE'), findsOneWidget);
        expect(find.text('STREET'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          controller.selection.focus,
          DocPosition(block: synopsis.block, offsetUtf16: 0),
        );
        expect(controller.source, source);
        await showNavigator();
        if (width >= 900) {
          await tester.tap(find.byTooltip('Clear filter'));
          await tester.pumpAndSettle();
        } else {
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('navigator filter')),
                )
                .controller!
                .text,
            isEmpty,
            reason: 'reopening the dismissed drawer creates a fresh filter',
          );
        }
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('navigator scene $second'))),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move scene up'));
        await tester.pumpAndSettle();
        expect(core.navigator().scenes.map((scene) => scene.block), [
          second,
          first,
        ]);
        expect(
          core
              .navigator()
              .outline
              .firstWhere((node) => node.block == synopsis.block)
              .parent,
          first,
        );
        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.source, source);
        expect(
          core.navigator().outline.map(
            (node) =>
                (node.block, node.kind, node.text, node.parent, node.depth),
          ),
          view.outline.map(
            (node) =>
                (node.block, node.kind, node.text, node.parent, node.depth),
          ),
        );
        expect(
          core.navigator().scenes.map((scene) => scene.block),
          view.scenes.map((scene) => scene.block),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'native inline shortcuts preserve printed wraps and directional history',
    (tester) async {
      List<(int, String)> printedRows(EditorController controller) => [
        for (final line in controller.layout.linesOf(0))
          (line.columns, line.textIn(controller.focusedBlock.text)),
      ];
      final text = 'plain 🎬 text. ${List.filled(12, 'unchanged').join(' ')}';
      final source = '!$text\n';
      for (final (key, marker, face) in [
        (LogicalKeyboardKey.keyB, '**', InlineStyle.bold),
        (LogicalKeyboardKey.keyI, '*', InlineStyle.italic),
        (LogicalKeyboardKey.keyU, '_', InlineStyle.underline),
      ]) {
        for (final reverse in [false, true]) {
          final controller = await open(tester, source);
          final id = controller.blocks.single.id;
          final widths = printedRows(controller);
          expect(widths.length, greaterThan(1));
          final before = DocSelection(
            anchor: DocPosition(block: id, offsetUtf16: reverse ? 8 : 6),
            focus: DocPosition(block: id, offsetUtf16: reverse ? 6 : 8),
          );
          final after = DocSelection(
            anchor: DocPosition(
              block: id,
              offsetUtf16: (reverse ? 8 : 6) + marker.length,
            ),
            focus: DocPosition(
              block: id,
              offsetUtf16: (reverse ? 6 : 8) + marker.length,
            ),
          );
          final formatted = text.replaceFirst('🎬', '$marker🎬$marker');
          controller.setSelection(before);
          await press(tester, key, control: true);
          expect(controller.focusedBlock.text, formatted);
          expect(controller.focusedBlock.id, id);
          expect(controller.focusedBlock.kind, BlockKind.action);
          expect(controller.focusedBlock.forced, isTrue);
          expect(printedRows(controller), widths);
          expect(controller.selection, after);
          final selected = controller.focusedBlock.inlineRuns.singleWhere(
            (run) =>
                !run.hidden &&
                run.startUtf16 == 6 + marker.length &&
                run.endUtf16 == 8 + marker.length,
          );
          expect(
            (selected.bold, selected.italic, selected.underline),
            (
              face == InlineStyle.bold,
              face == InlineStyle.italic,
              face == InlineStyle.underline,
            ),
          );
          await press(tester, LogicalKeyboardKey.keyZ, control: true);
          expect(controller.focusedBlock.text, text);
          expect(controller.selection, before);
          expect(controller.core.source(), source);
          expect(printedRows(controller), widths);
          expect(
            controller.core.undo(),
            isNull,
            reason: 'a formatting gesture must be exactly one undo step',
          );
          await press(tester, LogicalKeyboardKey.keyY, control: true);
          expect(controller.focusedBlock.text, formatted);
          expect(controller.selection, after);
          expect(controller.focusedBlock.id, id);
          expect(controller.focusedBlock.kind, BlockKind.action);
          expect(controller.focusedBlock.forced, isTrue);
          expect(printedRows(controller), widths);
          final line = controller.layout.linesOf(0).first;
          controller.placeCaretAt(
            0,
            line.displayColumnAtOffset(6 + marker.length),
          );
          expect(
            controller.selection.focus,
            DocPosition(block: id, offsetUtf16: 6 + marker.length),
          );
        }
      }
    },
  );

  List<BlockKind> kinds(EditorController controller) =>
      controller.blocks.map((block) => block.kind).toList();

  testWidgets(
    'scene palette numbering persists and is one journalled undo step',
    (tester) async {
      const source =
          'Title: Numbering\n\n'
          'INT. CAFÉ 🎬 - DAY #12A#\n\n'
          '!Keep #88# here.\n\n'
          'ALICE\nHello.\n\nBOB ^\nGoodbye.\n\n'
          '.An unusual depot\n\n'
          'EXT. ROAD - NIGHT ##\n';
      final file = File(managed.path('scene-numbering.fountain'))
        ..writeAsStringSync(source);
      var core = (await Core.instance.openDocument(file.path))!;
      var controller = EditorController(core);
      addTearDown(() => core.close());
      addTearDown(() => controller.dispose());
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.tap(find.byType(EditorSurface));
        await tester.pump();
      }

      Future<void> palette(String label) async {
        await press(tester, LogicalKeyboardKey.keyK, control: true);
        await tester.enterText(
          find.widgetWithText(TextField, 'Element or command'),
          label,
        );
        await tester.pump();
        expect(find.text('No matching command'), findsNothing);
        await press(tester, LogicalKeyboardKey.enter);
      }

      Future<List<String>> gutters(SceneNumbers setting) async {
        final pagination = switch (await (core as ScreenplayOutput).paginate(
          PageSetup(
            paper: PaperSize.usLetter,
            sceneNumbers: setting,
            boldSceneHeadings: false,
            numberFirstPage: false,
          ),
        )) {
          PaginationOutcome_Current(:final pagination) => pagination,
          _ => throw StateError('Expected current pagination'),
        };
        return [
          for (final page in pagination.pages)
            for (final line in page.lines)
              if (line.kind == LayoutLineKind.sceneNumberLeft) line.content,
        ];
      }

      await mount();
      final original = List<BlockView>.of(controller.blocks);
      final scenes = original
          .where((b) => b.kind == BlockKind.sceneHeading)
          .toList();
      expect(scenes, hasLength(3));
      expect(await gutters(SceneNumbers.left), ['12A']);
      expect(core.source(), source, reason: 'output never invents numbers');
      await core.save();
      expect(
        file.readAsStringSync(),
        source,
        reason: 'save never invents numbers',
      );
      final before = DocSelection(
        anchor: DocPosition(block: scenes.last.id, offsetUtf16: 4),
        focus: DocPosition(
          block: scenes.first.id,
          offsetUtf16: scenes.first.text.length,
        ),
      );
      controller.setSelection(before);
      final recorded = core.journalState.$1;
      await palette('Number scenes');
      final numbered = controller.source;
      expect(
        controller.blocks
            .where((b) => b.kind == BlockKind.sceneHeading)
            .map((b) => b.text),
        [
          'INT. CAFÉ 🎬 - DAY #1#',
          'An unusual depot #2#',
          'EXT. ROAD - NIGHT ## #3#',
        ],
      );
      final after = controller.selection;
      expect(after.anchor, before.anchor);
      expect(after.focus.offsetUtf16, 'INT. CAFÉ 🎬 - DAY #1#'.length);
      expect(controller.blocks.map((b) => b.id), original.map((b) => b.id));
      for (final block in original.where(
        (b) => b.kind != BlockKind.sceneHeading,
      )) {
        expect(controller.blocks.singleWhere((b) => b.id == block.id), block);
      }
      for (final scene in scenes) {
        final actual = controller.blocks.singleWhere((b) => b.id == scene.id);
        expect(
          (actual.kind, actual.forced, actual.dual),
          (scene.kind, scene.forced, scene.dual),
        );
      }
      expect(core.titlePage().single.value, 'Numbering');
      expect(core.journalState, (recorded + 1, false));
      // Read the real outcome record: all headings are in one patch.
      final journals = Directory(
        '${scratch.path}/state',
      ).listSync(recursive: true).whereType<File>();
      final records = journals
          .where((f) => f.path.endsWith('.log'))
          .map((f) {
            return f
                .readAsLinesSync()
                .map((line) => jsonDecode(line) as Map<String, dynamic>)
                .toList();
          })
          .where(
            (lines) => lines.isNotEmpty && lines.first['script'] == file.path,
          )
          .single;
      expect(records.last['changed'], hasLength(3));
      expect(
        (records.last['changed'] as List).map((b) => b['id']),
        scenes.map((b) => b.id),
      );
      await press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.source, source);
      expect(controller.selection, before);
      expect(core.dirty, isFalse);
      expect(core.undo(), isNull, reason: 'all three headings were one step');
      await press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      expect(controller.source, numbered);
      expect(controller.selection, after);
      expect(await gutters(SceneNumbers.left), ['1', '2', '3']);
      expect(await gutters(SceneNumbers.off), isEmpty);
      expect(
        core.source(),
        numbered,
        reason: 'output preference changes no source',
      );
      for (final setting in [SceneNumbers.left, SceneNumbers.off]) {
        final pdf = '${scratch.path}/scene-numbering-${setting.name}.pdf';
        expect(
          await (core as ScreenplayOutput).exportPdf(
            pdf,
            setup: PageSetup(
              paper: PaperSize.usLetter,
              sceneNumbers: setting,
              boldSceneHeadings: false,
              numberFirstPage: false,
            ),
          ),
          isA<SaveOutcome_Saved>(),
        );
        final extracted = await Process.run('pdftotext', ['-layout', pdf, '-']);
        expect(extracted.exitCode, 0);
        final words = (extracted.stdout as String).split(RegExp(r'\s+'));
        for (final number in ['1', '2', '3']) {
          expect(words.contains(number), setting == SceneNumbers.left);
        }
        expect(extracted.stdout, isNot(contains('#1#')));
        expect(core.source(), numbered);
      }
      expect(await core.save(), isA<SaveOutcome_Saved>());
      final noOpJournal = core.journalState;
      await palette('Number scenes');
      expect(core.dirty, isFalse);
      expect(core.journalState, noOpJournal);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      core.close();
      core = (await Core.instance.openDocument(file.path))!;
      controller = EditorController(core);
      await mount();
      expect(core.source(), numbered);
      expect(await gutters(SceneNumbers.left), ['1', '2', '3']);
      final reopenedScenes = controller.blocks
          .where((b) => b.kind == BlockKind.sceneHeading)
          .toList();
      final removalBefore = DocSelection(
        anchor: DocPosition(block: reopenedScenes.first.id, offsetUtf16: 0),
        focus: DocPosition(
          block: reopenedScenes.last.id,
          offsetUtf16: reopenedScenes.last.text.length,
        ),
      );
      controller.setSelection(removalBefore);
      await palette('Remove scene numbers');
      final removed = controller.source;
      final removalAfter = controller.selection;
      expect(core.journalState, (1, false));
      expect(
        controller.blocks
            .where((b) => b.kind == BlockKind.sceneHeading)
            .map((b) => b.text),
        ['INT. CAFÉ 🎬 - DAY', 'An unusual depot', 'EXT. ROAD - NIGHT ##'],
      );
      expect(await gutters(SceneNumbers.left), isEmpty);
      await press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.source, numbered);
      expect(controller.selection, removalBefore);
      expect(core.undo(), isNull);
      await press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      expect(controller.source, removed);
      expect(controller.selection, removalAfter);
      expect(await core.save(), isA<SaveOutcome_Saved>());
      await palette('Remove scene numbers');
      expect(core.dirty, isFalse);
      expect(core.journalState, (0, false));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      core.close();
      core = (await Core.instance.openDocument(file.path))!;
      controller = EditorController(core);
      expect(core.source(), removed);
      expect(await gutters(SceneNumbers.left), isEmpty);
    },
  );

  for (final pageView in [false, true]) {
    for (final (name, source) in [
      ('empty', ''),
      ('note', '[[Private note.]]\n'),
      (
        'source-only',
        '\uFEFF[[Private note.]]\r\n\r\n'
            '# Private section\r\n\r\n= Private synopsis\r\n\r\n'
            '/* Private boneyard. */\r\n',
      ),
    ]) {
      testWidgets(
        'zero printed pages edit save reopen $name pageView=$pageView',
        (tester) async {
          final file = File(managed.path('zero-pages-$name-$pageView.fountain'))
            ..writeAsStringSync(source);
          final originalBytes = file.readAsBytesSync();
          var core = (await Core.instance.openDocument(file.path))!;
          addTearDown(() => core.close());
          var controller = EditorController(core);
          addTearDown(() => controller.dispose());

          Future<void> mount() async {
            await tester.pumpWidget(
              MaterialApp(
                home: EditorPage(controller: controller, pageView: pageView),
              ),
            );
            await tester.tap(find.byType(EditorSurface));
            final start = controller.blocks.firstWhere(
              (block) => !block.readOnly,
            );
            controller.setSelection(
              DocSelection(
                anchor: DocPosition(block: start.id, offsetUtf16: 0),
                focus: DocPosition(block: start.id, offsetUtf16: 0),
              ),
            );
            await tester.pump();
          }

          Future<void> shows(String label) async {
            final deadline = DateTime.now().add(const Duration(seconds: 10));
            while (find.textContaining(label).evaluate().isEmpty &&
                DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(find.textContaining(label), findsOneWidget);
            expect(tester.takeException(), isNull);
          }

          Future<void> saveReopen(String expected) async {
            final body = expected.startsWith('\uFEFF')
                ? expected.substring(1)
                : expected;
            final diskSource = source.startsWith('\uFEFF')
                ? '\uFEFF$body'
                : body;
            expect(await core.save(), isA<SaveOutcome_Saved>());
            expect(file.readAsBytesSync(), utf8.encode(diskSource));
            final savedBytes = file.readAsBytesSync();
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            core.close();
            core = (await Core.instance.openDocument(file.path))!;
            controller = EditorController(core);
            expect(core.source(), body);
            expect(file.readAsBytesSync(), savedBytes);
            await mount();
          }

          final initialPagination = switch (await (core as ScreenplayOutput)
              .paginate(
                const PageSetup(
                  paper: PaperSize.usLetter,
                  sceneNumbers: SceneNumbers.off,
                  boldSceneHeadings: false,
                  numberFirstPage: false,
                  debugLinesPerPage: null,
                ),
              )) {
            PaginationOutcome_Current(:final pagination) => pagination,
            _ => throw StateError('Expected current pagination'),
          };
          // An empty editable Action gets one blank sheet from Rust; source-only
          // blocks get none. The presentation must follow either snapshot.
          expect(initialPagination.pageCount, name == 'empty' ? 1 : 0);
          final initialLabel = initialPagination.pageCount == 0
              ? 'No printed pages'
              : 'Page 1 of 1';
          await mount();
          await shows(initialLabel);
          expect(await core.save(), isA<SaveOutcome_Saved>());
          expect(file.readAsBytesSync(), originalBytes);
          await saveReopen(source);
          await shows(initialLabel);

          final first = controller.blocks.firstWhere(
            (block) => !block.readOnly,
          );
          controller.setSelection(
            DocSelection(
              anchor: DocPosition(
                block: first.id,
                offsetUtf16: first.text.length,
              ),
              focus: DocPosition(
                block: first.id,
                offsetUtf16: first.text.length,
              ),
            ),
          );
          controller.setKind(BlockKind.note);
          await type(tester, controller, ' Extra private text.');
          await shows('No printed pages');
          final nonPrinting = controller.source;
          controller.setKind(BlockKind.action);
          await shows('Page 1 of 1');
          controller.undo();
          expect(controller.source, nonPrinting);
          await shows('No printed pages');
          controller.redo();
          await shows('Page 1 of 1');
          final printable = controller.source;
          await saveReopen(printable);
          await shows('Page 1 of 1');
          controller.setKind(BlockKind.note);
          await shows('No printed pages');
          final finalSource = controller.source;
          await saveReopen(finalSource);
          await shows('No printed pages');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final pageView in [false, true]) {
    testWidgets('go to page uses real pagination, pageView=$pageView', (
      tester,
    ) async {
      // A continuous page target can already be visible in a tall desktop.
      // Establish an off-screen target before asserting that navigation scrolls.
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source =
          '\uFEFFTitle: Reader notes\r\n\r\n'
          '[[A private opening note.]]\r\n\r\n'
          '${List.generate(150, (line) => 'Action line $line with 🎬.').join('\r\n')}\r\n';
      final file = File(managed.path('go-to-page-$pageView.fountain'))
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
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable && widget.axis == Axis.vertical,
              ),
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
    (BlockKind.note, '[[Seed.]]\n', 0, '[[First 🎬 line.\nSecond line.]]\n'),
  ]) {
    testWidgets(
      'Shift+Enter saves adjacent lines in ${kind.name} and reopens',
      (tester) async {
        final file = File(managed.path('line-break-${kind.name}.fountain'))
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
      final file = File(managed.path('palette.fountain'))
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
      const channel = MethodChannel('slugline/window');
      var pickers = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'chooseFile') throw MissingPluginException();
        pickers++;
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      final alpha = File(managed.path('alpha.fountain'))
        ..writeAsStringSync('Original draft.\n');
      final beta = File(managed.path('beta.fountain'))
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
      await _waitForScript(tester, alpha.path);
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
      expect(find.text('Save changes to alpha?'), findsOneWidget);
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
      await _waitForScript(tester, beta.path);
      expect(current().core.path, beta.path);
      expect(alpha.readAsStringSync(), 'Native unsaved words.\n');
      await press(tester, LogicalKeyboardKey.keyN, control: true);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while ((find.byType(EditorPage).evaluate().isEmpty ||
              current().core.path == beta.path) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final newPath = current().core.path!;
      expect(newPath, isNot(beta.path));
      expect(newPath, startsWith('${scratch.path}/data/library/'));
      expect(File(newPath).existsSync(), isTrue);
      expect(pickers, 0);
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

    // The file uses only necessary markers; Tab still pins the live cue.
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\n'
      'John enters, holding a letter.\n\n'
      'JOHN\n'
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

    expect(controller.source, 'JOHN\nHello.\n\nMARY\nHello yourself.\n');
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

  for (final control in ['Match case', 'Whole word', 'element filter']) {
    testWidgets(
      'Find keyboard after native pointer interaction with $control',
      (tester) async {
        const source =
            'INT. CHECK - DAY\r\n\r\nA river meets another river.\r\n';
        final file = File(
          managed.path('find-focus-${control.replaceAll(' ', '-')}.fountain'),
        )..writeAsStringSync(source);
        final bytes = file.readAsBytesSync();
        final core = (await Core.instance.openDocument(file.path))!;
        addTearDown(core.close);
        final controller = EditorController(core);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(home: EditorPage(controller: controller)),
        );
        await tester.tap(find.byType(EditorSurface));
        controller.moveToDocumentEdge(start: true);
        await tester.pump();
        await press(tester, LogicalKeyboardKey.keyF, control: true);
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Find'), 'river');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(controller.matchIndex, 0);
        expect(controller.matches, hasLength(2));
        if (control == 'element filter') {
          await tester.tap(find.byTooltip('Restrict to an element type'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Action').last);
        } else {
          await tester.tap(find.text(control));
        }
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.enter);
        expect(controller.matchIndex, 1);
        await press(tester, LogicalKeyboardKey.enter, shift: true);
        expect(controller.matchIndex, 0);
        await press(tester, LogicalKeyboardKey.numpadEnter);
        expect(controller.matchIndex, 1);
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(FindBar), findsNothing);
        expect(
          tester
              .widget<EditorSurface>(find.byType(EditorSurface))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        expect(controller.source, source);
        expect(core.dirty, isFalse);
        expect(core.journalState, (0, false));
        expect(file.readAsBytesSync(), bytes);
        expect(await core.save(), isA<SaveOutcome_Saved>());
        expect(file.readAsBytesSync(), bytes);
        await tester.pumpWidget(const SizedBox.shrink());
        core.close();
        final reopened = (await Core.instance.openDocument(file.path))!;
        expect(reopened.source(), source);
        reopened.close();
      },
    );
  }

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
