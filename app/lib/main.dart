import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';

/// Phase 2: you can type a screenplay in a window. Nothing is saved yet —
/// opening, saving and the library are Phase 4, and the window says so.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Core.init();
  runApp(SluglineApp(controller: EditorController(RustDocumentCore.create())));
}

class SluglineApp extends StatelessWidget {
  const SluglineApp({required this.controller, super.key});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slugline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B6EA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: EditorPage(controller: controller),
    );
  }
}

class EditorPage extends StatelessWidget {
  const EditorPage({required this.controller, super.key});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: EditorSurface(controller: controller)),
          _StatusBar(controller: controller),
        ],
      ),
    );
  }
}

/// The element the caret is in, and whether the last edit was refused.
///
/// Phase 3 replaces this with a real element selector and a command palette;
/// for now it exists so that "what am I typing?" has an answer on screen.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 28,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final rejection = controller.lastRejection;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    currentKindLabel(controller),
                    style: theme.textTheme.labelMedium,
                  ),
                  const Spacer(),
                  if (rejection != null)
                    Text(
                      _rejectionMessage(rejection),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  const SizedBox(width: 16),
                  Text(
                    '${controller.blocks.length} blocks · not saved',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.disabledColor),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Two of these are ordinary things to try, not bugs, so they get a sentence
  /// a writer can act on. The rest are the core telling us we asked wrongly.
  String _rejectionMessage(EditRejection rejection) => switch (rejection) {
        EditRejection.notEditable =>
          'That block round-trips verbatim and cannot be edited.',
        EditRejection.noBlockAfter => 'Nothing to join this to.',
        _ => 'That edit was refused.',
      };
}
