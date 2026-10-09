import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/metrics.dart';

/// One visual row of one block: the slice of the block's text it shows.
///
/// A row has two coordinate systems and they are not interchangeable. [start]
/// and [end] are UTF-16 code units, the coordinates the bridge speaks and the
/// ones `String.substring` uses, so the model slice needs no conversion.
/// [columns] is the row's width on the §5.1 grid, where one Unicode scalar is
/// one cell and a tab is however many cells its stop takes. Use
/// [columnAtOffset] and [offsetAtColumn] to cross between them: subtracting
/// [start] from a model offset is a column only for text that happens to be
/// plain BMP, and `docs/LINE_BREAKING.md` is what says so.
class VisualLine {
  /// A row whose columns are its code units: no tab, no astral scalar.
  VisualLine(this.start, this.end, this.columns, {this.hardBreakOffsetUtf16})
    : _columnOffsets = null;

  /// A row that needs a column map, because a tab or an astral scalar makes a
  /// column something other than an offset less [start].
  VisualLine.mapped(
    this.start,
    this.end,
    this.columns,
    this._columnOffsets, {
    this.hardBreakOffsetUtf16,
  });

  /// Inclusive.
  final int start;

  /// Exclusive.
  final int end;

  /// Printed grid cells after hidden syntax removal and tab expansion.
  ///
  /// Not `end - start`: paired markers have no printed cells, an astral scalar
  /// is two code units and one cell, and a tab has up to four cells.
  final int columns;

  /// The model offset of the `\n` that terminates this row, when there is one.
  ///
  /// The newline is not part of the printable slice [start], [end]. A caret at
  /// this offset stays at the end of this row; the offset after it belongs to
  /// the next row. Keeping the offset here also preserves trailing model spaces
  /// that wrapping may omit from the painted slice.
  final int? hardBreakOffsetUtf16;

  /// The actual source offset of each printed cell, plus [end].
  ///
  /// Null on plain BMP rows without syntax/tabs. Hidden source boundaries are
  /// represented separately by [_editorCells]; tab cells share one offset.
  final List<int>? _columnOffsets;

  List<EditorCell>? _editorCells;

  /// Printed columns stay independent of the editable display. Resolved syntax
  /// has zero printed width but a dim half-cell in the editor, never an overlay.
  List<EditorCell>? get editorCells => _editorCells;

  double displayColumnAtOffset(int offset) {
    final cells = _editorCells;
    if (cells == null) return columnAtOffset(offset).toDouble();
    for (final cell in cells) {
      if (cell.offset >= offset) return cell.column;
    }
    return cells.isEmpty ? 0 : cells.last.column + cells.last.width;
  }

  int offsetAtDisplayColumn(num column) {
    final cells = _editorCells;
    if (cells == null) return offsetAtColumn(column.round());
    if (column <= 0) return start;
    for (final cell in cells) {
      if (column < cell.column + cell.width / 2) return cell.offset;
    }
    return end;
  }

  void _project(String source, List<InlineRunView> runs) {
    if (runs.isEmpty) return;
    final cells = <EditorCell>[];
    var runIndex = 0;
    var printed = 0;
    var offset = start;
    var column = 0.0;
    while (offset < end) {
      while (runIndex < runs.length && runs[runIndex].endUtf16 <= offset) {
        runIndex++;
      }
      final run = runIndex < runs.length && runs[runIndex].startUtf16 <= offset
          ? runs[runIndex]
          : null;
      final unit = source.codeUnitAt(offset);
      final units =
          _isHighSurrogate(unit) &&
              offset + 1 < end &&
              _isLowSurrogate(source.codeUnitAt(offset + 1))
          ? 2
          : 1;
      final hidden = run?.hidden ?? false;
      if (hidden) {
        cells.add(
          EditorCell(
            offset,
            offset + units,
            column,
            0.5,
            source.substring(offset, offset + units),
            run,
          ),
        );
        column += 0.5;
      } else {
        while (printed < columns && offsetAtColumn(printed) == offset) {
          cells.add(
            EditorCell(
              offset,
              offset + units,
              column,
              1,
              unit == _tab ? ' ' : source.substring(offset, offset + units),
              run,
            ),
          );
          column++;
          printed++;
        }
      }
      offset += units;
    }
    _editorCells = cells;
  }

