/// The contract every prototype implements, so one benchmark script drives all
/// three and the numbers are comparable.
library;

import 'package:flutter/widgets.dart';

abstract class SpikeSurface {
  /// Scrolls so [blockIndex] is on screen and puts the caret in it.
  Future<void> placeCaret(int blockIndex, int offset);

  /// Types one character at the caret.
  Future<void> typeCharacter(String character);

  /// Presses Down once. Returns the block the caret ended up in, so the driver
  /// can confirm it actually crossed a paragraph boundary.
  Future<int> arrowDown();

  /// Selects from the start of [startBlock] to the end of `startBlock + 3` and
  /// returns the selection as plain text — the Phase 0 requirement.
  Future<String> selectFourParagraphsAsText(int startBlock);

  /// For scroll measurements.
  ScrollController get scrollController;

  /// Total paragraphs currently loaded.
  int get blockCount;
}
