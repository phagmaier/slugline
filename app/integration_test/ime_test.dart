// ADR 0005's hard exit gate for Phase 3: input-method composition, dead-key
// accents, and a clipboard round trip.
//
//     flutter test integration_test/ime_test.dart -d linux
//
// **What this can and cannot prove.** These tests drive the same interface a real
// input method drives — `TextInputClient`, which is what `ibus` reaches the
// application through — by handing the surface the editing values and composing
// ranges an IME produces, and asserting what reaches the core. That covers the
// whole of our own side of the contract: the diff, the offsets, the composing
// range, and what happens to a composition when the caret leaves the block it was
// in. The values go to the client directly rather than through
// `tester.testTextInput`, which an integration binding does not register; what is
// skipped is Flutter's own channel plumbing, and none of ours.
//
// It does **not** prove that `ibus` itself is configured correctly on a given
// machine, because no automated test can: that is a property of the desktop
// session, not of this code. ADR 0005 asks for a manual check with `ibus` and a
// CJK input method as well, and `SPEC.md`'s Phase 2 list records whether it has
// been run.

import 'dart:io';

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

  late Directory root;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('slugline-native-ime-');
    await Core.init(
      configDir: '${root.path}/config',
      dataDir: '${root.path}/data',
      stateDir: '${root.path}/state',
    );
  });
  tearDownAll(() async {
    await Core.instance.shutdown();
    root.deleteSync(recursive: true);
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
        home: Scaffold(body: EditorSurface(controller: controller)),
      ),
    );
    await tester.tap(find.byType(EditorSurface));
    // The tap took the focus, and put the caret wherever it landed. Every test
    // below starts from the top of the script.
    controller.moveToDocumentEdge(start: true);
    await tester.pump();
    return controller;
  }

  /// The editor, as the platform sees it: a `TextInputClient`.
  EditorSurfaceState client(WidgetTester tester) =>
      tester.state<EditorSurfaceState>(find.byType(EditorSurface));

  /// One step of a composition, exactly as a platform input method sends it: the
  /// whole text of the editing session, and which part of it is still provisional.
  Future<void> compose(
    WidgetTester tester,
    String text, {
    required int from,
    required int to,
    int? caret,
  }) async {
    client(tester).updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
        composing: TextRange(start: from, end: to),
      ),
    );
    await tester.pump();
  }

  /// The commit: the same text, with nothing provisional left in it.
  Future<void> commit(WidgetTester tester, String text) async {
    client(tester).updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
  }

  testWidgets('a CJK composition reaches the core as the characters it produced', (
    tester,
  ) async {
    final controller = await open(tester);

    // Typing "nihao" on a Pinyin input method: the Latin letters are provisional,
    // then they are replaced by the characters, then committed.
    await compose(tester, 'n', from: 0, to: 1);
    await compose(tester, 'ni', from: 0, to: 2);
    await compose(tester, 'niha', from: 0, to: 4);
    await compose(tester, 'nihao', from: 0, to: 5);
    expect(
      controller.blocks.single.text,
      'nihao',
      reason: 'provisional text is still text, and still the core\'s',
    );

    await compose(tester, '你好', from: 0, to: 2);
    expect(controller.blocks.single.text, '你好');

    await commit(tester, '你好');
    expect(controller.blocks.single.text, '你好');
    expect(controller.selection.focus.offsetUtf16, 2);
    expect(controller.source, '你好\n');

    // Undo steps back through the composition's stages rather than over the whole
    // of it. §3.4 coalesces a run of insertions and a run of deletions; swapping
    // the Latin letters for the characters is neither, so it is a transaction of
    // its own. Nothing is lost at either step, which is what matters.
    controller.undo();
    await tester.pump();
    expect(controller.blocks.single.text, 'nihao');
    controller.undo();
    await tester.pump();
    expect(controller.blocks.single.text, isEmpty);
  });

  testWidgets('a composition inside existing text lands at the caret', (
    tester,
  ) async {
    final controller = await open(tester, 'ab\n');
    final id = controller.blocks.single.id;
    controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: id, offsetUtf16: 1),
        focus: DocPosition(block: id, offsetUtf16: 1),
      ),
    );
    await tester.pump();

    await compose(tester, 'ani b', from: 1, to: 4, caret: 4);
    await compose(tester, 'a你 b', from: 1, to: 2, caret: 2);
    await commit(tester, 'a你 b');

    expect(controller.blocks.single.text, 'a你 b');
  });

  testWidgets('a dead-key accent produces one character, not two', (
    tester,
  ) async {
    final controller = await open(tester);

    // `´` then `e` on a dead-key layout: the accent is composed, then replaced.
    await compose(tester, 'caf´', from: 3, to: 4);
    await compose(tester, 'café', from: 3, to: 4);
    await commit(tester, 'café');

    expect(controller.blocks.single.text, 'café');
    // Four characters, five bytes: the offset the core was handed has to have
    // been the UTF-16 one (§2.4), or the accent would have landed inside the 'é'.
    expect(controller.selection.focus.offsetUtf16, 4);
    expect(controller.source, 'café\n');
  });

  testWidgets('a composition of an astral-plane character keeps its offsets', (
    tester,
  ) async {
    final controller = await open(tester);

    // An emoji is two UTF-16 code units and four bytes. A composition that ends
    // on one is the case ADR 0001 refuses to round.
    await compose(tester, 'clap', from: 0, to: 4);
    await compose(tester, '🎬', from: 0, to: 2);
    await commit(tester, '🎬');

    expect(controller.blocks.single.text, '🎬');
    expect(controller.selection.focus.offsetUtf16, 2);
    expect(controller.lastRejection, isNull);
    expect(controller.source, '🎬\n');
  });

  testWidgets('a composition abandoned mid-way leaves what was typed', (
    tester,
  ) async {
    final controller = await open(tester);
    await compose(tester, 'ni', from: 0, to: 2);
    // The input method gives up — Escape at the ibus level — and hands back the
    // Latin letters with nothing provisional. Nothing is lost, which is the only
    // outcome §1.2 allows.
    await commit(tester, 'ni');

    expect(controller.blocks.single.text, 'ni');
  });

  testWidgets('a composition does not survive the caret leaving its block', (
    tester,
  ) async {
    // ADR 0005 hands the platform one block at a time and records a composition
    // spanning a block boundary as Phase 3 work. This is that work: the session
    // belongs to a block, and moving out of it ends the session rather than
    // leaving a composing range describing text the platform can no longer see.
    final controller = await open(tester, 'first\n\nsecond\n');
    expect(controller.blocks.length, 2);

    await compose(tester, 'firstni', from: 5, to: 7);
    expect(controller.blocks.first.text, 'firstni');

    // Down into the second block.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.selection.focus.block, controller.blocks[1].id);

    // The platform is now looking at the second block, with nothing provisional.
    expect(client(tester).currentTextEditingValue.text, 'second');
    expect(client(tester).currentTextEditingValue.composing, TextRange.empty);

    // And the next composition applies to the second block, not the first.
    await compose(tester, 'secondni', from: 6, to: 8);
    await compose(tester, 'second你', from: 6, to: 7);
    await commit(tester, 'second你');

    expect(controller.blocks.first.text, 'firstni');
    expect(controller.blocks[1].text, 'second你');
    expect(controller.source, 'firstni\n\nsecond你\n');
  });

  testWidgets('Enter during a composition splits after the composed text', (
    tester,
  ) async {
    final controller = await open(tester);
    await compose(tester, 'ni', from: 0, to: 2);
    await compose(tester, '你', from: 0, to: 1);

    // A newline reaching us mid-composition: the composed text is already in the
    // document, so the split happens after it and nothing is provisional.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.blocks.length, 2);
    expect(controller.blocks.first.text, '你');
    expect(controller.blocks[1].text, isEmpty);
    expect(client(tester).currentTextEditingValue.composing, TextRange.empty);
  });

  testWidgets(
    'a newline from the input method splits rather than being smuggled in',
    (tester) async {
      final controller = await open(tester);
      // Some input methods send the newline as text rather than as an action. A
      // `\n` inside a block's text is not something the model can represent for
      // most element types, so it has to become a split.
      client(tester).updateEditingValue(
        const TextEditingValue(
          text: 'one\ntwo',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();

      expect(controller.blocks.length, 2);
      expect(controller.blocks.map((block) => block.text).toList(), [
        'one',
        'two',
      ]);
      expect(controller.source, 'one\n\ntwo\n');
    },
  );

  testWidgets('non-ASCII text survives the clipboard in both directions', (
    tester,
  ) async {
    const script = 'INT. CAFÉ - DAY\n\nJOSÉ\n(quietly)\n你好。🎬\n';
    final controller = await open(tester, script);

    controller.selectAll();
    final copied = controller.selectedText();
    expect(
      copied,
      script,
      reason: 'copying the whole script gives its bytes back',
    );

    await Clipboard.setData(ClipboardData(text: copied!));
    // Straight back out of the platform clipboard, which is where a real IME's
    // output would have come from.
    final read = await Clipboard.getData(Clipboard.kTextPlain);
    expect(read?.text, script);

    // And pasting it into an empty script reproduces the same elements.
    final fresh = EditorController(RustDocumentCore.create());
    addTearDown(fresh.dispose);
    await fresh.paste();
    expect(fresh.source, script);
    expect(fresh.blocks.map((block) => block.kind).toList(), [
      BlockKind.sceneHeading,
      BlockKind.character,
      BlockKind.parenthetical,
      BlockKind.dialogue,
    ]);
  });
}
