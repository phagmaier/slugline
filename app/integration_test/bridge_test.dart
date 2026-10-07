// The four bridge properties, against the real `libslugline_bridge.so`.
//
//     flutter test integration_test/bridge_test.dart -d linux
//
// These were Phase 0's exit proofs, and until Phase 11 they were asserted
// against `api/handshake.rs` — `core_info`, `ping`, `echo`, `slice_utf16` and a
// second `StreamSink`. That module existed to demonstrate the boundary worked
// before there was an application to demonstrate it with, and said in its own
// header that it would be deleted once §6 landed. It was, at Phase 11.
//
// The properties did not go with it. They are the same four, now asserted
// through the surface the application actually uses — which is the stronger
// test: a regression here breaks a feature rather than a proof nothing
// depended on.
//
// `flutter test` (the CI unit-test step) does not run this; it needs the .so
// out of the built bundle.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';

/// ASCII, a Latin-1 accent, CJK, and an astral-plane emoji — a surrogate pair
/// in Dart. Ten UTF-16 code units, nine characters, seventeen UTF-8 bytes.
/// Every disagreement the bridge could have with Dart about a string shows up
/// somewhere in it.
const proof = 'café 日本 🎬';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Core.init();
  });

  /// A fresh in-memory document with [text] in its first block.
  (RustDocumentCore, int) documentOf(String text) {
    final core = RustDocumentCore.create();
    final block = core.blocks(0, 1).first.id;
    core.apply(
      EditCommand.replaceText(
        block: block,
        startUtf16: 0,
        endUtf16: 0,
        with_: text,
      ),
    );
    return (core, block);
  }

  test('Dart calls Rust and gets a struct with a nested list back', () {
    // Was `core_info()` and its `Vec<CrateInfo>`. Now a real read of the
    // document: a list of `BlockView`, each a struct with its own fields.
    final (core, _) = documentOf('INT. HOUSE - DAY');
    addTearDown(core.close);

    final blocks = core.blocks(0, 1);
    expect(blocks, hasLength(1));
    expect(blocks.first.id, isNonZero);
    expect(blocks.first.text, 'INT. HOUSE - DAY');
    // The kind came back too, and it is the one the core inferred — proof that
    // what crossed the boundary is a struct and not just a string.
    expect(blocks.first.kind, BlockKind.sceneHeading);
    expect(blocks.first.forced, isFalse);
  });

  test('Rust pushes an event and Dart receives it', () async {
    // Was `ping` and its `Pong` from a worker thread. The property is that the
    // core can tell Dart something *without being asked*; the real instance of
    // it is the entity index, which is rebuilt off the actor thread after an
    // edit and announced when it lands.
    final (core, block) = documentOf('INT. HOUSE - DAY\n');
    addTearDown(core.close);

    final announced = Core.instance.events
        .firstWhere((event) => event is CoreEvent_EntityIndexUpdated)
        .timeout(const Duration(seconds: 10));

    core.apply(
      EditCommand.replaceText(
        block: block,
        startUtf16: 0,
        endUtf16: 0,
        with_: 'EXT. STREET - NIGHT',
      ),
    );

    final event = await announced as CoreEvent_EntityIndexUpdated;
    expect(event.handle, isNonZero);
  });

  test('non-ASCII text survives the bridge unchanged', () {
    // Was `echo`. Now the round trip that matters: text in, held in a Rust
    // `Document`, serialised back out as Fountain.
    final (core, _) = documentOf(proof);
    addTearDown(core.close);

    expect(core.blocks(0, 1).first.text, proof);
    expect(core.source(), contains(proof));

    // And Rust agrees with Dart about how long it is. `String.length` is UTF-16
    // code units, which is the coordinate the whole bridge speaks (§2.4).
    expect(proof.length, 10);
    expect(
      proof.runes.length,
      9,
      reason: 'the emoji is one character, two units',
    );
  });

  test('UTF-16 offsets mean the same thing on both sides', () {
    // Was `slice_utf16`. `extract` is the same question asked of a real
    // document, and it answers it the same way: null, never a rounded offset.
    final (core, block) = documentOf(proof);
    addTearDown(core.close);

    String? slice(int start, int end) => core.extract(
      DocPosition(block: block, offsetUtf16: start),
      DocPosition(block: block, offsetUtf16: end),
    );

    expect(slice(0, 4), 'café');
    expect(slice(5, 7), '日本');
    expect(slice(8, 10), '🎬');
    // Dart's own substring agrees, which is the whole point.
    expect(slice(0, 4), proof.substring(0, 4));
    expect(slice(5, 7), proof.substring(5, 7));

    // An offset inside the surrogate pair is refused rather than rounded to the
    // nearest boundary (ADR 0001), and so is one past the end.
    expect(slice(8, 9), isNull, reason: 'that offset is inside the emoji');
    expect(slice(9, 10), isNull, reason: 'so is that one');
    expect(slice(0, 99), isNull, reason: 'and that is past the end');
  });
}
