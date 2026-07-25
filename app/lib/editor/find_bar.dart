import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';
import 'package:slugline/editor/metrics.dart';

/// `Ctrl+F`: find, with a live match count, and replace.
///
/// The bar owns the two text fields and the three toggles; the controller owns
/// the match list and which one the caret is on, because moving the caret to a
/// match is a selection change and selections belong to the controller (§2.1).
/// Escape closes the bar and changes no text — that is §Phase 3's requirement and
/// the reason Escape is handled here rather than left to bubble.
class FindBar extends StatefulWidget {
  const FindBar({
    required this.controller,
    required this.onDismiss,
    super.key,
  });

  final EditorController controller;
  final VoidCallback onDismiss;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  bool _caseSensitive = false;
  bool _wholeWord = false;

  /// `null` is every element type. Otherwise the one the search is restricted
  /// to — §Phase 3's optional element filter.
  BlockKind? _only;

  @override
  void initState() {
    super.initState();
    _find.text = widget.controller.query.text;
    _caseSensitive = widget.controller.query.caseSensitive;
    _wholeWord = widget.controller.query.wholeWord;
    _findFocus.requestFocus();
    if (_find.text.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _search() {
    widget.controller.search(FindQuery(
      text: _find.text,
      caseSensitive: _caseSensitive,
      wholeWord: _wholeWord,
      kinds: _only == null ? const [] : [_only!],
    ));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        shift ? widget.controller.previousMatch() : widget.controller.nextMatch();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      onKeyEvent: _onKey,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHigh,
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
                          onChanged: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MatchCount(controller: widget.controller),
                      IconButton(
                        tooltip: 'Previous match (Shift+Enter)',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: widget.controller.previousMatch,
                      ),
                      IconButton(
                        tooltip: 'Next match (Enter)',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: widget.controller.nextMatch,
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
                        onPressed: () => widget.controller.replaceCurrent(_replace.text),
                        child: const Text('Replace'),
                      ),
                      TextButton(
                        onPressed: () => widget.controller.replaceAll(_replace.text),
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
        style: theme.textTheme.labelMedium?.copyWith(color: theme.disabledColor),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, required this.onChanged});

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

class _ElementFilter extends StatelessWidget {
  const _ElementFilter({required this.value, required this.onChanged});

  final BlockKind? value;
  final ValueChanged<BlockKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<BlockKind?>(
      tooltip: 'Restrict to an element type',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Every element')),
        const PopupMenuDivider(),
        for (final choice in elementChoices)
          PopupMenuItem(value: choice.kind, child: Text(choice.label)),
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
