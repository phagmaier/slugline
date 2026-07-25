/// Prototype C — one editing surface for the whole document.
///
/// A single `TextInputClient` for the document, our own line layout, our own
/// caret and selection painting, our own key handling. Nothing between us and
/// the model.
///
/// What this buys, and it is not nothing:
///
/// * Selection across paragraphs is trivial, because a selection is just two
///   `(block, offset)` pairs in a model we own.
/// * Line breaking is character counting on the monospace grid (§5.1), so what
///   we paint is exactly what `layout::paginate` will compute in Rust. The
///   editor and the PDF cannot disagree.
/// * No blinking-caret animation loop, so the 0% idle CPU budget (§1.3) is met
///   by construction rather than by fighting a widget.
///
/// What it costs is on the input side: the IME contract below is the *simple*
/// version — the current paragraph is handed to the platform as a one-block
/// editing session. Composition spanning a paragraph boundary, and the
/// platform's text-editing intents (word-wise delete, macOS-style emacs keys,
/// accessibility) are not implemented here. That gap is the finding, and it is
/// the part that does not shrink with effort.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'surface.dart';
import 'synthetic.dart';

const _fontSize = 14.0;
const _lineHeight = 19.0;
const _leftGutter = 24.0;

class PrototypeC extends StatefulWidget {
  const PrototypeC({required this.blocks, super.key});

  final List<SyntheticBlock> blocks;

  @override
  State<PrototypeC> createState() => PrototypeCState();
}

/// A position in the document. Compare with §3.3 — the same two fields.
class _Pos implements Comparable<_Pos> {
  const _Pos(this.block, this.offset);
  final int block;
  final int offset;

  @override
  int compareTo(_Pos other) =>
      block != other.block ? block.compareTo(other.block) : offset.compareTo(other.offset);
}

/// One visual line: which block it came from and the slice of that block's text
/// it shows. This is the editor's half of what `layout` will compute in Rust.
class _Line {
  const _Line(this.block, this.start, this.end, this.indent);
  final int block;
  final int start;
  final int end;
  final double indent;
}

class PrototypeCState extends State<PrototypeC> implements SpikeSurface, TextInputClient {
  @override
  final ScrollController scrollController = ScrollController();

  final FocusNode _focusNode = FocusNode();
  late final List<String> _text = [for (final b in widget.blocks) b.text];

  /// Wrapped lines per block, and the running line index at which each block
  /// starts. An edit rebuilds one block's lines and the prefix array.
  late List<List<_Line>> _blockLines;
  late List<int> _lineStart;
  int _totalLines = 0;

  _Pos _caret = const _Pos(0, 0);
  _Pos _anchor = const _Pos(0, 0);

  TextInputConnection? _connection;
  double _advance = 8.4;

  @override
  int get blockCount => _text.length;

  @override
  void initState() {
    super.initState();
    _measureAdvance();
    _relayoutAll();
    scrollController.addListener(_onScroll);
  }

  void _onScroll() => setState(() {});

