import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A file chooser, in the application, with no dependency behind it.
///
/// The obvious answer is `file_selector_linux`, which puts up GTK's own dialog.
/// It is turned down for one reason: it pulls `http` in transitively, and §1.2
/// makes "the application makes **zero** network requests" a build-time
/// assertion (§13). An HTTP client linked into the bundle is a thing that
/// assertion then has to argue with. Phase 10 revisited the choice and retained
/// this dependency-free surface (ADR 0037), adding directory selection for
/// backup preferences.
///
/// What this does instead is small and honest: list a directory, walk into it,
/// and type a name. Keyboard-first, like everything else here (§1.1).
class FileChooser extends StatefulWidget {
  const FileChooser({
    required this.title,
    required this.action,
    required this.directory,
    this.suggestedName,
    this.mustExist = false,
    this.selectDirectory = false,
    super.key,
  });

  /// "Open script", "Save as", "New script".
  final String title;

  /// The confirm button's label.
  final String action;

  /// Where to start. The last directory used, or the user's home.
  final String directory;

  /// Pre-filled in the name field. Null for an open dialog, which has no name to
  /// suggest.
  final String? suggestedName;

  /// Whether the chosen file has to be one that is already there.
  final bool mustExist;
  final bool selectDirectory;

  /// Shows the chooser. Returns the absolute path chosen, or null.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String action,
    String? directory,
    String? suggestedName,
    bool mustExist = false,
    bool selectDirectory = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => FileChooser(
        title: title,
        action: action,
        directory: directory ?? defaultDirectory(),
        suggestedName: suggestedName,
        mustExist: mustExist,
        selectDirectory: selectDirectory,
      ),
    );
  }

  /// Where a chooser starts when nothing better is known.
  static String defaultDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return Directory.current.path;
    return home;
  }

  @override
  State<FileChooser> createState() => _FileChooserState();
}

class _FileChooserState extends State<FileChooser> {
  late String _directory = widget.directory;
  late final TextEditingController _name =
      TextEditingController(text: widget.suggestedName ?? '');
  final FocusNode _nameFocus = FocusNode();

  List<FileSystemEntity> _entries = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _list();
    if (!widget.selectDirectory) _nameFocus.requestFocus();
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _list() {
    try {
      final entries = Directory(_directory).listSync(followLinks: false)
        ..removeWhere((entry) {
          final name = _basename(entry.path);
          // Dotfiles, and our own in-flight saves. A `.tmp-` file in a directory
          // is a save happening right now; offering to open one would be
          // offering a file that is about to stop existing.
          return name.startsWith('.') || name.contains('.tmp-');
        });
      entries.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return _basename(a.path).toLowerCase().compareTo(_basename(b.path).toLowerCase());
      });
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on FileSystemException catch (failure) {
      setState(() {
        _entries = const [];
        _error = failure.osError?.message ?? 'cannot read this directory';
      });
    }
  }

  void _enter(String path) {
    setState(() => _directory = path);
    _list();
  }

  void _up() {
    final parent = Directory(_directory).parent.path;
    if (parent != _directory) _enter(parent);
  }

  String get _chosen {
    if (widget.selectDirectory) return _directory;
    var name = _name.text.trim();
    if (name.isEmpty) return '';
    if (name.startsWith('/')) return name;
    // A screenplay is a `.fountain` file (§1.1). Typing "heat" should not
    // produce a file no editor will recognise.
    if (!widget.mustExist && !name.contains('.')) name = '$name.fountain';
    return '$_directory/$name';
  }

  void _confirm() {
    final path = _chosen;
    if (path.isEmpty) return;
    if (widget.mustExist && !File(path).existsSync()) {
      setState(() => _error = 'there is no file at $path');
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _up,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Parent directory',
                ),
                Expanded(
                  child: Text(
                    _directory,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        _error ?? 'nothing here',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final name = _basename(entry.path);
                        final isDirectory = entry is Directory;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isDirectory ? Icons.folder : Icons.description_outlined,
                            size: 18,
                          ),
                          title: Text(name),
                          onTap: () {
                            if (isDirectory) {
                              _enter(entry.path);
                            } else if (!widget.selectDirectory) {
                              _name.text = name;
                              _nameFocus.requestFocus();
                            }
                          },
                        );
                      },
                    ),
            ),
            if (!widget.selectDirectory) ...[
              const Divider(height: 1),
              Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): _ConfirmIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter): _ConfirmIntent(),
                },
                child: Actions(
                  actions: {
                    _ConfirmIntent: CallbackAction<_ConfirmIntent>(
                      onInvoke: (_) {
                        _confirm();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'File name',
                      errorText: _error,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
              ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: Text(widget.action)),
      ],
    );
  }
}

class _ConfirmIntent extends Intent {
  const _ConfirmIntent();
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