  /// What this row draws, with tabs expanded to their cells.
  ///
  /// [source] is the block's text, or the upper-cased display text of it —
  /// `displayText` only transforms when that leaves every offset where it was,
  /// so the same columns hold either way.
  String textIn(String source) {
    final offsets = _columnOffsets;
    if (offsets == null) return source.substring(start, end);
    final buffer = StringBuffer();
    for (var column = 0; column < columns; column++) {
      final offset = offsets[column];
      final unit = source.codeUnitAt(offset);
      if (unit == _tab) {
        // Every cell of the expansion, including the ones a wrap cut off.
        buffer.writeCharCode(_space);
        continue;
      }
      buffer.writeCharCode(unit);
      if (_isHighSurrogate(unit) && offset + 1 < source.length) {
        final low = source.codeUnitAt(offset + 1);
        if (_isLowSurrogate(low)) buffer.writeCharCode(low);
      }
    }
    return buffer.toString();
  }

  /// The model offset a grid column lands on. Out-of-range columns clamp to the
  /// row's ends, which is what a click past the end of a line should do.
  int offsetAtColumn(int column) {
    final clamped = column < 0 ? 0 : (column > columns ? columns : column);
    final offsets = _columnOffsets;
    return offsets == null ? start + clamped : offsets[clamped];
  }

  /// The grid column a model offset sits at. An offset inside a tab's expansion
  /// reports the tab's first column, never a cell in the middle of it.
  int columnAtOffset(int offset) {
    final offsets = _columnOffsets;
    if (offsets == null) {
      final column = offset - start;
      return column < 0 ? 0 : (column > columns ? columns : column);
    }
    // The first column at or after the offset. Linear, over at most 60 cells,
    // and only for rows that contain a tab or an astral scalar.
    for (var column = 0; column <= columns; column++) {
      if (offsets[column] >= offset) return column;
    }
    return columns;
  }

  /// The same row, with the newline that ends its hard line attached.
  VisualLine _terminatedBy(int hardBreak) {
    final offsets = _columnOffsets;
    return offsets == null
        ? VisualLine(start, end, columns, hardBreakOffsetUtf16: hardBreak)
        : VisualLine.mapped(
            start,
            end,
            columns,
            offsets,
            hardBreakOffsetUtf16: hardBreak,
          );
  }
}

/// One painted source scalar (or virtual tab cell), resolved by Rust metadata.
class EditorCell {
  const EditorCell(
    this.offset,
    this.end,
    this.column,
    this.width,
    this.text,
    this.run,
  );
  final int offset;
  final int end;
  final double column;
  final double width;
  final String text;
  final InlineRunView? run;
}

/// Wraps a block's text to [width] columns.
///
/// Character counting, not text measurement: the screenplay grid is monospace
/// and fixed (§5.1), so a line break is arithmetic. That is what makes it cheap
/// enough to redo on the edited block on every keystroke — and it is the same
/// arithmetic `layout::break_lines` does in Rust, so the editor and the PDF
/// cannot drift apart.
///
/// This is the editor's half of `docs/LINE_BREAKING.md`: hard newlines are
/// mandatory breaks that occupy no column, tabs expand to four-column stops
/// before wrapping, a break is taken at the rightmost space that has content
/// before it, and the whole run of spaces at a chosen boundary is consumed. A
/// break never lands inside a scalar or inside a tab's expansion. The other
/// half is `layout::break_lines`, and a case answered differently there is a
/// bug on one side or the other, never a preference.
List<VisualLine> wrapText(
  String text,
  int width, {
  List<InlineRunView> inlineRuns = const [],
}) {
  final columns = width < 1 ? 1 : width;
  final lines = <VisualLine>[];
  var hardStart = 0;
  while (true) {
    final newline = text.indexOf('\n', hardStart);
    final hardEnd = newline < 0 ? text.length : newline;
    _wrapHardLine(
      text,
      hardStart,
      hardEnd,
      columns,
      newline < 0 ? null : newline,
      lines,
      inlineRuns,
    );
    if (newline < 0) {
      for (final line in lines) {
        line._project(text, inlineRuns);
      }
      return lines;
    }
    hardStart = newline + 1;
  }
}

const int _space = 0x20;
const int _tab = 0x09;
const int _carriageReturn = 0x0d;
const int _tabStop = 4;

