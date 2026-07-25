import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/library/file_chooser.dart';

/// The dialogs §Phase 4 requires around saving, in one file so that the wording
/// of a failure and the escape hatch offered with it stay together.
///
/// Two rules run through all of them:
///
/// * **A save failure is blocking and explicit — never a toast.** §Phase 4 says
///   so in as many words, and the reason is that a toast is a thing a writer
///   scrolls past. If the file did not get written, the writer has to know
///   before they type another word.
/// * **Every failure offers Save As.** Read-only, no permission, full disk: in
///   all three the writer's text exists and only the destination is wrong, so
///   the useful answer is always "then put it somewhere else".

/// What the writer chose when a save failed.
enum SaveFailureChoice {
  /// Try again at a path they picked.
  saveAs,

  /// Give up on this save. The document stays dirty and the journal keeps
  /// covering it.
  cancel,
}

/// A blocking, specific report that the file was not written.
Future<SaveFailureChoice> showSaveFailure(
  BuildContext context,
  SaveOutcome_Failed failure,
) async {
  final choice = await showDialog<SaveFailureChoice>(
    context: context,
    // Not dismissible: §Phase 4's "blocking, explicit error … never a silent
    // toast". Clicking away from this would be the silent version.
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.error_outline),
      title: Text(_headline(failure.failure)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_explanation(failure.failure, failure.path)),
          const SizedBox(height: 12),
          Text(
            'Your work is still here, and nothing has been lost. '
            'It just is not on disk yet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SelectableText(
            failure.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(SaveFailureChoice.cancel),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(SaveFailureChoice.saveAs),
          child: const Text('Save as…'),
        ),
      ],
    ),
  );
  return choice ?? SaveFailureChoice.cancel;
}

String _headline(SaveFailure failure) => switch (failure) {
      SaveFailure.readOnly => 'That file is read-only',
      SaveFailure.permissionDenied => 'No permission to write there',
      SaveFailure.noSpace => 'The disk is full',
      SaveFailure.noSuchDirectory => 'That folder is not there',
      SaveFailure.noPath => 'This script has no file yet',
      SaveFailure.noSuchDocument => 'That script is not open',
      SaveFailure.io => 'The file could not be written',
    };

String _explanation(SaveFailure failure, String path) => switch (failure) {
      SaveFailure.readOnly =>
        '$path is marked read-only, so Slugline did not overwrite it.',
      SaveFailure.permissionDenied =>
        'The folder holding $path will not accept a new file from this account.',
      SaveFailure.noSpace =>
        'There is no room left on the filesystem holding $path. '
            'Saving somewhere else will work; so will freeing some space and trying again.',
      SaveFailure.noSuchDirectory =>
        'The folder that $path would go in does not exist any more.',
      SaveFailure.noPath =>
        'Choose where this script should live and it will be written there.',
      SaveFailure.noSuchDocument =>
        'The editor and the core disagree about what is open. Reopening the '
            'script will fix it.',
      SaveFailure.io => 'The operating system refused to write $path.',
    };

/// §Phase 4's external-modification prompt.
enum ExternalChangeChoice { keepMine, takeTheirs, saveAs }

/// Asked when a file changes on disk **and** there are unsaved edits.
///
/// When there are no unsaved edits the file is reloaded silently and this is
/// never shown — §Phase 4 is explicit about the split, and it is the right one:
/// a prompt the writer cannot lose anything by answering either way is a prompt
/// that trains them to dismiss prompts.
Future<ExternalChangeChoice?> showExternalChange(
  BuildContext context,
  String path,
) {
  return showDialog<ExternalChangeChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.compare_arrows),
      title: const Text('This file changed on disk'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Something else has written to $path since you opened it, '
              'and you have unsaved changes here.'),
          const SizedBox(height: 12),
          Text(
            'Keep mine leaves the file alone until you next save. '
            'Take theirs discards your unsaved changes and the undo history with them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ExternalChangeChoice.takeTheirs),
          child: const Text('Take theirs'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ExternalChangeChoice.saveAs),
          child: const Text('Save as…'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ExternalChangeChoice.keepMine),
          child: const Text('Keep mine'),
        ),
      ],
    ),
  );
}

/// What to do with unsaved work on the way out.
enum UnsavedChoice { save, discard, cancel }

/// §10: "must never silently discard unsaved changes". This is the prompt that
/// makes that true when a script is closed or the window is shut.
Future<UnsavedChoice> showUnsavedChanges(BuildContext context, String title) async {
  final choice = await showDialog<UnsavedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Save changes to $title?'),
      content: const Text('There are edits here that are not in the file yet.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(UnsavedChoice.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return choice ?? UnsavedChoice.cancel;
}

/// Saves, and deals with whatever comes back — including asking for a new path
/// and trying again.
///
/// Every save in the application goes through here, so there is one answer to
/// "what happens when it fails" rather than one per button.
Future<SaveOutcome> saveWithDialogs(
  BuildContext context,
  DocumentCore core, {
  bool forcePath = false,
}) async {
  var outcome = forcePath || core.path == null
      ? await _askAndSave(context, core)
      : await core.save();

  while (outcome is SaveOutcome_Failed) {
    // `noPath` here can only mean the writer closed the chooser — the one path
    // that reaches this without having asked already is the first line above.
    // Asking again would be a dialog that will not take no for an answer.
    if (outcome.failure == SaveFailure.noPath) return outcome;
    if (!context.mounted) return outcome;
    final choice = await showSaveFailure(context, outcome);
    if (choice == SaveFailureChoice.cancel) return outcome;
    if (!context.mounted) return outcome;
    outcome = await _askAndSave(context, core);
  }
  return outcome;
}

Future<SaveOutcome> _askAndSave(BuildContext context, DocumentCore core) async {
  final existing = core.path;
  final path = await FileChooser.show(
    context,
    title: 'Save script as',
    action: 'Save',
    directory: existing == null ? null : _parent(existing),
    suggestedName: existing == null ? 'untitled.fountain' : _basename(existing),
  );
  if (path == null) {
    return const SaveOutcome.failed(
      failure: SaveFailure.noPath,
      path: '',
      message: 'no file was chosen',
    );
  }
  return core.saveAs(path);
}

String _parent(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
