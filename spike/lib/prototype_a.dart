/// Prototype A — one `EditableText` per paragraph inside a `ListView.builder`.
///
/// The appealing part: every paragraph is an ordinary Flutter editable, so IME,
/// composition, and per-paragraph indentation are free.
///
/// The expensive part, and the reason this prototype exists: **selection stops
/// at the widget boundary.** `EditableText` owns its own `TextSelection` and
/// knows nothing about its neighbours, so anything spanning paragraphs — the
/// selection, the copy, even shift+Down — has to be rebuilt by hand on top. The
/// code below is that reimplementation, kept as small as it can honestly be,
/// and it is the finding.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'surface.dart';
import 'synthetic.dart';

const _fontSize = 14.0;
const _lineHeight = 1.35;

class PrototypeA extends StatefulWidget {
  const PrototypeA({required this.blocks, super.key});

  final List<SyntheticBlock> blocks;

  @override
  State<PrototypeA> createState() => PrototypeAState();
}

/// A caret/selection endpoint in document coordinates. Nothing in Flutter
/// models this for us; §3.3 has the real version.
class _DocPosition {
  const _DocPosition(this.block, this.offset);
  final int block;
  final int offset;

  bool operator <=(_DocPosition other) =>
      block < other.block || (block == other.block && offset <= other.offset);
}

class PrototypeAState extends State<PrototypeA> implements SpikeSurface {
  @override
  final ScrollController scrollController = ScrollController();

  /// Controllers and focus nodes are created lazily and never freed. 3,000 live
  /// `EditableText`s is not viable, so the list virtualises — which means a
  /// paragraph's controller has to outlive its widget or the caret is lost on
  /// scroll. This map is the price.
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {};

  _DocPosition? _anchor;
  _DocPosition? _focus;

  @override
  int get blockCount => widget.blocks.length;

  double get _rowHeight => _fontSize * _lineHeight;

  TextEditingController _controllerFor(int index) => _controllers.putIfAbsent(
        index,
        () => TextEditingController(text: widget.blocks[index].text),
      );

  FocusNode _focusFor(int index) => _focusNodes.putIfAbsent(index, () => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    scrollController.dispose();
    super.dispose();
  }

  // --- SpikeSurface -------------------------------------------------------

  @override
  Future<void> placeCaret(int block, int offset) async {
    // Estimated offset: rows are not uniform height once text wraps, so this is
    // approximate — another cost of the per-block layout being opaque to us.
    final target = (block * (_rowHeight + 8.0)).clamp(0.0, scrollController.position.maxScrollExtent);
    scrollController.jumpTo(target);
    await WidgetsBinding.instance.endOfFrame;
    final node = _focusFor(block);
    node.requestFocus();
    _controllerFor(block).selection = TextSelection.collapsed(offset: offset);
    setState(() {
      _anchor = _DocPosition(block, offset);
      _focus = _anchor;
    });
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  Future<void> typeCharacter(String character) async {
    final position = _focus;
    if (position == null) return;
    final controller = _controllerFor(position.block);
    final text = controller.text;
    final at = position.offset.clamp(0, text.length);
    controller.value = TextEditingValue(
      text: text.replaceRange(at, at, character),
      selection: TextSelection.collapsed(offset: at + character.length),
    );
    setState(() => _focus = _DocPosition(position.block, at + character.length));
  }

  @override
  Future<int> arrowDown() async {
    final position = _focus;
    if (position == null) return -1;
    // Hand-rolled boundary crossing: a real implementation also has to know
    // whether the caret is on the *visual* last line of a wrapped paragraph,
    // which means asking the paragraph's RenderEditable for its line count.
    final next = (position.block + 1).clamp(0, widget.blocks.length - 1);
    _focusFor(next).requestFocus();
    _controllerFor(next).selection = const TextSelection.collapsed(offset: 0);
    setState(() {
      _focus = _DocPosition(next, 0);
      _anchor = _focus;
    });
    await WidgetsBinding.instance.endOfFrame;
    return next;
  }

  @override
  Future<String> selectFourParagraphsAsText(int startBlock) async {
    final end = (startBlock + 3).clamp(0, widget.blocks.length - 1);
    setState(() {
      _anchor = _DocPosition(startBlock, 0);
      _focus = _DocPosition(end, _controllerFor(end).text.length);
    });
    await WidgetsBinding.instance.endOfFrame;
    final text = _selectedText();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  String _selectedText() {
    final (from, to) = _normalised();
    if (from == null || to == null) return '';
    if (from.block == to.block) {
      return _controllerFor(from.block).text.substring(from.offset, to.offset);
    }
    final parts = <String>[_controllerFor(from.block).text.substring(from.offset)];
    for (var i = from.block + 1; i < to.block; i++) {
      parts.add(_controllerFor(i).text);
    }
    parts.add(_controllerFor(to.block).text.substring(0, to.offset));
    return parts.join('\n\n');
  }

  (_DocPosition?, _DocPosition?) _normalised() {
    final a = _anchor;
    final f = _focus;
    if (a == null || f == null) return (null, null);
    return a <= f ? (a, f) : (f, a);
  }

  // --- Rendering ----------------------------------------------------------

  bool _isFullySelected(int index) {
    final (from, to) = _normalised();
    if (from == null || to == null || from.block == to.block) return false;
    return index > from.block && index < to.block;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _MonoMetrics.of(context);
    return ListView.builder(
      controller: scrollController,
      itemCount: widget.blocks.length,
      itemExtent: null,
      itemBuilder: (context, index) {
        final block = widget.blocks[index];
        return Padding(
          padding: EdgeInsets.only(
            left: 24 + indentChars[block.kind]! * metrics.advance,
            top: block.kind == ElementKind.dialogue || block.kind == ElementKind.parenthetical ? 0 : 8,
          ),
          child: SizedBox(
            width: widthChars[block.kind]! * metrics.advance,
            child: ColoredBox(
              // Selection of interior paragraphs is painted by us, because
              // nothing else can see across widget boundaries.
              color: _isFullySelected(index)
                  ? const Color(0x553B6EA5)
                  : const Color(0x00000000),
              child: EditableText(
                controller: _controllerFor(index),
                focusNode: _focusFor(index),
                style: metrics.style,
                cursorColor: const Color(0xFFE0E0E0),
                backgroundCursorColor: const Color(0xFF444444),
                maxLines: null,
                selectionColor: const Color(0x553B6EA5),
                textCapitalization: block.kind == ElementKind.character ||
                        block.kind == ElementKind.sceneHeading
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                onSelectionChanged: (selection, cause) {
                  _focus = _DocPosition(index, selection.extentOffset);
                  if (!selection.isValid || selection.isCollapsed) {
                    _anchor = _focus;
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Courier-grid metrics: the advance width of one character in the chosen
/// monospace face, measured once.
class _MonoMetrics {
  _MonoMetrics(this.advance, this.style);

  final double advance;
  final TextStyle style;

  static _MonoMetrics? _cached;

  static _MonoMetrics of(BuildContext context) {
    if (_cached case final cached?) return cached;
    const style = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: _lineHeight,
      color: Color(0xFFE8E8E8),
    );
    final painter = TextPainter(
      text: const TextSpan(text: 'MMMMMMMMMM', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return _cached = _MonoMetrics(painter.width / 10, style);
  }
}
