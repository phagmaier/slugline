import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';

/// Phase 3: writing feels correct — element types are inferred as you type, the
/// keyboard reaches every one of them, and find and replace work. Nothing is
/// saved yet: opening, saving and the library are Phase 4, and the element bar
/// says so.
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
