import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';

/// The screenplay named on the command line, or null for the library.
///
/// `--version` and `--help` never reach here: the GTK runner answers those
/// before the engine starts, because handling them in Dart would flash a window
/// before printing (`linux/runner/my_application.cc`). What is left is a file
/// name, and the rules for finding it are the ordinary ones:
///
///  * the **first** non-option argument wins — this editor holds one script at
///    a time, and silently opening the last of four names would be a lie about
///    what happened to the other three;
///  * a bare `--` ends the options, so a file whose name begins with a dash is
///    still openable;
///  * anything else beginning with `-` is ignored rather than treated as a file,
///    because creating `--colour` as a screenplay is not what anybody meant.
///
/// The path is made absolute against the working directory and normalised,
/// since the core identifies a script by its path — it is what the library
/// index, the crash journal's name and the backup directory's name are all
/// derived from, so `./heat.fountain` and `heat.fountain` must not become two
/// different scripts.
String? scriptFromArguments(List<String> arguments, {required String workingDirectory}) {
  var optionsEnded = false;
  for (final argument in arguments) {
    if (!optionsEnded && argument == '--') {
      optionsEnded = true;
      continue;
    }
    if (!optionsEnded && argument.startsWith('-')) continue;
    if (argument.isEmpty) continue;
    final absolute =
        argument.startsWith('/') ? argument : '$workingDirectory/$argument';
    return Uri.file(absolute).normalizePath().toFilePath();
  }
  return null;
}

/// Phase 4: the application cannot lose your work.
///
/// Every keystroke is appended to a crash journal, the file is written by the
/// atomic sequence of §Phase 4 and never half-written, a rolling backup is kept
/// of every save, and a session that ends in a `SIGKILL` is offered back on the
/// next launch rather than mourned.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Empty directories mean "work them out from XDG" — ADR 0006's
  // `$XDG_*_HOME/slugline`. Only a test passes anything else.
  final Core core;
  try {
    core = await Core.init();
  } on CoreUnavailable catch (failure) {
    // Not a crash and not an editor: the one thing left to do is say why. An
    // editor with no storage under it cannot journal a keystroke, save a file
    // or list a script, and starting one anyway is how §1.2's P0 happens
    // quietly.
    runApp(StorageUnavailableApp(message: failure.message));
    return;
  }
  runApp(
    SluglineApp(
      core: core,
      initialPath: scriptFromArguments(
        arguments,
        workingDirectory: Directory.current.path,
      ),
    ),
  );
}
