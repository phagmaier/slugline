import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/identity.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/widgets/escape_dismissible.dart';

/// The dialogs §Phase 4 requires around saving, in one file so that the wording
/// of a failure and the escape hatch offered with it stay together.
///
/// Two rules run through all of them:
///
/// * **A save failure is blocking and explicit — never a toast.** §Phase 4 says
///   so in as many words, and the reason is that a toast is a thing a writer
///   scrolls past. If the file did not get written, the writer has to know
///   before they type another word.
/// * **Every failure offers Export a copy.** Read-only, no permission, full disk: in
///   all three the writer's text exists and only the destination is wrong, so
///   the useful answer is always "then put it somewhere else".

/// What the writer chose when a save failed.
enum SaveFailureChoice {
  /// Try again at a path they picked.
  exportCopy,
  retry,

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
    // Not click-away: §Phase 4's "blocking, explicit error … never a silent
    // toast". Phase 10 still gives the intentional Escape key a Cancel route.
    barrierDismissible: false,
    builder: (context) => EscapeDismissible(
      child: AlertDialog(
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
            // The core's own words about what went wrong. Chrome, so the chrome's
            // face: it used to be set in a monospace it had no need for, which
            // read as script and made a one-line error look like a stack trace.
            SelectableText(
              failure.message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(SaveFailureChoice.cancel),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(SaveFailureChoice.retry),
            child: const Text('Retry'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(SaveFailureChoice.exportCopy),
            child: const Text('Export a copy…'),
          ),
        ],
      ),
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
  SaveFailure.alreadyExists => 'There is already a file there',
  SaveFailure.scriptIsOpen => 'That script is open here',
  SaveFailure.changedOnDisk => 'That file changed on disk',
  SaveFailure.io => 'The file could not be written',
  SaveFailure.libraryDestination => 'The library destination is protected',
};

String _explanation(SaveFailure failure, String path) => switch (failure) {
  SaveFailure.readOnly =>
    '$path is marked read-only, so $applicationName did not overwrite it.',
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
  // The export refusals. The first is a question
  // rather than a fault and is normally answered by [confirmReplace] before
  // it ever gets here; this sentence is what a writer sees if they declined
  // and the failure came back up.
  SaveFailure.alreadyExists =>
    '$path is already there, and $applicationName did not replace it.',
  SaveFailure.scriptIsOpen =>
    '$path is open here. Save that script rather than writing this one over it.',
  // Normally never seen: [saveWithDialogs] returns this one to the caller
  // because the external-modification prompt is already coming. The
  // sentence is here for the same reason the two above are — the enum is
  // one enum, and a dialog that had nothing to say would be worse.
  SaveFailure.changedOnDisk =>
    'Something else has written to $path since it was last read here, so '
        '$applicationName did not replace it.',
  SaveFailure.io => 'The operating system refused to write $path.',
  SaveFailure.libraryDestination =>
    'Scripts stay in the library. Export a copy outside project folders to rescue or share text.',
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
    builder: (context) => EscapeDismissible(
      child: AlertDialog(
        icon: const Icon(Icons.compare_arrows),
        title: const Text('This file changed on disk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Something else has written to $path since you opened it, '
              'and you have unsaved changes here.',
            ),
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
            onPressed: () =>
                Navigator.of(context).pop(ExternalChangeChoice.saveAs),
            child: const Text('Export a copy…'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(ExternalChangeChoice.keepMine),
            child: const Text('Keep mine'),
          ),
        ],
      ),
    ),
  );
}

/// What to do with unsaved work on the way out.
enum UnsavedChoice { save, discard, cancel }

/// §10: "must never silently discard unsaved changes". This is the prompt that
/// makes that true when a script is closed or the window is shut.
Future<UnsavedChoice> showUnsavedChanges(
  BuildContext context,
  String title,
) async {
  final choice = await showDialog<UnsavedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => EscapeDismissible(
      child: AlertDialog(
        title: Text('Save changes to $title?'),
        content: const Text(
          'There are edits here that are not in the file yet.',
        ),
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
    ),
  );
  return choice ?? UnsavedChoice.cancel;
}

/// Asks where to export a snapshot. Null if they closed the chooser.
///
/// The application's own chooser, and a seam a test replaces. A widget test
/// can exercise replacement confirmation without a real directory.
typedef SavePathChooser =
    Future<String?> Function(
      BuildContext context, {
      required String? directory,
      required String suggestedName,
    });

