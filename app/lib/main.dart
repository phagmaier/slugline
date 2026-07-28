import 'package:flutter/material.dart';

import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';

/// Phase 4: the application cannot lose your work.
///
/// Every keystroke is appended to a crash journal, the file is written by the
/// atomic sequence of §Phase 4 and never half-written, a rolling backup is kept
/// of every save, and a session that ends in a `SIGKILL` is offered back on the
/// next launch rather than mourned.
Future<void> main() async {
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
  runApp(SluglineApp(core: core));
}
