import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/theme.dart';

/// Phase 9's installed-language selector and master switch.
class SpellDialog extends StatefulWidget {
  const SpellDialog({required this.controller, super.key});

  final EditorController controller;

  static Future<void> show(BuildContext context, EditorController controller) =>
      showDialog<void>(
        context: context,
        builder: (context) => SpellDialog(controller: controller),
      );

  @override
  State<SpellDialog> createState() => _SpellDialogState();
}

class _SpellDialogState extends State<SpellDialog> {
  late bool _enabled = widget.controller.spellStatus.enabled;
  late String? _language = widget.controller.spellStatus.language;
  bool _saving = false;
  String? _error;

  SpellStatus get _status => widget.controller.spellStatus;

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.controller.configureSpelling(
      enabled: _enabled,
      language: _language,
    );
    if (!mounted) return;
    switch (result) {
      case SpellActionResult_Applied():
        Navigator.of(context).pop();
      case SpellActionResult_Failed(:final message):
        setState(() {
          _saving = false;
          _error = message;
        });
      case SpellActionResult_NoScriptPath():
        setState(() {
          _saving = false;
          _error = 'The script must be saved first.';
        });
      case SpellActionResult_NoSuchDocument():
        setState(() {
          _saving = false;
          _error = 'The script is no longer open.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApply = !_saving && (!_enabled || _status.languages.isNotEmpty);
    return AlertDialog(
      title: const Text('Spell checking'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('spell enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Check spelling'),
              value: _enabled,
              onChanged: _saving
                  ? null
                  : (enabled) => setState(() => _enabled = enabled),
            ),
            if (_status.languages.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const ValueKey('spell language'),
                initialValue:
                    _status.languages.any(
                      (language) => language.code == _language,
                    )
                    ? _language
                    : _status.languages.first.code,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final language in _status.languages)
                    DropdownMenuItem(
                      value: language.code,
                      child: Text(language.label),
                    ),
                ],
                onChanged: _enabled && !_saving
                    ? (language) => setState(() => _language = language)
                    : null,
              )
            else
              Text(
                _status.message,
                key: const ValueKey('spell unavailable'),
                style: TextStyle(color: context.colours.danger),
              ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('spell error'),
                style: TextStyle(color: context.colours.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('apply spelling'),
          onPressed: canApply ? _apply : null,
          child: Text(_saving ? 'Applying…' : 'Apply'),
        ),
      ],
    );
  }
}
