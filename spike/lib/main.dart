/// Editor spike driver.
///
///     flutter run -d linux --dart-define=P=a          # interactive
///     flutter run -d linux --dart-define=P=b --dart-define=BENCH=true
///
/// With `BENCH=true` the app runs the same scripted workload against whichever
/// prototype is selected, prints the numbers, and exits. Every prototype
/// implements [SpikeSurface], so the script is identical for all three and the
/// numbers are comparable.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'bench.dart';
import 'prototype_a.dart';
import 'prototype_b.dart';
import 'prototype_c.dart';
import 'surface.dart';
import 'synthetic.dart';

const _prototype = String.fromEnvironment('P', defaultValue: 'a');
const _benchMode = bool.fromEnvironment('BENCH');
const _blockCount = int.fromEnvironment('BLOCKS', defaultValue: 3000);

final _surfaceKey = GlobalKey();
final _startup = Stopwatch();

void main() {
  _startup.start();
  WidgetsFlutterBinding.ensureInitialized();
  final blocks = buildSyntheticScript(count: _blockCount);
  runApp(SpikeApp(blocks: blocks));
  if (_benchMode) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runBenchmark()));
  }
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({required this.blocks, super.key});

  final List<SyntheticBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF16181C),
        appBar: AppBar(
          title: Text('Spike — prototype ${_prototype.toUpperCase()} '
              '(${blocks.length} paragraphs)'),
        ),
        body: switch (_prototype) {
          'b' => PrototypeB(blocks: blocks, key: _surfaceKey),
          'c' => PrototypeC(blocks: blocks, key: _surfaceKey),
          _ => PrototypeA(blocks: blocks, key: _surfaceKey),
        },
      ),
    );
  }
}

SpikeSurface get _surface => _surfaceKey.currentState! as SpikeSurface;

/// Phase markers, so a prototype that hangs tells us *where* it hung rather
/// than just timing out.
void _phase(Bench bench, String name) {
  bench.beginPhase(name);
  // ignore: avoid_print
  print('[phase] $name');
}

/// The workload every prototype has to survive, from the Phase 0 brief: load a
/// 3,000-paragraph document, type in any paragraph, navigate across paragraph
/// boundaries with the arrow keys, and select four paragraphs as copyable text.
Future<void> _runBenchmark() async {
  final bench = Bench(_prototype.toUpperCase());
  bench.record('load to first frame', _startup.elapsedMicroseconds / 1000);
  bench.startFrameCapture();

  // Settle before measuring anything else.
  for (var i = 0; i < 5; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }

  _phase(bench, 'typing');
  // --- Typing, in the middle of the document ---
  await _surface.placeCaret(1500, 0);
  for (var i = 0; i < 60; i++) {
    await bench.measure('keystroke', () => _surface.typeCharacter('x'));
  }

  _phase(bench, 'arrow navigation');
  // --- Arrow navigation across paragraph boundaries ---
  var crossings = 0;
  var lastBlock = -1;
  for (var i = 0; i < 40; i++) {
    var landed = -1;
    await bench.measure('arrow down', () async => landed = await _surface.arrowDown());
    if (landed != lastBlock) crossings++;
    lastBlock = landed;
  }

  _phase(bench, 'scrolling');
  // --- Scrolling ---
  final controller = _surface.scrollController;
  final extent = controller.position.maxScrollExtent;
  for (var i = 0; i <= 40; i++) {
    controller.jumpTo(extent * i / 40);
    await WidgetsBinding.instance.endOfFrame;
  }
  await controller.animateTo(
    extent * 0.5,
    duration: const Duration(milliseconds: 600),
    curve: Curves.linear,
  );

  _phase(bench, 'selection');
  // --- Selection across four paragraphs, copied as text ---
  var selected = '';
  var selectionOk = false;
  try {
    await bench.measure('select 4 paragraphs', () async {
      selected = await _surface.selectFourParagraphsAsText(1200);
    });
    selectionOk = selected.split('\n\n').length >= 4 && selected.isNotEmpty;
  } on Object catch (error) {
    selected = 'FAILED: $error';
  }

  _phase(bench, 'report');
  bench.report();
  // ignore: avoid_print
  print('paragraph boundaries crossed by 40 arrow-downs: $crossings/40');
  // ignore: avoid_print
  print('four-paragraph selection copyable as text: $selectionOk '
      '(${selected.length} chars)');

  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
