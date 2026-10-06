import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';

/// Where one output page begins, in the editor's own row coordinates.
///
/// [row] is a visual row of the fluid editor and [number] is the page the
/// paginator put that row on. Both come from Rust's snapshot: nothing here
/// decides where a page ends.
class PageStart {
  const PageStart({required this.row, required this.number});

  final int row;
  final int number;

  @override
  bool operator ==(Object other) =>
      other is PageStart && other.row == row && other.number == number;

  @override
  int get hashCode => Object.hash(row, number);

  @override
  String toString() => 'PageStart(row: $row, number: $number)';
}

/// The output page containing the top visible line of the fluid editor.
///
/// Page boundaries still do not enter the editing surface. Rust paginates an
/// immutable snapshot, and this object only maps the editor's visible
/// `(block, wrapped line)` back onto that snapshot — for a small status label,
/// and for the rules the surface draws between pages.
///
/// [pageStarts] is the second of those and obeys the same rule as the first: it
/// is Rust's answer re-expressed in editor coordinates, never a second opinion
/// about where a page break falls. The editor stays fluid and unpaginated (ADR
/// 0018); what it draws is a picture of a pagination it did not compute, and
/// between an edit and the next snapshot the picture is simply a little stale.
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

  /// The first printable line of each page, as the paginator gave it: page
  /// number to `(block id, wrapped line within that block)`.
  final Map<int, (int, int)> _firstLineOfPage = {};

  /// The pages whose snapshot carries no [LayoutLineKind.pageNumber] line.
  final Set<int> _unnumberedPages = {};

  /// [pageStarts], resolved against the layout the controller currently holds.
  /// Cleared whenever either side of that could have moved.
  List<PageStart>? _pageStarts;

  int? _current;
  int? _total;
  int? _words;

  int? get current => _current;
  int? get total => _total;

  /// How many words the script contains, or null before the first pagination.
  ///
  /// Counted from the paginated snapshot rather than from the blocks, which is
  /// what makes it the *script's* word count rather than the document's: what
  /// reaches a page is Rust's answer about what prints, so notes, synopses,
  /// sections and the boneyard are already gone, and a scene heading is already
  /// the line that will be typeset. Dart counts spaces in a list of strings and
  /// decides nothing (§2.1).
  ///
  /// It also lands where it costs nothing. Pagination is already an async job
  /// against a snapshot, debounced 120 ms behind the keystroke — the one place a
  /// pass over the whole script is affordable. A count recomputed per keystroke
  /// would be a second answer to "what is in this document" on exactly the path
  /// ADR 0018 keeps clear.
  int? get words => _words;

  /// Where each page begins on the editor's grid, in ascending row order.
  ///
  /// Empty until the first pagination arrives, which is what the surface draws
  /// when the answer is not known yet: no rules rather than guessed ones. The
  /// first page is omitted — a rule above row zero is a rule above the document.
  ///
  /// Resolved lazily and cached, because the block-id-to-row mapping is the
  /// controller's and changes with every edit. One pass over the blocks, and
  /// only when something has actually moved.
  List<PageStart> get pageStarts => _pageStarts ??= _resolvePageStarts();

  List<PageStart> _resolvePageStarts() {
    if (_firstLineOfPage.isEmpty) return const [];
    final blocks = controller.blocks;
    final indexOfBlock = <int, int>{
      for (var index = 0; index < blocks.length; index++) blocks[index].id: index,
    };

    final starts = <PageStart>[];
    for (final MapEntry(key: number, value: (block, sourceLine))
        in _firstLineOfPage.entries) {
      if (number <= 1) continue;
      final index = indexOfBlock[block];
      // A block the paginator saw and this layout no longer has. The next
      // snapshot will carry the correction; drawing nothing is the honest
      // answer in the meantime.
      if (index == null) continue;
      starts.add(
        PageStart(
          row: controller.rowOfLine(index, sourceLine),
          number: number,
        ),
      );
    }
    starts.sort((a, b) => a.row.compareTo(b.row));
    return List.unmodifiable(starts);
  }

  /// Whether [page]'s number is printed on its sheet.
  ///
  /// Rust's answer, read off the snapshot: a page prints its number exactly
  /// when the paginator gave it a page-number line. Page 1 conventionally has
  /// none, and whether it does is a page-setup option the paginator applies —
  /// so page view asks this instead of reading the option and repeating the
  /// rule. Every page counts as numbered until a snapshot says otherwise.
  bool printsNumber(int page) => !_unnumberedPages.contains(page);

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
    // The rows the current starts were resolved against have moved. Re-resolve
    // against the new layout at once — the page numbers are the previous
    // snapshot's until the refresh below lands, but their rules stay attached
    // to the text they were drawn for instead of drifting up the page.
    _pageStarts = null;
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
        _firstLineOfPage.clear();
        _unnumberedPages.clear();
        _pageStarts = null;
        _words = null;
        _setPosition(null, null);
    }
  }

  void _adopt(PaginationView pagination) {
    _pageAtLine.clear();
    _pageAtBlock.clear();
    _firstLineOfPage.clear();
    _unnumberedPages.clear();
    _pageStarts = null;

    final firstPageAtBlock = <int, int>{};
    for (final page in pagination.pages) {
      final number = page.number;
      if (number == null) continue;
      var numbered = false;
      for (final line in page.lines) {
        numbered = numbered || line.kind == LayoutLineKind.pageNumber;
        final block = line.block;
        if (block == null) continue;
        firstPageAtBlock.putIfAbsent(block, () => number);
        if (line.sourceLine case final sourceLine?) {
          _pageAtLine[(block, sourceLine)] = number;
          // The page's first line that came from the document. A page opens
          // with running heads and blank rows that belong to no block, and a
          // rule drawn at one of those would sit above the text it precedes.
          _firstLineOfPage.putIfAbsent(number, () => (block, sourceLine));
        }
      }
      if (!numbered) _unnumberedPages.add(number);
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
    _words = _countWords(pagination);
    _updateCurrent(forceNotify: true);
  }

  /// Words in the printable lines of a pagination.
  ///
  /// Only [LayoutLineKind.content] is counted: a page number, a `(MORE)`, a
  /// `CONT'D` and a scene number are the paginator talking, not the writer. A
  /// wrapped paragraph is safe to sum line by line because the line breaker
  /// breaks at spaces — the halves of a split word never both count.
  static int _countWords(PaginationView pagination) {
    var words = 0;
    for (final page in pagination.pages) {
      for (final line in page.lines) {
        if (line.kind != LayoutLineKind.content) continue;
        for (final piece in line.content.split(' ')) {
          if (piece.trim().isNotEmpty) words++;
        }
      }
    }
    return words;
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
