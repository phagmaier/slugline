import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/theme.dart';

/// §Phase 4's library: create, open, rename, duplicate, remove, delete, and the
/// recent list.
///
/// The list is a **cache** and behaves like one. A script that is not in it can
/// still be opened, by path; a script in it whose file has gone is shown as
/// missing rather than dropped, because a drive that is not mounted this morning
/// is not a script the writer threw away.
///
/// Remove and Delete are two commands, and the difference is the whole reason
/// the index is only a cache: removing forgets a row, deleting destroys a file.
/// They are not next to each other in the menu, and only one of them asks twice.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    required this.core,
    required this.onOpen,
    this.onOpenPreferences,
    this.onShowShortcuts,
    super.key,
  });

  final LibraryCore core;

  /// Open a script at this path. The shell above turns it into an editor.
  final Future<void> Function(String path) onOpen;
  final Future<void> Function()? onOpenPreferences;
  final Future<void> Function()? onShowShortcuts;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<ScriptView>? _scripts;
  Object? _error;

  final TextEditingController _search = TextEditingController();
  _LibrarySort _sort = _LibrarySort.recent;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final scripts = await widget.core.library();
      if (!mounted) return;
      setState(() {
        _scripts = scripts;
        _error = null;
      });
    } catch (error) {
      // Without this the spinner runs forever: `body` switches on `scripts`
      // alone and null means loading. Surface the failure with a retry.
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _newScript() async {
    final path = await FileChooser.show(
      context,
      title: 'New script',
      action: 'Create',
      suggestedName: 'untitled.fountain',
    );
    if (path == null || !mounted) return;
    await widget.onOpen(path);
    if (mounted) await _refresh();
  }

  Future<void> _openScript() async {
    final path = await FileChooser.show(
      context,
      title: 'Open script',
      action: 'Open',
      mustExist: true,
    );
    if (path == null || !mounted) return;
    await widget.onOpen(path);
    if (mounted) await _refresh();
  }

  Future<void> _rename(ScriptView script) async {
    final path = await FileChooser.show(
      context,
      title: 'Rename script',
      action: 'Rename',
      directory: _parent(script.path),
      suggestedName: _basename(script.path),
    );
    if (path == null || !mounted) return;
    final outcome = await widget.core.rename(script.id, path);
    if (!mounted) return;
    if (outcome case SaveOutcome_Failed(:final message)) {
      _say(message);
    }
    await _refresh();
  }

  Future<void> _duplicate(ScriptView script) async {
    final copy = await widget.core.duplicate(script.id);
    if (!mounted) return;
    if (copy == null) {
      _say('${script.title} could not be duplicated');
    }
    await _refresh();
  }

  Future<void> _remove(ScriptView script, {required bool deleteFile}) async {
    if (deleteFile) {
      // The only irreversible thing on this page. It says the file name, it says
      // the word "permanently", and its confirming button is destructive-red.
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.delete_forever_outlined),
              title: Text('Delete ${_basename(script.path)}?'),
              content: Text(
                'This permanently deletes ${script.path}. '
                'Backups of it are kept, but the file itself is gone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colours.danger,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }
    await widget.core.forget(script.id, deleteFile: deleteFile);
    if (mounted) await _refresh();
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scripts = _scripts;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.f1) {
          unawaited(widget.onShowShortcuts?.call());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.comma &&
            HardwareKeyboard.instance.isControlPressed) {
          unawaited(widget.onOpenPreferences?.call());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Keyboard shortcuts (F1)',
              onPressed: widget.onShowShortcuts,
              icon: const Icon(Icons.keyboard_outlined),
            ),
            IconButton(
              tooltip: 'Preferences (Ctrl+,)',
              onPressed: widget.onOpenPreferences,
              icon: const Icon(Icons.settings_outlined),
            ),
            TextButton(onPressed: _openScript, child: const Text('Open')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _newScript,
              icon: const Icon(Icons.add),
              label: const Text('New script'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: switch ((scripts, _error)) {
          (_, final error?) => _errorState(theme, error),
          (null, null) => const Center(child: CircularProgressIndicator()),
          ([], null) => _emptyState(theme),
          (final found?, null) => _recentScripts(found),
        },
      ),
    );
  }

  Widget _errorState(ThemeData theme, Object error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: context.colours.danger,
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load the library.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.colours.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.colours.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() => _error = null);
              _refresh();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              key: const ValueKey('library-empty-icon'),
              size: 56,
              color: context.colours.textTertiary,
            ),
            const SizedBox(height: 18),
            Text(
              'No scripts yet. Create a new script to start writing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: context.colours.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('create first script'),
                  onPressed: _newScript,
                  icon: const Icon(Icons.add),
                  label: const Text('New script'),
                ),
                TextButton(onPressed: _openScript, child: const Text('Open')),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _recentScripts(List<ScriptView> scripts) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
    child: Center(
      child: ConstrainedBox(
        key: const ValueKey('library-content'),
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _searchSortRow(),
            const SizedBox(height: 12),
            Text(
              _sort.header,
              style: TextStyle(
                color: context.colours.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _scriptList(scripts)),
          ],
        ),
      ),
    ),
  );

  /// Search and sort, on one row. A library is tens of scripts, so filtering
  /// and sorting run on every build with no memo — the alternative (cached
  /// lists with an invalidation story) is machinery for a millisecond.
  Widget _searchSortRow() => Row(
    children: [
      Expanded(
        child: TextField(
          key: const Key('library-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search scripts',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('library-search-clear'),
                    tooltip: 'Clear search',
                    iconSize: 16,
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<_LibrarySort>(
        key: const Key('library-sort'),
        tooltip: 'Sort scripts (${_sort.label})',
        icon: const Icon(Icons.sort_outlined),
        initialValue: _sort,
        onSelected: (sort) => setState(() => _sort = sort),
        itemBuilder: (context) => [
          for (final sort in _LibrarySort.values)
            PopupMenuItem(
              value: sort,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: sort == _sort
                        ? const Icon(Icons.check, size: 15)
                        : null,
                  ),
                  Text(sort.label),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  Widget _scriptList(List<ScriptView> scripts) {
    final visible = _visible(scripts);
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No scripts match "${_search.text}".',
              key: const Key('library-no-matches'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.colours.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const Key('library-clear-search'),
              onPressed: () => setState(_search.clear),
              child: const Text('Clear search'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _row(visible[index]),
    );
  }

  /// The scripts matching the search, in the chosen order. Missing files sort
  /// with the rest rather than sinking: a drive that is not mounted is not a
  /// script the writer threw away, and hiding those rows behind a sort would
  /// be dropping them by another name.
  List<ScriptView> _visible(List<ScriptView> scripts) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? List<ScriptView>.of(scripts)
        : scripts
              .where(
                (script) =>
                    script.title.toLowerCase().contains(query) ||
                    script.path.toLowerCase().contains(query),
              )
              .toList();
    switch (_sort) {
      case _LibrarySort.recent:
        visible.sort((a, b) => b.modifiedMillis.compareTo(a.modifiedMillis));
      case _LibrarySort.name:
        visible.sort(
          (a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _LibrarySort.pages:
        visible.sort((a, b) => b.pageCount.compareTo(a.pageCount));
    }
    return visible;
  }

  Widget _row(ScriptView script) {
    final theme = Theme.of(context);
    final colours = context.colours;
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: colours.textTertiary,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('library-row-${script.id}'),
        onTap: script.missing ? null : () => widget.onOpen(script.path),
        hoverColor: colours.surfaceRaised,
        highlightColor: colours.accentSubtle,
        mouseCursor: script.missing
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              Icon(
                script.missing
                    ? Icons.help_outline
                    : Icons.description_outlined,
                size: 22,
                color: script.missing ? colours.danger : colours.textSecondary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      script.title,
                      key: ValueKey('library-title-${script.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (script.missing) ...[
                          Text(
                            'Missing',
                            style: metadataStyle?.copyWith(
                              color: colours.danger,
                            ),
                          ),
                          _metadataSeparator(metadataStyle),
                        ],
                        Text(
                          _relativeTime(script.modifiedMillis),
                          style: metadataStyle,
                        ),
                        // Zero is "not paginated yet", not a zero-page script.
                        if (script.pageCount > 0) ...[
                          _metadataSeparator(metadataStyle),
                          Text(
                            _pageCount(script.pageCount),
                            style: metadataStyle,
                          ),
                        ],
                        _metadataSeparator(metadataStyle),
                        Flexible(
                          child: Tooltip(
                            message: script.path,
                            child: Text(
                              _displayPath(script.path),
                              key: ValueKey('library-path-${script.id}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metadataStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                onSelected: (action) => switch (action) {
                  _Action.rename => _rename(script),
                  _Action.duplicate => _duplicate(script),
                  _Action.remove => _remove(script, deleteFile: false),
                  _Action.delete => _remove(script, deleteFile: true),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _Action.rename,
                    enabled: !script.missing,
                    child: const Text('Rename…'),
                  ),
                  PopupMenuItem(
                    value: _Action.duplicate,
                    enabled: !script.missing,
                    child: const Text('Duplicate'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _Action.remove,
                    child: Text('Remove from library'),
                  ),
                  PopupMenuItem(
                    value: _Action.delete,
                    enabled: !script.missing,
                    child: Text(
                      'Delete file…',
                      style: TextStyle(color: colours.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metadataSeparator(TextStyle? style) => Text('  ·  ', style: style);

  String _displayPath(String path) {
    final home = Platform.environment['HOME'] ?? '';
    var display = path;
    if (home.isNotEmpty && path.startsWith(home)) {
      display = '~${path.substring(home.length)}';
    }
    if (display.length <= 48) return display;
    final basename = _basename(display);
    final dir = display.substring(0, display.length - basename.length);
    final keep = 48 - basename.length - 3;
    if (keep <= 0) return '...$basename';
    final start = (keep * 0.6).ceil();
    final end = keep - start;
    return '${dir.substring(0, start)}...${dir.substring(dir.length - end)}$basename';
  }
}

enum _Action { rename, duplicate, remove, delete }

String _parent(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

String _relativeTime(int modifiedMillis) {
  if (modifiedMillis <= 0) return 'Unknown time';
  final elapsedMillis = DateTime.now().millisecondsSinceEpoch - modifiedMillis;
  if (elapsedMillis < const Duration(minutes: 1).inMilliseconds) {
    return 'Just now';
  }

  final elapsed = Duration(milliseconds: elapsedMillis);
  if (elapsed.inHours < 1) {
    return _ago(elapsed.inMinutes, 'minute');
  }
  if (elapsed.inDays < 1) {
    return _ago(elapsed.inHours, 'hour');
  }
  if (elapsed.inDays < 7) {
    return _ago(elapsed.inDays, 'day');
  }
  if (elapsed.inDays < 30) {
    return _ago(elapsed.inDays ~/ 7, 'week');
  }
  if (elapsed.inDays < 365) {
    return _ago(elapsed.inDays ~/ 30, 'month');
  }
  return _ago(elapsed.inDays ~/ 365, 'year');
}

String _ago(int amount, String unit) =>
    '$amount $unit${amount == 1 ? '' : 's'} ago';

/// The orders a script list can be read in. Recent first is the default,
/// because the library answers "what was I working on" far more often than
/// anything else.
enum _LibrarySort {
  recent('Recently modified', 'RECENT'),
  name('Title', 'BY TITLE'),
  pages('Page count', 'BY PAGES');

  const _LibrarySort(this.label, this.header);

  final String label;
  final String header;
}

String _pageCount(int pages) => '$pages ${pages == 1 ? 'page' : 'pages'}';