  @override
  void dispose() {
    _connection?.close();
    _focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _measureAdvance() {
    final painter = TextPainter(
      text: const TextSpan(text: 'MMMMMMMMMM', style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    _advance = painter.width / 10;
  }

  // --- Line layout --------------------------------------------------------

  /// Character-count wrapping on the monospace grid. No font metrics, no
  /// shaping — §5.1's simplification, and the reason this is fast enough to
  /// redo on every keystroke.
  List<_Line> _wrap(int block) {
    final kind = widget.blocks[block].kind;
    final width = widthChars[kind]!;
    final indent = _leftGutter + indentChars[kind]! * _advance;
    final text = _text[block];
    if (text.isEmpty) return [_Line(block, 0, 0, indent)];

    final lines = <_Line>[];
    var start = 0;
    while (start < text.length) {
      if (text.length - start <= width) {
        lines.add(_Line(block, start, text.length, indent));
        break;
      }
      var breakAt = start + width;
      final space = text.lastIndexOf(' ', breakAt);
      if (space > start) breakAt = space;
      lines.add(_Line(block, start, breakAt, indent));
      start = breakAt + (text.codeUnitAt(math.min(breakAt, text.length - 1)) == 0x20 ? 1 : 0);
    }
    return lines;
  }

  void _relayoutAll() {
    _blockLines = [for (var i = 0; i < _text.length; i++) _wrap(i)];
    _rebuildIndex();
  }

  void _rebuildIndex() {
    _lineStart = List<int>.filled(_text.length + 1, 0);
    var running = 0;
    for (var i = 0; i < _text.length; i++) {
      _lineStart[i] = running;
      running += _blockLines[i].length + _blankLinesBefore(i);
    }
    _lineStart[_text.length] = running;
    _totalLines = running;
  }

  /// Blank lines before an element (§5.2), rendered as empty rows.
  int _blankLinesBefore(int block) {
    if (block == 0) return 0;
    return switch (widget.blocks[block].kind) {
      ElementKind.dialogue || ElementKind.parenthetical => 0,
      ElementKind.sceneHeading => 2,
      _ => 1,
    };
  }

  double get _documentHeight => _totalLines * _lineHeight + 64;

  int _firstLineOf(int block) => _lineStart[block] + _blankLinesBefore(block);

  /// Visual line index for a document position.
  int _lineOf(_Pos pos) {
    final lines = _blockLines[pos.block];
    for (var i = lines.length - 1; i >= 0; i--) {
      if (pos.offset >= lines[i].start) return _firstLineOf(pos.block) + i;
    }
    return _firstLineOf(pos.block);
  }

  // --- Editing ------------------------------------------------------------

  void _replaceBlock(int block, String text, int caretOffset) {
    _text[block] = text;
    _blockLines[block] = _wrap(block);
    _rebuildIndex();
    _caret = _Pos(block, caretOffset);
    _anchor = _caret;
    setState(() {});
  }

  String _textInSelection() {
    final (from, to) = _anchor.compareTo(_caret) <= 0 ? (_anchor, _caret) : (_caret, _anchor);
    if (from.block == to.block) {
      return _text[from.block].substring(from.offset, to.offset);
    }
    return [
      _text[from.block].substring(from.offset),
      for (var i = from.block + 1; i < to.block; i++) _text[i],
      _text[to.block].substring(0, to.offset),
    ].join('\n\n');
  }

  // --- SpikeSurface -------------------------------------------------------

  @override
  Future<void> placeCaret(int block, int offset) async {
    _caret = _Pos(block, offset);
    _anchor = _caret;
    final y = _lineOf(_caret) * _lineHeight;
    scrollController.jumpTo(y.clamp(0.0, math.max(0.0, _documentHeight - _viewportHeight)));
    _focusNode.requestFocus();
    _attachInput();
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  Future<void> typeCharacter(String character) async {
    final text = _text[_caret.block];
    final at = _caret.offset.clamp(0, text.length);
    _replaceBlock(_caret.block, text.replaceRange(at, at, character), at + character.length);
    _syncInputState();
  }

  @override
  Future<int> arrowDown() async {
    // We own the model, so crossing a paragraph boundary is arithmetic.
    final line = _lineOf(_caret);
    final column = _caret.offset - _blockLines[_caret.block][line - _firstLineOf(_caret.block)].start;
    final next = _positionAtLine(line + 1, column);
    setState(() {
      _caret = next;
      _anchor = next;
    });
    _syncInputState();
    await WidgetsBinding.instance.endOfFrame;
    return _caret.block;
  }

  _Pos _positionAtLine(int lineIndex, int column) {
    for (var block = 0; block < _text.length; block++) {
      final first = _firstLineOf(block);
      final lines = _blockLines[block];
      if (lineIndex >= first && lineIndex < first + lines.length) {
        final line = lines[lineIndex - first];
        return _Pos(block, math.min(line.start + column, line.end));
      }
    }
    return _Pos(_text.length - 1, _text.last.length);
  }

  @override
  Future<String> selectFourParagraphsAsText(int startBlock) async {
    final end = (startBlock + 3).clamp(0, _text.length - 1);
    setState(() {
      _anchor = _Pos(startBlock, 0);
      _caret = _Pos(end, _text[end].length);
    });
    await WidgetsBinding.instance.endOfFrame;
    final text = _textInSelection();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  // --- Platform text input ------------------------------------------------

  void _attachInput() {
    if (_connection?.attached ?? false) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
      ),
    )..show();
    _syncInputState();
  }

  /// The platform sees one paragraph at a time. Cheap, and correct for every
  /// case except a composition that spans a paragraph break.
  void _syncInputState() {
    _connection?.setEditingState(TextEditingValue(
      text: _text[_caret.block],
      selection: TextSelection.collapsed(offset: _caret.offset),
    ));
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value.text == _text[_caret.block]) return;
    _replaceBlock(_caret.block, value.text, value.selection.extentOffset.clamp(0, value.text.length));
  }

  @override
  void performAction(TextInputAction action) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void connectionClosed() => _connection = null;
  @override
  AutofillScope? get currentAutofillScope => null;
  @override
  TextEditingValue? get currentTextEditingValue => TextEditingValue(
        text: _text[_caret.block],
        selection: TextSelection.collapsed(offset: _caret.offset),
      );
  @override
  void insertTextPlaceholder(Size size) {}
  @override
  void removeTextPlaceholder() {}
  @override
  void showToolbar() {}
  @override
  void didChangeInputControl(TextInputControl? old, TextInputControl? current) {}
  @override
  void performSelector(String selectorName) {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  bool onFocusReceived() => true;
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  // --- Rendering ----------------------------------------------------------

  double _viewportHeight = 600;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveVertical(1, shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveVertical(-1, shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveHorizontal(-1, shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveHorizontal(1, shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC when HardwareKeyboard.instance.isControlPressed:
        Clipboard.setData(ClipboardData(text: _textInSelection()));
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveVertical(int delta, bool extend) {
    final line = _lineOf(_caret);
    final blockLine = _blockLines[_caret.block][line - _firstLineOf(_caret.block)];
    final column = _caret.offset - blockLine.start;
    final target = (line + delta).clamp(0, _totalLines - 1);
    setState(() {
      _caret = _positionAtLine(target, column);
      if (!extend) _anchor = _caret;
    });
    _syncInputState();
  }

  void _moveHorizontal(int delta, bool extend) {
    var block = _caret.block;
    var offset = _caret.offset + delta;
    if (offset < 0) {
      if (block == 0) return;
      block -= 1;
      offset = _text[block].length;
    } else if (offset > _text[block].length) {
      if (block == _text.length - 1) return;
      block += 1;
      offset = 0;
    }
    setState(() {
      _caret = _Pos(block, offset);
      if (!extend) _anchor = _caret;
    });
    _syncInputState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _viewportHeight = constraints.maxHeight;
      return Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTapDown: (_) {
            _focusNode.requestFocus();
            _attachInput();
          },
          child: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: _documentHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _SurfacePainter(
                  state: this,
                  scrollOffset: scrollController.hasClients ? scrollController.offset : 0,
                  viewportHeight: constraints.maxHeight,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

const _style = TextStyle(
  fontFamily: 'monospace',
  fontSize: _fontSize,
  height: 1.0,
  color: Color(0xFFE8E8E8),
);

class _SurfacePainter extends CustomPainter {
  _SurfacePainter({
    required this.state,
    required this.scrollOffset,
    required this.viewportHeight,
  });

  final PrototypeCState state;
  final double scrollOffset;
  final double viewportHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Only the visible band is laid out and painted, whatever the document
    // length. This is the whole performance story of this prototype.
    final firstLine = math.max(0, (scrollOffset / _lineHeight).floor() - 2);
    final lastLine = math.min(
      state._totalLines,
      ((scrollOffset + viewportHeight) / _lineHeight).ceil() + 2,
    );

    final (from, to) = state._anchor.compareTo(state._caret) <= 0
        ? (state._anchor, state._caret)
        : (state._caret, state._anchor);
    final selectionPaint = Paint()..color = const Color(0x553B6EA5);

    for (var block = 0; block < state._text.length; block++) {
      final first = state._firstLineOf(block);
      final lines = state._blockLines[block];
      if (first + lines.length < firstLine) continue;
      if (first > lastLine) break;

      for (var i = 0; i < lines.length; i++) {
        final lineIndex = first + i;
        if (lineIndex < firstLine || lineIndex > lastLine) continue;
        final line = lines[i];
        final y = lineIndex * _lineHeight;
        final text = state._text[block].substring(line.start, line.end);

        // Selection band for this line, in character columns.
        if (from.compareTo(to) != 0) {
          final selStart = block == from.block ? math.max(from.offset, line.start) : line.start;
          final selEnd = block == to.block ? math.min(to.offset, line.end) : line.end;
          final covered = block > from.block && block < to.block;
          if (covered || (block >= from.block && block <= to.block && selStart < selEnd)) {
            final a = covered ? line.start : selStart;
            final b = covered ? line.end : selEnd;
            canvas.drawRect(
              Rect.fromLTWH(
                line.indent + (a - line.start) * state._advance,
                y,
                math.max(2.0, (b - a) * state._advance),
                _lineHeight,
              ),
              selectionPaint,
            );
          }
        }

        TextPainter(
          text: TextSpan(text: text, style: _style),
          textDirection: TextDirection.ltr,
        )
          ..layout()
          ..paint(canvas, Offset(line.indent, y + 3));
      }
    }

    // Caret. Static, not blinking: a blink is an animation loop, and §1.3 asks
    // for 0% idle CPU.
    final caretLine = state._lineOf(state._caret);
    final lines = state._blockLines[state._caret.block];
    final line = lines[(caretLine - state._firstLineOf(state._caret.block)).clamp(0, lines.length - 1)];
    canvas.drawRect(
      Rect.fromLTWH(
        line.indent + (state._caret.offset - line.start) * state._advance,
        caretLine * _lineHeight,
        1.6,
        _lineHeight,
      ),
      Paint()..color = const Color(0xFFE0E0E0),
    );
  }

  @override
  bool shouldRepaint(_SurfacePainter old) => true;
}
