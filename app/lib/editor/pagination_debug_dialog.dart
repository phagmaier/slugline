import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/src/rust/api/layout.dart' as layout;

/// Phase 6F's inspection surface, not Phase 7's screenplay preview.
///
/// It prints the bridge DTOs as positioned diagnostics so page-breaking work
/// can be inspected without giving this view any layout rules of its own.
class PaginationDebugDialog extends StatefulWidget {
  const PaginationDebugDialog({required this.core, super.key});

  final ScreenplayOutput core;

  static Future<void> show(BuildContext context, ScreenplayOutput core) =>
      showDialog<void>(
        context: context,
        builder: (_) => PaginationDebugDialog(core: core),
      );

  @override
  State<PaginationDebugDialog> createState() => _PaginationDebugDialogState();
}

class _PaginationDebugDialogState extends State<PaginationDebugDialog> {
  late Future<layout.PaginationOutcome> _result;

  @override
  void initState() {
    super.initState();
    _request();
  }

  void _request() {
    // A deliberately short page makes split rules and continuation furniture
    // visible in an ordinary scene. It is the Rust PageConfig debug knob, not
    // a Dart pagination decision.
    _result = widget.core.paginate(
      const layout.PageSetup(
        paper: layout.PaperSize.usLetter,
        sceneNumbers: layout.SceneNumbers.both,
        boldSceneHeadings: false,
        numberFirstPage: false,
        debugLinesPerPage: 12,
      ),
    );
  }

  void _refresh() {
    setState(_request);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pagination debug'),
      content: SizedBox(
        width: 820,
        height: 620,
        child: FutureBuilder<layout.PaginationOutcome>(
          future: _result,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SelectableText('Pagination failed: ${snapshot.error}');
            }
            final outcome = snapshot.data;
            if (outcome == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return switch (outcome) {
              layout.PaginationOutcome_Current(:final pagination) =>
                _PaginationReport(status: 'CURRENT', pagination: pagination),
              layout.PaginationOutcome_Stale(:final pagination) =>
                _PaginationReport(
                  status: 'STALE — document changed while pagination ran',
                  pagination: pagination,
                ),
              layout.PaginationOutcome_NoSuchDocument() => const Center(
                child: Text('The document is no longer open.'),
              ),
            };
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _refresh, child: const Text('Run again')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PaginationReport extends StatelessWidget {
  const _PaginationReport({required this.status, required this.pagination});

  final String status;
  final layout.PaginationView pagination;

  @override
  Widget build(BuildContext context) {
    final stats = pagination.stats;
    final pageBlocks = <int, Set<int>>{};
    for (var pageIndex = 0; pageIndex < pagination.pages.length; pageIndex++) {
      for (final line in pagination.pages[pageIndex].lines) {
        if (line.block case final block?) {
          pageBlocks.putIfAbsent(block, () => <int>{}).add(pageIndex);
        }
      }
    }
    final splitBlocks = {
      for (final entry in pageBlocks.entries)
        if (entry.value.length > 1) entry.key,
    };

    final report = StringBuffer()
      ..writeln('DIAGNOSTIC ONLY — not the Phase 7 preview')
      ..writeln('status: $status')
      ..writeln(
        'revision: ${pagination.revision}  '
        'generation: ${pagination.generation}  '
        'page count: ${pagination.pageCount}',
      )
      ..writeln(
        'fixed-point iterations: ${stats.breakRuleIterations}  '
        'fell back to naive: ${stats.fellBackToNaive}',
      )
      ..writeln(
        'block cache hits/misses: ${stats.blockHits}/${stats.blockMisses}  '
        'reused prefix/tail pages: '
        '${stats.reusedPages}/${stats.reusedTailPages}  '
        'hinted block: ${stats.hintedBlock ?? 'none'}',
      )
      ..writeln(
        'split blocks: ${splitBlocks.isEmpty ? 'none' : splitBlocks.join(', ')}',
      );

    if (pagination.titlePage case final titlePage?) {
      _writePage(report, 'TITLE PAGE', titlePage, splitBlocks);
    }
    for (final page in pagination.pages) {
      _writePage(report, 'PAGE ${page.number ?? '?'}', page, splitBlocks);
    }

    return SingleChildScrollView(
      child: SelectableText(
        report.toString(),
        key: const Key('pagination-debug-report'),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  static void _writePage(
    StringBuffer report,
    String heading,
    layout.PageView page,
    Set<int> splitBlocks,
  ) {
    report
      ..writeln()
      ..writeln('========== $heading ==========');
    for (final line in page.lines) {
      final block = line.block;
      final sourceLine = line.sourceLine;
      final split = block != null && splitBlocks.contains(block)
          ? ' SPLIT'
          : '';
      report.writeln(
        'r${line.row.toString().padLeft(3)} '
        'c${line.column.toString().padLeft(3)} '
        '${line.kind.name.padRight(16)} '
        'block=${block ?? '-'}${sourceLine == null ? '' : ':$sourceLine'}'
        '$split  ${line.content}',
      );
    }
  }
}
