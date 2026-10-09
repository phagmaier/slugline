import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

import '../support/fake_core.dart';
import '../support/pump_editor.dart';

/// The scroll offset that parks [row] at the top of the viewport.
double _offsetOfRow(int row) => editorGeometry().yOfRow(row);

BlockView _block(int id) => BlockView(
  id: id,
  kind: BlockKind.action,
  sectionLevel: 0,
  text: 'Action line $id.',
  forced: false,
  dual: false,
  readOnly: false,
  inlineRuns: const [],
);

FakeCore _script(int blocks) =>
    FakeCore([for (var id = 1; id <= blocks; id++) _block(id)]);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    )
    .position;

Future<void> _pumpSurface(
  WidgetTester tester,
  EditorController controller, {
  required int initialScrollRow,
  FocusNode? focusNode,
  ValueChanged<int>? onScrolled,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: editorViewportWidth,
          height: editorViewportHeight,
          child: EditorSurface(
            controller: controller,
            initialScrollRow: initialScrollRow,
            focusNode: focusNode,
            onScrolled: onScrolled,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _press(
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

void main() {
  group('a key pressed with the restored view away from the caret', () {
    // A restored session: the view is where it was parked and the caret is
    // where a script opens, at the start.
    Future<EditorController> restored(
      WidgetTester tester, {
      FakeCore? core,
    }) async {
      final controller = EditorController(core ?? _script(100));
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await _pumpSurface(
        tester,
        controller,
        initialScrollRow: 42,
        focusNode: focusNode,
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(_position(tester).pixels, _offsetOfRow(42));
      return controller;
    }

    const start = DocPosition(block: 1, offsetUtf16: 0);

    // None of these moves a caret that is already at the start of the script,
    // so the controller has nothing to report and nothing follows from it.
    for (final (name, key, control, shift) in [
      ('Ctrl+Home', LogicalKeyboardKey.home, true, false),
      ('Shift+Ctrl+Home', LogicalKeyboardKey.home, true, true),
      ('Home', LogicalKeyboardKey.home, false, false),
      ('Up', LogicalKeyboardKey.arrowUp, false, false),
      ('Page Up', LogicalKeyboardKey.pageUp, false, false),
      ('Left', LogicalKeyboardKey.arrowLeft, false, false),
      ('Ctrl+Left', LogicalKeyboardKey.arrowLeft, true, false),
      ('Backspace', LogicalKeyboardKey.backspace, false, false),
    ]) {
      testWidgets('$name shows the caret it left where it was', (tester) async {
        final controller = await restored(tester);

        await _press(tester, key, control: control, shift: shift);

        expect(controller.selection.focus, start);
        expect(_position(tester).pixels, 0);
      });
    }

    // These change the script at the caret and leave the caret on it.
    for (final (name, key, control) in [
      ('Delete', LogicalKeyboardKey.delete, false),
      ('Ctrl+Delete', LogicalKeyboardKey.delete, true),
    ]) {
      testWidgets('$name shows what it changed', (tester) async {
        final controller = await restored(tester);
        final before = (controller.blocks.first.kind, controller.source);

        await _press(tester, key, control: control);

        expect((
          controller.blocks.first.kind,
          controller.source,
        ), isNot(before));
        expect(controller.selection.focus, start);
        expect(_position(tester).pixels, 0);
      });
    }

    testWidgets('an edit made there by something that is not a key shows it', (
      tester,
    ) async {
      // A palette command, say: the caret stays put and the text under it goes.
      final controller = await restored(tester);

      controller.deleteForward();
      await tester.pump();

      expect(controller.selection.focus, start);
      expect(_position(tester).pixels, 0);
    });

    testWidgets('Escape and copy are not about the caret and move nothing', (
      tester,
    ) async {
      await restored(tester);

      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.keyC, control: true);

      expect(_position(tester).pixels, _offsetOfRow(42));
    });

    testWidgets('spell-check results arriving move nothing either', (
      tester,
    ) async {
      final core = _script(100)
        ..spellStatusData = const SpellStatus(
          enabled: true,
          language: 'en_US',
          languages: [
            SpellLanguage(code: 'en_US', label: 'English (United States)'),
          ],
          message: 'Checking with English (United States).',
        )
        // One block at a time, so the last of them is long after the restore.
        ..spellCheckDelay = const Duration(milliseconds: 5);
      core.spellings[100] = const [
        Misspelling(block: 100, startUtf16: 0, endUtf16: 6, word: 'Action'),
      ];
      final controller = await restored(tester, core: core);
      expect(controller.misspellingsFor(100), isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(controller.misspellingsFor(100), hasLength(1));
      expect(_position(tester).pixels, _offsetOfRow(42));
    });
  });

  group('news that is not about the caret, with the view scrolled away', () {
    const away = 900.0;

    // An ordinary session, not a restored one: a key has been pressed, and
    // the writer has since scrolled somewhere else to read.
    Future<EditorController> scrolledAway(
      WidgetTester tester, {
      FakeCore? core,
    }) async {
      final controller = EditorController(core ?? _script(100));
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await _pumpSurface(
        tester,
        controller,
        initialScrollRow: 0,
        focusNode: focusNode,
      );
      focusNode.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      _position(tester).jumpTo(away);
      await tester.pump();
      return controller;
    }

    FakeCore checked() => _script(100)
      ..spellStatusData = const SpellStatus(
        enabled: true,
        language: 'en_US',
        languages: [
          SpellLanguage(code: 'en_US', label: 'English (United States)'),
        ],
        message: 'Checking with English (United States).',
      )
      ..spellings[100] = [
        const Misspelling(
          block: 100,
          startUtf16: 0,
          endUtf16: 6,
          word: 'Action',
        ),
      ];

    testWidgets('spell-check results arriving late leave it there', (
      tester,
    ) async {
      final controller = await scrolledAway(
        tester,
        core: checked()..spellCheckDelay = const Duration(milliseconds: 5),
      );
      expect(controller.misspellingsFor(100), isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(controller.misspellingsFor(100), hasLength(1));
      expect(_position(tester).pixels, away);
    });

    testWidgets('so does ignoring a spelling that is on screen there', (
      tester,
    ) async {
      final controller = await scrolledAway(tester, core: checked());
      await tester.pump(const Duration(seconds: 1));
      _position(tester).jumpTo(away);
      await tester.pump();

      controller.ignoreMisspellingOnce(controller.misspellingsFor(100).single);
      await tester.pump();

      expect(controller.misspellingsFor(100), isEmpty);
      expect(_position(tester).pixels, away);
    });

    testWidgets('and a search that finds nothing', (tester) async {
      final controller = await scrolledAway(tester);

      controller.search(
        const FindQuery(
          text: 'no such words',
          caseSensitive: false,
          wholeWord: false,
          kinds: [],
        ),
      );
      await tester.pump();

      expect(controller.matches, isEmpty);
      expect(_position(tester).pixels, away);
    });

    testWidgets('a search that lands on the match already selected is about '
        'the caret, and comes back to it', (tester) async {
      final controller = await scrolledAway(tester);
      const query = FindQuery(
        text: 'line 2.',
        caseSensitive: false,
        wholeWord: false,
        kinds: [],
      );
      controller.search(query);
      await tester.pump();
      final atMatch = _position(tester).pixels;
      final selection = controller.selection;
      expect(atMatch, lessThan(away));

      _position(tester).jumpTo(away);
      await tester.pump();
      controller.nextMatch();
      await tester.pump();

      expect(controller.selection, selection, reason: 'the only match');
      expect(_position(tester).pixels, atMatch);
    });

    testWidgets('typing the core refuses is the writer at the caret, and '
        'comes back to it', (tester) async {
      final core = _script(100);
      final controller = await scrolledAway(tester, core: core);
      final before = controller.source;

      core.refuseWith = EditRejection.notEditable;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'xAction line 2.',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(controller.source, before);
      expect(controller.lastRejection, EditRejection.notEditable);
      expect(_position(tester).pixels, lessThan(away));
    });
  });

  testWidgets('Ctrl+End with the caret already at the end, and the view '
      'scrolled away from it, comes back to it', (tester) async {
    final controller = EditorController(_script(100));
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 0,
      focusNode: focusNode,
    );
    focusNode.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.end, control: true);
    final position = _position(tester);
    final atEnd = position.pixels;
    expect(atEnd, greaterThan(0));

    position.jumpTo(0);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.end, control: true);

    expect(position.pixels, atEnd);
  });

  testWidgets(
    'a saved row is applied after the first layout and survives focus',
    (tester) async {
      final controller = EditorController(_script(100));
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await _pumpSurface(
        tester,
        controller,
        initialScrollRow: 42,
        focusNode: focusNode,
      );

      expect(_position(tester).pixels, _offsetOfRow(42));
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(_position(tester).pixels, _offsetOfRow(42));
    },
  );

  testWidgets('row zero starts at the top', (tester) async {
    final controller = EditorController(_script(100));
    addTearDown(controller.dispose);

    await _pumpSurface(tester, controller, initialScrollRow: 0);

    expect(_position(tester).pixels, 0);
  });

  testWidgets('a row beyond a shortened document clamps and is reported', (
    tester,
  ) async {
    final controller = EditorController(_script(20));
    final reported = <int>[];
    addTearDown(controller.dispose);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 500,
      onScrolled: reported.add,
    );

    final position = _position(tester);
    expect(position.pixels, position.maxScrollExtent);
    expect(reported, isNotEmpty);
    expect(reported.last, lessThan(500));
  });

  testWidgets('restoration runs once and later scrolling remains parked', (
    tester,
  ) async {
    final controller = EditorController(_script(100));
    final reported = <int>[];
    addTearDown(controller.dispose);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 12,
      onScrolled: reported.add,
    );
    final position = _position(tester);
    expect(position.pixels, _offsetOfRow(12));

    position.jumpTo(_offsetOfRow(30));
    await tester.pump();
    expect(reported.last, 30);

    await _pumpSurface(
      tester,
      controller,
      initialScrollRow: 12,
      onScrolled: reported.add,
    );
    expect(_position(tester).pixels, _offsetOfRow(30));
  });

  testWidgets('the scrollbar thumb can be dragged', (tester) async {
    final controller = EditorController(_script(100));
    addTearDown(controller.dispose);

    await _pumpSurface(tester, controller, initialScrollRow: 0);
    final position = _position(tester);
    position.jumpTo(1);
    await tester.pump(const Duration(milliseconds: 300));
    final verticalBar = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollbar &&
          widget.scrollbarOrientation != ScrollbarOrientation.bottom,
    );
    final scrollbar = tester.getRect(verticalBar);
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(of: verticalBar, matching: find.byType(CustomPaint)),
        )
        .map((paint) => paint.foregroundPainter)
        .whereType<ScrollbarPainter>()
        .first;
    Offset? thumb;
    for (var y = 0.0; y < scrollbar.height && thumb == null; y++) {
      for (var x = 0.0; x < scrollbar.width; x++) {
        final candidate = Offset(x, y);
        if (painter.hitTestOnlyThumbInteractive(
          candidate,
          PointerDeviceKind.mouse,
        )) {
          thumb = candidate;
          break;
        }
      }
    }
    expect(thumb, isNotNull);

    await tester.dragFrom(
      scrollbar.topLeft + thumb!,
      const Offset(0, 240),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(
      position.pixels,
      greaterThan(position.maxScrollExtent / 4),
      reason: 'thumb=$thumb scrollbar=$scrollbar',
    );
  });
}
