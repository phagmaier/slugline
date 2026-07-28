import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/commands.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/element_bar.dart';
import 'package:slugline/editor/find_bar.dart';
import 'package:slugline/editor/navigator_sidebar.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/editor/pagination_debug_dialog.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/title_page_dialog.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/library/backups_dialog.dart';
import 'package:slugline/library/save_dialogs.dart';

/// The editor, the two panels that can sit over it, the element bar, and — from
/// Phase 4 — everything that keeps the file in step with what is on screen.
///
/// The panels are children of this page rather than routes or dialogs. §Phase 3
/// requires that Escape dismisses whichever is open "and never loses text", and
/// the only way to be sure of that is for the same widget to own both the panel
/// and the surface underneath it: closing one is `setState`, and the document is
/// not involved at all.
///
/// Phase 4 adds one more thing this page owns: **the autosave suppressions.**
/// §Phase 4 says autosave "never runs while a modal is open or during an active
/// IME composition", and this is the only object that can see both. Every
/// suppression is paired with its release in a `try`/`finally`, because a save
/// held off by a dialog that threw would be a save that never happens.
class EditorPage extends StatefulWidget {
  const EditorPage({
    required this.controller,
    this.autosave,
    this.saveStatus,
    this.initialScrollRow = 0,
    this.navigatorVisible = false,
    this.textSize = 15,
    this.distractionFree = false,
    this.initialPageSetup = const PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      debugLinesPerPage: null,
    ),
    this.onNavigatorVisibilityChanged,
    this.onOpenPreferences,
    this.onShowShortcuts,
    this.onDistractionFreeChanged,
    this.onTextSizeChanged,
    this.onClosed,
    this.title,
    super.key,
  });

  final EditorController controller;

  /// Phase 4's autosave driver. Null in a widget test that is only interested in
  /// typing, which is how every Phase 2 and 3 test still runs unchanged.
  final AutosaveDriver? autosave;

  final SaveStatus? saveStatus;

  /// The visual row parked for this script in the previous session.
  final int initialScrollRow;

  /// §Phase 8's persisted global sidebar state.
  final bool navigatorVisible;
  final double textSize;
  final bool distractionFree;
  final PageSetup initialPageSetup;
  final Future<void> Function(bool visible)? onNavigatorVisibilityChanged;
  final Future<void> Function()? onOpenPreferences;
  final Future<void> Function()? onShowShortcuts;
  final Future<void> Function(bool enabled)? onDistractionFreeChanged;
  final Future<void> Function(int size)? onTextSizeChanged;

  /// Back to the library. Null when the editor is the whole application, which
  /// is what a test pumping this page directly gets.
  final Future<void> Function()? onClosed;

  final String? title;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  /// At most one panel is open. Two overlapping panels would both want Escape and
  /// both want the focus, and neither question has a good answer.
  _Panel _panel = _Panel.none;

  /// The surface's focus node lives here so that closing a panel hands the
  /// keyboard back explicitly.
  ///
  /// Flutter's focus manager would restore it anyway — removing the panel returns
  /// the scope's focus to its previous child — but that is a fallback, not a
  /// contract, and "can the writer type?" is not a question to leave to one. The
  /// tests in `test/editor/` assert the outcome rather than the mechanism.
  final FocusNode _editorFocus = FocusNode(debugLabel: 'editor surface');
  final GlobalKey<NavigatorSidebarState> _navigatorKey =
      GlobalKey<NavigatorSidebarState>();

  int _externalChangeSerial = 0;
  int _externalChangesActive = 0;
  Completer<void>? _externalChangesSettled;
  Timer? _navigatorRefresh;
  PageIndicator? _pageIndicator;
  late NavigatorView _navigator;
  late bool _navigatorVisible;
  int? _currentSceneBlock;
  int _knownDocumentRevision = 0;
  final Map<int, int?> _sceneAtBlock = {};
  bool _ignoreScrollHighlightThisFrame = false;

  DocumentCore get _core => widget.controller.core;

  @override
  void initState() {
    super.initState();
    _navigatorVisible = widget.navigatorVisible;
    _navigator = _core.navigator();
    _knownDocumentRevision = widget.controller.documentRevision;
    _rebuildSceneMap();
    _currentSceneBlock = _sceneAtBlock[widget.controller.selection.focus.block];
    widget.controller.addListener(_onControllerChanged);
    _createPageIndicator();
  }

  @override
  void didUpdateWidget(EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _navigatorRefresh?.cancel();
      _navigator = _core.navigator();
      _knownDocumentRevision = widget.controller.documentRevision;
      _rebuildSceneMap();
      _currentSceneBlock =
          _sceneAtBlock[widget.controller.selection.focus.block];
      _pageIndicator?.dispose();
      _createPageIndicator();
    } else if (oldWidget.initialPageSetup != widget.initialPageSetup) {
      _pageIndicator?.updateSetup(widget.initialPageSetup);
    }
  }

  @override
  void dispose() {
    _navigatorRefresh?.cancel();
    _pageIndicator?.dispose();
    widget.controller.removeListener(_onControllerChanged);
    _editorFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _ignoreScrollHighlightThisFrame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ignoreScrollHighlightThisFrame = false;
    });
    if (_knownDocumentRevision != widget.controller.documentRevision) {
      _knownDocumentRevision = widget.controller.documentRevision;
      if (_navigatorVisible) {
        _navigatorRefresh?.cancel();
        _navigatorRefresh = Timer(
          const Duration(milliseconds: 120),
          _refreshNavigator,
        );
      }
    }
    final current = _sceneAtBlock[widget.controller.selection.focus.block];
    if (current != _currentSceneBlock && mounted) {
      setState(() => _currentSceneBlock = current);
    }
  }

  void _refreshNavigator() {
    _navigatorRefresh = null;
    final navigator = _core.navigator();
    if (!mounted) return;
    setState(() {
      _navigator = navigator;
      _rebuildSceneMap();
      _currentSceneBlock =
          _sceneAtBlock[widget.controller.selection.focus.block];
    });
  }

  void _rebuildSceneMap() {
    _sceneAtBlock.clear();
    final scenes = _navigator.scenes.map((scene) => scene.block).toSet();
    int? current;
    for (final block in widget.controller.blocks) {
      if (scenes.contains(block.id)) current = block.id;
      _sceneAtBlock[block.id] = current;
    }
  }

  void _setNavigatorVisible(bool visible) {
    if (_navigatorVisible == visible) return;
    setState(() => _navigatorVisible = visible);
    unawaited(widget.onNavigatorVisibilityChanged?.call(visible));
    if (visible) _refreshNavigator();
  }

  void _showNavigatorSearch() {
    _setNavigatorVisible(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigatorKey.currentState?.focusSceneSearch();
    });
  }

  void _jumpToScene(int block) {
    if (!widget.controller.jumpToBlock(block)) {
      _refreshNavigator();
      return;
    }
    _editorFocus.requestFocus();
  }

  void _jumpToCharacter(NavigatorCharacter character) {
    if (character.blocks.isEmpty) return;
    final order = <int, int>{
      for (var i = 0; i < widget.controller.blocks.length; i++)
        widget.controller.blocks[i].id: i,
    };
    final caretIndex = order[widget.controller.selection.focus.block] ?? -1;
    final target = character.blocks.firstWhere(
      (block) => (order[block] ?? -1) > caretIndex,
      orElse: () => character.blocks.first,
    );
    if (!widget.controller.jumpToBlock(target)) {
      _refreshNavigator();
      return;
    }
    _editorFocus.requestFocus();
  }

  void _onScrolled(int row) {
    _core.setScrollRow(row);
    _pageIndicator?.updateVisibleRow(row);
    if (_ignoreScrollHighlightThisFrame) return;
    final current = _sceneAtBlock[widget.controller.blockAtRow(row).id];
    if (current != _currentSceneBlock && mounted) {
      setState(() => _currentSceneBlock = current);
    }
  }

  void _show(_Panel panel) {
    if (_panel == panel) return;
    setState(() => _panel = panel);
  }

  void _dismiss() {
    if (_panel == _Panel.none) return;
    setState(() => _panel = _Panel.none);
    _editorFocus.requestFocus();
  }

  // --- saving ----------------------------------------------------------------

  /// Runs [action] with autosave held off, and releases the hold whatever
  /// happens.
  ///
  /// §Phase 4: autosave "never runs while a modal is open". A modal that owns
  /// the screen while a save rewrites the file underneath it is a race the
  /// writer would experience as their dialog answering a question about a
  /// different document.
  Future<T> withModal<T>(Future<T> Function() action) async {
    widget.autosave?.suppress('modal');
    try {
      return await action();
    } finally {
      widget.autosave?.release('modal');
    }
  }

  /// Ctrl+S, and the command palette's Save.
  Future<void> save({bool forcePath = false}) async {
    await _saveWithOutcome(forcePath: forcePath);
  }

  Future<SaveOutcome> _saveWithOutcome({
    bool forcePath = false,
    bool waitForExternalChange = true,
  }) async {
    if (waitForExternalChange) {
      await _externalChangesSettled?.future;
    }
    widget.saveStatus?.savingStarted();
    final outcome = await withModal(
      () => saveWithDialogs(context, _core, forcePath: forcePath),
    );
    widget.saveStatus?.record(outcome);
    return outcome;
  }

  Future<void> _showBackups() =>
      withModal(() => BackupsDialog.show(context, _core));

  /// §Phase 7's title page. An ordinary modal, so autosave is held off while it
  /// is open like every other one.
  Future<void> _showTitlePage() =>
      withModal(() => TitlePageDialog.show(context, _core));

  Future<void> _showSpelling() =>
      withModal(() => SpellDialog.show(context, widget.controller));

  /// §Phase 7's preview-before-export. Null when the core cannot paginate,
  /// which is every widget test driving the editor through the double: a
  /// command that would open a window with nothing in it is not offered.
  ScreenplayOutput? get _output =>
      _core is ScreenplayOutput ? _core as ScreenplayOutput : null;

  void _createPageIndicator() {
    if (_output case final output?) {
      _pageIndicator = PageIndicator(
        controller: widget.controller,
        output: output,
        setup: widget.initialPageSetup,
        initialRow: widget.initialScrollRow,
      );
      unawaited(_pageIndicator!.refresh());
    }
  }

  Future<void> _showPreview() async {
    if (_output case final output?) {
      await withModal(
        () => ExportDialog.show(
          context,
          _core,
          output,
          initialSetup: widget.initialPageSetup,
        ),
      );
    }
  }

  /// Called when the file changed on disk under this document.
  ///
  /// §Phase 4's rule exactly: unmodified in the app → reload silently; modified
  /// → prompt. The silence in the first case is deliberate. A writer who has
  /// changed nothing has nothing to lose and nothing to decide, and a dialog
  /// there would only teach them to dismiss dialogs.
  Future<void> handleExternalChange() async {
    final suppression = 'external-change-${_externalChangeSerial++}';
    _externalChangesActive += 1;
    _externalChangesSettled ??= Completer<void>();
    widget.autosave?.suppress(suppression);
    try {
      await _handleExternalChange();
    } finally {
      widget.autosave?.release(suppression);
      _externalChangesActive -= 1;
      if (_externalChangesActive == 0) {
        final settled = _externalChangesSettled;
        _externalChangesSettled = null;
        settled?.complete();
      }
    }
  }

  Future<void> _handleExternalChange() async {
    final state = await _core.externalChange();
    if (state == null) return;
    final (dirty, differs) = state;
    if (!differs) return;
    if (!dirty) {
      if (!await _core.reload(onlyIfClean: true)) return;
      widget.controller.reloadFromCore();
      widget.saveStatus?.refresh();
      return;
    }
    if (!mounted) return;
    while (mounted) {
      final choice = await withModal(
        () => showExternalChange(context, _core.path ?? ''),
      );
      switch (choice) {
        case ExternalChangeChoice.takeTheirs:
          await _core.reload();
          widget.controller.reloadFromCore();
          widget.saveStatus?.refresh();
          return;
        case ExternalChangeChoice.saveAs:
          final outcome = await _saveWithOutcome(
            forcePath: true,
            waitForExternalChange: false,
          );
          if (outcome is SaveOutcome_Saved) return;
          // The chooser was cancelled or the write failed. The original file
          // is still conflicted, so no queued save may target it yet.
          continue;
        case ExternalChangeChoice.keepMine:
          // "Keep mine leaves the file alone until you next save", which is
          // what the dialog promises — so the core is told that this version of
          // the file has been seen and decided about. Without that the next
          // save would refuse it (the save path checks the file it replaces,
          // watcher or no watcher) and the writer would be answering this same
          // dialog for ever with no way to write their text.
          await _core.acceptDiskState();
          widget.saveStatus?.refresh();
          return;
        case null:
          return;
      }
    }
  }

  /// Leaving this script. §10: never silently discard unsaved changes.
  ///
  /// Returns whether the caller may proceed.
  Future<bool> confirmClose() async {
    if (!_core.dirty) return true;
    final choice = await withModal(
      () => showUnsavedChanges(context, widget.title ?? 'this script'),
    );
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        return true;
      case UnsavedChoice.save:
        final outcome = await withModal(() => saveWithDialogs(context, _core));
        widget.saveStatus?.record(outcome);
        // A save the writer abandoned is not consent to lose the work.
        return outcome is SaveOutcome_Saved;
    }
  }

  KeyEventResult _onPageKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(widget.onDistractionFreeChanged?.call(!widget.distractionFree));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      unawaited(widget.onShowShortcuts?.call());
      return KeyEventResult.handled;
    }
    if (!keys.isControlPressed) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyS when keys.isShiftPressed:
        unawaited(save(forcePath: true));
      case LogicalKeyboardKey.keyS:
        unawaited(save());
      case LogicalKeyboardKey.keyP when _output != null:
        unawaited(_showPreview());
      case LogicalKeyboardKey.keyJ:
        _showNavigatorSearch();
      case LogicalKeyboardKey.comma:
        unawaited(widget.onOpenPreferences?.call());
      case LogicalKeyboardKey.equal || LogicalKeyboardKey.numpadAdd:
        unawaited(
          widget.onTextSizeChanged?.call(
            (widget.textSize.round() + 1).clamp(12, 24),
          ),
        );
      case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract:
        unawaited(
          widget.onTextSizeChanged?.call(
            (widget.textSize.round() - 1).clamp(12, 24),
          ),
        );
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final navigatorWidth = (MediaQuery.sizeOf(context).width * 0.34).clamp(
      176.0,
      288.0,
    );
    return Focus(
      // Above the surface, so the surface still sees every editing key first and
      // only what it ignores reaches here.
      onKeyEvent: (_, event) => _onPageKey(event),
      child: Scaffold(
        appBar: widget.onClosed == null || widget.distractionFree
            ? null
            : AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to the library',
                  onPressed: () async {
                    if (await confirmClose() && context.mounted) {
                      await widget.onClosed?.call();
                    }
                  },
                ),
                title: Text(widget.title ?? 'Untitled'),
                actions: [
                  if (kDebugMode && _output != null)
                    IconButton(
                      icon: const Icon(Icons.view_agenda_outlined),
                      tooltip: 'Pagination debug',
                      onPressed: () => unawaited(
                        withModal(
                          () => PaginationDebugDialog.show(context, _output!),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted),
                    tooltip: 'Jump to scene (Ctrl+J)',
                    onPressed: _showNavigatorSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.article_outlined),
                    tooltip: 'Title page',
                    onPressed: () => unawaited(_showTitlePage()),
                  ),
                  IconButton(
                    key: const ValueKey('spell settings'),
                    icon: const Icon(Icons.spellcheck),
                    tooltip: 'Spell checking',
                    onPressed: () => unawaited(_showSpelling()),
                  ),
                  if (_output != null)
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'Preview and export (Ctrl+P)',
                      onPressed: () => unawaited(_showPreview()),
                    ),
                  IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: 'Previous versions',
                    onPressed: _showBackups,
                  ),
                  IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'Save (Ctrl+S)',
                    onPressed: () => unawaited(save()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_outlined),
                    tooltip: 'Keyboard shortcuts (F1)',
                    onPressed: widget.onShowShortcuts,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Preferences (Ctrl+,)',
                    onPressed: widget.onOpenPreferences,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: Row(
          children: [
            if (_navigatorVisible && !widget.distractionFree) ...[
              SizedBox(
                width: navigatorWidth,
                child: NavigatorSidebar(
                  key: _navigatorKey,
                  data: _navigator,
                  currentSceneBlock: _currentSceneBlock,
                  onSceneSelected: _jumpToScene,
                  onCharacterSelected: _jumpToCharacter,
                  onCollapse: () => _setNavigatorVisible(false),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: EditorSurface(
                                  controller: widget.controller,
                                  textSize: widget.textSize,
                                  initialScrollRow: widget.initialScrollRow,
                                  focusNode: _editorFocus,
                                  // The surface has the focus, so it sees these keys first and
                                  // hands the ones that are not editing back up here.
                                  onOpenPalette: () => _show(_Panel.palette),
                                  onOpenFind: () => _show(_Panel.find),
                                  onEscape: _dismiss,
                                  // §Phase 4: no autosave during a composition. A save that
                                  // serialises the document mid-composition would write text
                                  // the platform still considers provisional.
                                  onComposingChanged: (composing) => composing
                                      ? widget.autosave?.suppress('composing')
                                      : widget.autosave?.release('composing'),
                                  onScrolled: _onScrolled,
                                ),
                              ),
                              if (!_navigatorVisible && !widget.distractionFree)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: IconButton.filledTonal(
                                    key: const ValueKey('show navigator'),
                                    tooltip: 'Show navigator (Ctrl+J)',
                                    onPressed: () => _setNavigatorVisible(true),
                                    icon: const Icon(
                                      Icons.format_list_bulleted,
                                    ),
                                  ),
                                ),
                              if (_panel == _Panel.find)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: FindBar(
                                    controller: widget.controller,
                                    onDismiss: _dismiss,
                                  ),
                                ),
                              if (_panel == _Panel.palette)
                                Positioned.fill(
                                  child: CommandPalette(
                                    commands: editorCommands(
                                      controller: widget.controller,
                                      openFind: () => _show(_Panel.find),
                                      openNavigator: _showNavigatorSearch,
                                      save: () => unawaited(save()),
                                      saveAs: () =>
                                          unawaited(save(forcePath: true)),
                                      showBackups: () =>
                                          unawaited(_showBackups()),
                                      editTitlePage: () =>
                                          unawaited(_showTitlePage()),
                                      previewAndExport: _output == null
                                          ? null
                                          : () => unawaited(_showPreview()),
                                    ),
                                    onDismiss: _dismiss,
                                  ),
                                ),
                              if (widget.distractionFree)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton.filledTonal(
                                    key: const ValueKey(
                                      'leave distraction free',
                                    ),
                                    tooltip:
                                        'Leave distraction-free mode (F11)',
                                    onPressed: () => unawaited(
                                      widget.onDistractionFreeChanged?.call(
                                        false,
                                      ),
                                    ),
                                    icon: const Icon(Icons.fullscreen_exit),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!widget.distractionFree)
                          ElementBar(
                            controller: widget.controller,
                            saveStatus: widget.saveStatus,
                            pageIndicator: _pageIndicator,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Panel { none, find, palette }
