import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/theme.dart';

/// `Ctrl+F`: find, with a live match count, and replace.
///
/// The bar owns the two text fields and the three toggles; the controller owns
/// the match list and which one the caret is on, because moving the caret to a
/// match is a selection change and selections belong to the controller (§2.1).
/// While the bar is up the surface tints every match on screen; the page tells
/// it so, and the bar draws none of that.
/// Escape closes the bar and changes no text — that is §Phase 3's requirement and
/// the reason Escape is handled here rather than left to bubble.
class FindBar extends StatefulWidget {
  const FindBar({required this.controller, required this.onDismiss, super.key});

  final EditorController controller;
  final VoidCallback onDismiss;

  @override
  State<FindBar> createState() => FindBarState();
}

class FindBarState extends State<FindBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  bool _caseSensitive = false;
  bool _wholeWord = false;

  /// `null` is every element type. Otherwise the one the search is restricted
  /// to — §Phase 3's optional element filter.
  BlockKind? _only;

  /// Typing runs a full-document scan per keystroke on the UI thread, which
  /// janks a feature-length script. Keystrokes wait 150 ms for the next one;
  /// toggles, Enter and match navigation search at once (see [_searchNow]).
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _find.text = widget.controller.query.text;
    _caseSensitive = widget.controller.query.caseSensitive;
    _wholeWord = widget.controller.query.wholeWord;
    _only = widget.controller.query.kinds.firstOrNull;
    // The query above is already the one in force: the page ran
    // [EditorController.startFind] before putting the bar up, which is where
    // a selection becomes the search and the last search is resumed.
    //
    // After mount: requesting focus synchronously here is unreliable on
    // Linux/IME — the focus tree is not attached yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _offerQuery();
    });
  }

  /// Gives the find field the keyboard with its text selected: offered for
  /// replacement, not amendment. Only when Find is asked for — later typing
  /// and pointer/caret movement own the selection.
  void _offerQuery() {
    _findFocus.requestFocus();
    _find.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _find.text.length,
    );
  }

  /// `Ctrl+F` from the script with the bar already up: what opening does. A
  /// new selection becomes the search; otherwise the one in force stands,
  /// including anything typed that the debounce had not reached yet.
  void resume() {
    final before = widget.controller.query.text;
    widget.controller.startFind();
    final seeded = widget.controller.query.text;
    if (seeded != before) {
      _debounce?.cancel();
      _find.text = seeded;
    } else if (_find.text != seeded) {
      _search();
    }
    _offerQuery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  /// A keystroke in the find field: wait for the writer to pause.
  void _searchSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _search();
    });
  }

  /// Anything but a keystroke — a toggle, a filter, Enter, match navigation:
  /// the pending keystroke (if any) is part of this query, so run it first.
  void _search() {
    _debounce?.cancel();
    widget.controller.search(
      FindQuery(
        text: _find.text,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
        kinds: _only == null ? const [] : [_only!],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
      // The keyboard is already in the bar, so the script's selection is
      // whatever the last search left there and is not taken as a new one.
      case LogicalKeyboardKey.keyF
          when HardwareKeyboard.instance.isControlPressed:
        _offerQuery();
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        shift ? _previous() : _next();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Navigation always acts on what is typed, not on what the debounce has
  /// gotten around to searching: flush first, then move.
  void _previous() {
    _search();
    widget.controller.previousMatch();
  }

  void _next() {
    _search();
    widget.controller.nextMatch();
  }

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    return FocusScope(
      // Desktop text fields unfocus on pointer clicks outside them. Keep that
      // fallback inside Find so Escape and match navigation still reach _onKey.
      debugLabel: 'find bar',
      onKeyEvent: _onKey,
      // An overlay, floating over the script: the overlay surface and a
      // hairline of its own. No elevation — on a near-black background a drop
      // shadow separates nothing, and the surface step already does.
      child: Material(
        elevation: 0,
        color: colours.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: hairline(colours),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _find,
                          focusNode: _findFocus,
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            labelText: 'Find',
                          ),
                          onChanged: (_) => _searchSoon(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MatchCount(controller: widget.controller),
                      IconButton(
                        tooltip: 'Previous match (Shift+Enter)',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: _previous,
                      ),
                      IconButton(
                        tooltip: 'Next match (Enter)',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: _next,
                      ),
                      IconButton(
                        tooltip: 'Close (Escape)',
                        icon: const Icon(Icons.close),
                        onPressed: widget.onDismiss,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replace,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            labelText: 'Replace with',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            widget.controller.replaceCurrent(_replace.text),
                        child: const Text('Replace'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.controller.replaceAll(_replace.text),
                        child: const Text('All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // A `Wrap`, so that a long element-type name pushes the
                  // filter onto its own line instead of off the bar.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Toggle(
                        label: 'Match case',
                        value: _caseSensitive,
                        onChanged: (value) {
                          setState(() => _caseSensitive = value);
                          _search();
                        },
                      ),
                      _Toggle(
                        label: 'Whole word',
                        value: _wholeWord,
                        onChanged: (value) {
                          setState(() => _wholeWord = value);
                          _search();
                        },
                      ),
                      _ElementFilter(
                        value: _only,
                        onChanged: (kind) {
                          setState(() => _only = kind);
                          _search();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 of 17", or "No matches", which is what makes the count live.
class _MatchCount extends StatelessWidget {
  const _MatchCount({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = controller.matches.length;
    final index = controller.matchIndex;
    final label = switch ((controller.query.text.isEmpty, index)) {
      (true, _) => '',
      (false, null) => 'No matches',
      (false, final at?) => '${at + 1} of $total',
    };
    return SizedBox(
      width: 88,
      child: Text(
        label,
        key: const Key('find-match-count'),
        textAlign: TextAlign.right,
        style: theme.textTheme.labelMedium?.copyWith(
          color: context.colours.textTertiary,
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: onChanged,
    );
  }
}

// A non-null popup result distinguishes "Every element" from cancellation.
typedef _ElementFilterSelection = ({BlockKind? kind});

class _ElementFilter extends StatelessWidget {
  const _ElementFilter({required this.value, required this.onChanged});

  final BlockKind? value;
  final ValueChanged<BlockKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ElementFilterSelection>(
      tooltip: 'Restrict to an element type',
      initialValue: (kind: value),
      onSelected: (selection) => onChanged(selection.kind),
      itemBuilder: (context) => [
        const PopupMenuItem(value: (kind: null), child: Text('Every element')),
        const PopupMenuDivider(),
        for (final choice in elementChoices)
          PopupMenuItem(value: (kind: choice.kind), child: Text(choice.label)),
      ],
      child: Row(
        children: [
          Text(value == null ? 'Every element' : kindLabel(value!, 1)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
