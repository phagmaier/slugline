import 'dart:async';

import 'package:slugline/src/rust/api/handshake.dart' as rust;
import 'package:slugline/src/rust/frb_generated.dart';

export 'package:slugline/src/rust/api/handshake.dart'
    show CoreEvent, CoreEvent_Ready, CoreEvent_Pong, CoreInfo, CrateInfo, TextMetrics;

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
  Core._(this.events);

  /// Rust → Dart notifications (§2.3). Subscribed once, at startup; broadcast
  /// so widgets can come and go without re-subscribing on the Rust side.
  final Stream<rust.CoreEvent> events;

  static Core? _instance;

  /// The initialised core. Throws if [init] has not completed.
  static Core get instance {
    final core = _instance;
    if (core == null) {
      throw StateError('Core.init() must complete before Core.instance is used');
    }
    return core;
  }

  /// Loads `libslugline_bridge.so` and opens the event stream.
  static Future<Core> init() async {
    if (_instance case final existing?) return existing;
    await RustLib.init();
    final core = Core._(rust.coreEvents().asBroadcastStream());
    // Subscribe eagerly so the `Ready` event the core emits on subscription is
    // not dropped before the first widget listens.
    unawaited(core.events.first);
    return _instance = core;
  }

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

  /// Asks the core to push a [rust.CoreEvent_Pong] back from a worker thread.
  void ping(String text) => rust.ping(text: text);
}
