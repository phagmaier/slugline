import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';

/// §Phase 4's "Restore previous version" — the list of rolling backups, with
/// timestamps and sizes.
///
/// The confirmation is not boilerplate. Restoring replaces what is on screen and
/// what is on disk, so the dialog says the one thing that makes it safe:
/// **the current version is backed up first.** That is a §Phase 4 requirement
/// ("restoring a backup writes the current state to a new backup first") and it
/// is what turns a restore from a decision into an experiment.
class BackupsDialog extends StatefulWidget {
  const BackupsDialog({required this.core, super.key});

  final DocumentCore core;

  /// Returns true if a backup was restored.
  static Future<bool> show(BuildContext context, DocumentCore core) async {
    final restored = await showDialog<bool>(
      context: context,
      builder: (context) => BackupsDialog(core: core),
    );
    return restored ?? false;
  }

  @override
  State<BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<BackupsDialog> {
  List<BackupView>? _backups;
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

  Future<void> _restore(BackupView backup) async {
    setState(() => _working = true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backups = _backups;
    return AlertDialog(
      title: const Text('Previous versions'),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Restoring one of these writes the version you have now to a new '
              'backup first, so nothing here is a one-way door.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (backups) {
                null => const Center(child: CircularProgressIndicator()),
                [] => Center(
                    child: Text(
                      'No backups yet. One is written every time you save.',
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
                        title: Text(formatTimestamp(backup.writtenMillis)),
                        subtitle: Text(formatBytes(backup.bytes)),
                        trailing: TextButton(
                          onPressed:
                              _working ? null : () => unawaitedRestore(backup),
                          child: const Text('Restore'),
                        ),
                      );
                    },
                  ),
              },
            ),
            if (_error case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void unawaitedRestore(BackupView backup) {
    _restore(backup);
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
