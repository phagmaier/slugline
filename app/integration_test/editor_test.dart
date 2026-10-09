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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('slugline-native-editor-');
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
    'the first dense edit reveals the end caret after horizontal layout',
    (tester) async {
      final core = RustDocumentCore.create();
      await core.configureSpelling(enabled: false);
      final controller = EditorController(core);
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorSurface(controller: controller, focusNode: focus),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();

      // No prior caret move may initialize the surface's width cache.
      final dense = List.filled(30, '***x***').join(' ');
      controller.insertText(dense);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable && widget.axis == Axis.horizontal,
            ),
          )
          .position;
      final width = tester.getSize(find.byType(EditorSurface)).width;
      final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
      final geometry = EditorGeometry(
        metrics: ScreenplayMetrics.forFontSize(
          ScreenplayMetrics.fittedFontSize(
            preferredFontSize: surface.textSize,
            viewportWidth: width,
            pageView: surface.pageView,
          ),
        ),
        viewportWidth: width,
        totalRows: controller.layout.totalRows,
        pageView: surface.pageView,
        scrollbarWidth: kMinInteractiveDimension,
      );
      final line = controller.layout.linesOf(0).single;
      final caretX =
          geometry.columnLeft +
          line.displayColumnAtOffset(controller.selection.focus.offsetUtf16) *
              geometry.advance -
          scroll.pixels;
      expect(controller.selection.focus.offsetUtf16, dense.length);
      expect(
        caretX,
        inInclusiveRange(0, width - kMinInteractiveDimension),
        reason: 'the first paste must reveal its caret without another edit',
      );
    },
  );

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

    await tester.tap(find.byKey(const ValueKey('editor overflow')));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagination debug'));
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
    // The live choices stay pinned, while saved syntax needs no redundant markers.
    expect(controller.blocks.every((block) => block.forced), isTrue);
    expect(
      controller.source,
      'INT. HOUSE - DAY\n\nJohn enters, holding a letter.\n\nJOHN\nIt came.\n',
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

  // W8. The widget tests hold where the tint goes; these hold that it reaches
  // the screen, in the face the script is set in, over matches the real core
  // found — which means case folded, a heading stored in lower case and drawn
  // in capitals, and offsets counted past an astral character.
  group('Find on the real surface', () {
    const fillers = 12;
    final source =
        '${List.generate(fillers, (line) => 'Filler line $line.').join('\n\n')}'
        '\n\nint. house - day\n\n'
        '🎬 The HOUSE is quiet. Nobody has lived in the house since the winter, '
        'and nobody will until the house is sold.\n';
    const heading = fillers;
    const action = fillers + 1;
    final shot = GlobalKey();

    Future<EditorController> openPage(WidgetTester tester) async {
      final controller = EditorController(RustDocumentCore.parse(source));
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: shot,
            child: EditorPage(controller: controller),
          ),
        ),
      );
      await tester.tap(find.byType(EditorSurface));
      await tester.pumpAndSettle();
      expect(controller.blocks[heading].kind, BlockKind.sceneHeading);
      expect(controller.blocks[heading].text, 'int. house - day');
      return controller;
    }

    Future<void> pressFind(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Finder findField() =>
        find.ancestor(of: find.text('Find'), matching: find.byType(TextField));

    String findText(WidgetTester tester) =>
        tester.widget<TextField>(findField()).controller!.text;

    String? count(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('find-match-count'))).data;

    Future<void> typeFind(WidgetTester tester, String text) async {
      await tester.enterText(findField(), text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    void select(EditorController controller, int block, int from, int to) {
      final id = controller.blocks[block].id;
      controller.setSelection(
        DocSelection(
          anchor: DocPosition(block: id, offsetUtf16: from),
          focus: DocPosition(block: id, offsetUtf16: to),
        ),
      );
    }

    dynamic painter(WidgetTester tester) => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(EditorSurface),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere(
          (paint) => paint.painter.runtimeType.toString() == '_SurfacePainter',
        )
        .painter!;

    /// Where the cells of [block] from [from] to [to] are on screen. They must
    /// share a row.
    ///
    /// Less what the surface has scrolled: while the find bar is up the rows
    /// have its height above them and the view is that much further down, so
    /// that the text is where it was.
    Rect cells(
      WidgetTester tester,
      EditorController controller,
      int block,
      int from,
      int to,
    ) {
      final geometry = painter(tester).geometry as EditorGeometry;
      final scrolled = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(EditorSurface),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable && widget.axis == Axis.vertical,
              ),
            ),
          )
          .position
          .pixels;
      final layout = controller.layout;
      final lineIndex = layout.lineIndexAt(block, from);
      final line = layout.linesOf(block)[lineIndex];
      expect(to, lessThanOrEqualTo(line.end), reason: 'one row');
      final column = layout.columnOf(block, lineIndex);
      final left = column + line.columnAtOffset(from);
      final right = column + line.columnAtOffset(to);
      return Rect.fromLTWH(
        geometry.columnLeft + left * geometry.advance,
        geometry.yOfRow(layout.firstRowOf(block) + lineIndex),
        (right - left) * geometry.advance,
        geometry.lineHeight,
      ).shift(
        tester.getTopLeft(find.byType(EditorSurface)) - Offset(0, scrolled),
      );
    }

    /// The window as it is drawn, one byte per channel.
    Future<(ByteData, int)> capture(WidgetTester tester) async {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(shot),
      );
      late ByteData bytes;
      late int width;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        width = image.width;
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
      });
      return (bytes, width);
    }

    /// What is behind the text in [rect]: the colour most of it is.
    ///
    /// The ink is a minority of any cell in the script face and no two of its
    /// antialiased edges are the same shade, so the mode is the ground.
    Color ground((ByteData, int) image, Rect rect) {
      final (bytes, width) = image;
      final counts = <int, int>{};
      for (var y = rect.top.ceil() + 1; y < rect.bottom.floor() - 1; y++) {
        for (var x = rect.left.ceil() + 1; x < rect.right.floor() - 1; x++) {
          final pixel = bytes.getUint32((y * width + x) * 4);
          counts[pixel] = (counts[pixel] ?? 0) + 1;
        }
      }
      final rgba = counts.entries
          .reduce((most, entry) => entry.value > most.value ? entry : most)
          .key;
      return Color.fromARGB(
        rgba & 0xff,
        rgba >> 24 & 0xff,
        rgba >> 16 & 0xff,
        rgba >> 8 & 0xff,
      );
    }

    Matcher isColour(Color expected) => predicate<Color>(
      (colour) =>
          ((colour.r - expected.r).abs() * 255).round() <= 2 &&
          ((colour.g - expected.g).abs() * 255).round() <= 2 &&
          ((colour.b - expected.b).abs() * 255).round() <= 2,
      'within two steps of $expected',
    );

    testWidgets('every match is tinted in the script face, and none after', (
      tester,
    ) async {
      final controller = await openPage(tester);
      final text = controller.blocks[action].text;
      // UTF-16 offsets, as the bridge counts them: the clapperboard is two.
      final shouted = text.indexOf('HOUSE');
      final second = text.indexOf('house');
      final third = text.lastIndexOf('house');
      expect(shouted, 7);

      select(controller, 0, 0, 0);
      await tester.pump();
      await pressFind(tester);
      await typeFind(tester, 'house');
      expect(controller.matches, hasLength(4));
      expect(count(tester), '1 of 4', reason: 'the heading, from the top');
      // Step to the one the caret will stay on.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(count(tester), '2 of 4');
      expect(controller.selectedText(), 'HOUSE');

      final inHeading = cells(tester, controller, heading, 5, 10);
      final current = cells(tester, controller, action, shouted, shouted + 5);
      final others = [
        inHeading,
        cells(tester, controller, action, second, second + 5),
        cells(tester, controller, action, third, third + 5),
      ];
      final plain = cells(
        tester,
        controller,
        action,
        text.indexOf('quiet'),
        text.indexOf('quiet') + 5,
      );
      // Everything sampled is on screen and clear of the bar that floats over
      // the top of the script.
      final surface = tester.getRect(find.byType(EditorSurface));
      final bar = tester.getRect(find.byType(FindBar));
      for (final rect in [...others, current, plain]) {
        expect(surface.contains(rect.topLeft), isTrue);
        expect(surface.contains(rect.bottomRight), isTrue);
        expect(bar.overlaps(rect), isFalse);
      }

      final dynamic delegate = painter(tester);
      final tint = delegate.colours.match as Color;
      final selection = delegate.colours.selection as Color;

      var image = await capture(tester);
      final paper = ground(image, plain);
      final tinted = Color.alphaBlend(tint, paper);
      expect(tinted, isNot(isColour(paper)), reason: 'a tint that shows');
      for (final rect in others) {
        expect(ground(image, rect), isColour(tinted));
      }
      expect(
        ground(image, current),
        isColour(Color.alphaBlend(selection, tinted)),
        reason: 'the one the caret is on is selected over its tint',
      );
      // The cell either side of a match is not part of it.
      for (final rect in others) {
        final cell = rect.width / 5;
        expect(
          ground(
            image,
            rect.shift(Offset(-cell, 0)).topLeft & Size(cell, rect.height),
          ),
          isColour(paper),
        );
        expect(
          ground(image, rect.topRight & Size(cell, rect.height)),
          isColour(paper),
        );
      }

      // A toggle that drops a match without moving the caret: the next match
      // is spelled the same either way, and HOUSE is no longer one.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(count(tester), '3 of 4');
      final resting = controller.selection;
      await tester.tap(find.text('Match case'));
      await tester.pumpAndSettle();
      expect(controller.matches, hasLength(3));
      expect(count(tester), '2 of 3');
      expect(controller.selection, resting);
      image = await capture(tester);
      expect(ground(image, current), isColour(paper), reason: 'HOUSE');
      expect(ground(image, others[0]), isColour(tinted));
      expect(
        ground(image, others[1]),
        isColour(Color.alphaBlend(selection, tinted)),
      );
      expect(ground(image, others[2]), isColour(tinted));

      // By its button: the click on the chip took the keyboard out of the
      // find field, and on a desktop Escape does not reach the bar after that
      // (docs/BACKLOG.md, Found along the way).
      await tester.tap(find.byTooltip('Close (Escape)'));
      await tester.pumpAndSettle();
      expect(find.byType(FindBar), findsNothing);
      image = await capture(tester);
      for (final rect in [others[0], current, others[2]]) {
        expect(ground(image, rect), isColour(paper));
      }
      expect(
        ground(image, others[1]),
        isColour(Color.alphaBlend(selection, paper)),
        reason: 'the match stays selected, as it did before',
      );
      expect(controller.source, source, reason: 'finding edits nothing');
    });

    testWidgets('Find opened over a selection searches the real core for it', (
      tester,
    ) async {
      final controller = await openPage(tester);
      final text = controller.blocks[action].text;
      final shouted = text.indexOf('HOUSE');

      select(controller, action, shouted, shouted + 5);
      await tester.pump();
      await pressFind(tester);

      expect(findText(tester), 'HOUSE');
      expect(controller.matches, hasLength(4), reason: 'case is folded');
      expect(count(tester), '2 of 4', reason: 'on the one that was selected');
      expect(controller.selectedText(), 'HOUSE');

      // The stored text of a heading, not the capitals it is drawn in.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      select(controller, heading, 0, 4);
      await tester.pump();
      await pressFind(tester);
      expect(findText(tester), 'int.');
      expect(count(tester), '1 of 1');
      expect(controller.selectedText(), 'int.');

      // A search left on a match is resumed as it was typed.
      await typeFind(tester, 'house');
      expect(count(tester), '1 of 4');
      expect(controller.selectedText(), 'house');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.selectedText(), 'HOUSE');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await pressFind(tester);
      expect(findText(tester), 'house');
      expect(count(tester), '2 of 4');
      expect(controller.source, source);
    });
  });
}
