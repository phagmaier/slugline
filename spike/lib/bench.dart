/// Measurement harness for the editor spike.
///
/// Spec Phase 0: "Results recorded in docs/DECISIONS.md with numbers, not
/// impressions." This collects those numbers and prints them in a form that can
/// be pasted straight into the ADR.
///
/// Two things to know before reading any output:
///
/// 1. **Wall-clock metrics are vsync-quantised.** `measure` waits for the frame
///    that shows the change, so on a 60 Hz display 16.7 ms means "one frame" —
///    the floor, not a problem. The number that says whether we can *sustain*
///    that is the frame **build** time, which is why it is reported per phase.
/// 2. **Frame build time is the real budget.** §1.3 allows 16 ms from keystroke
///    to glyph; a build longer than that cannot keep up, whatever the wall clock
///    says.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class Bench {
  Bench(this.prototype);

  final String prototype;
  final Map<String, List<double>> _samples = {};
  final Map<String, List<FrameTiming>> _framesByPhase = {};
  String _phase = 'startup';
  bool _capturing = false;

  void record(String metric, double milliseconds) {
    _samples.putIfAbsent(metric, () => []).add(milliseconds);
  }

  /// Frames recorded from now on are attributed to [name].
  void beginPhase(String name) => _phase = name;

  /// Runs [action] and records how long until the resulting frame is rendered.
  Future<void> measure(String metric, FutureOr<void> Function() action) async {
    final watch = Stopwatch()..start();
    await action();
    await WidgetsBinding.instance.endOfFrame;
    record(metric, watch.elapsedMicroseconds / 1000);
  }

  void startFrameCapture() {
    if (_capturing) return;
    _capturing = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stopFrameCapture() {
    if (!_capturing) return;
    _capturing = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) =>
      _framesByPhase.putIfAbsent(_phase, () => []).addAll(timings);

  static double _percentile(List<double> values, double fraction) {
    if (values.isEmpty) return double.nan;
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * fraction).round()];
  }

  /// Resident set size in MB, from `/proc/self/status`. `statm`'s second field
  /// counts mapped pages, which for a Skia process is wildly larger than the
  /// memory actually resident.
  static double residentMb() {
    try {
      for (final line in File('/proc/self/status').readAsLinesSync()) {
        if (line.startsWith('VmRSS:')) {
          final kb = int.parse(RegExp(r'\d+').firstMatch(line)!.group(0)!);
          return kb / 1024;
        }
      }
    } on Object {
      // Fall through.
    }
    return double.nan;
  }

  String _row(String label, List<double> values) =>
      '${label.padRight(26)}'
      '${values.length.toString().padLeft(4)}  '
      '${_percentile(values, 0.50).toStringAsFixed(2).padLeft(8)}  '
      '${_percentile(values, 0.99).toStringAsFixed(2).padLeft(8)}  '
      '${_percentile(values, 1.0).toStringAsFixed(2).padLeft(8)}\n';

  void report() {
    stopFrameCapture();
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('=== SPIKE RESULT: prototype $prototype ===')
      ..writeln('wall clock (vsync-quantised; 16.7 ms = one frame at 60 Hz)')
      ..writeln('metric                       n       p50       p99       max')
      ..writeln('-' * 60);

    for (final entry in _samples.entries) {
      buffer.write(_row(entry.key, entry.value));
    }

    buffer
      ..writeln('')
      ..writeln('frame build time by phase (the §1.3 budget is 16 ms)')
      ..writeln('phase                        n       p50       p99       max')
      ..writeln('-' * 60);

    for (final entry in _framesByPhase.entries) {
      final build = entry.value.map((f) => f.buildDuration.inMicroseconds / 1000).toList();
      buffer.write(_row(entry.key, build));
    }

    final all = _framesByPhase.values.expand((f) => f).toList();
    if (all.isNotEmpty) {
      final raster = all.map((f) => f.rasterDuration.inMicroseconds / 1000).toList();
      final build = all.map((f) => f.buildDuration.inMicroseconds / 1000).toList();
      final over = build.where((b) => b > 16.0).length;
      buffer
        ..write(_row('raster (all phases)', raster))
        ..writeln('builds over 16 ms          ${over.toString().padLeft(4)}  '
            '(${(100 * over / build.length).toStringAsFixed(1)}% of ${build.length})');
    }

    buffer
      ..writeln('-' * 60)
      ..writeln('rss after run: ${residentMb().toStringAsFixed(1)} MB')
      ..writeln('=== END SPIKE RESULT ===');

    // ignore: avoid_print — this program's entire output is this table.
    print(buffer);
  }
}
