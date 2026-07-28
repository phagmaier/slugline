import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';
import 'package:slugline/editor/line_layout.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_geometry.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/editor/surface_semantics.dart';
import 'package:slugline/typography.dart';

/// One editing surface for the whole document (ADR 0005).
///
/// There is no widget per block and no `EditableText` anywhere. The document is
/// a list of rows on a monospace grid; this paints the ones that are on screen,
/// puts the caret where the arithmetic says, and sends every change to the core.
/// A 120-page script costs the same to paint as a one-page one, and a selection
/// spanning forty paragraphs is two `(block, offset)` pairs.
///
/// The platform's text input protocol is still Flutter's: we implement
/// [TextInputClient] and hand the platform the block the caret is in, which is
/// what makes an IME work. What we own is the model, the layout and the
/// painting.
class EditorSurface extends StatefulWidget {
  const EditorSurface({
    required this.controller,
    this.initialScrollRow = 0,
    this.textSize = 15,
    this.pageView = true,
    this.pageIndicator,
    this.focusNode,
    this.onOpenPalette,
    this.onOpenFind,
    this.onEscape,
    this.onComposingChanged,
    this.onScrolled,
    super.key,
  });

  final EditorController controller;

  /// The visual row to put at the top once the scroll extent is known.
  /// Applied once, rather than through [ScrollController.initialScrollOffset],
  /// because a stale row must be clamped against the newly laid-out document.
  final int initialScrollRow;
  final double textSize;

  /// Whether to draw the script as discrete sheets of paper rather than one
  /// continuous column. On by default (§Phase 10 preference `page_view`), and it
  /// falls back to continuous until [pageIndicator] has a pagination to draw —
  /// which is also what a widget test with no core behind it gets.
  final bool pageView;

  /// Where Rust's paginator put the page breaks.
  ///
  /// The surface draws page furniture from this and computes none of it. Null in
  /// a widget test, and before the first snapshot arrives, and the surface then
  /// draws a plain column — which is exactly what an unpaginated editor should
  /// show when it does not yet know where the pages fall.
  final PageIndicator? pageIndicator;

  /// Supplied when something above the surface has to be able to give it the
  /// keyboard back — which the editor page does when it closes a panel. The
  /// surface makes its own when nobody needs to.
  final FocusNode? focusNode;

  /// `Ctrl+K`, `Ctrl+F` and Escape. The surface has the keyboard focus, so it
  /// sees these first, but it owns none of them: what a panel is and where it
  /// sits belongs to the page above (see `editor_page.dart`). Escape is handed
  /// up unconditionally and never touches the document — §Phase 3 requires that
  /// it dismiss whatever is open without losing text.
  final VoidCallback? onOpenPalette;
  final VoidCallback? onOpenFind;
  final VoidCallback? onEscape;

  /// Whether the platform is holding a composing region right now.
  ///
  /// The surface is the only thing that knows: the composition lives in the
  /// `TextInputClient` contract it implements. §Phase 4 forbids autosaving
  /// during one, so the page above needs telling — see `editor_page.dart`.
  final void Function(bool composing)? onComposingChanged;

  /// The top visual row on screen, as it changes. Parked in the library index so
  /// that session restore, and a crash, both put the writer back where they were.
  final void Function(int row)? onScrolled;

  @override
  State<EditorSurface> createState() => EditorSurfaceState();
}

