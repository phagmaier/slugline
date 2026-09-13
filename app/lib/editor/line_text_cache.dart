import 'dart:collection';

import 'package:flutter/material.dart';

/// A bounded cache of laid-out [TextPainter]s, keyed on exactly what they draw.
///
/// Painting a screenplay means laying out the same short strings over and over:
/// every scroll frame re-lays ~60 visible lines that have not changed since the
/// last frame. A `TextPainter` layout is the expensive half of that — measuring
/// and shaping glyph runs — while `paint` at an offset is cheap. This keeps the
/// laid-out result around so a frame that shows the same text pays only the
/// paint.
///
/// ## Why this cannot paint stale text
///
/// There is no invalidation step to get wrong, because the key *is* the pixels:
/// the full line text plus the fully resolved [TextStyle]. An edit, a theme
/// change or a text-size change produces a different key and therefore a cache
/// miss, never a stale hit. Entries that fall out of use are evicted oldest
/// first past [maxEntries], and evicted painters are disposed — the previous
/// per-frame allocation never disposed its painters at all.
///
/// ## Lifetimes
///
/// The editor's surface owns one for the life of its [State]: it survives
/// rebuilds (a rebuild does not mean the text changed) and is disposed with the
/// state. The preview owns one per [PreviewView] state for the same reason. A
/// laid-out painter is position-independent — the offset is supplied to
/// `paint`, not baked in — so sharing one painter across frames, pages and
/// repeated lines is sound.
class LineTextCache {
  LineTextCache({this.maxEntries = 512});

  /// How many laid-out painters are kept. Bounded so a pathological document —
  /// thousands of unique lines — cannot turn the cache into the leak it
  /// replaces. A screenful is ~60; 512 covers it with room for repeated
  /// headings shared across pages.
  final int maxEntries;

  final LinkedHashMap<_LineKey, TextPainter> _entries = LinkedHashMap();

  /// Laid-out-painter hits and misses since creation. Zero-cost in release
  /// (two integer writes) and asserted on by the cache's own test.
  int hits = 0;
  int misses = 0;

  /// The laid-out painter for [text] in [style], shared with every other frame
  /// that asks for the same pair. Do not dispose the returned painter — the
  /// cache owns it. Do not mutate it either: laying out again with different
  /// constraints would corrupt every other frame sharing it.
  TextPainter line(String text, TextStyle style) {
    final key = _LineKey(text, style);
    final hit = _entries.remove(key);
    if (hit != null) {
      // Reinsert at the end: recently painted stays, long-unseen goes first.
      _entries[key] = hit;
      hits++;
      return hit;
    }
    misses++;
    final painter =
        TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
          )
          ..layout();
    _entries[key] = painter;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first)?.dispose();
    }
    return painter;
  }

  @visibleForTesting
  int get length => _entries.length;

  void dispose() {
    for (final painter in _entries.values) {
      painter.dispose();
    }
    _entries.clear();
  }
}

/// The pixels, as a map key. [TextStyle.==] is a value comparison over every
/// field that affects shaping, so two keys are equal exactly when their
/// painters would draw identically.
@immutable
class _LineKey {
  const _LineKey(this.text, this.style);

  final String text;
  final TextStyle style;

  @override
  bool operator ==(Object other) =>
      other is _LineKey && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);
}
