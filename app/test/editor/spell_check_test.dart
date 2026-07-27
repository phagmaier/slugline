import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/spell_dialog.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

const _language = SpellLanguage(
  code: 'en_US',
  label: 'English (United States)',
);

FakeCore _enabled(String text) {
  final core = FakeCore.single(BlockKind.action, text);
  core.spellStatusData = const SpellStatus(
    enabled: true,
    language: 'en_US',
    languages: [_language],
    message: 'Checking with English (United States).',
  );
  return core;
}

Misspelling _misspelling(int block, String word, int start) => Misspelling(
  block: block,
  startUtf16: start,
  endUtf16: start + word.length,
  word: word,
);

Future<void> _finishInitialCheck(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  testWidgets('checking and underlining never modify the script', (
    tester,
  ) async {
    final core = _enabled('wurld');
    core.spellings[1] = [_misspelling(1, 'wurld', 0)];
    final controller = await pumpEditor(tester, core);
    await _finishInitialCheck(tester);

    expect(controller.misspellingsFor(1), hasLength(1));
    expect(controller.source, 'wurld');
    expect(core.commands, isEmpty, reason: 'a spell result is paint-only');
  });

  testWidgets('changed blocks are checked only after the Dart debounce', (
    tester,
  ) async {
    final core = _enabled('word');
    final controller = await pumpEditor(tester, core);
    await _finishInitialCheck(tester);
    final initialChecks = core.spellChecks;

    caretAt(controller, 0, 4);
    controller.insertText('x');
    await tester.pump(const Duration(milliseconds: 299));
    expect(core.spellChecks, initialChecks);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(core.spellChecks, initialChecks + 1);
  });

  testWidgets('a 120-page background sweep does not hold up an edit', (
    tester,
  ) async {
    final blocks = [
      // Twenty-five short screenplay elements per page is deliberately
      // conservative: this is a 120-page/3,000-block sweep.
      for (var id = 1; id <= 3000; id++)
        BlockView(
          id: id,
          kind: BlockKind.action,
          sectionLevel: 0,
          text: 'line $id',
          forced: false,
          dual: false,
          readOnly: false,
        ),
    ];
    final core = FakeCore(blocks)
      ..spellStatusData = const SpellStatus(
        enabled: true,
        language: 'en_US',
        languages: [_language],
        message: 'Checking.',
      )
      ..spellCheckDelay = const Duration(milliseconds: 1);
    final controller = EditorController(core);

    // The sweep has started, but the synchronous keystroke path remains free.
    await tester.pump();
    controller.insertText('X');
    expect(controller.blocks.first.text, 'Xline 1');
    expect(core.commands, hasLength(1));
    expect(
      core.spellChecks,
      lessThan(3000),
      reason: 'the sweep is asynchronous rather than a constructor/edit cost',
    );
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('misspelling underlines are painted in the error colour', (
    tester,
  ) async {
    final core = _enabled('wurld');
    core.spellings[1] = [_misspelling(1, 'wurld', 0)];
    await pumpEditor(tester, core);
    await _finishInitialCheck(tester);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('editor paint')),
    );
    final image = await tester.runAsync(boundary.toImage);
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final pixels = bytes!.buffer.asUint8List();
    var errorPixels = 0;
    for (var offset = 0; offset < pixels.length; offset += 4) {
      if (pixels[offset] > 150 &&
          pixels[offset + 1] < 130 &&
          pixels[offset + 2] < 130 &&
          pixels[offset + 3] > 0) {
        errorPixels++;
      }
    }
    expect(errorPixels, greaterThan(0));
  });

  testWidgets('the context menu exposes every explicit Phase 9 action', (
    tester,
  ) async {
    final core = _enabled('wurld');
    core.spellings[1] = [_misspelling(1, 'wurld', 0)];
    await pumpEditor(tester, core);
    await _finishInitialCheck(tester);

    final topLeft = tester.getTopLeft(find.byType(EditorSurface));
    final painter = TextPainter(
      text: const TextSpan(
        text: 'MMMMMMMMMM',
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: ['Courier New', 'DejaVu Sans Mono'],
          fontSize: 15,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final advance = painter.width / 10;
    final pageLeft = (900 - 60 * advance) / 2;
    await tester.tapAt(
      topLeft + Offset(pageLeft + advance * 2, 38),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('wurld-suggestion'), findsOneWidget);
    expect(find.text('Replace…'), findsOneWidget);
    expect(find.text('Ignore Once'), findsOneWidget);
    expect(find.text('Ignore All'), findsOneWidget);
    expect(find.text('Add to Personal Dictionary'), findsOneWidget);
    expect(find.text('Add to Project Dictionary'), findsOneWidget);

    await tester.tap(find.text('Ignore Once'));
    await tester.pumpAndSettle();
    expect(core.spellActions, contains(('once', 'wurld')));
    expect(core.commands, isEmpty);
  });

  testWidgets('replacement is the only spell action that edits text', (
    tester,
  ) async {
    final core = _enabled('wurld');
    final misspelling = _misspelling(1, 'wurld', 0);
    core.spellings[1] = [misspelling];
    final controller = await pumpEditor(tester, core);
    await _finishInitialCheck(tester);

    controller.ignoreMisspellingAll(misspelling);
    await controller.addToPersonalDictionary(misspelling);
    await controller.addToProjectDictionary(misspelling);
    expect(core.commands, isEmpty);
    expect(controller.source, 'wurld');

    controller.replaceMisspelling(misspelling, 'world');
    expect(core.commands.single, isA<EditCommand_ReplaceText>());
    expect(controller.source, 'world');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'the selector clearly reports that no dictionaries are installed',
    (tester) async {
      final core = FakeCore.single(BlockKind.action, 'text')
        ..spellStatusData = const SpellStatus(
          enabled: true,
          language: null,
          languages: [],
          message: 'No Hunspell dictionaries were found.',
        );
      final controller = EditorController(core);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SpellDialog(controller: controller)),
        ),
      );

      expect(find.byKey(const ValueKey('spell unavailable')), findsOneWidget);
      expect(find.textContaining('No Hunspell dictionaries'), findsOneWidget);
    },
  );

  testWidgets('spell checking can be disabled entirely', (tester) async {
    final core = _enabled('text');
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SpellDialog(controller: controller)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('spell enabled')));
    await tester.tap(find.byKey(const ValueKey('apply spelling')));
    await tester.pumpAndSettle();

    expect(core.spellStatusData.enabled, isFalse);
    expect(controller.spellStatus.enabled, isFalse);
  });
}
