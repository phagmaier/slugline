// Phase 2's integration proofs, against the real `libslugline_bridge.so`.
//
// These live in `integration_test/` because they load the built library out of
// the bundle; `flutter test` (the CI unit-test step) does not run them. Run with:
//
//     flutter test integration_test/editor_test.dart -d linux
//
// The widget tests in `test/editor/` cover the same editor against a double that
// does list surgery. What only these can prove is that the whole chain agrees:
// keystroke → EditCommand → UTF-16 conversion → document → patch → Fountain.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Core.init();
  });

  Future<EditorController> open(WidgetTester tester, DocumentCore core) async {
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

  testWidgets(
    'typing 500 characters produces exactly those characters in the core',
    (tester) async {
      final controller = await open(tester, RustDocumentCore.create());

      // 500 characters of ordinary prose, with the awkward ones a real script has:
      // an accent, CJK, and an astral-plane emoji, so that every keystroke after
      // them is at an offset the two sides have to agree about (§2.4).
      const unit = 'John enters the café. 日本 🎬 ';
      final typed = StringBuffer();
      while (typed.length + unit.length <= 500) {
        typed.write(unit);
      }
      while (typed.length < 500) {
        typed.write('.');
      }
      final expected = typed.toString();
      expect(expected.length, 500, reason: 'UTF-16 code units, as Dart counts');

      for (final character in expected.characters) {
        controller.insertText(character);
      }
      await tester.pump();

      expect(controller.blocks.length, 1);
      expect(controller.blocks.single.text, expected);
      // And what the core would write out is that text and one newline.
      expect(controller.source, '$expected\n');
    },
  );

  testWidgets('the app invokes Rust pagination and displays its diagnostics', (
    tester,
  ) async {
    final core = RustDocumentCore.parse(
      'INT. ROOM - DAY\n\n'
      'A deliberately long action paragraph that wraps across several lines '
      'and gives the debug paginator enough material to show page boundaries.\n\n'
      'JOHN\n'
      'This deliberately long speech repeats enough words to cross the short '
      'debug page and make continuation furniture visible in the bridge result. '
      'More words follow so the paginator must place the block on another page '
      'instead of fitting all of it beside the character cue.\n',
    );
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          title: 'Pagination proof',
          onClosed: () async {},
        ),
      ),
    );

    await tester.tap(find.byTooltip('Pagination debug'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Pagination debug'), findsOneWidget);
    final report = tester.widget<SelectableText>(
      find.byKey(const Key('pagination-debug-report')),
    );
    final text = report.data!;
    expect(text, contains('DIAGNOSTIC ONLY — not the Phase 7 preview'));
    expect(text, contains('status: CURRENT'));
    expect(text, contains('fixed-point iterations:'));
    expect(text, contains('========== PAGE 1 =========='));
    expect(text, contains('block='));
    expect(text, contains('continued'));
    expect(text, contains('more'));
  });

  testWidgets(
    'the reference fixture gives every hard line its own visual row',
    (tester) async {
      final source = File(
        '../testdata/reference-feature.fountain',
      ).readAsStringSync();
      final controller = await open(tester, RustDocumentCore.parse(source));
      final multiline = <int>[];

      for (
        var blockIndex = 0;
        blockIndex < controller.blocks.length;
        blockIndex++
      ) {
        final block = controller.blocks[blockIndex];
        if (!block.text.contains('\n')) continue;
        multiline.add(blockIndex);
        final lines = controller.layout.linesOf(blockIndex);
        expect(
          lines.length,
          greaterThanOrEqualTo('\n'.allMatches(block.text).length + 1),
        );
        for (final line in lines) {
          expect(
            block.text.substring(line.start, line.end),
            isNot(contains('\n')),
            reason: 'a one-row paint slice must contain no hard newline',
          );
        }
      }

      expect(
        multiline,
        isNotEmpty,
        reason: 'the fixture must exercise this path',
      );
      for (var i = 1; i < controller.blocks.length; i++) {
        expect(
          controller.layout.firstRowOf(i),
          greaterThanOrEqualTo(controller.layout.endRowOf(i - 1)),
          reason: 'block $i must start below the preceding visual rows',
        );
      }
    },
  );

  testWidgets('setting every element type by hand keeps the text exactly', (
    tester,
  ) async {
    final controller = await open(tester, RustDocumentCore.create());

    Future<void> type(String text) async {
      controller.insertText(text);
      await tester.pump();
    }

    Future<void> enter() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    // The explicit path: every type set by hand, which is what the element
    // selector and `Ctrl+<digit>` do. `writing_test.dart` covers the same scene
    // written the way §Phase 3 intends, with the types inferred and Tab.
    await type('INT. HOUSE - DAY');
    controller.setKind(BlockKind.sceneHeading);
    await enter();
    controller.setKind(BlockKind.action);
    await type('John enters, holding a letter.');
    await enter();
    controller.setKind(BlockKind.character);
    await type('JOHN');
    await enter();
    controller.setKind(BlockKind.dialogue);
    await type('It came.');
    await tester.pump();

    expect(controller.blocks.map((block) => block.kind).toList(), [
      BlockKind.sceneHeading,
      BlockKind.action,
      BlockKind.character,
      BlockKind.dialogue,
    ]);
    // Not a character of the text moved when the types changed (§13's
    // `element_change_preserves_text`).
    expect(controller.blocks.map((block) => block.text).toList(), [
      'INT. HOUSE - DAY',
      'John enters, holding a letter.',
      'JOHN',
      'It came.',
    ]);
    // Every one of these was pinned by hand, so every one is written in its
    // forced form (§4.1) — including the `!` on an Action that would have read
    // as Action anyway. That is what `forced = true` means, and §Phase 3 asks
    // for it: it is the record that a human, not the editor, chose this.
    expect(
      controller.source,
      '.INT. HOUSE - DAY\n\n!John enters, holding a letter.\n\n@JOHN\nIt came.\n',
    );
  });

  testWidgets('undo unwinds a run of typing and puts the caret back', (
    tester,
  ) async {
    final controller = await open(tester, RustDocumentCore.parse('Action.\n'));
    final block = controller.blocks.single.id;
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: block, offsetUtf16: 7),
        focus: DocPosition(block: block, offsetUtf16: 7),
      ),
    );

    for (final character in ' And more.'.characters) {
      controller.insertText(character);
    }
    await tester.pump();
    expect(controller.blocks.single.text, 'Action. And more.');

    controller.undo();
    await tester.pump();

    // §3.4: one run of typing, one undo — and the caret lands where the run
    // started, not where it ended.
    expect(controller.blocks.single.text, 'Action.');
    expect(controller.selection.focus.offsetUtf16, 7);
    expect(controller.source, 'Action.\n');
  });

  testWidgets('an offset inside an emoji never reaches the core', (
    tester,
  ) async {
    final controller = await open(tester, RustDocumentCore.parse('a🎬b\n'));
    final block = controller.blocks.single.id;
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: block, offsetUtf16: 3),
        focus: DocPosition(block: block, offsetUtf16: 3),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    // The whole emoji goes; nothing was rounded, and nothing was refused.
    expect(controller.blocks.single.text, 'ab');
    expect(controller.lastRejection, isNull);
  });

  testWidgets('a boneyard comment refuses to be edited and says why', (
    tester,
  ) async {
    final controller = await open(
      tester,
      RustDocumentCore.parse('/* hidden */\n\nAction.\n'),
    );
    expect(controller.blocks.first.readOnly, isTrue);

    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: controller.blocks.first.id, offsetUtf16: 3),
        focus: DocPosition(block: controller.blocks.first.id, offsetUtf16: 3),
      ),
    );
    controller.insertText('x');
    await tester.pump();

    expect(controller.lastRejection, EditRejection.notEditable);
    expect(controller.source, '/* hidden */\n\nAction.\n');
  });

  testWidgets('copying a scene and pasting it produces the same Fountain', (
    tester,
  ) async {
    const script = 'INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\nHello.\n';
    final controller = await open(tester, RustDocumentCore.parse(script));

    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: controller.blocks.first.id, offsetUtf16: 0),
        focus: DocPosition(
          block: controller.blocks.last.id,
          offsetUtf16: controller.blocks.last.text.length,
        ),
      ),
    );
    final copied = controller.selectedText();
    expect(copied, script);

    // Paste it at the end of the script; the second copy must read as the same
    // elements as the first.
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(
          block: controller.blocks.last.id,
          offsetUtf16: controller.blocks.last.text.length,
        ),
        focus: DocPosition(
          block: controller.blocks.last.id,
          offsetUtf16: controller.blocks.last.text.length,
        ),
      ),
    );
    await Clipboard.setData(ClipboardData(text: copied!));
    await controller.paste();
    await tester.pump();

    final kinds = controller.blocks.map((block) => block.kind).toList();
    expect(kinds, [
      BlockKind.sceneHeading,
      BlockKind.action,
      BlockKind.character,
      BlockKind.dialogue,
      BlockKind.sceneHeading,
      BlockKind.action,
      BlockKind.character,
      BlockKind.dialogue,
    ]);
  });
}
