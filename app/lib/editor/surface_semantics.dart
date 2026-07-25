import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The semantics node for one block of the editing surface.
///
/// ADR 0005 chose one custom editing surface over `EditableText`, and listed
/// what that costs. This is the last of those items: `EditableText` puts a
/// `textField` node with a value and a caret into the semantics tree for free,
/// and a `CustomPaint` puts nothing there at all. A screen reader pointed at the
/// surface before this existed found a scrollable with no content in it.
///
/// It is a render object rather than a [Semantics] widget or a
/// `CustomPainter.semanticsBuilder` for one reason: **the caret**.
/// `SemanticsProperties` — which is all either of those can express — has no
/// field for a text selection, and `SemanticsConfiguration.textSelection` is
/// what carries the caret offset to AT-SPI as `textSelectionBase`/`Extent`.
/// Without it a screen reader can read the paragraph but cannot tell you where
/// in it you are, which for a writing tool is most of the point. `RenderEditable`
/// reaches the same setter the same way.
///
/// One node per block rather than one for the document. A `value` is one string,
/// and the document's is 500 kB on a feature; per-block nodes are what the
/// screen reader can navigate paragraph by paragraph anyway, and they are what
/// let the element type be announced — "Character, JOHN" is the thing a
/// screenwriter needs to hear and the thing no generic text field could say.
///
/// The node paints nothing and never hit-tests, so it costs a layout of a
/// zero-work box. The surface only builds these while
/// [SemanticsBinding.semanticsEnabled] is true, so with no assistive technology
/// running the cost is not paid at all.
class ScriptBlockSemantics extends LeafRenderObjectWidget {
  const ScriptBlockSemantics({
    required this.label,
    required this.value,
    required this.focused,
    required this.selection,
    required this.readOnly,
    required this.onFocusRequested,
    required this.onSetSelection,
    required this.onSetText,
    required this.onMoveCursorByCharacter,
    required this.onMoveCursorByWord,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    super.key,
  });

  /// The element type, as `kindLabel` gives it: "Scene heading", "Dialogue".
  final String label;

  /// The block's text as it is drawn — upper-cased where §5.2 upper-cases it.
  /// `displayText` never changes a string's length, so [selection]'s offsets
  /// index into this exactly as they index into the model's text.
  final String value;

  /// Whether the caret is in this block.
  final bool focused;

  /// The caret or selection within this block. Only read when [focused].
  final TextSelection selection;

  /// Opaque blocks refuse every edit (§3.2); saying so stops a screen reader
  /// offering an edit the core will reject.
  final bool readOnly;

  /// Move the caret into this block. Bound to both a tap and the moment the
  /// node takes accessibility focus, so that swiping through the document with
  /// a screen reader moves the real caret with it.
  final VoidCallback onFocusRequested;

  final SetSelectionHandler onSetSelection;
  final SetTextHandler onSetText;

  /// `(delta, extendSelection)`. Delta is +1 or -1.
  final void Function(int delta, bool extendSelection) onMoveCursorByCharacter;
  final void Function(int delta, bool extendSelection) onMoveCursorByWord;

  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onPaste;

  @override
  RenderScriptBlockSemantics createRenderObject(BuildContext context) =>
      RenderScriptBlockSemantics(this);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderScriptBlockSemantics renderObject,
  ) {
    renderObject.description = this;
  }
}

/// The render object behind [ScriptBlockSemantics]. Occupies the block's
/// rectangle, paints nothing, and describes itself.
///
/// It keeps the widget rather than copying its thirteen fields out: every one of
/// them is part of one description, and splitting them into thirteen setters
/// would mean thirteen chances to forget a [markNeedsSemanticsUpdate].
class RenderScriptBlockSemantics extends RenderBox {
  RenderScriptBlockSemantics(this._description);

  ScriptBlockSemantics _description;

  set description(ScriptBlockSemantics value) {
    final previous = _description;
    _description = value;
    // The handlers are closures rebuilt every frame, so comparing them would
    // never say "unchanged". What the tree holds is the five fields below plus
    // *which* actions are on offer, and that follows from `focused` and
    // `readOnly` — so this covers it exactly.
    if (previous.label != value.label ||
        previous.value != value.value ||
        previous.focused != value.focused ||
        previous.selection != value.selection ||
        previous.readOnly != value.readOnly) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// Never. The surface's `Listener` sits above the scroll view and owns every
  /// pointer; this box must not take one away from it.
  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final block = _description;
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = block.label
      ..value = block.value
      ..isTextField = true
      ..isMultiline = true
      ..isReadOnly = block.readOnly
      ..isFocused = block.focused
      ..onTap = block.onFocusRequested
      ..onDidGainAccessibilityFocus = block.onFocusRequested;

    // Everything below acts on the caret, and there is one caret. Offering it
    // on a block that does not hold it would mean a move that silently jumps
    // somewhere else first.
    if (!block.focused) return;
    config
      ..textSelection = block.selection
      ..onSetSelection = block.onSetSelection
      ..onMoveCursorForwardByCharacter = (extend) {
        block.onMoveCursorByCharacter(1, extend);
      }
      ..onMoveCursorBackwardByCharacter = (extend) {
        block.onMoveCursorByCharacter(-1, extend);
      }
      ..onMoveCursorForwardByWord = (extend) {
        block.onMoveCursorByWord(1, extend);
      }
      ..onMoveCursorBackwardByWord = (extend) {
        block.onMoveCursorByWord(-1, extend);
      }
      ..onCopy = block.onCopy;
    if (block.readOnly) return;
    config
      ..onSetText = block.onSetText
      ..onCut = block.onCut
      ..onPaste = block.onPaste;
  }
}
