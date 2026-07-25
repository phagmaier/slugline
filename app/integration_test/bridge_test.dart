// The Phase 0 exit proofs, as assertions.
//
// These live in `integration_test/` rather than `test/` because they load the
// real `libscreenplay_bridge.so` out of the built bundle. Run with:
//
//     flutter test integration_test/bridge_test.dart -d linux
//
// `flutter test` (the CI unit-test step) does not run them.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:screenplay/core/core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Core core;

  setUpAll(() async {
    core = await Core.init();
  });

  test('Dart calls Rust and gets a struct back', () {
    final info = core.info();
    expect(info.coreVersion, isNotEmpty);
    expect(info.frbVersion, isNotEmpty);
    // The seven crates of §2.5, with the layering the spec mandates.
    expect(info.crates.map((c) => c.name), [
      'fountain',
      'document',
      'layout',
      'render_pdf',
      'storage',
      'spell',
      'bridge',
    ]);
    expect(info.crates.first.dependsOn, isEmpty, reason: 'fountain depends on nothing');
  });

  test('Rust pushes an event and Dart receives it', () async {
    // `ping` returns immediately; the event arrives from a Rust worker thread.
    final pong = core.events.firstWhere((e) => e is CoreEvent_Pong);
    core.ping('from the test');
    final event = await pong.timeout(const Duration(seconds: 5)) as CoreEvent_Pong;
    expect(event.text, 'from the test');
    expect(event.lenUtf16, 'from the test'.length);
  });

  test('non-ASCII text survives the bridge unchanged', () {
    const proof = 'café 日本 🎬';
    expect(core.echo(proof), proof);

    final metrics = core.metrics(proof);
    expect(metrics.lenUtf16, proof.length, reason: 'Rust must agree with Dart String.length');
    expect(metrics.lenUtf16, 10);
    expect(metrics.lenUtf8, 17);
    expect(metrics.charCount, 9);
  });

  test('UTF-16 offsets mean the same thing on both sides', () {
    const proof = 'café 日本 🎬';
    expect(core.slice(proof, 0, 4), 'café');
    expect(core.slice(proof, 5, 7), '日本');
    expect(core.slice(proof, 8, 10), '🎬');
    // Dart's own substring agrees, which is the whole point.
    expect(core.slice(proof, 0, 4), proof.substring(0, 4));
    // An offset inside a surrogate pair is refused rather than rounded.
    expect(core.slice(proof, 8, 9), isNull);
    expect(core.slice(proof, 0, 99), isNull);
  });
}
