import 'dart:async';

import 'package:slugline/identity.dart';
import 'package:slugline/src/rust/api/events.dart' as bus;
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/src/rust/api/spell.dart' as spelling;
import 'package:slugline/src/rust/frb_generated.dart';

export 'package:slugline/src/rust/api/events.dart'
    show
        CoreEvent,
        CoreEvent_AutosaveFailed,
        CoreEvent_BackupWritten,
        CoreEvent_EntityIndexUpdated,
        CoreEvent_ExternalWatchUnavailable,
        CoreEvent_FileChangedOnDisk,
        CoreEvent_JournalBroken,
        CoreEvent_SaveStateChanged;
export 'package:slugline/src/rust/api/files.dart'
    show
        BackupView,
        PreferencesView,
        RecoveryOffer,
        SaveFailure,
        SaveOutcome,
        SaveOutcome_Failed,
        SaveOutcome_Saved,
        SaveOutcome_Unchanged,
        ScriptView;
export 'package:slugline/src/rust/api/spell.dart'
    show
        SpellActionResult,
        SpellActionResult_Applied,
        SpellActionResult_Failed,
        SpellLanguage,
        SpellStatus;

/// The core came up without the storage everything else stands on.
///
/// Thrown by [Core.init], and caught in `main`, which shows [message] instead of
/// an editor. It is a distinct type rather than a `StateError` because it is not
/// a programming mistake: it is the machine saying no, and the one thing to do
/// about it is to tell the writer *before* they type a page into a session that
/// cannot journal, save or list it.
class CoreUnavailable implements Exception {
  const CoreUnavailable(this.message);

  /// Plain language, for the writer. Shown as-is.
  final String message;

  @override
  String toString() => 'CoreUnavailable: $message';
}

/// The small part of the core the opening screen needs.
///
/// Keeping this seam narrower than [Core] lets the library's presentation be
/// exercised in widget tests without loading the Rust dynamic library.
abstract interface class LibraryCore {
  Future<List<files.ScriptView>> library();

  Future<files.ScriptView?> duplicate(String id);

  Future<files.SaveOutcome> rename(String id, String newPath);

  Future<bool> forget(String id, {required bool deleteFile});
}

/// The Dart-side handle on the Rust core.
///
/// Everything that crosses the bridge goes through here, so there is one place
/// to look when an offset is wrong or an event goes missing. Per §2.1, Flutter
/// asks the core for screenplay semantics rather than deriving them: this class
/// forwards, it does not interpret.
class Core implements LibraryCore {
  Core._(this.events);

  /// Rust → Dart notifications (§2.3). Subscribed once, at startup; broadcast
  /// so widgets can come and go without re-subscribing on the Rust side.
  ///
  /// This is the only stream. Phase 0's handshake carried a second one, as a
  /// proof that a `StreamSink` worked at all; it was retired with that module
  /// at Phase 11.
  final Stream<bus.CoreEvent> events;

  static Core? _instance;

  /// The initialised core. Throws if [init] has not completed.
  static Core get instance {
    final core = _instance;
    if (core == null) {
      throw StateError(
        'Core.init() must complete before Core.instance is used',
      );
    }
    return core;
  }

  /// Loads `libslugline_bridge.so`, opens the event stream, and tells the core
  /// where its directories are.
  ///
  /// The three directory arguments are for tests: an integration test hands the
  /// core three temporary directories so that it cannot see — or write to — the
  /// ones the user's real scripts are indexed in. Empty means "work it out from
  /// XDG", which is what the application passes and what ADR 0006 settled.
  static Future<Core> init({
    String configDir = '',
    String dataDir = '',
    String stateDir = '',
  }) async {
    if (_instance case final existing?) return existing;
    await RustLib.init();
    final core = Core._(bus.coreEvents().asBroadcastStream());
    // Subscribe eagerly so that events emitted before the first widget listens
    // are not dropped — anything `init` itself causes.
    unawaited(core.events.first);
    final ready = await files.init(
      configDir: configDir,
      dataDir: dataDir,
      stateDir: stateDir,
    );
    if (!ready) {
      // The core has no directories: with empty arguments there was no home
      // directory to derive them from (ADR 0006). Everything §Phase 4 promises
      // — the crash journal, the atomic save, the rolling backups, the library
      // index — is downstream of that, so a core without storage is an editor
      // that cannot keep anything. This answer used to be discarded, and the
      // app started anyway; §1.2 makes losing user text a P0, and starting
      // knowing that nothing can be kept is the version of it that looks fine.
      throw const CoreUnavailable(
        '$applicationName could not work out where to keep your scripts. It needs a '
        'home directory (or XDG_CONFIG_HOME, XDG_DATA_HOME and XDG_STATE_HOME) '
        'to put the library, the crash journal and the backups in.',
      );
    }
    return _instance = core;
  }

  /// Ends the session: every journal is discarded and the library index is
  /// written. A session that skips this looks like a crash on next startup,
  /// which is exactly right when it *was* one.
  Future<void> shutdown() => files.shutdown();

  // --- library ---------------------------------------------------------------

  @override
  Future<List<files.ScriptView>> library() => files.libraryList();

  Future<List<files.ScriptView>> sessionToRestore() => files.sessionRestore();

  @override
  Future<files.ScriptView?> duplicate(String id) =>
      files.libraryDuplicate(id: id);

  @override
  Future<files.SaveOutcome> rename(String id, String newPath) =>
      files.libraryRename(id: id, newPath: newPath);

  @override
  Future<bool> forget(String id, {required bool deleteFile}) =>
      files.libraryRemove(id: id, deleteFile: deleteFile);

  // --- recovery --------------------------------------------------------------

  /// Crashed sessions found at startup. Nothing has been applied to anything.
  Future<List<files.RecoveryOffer>> pendingRecoveries() =>
      files.recoveryPending();

  Future<bool> discardRecovery(String journalPath) =>
      files.recoveryDiscard(journalPath: journalPath);

  // --- preferences -----------------------------------------------------------

  files.PreferencesView preferences() => files.prefsGet();

  Future<bool> setPreferences(files.PreferencesView preferences) =>
      files.prefsSet(preferences: preferences);

  spelling.SpellStatus spellStatus() => spelling.spellStatus();

  Future<spelling.SpellActionResult> configureSpelling({
    required bool enabled,
    String? language,
  }) => spelling.spellConfigure(enabled: enabled, language: language);
}
