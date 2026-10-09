import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/theme.dart';
import 'package:slugline/typography.dart';
import 'package:slugline/widgets/escape_dismissible.dart';

/// Previous versions can be read without changing the current script, restored,
/// or saved to a new file and opened in another window.
class BackupsDialog extends StatefulWidget {
  const BackupsDialog({required this.core, required this.openCopy, super.key});

  final DocumentCore core;

  /// The desktop launch seam; widget tests do not start a second application.
  final Future<void> Function(String path) openCopy;

  /// Returns true only if a backup replaced the current script.
  static Future<bool> show(
    BuildContext context,
    DocumentCore core, {
    required Future<void> Function(String source) openCopy,
  }) async {
    final restored = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackupsDialog(core: core, openCopy: openCopy),
    );
    return restored ?? false;
  }

  @override
  State<BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<BackupsDialog> {
  List<BackupView>? _backups;
  BackupView? _viewing;
  String? _source;
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backups = await widget.core.backups();
    if (!mounted) return;
    setState(() => _backups = backups);
  }

  Future<void> _view(BackupView backup) async {
    setState(() {
      _working = true;
      _error = null;
    });
    final outcome = await widget.core.readBackup(backup.path);
    if (!mounted) return;
    setState(() {
      _working = false;
      switch (outcome) {
        case BackupReadOutcome_Read(:final source):
          _viewing = backup;
          _source = source;
        case BackupReadOutcome_Failed(:final message):
          _error = message;
      }
    });
  }

  Future<void> _restore(BackupView backup) async {
    setState(() {
      _working = true;
      _error = null;
    });
    final outcome = await widget.core.restoreBackup(backup.path);
    if (!mounted) return;
    switch (outcome) {
      case SaveOutcome_Saved():
        Navigator.of(context).pop(true);
      case SaveOutcome_Failed(:final message):
        setState(() {
          _working = false;
          _error = message;
        });
      case SaveOutcome_Unchanged():
        setState(() => _working = false);
    }
  }

  Future<void> _copy() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final source = _source;
    if (source == null) return;
    Navigator.of(context).pop(false);
    await widget.openCopy(source);
  }

  void _back() {
    setState(() {
      _viewing = null;
      _source = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backups = _backups;
    final viewing = _viewing;
    return PopScope(
      canPop: !_working,
      child: EscapeDismissible(
        child: AlertDialog(
          title: Text(
            viewing == null
                ? 'Previous versions'
                : formatTimestamp(viewing.writtenMillis),
          ),
          content: SizedBox(
            width: viewing == null ? 540 : 720,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  viewing == null
                      ? 'View a version without changing your script, or open it '
                            'as a new library script. Restoring backs up '
                            'the current version first.'
                      : 'Read-only Fountain text. Open as copy leaves your '
                            'current script untouched.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: viewing != null
                      ? Scrollbar(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _source!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: scriptFontFamily,
                              ),
                            ),
                          ),
                        )
                      : switch (backups) {
                          null => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          [] => Center(
                            child: Text(
                              'No previous versions yet. Opening preserves '
                              'changed on-disk text. Autosave snapshots changed '
                              'text at most every ten minutes. Saving by hand '
                              'records a version every time.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          final found => ListView.builder(
                            itemCount: found.length,
                            itemBuilder: (context, index) {
                              final backup = found[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  formatTimestamp(backup.writtenMillis),
                                ),
                                subtitle: Text(formatBytes(backup.bytes)),
                                onTap: _working ? null : () => _view(backup),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: _working
                                          ? null
                                          : () => _view(backup),
                                      child: const Text('View'),
                                    ),
                                    TextButton(
                                      onPressed: _working
                                          ? null
                                          : () => _restore(backup),
                                      child: const Text('Restore'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        },
                ),
                if (_working) const LinearProgressIndicator(),
                if (_error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.colours.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (viewing != null) ...[
              TextButton(
                onPressed: _working ? null : _back,
                child: const Text('Back'),
              ),
              TextButton(
                onPressed: _working ? null : () => _restore(viewing),
                child: const Text('Restore'),
              ),
              FilledButton(
                onPressed: _working ? null : _copy,
                child: Text('Open as copy'),
              ),
            ],
            TextButton(
              onPressed: _working
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unix milliseconds as a local date and time.
///
/// Formatted here rather than in Rust because a date's appearance is a locale
/// question and the core has no locale — and because `intl` is a dependency for
/// one line (§1.2).
String formatTimestamp(int millis) {
  final when = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final now = DateTime.now();
  final time = '${_two(when.hour)}:${_two(when.minute)}';
  if (when.year == now.year && when.month == now.month && when.day == now.day) {
    return 'Today at $time';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (when.year == yesterday.year &&
      when.month == yesterday.month &&
      when.day == yesterday.day) {
    return 'Yesterday at $time';
  }
  return '${when.year}-${_two(when.month)}-${_two(when.day)} at $time';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _two(int value) => value.toString().padLeft(2, '0');