class EditorSurfaceState extends State<EditorSurface>
    implements TextInputClient {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();

  /// Only a node we made is a node we may dispose.
  bool get _ownsFocusNode => widget.focusNode == null;

  final ScrollController _scroll = ScrollController();

  /// Caret notifications must not pull the viewport back to row zero while the
  /// first layout is still waiting to apply the parked position.
  bool _initialScrollPending = true;
  bool _initialScrollScheduled = false;

  TextInputConnection? _connection;

  double _viewportWidth = 900;
  double _viewportHeight = 600;

  /// Where the grid lands in the viewport, as of right now.
  ///
  /// Built rather than cached, so that no call site can work from a row-to-pixel
  /// mapping that a re-wrap or a fresh pagination has already invalidated. It is
  /// a handful of field reads and one cached list.
  EditorGeometry get _geometry => EditorGeometry(
    metrics: _metrics,
    viewportWidth: _viewportWidth,
    totalRows: _controller.layout.totalRows,
    pageStarts: widget.pageIndicator?.pageStarts ?? const [],
    pageView: widget.pageView,
  );

  /// The composing region the platform is holding, in offsets into the focused
  /// block. Painted with an underline; never interpreted.
  TextRange _composing = TextRange.empty;

  /// The block the platform's editing session is for.
  ///
  /// ADR 0005 hands the platform one block at a time, which is correct for every
  /// composition except one that would span a block boundary. This is what closes
  /// that gap: a session belongs to a block, and when the caret leaves that block
  /// the session ends and a new one begins. A composing region can then never
  /// describe a range in text the platform is no longer looking at.
  int? _sessionBlock;

  EditorController get _controller => widget.controller;

  /// The grid, as of the viewport this surface was last laid out into.
  ///
  /// Derived rather than measured and rather than cached: the text-size
  /// preference is the size the writer asked for, and what comes back is that
  /// size or the largest one whose page fits across the window, so the script
  /// gets smaller when the window does instead of running off the edge of a
  /// column that has been clamped out from under it.
  ScreenplayMetrics get _metrics => ScreenplayMetrics.forFontSize(_fontSize);

  double get _fontSize => ScreenplayMetrics.fittedFontSize(
    preferredFontSize: widget.textSize.clamp(12, 24).toDouble(),
    viewportWidth: _viewportWidth,
    pageView: widget.pageView,
  );

  double get _advance => _metrics.advance;
  double get _lineHeight => _metrics.lineHeight;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onDocumentChanged);
    _focusNode.addListener(_onFocusChanged);
    _scroll.addListener(_refreshSemantics);
    _scroll.addListener(_reportScroll);
    _scheduleInitialScroll();
  }

  @override
  void didUpdateWidget(EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textSize != widget.textSize) {
      _reportedRow = -1;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDocumentChanged);
      widget.controller.addListener(_onDocumentChanged);
      _reportedRow = -1;
      _initialScrollPending = true;
      _scheduleInitialScroll();
    }
  }

  @override
  void dispose() {
    _connection?.close();
    _controller.removeListener(_onDocumentChanged);
    _focusNode.removeListener(_onFocusChanged);
    _scroll.removeListener(_refreshSemantics);
    _scroll.removeListener(_reportScroll);
    if (_ownsFocusNode) _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onDocumentChanged() {
    _syncEditingState();
    _ensureCaretVisible();
    _refreshSemantics();
  }

  void _scheduleInitialScroll() {
    if (_initialScrollScheduled) return;
    _initialScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialScrollScheduled = false;
      if (!mounted || !_initialScrollPending) return;
      if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
        _scheduleInitialScroll();
        return;
      }

      final row = math.max(0, widget.initialScrollRow);
      final target = row == 0 ? 0.0 : _geometry.yOfRow(row);
      _initialScrollPending = false;
      _scroll.jumpTo(
        target.clamp(0.0, math.max(0.0, _scroll.position.maxScrollExtent)),
      );
      // `jumpTo(0)` sends no notification. Report explicitly so a stale row
      // from a file that became shorter is replaced by its clamped value.
      _reportScroll();
    });
  }

  /// Whether a rebuild is already queued for the semantics band.
  bool _semanticsRefreshQueued = false;

  /// Rebuilds so that the semantics nodes describe the current document and the
  /// current visible band.
  ///
  /// Painting does not need this — the painter repaints from a `Listenable` and
  /// never rebuilds — so with no assistive technology attached the surface still
  /// builds its widget tree once per layout and no more. When something *is*
  /// attached, an edit or a scroll has to reach the semantics tree, and the only
  /// way for a widget to change what it put there is to build again.
  ///
  /// Deferred to after the frame because both callers can fire mid-layout: a
  /// `ScrollPosition` notifies its listeners from inside `setPixels`.
  void _refreshSemantics() {
    if (!SemanticsBinding.instance.semanticsEnabled) return;
    if (_semanticsRefreshQueued) return;
    _semanticsRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _semanticsRefreshQueued = false;
      if (mounted) setState(() {});
    });
  }

  /// The last row reported upward, so that a scroll of half a line is not a
  /// call across the bridge.
  int _reportedRow = -1;

  void _reportScroll() {
    if (widget.onScrolled == null || !_scroll.hasClients) return;
    final row = _geometry.rowAtY(_scroll.offset).clamp(0, 1 << 30);
    if (row == _reportedRow) return;
    _reportedRow = row;
    widget.onScrolled!(row);
  }

  /// Tells the page above when a composition starts or ends.
  void _reportComposing() {
    final composing = _composing.isValid && !_composing.isCollapsed;
    if (composing == _reportedComposing) return;
    _reportedComposing = composing;
    widget.onComposingChanged?.call(composing);
  }

  bool _reportedComposing = false;

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _attachInput();
    } else {
      _connection?.close();
      _connection = null;
      _composing = TextRange.empty;
      _sessionBlock = null;
      _reportComposing();
    }
    setState(() {});
  }

  // --- platform text input -------------------------------------------------

  void _attachInput() {
    if (_connection?.attached ?? false) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        // The core decides what a screenplay line means; the platform must not
        // capitalise, correct or suggest anything on its own (§9's "no code
        // path modifies text without an explicit user action", early).
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      ),
    )..show();
    _syncEditingState();
  }

  /// What the platform is told the document is.
  ///
  /// One block at a time. That is the simple half of the IME contract and it is
  /// correct for everything except a composition that spans a block boundary,
  /// which ADR 0005 records as Phase 3 work.
  TextEditingValue get _editingValue {
    final block = _controller.focusedBlock;
    final selection = _controller.selection;
    final withinOneBlock = selection.anchor.block == selection.focus.block;
    return TextEditingValue(
      text: block.text,
      selection: withinOneBlock
          ? TextSelection(
              baseOffset: selection.anchor.offsetUtf16,
              extentOffset: selection.focus.offsetUtf16,
            )
          : TextSelection.collapsed(offset: selection.focus.offsetUtf16),
      composing: _composing.isValid && _composing.end <= block.text.length
          ? _composing
          : TextRange.empty,
    );
  }

  /// Tells the platform what the document is, ending the previous session first
  /// if the caret has moved to a different block.
  ///
  /// Ending it means dropping the composing region. That is not a lost keystroke:
  /// composed text reaches us as ordinary text in `updateEditingValue` and is
  /// already in the document by the time the region changes — what is dropped is
  /// only the platform's claim that some of it is still provisional. Keeping that
  /// claim across a block boundary is what would lose text, because the offsets in
  /// it would then describe a range in a block the platform cannot see.
  void _syncEditingState() {
    final block = _controller.focusedBlock.id;
    if (_sessionBlock != block) {
      _sessionBlock = block;
      if (_composing.isValid) {
        _composing = TextRange.empty;
        _reportComposing();
        // The underline goes with it.
        if (mounted) setState(() {});
      }
    }
    _connection?.setEditingState(_editingValue);
  }

  @override
  TextEditingValue get currentTextEditingValue => _editingValue;

  @override
  void updateEditingValue(TextEditingValue value) {
    final previous = _editingValue;
    _composing = value.composing;
    _reportComposing();
    if (value.text == previous.text) {
      // Selection-only news — a composition being confirmed, or the platform
      // moving its own caret. The model's caret is ours, so only repaint.
      setState(() {});
      return;
    }

    // What the platform changed, as the smallest range that explains it. A
    // minimal range is not just tidy: the core coalesces consecutive insertions
    // into one undo step only when they are insertions (§3.4).
    final (start, oldEnd, inserted) = _diff(previous.text, value.text);
    final block = _controller.focusedBlock.id;
    _controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: block, offsetUtf16: start),
        focus: DocPosition(block: block, offsetUtf16: oldEnd),
      ),
    );

    // A newline can only arrive here if the platform's IM produced one rather
    // than the key reaching our handler. Split, so that the block structure is
    // still the core's and not a `\n` smuggled into a block's text.
    final parts = inserted.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) _controller.splitBlock();
      if (parts[i].isNotEmpty) _controller.insertText(parts[i]);
    }
    if (inserted.isEmpty) _controller.deleteSelection();
  }

  /// The common prefix and suffix of two strings, as `(start, oldEnd, inserted)`.
  static (int, int, String) _diff(String before, String after) {
    var start = 0;
    final shortest = math.min(before.length, after.length);
    while (start < shortest &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    var tail = 0;
    while (tail < shortest - start &&
        before.codeUnitAt(before.length - tail - 1) ==
            after.codeUnitAt(after.length - tail - 1)) {
      tail++;
    }
    return (
      start,
      before.length - tail,
      after.substring(start, after.length - tail),
    );
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) _controller.splitBlock();
  }

  @override
  void connectionClosed() => _connection = null;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void didChangeInputControl(
    TextInputControl? old,
    TextInputControl? current,
  ) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  bool onFocusReceived() => true;

  // --- keyboard ------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final control = keys.isControlPressed;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp when _controller.completions.isNotEmpty:
        _controller.moveCompletion(-1);
      case LogicalKeyboardKey.arrowDown when _controller.completions.isNotEmpty:
        _controller.moveCompletion(1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when _controller.completions.isNotEmpty &&
              _controller.completionWasNavigated:
        _controller.acceptCompletion();
      case LogicalKeyboardKey.tab
          when !shift && _controller.completions.isNotEmpty:
        _controller.acceptCompletion();
      case LogicalKeyboardKey.arrowLeft when control:
        _controller.moveByWord(-1, extend: shift);
      case LogicalKeyboardKey.arrowRight when control:
        _controller.moveByWord(1, extend: shift);
      case LogicalKeyboardKey.arrowLeft:
        _controller.moveHorizontal(-1, extend: shift);
      case LogicalKeyboardKey.arrowRight:
        _controller.moveHorizontal(1, extend: shift);
      case LogicalKeyboardKey.arrowUp:
        _controller.moveVertical(-1, extend: shift);
      case LogicalKeyboardKey.arrowDown:
        _controller.moveVertical(1, extend: shift);
      case LogicalKeyboardKey.pageUp:
        _controller.moveVertical(-_rowsPerPage, extend: shift);
      case LogicalKeyboardKey.pageDown:
        _controller.moveVertical(_rowsPerPage, extend: shift);
      case LogicalKeyboardKey.home:
        if (control) {
          _controller.moveToDocumentEdge(start: true, extend: shift);
        } else {
          _controller.moveToLineEdge(start: true, extend: shift);
        }
      case LogicalKeyboardKey.end:
        if (control) {
          _controller.moveToDocumentEdge(start: false, extend: shift);
        } else {
          _controller.moveToLineEdge(start: false, extend: shift);
        }
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _controller.splitBlock();
      case LogicalKeyboardKey.backspace when control:
        _controller.deleteWord(forward: false);
      case LogicalKeyboardKey.delete when control:
        _controller.deleteWord(forward: true);
      case LogicalKeyboardKey.backspace:
        _controller.deleteBackward();
      case LogicalKeyboardKey.delete:
        _controller.deleteForward();
      case LogicalKeyboardKey.keyA when control:
        _controller.selectAll();
      case LogicalKeyboardKey.keyC when control:
        _controller.copy();
      case LogicalKeyboardKey.keyX when control:
        _controller.cut();
      case LogicalKeyboardKey.keyV when control:
        _controller.paste(plain: shift);
      case LogicalKeyboardKey.keyZ when control && shift:
        _controller.redo();
      case LogicalKeyboardKey.keyZ when control:
        _controller.undo();
      case LogicalKeyboardKey.keyY when control:
        _controller.redo();
      // Tab is the element cycle of `docs/KEYMAP.md`, and Shift+Tab reverses it.
      // It never moves the focus out of the document — there is nowhere in a
      // script for the focus to go.
      case LogicalKeyboardKey.tab:
        _controller.cycleElement(reverse: shift);
      case LogicalKeyboardKey.keyK when control:
        widget.onOpenPalette?.call();
      case LogicalKeyboardKey.keyF when control:
        widget.onOpenFind?.call();
      case LogicalKeyboardKey.keyG when control && shift:
        _controller.previousMatch();
      case LogicalKeyboardKey.keyG when control:
        _controller.nextMatch();
      // Escape changes nothing. It dismisses whatever is open, and when nothing
      // is, it collapses the selection — never a deletion, never a command.
      case LogicalKeyboardKey.escape:
        if (_controller.completions.isNotEmpty) {
          _controller.dismissCompletions(suppressHighlighted: true);
          return KeyEventResult.handled;
        }
        widget.onEscape?.call();
        _controller.collapseSelection();
      // The element shortcuts. `Ctrl+<digit>` sets the type and pins it, which
      // is also how a writer overrules an automatic change (§Phase 3).
      case final key when control && elementShortcuts.containsKey(key):
        final choice = elementShortcuts[key]!;
        _controller.setKind(choice.kind, sectionLevel: choice.sectionLevel);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int get _rowsPerPage =>
      math.max(1, (_viewportHeight / _lineHeight).floor() - 2);

  // --- pointer -------------------------------------------------------------

  /// When and where the last click landed, for counting double and triple
  /// clicks. `Listener` reports pointers, not gestures, so the count is ours to
  /// keep — and a `GestureDetector` would not do better: it has no triple tap.
  Duration _lastClickAt = Duration.zero;
  Offset _lastClickPosition = Offset.zero;
  int _clickCount = 0;

  /// The platform's own double-click window, and how far the pointer may drift
  /// between clicks and still be the same click.
  static const Duration _multiClickWindow = Duration(milliseconds: 400);
  static const double _multiClickSlop = 8;

  /// Whether the current pointer sequence belongs to the scrollbar.
  ///
  /// A scrollbar paints in front of its child, but its foreground painter and
  /// the child are both on the pointer hit-test path. Without this ownership
  /// check a thumb drag is also interpreted as a selection drag, and keeping
  /// that accidental caret visible pulls the viewport back under the thumb.
  bool _scrollbarPointerActive = false;

  bool _isInScrollbarGutter(Offset local) {
    // Flutter expands a touch thumb to its minimum interactive size around the
    // painted track, so reserve that whole edge band for the scrollbar.
    const gutter = kMinInteractiveDimension;
    return switch (Directionality.of(context)) {
      TextDirection.ltr => local.dx >= _viewportWidth - gutter,
      TextDirection.rtl => local.dx <= gutter,
    };
  }

  void _onPointerDown(PointerDownEvent event) {
    _scrollbarPointerActive = _isInScrollbarGutter(event.localPosition);
    if (_scrollbarPointerActive) return;
    if (event.buttons & kSecondaryButton != 0) {
      unawaited(_showSpellingMenu(event));
      return;
    }
    if (event.buttons & kPrimaryButton == 0) return;
    _focusNode.requestFocus();
    final (row, column) = _gridAt(event.localPosition);
    final shift = HardwareKeyboard.instance.isShiftPressed;

    final quick =
        event.timeStamp - _lastClickAt < _multiClickWindow &&
        (event.localPosition - _lastClickPosition).distance < _multiClickSlop;
    _clickCount = quick ? _clickCount + 1 : 1;
    _lastClickAt = event.timeStamp;
    _lastClickPosition = event.localPosition;

    // Shift-clicking is always extending a selection, whatever the count.
    if (shift) {
      _controller.placeCaretAt(row, column, extend: true);
      return;
    }
    switch (_clickCount) {
      case 1:
        _controller.placeCaretAt(row, column);
      case 2:
        _controller.selectWordAt(row, column);
      default:
        _controller.selectBlockAt(row, column);
    }
  }

  Future<void> _showSpellingMenu(PointerDownEvent event) async {
    final geometry = _geometry;
    if (event.localPosition.dx < geometry.columnLeft ||
        event.localPosition.dx > geometry.columnRight) {
      return;
    }
    final (row, column) = _gridAt(event.localPosition);
    final misspelling = _controller.misspellingAt(
      _controller.positionAt(row, column),
    );
    if (misspelling == null) return;
    final suggestions = await _controller.suggestionsFor(misspelling);
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_SpellMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(event.position, event.position),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final suggestion in suggestions)
          PopupMenuItem(
            value: _SpellReplacement(suggestion),
            child: Text(suggestion),
          ),
        if (suggestions.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: _SpellReplace(), child: Text('Replace…')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _SpellIgnoreOnce(),
          child: Text('Ignore Once'),
        ),
        const PopupMenuItem(
          value: _SpellIgnoreAll(),
          child: Text('Ignore All'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _SpellAddPersonal(),
          child: Text('Add to Personal Dictionary'),
        ),
        const PopupMenuItem(
          value: _SpellAddProject(),
          child: Text('Add to Project Dictionary'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SpellReplacement(:final word):
        _controller.replaceMisspelling(misspelling, word);
      case _SpellReplace():
        final replacement = await _replacementFor(misspelling.word);
        if (replacement != null && replacement != misspelling.word) {
          _controller.replaceMisspelling(misspelling, replacement);
        }
      case _SpellIgnoreOnce():
        _reportSpellAction(_controller.ignoreMisspellingOnce(misspelling));
      case _SpellIgnoreAll():
        _reportSpellAction(_controller.ignoreMisspellingAll(misspelling));
      case _SpellAddPersonal():
        _reportSpellAction(
          await _controller.addToPersonalDictionary(misspelling),
        );
      case _SpellAddProject():
        _reportSpellAction(
          await _controller.addToProjectDictionary(misspelling),
        );
    }
  }

  Future<String?> _replacementFor(String word) async {
    final input = TextEditingController(text: word);
    final replacement = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace misspelling'),
        content: TextField(
          key: const ValueKey('spell replacement'),
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Replacement'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    input.dispose();
    return replacement;
  }

  void _reportSpellAction(SpellActionResult result) {
    if (!mounted) return;
    final message = switch (result) {
      SpellActionResult_Applied() => null,
      SpellActionResult_NoScriptPath() =>
        'Save the script before adding a project word.',
      SpellActionResult_NoSuchDocument() => 'The script is no longer open.',
      SpellActionResult_Failed(:final message) => message,
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_scrollbarPointerActive) return;
    if (event.buttons & kPrimaryButton == 0) return;
    // A drag is a fresh selection, not a continuation of the click count.
    _clickCount = 1;
    final (row, column) = _gridAt(event.localPosition);
    _controller.placeCaretAt(row, column, extend: true);
    _autoScroll(event.localPosition);
  }

  void _onPointerEnd(PointerEvent event) {
    _scrollbarPointerActive = false;
  }

  /// Scrolls while a drag is held against the top or bottom edge.
  ///
  /// One row per move event rather than a timer: the pointer keeps sending them
  /// while it is held, and a timer would be a wakeup in an idle process (§1.3).
  void _autoScroll(Offset local) {
    if (!_scroll.hasClients) return;
    final edge = 2 * _lineHeight;
    final height = _scroll.position.viewportDimension;
    final delta = switch (local.dy) {
      final y when y < edge => -_lineHeight,
      final y when y > height - edge => _lineHeight,
      _ => 0.0,
    };
    if (delta == 0) return;
    _scroll.jumpTo(
      (_scroll.offset + delta).clamp(
        0.0,
        math.max(0.0, _scroll.position.maxScrollExtent),
      ),
    );
  }

  /// The grid cell under a point in the viewport.
  (int, int) _gridAt(Offset local) {
    final scrolled = _scroll.hasClients ? _scroll.offset : 0.0;
    final geometry = _geometry;
    final row = geometry.rowAtY(local.dy + scrolled);
    final column = ((local.dx - geometry.columnLeft) / _advance).round();
    return (
      row.clamp(0, math.max(0, _controller.layout.totalRows - 1)),
      math.max(0, column),
    );
  }

  // --- scrolling -----------------------------------------------------------

  /// Keeps the caret on screen with a few rows of air around it.
  void _ensureCaretVisible() {
    if (_initialScrollPending || !_scroll.hasClients) return;
    final margin = 3 * _lineHeight;
    final caretTop = _geometry.yOfRow(_controller.caretRow);
    final caretBottom = caretTop + _lineHeight;
    final top = _scroll.offset;
    final bottom = top + _scroll.position.viewportDimension;

    double? target;
    if (caretTop - margin < top) {
      target = caretTop - margin;
    } else if (caretBottom + margin > bottom) {
      target = caretBottom + margin - _scroll.position.viewportDimension;
    }
    if (target == null) return;
    _scroll.jumpTo(
      target.clamp(0.0, math.max(0.0, _scroll.position.maxScrollExtent)),
    );
  }

  // --- accessibility -------------------------------------------------------

  /// A semantics node over each block in the visible band.
  ///
  /// The painter paints a band and nothing else, and this describes the same
  /// band for the same reason: a 120-page script is some three thousand blocks,
  /// and a semantics tree with three thousand nodes in it is a tree no screen
  /// reader wants and no frame budget affords. Scrolling rebuilds it —
  /// [_refreshSemantics] — so what the tree holds is what is on screen, which is
  /// also what a screen reader's own scroll actions move through.
  ///
  /// Empty when nothing is listening, which is the ordinary case.
  List<Widget> _blockSemantics() {
    if (!SemanticsBinding.instance.semanticsEnabled) return const [];

    final layout = _controller.layout;
    final blocks = _controller.blocks;
    final geometry = _geometry;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final (first: firstRow, last: lastRow) = geometry.rowBand(
      offset,
      offset + _viewportHeight,
    );
    if (lastRow <= firstRow || blocks.isEmpty) return const [];

    final selection = _controller.selection;
    final nodes = <Widget>[];
    for (
      var index = layout.blockAtRow(firstRow);
      index < blocks.length;
      index++
    ) {
      if (layout.firstRowOf(index) > lastRow) break;
      final block = blocks[index];
      final focused = block.id == selection.focus.block;
      final withinOneBlock = selection.anchor.block == selection.focus.block;
      nodes.add(
        Positioned(
          left: geometry.columnLeft,
          top: geometry.yOfRow(layout.firstRowOf(index)),
          width: geometry.columnWidth,
          height: math.max(
            _lineHeight,
            layout.linesOf(index).length * _lineHeight,
          ),
          child: ScriptBlockSemantics(
            key: ValueKey(block.id),
            label: kindLabel(block.kind, block.sectionLevel),
            value: displayText(block.kind, block.text),
            focused: focused,
            selection: withinOneBlock
                ? TextSelection(
                    baseOffset: selection.anchor.offsetUtf16,
                    extentOffset: selection.focus.offsetUtf16,
                  )
                : TextSelection.collapsed(offset: selection.focus.offsetUtf16),
            readOnly: block.readOnly,
            onFocusRequested: () => _placeCaretIn(block),
            onSetSelection: (value) => _controller.setSelection(
              DocSelection(
                anchor: DocPosition(
                  block: block.id,
                  offsetUtf16: value.baseOffset,
                ),
                focus: DocPosition(
                  block: block.id,
                  offsetUtf16: value.extentOffset,
                ),
              ),
            ),
            onSetText: (text) => _replaceBlockText(block, text),
            onMoveCursorByCharacter: (delta, extend) =>
                _controller.moveHorizontal(delta, extend: extend),
            onMoveCursorByWord: (delta, extend) =>
                _controller.moveByWord(delta, extend: extend),
            onCopy: () => unawaited(_controller.copy()),
            onCut: () => unawaited(_controller.cut()),
            onPaste: () => unawaited(_controller.paste()),
          ),
        ),
      );
    }
    return nodes;
  }

  /// Moves the caret into [block] without disturbing its text.
  ///
  /// This is what a screen reader's own navigation does when it lands on a
  /// paragraph, so it must be a caret move and nothing more. Focusing the
  /// surface as well is deliberate: the writer who arrived here by swiping
  /// expects the next key they press to type into this block.
  void _placeCaretIn(BlockView block) {
    _focusNode.requestFocus();
    final at = DocPosition(block: block.id, offsetUtf16: 0);
    _controller.setSelection(DocSelection(anchor: at, focus: at));
  }

  /// The `SetText` action: replace one block's text wholesale.
  ///
  /// Expressed as a selection plus an insertion rather than a command of its
  /// own, so that it takes exactly the path a paste takes — one undo step, and
  /// the same re-inference afterwards. An accessibility action must not be a
  /// second way into the document.
  void _replaceBlockText(BlockView block, String text) {
    _controller.setSelection(
      DocSelection(
        anchor: DocPosition(block: block.id, offsetUtf16: 0),
        focus: DocPosition(block: block.id, offsetUtf16: block.text.length),
      ),
    );
    if (text.isEmpty) {
      _controller.deleteSelection();
    } else {
      _controller.insertText(text);
    }
  }

  // --- building ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        _viewportHeight = constraints.maxHeight;
        final geometry = _geometry;

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: Scrollbar(
            controller: _scroll,
            interactive: true,
            thumbVisibility: true,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: math.max(
                    geometry.contentHeight,
                    constraints.maxHeight,
                  ),
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          key: const ValueKey('editor paint'),
                          child: CustomPaint(
                            painter: _SurfacePainter(
                              controller: _controller,
                              scroll: _scroll,
                              pageIndicator: widget.pageIndicator,
                              geometry: geometry,
                              showCaret: _focusNode.hasFocus,
                              composing: _composing,
                              colours: _EditorColours.of(context),
                              fontSize: _fontSize,
                            ),
                          ),
                        ),
                      ),
                      ..._blockSemantics(),
                      if (_controller.completions.isNotEmpty)
                        Positioned(
                          left: geometry.columnLeft,
                          top: geometry.yOfRow(_controller.caretRow + 1),
                          child: _CompletionPopup(
                            controller: _controller,
                            textSize: _fontSize,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The candidate list, and the gestures that accept or dismiss one.
///
/// The footer is not decoration. Tab is the only thing that takes the default
/// candidate (ADR 0017), and nothing on screen said so: the Phase 9 pass reached
/// for Enter and for the mouse, got a block split and nothing at all, and
/// reported autocomplete as broken. Naming the gestures is the repair (ADR 0030).
///
/// The rows are deliberately **not** click targets. See ADR 0030: the popup
/// floats over the writer's own text, so a click there is as likely to be aimed
/// at the page as at a candidate, and the version of it that guesses wrong
/// writes a scene prefix into the script.
class _CompletionPopup extends StatelessWidget {
  const _CompletionPopup({required this.controller, required this.textSize});

  final EditorController controller;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('completion-popup'),
      elevation: 6,
      color: colours.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, candidate)
                in controller.completions.take(8).indexed)
              Container(
                key: ValueKey('completion-${candidate.value}'),
                color: index == controller.completionIndex
                    ? colours.primaryContainer
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        candidate.value,
                        style: _textStyle(textSize).copyWith(
                          color: index == controller.completionIndex
                              ? colours.onPrimaryContainer
                              : colours.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('pin-${candidate.value}'),
                      visualDensity: VisualDensity.compact,
                      tooltip: candidate.pinned
                          ? 'Unpin suggestion'
                          : 'Pin suggestion',
                      onPressed: () =>
                          controller.toggleCompletionPin(candidate),
                      icon: Icon(
                        candidate.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              key: const ValueKey('completion-hint'),
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              // The candidates above are script — they are the writer's own
              // text — but the gestures are the application talking, so the
              // footer is chrome and stays the chrome's size whatever the
              // script is set at.
              child: Text(
                'Tab accepts · ↑↓ then Enter · Esc dismisses',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colours.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The script, in the face the PDF prints it in.
///
/// No `fontFamilyFallback`: the face is bundled, so there is nothing to fall
/// back to and nothing that would silently change the advance the grid is
/// derived from ([ScreenplayMetrics.advanceRatio]).
TextStyle _textStyle(double fontSize) => TextStyle(
  fontFamily: scriptFontFamily,
  fontSize: fontSize,
  height: 1.0,
);

class _EditorColours {
  const _EditorColours({
    required this.text,
    required this.dim,
    required this.selection,
    required this.caret,
    required this.rule,
    required this.spelling,
    required this.paper,
    required this.paperEdge,
    required this.pageBreak,
    required this.gutter,
  });

  factory _EditorColours.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _EditorColours(
      text: scheme.onSurface,
      dim: scheme.onSurface.withValues(alpha: 0.55),
      selection: scheme.primary.withValues(alpha: 0.30),
      caret: scheme.primary,
      rule: scheme.onSurface.withValues(alpha: 0.25),
      spelling: scheme.error,
      // The sheet is the surface a script is read on, so it is lifted out of the
      // background rather than tinted: paper white in a light theme, and one
      // step up from the background in a dark one, which is what the container
      // roles already mean.
      paper: scheme.surfaceContainerLowest,
      paperEdge: scheme.shadow.withValues(alpha: 0.18),
      // A page break is information, not decoration. It has to be findable at a
      // glance and invisible while reading, which is what a hairline this faint
      // buys.
      pageBreak: scheme.outlineVariant,
      gutter: scheme.onSurface.withValues(alpha: 0.40),
    );
  }

  final Color text;
  final Color dim;
  final Color selection;
  final Color caret;
  final Color rule;
  final Color spelling;
  final Color paper;
  final Color paperEdge;
  final Color pageBreak;
  final Color gutter;
}

/// Paints the rows that are on screen, and nothing else.
class _SurfacePainter extends CustomPainter {
  _SurfacePainter({
    required this.controller,
    required this.scroll,
    required this.pageIndicator,
    required this.geometry,
    required this.showCaret,
    required this.composing,
    required this.colours,
    required this.fontSize,
  }) : super(
         repaint: Listenable.merge([
           controller,
           scroll,
           // A fresh pagination moves every rule and every sheet below it.
           ?pageIndicator,
         ]),
       );

  final EditorController controller;
  final ScrollController scroll;
  final PageIndicator? pageIndicator;
  final EditorGeometry geometry;
  final bool showCaret;
  final TextRange composing;
  final _EditorColours colours;
  final double fontSize;

  double get advance => geometry.advance;
  double get lineHeight => geometry.lineHeight;
  double get pageLeft => geometry.columnLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = controller.layout;
    final blocks = controller.blocks;
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final viewport = scroll.hasClients
        ? scroll.position.viewportDimension
        : size.height;

    // The whole performance story: the band, not the document.
    final (first: firstRow, last: lastRow) = geometry.rowBand(
      offset,
      offset + viewport,
    );
    if (lastRow <= firstRow) return;

    // Under the text, and clipped to the same band for the same reason.
    _paintPageFurniture(canvas, offset, offset + viewport);

    final (from, to) = controller.orderedSelection;
    final fromIndex = blocks.indexWhere((block) => block.id == from.block);
    final toIndex = blocks.indexWhere((block) => block.id == to.block);
    final hasSelection = controller.hasSelection;

    final selectionPaint = Paint()..color = colours.selection;
    final rulePaint = Paint()
      ..color = colours.rule
      ..strokeWidth = 1.0;

    for (
      var index = layout.blockAtRow(firstRow);
      index < blocks.length;
      index++
    ) {
      if (layout.firstRowOf(index) > lastRow) break;
      final block = blocks[index];
      final lines = layout.linesOf(index);
      final first = layout.firstRowOf(index);
      // Capitalised once for the block, not once per row: the rule is per
      // scalar and never moves an offset, so a row still slices this string by
      // its own model bounds.
      final display = displayText(block.kind, block.text);

      if (block.kind == BlockKind.pageBreak) {
        final y = geometry.yOfRow(first) + lineHeight / 2;
        canvas.drawLine(
          Offset(pageLeft, y),
          Offset(geometry.columnRight, y),
          rulePaint,
        );
        continue;
      }

      for (var i = 0; i < lines.length; i++) {
        final row = first + i;
        if (row < firstRow || row > lastRow) continue;
        final line = lines[i];
        final column = layout.columnOf(index, i);
        final x = pageLeft + column * advance;
        final y = geometry.yOfRow(row);

        if (hasSelection) {
          _paintSelection(
            canvas,
            selectionPaint,
            index,
            i,
            line,
            x,
            y,
            fromIndex,
            from,
            toIndex,
            to,
          );
        }

        if (line.columns > 0) {
          final text = line.textIn(display);
          TextPainter(
              text: TextSpan(
                text: text,
                style: _textStyle(fontSize).copyWith(
                  color: _isMuted(block.kind) ? colours.dim : colours.text,
                  fontStyle: _isMuted(block.kind) ? FontStyle.italic : null,
                ),
              ),
              textDirection: TextDirection.ltr,
            )
            ..layout()
            ..paint(canvas, Offset(x, y + (lineHeight - fontSize) / 2));
        }

        _paintSpellingUnderlines(canvas, block.id, line, x, y);

        if (composing.isValid && block.id == controller.selection.focus.block) {
          _paintComposingUnderline(canvas, line, column, y);
        }
      }
    }

    if (showCaret) _paintCaret(canvas);
  }

  /// The sheets, or the rules that stand in for them.
  ///
  /// Neither is computed here. `pageStarts` is Rust's pagination re-expressed in
  /// editor rows, and both branches below are ways of drawing the same list. If
  /// it is empty — nothing paginated yet, or a test with no core behind it —
  /// this draws nothing at all, and the surface is the plain centred column it
  /// has always been.
  void _paintPageFurniture(Canvas canvas, double top, double bottom) {
    if (geometry.sheeted) {
      _paintSheets(canvas, top, bottom);
    } else {
      _paintPageRules(canvas, top, bottom);
    }
  }

  void _paintSheets(Canvas canvas, double top, double bottom) {
    final paper = Paint()..color = colours.paper;
    final edge = Paint()
      ..color = colours.paperEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final radius = Radius.circular(advance);

    for (final sheet in geometry.sheets()) {
      if (sheet.bottom < top) continue;
      if (sheet.top > bottom) break;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          geometry.sheetLeft,
          sheet.top,
          geometry.sheetLeft + geometry.sheetWidth,
          sheet.bottom,
        ),
        radius,
      );
      canvas
        ..drawRRect(rect, paper)
        ..drawRRect(rect, edge);
      _paintPageNumber(canvas, sheet.number, sheet.top);
    }
  }

  /// §5.2 puts the page number half an inch above the text, right-aligned to the
  /// measure's right edge. A sheet has the room for it, so it goes where it will
  /// go on paper.
  void _paintPageNumber(Canvas canvas, int number, double sheetTop) {
    final label = _label('$number.', colours.gutter);
    label.paint(
      canvas,
      Offset(
        geometry.columnRight - label.width,
        sheetTop +
            geometry.metrics.down(1) +
            ScreenplayMetrics.pageNumberRow * lineHeight,
      ),
    );
  }

  /// Continuous view: a hairline where the page turns, and its number set in the
  /// gutter beside it.
  ///
  /// The rule stops short of the text column on both sides so that it reads as
  /// furniture rather than as a horizontal line in the script — a scripted page
  /// break paints a rule of its own across the full measure, and the two must
  /// not be mistakable for each other.
  void _paintPageRules(Canvas canvas, double top, double bottom) {
    final line = Paint()
      ..color = colours.pageBreak
      ..strokeWidth = 1.0;
    final inset = geometry.metrics.across(0.2);

    for (final rule in geometry.rules()) {
      if (rule.y < top) continue;
      if (rule.y > bottom) break;
      canvas.drawLine(
        Offset(pageLeft + inset, rule.y),
        Offset(geometry.columnRight - inset, rule.y),
        line,
      );
      final label = _label('${rule.number}', colours.gutter);
      // In the gutter: left of the column, right-aligned against it, so the
      // numbers form a column of their own down the edge of the script. A
      // window too narrow to hold one gets the rule and no number rather than a
      // number over the text.
      final labelLeft = pageLeft - inset - label.width;
      if (labelLeft >= 0) {
        label.paint(canvas, Offset(labelLeft, rule.y - label.height / 2));
      }
    }
  }

  /// A page number down the gutter. Chrome, not script: it is the application
  /// counting pages, so it is set in the chrome's sans at the chrome's size and
  /// does not grow with the text-size preference the way the script does.
  TextPainter _label(String text, Color colour) => TextPainter(
    text: TextSpan(text: text, style: chromeLabelStyle(colour)),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintSpellingUnderlines(
    Canvas canvas,
    int block,
    VisualLine line,
    double x,
    double y,
  ) {
    for (final misspelling in controller.misspellingsFor(block)) {
      final start = math.max(misspelling.startUtf16, line.start);
      final end = math.min(misspelling.endUtf16, line.end);
      if (end <= start) continue;
      final from = x + line.columnAtOffset(start) * advance;
      final to = x + line.columnAtOffset(end) * advance;
      final baseline = y + lineHeight - 1.5;
      final path = Path()..moveTo(from, baseline);
      var cursor = from;
      var up = true;
      while (cursor < to) {
        cursor = math.min(to, cursor + 2.0);
        path.lineTo(cursor, baseline + (up ? -1.5 : 1.5));
        up = !up;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colours.spelling
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  /// Sections, synopses, notes and boneyard never reach the page (§5.2). Showing
  /// them dimmed says so without hiding them.
  bool _isMuted(BlockKind kind) => switch (kind) {
    BlockKind.section ||
    BlockKind.synopsis ||
    BlockKind.note ||
    BlockKind.opaque => true,
    _ => false,
  };

  void _paintSelection(
    Canvas canvas,
    Paint paint,
    int index,
    int lineIndex,
    VisualLine line,
    double x,
    double y,
    int fromIndex,
    DocPosition from,
    int toIndex,
    DocPosition to,
  ) {
    if (index < fromIndex || index > toIndex) return;
    final selectionStart = index == fromIndex ? from.offsetUtf16 : 0;
    final selectionEnd = index == toIndex
        ? to.offsetUtf16
        : controller.blocks[index].text.length;
    final startOffset = math
        .max(selectionStart, line.start)
        .clamp(line.start, line.end);
    final endOffset = math
        .min(selectionEnd, line.end)
        .clamp(line.start, line.end);
    // Grid cells, not code units: an astral scalar is one cell of two units and
    // a tab is one unit of up to four cells.
    final startColumn = line.columnAtOffset(startOffset);
    final endColumn = line.columnAtOffset(endOffset);
    final textWidth = (endColumn - startColumn) * advance;
    if (textWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(x + startColumn * advance, y, textWidth, lineHeight),
        paint,
      );
    }

    final hardBreak = line.hardBreakOffsetUtf16;
    if (hardBreak != null &&
        selectionStart <= hardBreak &&
        selectionEnd > hardBreak) {
      // A newline has no printable column. A half-cell marker at the line end
      // makes its inclusion visible without shifting the next line's geometry.
      canvas.drawRect(
        Rect.fromLTWH(
          x + line.columnAtOffset(hardBreak) * advance,
          y,
          advance / 2,
          lineHeight,
        ),
        paint,
      );
    } else if (line.columns == 0 && index < toIndex) {
      // A selected empty block still needs a visible mark.
      canvas.drawRect(Rect.fromLTWH(x, y, advance / 2, lineHeight), paint);
    }
  }

  void _paintComposingUnderline(
    Canvas canvas,
    VisualLine line,
    int column,
    double y,
  ) {
    final start = math.max(composing.start, line.start);
    final end = math.min(composing.end, line.end);
    if (end <= start) return;
    final startColumn = line.columnAtOffset(start);
    final endColumn = line.columnAtOffset(end);
    final x = pageLeft + (column + startColumn) * advance;
    canvas.drawLine(
      Offset(x, y + lineHeight - 2),
      Offset(x + (endColumn - startColumn) * advance, y + lineHeight - 2),
      Paint()
        ..color = colours.text
        ..strokeWidth = 1.5,
    );
  }

  void _paintCaret(Canvas canvas) {
    final layout = controller.layout;
    final focus = controller.selection.focus;
    final index = controller.blocks.indexWhere(
      (block) => block.id == focus.block,
    );
    if (index < 0) return;
    final lineIndex = layout.lineIndexAt(index, focus.offsetUtf16);
    final line = layout.linesOf(index)[lineIndex];
    final column =
        layout.columnOf(index, lineIndex) +
        line.columnAtOffset(focus.offsetUtf16);
    // Static, not blinking. A blink is an animation loop and §1.3 asks for 0%
    // idle CPU.
    canvas.drawRect(
      Rect.fromLTWH(
        pageLeft + column * advance,
        geometry.yOfRow(layout.firstRowOf(index) + lineIndex),
        2.0,
        lineHeight,
      ),
      Paint()..color = colours.caret,
    );
  }

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.controller != controller ||
      old.geometry != geometry ||
      old.fontSize != fontSize ||
      old.showCaret != showCaret ||
      old.composing != composing;
}

sealed class _SpellMenuAction {
  const _SpellMenuAction();
}

class _SpellReplacement extends _SpellMenuAction {
  const _SpellReplacement(this.word);
  final String word;
}

class _SpellReplace extends _SpellMenuAction {
  const _SpellReplace();
}

class _SpellIgnoreOnce extends _SpellMenuAction {
  const _SpellIgnoreOnce();
}

class _SpellIgnoreAll extends _SpellMenuAction {
  const _SpellIgnoreAll();
}

class _SpellAddPersonal extends _SpellMenuAction {
  const _SpellAddPersonal();
}

class _SpellAddProject extends _SpellMenuAction {
  const _SpellAddProject();
}
