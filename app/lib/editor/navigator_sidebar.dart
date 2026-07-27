import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';

/// §Phase 8's scene and character navigator.
///
/// All screenplay semantics in [data] came from Rust. This widget owns only
/// presentation and gestures: filtering, keyboard selection, and explicit jump
/// callbacks.
class NavigatorSidebar extends StatefulWidget {
  const NavigatorSidebar({
    required this.data,
    required this.currentSceneBlock,
    required this.onSceneSelected,
    required this.onCharacterSelected,
    required this.onCollapse,
    super.key,
  });

  final NavigatorView data;
  final int? currentSceneBlock;
  final ValueChanged<int> onSceneSelected;
  final ValueChanged<NavigatorCharacter> onCharacterSelected;
  final VoidCallback onCollapse;

  @override
  State<NavigatorSidebar> createState() => NavigatorSidebarState();
}

class NavigatorSidebarState extends State<NavigatorSidebar> {
  final TextEditingController _filter = TextEditingController();
  final FocusNode _filterFocus = FocusNode(debugLabel: 'navigator filter');
  final ScrollController _scroll = ScrollController();
  _NavigatorSection _section = _NavigatorSection.scenes;
  int _selected = 0;

  @override
  void didUpdateWidget(NavigatorSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clampSelection();
  }

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the quick-jump path: scenes selected and the filter ready to type.
  void focusSceneSearch() {
    if (_section != _NavigatorSection.scenes) {
      setState(() {
        _section = _NavigatorSection.scenes;
        _selected = 0;
      });
    }
    _filterFocus.requestFocus();
    _filter.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _filter.text.length,
    );
  }

  List<NavigatorScene> get _scenes {
    final query = _filter.text.trim().toLowerCase();
    if (query.isEmpty) return widget.data.scenes;
    return widget.data.scenes.where((scene) {
      final searchable = [
        scene.sceneNumber,
        scene.prefix,
        scene.location,
        scene.timeOfDay,
      ].whereType<String>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  List<NavigatorCharacter> get _characters {
    final query = _filter.text.trim().toLowerCase();
    if (query.isEmpty) return widget.data.characters;
    return widget.data.characters
        .where((character) => character.name.toLowerCase().contains(query))
        .toList();
  }

  int get _itemCount => switch (_section) {
    _NavigatorSection.scenes => _scenes.length,
    _NavigatorSection.characters => _characters.length,
  };

  void _setSection(_NavigatorSection section) {
    if (_section == section) return;
    setState(() {
      _section = section;
      _selected = 0;
    });
    _scrollToSelection();
  }

  void _filterChanged(String _) {
    setState(() => _selected = 0);
    _scrollToSelection();
  }

  void _clampSelection() {
    final last = _itemCount - 1;
    if (last < 0) {
      _selected = 0;
    } else if (_selected > last) {
      _selected = last;
    }
  }

  void _move(int delta) {
    final count = _itemCount;
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    _scrollToSelection();
  }

  void _scrollToSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      const extent = 64.0;
      final target = _selected * extent;
      final top = _scroll.offset;
      final bottom = top + _scroll.position.viewportDimension - extent;
      if (target < top) {
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      } else if (target > bottom) {
        _scroll.jumpTo(
          (target - _scroll.position.viewportDimension + extent).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _activate() {
    if (_itemCount == 0) return;
    switch (_section) {
      case _NavigatorSection.scenes:
        widget.onSceneSelected(_scenes[_selected].block);
      case _NavigatorSection.characters:
        widget.onCharacterSelected(_characters[_selected]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveNavigatorIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveNavigatorIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _ActivateNavigatorIntent(),
      },
      child: Actions(
        actions: {
          _MoveNavigatorIntent: CallbackAction<_MoveNavigatorIntent>(
            onInvoke: (intent) {
              _move(intent.delta);
              return null;
            },
          ),
          _ActivateNavigatorIntent: CallbackAction<_ActivateNavigatorIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Navigator',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('collapse navigator'),
                      tooltip: 'Hide navigator',
                      onPressed: widget.onCollapse,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: TextField(
                  key: const ValueKey('navigator filter'),
                  controller: _filter,
                  focusNode: _filterFocus,
                  onChanged: _filterChanged,
                  onSubmitted: (_) => _activate(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _section == _NavigatorSection.scenes
                        ? 'Jump to scene…'
                        : 'Find character…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _filter.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear filter',
                            onPressed: () {
                              _filter.clear();
                              _filterChanged('');
                              _filterFocus.requestFocus();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _SectionButton(
                        label: 'Scenes',
                        count: widget.data.scenes.length,
                        selected: _section == _NavigatorSection.scenes,
                        onPressed: () => _setSection(_NavigatorSection.scenes),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _SectionButton(
                        label: 'Characters',
                        count: widget.data.characters.length,
                        selected: _section == _NavigatorSection.characters,
                        onPressed: () =>
                            _setSection(_NavigatorSection.characters),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(child: _list(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(ThemeData theme) {
    if (_itemCount == 0) {
      return Center(
        child: Text(
          _filter.text.isEmpty
              ? switch (_section) {
                  _NavigatorSection.scenes => 'No scenes',
                  _NavigatorSection.characters => 'No characters',
                }
              : 'No matches',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: 64,
      itemCount: _itemCount,
      itemBuilder: (context, index) => switch (_section) {
        _NavigatorSection.scenes => _sceneRow(theme, _scenes[index], index),
        _NavigatorSection.characters => _characterRow(
          theme,
          _characters[index],
          index,
        ),
      },
    );
  }

  Widget _sceneRow(ThemeData theme, NavigatorScene scene, int index) {
    final current = scene.block == widget.currentSceneBlock;
    final keyboardSelected = index == _selected;
    final subtitle = [
      scene.prefix,
      scene.timeOfDay,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    return Material(
      color: current
          ? theme.colorScheme.secondaryContainer
          : keyboardSelected
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent,
      child: ListTile(
        key: ValueKey('navigator scene ${scene.block}'),
        dense: true,
        selected: current,
        leading: scene.sceneNumber == null
            ? const SizedBox(width: 28)
            : SizedBox(
                width: 28,
                child: Text(
                  scene.sceneNumber!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ),
        title: Text(
          scene.location.isEmpty ? scene.prefix : scene.location,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () {
          setState(() => _selected = index);
          widget.onSceneSelected(scene.block);
        },
      ),
    );
  }

  Widget _characterRow(
    ThemeData theme,
    NavigatorCharacter character,
    int index,
  ) {
    final keyboardSelected = index == _selected;
    final count = character.occurrences;
    return Material(
      color: keyboardSelected
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent,
      child: ListTile(
        key: ValueKey('navigator character ${character.name}'),
        dense: true,
        leading: const SizedBox(
          width: 28,
          child: Icon(Icons.person_outline, size: 20),
        ),
        title: Text(
          character.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('$count ${count == 1 ? 'occurrence' : 'occurrences'}'),
        onTap: () {
          setState(() => _selected = index);
          widget.onCharacterSelected(character);
        },
      ),
    );
  }
}

enum _NavigatorSection { scenes, characters }

class _MoveNavigatorIntent extends Intent {
  const _MoveNavigatorIntent(this.delta);

  final int delta;
}

class _ActivateNavigatorIntent extends Intent {
  const _ActivateNavigatorIntent();
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton.tonal(onPressed: onPressed, child: Text('$label $count'))
        : TextButton(onPressed: onPressed, child: Text('$label $count'));
  }
}
