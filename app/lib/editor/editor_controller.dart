import 'dart:collection';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/line_layout.dart';

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
    assert(
      _blocks.isNotEmpty,
      'a document always has somewhere to put the caret',
    );
    _blocksView = UnmodifiableListView(_blocks);
    _layout = DocumentLayout(_blocks);
    _reindexIds();
    final first = _blocks.first;
    _selection = DocSelection(
      anchor: DocPosition(block: first.id, offsetUtf16: 0),
      focus: DocPosition(block: first.id, offsetUtf16: 0),
    );
    _refreshCompletions();
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

  List<Completion> _completions = const [];
  final Set<String> _suppressedCompletions = {};
  int _completionIndex = 0;
  // Enter accepts only after the writer moves through the popup; its initial
  // highlight is an offer, not a choice (ADR 0017).
  bool _completionWasNavigated = false;

  List<Completion> get completions => _completions;
  int get completionIndex => _completionIndex;
  bool get completionWasNavigated => _completionWasNavigated;
  Completion? get highlightedCompletion =>
      _completions.isEmpty ? null : _completions[_completionIndex];

  BlockView get focusedBlock => _blocks[_focusIndex];

  /// The row the caret is on, for scrolling it into view.
  int get caretRow => _layout.rowAt(_focusIndex, _selection.focus.offsetUtf16);

  /// What the core would write out. Phase 2 saves nothing; this is how a test
  /// asks what the core actually holds.
  String get source => core.source();

  /// Closes the core.
  ///
  /// The controller owns the core it was handed: a `DocumentCore` is a session
  /// on the actor thread, and disposing the thing that drives it is what ends
  /// it. Nothing else may close it — two closes were harmless only for as long
  /// as closing had no side effects (F12), and the whole point of a close is to
  /// acquire some.
  @override
  void dispose() {
    core.close();
    super.dispose();
  }

  // --- reading -------------------------------------------------------------

  /// `BlockId` → index, or `null` when this document has no such block.
  ///
  /// F12: this used to answer `0` for an unknown id. A stale id — a caret left
  /// behind by a patch, a find match that outlived its block — would then aim
  /// its operation at the *first block of the script*, silently, which in a
  /// program whose P0 is losing text is the worst answer available. It now says
  /// it does not know, and every caller decides what that means: an edit
  /// refuses, the caret repairs itself, and ordering sorts the id to the top.
  /// Nothing falls back to block 0 by accident any more.
  int? _indexOf(int blockId) => _indexById[blockId];

  String? _textOf(int blockId) {
    final index = _indexOf(blockId);
    return index == null ? null : _blocks[index].text;
  }

  /// The index of the block the caret is in, repairing the caret if it names a
  /// block that is gone.
  ///
  /// The caret is the one id the editor cannot proceed without: the IME reads
  /// the focused block's text and writes back into it *by id*, so a focus that
  /// quietly answered "block 0" while the selection still named a vanished
  /// block is precisely how a stale id becomes an edit to the top of the
  /// script. Moving the caret somewhere that exists costs the writer a caret
  /// position; the alternative costs them a line of their screenplay.
  int get _focusIndex {
    final ghost = _selection.focus.block;
    final index = _indexOf(ghost);
    if (index != null) return index;
    final home = DocPosition(block: _blocks.first.id, offsetUtf16: 0);
    _selection = DocSelection(anchor: home, focus: home);
    _shoutAbout(ghost);
    return 0;
  }

  /// An operation named a block that is not here. The editor and the core have
  /// drifted apart, so the operation is refused rather than aimed somewhere
  /// else — the same answer, and the same word for it, that the core gives.
  void _refuseUnknownBlock(int blockId) {
    lastRejection = EditRejection.unknownBlock;
    notifyListeners();
    _shoutAbout(blockId);
  }

  /// Debug builds stop here, because drift between the editor's block list and
  /// the core's is a bug and a test run is where it should stop being quiet.
  ///
  /// It is deliberately the *last* thing the two callers above do. An assertion
  /// that pre-empted the refusal or the repair would leave both of them
  /// unreachable in every run capable of checking that they work, and an
  /// untested recovery path is not a recovery path.
  void _shoutAbout(int blockId) {
    assert(false, 'block $blockId is not in this document');
  }

  void _reindexIds() {
    _indexById.clear();
    for (var i = 0; i < _blocks.length; i++) {
      _indexById[_blocks[i].id] = i;
    }
  }

  /// Rebuilds everything from the core, throwing away the caret and the layout.
  ///
  /// The one legitimate exception to ADR 0009's "never refetch the document":
  /// after a reload from disk or a backup restore, the core is holding a
  /// *different* document — new block ids, no shared history — and there is no
  /// patch that could describe the difference. Every other path applies a patch.
  void reloadFromCore() {
    _blocks
      ..clear()
      ..addAll(core.blocks(0, core.blockCount));
    if (_blocks.isEmpty) return;
    _reindexIds();
    _layout.rebuild();
    final first = _blocks.first;
    _selection = DocSelection(
      anchor: DocPosition(block: first.id, offsetUtf16: 0),
      focus: DocPosition(block: first.id, offsetUtf16: 0),
    );
    lastRejection = null;
    notifyListeners();
  }

  /// Document order for two positions.
  ///
  /// A comparator has no way to refuse, so an id this document does not have
  /// sorts as if it were at the top. Nothing is edited on the strength of that:
  /// the ids themselves are what reach the core, and the core refuses one it
  /// does not know.
  int comparePositions(DocPosition a, DocPosition b) {
    final byBlock = (_indexOf(a.block) ?? 0).compareTo(_indexOf(b.block) ?? 0);
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
    _refreshCompletions();
    notifyListeners();
  }

  void _moveTo(
    DocPosition position, {
    required bool extend,
    bool sticky = false,
  }) {
    if (!sticky) _stickyColumn = null;
    _selection = DocSelection(
      anchor: extend ? _selection.anchor : position,
      focus: position,
    );
    notifyListeners();
  }

  /// Drops the selection, leaving the caret at its focus.
  ///
  /// What Escape does when there is no panel to dismiss. It is a selection
  /// change and nothing else: §Phase 3 requires that Escape never loses text, so
  /// it must not be a deletion however tempting the key is.
  void collapseSelection() {
    if (!hasSelection) return;
    setSelection(
      DocSelection(anchor: _selection.focus, focus: _selection.focus),
    );
  }

  void selectAll() {
    final last = _blocks.last;
    setSelection(
      DocSelection(
        anchor: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
        focus: DocPosition(block: last.id, offsetUtf16: last.text.length),
      ),
    );
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
    final index = _focusIndex;
    final focus = _selection.focus;
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

  /// One word left or right, crossing block boundaries.
  ///
  /// A "word" is a run of word characters; moving over one skips any whitespace
  /// and punctuation on the way, which is the behaviour every text editor on this
  /// platform has. At the edge of a block the move lands on the boundary rather
  /// than carrying on into the next block: stopping at the end of a paragraph is
  /// what makes Ctrl+Right usable for getting *to* the end of a paragraph.
  void moveByWord(int delta, {bool extend = false}) {
    final index = _focusIndex;
    final focus = _selection.focus;
    final text = _blocks[index].text;

    if (delta < 0 && focus.offsetUtf16 == 0) {
      if (index == 0) return;
      final previous = _blocks[index - 1];
      _moveTo(
        DocPosition(block: previous.id, offsetUtf16: previous.text.length),
        extend: extend,
      );
      return;
    }
    if (delta > 0 && focus.offsetUtf16 >= text.length) {
      if (index == _blocks.length - 1) return;
      _moveTo(
        DocPosition(block: _blocks[index + 1].id, offsetUtf16: 0),
        extend: extend,
      );
      return;
    }
    _moveTo(
      DocPosition(
        block: focus.block,
        offsetUtf16: delta < 0
            ? wordStartBefore(text, focus.offsetUtf16)
            : wordEndAfter(text, focus.offsetUtf16),
      ),
      extend: extend,
    );
  }

  /// [rows] visual lines up or down, skipping the blank rows between elements.
  void moveVertical(int rows, {bool extend = false}) {
    final index = _focusIndex;
    final lineIndex = _layout.lineIndexAt(index, _selection.focus.offsetUtf16);
    final column =
        _stickyColumn ??
        _layout.columnOf(index, lineIndex) +
            _layout
                .linesOf(index)[lineIndex]
                .columnAtOffset(_selection.focus.offsetUtf16);

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
    final index = _focusIndex;
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
      DocPosition(block: block.id, offsetUtf16: start ? 0 : block.text.length),
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

  /// A double-click: the word under the point.
  void selectWordAt(int row, int column) {
    final block = _layout.blockAtRow(row);
    final at = _pointIn(block, row, column);
    final text = _blocks[block].text;
    // Both ends of the same word, so a click in the middle of one selects it
    // rather than reaching into the space beside it. The probe is the whole
    // character under the point — half of a surrogate pair matches nothing —
    // and an empty block has no character to probe at all.
    var start = at;
    if (text.isNotEmpty) {
      final (rune, after) = _runeAt(
        text,
        at < text.length ? at : _runeBefore(text, text.length).$2,
      );
      if (_isWordCharacter(rune)) start = wordStartBefore(text, after);
    }
    setSelection(
      DocSelection(
        anchor: DocPosition(block: _blocks[block].id, offsetUtf16: start),
        focus: DocPosition(
          block: _blocks[block].id,
          offsetUtf16: wordEndAfter(text, start),
        ),
      ),
    );
  }

  /// A triple-click: the whole element.
  void selectBlockAt(int row, int column) {
    final index = _layout.blockAtRow(row);
    final block = _blocks[index];
    setSelection(
      DocSelection(
        anchor: DocPosition(block: block.id, offsetUtf16: 0),
        focus: DocPosition(block: block.id, offsetUtf16: block.text.length),
      ),
    );
  }

  /// The offset in [blockIndex] a grid point lands on.
  int _pointIn(int blockIndex, int row, int column) {
    final lines = _layout.linesOf(blockIndex);
    final line = (row - _layout.firstRowOf(blockIndex)).clamp(
      0,
      lines.length - 1,
    );
    return _positionAt(blockIndex, line, column).offsetUtf16;
  }

  DocPosition _positionAt(int blockIndex, int lineIndex, int column) {
    final line = _layout.linesOf(blockIndex)[lineIndex];
    final startColumn = _layout.columnOf(blockIndex, lineIndex);
    final offset = line.offsetAtColumn(column - startColumn);
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

  /// Enter.
  ///
  /// The whole keystroke goes to the core in one call — replace the selection,
  /// split, and give what appears below the element type that follows this one —
  /// because all three have to be one undo step and because the last of them is
  /// a screenplay question (§2.1). The table is in `document/src/workflow.rs`
  /// and written out in `docs/KEYMAP.md`.
  void splitBlock() => _outcome(core.enter(_selection));

  /// Commits the highlighted item. This is deliberately the only completion
  /// method that writes text, and is called only from Tab/Enter key handling.
  bool acceptCompletion() {
    final candidate = highlightedCompletion;
    if (candidate == null || hasSelection) return false;
    _apply(
      EditCommand.replaceText(
        block: _selection.focus.block,
        startUtf16: candidate.startUtf16,
        endUtf16: candidate.endUtf16,
        with_: candidate.value,
      ),
    );
    dismissCompletions();
    return true;
  }

  void moveCompletion(int delta) {
    if (_completions.isEmpty) return;
    _completionIndex = (_completionIndex + delta) % _completions.length;
    if (_completionIndex < 0) _completionIndex += _completions.length;
    _completionWasNavigated = true;
    notifyListeners();
  }

  void toggleCompletionPin(Completion candidate) {
    if (!core.setEntityPinned(
      candidate.kind,
      candidate.value,
      !candidate.pinned,
    )) {
      return;
    }
    _refreshCompletions();
    notifyListeners();
  }

  void dismissCompletions({bool suppressHighlighted = false}) {
    if (suppressHighlighted) {
      final candidate = highlightedCompletion;
      if (candidate != null) _suppressedCompletions.add(candidate.value);
    }
    if (_completions.isEmpty) return;
    _completions = const [];
    _completionIndex = 0;
    _completionWasNavigated = false;
    notifyListeners();
  }

  /// Backspace.
  void deleteBackward() {
    if (hasSelection) return deleteSelection();
    final focus = _selection.focus;
    final index = _indexOf(focus.block);
    if (index == null) return _refuseUnknownBlock(focus.block);
    if (focus.offsetUtf16 > 0) {
      _apply(
        EditCommand.replaceText(
          block: focus.block,
          startUtf16: previousBoundary(_blocks[index].text, focus.offsetUtf16),
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
    if (index == null) return _refuseUnknownBlock(focus.block);
    final text = _blocks[index].text;
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

  /// Ctrl+Backspace and Ctrl+Delete: one word, in one command.
  ///
  /// At the edge of a block it falls through to the plain version, so that
  /// Ctrl+Backspace at offset 0 joins the block above rather than doing nothing.
  void deleteWord({required bool forward}) {
    if (hasSelection) return deleteSelection();
    final focus = _selection.focus;
    final text = _textOf(focus.block);
    if (text == null) return _refuseUnknownBlock(focus.block);
    final to = forward
        ? wordEndAfter(text, focus.offsetUtf16)
        : wordStartBefore(text, focus.offsetUtf16);
    if (to == focus.offsetUtf16) {
      return forward ? deleteForward() : deleteBackward();
    }
    _apply(
      EditCommand.replaceText(
        block: focus.block,
        startUtf16: forward ? focus.offsetUtf16 : to,
        endUtf16: forward ? to : focus.offsetUtf16,
        with_: '',
      ),
    );
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
  ///
  /// `forced` is true, as §Phase 3 requires: the writer has said what this
  /// element is, and automatic re-classification does not get to argue with it
  /// on the next keystroke. Doing this straight after an automatic change is
  /// therefore how you overrule one.
  void setKind(BlockKind kind, {int sectionLevel = 1}) {
    final was = _selection;
    _apply(
      EditCommand.setKind(
        block: _selection.focus.block,
        kind: kind,
        sectionLevel: sectionLevel,
        forced: true,
      ),
    );
    _restoreCaret(was);
  }

  /// Tab, or Shift+Tab: the next element type at this position, or nothing at
  /// all where the table has none. See `docs/KEYMAP.md`.
  void cycleElement({bool reverse = false}) {
    final was = _selection;
    final outcome = core.tab(_selection, shift: reverse);
    // No answer means Tab has nothing to do here. That is not a refusal, so
    // nothing is reported and nothing repaints.
    if (outcome == null) return;
    _outcome(outcome);
    _restoreCaret(was);
  }

  /// The element type Tab would move to from here, for the element bar's hint.
  BlockKind? tabTarget({bool reverse = false}) =>
      core.tabTarget(_selection.focus.block, shift: reverse);

  /// A character cue the script already has whose name the caret's block
  /// matches. Shown as a hint; only Tab acts on it.
  String? get characterSuggestion =>
      core.characterSuggestion(_selection.focus.block);

  /// Puts the caret back where it was after an edit that changed no text.
  ///
  /// A kind change reports the caret at the end of the block, which is the only
  /// answer the core can give without owning the caret — and it is the wrong one
  /// for a writer who pressed the shortcut mid-sentence. The offsets are still
  /// valid because no character moved, but they are clamped anyway: the block may
  /// have been refused and left as it was.
  void _restoreCaret(DocSelection was) {
    if (lastRejection != null) return;
    final anchor = _clamp(was.anchor);
    final focus = _clamp(was.focus);
    if (anchor == null || focus == null) return;
    setSelection(DocSelection(anchor: anchor, focus: focus));
  }

  DocPosition? _clamp(DocPosition position) {
    final index = _indexById[position.block];
    if (index == null) return null;
    final text = _blocks[index].text;
    return DocPosition(
      block: position.block,
      offsetUtf16: _snapToBoundary(text, position.offsetUtf16),
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

  // --- find and replace ----------------------------------------------------

  FindQuery _query = const FindQuery(
    text: '',
    caseSensitive: false,
    wholeWord: false,
    kinds: [],
  );
  List<FindMatch> _matches = const [];
  int _matchIndex = 0;

  FindQuery get query => _query;

  /// Every match of the current query, in document order.
  List<FindMatch> get matches => _matches;

  /// Which match the caret is on, or `null` when there are none. The find bar
  /// shows this as "3 of 17".
  int? get matchIndex => _matches.isEmpty ? null : _matchIndex;

  /// Runs [query] and selects the first match at or after the caret, so that
  /// typing in the find box walks forwards through the script rather than
  /// jumping back to the top on every keystroke.
  void search(FindQuery query) {
    _query = query;
    _matches = core.find(query);
    if (_matches.isEmpty) {
      _matchIndex = 0;
      notifyListeners();
      return;
    }
    final from = orderedSelection.$1;
    _matchIndex = _matches.indexWhere((match) => _isAtOrAfter(match, from));
    if (_matchIndex < 0) _matchIndex = 0;
    _selectMatch();
  }

  /// Re-runs the current query. Called after an edit changes the text under it.
  void refreshSearch() {
    if (_query.text.isEmpty) {
      _matches = const [];
      return;
    }
    _matches = core.find(_query);
    if (_matchIndex >= _matches.length) _matchIndex = 0;
  }

  void nextMatch() => _step(1);

  void previousMatch() => _step(-1);

  void _step(int delta) {
    if (_matches.isEmpty) return;
    _matchIndex = (_matchIndex + delta) % _matches.length;
    if (_matchIndex < 0) _matchIndex += _matches.length;
    _selectMatch();
  }

  void _selectMatch() {
    final match = _matches[_matchIndex];
    setSelection(
      DocSelection(
        anchor: DocPosition(block: match.block, offsetUtf16: match.startUtf16),
        focus: DocPosition(block: match.block, offsetUtf16: match.endUtf16),
      ),
    );
  }

  /// Replaces the match the caret is on and moves to the next one.
  void replaceCurrent(String with_) {
    if (_matches.isEmpty) return;
    final match = _matches[_matchIndex];
    _apply(
      EditCommand.replaceText(
        block: match.block,
        startUtf16: match.startUtf16,
        endUtf16: match.endUtf16,
        with_: with_,
      ),
    );
    if (lastRejection != null) return;
    // `_outcome` has already re-run the query: the match list was stale the
    // moment the text under it changed.
    if (_matches.isEmpty) {
      _matchIndex = 0;
      notifyListeners();
      return;
    }
    // Forwards from where the replacement left the caret, so replacing a word
    // with something containing it does not loop on itself.
    final after = orderedSelection.$2;
    final next = _matches.indexWhere(
      (candidate) => _isAtOrAfter(candidate, after),
    );
    _matchIndex = next < 0 ? 0 : next;
    _selectMatch();
  }

  /// Replaces every match, as one undo transaction.
  void replaceAll(String with_) {
    if (_query.text.isEmpty) return;
    final was = _selection;
    _outcome(core.replaceAll(_query, with_));
    if (lastRejection != null) return;
    _matchIndex = 0;
    // The caret was not necessarily anywhere near a replacement, so it stays
    // where the writer left it rather than following the last one.
    _restoreCaret(was);
  }

  bool _isAtOrAfter(FindMatch match, DocPosition position) {
    // As in [comparePositions]: ordering cannot refuse, and no edit is aimed by
    // the answer — `replaceCurrent` sends the match's own id to the core.
    final byBlock = (_indexOf(match.block) ?? 0).compareTo(
      _indexOf(position.block) ?? 0,
    );
    if (byBlock != 0) return byBlock > 0;
    return match.startUtf16 >= position.offsetUtf16;
  }

  // --- history -------------------------------------------------------------

  void undo() => _replay(core.undo());

  void redo() => _replay(core.redo());

  void _replay(EditResult? result) {
    if (result == null) return;
    lastRejection = null;
    _applyResult(result);
    refreshSearch();
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
        // Every match offset is an offset into text the edit may have moved.
        refreshSearch();
        _refreshCompletions();
      case EditOutcome_Rejected(:final reason):
        lastRejection = reason;
    }
    _stickyColumn = null;
    notifyListeners();
  }

  void _refreshCompletions() {
    _completionWasNavigated = false;
    if (hasSelection) {
      _completions = const [];
      _completionIndex = 0;
      return;
    }
    final focus = _selection.focus;
    _completions = core.complete(
      focus.block,
      focus.offsetUtf16,
      _suppressedCompletions.toList(growable: false),
    );
    if (_completionIndex >= _completions.length) _completionIndex = 0;
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

/// Letters, digits, combining marks, `_`, and the apostrophe — so that word-wise
/// motion treats "don't" as one word and "café" as one word.
///
/// Spelled out rather than `\w`, which in Dart is ASCII even with `unicode: true`
/// and would stop at the first accent in a script full of them. Built once: this
/// runs per character.
final RegExp _wordCharacter = RegExp(r"[\p{L}\p{N}\p{M}_'’]", unicode: true);

/// Whether [rune] — a whole Unicode scalar, not a UTF-16 code unit — is one.
///
/// F12: this used to be asked per code unit, and half a surrogate pair is not a
/// character. `\p{L}` never matches one, so every astral-plane letter — 𝐀, 𝔄,
/// 𝕬, an emoji in a stage direction — looked like punctuation, and Ctrl+arrow
/// stopped inside a word instead of stepping over it. Offsets stay UTF-16 (ADR
/// 0008); only the classification is per scalar.
bool _isWordCharacter(int rune) =>
    _wordCharacter.hasMatch(String.fromCharCode(rune));

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// The scalar ending at [end], and the offset it starts at.
///
/// An unpaired surrogate is returned as itself: it is not a word character, so
/// motion steps over it one code unit at a time rather than looping.
(int, int) _runeBefore(String text, int end) {
  final last = text.codeUnitAt(end - 1);
  if (end >= 2 && _isLowSurrogate(last)) {
    final first = text.codeUnitAt(end - 2);
    if (_isHighSurrogate(first)) {
      return (_combine(first, last), end - 2);
    }
  }
  return (last, end - 1);
}

/// The scalar starting at [start], and the offset just past it.
(int, int) _runeAt(String text, int start) {
  final first = text.codeUnitAt(start);
  if (start + 1 < text.length && _isHighSurrogate(first)) {
    final last = text.codeUnitAt(start + 1);
    if (_isLowSurrogate(last)) {
      return (_combine(first, last), start + 2);
    }
  }
  return (first, start + 1);
}

int _combine(int high, int low) =>
    0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);

/// The start of the word at or before [offset]: whitespace and punctuation are
/// skipped, then the run of word characters.
int wordStartBefore(String text, int offset) {
  var at = offset.clamp(0, text.length);
  while (at > 0) {
    final (rune, start) = _runeBefore(text, at);
    if (_isWordCharacter(rune)) break;
    at = start;
  }
  while (at > 0) {
    final (rune, start) = _runeBefore(text, at);
    if (!_isWordCharacter(rune)) break;
    at = start;
  }
  return at;
}

/// The end of the word at or after [offset], the same way round.
int wordEndAfter(String text, int offset) {
  var at = offset.clamp(0, text.length);
  while (at < text.length) {
    final (rune, end) = _runeAt(text, at);
    if (_isWordCharacter(rune)) break;
    at = end;
  }
  while (at < text.length) {
    final (rune, end) = _runeAt(text, at);
    if (!_isWordCharacter(rune)) break;
    at = end;
  }
  return at;
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
/// Only a click can produce one. A column is one Unicode scalar, so no click
/// lands inside an emoji's surrogate pair any more — but a grapheme cluster is
/// several scalars and so several columns, and a caret between a letter and its
/// combining mark is still an offset to step off (`docs/LINE_BREAKING.md`).
int _snapToBoundary(String text, int offset) {
  final clamped = offset.clamp(0, text.length);
  if (clamped == 0 || clamped == text.length) return clamped;
  // `CharacterRange.at` expands to cover the cluster an index falls inside, so
  // what is before the range is the boundary we want.
  return CharacterRange.at(text, clamped).stringBeforeLength;
}
