import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/library/backups_dialog.dart' show formatBytes, formatTimestamp;
import 'package:slugline/library/file_chooser.dart';

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
    super.key,
  });

  final Core core;

  /// Open a script at this path. The shell above turns it into an editor.
  final Future<void> Function(String path) onOpen;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<ScriptView>? _scripts;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final scripts = await widget.core.library();
    if (!mounted) return;
    setState(() => _scripts = scripts);
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
      final confirmed = await showDialog<bool>(
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
                    backgroundColor: Theme.of(context).colorScheme.error,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scripts = _scripts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slugline'),
        actions: [
          TextButton.icon(
            onPressed: _openScript,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open'),
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
      body: switch (scripts) {
        null => const Center(child: CircularProgressIndicator()),
        [] => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No scripts yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Everything Slugline writes is an ordinary .fountain file '
                  'at a path you chose.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        final found => ListView.separated(
            itemCount: found.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _row(found[index]),
          ),
      },
    );
  }

  Widget _row(ScriptView script) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        script.missing ? Icons.help_outline : Icons.description_outlined,
        color: script.missing ? theme.colorScheme.error : null,
      ),
      title: Text(script.title),
      subtitle: Text(
        [
          script.path,
          if (script.missing)
            'missing'
          else ...[
            formatTimestamp(script.modifiedMillis),
            formatBytes(script.bytes),
            // Phase 6's `layout` crate fills this in; until then the library
            // says nothing rather than guessing.
            if (script.pageCount > 0) '${script.pageCount} pages',
          ],
        ].join(' · '),
        style: theme.textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: script.missing ? null : () => widget.onOpen(script.path),
      trailing: PopupMenuButton<_Action>(
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
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
