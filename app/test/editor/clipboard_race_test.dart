import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';

import '../support/fake_core.dart';

void main() {
  for (final cutting in [true, false]) {
    final operation = cutting ? 'cut' : 'paste';
    for (final change in ['selection', 'text', 'reload', 'dispose', 'none']) {
      testWidgets('$operation after delayed clipboard reply: $change', (
        tester,
      ) async {
        final core = FakeCore.single(BlockKind.action, 'first second');
        final controller = EditorController(core);
        controller.setSelection(
          const DocSelection(
            anchor: DocPosition(block: 1, offsetUtf16: 0),
            focus: DocPosition(block: 1, offsetUtf16: 5),
          ),
        );
        final reply = Completer<Object?>();
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
              return reply.future;
            }
            if (call.method == 'Clipboard.getData') return reply.future;
            return Future<Object?>.value();
          },
        );

        final pending = cutting ? controller.cut() : controller.paste();
        switch (change) {
          case 'selection':
            controller.setSelection(
              const DocSelection(
                anchor: DocPosition(block: 1, offsetUtf16: 6),
                focus: DocPosition(block: 1, offsetUtf16: 12),
              ),
            );
          case 'text':
            // Keep the same selection coordinates; revision must be checked too.
            final selected = controller.selection;
            controller.insertText('other');
            controller.setSelection(selected);
          case 'reload':
            controller.reloadFromCore();
          case 'dispose':
            controller.dispose();
          case 'none':
            break;
        }
        final before = core.source();
        final commands = core.commands.length;
        reply.complete(cutting ? null : {'text': 'pasted'});
        await tester.pump();
        await pending;

        if (cutting) expect(copied, 'first');
        if (change == 'none') {
          expect(
            controller.blocks.single.text,
            cutting ? ' second' : 'pasted second',
          );
        } else {
          expect(core.source(), before);
          expect(core.commands.length, commands);
          expect(core.pastes, isEmpty);
        }
        if (change != 'dispose') controller.dispose();
      });
    }
  }
}
