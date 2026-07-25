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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Core.init();
  });

  Future<EditorController> open(WidgetTester tester, DocumentCore core) async {
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EditorSurface(controller: controller)),
    ));
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    return controller;
  }

  testWidgets('typing 500 characters produces exactly those characters in the core',
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
  });

  testWidgets('a scene typed with the keyboard reads back as a screenplay',
      (tester) async {
    final controller = await open(tester, RustDocumentCore.create());

    Future<void> type(String text) async {
      controller.insertText(text);
      await tester.pump();
    }

    Future<void> enter() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    // Everything typed is Action until something says otherwise: **Phase 2 has
    // no element inference.** "Automatic detection on the current block as you
    // type" and the shortcuts that reach `setKind` are Phase 3's list; what this
    // proves is that the command path underneath them already works.
    await type('INT. HOUSE - DAY');
    controller.setKind(BlockKind.sceneHeading);
    await enter();
    // Enter carries the kind of the block it split, so the new block has to be
    // told what it is. Phase 3's Enter table is what stops that being manual.
    controller.setKind(BlockKind.action);
    await type('John enters, holding a letter.');
    await enter();
    controller.setKind(BlockKind.character);
    await type('JOHN');
    await enter();
    controller.setKind(BlockKind.dialogue);
    await type('It came.');
    await tester.pump();

    expect(
      controller.blocks.map((block) => block.kind).toList(),
      [
        BlockKind.sceneHeading,
        BlockKind.action,
        BlockKind.character,
        BlockKind.dialogue,
      ],
    );
    // Not a character of the text moved when the types changed (§13's
    // `element_change_preserves_text`), and the markers are the forced forms of
    // §4.1: an explicit type is a pinned one.
    expect(
      controller.blocks.map((block) => block.text).toList(),
      [
        'INT. HOUSE - DAY',
        'John enters, holding a letter.',
        'JOHN',
        'It came.',
      ],
    );
    // Every one of these was pinned by hand, so every one is written in its
    // forced form (§4.1) — including the `!` on an Action that would have read
    // as Action anyway. Whether choosing "Action" from a menu should pin it is
    // Phase 3's question; the round trip is right either way.
    expect(
      controller.source,
      '.INT. HOUSE - DAY\n\n!John enters, holding a letter.\n\n@JOHN\nIt came.\n',
    );
  });

  testWidgets('undo unwinds a run of typing and puts the caret back',
      (tester) async {
    final controller = await open(tester, RustDocumentCore.parse('Action.\n'));
    final block = controller.blocks.single.id;
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: block, offsetUtf16: 7),
      focus: DocPosition(block: block, offsetUtf16: 7),
    ));

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

  testWidgets('an offset inside an emoji never reaches the core', (tester) async {
    final controller = await open(tester, RustDocumentCore.parse('a🎬b\n'));
    final block = controller.blocks.single.id;
    controller.setSelection(DocSelection(
      anchor: DocPosition(block: block, offsetUtf16: 3),
      focus: DocPosition(block: block, offsetUtf16: 3),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    // The whole emoji goes; nothing was rounded, and nothing was refused.
    expect(controller.blocks.single.text, 'ab');
    expect(controller.lastRejection, isNull);
  });

  testWidgets('a boneyard comment refuses to be edited and says why',
      (tester) async {
    final controller =
        await open(tester, RustDocumentCore.parse('/* hidden */\n\nAction.\n'));
    expect(controller.blocks.first.readOnly, isTrue);

    controller.setSelection(DocSelection(
      anchor: DocPosition(block: controller.blocks.first.id, offsetUtf16: 3),
      focus: DocPosition(block: controller.blocks.first.id, offsetUtf16: 3),
    ));
    controller.insertText('x');
    await tester.pump();

    expect(controller.lastRejection, EditRejection.notEditable);
    expect(controller.source, '/* hidden */\n\nAction.\n');
  });

  testWidgets('copying a scene and pasting it produces the same Fountain',
      (tester) async {
    const script = 'INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\nHello.\n';
    final controller = await open(tester, RustDocumentCore.parse(script));

    controller.setSelection(DocSelection(
      anchor: DocPosition(block: controller.blocks.first.id, offsetUtf16: 0),
      focus: DocPosition(
        block: controller.blocks.last.id,
        offsetUtf16: controller.blocks.last.text.length,
      ),
    ));
    final copied = controller.selectedText();
    expect(copied, script);

    // Paste it at the end of the script; the second copy must read as the same
    // elements as the first.
    controller.setSelection(DocSelection(
      anchor: DocPosition(
        block: controller.blocks.last.id,
        offsetUtf16: controller.blocks.last.text.length,
      ),
      focus: DocPosition(
        block: controller.blocks.last.id,
        offsetUtf16: controller.blocks.last.text.length,
      ),
    ));
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
