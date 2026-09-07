import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/theme.dart';

typedef SceneReorderCallback =
    void Function(int sceneBlock, int? beforeSceneBlock);

const _navigatorRowExtent = 52.0;

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
    required this.onSceneReordered,
    required this.onCharacterSelected,
    required this.onCollapse,
    super.key,
  });

  final NavigatorView data;
  final int? currentSceneBlock;
  final ValueChanged<int> onSceneSelected;
  final SceneReorderCallback onSceneReordered;
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
  int? _hoveredScene;
  int? _focusedScene;
  String? _hoveredCharacter;

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

  double get _rowExtent =>
      _navigatorRowExtent +
      (MediaQuery.textScalerOf(context).scale(26) - 26).clamp(
        0.0,
        double.infinity,
      );

  void _move(int delta) {
    final count = _itemCount;
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    _scrollToSelection();
  }

  void _scrollToSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final extent = _rowExtent;
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

  void scrollToSceneBlock(int blockId) {
    if (_section != _NavigatorSection.scenes || !_scroll.hasClients) return;
    final scenes = _scenes;
    final index = scenes.indexWhere((s) => s.block == blockId);
    if (index < 0) return;

    final extent = _rowExtent;
    final target = index * extent;
    final viewport = _scroll.position.viewportDimension;
    final top = _scroll.offset;
    final bottom = top + viewport;

    if (target >= top - extent && target + extent <= bottom + extent) return;

    _scroll.jumpTo(
      (target - viewport / 2 + extent / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      ),
    );
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

  void _reorderScenes(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    final scenes = List<NavigatorScene>.of(widget.data.scenes);
    final moved = scenes.removeAt(oldIndex);
    scenes.insert(newIndex, moved);
    final before = newIndex + 1 < scenes.length
        ? scenes[newIndex + 1].block
        : null;
    setState(() => _selected = newIndex);
    widget.onSceneReordered(moved.block, before);
  }

  Future<void> _showSceneMenu(
    NavigatorScene scene,
    int index,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_SceneMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: _SceneMenuAction.jump,
          child: _MenuItem(icon: Icons.arrow_forward, label: 'Jump to scene'),
        ),
        const PopupMenuItem(
          value: _SceneMenuAction.copyHeading,
          child: _MenuItem(icon: Icons.copy_outlined, label: 'Copy heading'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SceneMenuAction.moveUp,
          enabled: index > 0 && _filter.text.isEmpty,
          child: const _MenuItem(
            icon: Icons.keyboard_arrow_up,
            label: 'Move scene up',
          ),
        ),
        PopupMenuItem(
          value: _SceneMenuAction.moveDown,
          enabled:
              index + 1 < widget.data.scenes.length && _filter.text.isEmpty,
          child: const _MenuItem(
            icon: Icons.keyboard_arrow_down,
            label: 'Move scene down',
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SceneMenuAction.jump:
        setState(() => _selected = index);
        widget.onSceneSelected(scene.block);
      case _SceneMenuAction.copyHeading:
        await Clipboard.setData(ClipboardData(text: _headingOf(scene)));
      case _SceneMenuAction.moveUp:
        _reorderScenes(index, index - 1);
      case _SceneMenuAction.moveDown:
        _reorderScenes(index, index + 1);
    }
  }

  String _headingOf(NavigatorScene scene) {
    final heading = [
      scene.prefix,
      scene.location,
    ].where((part) => part.isNotEmpty).join(' ');
    final time = scene.timeOfDay;
    return time != null && time.isNotEmpty ? '$heading - $time' : heading;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = context.colours;
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
          // A region, not a panel floating over the script: its own surface, and
          // the hairline `editor_page.dart` draws between it and the editor.
          color: colours.surfaceRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'NAVIGATOR',
                        style: TextStyle(
                          color: colours.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('collapse navigator'),
                      tooltip: 'Hide navigator',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onCollapse,
                      icon: const Icon(Icons.chevron_left, size: 18),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: _NavigatorSegmentedControl(
                  section: _section,
                  sceneCount: widget.data.scenes.length,
                  characterCount: widget.data.characters.length,
                  onChanged: _setSection,
                ),
              ),
              Padding(
                // This remains outside the scrolling child below, so filtering
                // is always available even deep into a long scene list.
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: TextField(
                  key: const ValueKey('navigator filter'),
                  controller: _filter,
                  focusNode: _filterFocus,
                  onChanged: _filterChanged,
                  onSubmitted: (_) => _activate(),
                  style: TextStyle(color: colours.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    hintText: _section == _NavigatorSection.scenes
                        ? 'Jump to scene…'
                        : 'Find character…',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    suffixIcon: _filter.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear filter',
                            onPressed: () {
                              _filter.clear();
                              _filterChanged('');
                              _filterFocus.requestFocus();
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
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
    if (_section == _NavigatorSection.scenes && _filter.text.isEmpty) {
      return ReorderableListView.builder(
        scrollController: _scroll,
        buildDefaultDragHandles: false,
        itemExtent: _rowExtent,
        itemCount: widget.data.scenes.length,
        onReorderItem: _reorderScenes,
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            color: context.colours.surfaceOverlay,
            elevation: 2 * animation.value,
            child: child,
          ),
          child: child,
        ),
        itemBuilder: (context, index) {
          final scene = widget.data.scenes[index];
          return KeyedSubtree(
            key: ValueKey('reorder scene ${scene.block}'),
            child: _sceneRow(theme, scene, index, reorderable: true),
          );
        },
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: _rowExtent,
      itemCount: _itemCount,
      itemBuilder: (context, index) => switch (_section) {
        _NavigatorSection.scenes => _sceneRow(
          theme,
          _scenes[index],
          index,
          reorderable: false,
        ),
        _NavigatorSection.characters => _characterRow(
          theme,
          _characters[index],
          index,
        ),
      },
    );
  }

  Widget _sceneRow(
    ThemeData theme,
    NavigatorScene scene,
    int index, {
    required bool reorderable,
  }) {
    final current = scene.block == widget.currentSceneBlock;
    final keyboardSelected = index == _selected;
    final hovered = scene.block == _hoveredScene;
    final focused = scene.block == _focusedScene;
    final showDragHandle = hovered || focused;
    final subtitle = [
      scene.prefix,
      scene.timeOfDay,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    final colours = context.colours;
    final background = current
        ? colours.surfaceOverlay
        : hovered || keyboardSelected
        ? colours.surfaceOverlay.withValues(alpha: 0.58)
        : Colors.transparent;
    final dragHandle = reorderable
        ? ReorderableDragStartListener(
            key: ValueKey('drag scene ${scene.block}'),
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag to reorder',
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: colours.textTertiary,
                  ),
                ),
              ),
            ),
          )
        : Tooltip(
            message: 'Clear search to reorder',
            child: Icon(
              Icons.drag_indicator,
              size: 16,
              color: colours.textTertiary.withValues(alpha: 0.45),
            ),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredScene = scene.block),
      onExit: (_) {
        if (_hoveredScene == scene.block) {
          setState(() => _hoveredScene = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) {
          setState(() => _selected = index);
          _showSceneMenu(scene, index, details.globalPosition);
        },
        child: Material(
          key: ValueKey('navigator scene background ${scene.block}'),
          color: background,
          child: ListTile(
            key: ValueKey('navigator scene ${scene.block}'),
            dense: true,
            minTileHeight: _rowExtent,
            minVerticalPadding: 8,
            horizontalTitleGap: 8,
            contentPadding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
            onFocusChange: (hasFocus) {
              setState(() {
                if (hasFocus) {
                  _focusedScene = scene.block;
                } else if (_focusedScene == scene.block) {
                  _focusedScene = null;
                }
              });
            },
            selected: current,
            shape: Border(
              left: BorderSide(
                color: current ? colours.accent : Colors.transparent,
                width: 2,
              ),
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  key: ValueKey('scene number column ${scene.block}'),
                  width: 30,
                  child: Text(
                    scene.sceneNumber ?? '${index + 1}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colours.textTertiary,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    scene.location.isEmpty ? scene.prefix : scene.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colours.textPrimary,
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Row(
                    children: [
                      const SizedBox(width: 48),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colours.textTertiary,
                            fontSize: 11,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
            trailing: IgnorePointer(
              ignoring: !showDragHandle,
              child: ExcludeSemantics(
                excluding: !showDragHandle,
                child: AnimatedOpacity(
                  key: ValueKey('drag scene ${scene.block} visibility'),
                  opacity: showDragHandle ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: dragHandle,
                ),
              ),
            ),
            onTap: () {
              setState(() => _selected = index);
              widget.onSceneSelected(scene.block);
            },
          ),
        ),
      ),
    );
  }

  Widget _characterRow(
    ThemeData theme,
    NavigatorCharacter character,
    int index,
  ) {
    final keyboardSelected = index == _selected;
    final hovered = character.name == _hoveredCharacter;
    final count = character.occurrences;
    final colours = context.colours;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredCharacter = character.name),
      onExit: (_) {
        if (_hoveredCharacter == character.name) {
          setState(() => _hoveredCharacter = null);
        }
      },
      child: Material(
        color: hovered || keyboardSelected
            ? colours.surfaceOverlay.withValues(alpha: 0.58)
            : Colors.transparent,
        child: ListTile(
          key: ValueKey('navigator character ${character.name}'),
          dense: true,
          minTileHeight: _rowExtent,
          minVerticalPadding: 8,
          horizontalTitleGap: 8,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: const SizedBox(
            width: 30,
            child: Icon(Icons.person_outline, size: 16),
          ),
          title: Text(
            character.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colours.textPrimary, fontSize: 13),
          ),
          subtitle: Text(
            '$count ${count == 1 ? 'occurrence' : 'occurrences'}',
            style: TextStyle(color: colours.textTertiary, fontSize: 11),
          ),
          onTap: () {
            setState(() => _selected = index);
            widget.onCharacterSelected(character);
          },
        ),
      ),
    );
  }
}

enum _NavigatorSection { scenes, characters }

enum _SceneMenuAction { jump, copyHeading, moveUp, moveDown }

class _MoveNavigatorIntent extends Intent {
  const _MoveNavigatorIntent(this.delta);

  final int delta;
}

class _ActivateNavigatorIntent extends Intent {
  const _ActivateNavigatorIntent();
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)],
  );
}

