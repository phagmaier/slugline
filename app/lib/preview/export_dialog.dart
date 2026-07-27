import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/preview/preview_view.dart';

/// Preview, then export (§Phase 7).
///
/// ## The flow
///
/// §Phase 7 asks for a "preview-before-export flow in the export dialog", and
/// this is it in one window: the pages on the left as they will print, the page
/// setup and the two exports on the right. Changing the paper repaginates —
/// through Rust, which is the only thing that paginates — and the preview and
/// the PDF are therefore looking at the same answer by construction.
///
/// ## The two exports are not the same operation
///
/// "Export PDF" writes pages. "Export Fountain copy" writes the script's own
/// text somewhere else. Neither is Save As: an export copies and the session
/// stays where it is, and only Save As rebinds a writer's session to a new file
/// (ADR 0029). That is why this dialog calls [DocumentCore.exportFountain] and
/// [ScreenplayOutput.exportPdf] and never `saveAs`.
///
/// ## The refusals
///
/// The core refuses a destination that already exists and one that is a script
/// open here, and both refusals are the core's rather than this dialog's, so
/// there is no way to skip them from the outside. What the dialog does with them
/// is what §Phase 7 asks: ask about the first and re-export saying yes, and
/// report the second as the refusal it is.
/// Asks the writer where a file should go. Null if they closed the chooser.
typedef PathChooser =
    Future<String?> Function(
      BuildContext context, {
      required String title,
      required String suggestedName,
      required String? directory,
    });

class ExportDialog extends StatefulWidget {
  const ExportDialog({
    required this.core,
    required this.output,
    this.chooseFile = _chooseWithFileChooser,
    super.key,
  });

  final DocumentCore core;
  final ScreenplayOutput output;

  /// How a destination is asked for. The application's own chooser, and a seam
  /// a test replaces — what §Phase 7 specifies about exporting is what happens
  /// to the *answer*, and a widget test should not need a real directory to
  /// exercise it.
  final PathChooser chooseFile;

  static Future<void> show(
    BuildContext context,
    DocumentCore core,
    ScreenplayOutput output,
  ) => showDialog<void>(
    context: context,
    builder: (_) => ExportDialog(core: core, output: output),
  );

  static Future<String?> _chooseWithFileChooser(
    BuildContext context, {
    required String title,
    required String suggestedName,
    required String? directory,
  }) => FileChooser.show(
    context,
    title: title,
    action: 'Export',
    directory: directory,
    suggestedName: suggestedName,
  );

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  PaperSize _paper = PaperSize.usLetter;
  bool _sceneNumbers = false;
  double _scale = 4.2;

  late Future<PaginationOutcome> _pagination;

  /// What the last export said, shown under the buttons rather than as a toast:
  /// an export that did not happen is not something to scroll past.
  String? _report;
  bool _reportIsFailure = false;

  PageSetup get _setup => PageSetup(
    paper: _paper,
    sceneNumbers: _sceneNumbers ? SceneNumbers.both : SceneNumbers.off,
    // Never set outside the Phase 6F diagnostic: a real preview and a real
    // export take the row count from the paper (§5.2).
    debugLinesPerPage: null,
  );

  @override
  void initState() {
    super.initState();
    _repaginate();
  }

  void _repaginate() {
    _pagination = widget.output.paginate(_setup);
  }

  void _setPaper(PaperSize paper) {
    if (paper == _paper) return;
    setState(() {
      _paper = paper;
      _repaginate();
    });
  }

  void _setSceneNumbers(bool on) {
    if (on == _sceneNumbers) return;
    setState(() {
      _sceneNumbers = on;
      _repaginate();
    });
  }

  // --- exporting -------------------------------------------------------------

  Future<void> _exportPdf() async {
    final path = await _ask('Export PDF', 'pdf');
    if (path == null || !mounted) return;
    var outcome = await widget.output.exportPdf(path, setup: _setup);
    outcome = await _confirmOverwrite(
      outcome,
      (overwrite) =>
          widget.output.exportPdf(path, setup: _setup, overwrite: overwrite),
    );
    _record(outcome, 'PDF');
  }

  Future<void> _exportFountain() async {
    final path = await _ask('Export Fountain copy', 'fountain');
    if (path == null || !mounted) return;
    var outcome = await widget.core.exportFountain(path);
    outcome = await _confirmOverwrite(
      outcome,
      (overwrite) => widget.core.exportFountain(path, overwrite: overwrite),
    );
    _record(outcome, 'copy');
  }

  Future<String?> _ask(String title, String extension) {
    final existing = widget.core.path;
    final stem = existing == null
        ? 'untitled'
        : _basename(existing).replaceAll(RegExp(r'\.fountain$'), '');
    return widget.chooseFile(
      context,
      title: title,
      suggestedName: '$stem.$extension',
      directory: existing == null ? null : _parent(existing),
    );
  }

