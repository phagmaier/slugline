import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/editor/commands.dart';

/// `Ctrl+K`: a searchable list of every element type and command.
///
/// It is a panel inside the editor rather than a `showDialog`, for two reasons:
/// a dialog steals the focus tree and gives it back somewhere else, and Escape
/// has to be ours — §Phase 3 requires that Escape dismisses this and **never
/// loses text**, which means it must not reach the surface and must not be
/// handled by a route pop we do not control.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    required this.commands,
    required this.onDismiss,
    super.key,
  });

  final List<EditorCommand> commands;

  /// Called for Escape, for a click outside, and after a command runs. The
  /// palette never closes itself.
  final VoidCallback onDismiss;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// One row's height. Fixed, so that scrolling the highlight into view is
/// arithmetic rather than a layout query.
const double _rowHeight = 44;

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  int _highlighted = 0;

  List<EditorCommand> get _visible => filterCommands(widget.commands, _query.text);

  @override
  void initState() {
    super.initState();
    _queryFocus.requestFocus();
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(EditorCommand command) {
    // Dismiss first: the command moves the caret, and the surface has to have
    // the focus back before it does.
    widget.onDismiss();
    command.run();
  }

  void _runHighlighted() {
    final visible = _visible;
    if (visible.isEmpty) return;
    _run(visible[_highlighted.clamp(0, visible.length - 1)]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _runHighlighted();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _move(int delta) {
    final count = _visible.length;
    if (count == 0) return;
    setState(() {
      _highlighted = (_highlighted + delta) % count;
      if (_highlighted < 0) _highlighted += count;
    });
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      (_highlighted * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    if (_highlighted >= visible.length) _highlighted = 0;

    return Stack(
      children: [
        // A click anywhere outside closes it, as every palette does.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 72),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.surfaceContainerHigh,
                child: Focus(
                  onKeyEvent: _onKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                        child: TextField(
                          controller: _query,
                          focusNode: _queryFocus,
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Element or command',
                            prefixIcon: Icon(Icons.search, size: 18),
                          ),
                          onChanged: (_) => setState(() => _highlighted = 0),
                          onSubmitted: (_) => _runHighlighted(),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: visible.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No matching command'),
                              )
                            : ListView.builder(
                                controller: _scroll,
                                shrinkWrap: true,
                                itemCount: visible.length,
                                itemExtent: _rowHeight,
                                itemBuilder: (context, index) => _PaletteRow(
                                  command: visible[index],
                                  selected: index == _highlighted,
                                  onTap: () => _run(visible[index]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final EditorCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.18) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                command.group,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor),
              ),
            ),
            Expanded(child: Text(command.label, style: theme.textTheme.bodyMedium)),
            if (command.shortcut.isNotEmpty)
              Text(
                command.shortcut,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor),
              ),
          ],
        ),
      ),
    );
  }
}
