import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/theme.dart';

/// Ctrl+O selects a recent script without leaving the current session. Browse
/// hands off to the existing chooser only after this dialog has been dismissed.
class QuickOpenDialog extends StatefulWidget {
  const QuickOpenDialog({required this.core, super.key});

  final LibraryCore core;

  static Future<String?> show(BuildContext context, LibraryCore core) async {
    final chosen = await showDialog<Object>(
      context: context,
      builder: (_) => QuickOpenDialog(core: core),
    );
    if (chosen is String) return chosen;
    if (chosen != _Browse.choose || !context.mounted) return null;
    return FileChooser.show(
      context,
      title: 'Open script',
      action: 'Open',
      mustExist: true,
    );
  }

  @override
  State<QuickOpenDialog> createState() => _QuickOpenDialogState();
}

enum _Browse { choose }

class _QuickOpenDialogState extends State<QuickOpenDialog> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<ScriptView> _scripts = const [];
  String? _error;
  bool _loading = true;
  int _highlighted = 0;
  static const _rowHeight = 64.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final scripts = await widget.core.library();
      if (!mounted) return;
      setState(() {
        _scripts = scripts.where((script) => !script.missing).toList()
          ..sort((a, b) => b.modifiedMillis.compareTo(a.modifiedMillis));
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load recent scripts. Browse to open a file.';
        });
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ScriptView> get _visible {
    final query = _query.text.trim().toLowerCase();
    return _scripts
        .where(
          (script) =>
              script.title.toLowerCase().contains(query) ||
              script.path.toLowerCase().contains(query),
        )
        .toList();
  }

  void _choose() {
    final visible = _visible;
    Navigator.of(context).pop(
      _highlighted < visible.length
          ? visible[_highlighted].path
          : _Browse.choose,
    );
  }

  void _move(int delta) {
    setState(
      () => _highlighted = (_highlighted + delta) % (_visible.length + 1),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_highlighted * _rowHeight).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    _highlighted = _highlighted.clamp(0, visible.length);
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 420,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            switch (event.logicalKey) {
              case LogicalKeyboardKey.escape:
                Navigator.of(context).pop();
              case LogicalKeyboardKey.arrowDown:
                _move(1);
              case LogicalKeyboardKey.arrowUp:
                _move(-1);
              case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
                _choose();
              default:
                return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('Open script'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: TextField(
                  key: const Key('quick-open-search'),
                  controller: _query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search scripts',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() => _highlighted = 0),
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              if (!_loading && _error == null && visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No matching scripts'),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: visible.length + 1,
                  itemExtent: _rowHeight,
                  itemBuilder: (context, index) {
                    final script = index < visible.length
                        ? visible[index]
                        : null;
                    return Material(
                      color: index == _highlighted
                          ? context.colours.accentSubtle
                          : Colors.transparent,
                      child: ListTile(
                        key: ValueKey(
                          script == null
                              ? 'quick-open-browse'
                              : 'quick-open-${script.id}',
                        ),
                        selected: index == _highlighted,
                        title: Text(
                          script?.title ?? 'Browse…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: script == null
                            ? null
                            : Text(
                                script.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () {
                          _highlighted = index;
                          _choose();
                        },
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('↑ / ↓ select · Enter opens · Escape closes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
