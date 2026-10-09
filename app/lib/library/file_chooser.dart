import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GTK's local file chooser, owned by the Linux runner (ADR 0052).
///
/// The core still authorizes writes. GTK does not ask about overwriting; Save
/// As and exports share the application's confirmation after a core refusal.
abstract final class FileChooser {
  static const _channel = MethodChannel('slugline/window');

  /// Returns an absolute local path, or null when the writer cancels.
  /// [screenplayFiles] combines Fountain and FDX filters for an open-file picker.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String action,
    String? directory,
    String? suggestedName,
    bool mustExist = false,
    bool selectDirectory = false,
    String extension = 'fountain',
    bool screenplayFiles = false,
  }) async {
    try {
      return await _channel.invokeMethod<String>('chooseFile', {
        'title': title,
        'action': action,
        'directory': directory,
        'suggestedName': suggestedName,
        'mustExist': mustExist,
        'selectDirectory': selectDirectory,
        'extension': extension,
        if (screenplayFiles) 'screenplayFiles': true,
      });
    } on PlatformException catch (failure) {
      if (context.mounted) {
        await _showFailure(context, failure.message ?? failure.code);
      }
    } on MissingPluginException {
      if (context.mounted) {
        await _showFailure(context, 'The Linux file chooser is unavailable.');
      }
    }
    return null;
  }

  static Future<void> _showFailure(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Could not open the file chooser'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
}
