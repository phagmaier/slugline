import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';

/// The output page containing the top visible line of the fluid editor.
///
/// Page boundaries still do not enter the editing surface. Rust paginates an
/// immutable snapshot, and this object only maps the editor's visible
/// `(block, wrapped line)` back onto that snapshot for a small status label.
class PageIndicator extends ChangeNotifier {
  PageIndicator({
    required this.controller,
    required this.output,
    required this.setup,
    int initialRow = 0,
  }) : _visibleRow = initialRow,
       _knownDocumentRevision = controller.documentRevision {
    controller.addListener(_onControllerChanged);
  }

  final EditorController controller;
  final ScreenplayOutput output;

  PageSetup setup;
  int _visibleRow;
  int _knownDocumentRevision;
  Timer? _refreshTimer;
  int _request = 0;
  bool _disposed = false;

  final Map<(int, int), int> _pageAtLine = {};
  final Map<int, int> _pageAtBlock = {};
  int? _current;
  int? _total;

  int? get current => _current;
  int? get total => _total;

  String get label => switch ((_current, _total)) {
    (final current?, final total?) => 'Page $current of $total',
    _ => 'Pages …',
  };

  void updateSetup(PageSetup setup) {
    if (this.setup == setup) return;
    this.setup = setup;
    unawaited(refresh());
  }

  void updateVisibleRow(int row) {
    if (_visibleRow == row) return;
    _visibleRow = row;
    _updateCurrent();
  }

  void _onControllerChanged() {
    final revision = controller.documentRevision;
    if (_knownDocumentRevision == revision) return;
    _knownDocumentRevision = revision;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 120), () {
      _refreshTimer = null;
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final request = ++_request;
    late final PaginationOutcome outcome;
    try {
      outcome = await output.paginate(setup);
    } on Object {
      // Pagination is supplemental editor chrome. Preview/export report their
      // own failures; a failed background refresh must not disrupt typing.
      return;
    }
    if (_disposed || request != _request) return;
    switch (outcome) {
      case PaginationOutcome_Current(:final pagination) ||
          PaginationOutcome_Stale(:final pagination):
        _adopt(pagination);
      case PaginationOutcome_NoSuchDocument():
        _pageAtLine.clear();
        _pageAtBlock.clear();
        _setPosition(null, null);
    }
  }

  void _adopt(PaginationView pagination) {
    _pageAtLine.clear();
    _pageAtBlock.clear();

    final firstPageAtBlock = <int, int>{};
    for (final page in pagination.pages) {
      final number = page.number;
      if (number == null) continue;
      for (final line in page.lines) {
        final block = line.block;
        if (block == null) continue;
        firstPageAtBlock.putIfAbsent(block, () => number);
        if (line.sourceLine case final sourceLine?) {
          _pageAtLine[(block, sourceLine)] = number;
        }
      }
    }

    // Sections, notes and other non-printing blocks have no paginator row.
    // Associate them with the preceding printable page so the label remains
    // stable while the writer scrolls through source-only material.
    var page = pagination.pages.firstOrNull?.number ?? 1;
    for (final block in controller.blocks) {
      page = firstPageAtBlock[block.id] ?? page;
      _pageAtBlock[block.id] = page;
    }

    _total = pagination.pageCount;
    _updateCurrent(forceNotify: true);
  }

  void _updateCurrent({bool forceNotify = false}) {
    if (_total == null || _pageAtBlock.isEmpty) return;
    final anchor = controller.pageAnchorAtRow(_visibleRow);
    final page =
        _pageAtLine[(anchor.block, anchor.sourceLine)] ??
        _pageAtBlock[anchor.block] ??
        1;
    _setPosition(page.clamp(1, _total!), _total, forceNotify: forceNotify);
  }

  void _setPosition(int? current, int? total, {bool forceNotify = false}) {
    if (!forceNotify && _current == current && _total == total) return;
    _current = current;
    _total = total;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _refreshTimer?.cancel();
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}