class _NavigatorSegmentedControl extends StatelessWidget {
  const _NavigatorSegmentedControl({
    required this.section,
    required this.sceneCount,
    required this.characterCount,
    required this.onChanged,
  });

  final _NavigatorSection section;
  final int sceneCount;
  final int characterCount;
  final ValueChanged<_NavigatorSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    const radius = BorderRadius.all(Radius.circular(8));
    return Semantics(
      container: true,
      label: 'Navigator section',
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: colours.surface,
          borderRadius: radius,
          border: Border.all(color: colours.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: section == _NavigatorSection.scenes
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: DecoratedBox(
                    key: const ValueKey('navigator segment indicator'),
                    decoration: BoxDecoration(
                      color: colours.surfaceOverlay,
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _Segment(
                    label: 'Scenes',
                    count: sceneCount,
                    selected: section == _NavigatorSection.scenes,
                    onTap: () => onChanged(_NavigatorSection.scenes),
                  ),
                ),
                Expanded(
                  child: _Segment(
                    label: 'Characters',
                    count: characterCount,
                    selected: section == _NavigatorSection.characters,
                    onTap: () => onChanged(_NavigatorSection.characters),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: AnimatedDefaultTextStyle(
                  key: ValueKey('navigator $label label style'),
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    color: selected
                        ? colours.textPrimary
                        : colours.textTertiary,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                key: ValueKey('navigator $label count style'),
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: colours.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
                child: Text('$count'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
