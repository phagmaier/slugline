import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/element_bar.dart';

import '../support/fake_core.dart';

void main() {
  testWidgets('F1, F11, and Ctrl+plus reach the application preferences', (
    tester,
  ) async {
    final core = FakeCore.single(BlockKind.action, 'A quiet page.');
    final controller = EditorController(core);
    addTearDown(controller.dispose);
    var shortcuts = 0;
    bool? focusMode;
    int? textSize;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          textSize: 15,
          onShowShortcuts: () async => shortcuts++,
          onDistractionFreeChanged: (enabled) async => focusMode = enabled,
          onTextSizeChanged: (size) async => textSize = size,
        ),
      ),
    );
    await tester.tap(find.byType(EditorSurface));

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(shortcuts, 1);
    expect(focusMode, isTrue);
    expect(textSize, 16);
  });

  testWidgets('distraction-free mode removes editor chrome but keeps an exit', (
    tester,
  ) async {
    final controller = EditorController(
      FakeCore.single(BlockKind.action, 'Only the page.'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          controller: controller,
          distractionFree: true,
          onDistractionFreeChanged: (_) async {},
        ),
      ),
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ElementBar), findsNothing);
    expect(
      find.byKey(const ValueKey('leave distraction free')),
      findsOneWidget,
    );
  });
}
