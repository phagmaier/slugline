import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds native selection until a workflow test supplies a path or cancels.
Completer<String?> pendingFileChoice(WidgetTester tester) {
  const channel = MethodChannel('slugline/window');
  final choice = Completer<String?>();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) {
    if (call.method != 'chooseFile') throw MissingPluginException();
    return choice.future;
  });
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
  return choice;
}
