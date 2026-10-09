import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/library/reveal_folder.dart';
import 'package:slugline/library/save_dialogs.dart';
import 'package:slugline/library/name_dialog.dart';
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/library/quick_open_dialog.dart';
import 'package:slugline/theme.dart';

/// Directory-backed scripts, including explicit import, archive and migration.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    required this.core,
    required this.onOpen,
    this.onCreate,
    this.onImport,
    this.onOpenPreferences,
    this.onShowShortcuts,
    super.key,
  });

  final LibraryCore core;

  /// Open a script at this path. The shell above turns it into an editor.
  final Future<void> Function(String path) onOpen;
  final Future<void> Function(String path)? onCreate;
  final Future<void> Function()? onImport;
  final Future<void> Function()? onOpenPreferences;
  final Future<void> Function()? onShowShortcuts;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<ScriptView>? _scripts;
  Object? _error;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Map<String, GlobalKey> _rowKeys = {};
  int _highlighted = 0;
  bool _choosing = false;
  bool _archived = false;
  _LibrarySort _sort = _LibrarySort.recent;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final scripts = await widget.core.library();
      if (!mounted) return;
      setState(() {
        _scripts = scripts;
        _error = null;
        _highlighted = 0;
      });
      _searchFocus.requestFocus();
    } catch (error) {
      // Without this the spinner runs forever: `body` switches on `scripts`
      // alone and null means loading. Surface the failure with a retry.
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _newScript() async {
    if (_choosing || widget.onCreate == null) return;
    _choosing = true;
    try {
      await widget.onCreate!('Untitled');
      if (mounted) await _refresh();
    } finally {
      _choosing = false;
    }
  }

  Future<void> _openScript() async {
    await _choose(() => QuickOpenDialog.show(context, widget.core));
  }

  Future<void> _importScript() async {
    final action = widget.onImport;
    if (_choosing || action == null) return;
    _choosing = true;
    try {
      await action();
      if (mounted) await _refresh();
    } finally {
      _choosing = false;
      if (mounted) _searchFocus.requestFocus();
    }
  }

  Future<void> _choose(
    Future<String?> Function() choose, {
    Future<void> Function(String path)? accept,
  }) async {
    if (_choosing) return;
    _choosing = true;
    try {
      final path = await choose();
      if (path == null || !mounted) return;
      await (accept ?? widget.onOpen)(path);
      if (mounted) await _refresh();
    } finally {
      _choosing = false;
      if (mounted) _searchFocus.requestFocus();
    }
  }

  void _moveHighlight(int delta) {
    final visible = _visible(_scripts ?? const []);
    if (visible.isEmpty) return;
    setState(
      () => _highlighted = (_highlighted + delta).clamp(0, visible.length - 1),
    );
    final id = visible[_highlighted].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _rowKeys[id]?.currentContext;
      if (row != null) Scrollable.ensureVisible(row);
    });
  }

  void _openHighlighted() {
    if (_choosing) return;
    final visible = _visible(_scripts ?? const []);
    if (visible.isEmpty) return;
    final script = visible[_highlighted.clamp(0, visible.length - 1)];
    if (!script.missing && script.problem == null && !script.archived) {
      unawaited(_choose(() async => script.path));
    }
  }

  Future<void> _rename(ScriptView script) async {
    final chosen = await renameProjectDialog(context, script.title);
    if (chosen == null || !mounted) return;
    final outcome = await widget.core.rename(script.id, chosen);
    if (!mounted) return;
    if (outcome case SaveOutcome_Failed(:final message)) _say(message);
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

  Future<void> _archive(ScriptView script) async {
    final core = widget.core;
    final success = core is ManagedLibraryCore
        ? await (core as ManagedLibraryCore).archive(
            script.id,
            !script.archived,
          )
        : await core.forget(script.id, deleteFile: false);
    if (!mounted) return;
    if (!success) {
      _say('Could not update archive metadata. The script remains unchanged.');
    }
    await _refresh();
  }

  Future<void> _repair(ScriptView script) async {
    final core = widget.core;
    if (core is! ManagedLibraryCore) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair project metadata?'),
        content: const Text(
          'The damaged sidecar is preserved beside the repaired file. Screenplay bytes stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (!await (core as ManagedLibraryCore).repair(script.id) && mounted) {
      _say('This project needs manual repair or a newer Slugline version.');
    }
    if (mounted) await _refresh();
  }

  Future<void> _rescue(ScriptView script) async {
    final path = await FileChooser.show(
      context,
      title: 'Export saved screenplay text',
      action: 'Export',
      suggestedName: '${script.title}.fountain',
    );
    if (path == null || !mounted) return;
    var outcome = await files.libraryRescue(
      id: script.id,
      path: path,
      overwrite: false,
    );
    if (outcome is SaveOutcome_Failed &&
        outcome.failure == SaveFailure.alreadyExists &&
        mounted) {
      if (await confirmReplace(context, path)) {
        outcome = await files.libraryRescue(
          id: script.id,
          path: path,
          overwrite: true,
        );
      }
    }
    if (outcome case SaveOutcome_Failed(:final message)) {
      if (mounted) _say(message);
    }
  }

  Future<void> _migrate() async {
    final core = widget.core;
    if (_choosing || core is! ManagedLibraryCore) return;
    final entries = await (core as ManagedLibraryCore).legacyScripts();
    if (!mounted) return;
    final selected = <String>{};
    final statuses = <String, String>{};
    var busy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          return PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('Bring existing scripts into the library'),
              content: SizedBox(
                width: 580,
                height: 320,
                child: Column(
                  children: [
                    const Text(
                      'Copies are created in the library. Original files and old version folders remain unchanged. Resolve pending recovery first.',
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final entry in entries)
                            CheckboxListTile(
                              title: Text(entry.title),
                              subtitle: Text(statuses[entry.id] ?? entry.path),
                              value: selected.contains(entry.id),
                              onChanged: busy
                                  ? null
                                  : (value) {
                                      update(() {
                                        if (value == true) {
                                          selected.add(entry.id);
                                        } else {
                                          selected.remove(entry.id);
                                        }
                                      });
                                    },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Decide later'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (selected.isEmpty) return;
                          update(() => busy = true);
                          for (final id in selected.toList()) {
                            final result = await (core as ManagedLibraryCore)
                                .migrate(id);
                            if (!context.mounted) break;
                            update(() => statuses[id] = result.message);
                          }
                          if (context.mounted) update(() => busy = false);
                        },
                  child: Text(busy ? 'Importing…' : 'Import selected'),
                ),
              ],
            ),
          );
        },
      ),
    );
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
    return FocusScope(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final keys = HardwareKeyboard.instance;
        if (!keys.isControlPressed &&
            !keys.isShiftPressed &&
            _searchFocus.hasFocus &&
            const [
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.numpadEnter,
            ].contains(event.logicalKey)) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowDown:
              _moveHighlight(1);
            case LogicalKeyboardKey.arrowUp:
              _moveHighlight(-1);
            case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
              _openHighlighted();
            default:
              return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        }
        if (event is KeyRepeatEvent) return KeyEventResult.ignored;
        if (keys.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyN) {
          unawaited(_newScript());
          return KeyEventResult.handled;
        }
        if (keys.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyO) {
          unawaited(_openScript());
          return KeyEventResult.handled;
        }
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
            if (widget.core case final ManagedLibraryCore managed) ...[
              IconButton(
                tooltip: 'Reveal library folder',
                onPressed: () =>
                    revealFolder(context, managed.libraryStatus().path),
                icon: const Icon(Icons.folder_outlined),
              ),
              if (managed.libraryStatus().legacyCount > 0)
                TextButton(
                  onPressed: _migrate,
                  child: const Text('Bring existing scripts…'),
                ),
            ],
            TextButton(
              onPressed: () => setState(() {
                _archived = !_archived;
                _highlighted = 0;
              }),
              child: Text(_archived ? 'Active scripts' : 'Archived'),
            ),
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
            if (widget.onImport != null)
              TextButton(
                key: const Key('import-script'),
                onPressed: _importScript,
                child: const Text('Import…'),
              ),
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
          Icon(Icons.error_outline, size: 48, color: context.colours.danger),
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
              'No scripts yet. Create a new script or import a screenplay.',
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
                if (widget.onImport != null)
                  TextButton(
                    onPressed: _importScript,
                    child: const Text('Import…'),
                  ),
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
          focusNode: _searchFocus,
          autofocus: true,
          onChanged: (_) => setState(() => _highlighted = 0),
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
                    onPressed: _clearSearch,
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
        onSelected: (sort) {
          setState(() {
            _sort = sort;
            _highlighted = 0;
          });
          _searchFocus.requestFocus();
        },
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
    _highlighted = _highlighted.clamp(
      0,
      visible.isEmpty ? 0 : visible.length - 1,
    );
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
              onPressed: _clearSearch,
              child: const Text('Clear search'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _row(visible[index], selected: index == _highlighted),
    );
  }

  /// The scripts matching the search, in the chosen order. Missing files sort
  /// with the rest rather than sinking: a drive that is not mounted is not a
  /// script the writer threw away, and hiding those rows behind a sort would
  /// be dropping them by another name.
  List<ScriptView> _visible(List<ScriptView> scripts) {
    final query = _search.text.trim().toLowerCase();
    scripts = scripts.where((script) => script.archived == _archived).toList();
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
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _LibrarySort.pages:
        visible.sort((a, b) => b.pageCount.compareTo(a.pageCount));
    }
    return visible;
  }

  void _clearSearch() {
    setState(() {
      _search.clear();
      _highlighted = 0;
    });
    _searchFocus.requestFocus();
  }

  Widget _row(ScriptView script, {required bool selected}) {
    final theme = Theme.of(context);
    final colours = context.colours;
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: colours.textTertiary,
    );
    return Material(
      key: _rowKeys.putIfAbsent(script.id, () => GlobalKey()),
      color: selected ? colours.accentSubtle : Colors.transparent,
      child: InkWell(
        key: ValueKey('library-row-${script.id}'),
        onTap:
            script.missing ||
                script.problem != null ||
                script.archived ||
                _choosing
            ? null
            : () => unawaited(_choose(() async => script.path)),
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
                        if (script.migrationStatus != null)
                          Flexible(
                            child: Text(
                              script.migrationStatus!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (script.problem != null)
                          Flexible(
                            child: Text(
                              script.problem!,
                              style: metadataStyle?.copyWith(
                                color: colours.danger,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                  _Action.archive => _archive(script),
                  _Action.reveal => revealFolder(context, _parent(script.path)),
                  _Action.repair => _repair(script),
                  _Action.rescue => _rescue(script),
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
                  PopupMenuItem(
                    value: _Action.archive,
                    enabled: script.problem == null,
                    child: Text(
                      script.archived ? 'Restore archived' : 'Archive',
                    ),
                  ),
                  const PopupMenuItem(
                    value: _Action.reveal,
                    child: Text('Reveal project folder'),
                  ),
                  if (script.problem != null) ...[
                    const PopupMenuItem(
                      value: _Action.repair,
                      child: Text('Repair metadata…'),
                    ),
                    const PopupMenuItem(
                      value: _Action.rescue,
                      child: Text('Export saved text…'),
                    ),
                  ],
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

enum _Action { rename, duplicate, archive, reveal, repair, rescue }

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
