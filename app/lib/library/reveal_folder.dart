import 'dart:io';
import 'package:flutter/material.dart';

Future<void> revealFolder(BuildContext context, String path) async {
  try {
    if (!await Directory(path).exists()) {
      throw FileSystemException('Folder unavailable', path);
    }
    final result = await Process.run('xdg-open', [path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'xdg-open',
        [path],
        '${result.stderr}',
        result.exitCode,
      );
    }
  } catch (error) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Could not reveal the folder'),
        content: SelectableText('$path\n$error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