/// Saves, offering Retry or a rescue export on failure. [forcePath] requests
/// an export directly and leaves the managed session unchanged.
///
/// Every save in the application goes through here, so there is one answer to
/// "what happens when it fails" rather than one per button.
Future<SaveOutcome> saveWithDialogs(
  BuildContext context,
  DocumentCore core, {
  bool forcePath = false,
  SavePathChooser chooseFile = _chooseWithFileChooser,
}) async {
  if (forcePath) {
    final exported = await _askAndSave(context, core, chooseFile);
    if (exported is SaveOutcome_Failed &&
        exported.failure != SaveFailure.noPath &&
        context.mounted) {
      await showSaveFailure(context, exported);
    }
    return exported;
  }
  var outcome = await core.save();

  while (outcome is SaveOutcome_Failed) {
    // `noPath` here can only mean the writer closed the chooser — the one path
    // that reaches this without having asked already is the first line above.
    // Asking again would be a dialog that will not take no for an answer.
    if (outcome.failure == SaveFailure.noPath) return outcome;
    // Nor `changedOnDisk`. The core refused because the file is not the one it
    // last read, and it pushed the same `FileChangedOnDisk` the watcher would
    // have — so §Phase 4's external-modification prompt is already on its way,
    // with the three answers that fit ("keep mine", "take theirs", "export").
    // A second dialog here would ask a worse version of the same question over
    // the top of it.
    if (outcome.failure == SaveFailure.changedOnDisk) return outcome;
    if (!context.mounted) return outcome;
    final choice = await showSaveFailure(context, outcome);
    if (choice == SaveFailureChoice.cancel) return outcome;
    if (!context.mounted) return outcome;
    if (choice == SaveFailureChoice.retry) {
      outcome = await core.save();
    } else {
      final exported = await _askAndSave(context, core, chooseFile);
      if (exported is SaveOutcome_Failed &&
          exported.failure != SaveFailure.noPath &&
          context.mounted) {
        await showSaveFailure(context, exported);
      }
      // A rescue export leaves the library save unresolved and dirty.
      return outcome;
    }
  }
  return outcome;
}

/// "There is already a file there." Answered by calling again with
/// `overwrite: true`, and by nothing else.
///
/// Shared by Fountain copy and by the export dialog, so that replacing a file is one
/// question with one wording however the writer arrived at it. It is a
/// confirmation, not a check: the core has already refused the write, and
/// declining here simply leaves that refusal standing.
Future<bool> confirmReplace(BuildContext context, String path) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => EscapeDismissible(
      child: AlertDialog(
        icon: const Icon(Icons.help_outline),
        title: const Text('There is already a file there'),
        content: Text('$path exists. Replacing it cannot be undone.'),
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
    ),
  );
  return replace ?? false;
}

/// Asks where to export a snapshot, and writes the copy there.
///
/// The loop is the replace confirmation: the core refuses an occupied
/// destination, and a writer who declines to replace it is back at the chooser
/// picking another name. Closing the chooser cancels the export.
///
/// Only two things leave it: a chosen path that was written (or refused for some
/// other reason, which [saveWithDialogs] reports), and a closed chooser.
Future<SaveOutcome> _askAndSave(
  BuildContext context,
  DocumentCore core,
  SavePathChooser chooseFile,
) async {
  final existing = core.path;
  // Where the chooser opens, and what it opens with. They follow the last
  // attempt round the loop: a writer who declined to replace a file was in the
  // right folder and typing a name near the one they wanted.
  var directory = existing == null ? null : _parent(existing);
  var suggested = existing == null ? 'untitled.fountain' : _basename(existing);

  while (true) {
    final path = await chooseFile(
      context,
      directory: directory,
      suggestedName: suggested,
    );
    if (path == null || !context.mounted) return _noPath;
    final outcome = await core.exportFountain(path);
    if (outcome is! SaveOutcome_Failed ||
        outcome.failure != SaveFailure.alreadyExists) {
      return outcome;
    }
    if (!context.mounted) return outcome;
    if (await confirmReplace(context, path)) {
      if (!context.mounted) return outcome;
      return core.exportFountain(path, overwrite: true);
    }
    if (!context.mounted) return outcome;
    directory = _parent(path);
    suggested = _basename(path);
  }
}

Future<String?> _chooseWithFileChooser(
  BuildContext context, {
  required String? directory,
  required String suggestedName,
}) => FileChooser.show(
  context,
  title: 'Export a Fountain copy',
  action: 'Export',
  directory: directory,
  suggestedName: suggestedName,
);

/// What a closed chooser answers with. `noPath` rather than a cancellation
/// because nothing was written and [saveWithDialogs] must not ask again — see
/// the comment on its loop.
const SaveOutcome _noPath = SaveOutcome.failed(
  failure: SaveFailure.noPath,
  path: '',
  message: 'no file was chosen',
);

String _parent(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
