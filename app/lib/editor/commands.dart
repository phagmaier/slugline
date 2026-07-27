import 'package:flutter/foundation.dart';

import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';

/// One entry in the command palette.
class EditorCommand {
  const EditorCommand({
    required this.group,
    required this.label,
    required this.run,
    this.shortcut = '',
  });

  /// The heading the palette files it under.
  final String group;
  final String label;

  /// The key that does the same thing, shown so that the palette teaches the
  /// keyboard instead of replacing it.
  final String shortcut;

  final VoidCallback run;
}

/// Every command the palette offers (§Phase 3: "covering every element type and
/// command").
///
/// The list is built rather than declared so that the element types come from
/// [elementChoices] — one table, so the palette and `Ctrl+<digit>` cannot offer
/// different sets.
List<EditorCommand> editorCommands({
  required EditorController controller,
  required VoidCallback openFind,
  VoidCallback? openNavigator,
  VoidCallback? save,
  VoidCallback? saveAs,
  VoidCallback? showBackups,
  VoidCallback? editTitlePage,
  VoidCallback? previewAndExport,
}) {
  return [
    // Phase 4's file commands, and null where there is no persistence attached —
    // which is a widget test driving the palette on its own. A palette entry
    // that does nothing is worse than one that is not there.
    if (save case final run?)
      EditorCommand(group: 'File', label: 'Save', shortcut: 'Ctrl+S', run: run),
    if (saveAs case final run?)
      EditorCommand(
        group: 'File',
        label: 'Save as…',
        shortcut: 'Ctrl+Shift+S',
        run: run,
      ),
    if (showBackups case final run?)
      EditorCommand(group: 'File', label: 'Previous versions…', run: run),
    // Phase 7. "Export" is not among the labels on purpose: the export lives
    // inside the preview, because §Phase 7 wants a writer to have looked at the
    // pages before they send them anywhere.
    if (editTitlePage case final run?)
      EditorCommand(group: 'File', label: 'Title page…', run: run),
    if (previewAndExport case final run?)
      EditorCommand(
        group: 'File',
        label: 'Preview and export…',
        shortcut: 'Ctrl+P',
        run: run,
      ),
    for (final choice in elementChoices)
      EditorCommand(
        group: 'Element',
        label: choice.label,
        shortcut: choice.shortcut,
        run: () =>
            controller.setKind(choice.kind, sectionLevel: choice.sectionLevel),
      ),
    EditorCommand(
      group: 'Element',
      label: 'Next element type',
      shortcut: 'Tab',
      run: controller.cycleElement,
    ),
    EditorCommand(
      group: 'Element',
      label: 'Previous element type',
      shortcut: 'Shift+Tab',
      run: () => controller.cycleElement(reverse: true),
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Undo',
      shortcut: 'Ctrl+Z',
      run: controller.undo,
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Redo',
      shortcut: 'Ctrl+Shift+Z',
      run: controller.redo,
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Cut',
      shortcut: 'Ctrl+X',
      run: controller.cut,
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Copy',
      shortcut: 'Ctrl+C',
      run: controller.copy,
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Paste',
      shortcut: 'Ctrl+V',
      run: controller.paste,
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Paste as plain text',
      shortcut: 'Ctrl+Shift+V',
      run: () => controller.paste(plain: true),
    ),
    EditorCommand(
      group: 'Edit',
      label: 'Select all',
      shortcut: 'Ctrl+A',
      run: controller.selectAll,
    ),
    EditorCommand(
      group: 'Find',
      label: 'Find and replace',
      shortcut: 'Ctrl+F',
      run: openFind,
    ),
    EditorCommand(
      group: 'Find',
      label: 'Find next',
      shortcut: 'Ctrl+G',
      run: controller.nextMatch,
    ),
    EditorCommand(
      group: 'Find',
      label: 'Find previous',
      shortcut: 'Ctrl+Shift+G',
      run: controller.previousMatch,
    ),
    if (openNavigator case final run?)
      EditorCommand(
        group: 'Go to',
        label: 'Jump to scene…',
        shortcut: 'Ctrl+J',
        run: run,
      ),
    EditorCommand(
      group: 'Go to',
      label: 'Start of script',
      shortcut: 'Ctrl+Home',
      run: () => controller.moveToDocumentEdge(start: true),
    ),
    EditorCommand(
      group: 'Go to',
      label: 'End of script',
      shortcut: 'Ctrl+End',
      run: () => controller.moveToDocumentEdge(start: false),
    ),
  ];
}

/// The commands matching [query], best first. An empty query keeps the order the
/// list was declared in, which is the order a writer will learn.
///
/// Matching is a subsequence, not a substring, so `sh` finds "Scene heading" and
/// `pplain` finds "Paste as plain text". The score prefers a match that starts
/// at the beginning of the label, then one that starts at the beginning of a
/// word, then anything else — enough to put the obvious answer first without
/// pretending to be a fuzzy finder.
List<EditorCommand> filterCommands(List<EditorCommand> commands, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return commands;
  final scored = <(int, int, EditorCommand)>[];
  for (var i = 0; i < commands.length; i++) {
    final score = _score(commands[i].label.toLowerCase(), needle);
    if (score != null) scored.add((score, i, commands[i]));
  }
  // The index is the tie-breaker, so equal scores keep the declared order.
  scored.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return [for (final entry in scored) entry.$3];
}

/// A lower score is a better match; `null` is no match at all.
int? _score(String label, String needle) {
  var at = 0;
  var penalty = 0;
  for (final want in needle.codeUnits) {
    final found = label.indexOf(String.fromCharCode(want), at);
    if (found < 0) return null;
    // Landing at the start of the label costs nothing, at the start of a word a
    // little, and mid-word more — so `sh` prefers "Scene heading" to "Synopsis".
    penalty += switch (found) {
      0 => 0,
      _ when label[found - 1] == ' ' => 1,
      _ => 4,
    };
    at = found + 1;
  }
  return penalty;
}
