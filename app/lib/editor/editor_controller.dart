import 'dart:collection';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/line_layout.dart';
import 'package:slugline/editor/metrics.dart';

/// The editor's copy of the document, and every operation the surface performs
/// on it.
///
/// The division of labour is §2.1's, exactly: this class owns the caret, the
/// selection, the wrapped line geometry and the scroll intent. It owns no
/// screenplay semantics at all — every change to the text goes to the core as an
/// `EditCommand` and comes back as a patch, and the patch is applied here rather
/// than the document being refetched (§6).
class EditorController extends ChangeNotifier {
  EditorController(this.core) {
    _blocks.addAll(core.blocks(0, core.blockCount));
    assert(_blocks.isNotEmpty, 'a document always has somewhere to put the caret');
    _blocksView = UnmodifiableListView(_blocks);
    _layout = DocumentLayout(_blocks);
    _reindexIds();
    final first = _blocks.first;
    _selection = DocSelection(
      anchor: DocPosition(block: first.id, offsetUtf16: 0),
      focus: DocPosition(block: first.id, offsetUtf16: 0),
    );
  }

  final DocumentCore core;

  final List<BlockView> _blocks = [];
  late final DocumentLayout _layout;

  /// `BlockId` → index. Rebuilt only when the block list changes shape, so the
  /// common edit — one block's text — costs a map lookup rather than a scan.
  final Map<int, int> _indexById = {};

  late DocSelection _selection;

  /// The column vertical movement is aiming for, so that moving down through a
  /// short line and out the other side lands where the caret started rather than
  /// where the short line ended.
  int? _stickyColumn;

  /// Why the last edit was refused, if it was. The surface shows it and clears
  /// it; nothing else depends on it.
  EditRejection? lastRejection;

  late final UnmodifiableListView<BlockView> _blocksView;

  /// The blocks, in document order. The layout below shares this list rather
  /// than copying it, so a patch mutates both at once.
  List<BlockView> get blocks => _blocksView;
  DocumentLayout get layout => _layout;
  DocSelection get selection => _selection;
  bool get hasSelection => _selection.anchor != _selection.focus;

  BlockView get focusedBlock => _blocks[_indexOf(_selection.focus.block)];

  /// The row the caret is on, for scrolling it into view.
  int get caretRow {
    final index = _indexOf(_selection.focus.block);
    return _layout.rowAt(index, _selection.focus.offsetUtf16);
  }

  /// What the core would write out. Phase 2 saves nothing; this is how a test
  /// asks what the core actually holds.
  String get source => core.source();

  @override
  void dispose() {
    core.close();
    super.dispose();
  }

  // --- reading -------------------------------------------------------------

  int _indexOf(int blockId) => _indexById[blockId] ?? 0;

  String _textOf(int blockId) => _blocks[_indexOf(blockId)].text;

  void _reindexIds() {
    _indexById.clear();
    for (var i = 0; i < _blocks.length; i++) {
      _indexById[_blocks[i].id] = i;
    }
  }

  /// Document order for two positions.
  int comparePositions(DocPosition a, DocPosition b) {
    final byBlock = _indexOf(a.block).compareTo(_indexOf(b.block));
    return byBlock != 0 ? byBlock : a.offsetUtf16.compareTo(b.offsetUtf16);
  }

  /// The selection, in document order.
  (DocPosition, DocPosition) get orderedSelection =>
      comparePositions(_selection.anchor, _selection.focus) <= 0
          ? (_selection.anchor, _selection.focus)
          : (_selection.focus, _selection.anchor);

  // --- selection -----------------------------------------------------------

  void setSelection(DocSelection selection, {bool keepStickyColumn = false}) {
    if (!keepStickyColumn) _stickyColumn = null;
    _selection = selection;
    notifyListeners();
  }

  void _moveTo(DocPosition position, {required bool extend, bool sticky = false}) {
    if (!sticky) _stickyColumn = null;
    _selection = DocSelection(
      anchor: extend ? _selection.anchor : position,
      focus: position,
    );
    notifyListeners();
  }

  void selectAll() {
    final last = _blocks.last;
    setSelection(DocSelection(
      anchor: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
      focus: DocPosition(block: last.id, offsetUtf16: last.text.length),
    ));
  }

  // --- navigation ----------------------------------------------------------

  /// One grapheme cluster left or right, crossing block boundaries.
  ///
  /// Cluster-wise rather than code-unit-wise so that the caret can never come to
  /// rest between the halves of a surrogate pair — an offset the bridge refuses
  /// outright (ADR 0001), which would make the next keystroke do nothing at all.
  void moveHorizontal(int delta, {bool extend = false}) {
    if (!extend && hasSelection) {
      // Collapsing a selection is a move in itself, as in every text editor.
      final (start, end) = orderedSelection;
      _moveTo(delta < 0 ? start : end, extend: false);
      return;
    }
    final focus = _selection.focus;
    final index = _indexOf(focus.block);
    final text = _blocks[index].text;

    if (delta < 0) {
      if (focus.offsetUtf16 > 0) {
        _moveTo(
          DocPosition(
            block: focus.block,
            offsetUtf16: previousBoundary(text, focus.offsetUtf16),
          ),
          extend: extend,
        );
      } else if (index > 0) {
        final previous = _blocks[index - 1];
        _moveTo(
          DocPosition(block: previous.id, offsetUtf16: previous.text.length),
          extend: extend,
        );
      }
    } else {
      if (focus.offsetUtf16 < text.length) {
        _moveTo(
          DocPosition(
            block: focus.block,
            offsetUtf16: nextBoundary(text, focus.offsetUtf16),
          ),
          extend: extend,
        );
      } else if (index < _blocks.length - 1) {
        _moveTo(
          DocPosition(block: _blocks[index + 1].id, offsetUtf16: 0),
          extend: extend,
        );
      }
    }
  }

