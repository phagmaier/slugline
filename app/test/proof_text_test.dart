// Unit tests run without the Rust library loaded, so this file guards the one
// thing the Dart side can check on its own: that the shared proof fixture still
// has the shape both sides hardcode. If someone edits `proofText`, this fails
// next to the Rust tests in `crates/bridge/src/api/handshake.rs` rather than
// silently weakening the UTF-16 proof.

import 'package:flutter_test/flutter_test.dart';
import 'package:slugline/core/core.dart';

void main() {
  test('the proof string still covers every width class', () {
    expect(proofText, 'café 日本 🎬');
    expect(proofText.length, 10, reason: 'UTF-16 code units');
    expect(proofText.runes.length, 9, reason: 'characters — the emoji is a pair');
    expect(proofText.codeUnits.where((u) => u >= 0xD800 && u <= 0xDBFF), isNotEmpty,
        reason: 'must contain an astral-plane character');
    expect(proofText.codeUnits.any((u) => u > 0x7F && u < 0x100), isTrue,
        reason: 'must contain a Latin-1 accent');
  });
}