/// One hard line expanded onto the grid: one entry per cell.
class _Cells {
  _Cells(this.scalars, this.offsets, this.starts, this.plain);

  /// The scalar drawn in each cell. A tab contributes spaces.
  final List<int> scalars;

  /// The model offset of the scalar each cell belongs to.
  final List<int> offsets;

  /// Boundary ownership includes a hidden prefix on the following cell.
  final List<int> starts;

  /// True when cells and code units are one to one, so no per-row map is worth
  /// the memory.
  final bool plain;

  int get length => scalars.length;
}

_Cells _expand(
  String text,
  int hardStart,
  int hardEnd,
  List<InlineRunView> runs,
) {
  final scalars = <int>[];
  final offsets = <int>[];
  final starts = runs.isEmpty ? offsets : <int>[];
  var pending = hardStart;
  var runIndex = 0;
  var plain = true;
  var column = 0;
  var index = hardStart;
  while (index < hardEnd) {
    while (runIndex < runs.length && runs[runIndex].endUtf16 <= index) {
      runIndex++;
    }
    if (runIndex < runs.length &&
        runs[runIndex].startUtf16 <= index &&
        runs[runIndex].hidden) {
      plain = false;
      index = runs[runIndex].endUtf16.clamp(index, hardEnd);
      continue;
    }
    final unit = text.codeUnitAt(index);
    if (unit == _tab) {
      plain = false;
      final cells = _tabStop - column % _tabStop;
      for (var cell = 0; cell < cells; cell++) {
        scalars.add(_space);
        offsets.add(index);
        if (!identical(starts, offsets)) {
          starts.add(cell == 0 ? pending : index);
        }
      }
      column += cells;
      index += 1;
      pending = index;
      continue;
    }
    if (unit == _carriageReturn) {
      // Not part of the shared input domain; Rust drops it before wrapping.
      plain = false;
      index += 1;
      continue;
    }
    var scalar = unit;
    var units = 1;
    if (_isHighSurrogate(unit) && index + 1 < hardEnd) {
      final low = text.codeUnitAt(index + 1);
      if (_isLowSurrogate(low)) {
        scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        units = 2;
        plain = false;
      }
    }
    scalars.add(scalar);
    offsets.add(index);
    if (!identical(starts, offsets)) starts.add(pending);
    column += 1;
    pending = index + units;
    index += units;
  }
  return _Cells(scalars, offsets, starts, plain);
}

void _wrapHardLine(
  String text,
  int hardStart,
  int hardEnd,
  int width,
  int? hardBreakOffsetUtf16,
  List<VisualLine> lines,
  List<InlineRunView> inlineRuns,
) {
  final cells = _expand(text, hardStart, hardEnd, inlineRuns);
  if (cells.length == 0) {
    // An empty hard line still occupies a row: an empty block is where the
    // caret goes after the Enter that made it.
    lines.add(
      VisualLine(
        hardStart,
        hardEnd,
        0,
        hardBreakOffsetUtf16: hardBreakOffsetUtf16,
      ),
    );
    return;
  }

  final firstLine = lines.length;
  var start = 0;
  while (cells.length - start > width) {
    final breakAt = _breakColumn(cells, start, width);
    if (breakAt == null) {
      // No space to break on: the only case that splits a word.
      lines.add(_line(cells, start, start + width, hardEnd));
      start += width;
      continue;
    }
    lines.add(_line(cells, start, start + breakAt, hardEnd));
    start += breakAt;
    while (start < cells.length && cells.scalars[start] == _space) {
      start += 1;
    }
    final gapEnd = start < cells.length ? cells.starts[start] : hardEnd;
    final previous = lines.last;
    var extendedEnd = previous.end;
    for (final run in inlineRuns) {
      if (run.startUtf16 >= gapEnd) break;
      if (run.hidden && run.endUtf16 > extendedEnd) {
        extendedEnd = run.endUtf16.clamp(extendedEnd, gapEnd);
      }
    }
    if (extendedEnd > previous.end) {
      lines[lines.length - 1] = VisualLine.mapped(
        previous.start,
        extendedEnd,
        previous.columns,
        [
          for (var c = 0; c < previous.columns; c++) previous.offsetAtColumn(c),
          extendedEnd,
        ],
      );
    }
  }

  if (start < cells.length) {
    lines.add(
      _line(
        cells,
        start,
        cells.length,
        hardEnd,
        hardBreakOffsetUtf16: hardBreakOffsetUtf16,
      ),
    );
  } else if (hardBreakOffsetUtf16 != null) {
    // A consumed space run can exhaust the rest of a non-empty hard line. It
    // does not create a phantom row, but its newline still terminates the
    // preceding row.
    final last = lines.length - 1;
    assert(last >= firstLine);
    lines[last] = lines[last]._terminatedBy(hardBreakOffsetUtf16);
  }
}

