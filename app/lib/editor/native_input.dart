import 'package:flutter/services.dart';

/// Synchronizes queued Linux text updates before an explicit Save snapshot.
/// Raw keys and text input arrive asynchronously; handling Ctrl+S does not mean
/// the native handler has finished redispatching the preceding printable key.
class NativeInput {
  const NativeInput._();

  static const _channel = MethodChannel('slugline/window');

  static Future<void> flush() async {
    try {
      await _channel.invokeMethod<void>('flushTextInput');
    } on MissingPluginException {
      // Widget tests and non-Linux tooling have no native input queue.
    }
  }
}