  /// [rows] visual lines up or down, skipping the blank rows between elements.
  void moveVertical(int rows, {bool extend = false}) {
    final index = _indexOf(_selection.focus.block);
    final lineIndex = _layout.lineIndexAt(index, _selection.focus.offsetUtf16);
    final column = _stickyColumn ??
        _layout.columnOf(index, lineIndex) +
            (_selection.focus.offsetUtf16 - _layout.linesOf(index)[lineIndex].start);

    var block = index;
    var line = lineIndex + rows;
    while (line < 0) {
      if (block == 0) {
        line = 0;
        break;
      }
      block -= 1;
      line += _layout.linesOf(block).length;
    }
    while (line >= _layout.linesOf(block).length) {
      if (block == _blocks.length - 1) {
        line = _layout.linesOf(block).length - 1;
        break;
      }
      line -= _layout.linesOf(block).length;
      block += 1;
    }

    _stickyColumn = column;
    _moveTo(_positionAt(block, line, column), extend: extend, sticky: true);
  }

  void moveToLineEdge({required bool start, bool extend = false}) {
    final index = _indexOf(_selection.focus.block);
    final lineIndex = _layout.lineIndexAt(index, _selection.focus.offsetUtf16);
    final line = _layout.linesOf(index)[lineIndex];
    _moveTo(
      DocPosition(
        block: _selection.focus.block,
        offsetUtf16: start ? line.start : line.end,
      ),
      extend: extend,
    );
  }

  void moveToDocumentEdge({required bool start, bool extend = false}) {
    final block = start ? _blocks.first : _blocks.last;
    _moveTo(
      DocPosition(
        block: block.id,
        offsetUtf16: start ? 0 : block.text.length,
      ),
      extend: extend,
    );
  }

  /// The caret nearest a point on the grid, for a click or a drag.
  void placeCaretAt(int row, int column, {bool extend = false}) {
    final block = _layout.blockAtRow(row);
    final lines = _layout.linesOf(block);
    final line = (row - _layout.firstRowOf(block)).clamp(0, lines.length - 1);
    _moveTo(_positionAt(block, line, column), extend: extend);
  }

  DocPosition _positionAt(int blockIndex, int lineIndex, int column) {
    final line = _layout.linesOf(blockIndex)[lineIndex];
    final startColumn = _layout.columnOf(blockIndex, lineIndex);
    final offset = line.start + (column - startColumn).clamp(0, line.length);
    return DocPosition(
      block: _blocks[blockIndex].id,
      offsetUtf16: _snapToBoundary(_blocks[blockIndex].text, offset),
    );
  }

  // --- editing -------------------------------------------------------------

  /// Inserts text at the caret, replacing the selection if there is one.
  void insertText(String text) {
    if (text.isEmpty && !hasSelection) return;
    final (start, end) = orderedSelection;
    if (start.block == end.block) {
      _apply(
        EditCommand.replaceText(
          block: start.block,
          startUtf16: start.offsetUtf16,
          endUtf16: end.offsetUtf16,
          with_: text,
        ),
      );
      return;
    }
    // Across blocks the delete and the insert have to be one undo step, and the
    // core's paste is exactly that. `plain` so that a typed `#` is a character
    // and not a section heading.
    _outcome(core.paste(_selection, text, plain: true));
  }

  /// Enter: the block splits at the caret and the caret lands in the new one.
  void splitBlock() {
    if (hasSelection) {
      deleteSelection();
      if (hasSelection) return; // The delete was refused.
    }
    _apply(
      EditCommand.splitBlock(
        block: _selection.focus.block,
        atUtf16: _selection.focus.offsetUtf16,
      ),
    );
  }

  /// Backspace.
  void deleteBackward() {
    if (hasSelection) return deleteSelection();
    final focus = _selection.focus;
    final index = _indexOf(focus.block);
    if (focus.offsetUtf16 > 0) {
      _apply(
        EditCommand.replaceText(
          block: focus.block,
          startUtf16: previousBoundary(_textOf(focus.block), focus.offsetUtf16),
          endUtf16: focus.offsetUtf16,
          with_: '',
        ),
      );
    } else if (index > 0) {
      // At the very start of a block, backspace joins it to the one above.
      _apply(EditCommand.mergeBlocks(first: _blocks[index - 1].id));
    }
  }

