// What startup does when the core comes up without storage.
//
// `files.init` answers false when the core could not work out where its
// directories are, and that answer used to be discarded: the app ran an editor
// over a core with no library, no journal and nowhere to save. §1.2 makes losing
// user text a P0, and the quiet version of it is the one that looks like a
// working editor. `main` now shows this instead.
//
// Unit tests run without the Rust library, so what is checked here is the screen
// and the exception that reaches it. That `Core.init` throws it is in
// `app/lib/core/core.dart`, one `if` after the call it used to ignore.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/app.dart';
import 'package:slugline/core/core.dart';
import 'package:slugline/identity.dart';

void main() {
  testWidgets('the failure screen says what is wrong and offers no editor', (
    tester,
  ) async {
    const failure = CoreUnavailable(
      'Slugline could not work out where to keep your scripts.',
    );

    await tester.pumpWidget(StorageUnavailableApp(message: failure.message));

    expect(find.text('$applicationName cannot start'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      applicationName,
    );
    expect(find.text(failure.message), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'nothing typed here could be kept, so there is nowhere to type',
    );
  });

  test(
    'the exception carries a sentence for the writer, not a stack trace',
    () {
      const failure = CoreUnavailable('no home directory');
      expect(failure.message, 'no home directory');
      expect(failure.toString(), contains('no home directory'));
      expect(failure, isA<Exception>());
    },
  );
}
