import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';

/// The title page, editable (§Phase 7).
///
/// ## It is the Fountain title page, not a form beside it
///
/// Every field here is a `Key: value` pair in the file. There is no separate
/// store, nothing is kept in this widget between openings, and closing the
/// dialog writes nothing that was not already written — each field is committed
/// through [DocumentCore.setTitleField] as it loses focus, which is one undo
/// step per field and the same path a crash journal records (ADR 0033).
///
/// ## Looking is not editing
///
/// Only a box whose text has changed is committed. A title page opened and
/// closed is the title page it was: no edit, no undo step, nothing unsaved.
///
/// ## Why the keys are strings
///
/// §Phase 7 names six fields and "free-form additional text". The format allows
/// any key, and a writer who has typed `Revision Colour: Blue` into their script
/// has said something the application does not get to forget. So the six are
/// laid out as a form because they are the ones people fill in, everything else
/// is shown underneath in the order the file has it, and both go through the
/// same call.
class TitlePageDialog extends StatefulWidget {
  const TitlePageDialog({required this.core, this.onCommitted, super.key});

  final DocumentCore core;
  final VoidCallback? onCommitted;

  static Future<void> show(
    BuildContext context,
    DocumentCore core, {
    VoidCallback? onCommitted,
  }) => showDialog<void>(
    context: context,
    builder: (_) => TitlePageDialog(core: core, onCommitted: onCommitted),
  );

  @override
  State<TitlePageDialog> createState() => _TitlePageDialogState();
}

/// The keys §Phase 7 names, with the labels a writer recognises them by.
///
/// `Author` rather than `Authors`: the format has both, they mean the same
/// thing, and offering two boxes that overwrite each other's meaning would be a
/// worse answer than offering one. A file that already uses `Authors` keeps it,
/// because it appears among the additional fields below.
const List<(String, String, String)> _fields = [
  ('Title', 'Title', ''),
  ('Credit', 'Credit', 'Written by'),
  ('Author', 'Author', ''),
  ('Source', 'Source', 'Based on…'),
  ('Draft date', 'Draft date', ''),
  ('Contact', 'Contact', ''),
  ('Notes', 'Notes', ''),
];

class _TitlePageDialogState extends State<TitlePageDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focus = {};

  /// What the core holds under each key: as read on opening, then as this form
  /// last wrote it. A key with no entry holds nothing.
  final Map<String, String> _held = {};

  /// Keys the file has that the form above does not name.
  List<String> _extra = const [];

  @override
  void initState() {
    super.initState();
    // A file may repeat a key. The first entry is the one `setTitleField` reads
    // and writes, so it is the one a box shows; the later ones stay in the file
    // as they are, and are not this form's to merge.
    for (final entry in widget.core.titlePage()) {
      _held.putIfAbsent(entry.key, () => entry.value);
    }
    _extra = [
      for (final key in _held.keys)
        if (!_fields.any((field) => field.$1 == key)) key,
    ];
    for (final key in [for (final field in _fields) field.$1, ..._extra]) {
      _controllers[key] = TextEditingController(text: _held[key] ?? '');
      _focus[key] = FocusNode()
        ..addListener(() {
          if (!_focus[key]!.hasFocus) _commit(key);
        });
    }
  }

  @override
  void dispose() {
    // Committed on the way out as well as on focus loss: closing the dialog with
    // the caret still in a box is the ordinary way to finish typing in one, and
    // it must not be the way to lose what was typed.
    for (final key in _controllers.keys) {
      _commit(key);
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Writes one field through the core, if its box has changed.
  ///
  /// A box nobody typed in is never sent. What it shows is not always what a
  /// write of it would leave — a key the file wrote with nothing after it reads
  /// as empty, and sending empty removes the line.
  void _commit(String key) {
    final text = _controllers[key]!.text;
    if (text == (_held[key] ?? '')) return;
    final outcome = widget.core.setTitleField(key, text);
    if (outcome is! EditOutcome_Applied) return;
    _held[key] = text;
    widget.onCommitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Title page'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (key, label, hint) in _fields) _box(key, label, hint),
              if (_extra.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Also in this file',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final key in _extra) _box(key, key, ''),
              ],
              const SizedBox(height: 12),
              Text(
                'These are the Fountain title page. Clearing a box removes the '
                'line from the file; the title page is not printed with a page '
                'number and is not page one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _box(String key, String label, String hint) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      key: Key('title-field-$key'),
      controller: _controllers[key],
      focusNode: _focus[key],
      minLines: 1,
      maxLines: null,
      onSubmitted: (_) => _commit(key),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}
