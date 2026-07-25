import 'package:flutter/material.dart';

import 'package:screenplay/core/core.dart';

/// Phase 0 handshake window.
///
/// This is not the application. It renders the four things Phase 0 has to
/// prove — struct round trip, event stream, non-ASCII fidelity, and UTF-16
/// offset agreement — so that a human can see them pass. It is deleted when the
/// editor shell lands in Phase 3.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final core = await Core.init();
  runApp(HandshakeApp(core: core));
}

/// The string Phase 0 requires to survive the bridge unchanged: ASCII, a
/// Latin-1 accent, CJK, and an astral-plane emoji (a surrogate pair in Dart).
const proofText = 'café 日本 🎬';

class HandshakeApp extends StatelessWidget {
  const HandshakeApp({required this.core, super.key});

  final Core core;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screenplay — Phase 0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B6EA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HandshakePage(core: core),
    );
  }
}

class HandshakePage extends StatefulWidget {
  const HandshakePage({required this.core, super.key});

  final Core core;

  @override
  State<HandshakePage> createState() => _HandshakePageState();
}

class _HandshakePageState extends State<HandshakePage> {
  late final CoreInfo _info = widget.core.info();
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    widget.core.events.listen(_onEvent);
  }

  void _onEvent(CoreEvent event) {
    final description = switch (event) {
      CoreEvent_Ready(:final coreVersion) => 'Ready — core $coreVersion',
      CoreEvent_Pong(:final text, :final lenUtf16) =>
        'Pong — "$text" ($lenUtf16 UTF-16 units)',
    };
    if (mounted) setState(() => _log.add(description));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screenplay — Phase 0 handshake'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'core ${_info.coreVersion}  ·  flutter_rust_bridge ${_info.frbVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ProofCard(
            title: 'Struct round trip',
            detail: 'Dart called core_info() and got a struct back, '
                'including a nested List<CrateInfo>.',
            passed: _info.crates.length == 7,
            child: _CrateTable(crates: _info.crates),
          ),
          const SizedBox(height: 16),
          _NonAsciiProof(core: widget.core),
          const SizedBox(height: 16),
          _ProofCard(
            title: 'Event stream',
            detail: 'Rust pushes over a single StreamSink<CoreEvent>. '
                'Ping asks the core to reply from a worker thread.',
            passed: _log.isNotEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _log)
                  Text(line, style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => widget.core.ping(proofText),
                  child: const Text('Ping the core'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NonAsciiProof extends StatelessWidget {
  const _NonAsciiProof({required this.core});

  final Core core;

  @override
  Widget build(BuildContext context) {
    final echoed = core.echo(proofText);
    final metrics = core.metrics(proofText);
    // In 'café 日本 🎬', UTF-16 offsets 8..10 are the two halves of the emoji's
    // surrogate pair, so this slice is only correct if both sides agree.
    final emoji = core.slice(proofText, 8, 10);
    final splitPair = core.slice(proofText, 8, 9);

    final passed = echoed == proofText &&
        metrics.lenUtf16 == proofText.length &&
        emoji == '🎬' &&
        splitPair == null;

    return _ProofCard(
      title: 'Non-ASCII and UTF-16 offsets',
      detail: 'Text crosses as UTF-8 and comes back as UTF-16 unchanged, '
          'and both sides count offsets the same way (§2.4).',
      passed: passed,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'monospace'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('sent             $proofText'),
            Text('received         $echoed'),
            Text('identical        ${echoed == proofText}'),
            Text('dart .length     ${proofText.length}'),
            Text('rust len_utf16   ${metrics.lenUtf16}'),
            Text('rust len_utf8    ${metrics.lenUtf8}'),
            Text('rust char_count  ${metrics.charCount}'),
            Text('slice 8..10      ${emoji ?? "null"}'),
            Text('slice 8..9       ${splitPair ?? "null — surrogate pair refused"}'),
          ],
        ),
      ),
    );
  }
}

class _CrateTable extends StatelessWidget {
  const _CrateTable({required this.crates});

  final List<CrateInfo> crates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final crate in crates)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${crate.name.padRight(12)}→ '
              '${crate.dependsOn.isEmpty ? "nothing" : crate.dependsOn.join(", ")}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({
    required this.title,
    required this.detail,
    required this.passed,
    required this.child,
  });

  final String title;
  final String detail;
  final bool passed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.pending_outlined,
                  color: passed ? Colors.green : theme.disabledColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
