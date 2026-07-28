import 'package:flutter/foundation.dart';

import 'package:slugline/core/document_core.dart';

/// What the status bar says about the file.
///
/// A `ChangeNotifier` rather than state on the page, because three separate
/// things move it — an edit, an autosave finishing, and a `CoreEvent` arriving
/// from Rust — and threading three callbacks through the widget tree to reach
/// one line of text is how a status line ends up lying.
///
/// It says one of six things, and the order below is the order they take
/// precedence in. A failure outranks everything: a writer whose disk is full
/// must not see "saved" because an earlier save succeeded. A session that is not
/// being recorded says so in every one of the remaining states, because that is
/// a fact about the session rather than about the last write — and so, for the
/// same reason, does one whose file nobody is watching.
class SaveStatus extends ChangeNotifier {
  SaveStatus({required this.core});

  final DocumentCore core;

  String? _failure;
  bool _saving = false;
  int _savedAtMillis = 0;

  /// Set when a save failed, cleared when one succeeds.
  bool get isError => _failure != null;

  String get label {
    final state = _state;
    // Said in every state including a failure, because it is a fact about the
    // session rather than about the last write: on a machine with no inotify
    // left, nothing will interrupt the writer when another program edits their
    // script — the next save will refuse to overwrite it, which is protection,
    // but it is not a warning, and a writer who expects to be told will not
    // check.
    if (!core.watched) return '$state · external changes not watched';
    return state;
  }

  String get _state {
    if (_failure case final message?) return message;
    if (_saving) return 'saving…';
    final (edits, broken) = core.journalState;
    // Said whether or not there is anything unsaved, because what it describes
    // is the *next* few seconds rather than the last ones: a session with no
    // crash record is one an autosave has only just made safe, and it goes on
    // being that after every save. A session that never got a journal at all —
    // an unwritable state directory, a name a pending recovery still holds —
    // is in exactly this state from the moment it opens, and used to say
    // nothing at all until something was typed.
    if (broken) {
      final state = switch ((core.dirty, core.path)) {
        (true, _) => 'not saved',
        (false, null) => 'never saved',
        (false, _) => 'saved',
      };
      return '$state · recovery record unavailable';
    }
    if (core.dirty) {
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

  /// Whether [label] is the unremarkable "saved", and nothing else.
  ///
  /// The status bar shows a relative time instead of the label — "saved 2
  /// minutes ago" — and this is what says it may. Every other state has a
  /// sentence in it that has to be read rather than summarised: a failure, a
  /// count of journalled edits, and above all the two that are facts about the
  /// whole session and go on being said for the rest of it — "recovery record
  /// unavailable" and "external changes not watched". Replacing one of those
  /// with a timestamp would be the status line lying by omission, which is the
  /// specific thing this class exists not to do.
  bool get isPlainSaved => label == 'saved';

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
        // The prompt that is already on its way says the rest of it. This line
        // is what the writer sees behind it, and what they go on seeing if they
        // dismiss it without deciding.
        SaveFailure.changedOnDisk => 'the file changed on disk',
        SaveFailure.io => 'the write failed',
      };
}
