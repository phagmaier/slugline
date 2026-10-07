import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/editor/line_text_cache.dart';

void main() {
  TextStyle style({Color color = Colors.black, double size = 14}) => TextStyle(
    fontFamily: 'Courier Prime',
    fontSize: size,
    height: 1.0,
    color: color,
  );

  test('the same text and style share one laid-out painter', () {
    final cache = LineTextCache();
    addTearDown(cache.dispose);
    final first = cache.line('INT. HOUSE - DAY', style());
    final second = cache.line('INT. HOUSE - DAY', style());
    expect(
      identical(first, second),
      isTrue,
      reason: 'a scroll frame must not re-lay',
    );
    expect(cache.hits, 1);
    expect(cache.misses, 1);
    expect(first.width, greaterThan(0));
  });

  test('any change to the pixels is a miss, never a stale hit', () {
    final cache = LineTextCache();
    addTearDown(cache.dispose);
    final original = cache.line('NADIA', style());
    // The edit-then-repaint sequence: the changed line misses, the meanwhile
    // unchanged ones still hit.
    final edited = cache.line('NADIA!', style());
    expect(identical(edited, original), isFalse);
    expect((edited.text! as TextSpan).text, 'NADIA!');
    expect((original.text! as TextSpan).text, 'NADIA');
    expect(identical(cache.line('NADIA', style()), original), isTrue);

    // Every style field that reaches the screen is part of the key.
    expect(
      identical(cache.line('NADIA', style(color: Colors.red)), original),
      isFalse,
    );
    expect(identical(cache.line('NADIA', style(size: 18)), original), isFalse);
    expect(
      identical(
        cache.line('NADIA', style().copyWith(fontStyle: FontStyle.italic)),
        original,
      ),
      isFalse,
    );
  });

  test('entries past the cap are evicted oldest-first', () {
    final cache = LineTextCache(maxEntries: 4);
    addTearDown(cache.dispose);
    final painters = [
      for (var i = 0; i < 4; i++) cache.line('line $i', style()),
    ];
    expect(cache.length, 4);
    // Touch line 0 so line 1 is the oldest, then overflow.
    expect(identical(cache.line('line 0', style()), painters[0]), isTrue);
    cache.line('line 4', style());
    expect(cache.length, 4);
    // Line 1 fell out: a miss and a new painter.
    expect(identical(cache.line('line 1', style()), painters[1]), isFalse);
    // Lines 0, 2, 3, 4 are still resident.
    expect(identical(cache.line('line 0', style()), painters[0]), isTrue);
  });

  test('unicode and empty lines are cached like any other', () {
    final cache = LineTextCache();
    addTearDown(cache.dispose);
    expect(
      identical(
        cache.line('MARÍA — 日本語 🎬', style()),
        cache.line('MARÍA — 日本語 🎬', style()),
      ),
      isTrue,
    );
    expect(identical(cache.line('', style()), cache.line('', style())), isTrue);
  });

  test('dispose empties the cache', () {
    final cache = LineTextCache();
    cache.line('INT. HOUSE - DAY', style());
    expect(cache.length, 1);
    cache.dispose();
    expect(cache.length, 0);
    expect(cache.line('INT. HOUSE - DAY', style()).width, greaterThan(0));
  });
}
