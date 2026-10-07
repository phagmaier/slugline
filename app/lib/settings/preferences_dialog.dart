import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/identity.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/theme.dart';

/// Phase 10's single settings surface.
///
/// Values are returned as one immutable bridge view. The application persists
/// that view atomically, then applies the appearance-only values in memory so
/// no restart is needed.
class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({
    required this.preferences,
    required this.spelling,
    super.key,
  });

  final PreferencesView preferences;
  final SpellStatus spelling;

  static Future<PreferencesView?> show(
    BuildContext context, {
    required PreferencesView preferences,
    required SpellStatus spelling,
  }) => showDialog<PreferencesView>(
    context: context,
    builder: (context) =>
        PreferencesDialog(preferences: preferences, spelling: spelling),
  );

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late String _appearance = widget.preferences.appearance;
  late double _textSize = widget.preferences.editorTextSize.toDouble();
  late bool _spellEnabled = widget.spelling.enabled;
  late String? _spellLanguage =
      widget.spelling.language ??
      (widget.spelling.languages.isEmpty
          ? null
          : widget.spelling.languages.first.code);
  late bool _autosave = widget.preferences.autosaveEnabled;
  late bool _autocomplete = widget.preferences.autocompleteEnabled;
  late String _paper = widget.preferences.defaultPaper;
  late String _sceneNumbers = widget.preferences.sceneNumbers;
  late bool _boldSceneHeadings = widget.preferences.boldSceneHeadings;
  late bool _numberFirstPage = widget.preferences.numberFirstPage;
  late bool _distractionFree = widget.preferences.distractionFree;
  late bool _pageView = widget.preferences.pageView;

  late final TextEditingController _idle = TextEditingController(
    text: _seconds(widget.preferences.autosaveIdleMs),
  );
  late final TextEditingController _interval = TextEditingController(
    text: _seconds(widget.preferences.autosaveIntervalMs),
  );
  late final TextEditingController _font = TextEditingController(
    text: widget.preferences.pdfFontPath ?? '',
  );
  late final TextEditingController _backup = TextEditingController(
    text: widget.preferences.backupDir ?? '',
  );
  late final TextEditingController _versions = TextEditingController(
    text: '${widget.preferences.backupKeepVersions}',
  );
  late final TextEditingController _days = TextEditingController(
    text: '${widget.preferences.backupKeepDays}',
  );

  @override
  void dispose() {
    _idle.dispose();
    _interval.dispose();
    _font.dispose();
    _backup.dispose();
    _versions.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _chooseFont() async {
    final path = await FileChooser.show(
      context,
      title: 'Choose a TrueType monospace font',
      action: 'Choose',
      mustExist: true,
      extension: 'ttf',
    );
    if (path != null && mounted) setState(() => _font.text = path);
  }

  Future<void> _chooseBackupDirectory() async {
    final current = _backup.text.trim();
    final path = await FileChooser.show(
      context,
      title: 'Choose backup location',
      action: 'Use this folder',
      directory: current.isEmpty ? null : current,
      selectDirectory: true,
    );
    if (path != null && mounted) setState(() => _backup.text = path);
  }

  void _save() {
    final idleMs = (_number(_idle.text, 2, min: 0.25, max: 60) * 1000).round();
    final intervalMs = (_number(_interval.text, 30, min: 1, max: 3600) * 1000)
        .round();
    final font = _font.text.trim();
    final backup = _backup.text.trim();
    Navigator.of(context).pop(
      PreferencesView(
        autosaveEnabled: _autosave,
        autocompleteEnabled: _autocomplete,
        navigatorVisible: widget.preferences.navigatorVisible,
        spellEnabled: _spellEnabled,
        spellLanguage: _spellLanguage,
        appearance: _appearance,
        editorTextSize: _textSize.round(),
        defaultPaper: _paper,
        sceneNumbers: _sceneNumbers,
        boldSceneHeadings: _boldSceneHeadings,
        numberFirstPage: _numberFirstPage,
        pdfFontPath: font.isEmpty ? null : font,
        distractionFree: _distractionFree,
        pageView: _pageView,
        autosaveIdleMs: idleMs,
        autosaveIntervalMs: intervalMs,
        backupDir: backup.isEmpty ? null : backup,
        backupKeepVersions: _integer(_versions.text, 10, min: 1, max: 100),
        backupKeepDays: _integer(_days.text, 7, min: 1, max: 3650),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customFont = _font.text.trim().isNotEmpty;
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
              child: Row(
                children: [
                  Text(
                    'Preferences',
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  _heading(context, 'Appearance'),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('appearance preference'),
                    initialValue: _appearance,
                    decoration: const InputDecoration(labelText: 'Colour mode'),
                    items: const [
                      DropdownMenuItem(
                        value: 'system',
                        child: Text('Follow system'),
                      ),
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    ],
                    onChanged: (value) =>
                        setState(() => _appearance = value ?? 'system'),
                  ),
                  const SizedBox(height: 12),
                  Text('Editor text size: ${_textSize.round()}'),
                  Slider(
                    key: const ValueKey('editor text size'),
                    min: 12,
                    max: 24,
                    divisions: 12,
                    value: _textSize,
                    label: '${_textSize.round()}',
                    onChanged: (value) => setState(() => _textSize = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<bool>(
                    key: const ValueKey('page view preference'),
                    initialValue: _pageView,
                    decoration: const InputDecoration(labelText: 'Editor view'),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Page view')),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Continuous scroll'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _pageView = value ?? true),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      _pageView
                          ? 'The script is drawn as separate sheets of paper. '
                                'Page boundaries come from the paginator, so '
                                'they settle a moment after you stop typing.'
                          : 'One column, with a rule and a page number where '
                                'each page turns.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('distraction free preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Distraction-free full screen'),
                    subtitle: const Text('F11 toggles this while editing.'),
                    value: _distractionFree,
                    onChanged: (value) =>
                        setState(() => _distractionFree = value),
                  ),
                  const Divider(height: 32),
                  _heading(context, 'Writing'),
                  SwitchListTile(
                    key: const ValueKey('autocomplete preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autocomplete'),
                    value: _autocomplete,
                    onChanged: (value) => setState(() => _autocomplete = value),
                  ),
                  SwitchListTile(
                    key: const ValueKey('spell preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check spelling'),
                    value: _spellEnabled,
                    onChanged: (value) => setState(() => _spellEnabled = value),
                  ),
                  if (widget.spelling.languages.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: const ValueKey('spell language preference'),
                      initialValue:
                          widget.spelling.languages.any(
                            (language) => language.code == _spellLanguage,
                          )
                          ? _spellLanguage
                          : widget.spelling.languages.first.code,
                      decoration: const InputDecoration(labelText: 'Language'),
                      items: [
                        for (final language in widget.spelling.languages)
                          DropdownMenuItem(
                            value: language.code,
                            child: Text(language.label),
                          ),
                      ],
                      onChanged: _spellEnabled
                          ? (value) => setState(() => _spellLanguage = value)
                          : null,
                    )
                  else
                    Text(
                      widget.spelling.message,
                      style: TextStyle(color: context.colours.danger),
                    ),
                  const Divider(height: 32),
                  _heading(context, 'Autosave'),
                  SwitchListTile(
                    key: const ValueKey('autosave preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autosave'),
                    value: _autosave,
                    onChanged: (value) => setState(() => _autosave = value),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('autosave idle'),
                          controller: _idle,
                          enabled: _autosave,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'After inactivity',
                            suffixText: 'seconds',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('autosave interval'),
                          controller: _interval,
                          enabled: _autosave,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'While typing',
                            suffixText: 'seconds',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _heading(context, 'Page defaults'),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('paper preference'),
                          initialValue: _paper,
                          decoration: const InputDecoration(
                            labelText: 'Paper size',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'us_letter',
                              child: Text('US Letter'),
                            ),
                            DropdownMenuItem(value: 'a4', child: Text('A4')),
                          ],
                          onChanged: (value) =>
                              setState(() => _paper = value ?? 'us_letter'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('scene numbers preference'),
                          initialValue: _sceneNumbers,
                          decoration: const InputDecoration(
                            labelText: 'Scene numbers',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'off',
                              child: Text('Hidden'),
                            ),
                            DropdownMenuItem(
                              value: 'left',
                              child: Text('Left'),
                            ),
                            DropdownMenuItem(
                              value: 'right',
                              child: Text('Right'),
                            ),
                            DropdownMenuItem(
                              value: 'both',
                              child: Text('Both sides'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _sceneNumbers = value ?? 'off'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    key: const ValueKey('bold scene headings preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bold scene headings'),
                    value: _boldSceneHeadings,
                    onChanged: (value) =>
                        setState(() => _boldSceneHeadings = value),
                  ),
                  SwitchListTile(
                    key: const ValueKey('number first page preference'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Number the first page'),
                    subtitle: const Text(
                      'Page 1 is conventionally left unnumbered.',
                    ),
                    value: _numberFirstPage,
                    onChanged: (value) =>
                        setState(() => _numberFirstPage = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('pdf font preference'),
                    controller: _font,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'PDF font',
                      hintText: 'Courier Prime (recommended)',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (customFont)
                            IconButton(
                              tooltip: 'Use Courier Prime',
                              onPressed: () => setState(_font.clear),
                              icon: const Icon(Icons.restart_alt),
                            ),
                          IconButton(
                            tooltip: 'Choose system font file',
                            onPressed: _chooseFont,
                            icon: const Icon(Icons.folder_open),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (customFont)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Warning: non-standard fonts can break screenplay grid '
                        'fidelity. $applicationName keeps the fixed grid, but the chosen '
                        'face may not fit it.',
                        key: const ValueKey('font fidelity warning'),
                        style: TextStyle(color: context.colours.danger),
                      ),
                    ),
                  const Divider(height: 32),
                  _heading(context, 'Backups'),
                  TextField(
                    key: const ValueKey('backup location preference'),
                    controller: _backup,
                    decoration: InputDecoration(
                      labelText: 'Backup location',
                      hintText: 'Default $applicationName state directory',
                      suffixIcon: IconButton(
                        tooltip: 'Choose backup folder',
                        onPressed: _chooseBackupDirectory,
                        icon: const Icon(Icons.folder_open),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('backup versions preference'),
                          controller: _versions,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Keep versions',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('backup days preference'),
                          controller: _days,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Keep days',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('save preferences'),
                    onPressed: _save,
                    child: const Text('Save'),
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

Widget _heading(BuildContext context, String label) =>
    Text(label, style: Theme.of(context).textTheme.titleMedium);

String _seconds(int milliseconds) {
  final value = milliseconds / 1000;
  return value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(2);
}

double _number(
  String value,
  double fallback, {
  required double min,
  required double max,
}) => (double.tryParse(value) ?? fallback).clamp(min, max);

int _integer(
  String value,
  int fallback, {
  required int min,
  required int max,
}) => (int.tryParse(value) ?? fallback).clamp(min, max);