  /// `AlreadyExists` is a question, so it is asked and then answered by calling
  /// again with `overwrite: true` — never by the dialog deciding for itself.
  /// `ScriptIsOpen` is not a question and is not re-tried.
  Future<SaveOutcome> _confirmOverwrite(
    SaveOutcome outcome,
    Future<SaveOutcome> Function(bool overwrite) again,
  ) async {
    if (outcome is! SaveOutcome_Failed) return outcome;
    if (outcome.failure != SaveFailure.alreadyExists) return outcome;
    if (!mounted) return outcome;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.help_outline),
        title: const Text('There is already a file there'),
        content: Text(
          '${outcome.path} exists. Replacing it cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (replace != true) return outcome;
    return again(true);
  }

  void _record(SaveOutcome outcome, String what) {
    if (!mounted) return;
    setState(() {
      switch (outcome) {
        case SaveOutcome_Saved(:final path, :final bytes):
          _reportIsFailure = false;
          _report = 'Wrote ${_size(bytes)} to $path';
        case SaveOutcome_Failed(:final failure)
            when failure == SaveFailure.noPath:
          // The chooser was closed. Nothing happened and nothing is wrong.
          _report = null;
          _reportIsFailure = false;
        case SaveOutcome_Failed(:final failure, :final message):
          _reportIsFailure = true;
          _report = switch (failure) {
            SaveFailure.scriptIsOpen =>
              'That file is a script open here. Save it rather than '
                  'exporting a $what over it.',
            SaveFailure.alreadyExists => 'The file was left as it was.',
            _ => message,
          };
        case SaveOutcome_Unchanged():
          _reportIsFailure = false;
          _report = 'Nothing needed writing.';
      }
    });
  }

  // --- the window ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 940,
        height: 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
              child: Row(
                children: [
                  Text(
                    'Preview and export',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _preview()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 300, child: _sidebar(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    return FutureBuilder<PaginationOutcome>(
      future: _pagination,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SelectableText('The preview failed: ${snapshot.error}'),
          );
        }
        final outcome = snapshot.data;
        if (outcome == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return switch (outcome) {
          // A stale pagination is a correct pagination of the text that was
          // there a moment ago (ADR 0020). It is shown rather than swallowed —
          // the alternative is a blank window while the writer types — and the
          // export takes its own, newer one.
          PaginationOutcome_Current(:final pagination) ||
          PaginationOutcome_Stale(:final pagination) => PreviewView(
            pagination: pagination,
            paper: _paper,
            scale: _scale,
          ),
          PaginationOutcome_NoSuchDocument() => const Center(
            child: Text('The document is no longer open.'),
          ),
        };
      },
    );
  }

  /// The page setup scrolls; the two exports and what they said do not.
  ///
  /// A writer should never have to scroll to find out whether their PDF was
  /// written, and an export that was refused is not something to go looking for.
  Widget _sidebar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _setupControls(context)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                key: const Key('export-pdf'),
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF…'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('export-fountain'),
                onPressed: _exportFountain,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Export Fountain copy…'),
              ),
              const SizedBox(height: 8),
              Text(
                'An export writes a copy. This script stays where it is — use '
                'Save as to move it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_report case final report?) ...[
                const SizedBox(height: 12),
                SelectableText(
                  report,
                  key: const Key('export-report'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _reportIsFailure
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _setupControls(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        Text('Paper', style: Theme.of(context).textTheme.labelLarge),
        RadioGroup<PaperSize>(
          groupValue: _paper,
          onChanged: (paper) => _setPaper(paper ?? PaperSize.usLetter),
          child: const Column(
            children: [
              RadioListTile<PaperSize>(
                key: Key('paper-us-letter'),
                value: PaperSize.usLetter,
                dense: true,
                title: Text('US Letter'),
              ),
              RadioListTile<PaperSize>(
                key: Key('paper-a4'),
                value: PaperSize.a4,
                dense: true,
                title: Text('A4'),
              ),
            ],
          ),
        ),
        const Divider(),
        SwitchListTile(
          key: const Key('scene-numbers'),
          value: _sceneNumbers,
          onChanged: _setSceneNumbers,
          dense: true,
          title: const Text('Scene numbers'),
          subtitle: const Text('In both margins, where the script has them'),
        ),
        const Divider(),
        Text('Preview size', style: Theme.of(context).textTheme.labelLarge),
        Slider(
          key: const Key('preview-scale'),
          value: _scale,
          min: 2.4,
          max: 9.6,
          onChanged: (scale) => setState(() => _scale = scale),
        ),
        Text(
          'Preview size changes nothing about the pages. The page count, the '
          'line breaks and the PDF are the same at every size.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _size(int bytes) => bytes < 1024
    ? '$bytes bytes'
    : '${(bytes / 1024).toStringAsFixed(bytes < 1024 * 1024 ? 0 : 1)} '
          '${bytes < 1024 * 1024 ? 'kB' : 'MB'}';

String _parent(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