/// Where to break the unplaced suffix starting at [start], or null when there is
/// no eligible space and the word must be split at the width.
int? _breakColumn(_Cells cells, int start, int width) {
  if (cells.scalars[start + width] == _space) return width;
  for (var column = width - 1; column > 0; column--) {
    if (cells.scalars[start + column] != _space) continue;
    // The rightmost space inside the width, and the only candidate: a space
    // with nothing but spaces before it would put an empty line on the page.
    for (var before = 0; before < column; before++) {
      if (cells.scalars[start + before] != _space) return column;
    }
    return null;
  }
  return null;
}

/// One row, from the half-open cell range that fits on it.
VisualLine _line(
  _Cells cells,
  int from,
  int to,
  int hardEnd, {
  int? hardBreakOffsetUtf16,
}) {
  // A row always begins on a scalar: a break lands either on a non-space cell
  // or after a whole run of spaces, and every cell of a tab is a space.
  assert(from == 0 || cells.offsets[from - 1] != cells.offsets[from]);
  final start = cells.starts[from];
  // A row ends before the scalar of the next cell, so a tab straddling the
  // boundary stays outside both rows' model slices.
  final end = to < cells.length ? cells.starts[to] : hardEnd;
  if (cells.plain) {
    return VisualLine(
      start,
      end,
      to - from,
      hardBreakOffsetUtf16: hardBreakOffsetUtf16,
    );
  }
  return VisualLine.mapped(start, end, to - from, [
    for (var cell = from; cell < to; cell++) cells.offsets[cell],
    end,
  ], hardBreakOffsetUtf16: hardBreakOffsetUtf16);
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

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
  final List<double> _displayEnds = [];
  final List<BlockView> _wrapContext = [];
  List<int> _widths = [];
  bool _pairingDirty = false;
  List<int> _rowStart = const [0];
  int _totalRows = 0;
  double _displayColumns = 0;

  int get totalRows => _totalRows;

  /// Furthest editable column, including syntax slots, cached with the wraps.
  double get displayColumns => _displayColumns;

  List<VisualLine> linesOf(int blockIndex) => _lines[blockIndex];

  /// Re-wraps every block. Called on load and when the whole list is replaced.
  void rebuild() {
    _wrapContext
      ..clear()
      ..addAll(_blocks);
    _widths = _pairedWidths();
    _pairingDirty = false;
    _lines
      ..clear()
      ..addAll([for (var i = 0; i < _blocks.length; i++) _wrap(i)]);
    _displayEnds
      ..clear()
      ..addAll([for (var i = 0; i < _blocks.length; i++) _displayEnd(i)]);
    reindex();
  }

  /// Re-wraps one edited block. Cue/kind changes also dirty the wrapping
  /// context, reconciled once when the patch reindexes.
  ///
  /// The three mutators below leave the row index stale on purpose: a patch may
  /// touch several blocks, and reindexing once at the end of it is the whole
  /// difference between O(blocks) and O(blocks × changes).
  void rewrap(int blockIndex) {
    final block = _blocks[blockIndex];
    final previous = _wrapContext[blockIndex];
    if (block.kind != previous.kind || block.dual != previous.dual) {
      _pairingDirty = true;
    }
    _wrapContext[blockIndex] = block;
    _lines[blockIndex] = _wrap(blockIndex);
    _displayEnds[blockIndex] = _displayEnd(blockIndex);
  }

  void insertAt(int blockIndex) {
    _wrapContext.insert(blockIndex, _blocks[blockIndex]);
    _widths.insert(blockIndex, metricsFor(_blocks[blockIndex].kind).width);
    _lines.insert(blockIndex, _wrap(blockIndex));
    _displayEnds.insert(blockIndex, _displayEnd(blockIndex));
    _pairingDirty = true;
  }

  void removeAt(int blockIndex) {
    _lines.removeAt(blockIndex);
    _displayEnds.removeAt(blockIndex);
    _wrapContext.removeAt(blockIndex);
    _widths.removeAt(blockIndex);
    _pairingDirty = true;
  }

  /// Recomputes the running row index. O(blocks), a few thousand integer adds
  /// on a feature-length script.
  void reindex() {
    if (_pairingDirty) {
      final widths = _pairedWidths();
      for (var i = 0; i < _blocks.length; i++) {
        if (widths[i] == _widths[i]) continue;
        _widths[i] = widths[i];
        _lines[i] = _wrap(i);
        _displayEnds[i] = _displayEnd(i);
      }
      _pairingDirty = false;
    }
    final starts = List<int>.filled(_blocks.length + 1, 0);
    var row = 0;
    var displayColumns = 0.0;
    for (var i = 0; i < _blocks.length; i++) {
      starts[i] = row;
      row += blankRowsBefore(i) + _lines[i].length;
      if (_displayEnds[i] > displayColumns) displayColumns = _displayEnds[i];
    }
    starts[_blocks.length] = row;
    _rowStart = starts;
    _totalRows = row;
    _displayColumns = displayColumns;
  }

  /// Blank rows above a block. Lyric runs share one leading blank; the first
  /// document block has none.
  int blankRowsBefore(int blockIndex) {
    if (blockIndex == 0) return 0;
    final kind = _blocks[blockIndex].kind;
    if (kind == BlockKind.lyric &&
        _blocks[blockIndex - 1].kind == BlockKind.lyric) {
      return 0;
    }
    return metricsFor(kind).blankLinesBefore;
  }

  /// The first row that shows text of this block.
  int firstRowOf(int blockIndex) =>
      _rowStart[blockIndex] + blankRowsBefore(blockIndex);

  /// One past the last row of this block.
  int endRowOf(int blockIndex) => _rowStart[blockIndex + 1];

  /// Which line of [blockIndex] holds [offset]. Offsets at a soft-wrap point
  /// belong to the line that starts there. A hard newline belongs to the line
  /// it terminates, while the offset after it starts the next line.
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
      ColumnAlignment.right => metrics.indent + metrics.width - line.columns,
      ColumnAlignment.centre =>
        metrics.indent + ((metrics.width - line.columns) ~/ 2),
    };
  }

  double _displayEnd(int blockIndex) {
    var end = 0.0;
    final lines = _lines[blockIndex];
    for (var i = 0; i < lines.length; i++) {
      final right =
          columnOf(blockIndex, i) +
          lines[i].displayColumnAtOffset(lines[i].end);
      if (right > end) end = right;
    }
    return end;
  }

  List<VisualLine> _wrap(int blockIndex) => wrapText(
    _blocks[blockIndex].text,
    _widths[blockIndex],
    inlineRuns: _blocks[blockIndex].inlineRuns,
  );

  /// Mirrors only Rust's wrapping context, not pagination or document state.
  /// Source-adjacent speeches pair greedily and disjointly; every other kind,
  /// including unprinted scaffolding, interrupts adjacency.
  List<int> _pairedWidths() {
    final widths = [for (final block in _blocks) metricsFor(block.kind).width];
    var cue = 0;
    while (cue < _blocks.length) {
      if (_blocks[cue].kind != BlockKind.character) {
        cue++;
        continue;
      }
      final next = _speechEnd(cue);
      if (next > cue + 1 &&
          next < _blocks.length &&
          _blocks[next].kind == BlockKind.character &&
          _blocks[next].dual) {
        final end = _speechEnd(next);
        if (end > next + 1) {
          for (var i = cue; i < end; i++) {
            widths[i] = switch (_blocks[i].kind) {
              BlockKind.character => dualCharacterWidth,
              BlockKind.dialogue => dualDialogueWidth,
              BlockKind.parenthetical => dualParentheticalWidth,
              _ => widths[i],
            };
          }
          cue = end;
          continue;
        }
      }
      cue = next;
    }
    return widths;
  }

  int _speechEnd(int cue) {
    var end = cue + 1;
    while (end < _blocks.length &&
        (_blocks[end].kind == BlockKind.dialogue ||
            _blocks[end].kind == BlockKind.parenthetical)) {
      end++;
    }
    return end;
  }
}
