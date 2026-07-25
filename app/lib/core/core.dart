import 'dart:async';

import 'package:slugline/src/rust/api/events.dart' as bus;
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/src/rust/api/handshake.dart' as rust;
import 'package:slugline/src/rust/frb_generated.dart';

export 'package:slugline/src/rust/api/events.dart'
    show
        CoreEvent,
        CoreEvent_AutosaveFailed,
        CoreEvent_BackupWritten,
        CoreEvent_EntityIndexUpdated,
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
export 'package:slugline/src/rust/api/handshake.dart'
    show CoreInfo, CrateInfo, ProofEvent, ProofEvent_Pong, ProofEvent_Ready, TextMetrics;

/// The string Phase 0 requires to survive the bridge unchanged: ASCII, a
/// Latin-1 accent, CJK, and an astral-plane emoji (a surrogate pair in Dart).
///
/// Both sides hardcode it — see `crates/bridge/src/api/handshake.rs` — so it
/// lives beside the client rather than in whatever widget happens to show it.
const proofText = 'café 日本 🎬';

/// The Dart-side handle on the Rust core.
///
/// Everything that crosses the bridge goes through here, so there is one place
/// to look when an offset is wrong or an event goes missing. Per §2.1, Flutter
/// asks the core for screenplay semantics rather than deriving them: this class
/// forwards, it does not interpret.
class Core {
  Core._(this.events, this.proofEvents);

  /// Rust → Dart notifications (§2.3). Subscribed once, at startup; broadcast
  /// so widgets can come and go without re-subscribing on the Rust side.
  final Stream<bus.CoreEvent> events;

  /// The Phase 0 handshake channel, which is a proof and not an application
  /// channel — see `crates/bridge/src/api/handshake.rs`. It goes when that file
  /// does; nothing outside `integration_test/bridge_test.dart` listens to it.
  final Stream<rust.ProofEvent> proofEvents;

  static Core? _instance;

  /// The initialised core. Throws if [init] has not completed.
  static Core get instance {
    final core = _instance;
    if (core == null) {
      throw StateError('Core.init() must complete before Core.instance is used');
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
    final core = Core._(
      bus.coreEvents().asBroadcastStream(),
      rust.proofEvents().asBroadcastStream(),
    );
    // Subscribe eagerly so that events emitted before the first widget listens
    // are not dropped — the `Ready` the proof channel sends on subscription,
    // and anything `init` itself causes.
    unawaited(core.events.first);
    unawaited(core.proofEvents.first);
    await files.init(configDir: configDir, dataDir: dataDir, stateDir: stateDir);
    return _instance = core;
  }

  /// Ends the session: every journal is discarded and the library index is
  /// written. A session that skips this looks like a crash on next startup,
  /// which is exactly right when it *was* one.
  Future<void> shutdown() => files.shutdown();

  // --- library ---------------------------------------------------------------

  Future<List<files.ScriptView>> library() => files.libraryList();

  Future<List<files.ScriptView>> sessionToRestore() => files.sessionRestore();

  Future<files.ScriptView?> duplicate(String id) => files.libraryDuplicate(id: id);

  Future<files.SaveOutcome> rename(String id, String newPath) =>
      files.libraryRename(id: id, newPath: newPath);

  Future<bool> forget(String id, {required bool deleteFile}) =>
      files.libraryRemove(id: id, deleteFile: deleteFile);

  // --- recovery --------------------------------------------------------------

  /// Crashed sessions found at startup. Nothing has been applied to anything.
  Future<List<files.RecoveryOffer>> pendingRecoveries() => files.recoveryPending();

  Future<bool> discardRecovery(String journalPath) =>
      files.recoveryDiscard(journalPath: journalPath);

  // --- preferences -----------------------------------------------------------

  files.PreferencesView preferences() => files.prefsGet();

  Future<bool> setPreferences(files.PreferencesView preferences) =>
      files.prefsSet(preferences: preferences);

  // --- Phase 0 proofs --------------------------------------------------------

  /// Version and workspace layout, as the core reports them.
  rust.CoreInfo info() => rust.coreInfo();

  /// Round-trips [text] through Rust unchanged.
  String echo(String text) => rust.echo(text: text);

  /// How the core measures [text]. `lenUtf16` must equal Dart's `String.length`.
  rust.TextMetrics metrics(String text) => rust.textMetrics(text: text);

  /// Slices [text] by UTF-16 offsets, the coordinates the bridge speaks (§2.4).
  /// Returns null when an offset splits a surrogate pair.
  String? slice(String text, int startUtf16, int endUtf16) =>
      rust.sliceUtf16(text: text, startUtf16: startUtf16, endUtf16: endUtf16);

  /// Asks the core to push a [rust.ProofEvent_Pong] back from a worker thread.
  void ping(String text) => rust.ping(text: text);
}
