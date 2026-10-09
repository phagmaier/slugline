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
  final Map<String, List<_TitleBox>> _boxes = {};
  // Keep removed boxes alive until dispose: focus loss can be what removed one.
  final List<_TitleBox> _all = [];
  bool _closing = false;

  /// Keys the file has that the form above does not name.
  List<String> _extra = const [];

  @override
  void initState() {
    super.initState();
    for (final entry in widget.core.titlePage()) {
      _addBox(entry.key, entry.value);
    }
    _extra = [
      for (final key in _boxes.keys)
        if (!_fields.any((field) => field.$1 == key)) key,
    ];
    for (final (key, _, _) in _fields) {
      if (!_boxes.containsKey(key)) _addBox(key, '');
    }
  }

  void _addBox(String key, String value) {
    final group = _boxes.putIfAbsent(key, () => []);
    final box = _TitleBox(key, group.length, value);
    group.add(box);
    _all.add(box);
    box.focus.addListener(() {
      if (!box.focus.hasFocus) _commit(box);
    });
  }

  @override
  void dispose() {
    // Committed on the way out as well as on focus loss: closing the dialog with
    // the caret still in a box is the ordinary way to finish typing in one, and
    // it must not be the way to lose what was typed.
    _closing = true;
    for (final box in _all) {
      _commit(box);
    }
    for (final box in _all) {
      box.controller.dispose();
      box.focus.dispose();
    }
    super.dispose();
  }

  /// Writes one field through the core, if its box has changed.
  ///
  /// A box nobody typed in is never sent. What it shows is not always what a
  /// write of it would leave — a key the file wrote with nothing after it reads
  /// as empty, and sending empty removes the line.
  void _commit(_TitleBox box) {
    if (!box.active) return;
    final text = box.controller.text;
    if (text == box.held) return;
    final group = _boxes[box.key]!;
    final outcome = widget.core.setTitleField(
      box.key,
      text,
      occurrence: group.indexOf(box),
    );
    if (outcome is! EditOutcome_Applied) return;
    box.held = text;
    if (text.isEmpty) {
      // Removing a box shifts only this key's later occurrences. The remaining
      // boxes keep their controllers and their source entry, even with pending
      // text, and the next commit uses their new occurrence.
      group.remove(box);
      box.active = false;
      if (group.isEmpty && !_closing) {
        if (_fields.any((field) => field.$1 == box.key)) {
          _addBox(box.key, '');
        } else {
          _extra.remove(box.key);
        }
      }
    }
    if (!_closing) setState(() {});
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
              for (final (key, label, hint) in _fields)
                for (final box in _boxes[key]!) _box(box, label, hint),
              if (_extra.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Also in this file',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final key in _extra)
                  for (final box in _boxes[key]!) _box(box, key, ''),
              ],
              const SizedBox(height: 12),
              Text(
                'Each box is one Fountain title entry. Clearing a box removes '
                'only that entry; the title page is not printed with a page '
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

  Widget _box(_TitleBox box, String label, String hint) => Padding(
    key: ObjectKey(box),
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      key: box.widgetKey,
      controller: box.controller,
      focusNode: box.focus,
      minLines: 1,
      maxLines: null,
      onSubmitted: (_) => _commit(box),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}

class _TitleBox {
  _TitleBox(this.key, int occurrence, this.held)
    : widgetKey = Key(
        'title-field-$key${occurrence == 0 ? '' : '-${occurrence + 1}'}',
      ),
      controller = TextEditingController(text: held);

  final String key;
  final Key widgetKey;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  String held;
  bool active = true;
}
