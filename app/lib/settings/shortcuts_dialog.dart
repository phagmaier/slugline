import 'package:flutter/material.dart';

/// The in-app reference for `docs/KEYMAP.md`.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const ShortcutsDialog(),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 700,
        height: 680,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
              child: Row(
                children: [
                  Text(
                    'Keyboard shortcuts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  for (final section in _sections) ...[
                    Text(
                      section.$1,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    for (final shortcut in section.$2)
                      _ShortcutRow(keys: shortcut.$1, action: shortcut.$2),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    'Tab follows screenplay context: it accepts a visible '
                    'completion, otherwise cycles the current element where the '
                    'workflow allows it. Escape never changes text.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            // The fixed-width column is what lines the keys up; the face does
            // not have to, and a monospace one here is the script's type system
            // leaking into a dialog.
            child: Text(
              keys,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

const _sections = <(String, List<(String, String)>)>[
  (
    'Files and view',
    [
      ('Ctrl+N', 'New script…'),
      ('Ctrl+O', 'Quick-open scripts; Browse… for another file'),
      ('Ctrl+W', 'Back to the library'),
      ('↑ / ↓ / Enter', 'Select / open a library or quick-open script'),
      ('Ctrl+S', 'Save'),
      ('Ctrl+Shift+S', 'Save as…'),
      ('Ctrl+P', 'Preview and export…'),
      ('Ctrl+,', 'Preferences'),
      ('Ctrl++ / Ctrl+-', 'Increase / decrease editor text size'),
      ('F1', 'Keyboard shortcut reference'),
      ('F11', 'Distraction-free full screen'),
    ],
  ),
  (
    'Editing',
    [
      ('Ctrl+Z', 'Undo'),
      ('Ctrl+Shift+Z / Ctrl+Y', 'Redo'),
      ('Ctrl+X / Ctrl+C / Ctrl+V', 'Cut, copy, and Fountain-aware paste'),
      ('Ctrl+Shift+V', 'Paste as plain Action text'),
      ('Ctrl+A', 'Select all'),
      ('Ctrl+Space', 'Show suggestions, including the cast in an empty cue'),
      (
        'Shift+Enter',
        'Line break in Action, Dialogue or Note; Enter elsewhere',
      ),
      ('Ctrl+Backspace / Ctrl+Delete', 'Delete one word'),
      ('Tab / Shift+Tab', 'Cycle the context-appropriate element'),
      ('Ctrl+1 … Ctrl+0', 'Set screenplay element type'),
    ],
  ),
  (
    'Find and navigate',
    [
      ('Ctrl+K', 'Command palette'),
      ('Ctrl+F', 'Find and replace'),
      ('Ctrl+G / Ctrl+Shift+G', 'Next / previous match'),
      ('Ctrl+J', 'Scene and character navigator'),
      ('Ctrl+L', 'Go to page…'),
      ('Ctrl+Home / Ctrl+End', 'Start / end of script'),
      ('PageUp / PageDown', 'Move one screen'),
      ('Escape', 'Dismiss the open surface; never delete text'),
    ],
  ),
];
