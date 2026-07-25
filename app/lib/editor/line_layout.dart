import 'dart:math' as math;

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/metrics.dart';

/// One visual row of one block: the slice of the block's text it shows.
///
/// Offsets are UTF-16 code units, the same coordinates the bridge speaks and the
/// same ones `String.substring` uses, so a row can be painted without conversion.
class VisualLine {
  const VisualLine(this.start, this.end);

  /// Inclusive.
  final int start;

  /// Exclusive.
  final int end;

  int get length => end - start;
}

/// Wraps a block's text to [width] columns.
///
/// Character counting, not text measurement: the screenplay grid is monospace
/// and fixed (§5.1), so a line break is arithmetic. That is what makes it cheap
/// enough to redo on the edited block on every keystroke — and it is the same
/// arithmetic `layout::paginate` will do in Rust, so the editor and the PDF
/// cannot drift apart.
///
/// Breaks on spaces, and mid-word only when a single word is longer than the
/// column. A break is never placed between the halves of a surrogate pair.
List<VisualLine> wrapText(String text, int width) {
  if (text.isEmpty || width <= 0) return const [VisualLine(0, 0)];

  final lines = <VisualLine>[];
  var start = 0;
  while (true) {
    if (text.length - start <= width) {
      lines.add(VisualLine(start, text.length));
      return lines;
    }
    final limit = start + width;
    final space = text.lastIndexOf(' ', limit);
    if (space > start) {
      lines.add(VisualLine(start, space));
      start = space + 1;
    } else {
      final breakAt = _boundaryAtOrBefore(text, limit);
      // A single character wider than the column would otherwise loop forever.
      final end = math.max(breakAt, start + 1);
      lines.add(VisualLine(start, end));
      start = end;
    }
  }
}

/// Steps back off the low half of a surrogate pair.
int _boundaryAtOrBefore(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return offset;
  final unit = text.codeUnitAt(offset);
  final isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
  return isLowSurrogate ? offset - 1 : offset;
}

/// The wrapped shape of a whole document, and the row index every block starts
/// at.
///
/// Rows include the blank rows §5.2 puts above each element, so a row index is
/// a screen position and `row * lineHeight` is a y coordinate. Only the visible
/// band is ever painted; this exists so that the scrollable knows how tall the
/// document is without laying out any text.
class DocumentLayout {
  DocumentLayout(List<BlockView> blocks) : _blocks = blocks {
    rebuild();
  }

  final List<BlockView> _blocks;
  final List<List<VisualLine>> _lines = [];
  List<int> _rowStart = const [0];
  int _totalRows = 0;

  int get totalRows => _totalRows;

  List<VisualLine> linesOf(int blockIndex) => _lines[blockIndex];

  /// Re-wraps every block. Called on load and when the whole list is replaced.
  void rebuild() {
    _lines
      ..clear()
      ..addAll([for (final block in _blocks) _wrap(block)]);
    reindex();
  }

  /// Re-wraps one block, which is what an edit to it costs.
  ///
  /// The three mutators below leave the row index stale on purpose: a patch may
  /// touch several blocks, and reindexing once at the end of it is the whole
  /// difference between O(blocks) and O(blocks × changes).
  void rewrap(int blockIndex) {
    _lines[blockIndex] = _wrap(_blocks[blockIndex]);
  }

  void insertAt(int blockIndex) {
    _lines.insert(blockIndex, _wrap(_blocks[blockIndex]));
  }

  void removeAt(int blockIndex) => _lines.removeAt(blockIndex);

  /// Recomputes the running row index. O(blocks), a few thousand integer adds
  /// on a feature-length script.
  void reindex() {
    final starts = List<int>.filled(_blocks.length + 1, 0);
    var row = 0;
    for (var i = 0; i < _blocks.length; i++) {
      starts[i] = row;
      row += blankRowsBefore(i) + _lines[i].length;
    }
    starts[_blocks.length] = row;
    _rowStart = starts;
    _totalRows = row;
  }

  /// Blank rows above block [blockIndex]. Nothing above the first block.
  int blankRowsBefore(int blockIndex) =>
      blockIndex == 0 ? 0 : metricsFor(_blocks[blockIndex].kind).blankLinesBefore;

  /// The first row that shows text of this block.
  int firstRowOf(int blockIndex) =>
      _rowStart[blockIndex] + blankRowsBefore(blockIndex);

  /// One past the last row of this block.
  int endRowOf(int blockIndex) => _rowStart[blockIndex + 1];

  /// Which line of [blockIndex] holds [offset]. Offsets at a wrap point belong
  /// to the line that starts there, so the caret follows the text it typed.
  int lineIndexAt(int blockIndex, int offset) {
    final lines = _lines[blockIndex];
    for (var i = lines.length - 1; i >= 0; i--) {
      if (offset >= lines[i].start) return i;
    }
    return 0;
  }

  int rowAt(int blockIndex, int offset) =>
      firstRowOf(blockIndex) + lineIndexAt(blockIndex, offset);

  /// The block a row belongs to, or the nearest one above it if the row is a
  /// blank separator. Binary search: this runs for every click and every
  /// PageDown.
  int blockAtRow(int row) {
    if (row <= 0) return 0;
    if (row >= _totalRows) return _blocks.length - 1;
    var low = 0;
    var high = _blocks.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_rowStart[middle] <= row) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The starting column of a line, once alignment is applied.
  int columnOf(int blockIndex, int lineIndex) {
    final metrics = metricsFor(_blocks[blockIndex].kind);
    final line = _lines[blockIndex][lineIndex];
    return switch (metrics.alignment) {
      ColumnAlignment.left => metrics.indent,
      ColumnAlignment.right => metrics.indent + metrics.width - line.length,
      ColumnAlignment.centre =>
        metrics.indent + ((metrics.width - line.length) ~/ 2),
    };
  }

  List<VisualLine> _wrap(BlockView block) =>
      wrapText(block.text, metricsFor(block.kind).width);
}
