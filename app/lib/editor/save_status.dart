import 'package:flutter/foundation.dart';

import 'package:slugline/core/document_core.dart';

/// What the status bar says about the file.
///
/// A `ChangeNotifier` rather than state on the page, because three separate
/// things move it — an edit, an autosave finishing, and a `CoreEvent` arriving
/// from Rust — and threading three callbacks through the widget tree to reach
/// one line of text is how a status line ends up lying.
///
/// It says one of five things, and the order below is the order they take
/// precedence in. A failure outranks everything: a writer whose disk is full
/// must not see "saved" because an earlier save succeeded.
class SaveStatus extends ChangeNotifier {
  SaveStatus({required this.core});

  final DocumentCore core;

  String? _failure;
  bool _saving = false;
  int _savedAtMillis = 0;

  /// Set when a save failed, cleared when one succeeds.
  bool get isError => _failure != null;

  String get label {
    if (_failure case final message?) return message;
    if (_saving) return 'saving…';
    if (core.dirty) {
      final (edits, broken) = core.journalState;
      if (broken) return 'not saved · recovery record unavailable';
      if (core.path == null) return 'never saved';
      // The journal count is the honest answer to "what happens if this dies
      // right now": those edits are on disk, in a file recovery can read.
      return edits > 0 ? 'not saved · $edits edits recorded' : 'not saved';
    }
    if (core.path == null) return 'never saved';
    return 'saved';
  }

  /// When the file was last written, for the tooltip.
  int get savedAtMillis => _savedAtMillis;

  /// Called whenever anything might have changed the answer.
  void refresh() => notifyListeners();

  void savingStarted() {
    _saving = true;
    notifyListeners();
  }

  /// Records what a save came back with.
  void record(SaveOutcome outcome) {
    _saving = false;
    switch (outcome) {
      case SaveOutcome_Saved():
        _failure = null;
        _savedAtMillis = DateTime.now().millisecondsSinceEpoch;
      case SaveOutcome_Unchanged():
        _failure = null;
      case SaveOutcome_Failed(:final failure, :final path):
        // Short: this is a status line, and the sentence that explains it is in
        // the dialog. `noPath` is not a failure — it is a script that has never
        // been saved, which `label` already has a word for.
        _failure = failure == SaveFailure.noPath
            ? null
            : 'not saved · ${_shortReason(failure)}${path.isEmpty ? '' : ''}';
    }
    notifyListeners();
  }

  static String _shortReason(SaveFailure failure) => switch (failure) {
        SaveFailure.readOnly => 'the file is read-only',
        SaveFailure.permissionDenied => 'no permission',
        SaveFailure.noSpace => 'the disk is full',
        SaveFailure.noSuchDirectory => 'the folder is gone',
        SaveFailure.noSuchDocument => 'the core lost this script',
        SaveFailure.noPath => 'no file yet',
        // Neither can reach a *save*: both are answers `doc_export_fountain`
        // gives about a destination, and an export never touches this status.
        // They are here because the enum is one enum, and a status line that
        // said nothing would be worse than one that says something short.
        SaveFailure.alreadyExists => 'there is a file there already',
        SaveFailure.scriptIsOpen => 'that script is open here',
        SaveFailure.io => 'the write failed',
      };
}
