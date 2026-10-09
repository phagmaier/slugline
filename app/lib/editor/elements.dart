import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/metrics.dart';

/// One element type the UI offers, and the digit that reaches it.
///
/// This is a **keyboard map**, not a screenplay rule: which digit means which
/// element is a preference (Phase 10 makes it one), and nothing here decides what
/// an element *is* or what follows it. Those questions go to the core — see
/// `document/src/workflow.rs` and `docs/KEYMAP.md`.
class ElementChoice {
  const ElementChoice(this.kind, {this.sectionLevel = 1, this.digit});

  final BlockKind kind;

  /// Only meaningful for [BlockKind.section] (ADR 0009 keeps the level beside
  /// the kind rather than inside it).
  final int sectionLevel;

  /// The digit in `Ctrl+<digit>`, or `null` for the ones only the palette
  /// reaches. Ten digits, more element types than digits.
  final int? digit;

  String get label => kindLabel(kind, sectionLevel);

  /// `Ctrl+3`, or an empty string where there is no shortcut.
  String get shortcut => digit == null ? '' : 'Ctrl+$digit';
}

/// Palette-only cue command: no keyboard shortcut is assigned.
const String toggleDualDialogueLabel = 'Toggle dual dialogue';

/// Whole-script commands, available only through the palette.
const String numberScenesLabel = 'Number scenes';
const String removeSceneNumbersLabel = 'Remove scene numbers';

/// The element types a writer can set, in the order the selector lists them:
/// the six that make up a scene first, then the rest.
///
/// [BlockKind.opaque] is absent on purpose. It is content the editor does not
/// model and that round-trips verbatim (§3.2); the core refuses every edit to
/// one, so offering it would be offering a refusal.
const List<ElementChoice> elementChoices = [
  ElementChoice(BlockKind.sceneHeading, digit: 1),
  ElementChoice(BlockKind.action, digit: 2),
  ElementChoice(BlockKind.character, digit: 3),
  ElementChoice(BlockKind.dialogue, digit: 4),
  ElementChoice(BlockKind.parenthetical, digit: 5),
  ElementChoice(BlockKind.transition, digit: 6),
  ElementChoice(BlockKind.centered, digit: 7),
  ElementChoice(BlockKind.lyric, digit: 8),
  ElementChoice(BlockKind.section, digit: 9),
  ElementChoice(BlockKind.synopsis, digit: 0),
  ElementChoice(BlockKind.note),
  ElementChoice(BlockKind.pageBreak),
];

/// `Ctrl+1` … `Ctrl+0`, as logical keys. Both rows: the number pad sends
/// different keys from the digits above the letters, and a writer using one does
/// not expect the shortcut to stop working.
final Map<LogicalKeyboardKey, ElementChoice> elementShortcuts = {
  for (final choice in elementChoices)
    if (choice.digit case final digit?) ...{
      _digitKeys[digit]!: choice,
      _numpadKeys[digit]!: choice,
    },
};

const Map<int, LogicalKeyboardKey> _digitKeys = {
  0: LogicalKeyboardKey.digit0,
  1: LogicalKeyboardKey.digit1,
  2: LogicalKeyboardKey.digit2,
  3: LogicalKeyboardKey.digit3,
  4: LogicalKeyboardKey.digit4,
  5: LogicalKeyboardKey.digit5,
  6: LogicalKeyboardKey.digit6,
  7: LogicalKeyboardKey.digit7,
  8: LogicalKeyboardKey.digit8,
  9: LogicalKeyboardKey.digit9,
};

const Map<int, LogicalKeyboardKey> _numpadKeys = {
  0: LogicalKeyboardKey.numpad0,
  1: LogicalKeyboardKey.numpad1,
  2: LogicalKeyboardKey.numpad2,
  3: LogicalKeyboardKey.numpad3,
  4: LogicalKeyboardKey.numpad4,
  5: LogicalKeyboardKey.numpad5,
  6: LogicalKeyboardKey.numpad6,
  7: LogicalKeyboardKey.numpad7,
  8: LogicalKeyboardKey.numpad8,
  9: LogicalKeyboardKey.numpad9,
};
