// §Phase 11's "opening a file passed as `argv[1]`".
//
// `--version` and `--help` are not tested here because they never reach Dart —
// the GTK runner answers them before the engine starts, so that neither flashes
// a window. What Dart is responsible for is picking the file name out of what
// is left and making it absolute.

import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/main.dart';

void main() {
  String? script(
    List<String> arguments, {
    String cwd = '/home/writer/scripts',
  }) => scriptFromArguments(arguments, workingDirectory: cwd);

  group('the file named on the command line:', () {
    test('no arguments means the library', () {
      expect(script([]), isNull);
    });

    test('an absolute path is taken as it is', () {
      expect(script(['/srv/heat.fountain']), '/srv/heat.fountain');
    });

    test('a relative path is resolved against the working directory', () {
      // The core identifies a script by its path — the library index, the
      // journal's name and the backup directory's name all come from it — so a
      // relative path would name a different script from a different directory.
      expect(script(['heat.fountain']), '/home/writer/scripts/heat.fountain');
      expect(script(['./heat.fountain']), '/home/writer/scripts/heat.fountain');
      expect(script(['../heat.fountain']), '/home/writer/heat.fountain');
    });

    test('the first name wins, because the editor holds one script', () {
      // Opening the last of three silently would be a lie about what happened
      // to the other two.
      expect(
        script(['first.fountain', 'second.fountain']),
        '/home/writer/scripts/first.fountain',
      );
    });

    test('an unrecognised option is ignored, not opened as a file', () {
      // Creating `--colour` as a screenplay is not what anybody meant.
      expect(script(['--colour']), isNull);
      expect(
        script(['--colour', 'heat.fountain']),
        '/home/writer/scripts/heat.fountain',
      );
    });

    test('a bare -- ends the options', () {
      // So a screenplay honestly called `-heat.fountain` is still openable.
      expect(
        script(['--', '-heat.fountain']),
        '/home/writer/scripts/-heat.fountain',
      );
      expect(script(['--', '--help']), '/home/writer/scripts/--help');
    });

    test('an empty argument is not a file name', () {
      expect(script(['']), isNull);
      expect(
        script(['', 'heat.fountain']),
        '/home/writer/scripts/heat.fountain',
      );
    });

    test('a name with spaces and non-ASCII survives intact', () {
      expect(
        script(['Le Fabuleux Destin.fountain']),
        '/home/writer/scripts/Le Fabuleux Destin.fountain',
      );
      expect(script(['日本語.fountain']), '/home/writer/scripts/日本語.fountain');
    });
  });
}