  /// Delete.
  void deleteForward() {
    if (hasSelection) return deleteSelection();
    final focus = _selection.focus;
    final index = _indexOf(focus.block);
    final text = _textOf(focus.block);
    if (focus.offsetUtf16 < text.length) {
      _apply(
        EditCommand.replaceText(
          block: focus.block,
          startUtf16: focus.offsetUtf16,
          endUtf16: nextBoundary(text, focus.offsetUtf16),
          with_: '',
        ),
      );
    } else if (index < _blocks.length - 1) {
      _apply(EditCommand.mergeBlocks(first: focus.block));
    }
  }

  void deleteSelection() {
    if (!hasSelection) return;
    final (start, end) = orderedSelection;
    if (start.block == end.block) {
      _apply(
        EditCommand.replaceText(
          block: start.block,
          startUtf16: start.offsetUtf16,
          endUtf16: end.offsetUtf16,
          with_: '',
        ),
      );
    } else {
      _apply(EditCommand.deleteRange(from: start, to: end));
    }
  }

  /// Changes the element type of the block the caret is in, without touching a
  /// character of its text (§13, `element_change_preserves_text`).
  void setKind(BlockKind kind, {int sectionLevel = 1}) {
    _apply(
      EditCommand.setKind(
        block: _selection.focus.block,
        kind: kind,
        sectionLevel: sectionLevel,
        forced: true,
      ),
    );
  }

  // --- clipboard -----------------------------------------------------------

  /// The selection as Fountain. The core decides what that means; the editor
  /// only knows where the selection is.
  String? selectedText() {
    if (!hasSelection) return null;
    final (start, end) = orderedSelection;
    return core.extract(start, end);
  }

  Future<void> copy() async {
    final text = selectedText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> cut() async {
    final text = selectedText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    deleteSelection();
  }

  /// [plain] is `Ctrl+Shift+V`: the text arrives as Action, with nothing
  /// inferred from it.
  Future<void> paste({bool plain = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _outcome(core.paste(_selection, text, plain: plain));
  }

  // --- history -------------------------------------------------------------

  void undo() => _replay(core.undo());

  void redo() => _replay(core.redo());

  void _replay(EditResult? result) {
    if (result == null) return;
    _applyResult(result);
    notifyListeners();
  }

  // --- applying what the core says -----------------------------------------

  void _apply(EditCommand command) {
    _outcome(core.apply(command, before: _selection));
  }

  void _outcome(EditOutcome outcome) {
    switch (outcome) {
      case EditOutcome_Applied(:final result):
        lastRejection = null;
        _applyResult(result);
      case EditOutcome_Rejected(:final reason):
        lastRejection = reason;
    }
    _stickyColumn = null;
    notifyListeners();
  }

  /// Applies a patch (§6): drop what went, update what changed, insert what
  /// appeared. Nothing is refetched — a full refetch of a 120-page script on
  /// every keystroke is the thing this exists to avoid.
  void _applyResult(EditResult result) {
    var structural = false;

    if (result.removed.isNotEmpty) {
      final gone = result.removed.toSet();
      // Descending, so an index stays valid while the ones below it go.
      for (var i = _blocks.length - 1; i >= 0; i--) {
        if (gone.contains(_blocks[i].id)) {
          _blocks.removeAt(i);
          _layout.removeAt(i);
        }
      }
      structural = true;
    }

    if (structural) _reindexIds();

    for (final block in result.changed) {
      final index = _indexById[block.id];
      if (index == null) continue;
      _blocks[index] = block;
      _layout.rewrap(index);
    }

    for (final inserted in result.inserted) {
      final at = inserted.index.clamp(0, _blocks.length);
      _blocks.insert(at, inserted.block);
      _layout.insertAt(at);
      structural = true;
    }

    if (structural) _reindexIds();
    _layout.reindex();

    assert(
      _blocks.length == result.blockCount,
      'the editor and the core disagree about how many blocks there are: '
      '${_blocks.length} here, ${result.blockCount} in the core',
    );

    if (result.selection case final selection?) {
      _selection = selection;
    } else {
      _selection = DocSelection(
        anchor: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
        focus: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
      );
    }
  }
}

/// The offset one grapheme cluster before [offset].
int previousBoundary(String text, int offset) {
  if (offset <= 0) return 0;
  final before = text.substring(0, math.min(offset, text.length));
  return before.length - before.characters.last.length;
}

/// The offset one grapheme cluster after [offset].
int nextBoundary(String text, int offset) {
  if (offset >= text.length) return text.length;
  return offset + text.substring(offset).characters.first.length;
}

/// Nudges an offset that landed inside a cluster back to the start of it.
///
/// Only a click can produce one: the grid is measured in UTF-16 code units, and
/// a column can land in the middle of the two units an emoji is written with.
int _snapToBoundary(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  if (clamped == 0 || clamped == text.length) return clamped;
  // `CharacterRange.at` expands to cover the cluster an index falls inside, so
  // what is before the range is the boundary we want.
  return CharacterRange.at(text, clamped).stringBeforeLength;
}

/// The label for the element the caret is in, for the status bar.
String currentKindLabel(EditorController controller) {
  final block = controller.focusedBlock;
  return kindLabel(block.kind, block.sectionLevel);
}
