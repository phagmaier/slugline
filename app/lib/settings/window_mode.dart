import 'package:flutter/services.dart';

/// The one Linux window operation Phase 10 needs.
///
/// Kept behind a tiny channel so widget tests and non-Linux tooling can run
/// without a desktop runner. A missing channel simply means there is no native
/// window to resize.
class WindowMode {
  const WindowMode._();

  static const _channel = MethodChannel('slugline/window');

  static Future<void> setFullscreen(bool fullscreen) async {
    try {
      await _channel.invokeMethod<void>('setFullscreen', fullscreen);
    } on MissingPluginException {
      // Widget tests do not have a Linux runner.
    } on PlatformException {
      // Losing full screen is cosmetic; preferences and the document remain
      // usable even if a window manager refuses the request.
    }
  }
}
