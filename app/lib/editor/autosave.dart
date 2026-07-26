import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:slugline/core/document_core.dart';

/// §Phase 4's autosave: debounced after edit inactivity, and on a hard interval.
///
/// ## Why the clock is here and not in Rust
///
/// The core has no timer anywhere, on purpose: its actor thread blocks on a
/// channel and wakes only when something happens, which is how §1.3's 0% idle
/// CPU budget is met by construction. Putting the autosave clock in Dart is not
/// a way around that — it is the only place the rule can be applied correctly.
/// §Phase 4 says autosave "never runs while a modal is open or during an active
/// IME composition", and neither of those facts exists in Rust: a modal is a
/// widget and a composition is a state of the platform's input connection. The
/// core is told when to save. It decides how.
///
/// ## The two timers
///
/// * **Idle** (default 2 s). Restarted on every edit. This is the one that
///   normally fires: it saves a couple of seconds after the writer stops.
/// * **Interval** (default 30 s). *Not* restarted on every edit. Without it, a
///   writer who never pauses for two seconds — which is what a good session
///   looks like — would never be saved at all.
///
/// Both are cancelled the moment the document is clean, so an idle window costs
/// no wakeups. Neither exists at all when there is nothing to save.
///
/// ## What a suppression means
///
/// [suppress] holds the save off; it never cancels it. A save deferred by a
/// dialog happens when the dialog closes, and a save deferred by a composition
/// happens when the composition ends. §10 does not allow a save to be quietly
/// dropped because the timing was awkward.
class AutosaveDriver {
  AutosaveDriver({
    required this.core,
    required this.changes,
    required this.onOutcome,
    this.idle = const Duration(seconds: 2),
    this.interval = const Duration(seconds: 30),
    this.enabled = true,
  }) {
    changes.addListener(_onChanged);
  }

  final DocumentCore core;

  /// Fires on every edit. In the application this is the `EditorController`.
  final Listenable changes;

  /// Called with whatever the core said, on every autosave that actually ran.
  /// The status bar shows the good ones and §Phase 4's `AutosaveFailed` path
  /// shows the bad.
  final void Function(SaveOutcome outcome) onOutcome;

  final Duration idle;
  final Duration interval;
  final bool enabled;

  Timer? _idleTimer;
  Timer? _intervalTimer;

  /// Reasons the save is being held. A set rather than a flag: a dialog opened
  /// over a composition must not be able to un-suppress it by closing.
  final Set<String> _suppressions = {};

  /// A save was due while suppressed and has not happened yet.
  bool _owed = false;

  /// A save is in flight. Two overlapping saves would race for the same file.
  bool _saving = false;

  bool _disposed = false;

  /// Whether anything is currently holding autosave off.
  bool get suppressed => _suppressions.isNotEmpty;

  /// Whether a save is owed — for tests, and for the status bar's "saving…".
  bool get pending => _owed || _idleTimer != null;

  /// Holds autosave off while [reason] applies. §Phase 4 names two: a modal
  /// being open, and an active IME composition.
  void suppress(String reason) {
    _suppressions.add(reason);
  }

  /// Releases a hold, and pays what is owed.
  void release(String reason) {
    if (!_suppressions.remove(reason)) return;
    if (_suppressions.isEmpty && _owed) {
      _owed = false;
      unawaited(_save());
    }
  }

  /// Saves now, if there is anything to save. What Ctrl+S ends up calling for a
  /// document that already has a file, and what closing a window calls.
  Future<SaveOutcome> saveNow() async {
    _cancelTimers();
    _owed = false;
    return _save();
  }

  /// Tells the driver a document has just been adopted, so that it can start
  /// ticking for one that arrives already dirty.
  ///
  /// Every other way into this class is an *edit*, and for a document opened
  /// from a file that is right: it arrives clean and nothing needs saving until
  /// something changes. Crash recovery is the exception. A recovered document is
  /// dirty on arrival — its edits are ahead of the file, which is the whole
  /// point — but no edit event ever fires for them, so without this the first
  /// autosave would wait for the writer to type. Reading the recovered text
  /// before touching the keyboard is exactly what a person does at that moment,
  /// and it could last minutes.
  ///
  /// A clean document arms nothing, which is why this defers to the same rule as
  /// an edit rather than starting the timers outright.
  void documentAdopted() => _onChanged();

  void _onChanged() {
    if (_disposed || !enabled) return;
    if (!core.dirty) {
      // The change was an undo back to the saved state, or a caret move. Nothing
      // to write, so nothing should be ticking.
      _cancelTimers();
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idle, _due);
    // Deliberately not restarted: the point of the interval is that a writer who
    // never pauses is still saved.
    _intervalTimer ??= Timer.periodic(interval, (_) => _due());
  }

  void _due() {
    if (_disposed) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (suppressed) {
      // Owed, not cancelled. It happens when the last hold is released.
      _owed = true;
      return;
    }
    unawaited(_save());
  }

  Future<SaveOutcome> _save() async {
    if (_saving) return const SaveOutcome.unchanged();
    _saving = true;
    try {
      final outcome = await core.autosave();
      if (_disposed) return outcome;
      if (outcome is SaveOutcome_Saved) _cancelTimers();
      onOutcome(outcome);
      return outcome;
    } finally {
      _saving = false;
    }
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _intervalTimer?.cancel();
    _intervalTimer = null;
  }

  void dispose() {
    _disposed = true;
    changes.removeListener(_onChanged);
    _cancelTimers();
  }
}
