import 'package:flutter/material.dart';

/// These are conversion diagnostics, not a promise of production-layout fidelity.
Future<bool> confirmFdxWarnings(
  BuildContext context,
  List<String> warnings, {
  required bool importing,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          importing
              ? 'Import FDX with conversion warnings?'
              : 'Export FDX with conversion warnings?',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  importing
                      ? 'FDX becomes a new, unsaved Fountain script. The source file is not changed. Production revisions, locked pages, fonts and margins are not preserved exactly.'
                      : 'FDX is an interchange copy of screenplay content, not an exact copy of production revisions, locked pages, fonts or margins. Your Fountain script is not changed.',
                ),
                const SizedBox(height: 16),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(warning),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(importing ? 'Import' : 'Export copy'),
          ),
        ],
      ),
    ) ??
    false;
