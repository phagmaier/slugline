import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/surface_semantics.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

/// ADR 0005's last outstanding Phase 3 item: the custom surface exposes a
/// semantics tree, which `EditableText` would have given free.
///
/// These tests assert on the tree itself rather than on the widgets that produce
/// it. What matters to a screen reader is what arrives in `SemanticsData` — the
/// label, the value, the caret offsets, and which actions are on offer — and the
/// only honest way to check that is to read it back out of the semantics owner.
void main() {
  BlockView block(int id, BlockKind kind, String text, {bool readOnly = false}) =>
      BlockView(
        id: id,
        kind: kind,
        sectionLevel: 0,
        text: text,
        forced: false,
        dual: false,
        readOnly: readOnly,
      );

  FakeCore scene() => FakeCore([
        block(1, BlockKind.sceneHeading, 'int. house - day'),
        block(2, BlockKind.action, 'John enters.'),
        block(3, BlockKind.character, 'john'),
        block(4, BlockKind.dialogue, 'Hello there.'),
      ]);

  /// The semantics node the surface put over block [index].
  SemanticsNode nodeAt(WidgetTester tester, int index) => tester.getSemantics(
        find.byWidget(
          tester
              .widgetList<ScriptBlockSemantics>(find.byType(ScriptBlockSemantics))
              .elementAt(index),
        ),
      );

  /// Every node the surface put in the tree, in document order.
  List<SemanticsData> surfaceNodes(WidgetTester tester) {
    return tester
        .widgetList<ScriptBlockSemantics>(find.byType(ScriptBlockSemantics))
        .map((widget) => tester.getSemantics(find.byWidget(widget)).getSemanticsData())
        .toList();
  }

  testWidgets('only the visible band is described', (tester) async {
    // The other half of the cost story — that nothing is built at all while
    // `SemanticsBinding.semanticsEnabled` is false — is not reachable from here:
    // the test binding turns semantics on and there is no supported way to turn
    // them off. This is the half that is: a feature-length script must not put a
    // node in the tree for every one of its blocks.
    final handle = tester.ensureSemantics();
    await pumpEditor(
      tester,
      FakeCore([
        for (var id = 1; id <= 400; id++)
          block(id, BlockKind.action, 'Paragraph number $id.'),
      ]),
    );
    await tester.pump();

    final nodes = find.byType(ScriptBlockSemantics).evaluate().length;
    expect(nodes, greaterThan(0));
    expect(
      nodes,
      lessThan(60),
      reason: '600 logical pixels of viewport cannot hold 400 paragraphs',
    );
    handle.dispose();
  });

  testWidgets('every visible block is a node labelled with its element type',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, scene());
    await tester.pump();

    final nodes = surfaceNodes(tester);
    expect(nodes.length, 4);
    expect(
      nodes.map((node) => node.label),
      ['Scene heading', 'Action', 'Character', 'Dialogue'],
    );
    // The value is what is drawn, so a screen reader reads the script as it
    // appears — §5.2 upper-cases a scene heading and a cue on screen only.
    expect(
      nodes.map((node) => node.value),
      ['INT. HOUSE - DAY', 'John enters.', 'JOHN', 'Hello there.'],
    );
    for (final node in nodes) {
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isMultiline, isTrue);
    }
    handle.dispose();
  });

  testWidgets('the caret is reported on the block that holds it', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(tester, scene());
    caretAt(controller, 3, 5);
    await tester.pump();

    final nodes = surfaceNodes(tester);
    expect(
      nodes.map((node) => node.flagsCollection.isFocused),
      [Tristate.isFalse, Tristate.isFalse, Tristate.isFalse, Tristate.isTrue],
    );
    // The selection is what reaches AT-SPI as `textSelectionBase`/`Extent`.
    // Absent means "no caret here", which is right for the three blocks the
    // caret is not in.
    expect(
      nodes.map((node) => node.textSelection?.baseOffset),
      [null, null, null, 5],
    );
    expect(nodes.last.textSelection!.extentOffset, 5);
    handle.dispose();
  });

  testWidgets('a selection within a block is reported as a range',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(tester, scene());
    selectFromTo(controller, 1, 0, 1, 4);
    await tester.pump();

    final action = surfaceNodes(tester)[1];
    expect(action.textSelection!.baseOffset, 0);
    expect(action.textSelection!.extentOffset, 4);
    handle.dispose();
  });

  testWidgets('cursor actions are offered only where the caret is',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(tester, scene());
    caretAt(controller, 1, 0);
    await tester.pump();

    final nodes = surfaceNodes(tester);
    expect(
      nodes[1].hasAction(SemanticsAction.moveCursorForwardByCharacter),
      isTrue,
    );
    expect(nodes[1].hasAction(SemanticsAction.setSelection), isTrue);
    expect(nodes[1].hasAction(SemanticsAction.setText), isTrue);
    // There is one caret. A block that does not hold it must not offer to move
    // it, or the move would silently jump somewhere else first.
    expect(
      nodes[2].hasAction(SemanticsAction.moveCursorForwardByCharacter),
      isFalse,
    );
    // Every block can be reached, though.
    expect(nodes[2].hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('moving the cursor through the tree moves the real caret',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(tester, scene());
    caretAt(controller, 1, 0);
    await tester.pump();

    final action = nodeAt(tester, 1);
    action.owner!
        .performAction(action.id, SemanticsAction.moveCursorForwardByCharacter, false);
    await tester.pump();
    expect(controller.selection.focus.offsetUtf16, 1);
    expect(controller.selection.anchor.offsetUtf16, 1, reason: 'not extended');

    action.owner!
        .performAction(action.id, SemanticsAction.moveCursorForwardByWord, true);
    await tester.pump();
    expect(controller.selection.anchor.offsetUtf16, 1, reason: 'extended');
    expect(controller.selection.focus.offsetUtf16, greaterThan(1));
    handle.dispose();
  });

  testWidgets('taking accessibility focus moves the caret into that block',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(tester, scene());
    caretAt(controller, 0, 0);
    await tester.pump();

    final dialogue = nodeAt(tester, 3);
    dialogue.owner!
        .performAction(dialogue.id, SemanticsAction.didGainAccessibilityFocus);
    await tester.pump();

    expect(controller.selection.focus.block, controller.blocks[3].id);
    expect(controller.selection.focus.offsetUtf16, 0);
    handle.dispose();
  });

  testWidgets('setText replaces the block through the ordinary edit path',
      (tester) async {
    final handle = tester.ensureSemantics();
    final core = scene();
    final controller = await pumpEditor(tester, core);
    caretAt(controller, 1, 0);
    await tester.pump();

    final action = nodeAt(tester, 1);
    action.owner!.performAction(action.id, SemanticsAction.setText, 'Mary leaves.');
    await tester.pump();

    expect(controller.blocks[1].text, 'Mary leaves.');
    // It went to the core as an edit command, not around it.
    expect(core.commands, isNotEmpty);
    handle.dispose();
  });

  testWidgets('a block the core will not edit says so', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await pumpEditor(
      tester,
      FakeCore([
        block(1, BlockKind.action, 'John enters.'),
        block(2, BlockKind.opaque, '/* boneyard */', readOnly: true),
      ]),
    );
    caretAt(controller, 1, 0);
    await tester.pump();

    final opaque = surfaceNodes(tester)[1];
    expect(opaque.flagsCollection.isReadOnly, isTrue);
    expect(
      opaque.hasAction(SemanticsAction.setText),
      isFalse,
      reason: 'offering an edit the core refuses is offering a refusal',
    );
    // Reading it is still on offer.
    expect(opaque.hasAction(SemanticsAction.copy), isTrue);
    handle.dispose();
  });
}
