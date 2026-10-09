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
import 'package:slugline/editor/go_to_page_dialog.dart';
import 'package:slugline/editor/navigator_sidebar.dart';
import 'package:slugline/editor/native_input.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/editor/pagination_debug_dialog.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/editor/spell_dialog.dart';
import 'package:slugline/editor/title_page_dialog.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/preview/preview_view.dart';
import 'package:slugline/library/backups_dialog.dart';
import 'package:slugline/library/save_dialogs.dart';
import 'package:slugline/theme.dart';

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
    this.pageView = true,
    this.initialPageSetup = const PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    ),
    this.onNavigatorVisibilityChanged,
    this.onOpenPreferences,
    this.onShowShortcuts,
    this.onDistractionFreeChanged,
    this.onTextSizeChanged,
    this.onPageViewChanged,
    this.onClosed,
    this.onNewScript,
    this.onOpenScript,
    this.onImportFdx,
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

  /// §Phase 10's `page_view` preference: sheets of paper rather than one
  /// continuous column, and the default. Display only — it changes nothing the
  /// paginator is asked, and `appearance_prefs_dont_affect_pagination` holds it
  /// to that.
  final bool pageView;
  final PageSetup initialPageSetup;
  final Future<void> Function(bool visible)? onNavigatorVisibilityChanged;
  final Future<void> Function()? onOpenPreferences;
  final Future<void> Function()? onShowShortcuts;
  final Future<void> Function(bool enabled)? onDistractionFreeChanged;
  final Future<void> Function(int size)? onTextSizeChanged;
  final Future<void> Function(bool enabled)? onPageViewChanged;

  /// Back to the library. Null when the editor is the whole application, which
  /// is what a test pumping this page directly gets.
  final Future<void> Function()? onClosed;
  final Future<void> Function()? onNewScript;
  final Future<void> Function()? onOpenScript;
  final Future<void> Function()? onImportFdx;

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
  final GlobalKey<EditorSurfaceState> _surfaceKey =
      GlobalKey<EditorSurfaceState>();
  final GlobalKey<NavigatorSidebarState> _navigatorKey =
      GlobalKey<NavigatorSidebarState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _compactLayout = false;

  int _externalChangeSerial = 0;
  int _modalSerial = 0;
  bool _scriptActionActive = false;
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
  Timer? _scrollHighlightDebounce;
  Timer? _navigatorSuppressionTimer;
  bool _suppressNavigatorScroll = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editorFocus.requestFocus();
    });
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
    _scrollHighlightDebounce?.cancel();
    _navigatorSuppressionTimer?.cancel();
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
      if (_navigatorVisible ||
          (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
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
      _autoScrollNavigatorToCurrentScene();
    }
  }

  void _refreshNavigator() {
    _navigatorRefresh?.cancel();
    _navigatorRefresh = null;
    final navigator = _core.navigator();
    if (!mounted) return;
    setState(() {
      _navigator = navigator;
      _rebuildSceneMap();
      _currentSceneBlock =
          _sceneAtBlock[widget.controller.selection.focus.block];
    });
    _autoScrollNavigatorToCurrentScene();
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
    if (_compactLayout) {
      if (visible) {
        _refreshNavigator();
        _scaffoldKey.currentState?.openDrawer();
      } else {
        _scaffoldKey.currentState?.closeDrawer();
      }
      return;
    }
    if (_navigatorVisible == visible) return;
    setState(() => _navigatorVisible = visible);
    unawaited(widget.onNavigatorVisibilityChanged?.call(visible));
    if (visible) _refreshNavigator();
  }

  void _autoScrollNavigatorToCurrentScene() {
    if (_suppressNavigatorScroll) return;
    final scene = _currentSceneBlock;
    if (scene == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigatorKey.currentState?.scrollToSceneBlock(scene);
    });
  }

  void _showNavigatorSearch() {
    _setNavigatorVisible(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigatorKey.currentState?.focusSceneSearch();
    });
  }

  void _jumpToScene(int block) {
    _scaffoldKey.currentState?.closeDrawer();
    _suppressNavigatorScroll = true;
    _navigatorSuppressionTimer?.cancel();
    if (!widget.controller.jumpToBlock(block)) {
      _suppressNavigatorScroll = false;
      _refreshNavigator();
      return;
    }
    _editorFocus.requestFocus();
    _navigatorSuppressionTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) _suppressNavigatorScroll = false;
    });
  }

  void _reorderScene(int sceneBlock, int? beforeSceneBlock) {
    widget.controller.moveScene(sceneBlock, before: beforeSceneBlock);
    _refreshNavigator();
  }

  void _jumpToCharacter(NavigatorCharacter character) {
    _scaffoldKey.currentState?.closeDrawer();
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
    _suppressNavigatorScroll = true;
    _navigatorSuppressionTimer?.cancel();
    if (!widget.controller.jumpToBlock(target)) {
      _suppressNavigatorScroll = false;
      _refreshNavigator();
      return;
    }
    _editorFocus.requestFocus();
    _navigatorSuppressionTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) _suppressNavigatorScroll = false;
    });
  }

  void _onScrolled(int row) {
    _core.setScrollRow(row);
    _pageIndicator?.updateVisibleRow(row);
    _suppressNavigatorScroll = false;
    _navigatorSuppressionTimer?.cancel();
    if (_ignoreScrollHighlightThisFrame) return;
    _scrollHighlightDebounce?.cancel();
    _scrollHighlightDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || _ignoreScrollHighlightThisFrame) return;
      final current = _sceneAtBlock[widget.controller.blockAtRow(row).id];
      if (current != null && current != _currentSceneBlock) {
        setState(() => _currentSceneBlock = current);
        _autoScrollNavigatorToCurrentScene();
      }
    });
  }

  void _show(_Panel panel) {
    if (_panel == panel) return;
    _scaffoldKey.currentState?.closeDrawer();
    // Before the bar exists, so that it opens on this search: the selection's
    // text if there is one to take, the last query otherwise.
    if (panel == _Panel.find) widget.controller.startFind();
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
    // Each invocation owns its hold, including overlapping save dialogs.
    final autosave = widget.autosave;
    final suppression = 'modal-${_modalSerial++}';
    autosave?.suppress(suppression);
    try {
      return await action();
    } finally {
      autosave?.release(suppression);
    }
  }

  /// Ctrl+S, and the command palette's Save.
  Future<void> save({bool forcePath = false}) async {
    final controller = widget.controller;
    await NativeInput.flush();
    if (!mounted || widget.controller != controller) return;
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

  Future<void> _showBackups() => withModal(() async {
    final controller = widget.controller;
    final restored = await BackupsDialog.show(context, controller.core);
    if (!restored || !mounted || widget.controller != controller) return;
    controller.reloadFromCore();
    widget.saveStatus?.refresh();
  });

  /// §Phase 7's title page. An ordinary modal, so autosave is held off while it
  /// is open like every other one.
  Future<void> _showTitlePage() => withModal(
    () => TitlePageDialog.show(
      context,
      _core,
      onCommitted: () => _pageIndicator?.invalidate(),
    ),
  );

  Future<void> _showSpelling() =>
      withModal(() => SpellDialog.show(context, widget.controller));

  Future<void> _openPreferences() async {
    if (widget.onOpenPreferences case final action?) await withModal(action);
  }

  Future<void> _showShortcuts() async {
    if (widget.onShowShortcuts case final action?) await withModal(action);
  }

  Future<void> _showGoToPage() async {
    final indicator = _pageIndicator;
    if (indicator == null) return;
    final controller = widget.controller;
    _dismiss();
    _scaffoldKey.currentState?.closeDrawer();
    controller.dismissCompletions();
    final page = await withModal(() => GoToPageDialog.show(context, indicator));
    if (!mounted ||
        widget.controller != controller ||
        _pageIndicator != indicator) {
      return;
    }
    final position = page == null ? null : indicator.positionForPage(page);
    if (position != null) {
      controller.setSelection(DocSelection(anchor: position, focus: position));
      _surfaceKey.currentState?.revealPageTarget(documentStart: page == 1);
    }
    _editorFocus.requestFocus();
  }

  void _changeTextSize(int delta) {
    final size = (widget.textSize.round() + delta).clamp(12, 24);
    if (size != widget.textSize.round()) {
      unawaited(widget.onTextSizeChanged?.call(size));
    }
  }

  Future<void> _showPaginationDebug() =>
      withModal(() => PaginationDebugDialog.show(context, _output!));

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
      final caret = _caretInOutput();
      await withModal(
        () => ExportDialog.show(
          context,
          _core,
          output,
          initialSetup: widget.initialPageSetup,
          opensAt: caret,
        ),
      );
    }
  }

  /// Where the caret is, in the terms a pagination names a place in: its block
  /// and which wrapped line of it, with the blocks above for a caret in one
  /// that prints nothing.
  ///
  /// Not a page number. The status line's is the page of the top visible line,
  /// from a snapshot that trails the text; the preview finds this place in the
  /// pagination it is about to draw.
  PreviewAnchor _caretInOutput() {
    final controller = widget.controller;
    final blocks = controller.blocks;
    final anchor = controller.pageAnchorAtRow(controller.caretRow);
    final index = blocks.indexWhere((block) => block.id == anchor.block);
    return PreviewAnchor(
      block: anchor.block,
      sourceLine: anchor.sourceLine,
      earlierBlocks: [
        for (var earlier = index - 1; earlier >= 0; earlier--)
          blocks[earlier].id,
      ],
    );
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
        // The editor remains usable while the snapshot is written. A successful
        // save is permission to close only if it includes the latest edits.
        // A save the writer abandoned is not consent to lose the work either.
        return outcome is SaveOutcome_Saved && !_core.dirty;
    }
  }

  KeyEventResult _onPageKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_scriptActionActive) return KeyEventResult.handled;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(widget.onDistractionFreeChanged?.call(!widget.distractionFree));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      unawaited(_showShortcuts());
      return KeyEventResult.handled;
    }
    if (!keys.isControlPressed) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyK:
        _show(_Panel.palette);
      case LogicalKeyboardKey.keyN when widget.onNewScript != null:
        unawaited(_runScriptAction(widget.onNewScript!));
      case LogicalKeyboardKey.keyO when widget.onOpenScript != null:
        unawaited(_runScriptAction(widget.onOpenScript!));
      case LogicalKeyboardKey.keyW when widget.onClosed != null:
        unawaited(_runScriptAction(_closeScript));
      case LogicalKeyboardKey.keyS when keys.isShiftPressed:
        unawaited(save(forcePath: true));
      case LogicalKeyboardKey.keyS:
        unawaited(save());
      case LogicalKeyboardKey.keyP when _output != null:
        unawaited(_showPreview());
      case LogicalKeyboardKey.keyJ:
        _showNavigatorSearch();
      case LogicalKeyboardKey.keyL when _pageIndicator != null:
        unawaited(_showGoToPage());
      case LogicalKeyboardKey.comma:
        unawaited(_openPreferences());
      case LogicalKeyboardKey.equal || LogicalKeyboardKey.numpadAdd:
        _changeTextSize(1);
      case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract:
        _changeTextSize(-1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _closeScript() async {
    if (await confirmClose() && mounted) await widget.onClosed?.call();
  }

  Future<void> _runScriptAction(Future<void> Function() action) async {
    if (_scriptActionActive) return;
    setState(() => _scriptActionActive = true);
    _dismiss();
    widget.controller.dismissCompletions();
    _scaffoldKey.currentState?.closeDrawer();
    try {
      await withModal(action);
    } finally {
      if (mounted) {
        setState(() => _scriptActionActive = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _editorFocus.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: _scriptActionActive,
    child: _buildEditor(context, MediaQuery.sizeOf(context).width),
  );

  Widget _buildEditor(BuildContext context, double width) {
    _compactLayout = width < 900;
    final colours = context.colours;
    const navigatorWidth = 288.0;
    // The top bar carries the navigator toggle. When there is no top bar — the
    // editor pumped as the whole application, which is what a widget test gets —
    // something else has to, or hiding the navigator would hide the only way to
    // bring it back. Ctrl+J always works; a keystroke nobody can see is not a
    // way back.
    final hasTopBar = widget.onClosed != null && !widget.distractionFree;
    return FocusScope(
      // Desktop fields unfocus to their nearest scope. Keep that inside the
      // page's shortcut boundary; children still see editing keys first.
      debugLabel: 'editor page',
      descendantsAreFocusable: !_scriptActionActive,
      onKeyEvent: (_, event) => _onPageKey(event),
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _compactLayout && !widget.distractionFree
            ? Drawer(width: 288, child: SafeArea(child: _navigatorSidebar()))
            : null,
        onDrawerChanged: (open) {
          if (!open && _panel == _Panel.none) _editorFocus.requestFocus();
        },
        appBar: widget.onClosed == null || widget.distractionFree
            ? null
            : AppBar(
                leadingWidth: 44,
                leading: _BarButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back to the library (Ctrl+W)',
                  onPressed: () => unawaited(_runScriptAction(_closeScript)),
                ),
                titleSpacing: 4,
                title: _ScriptTitle(
                  name: widget.title ?? 'Untitled',
                  status: widget.saveStatus,
                ),
                actions: [
                  // Three clusters, in the order a writer reaches for them:
                  // what is in the script, what to do with the script, and
                  // what the application is set to. Eight buttons in a row of
                  // identical weight is a row with no shape — the eye has to
                  // read every tooltip to find anything, which is the same as
                  // having no toolbar. The hairlines are the shape.
                  _BarButton(
                    key: const ValueKey('toggle navigator'),
                    icon: Icons.format_list_bulleted,
                    tooltip: !_compactLayout && _navigatorVisible
                        ? 'Hide the navigator (Ctrl+J)'
                        : 'Show the navigator (Ctrl+J)',
                    selected: !_compactLayout && _navigatorVisible,
                    onPressed: () => _setNavigatorVisible(
                      _compactLayout || !_navigatorVisible,
                    ),
                  ),
                  _BarButton(
                    key: const ValueKey('open find'),
                    icon: Icons.search,
                    tooltip: 'Find and replace (Ctrl+F)',
                    selected: _panel == _Panel.find,
                    onPressed: () => _show(_Panel.find),
                  ),
                  _BarButton(
                    key: const ValueKey('open commands'),
                    icon: Icons.keyboard_command_key,
                    tooltip: 'Commands (Ctrl+K)',
                    onPressed: () => _show(_Panel.palette),
                  ),
                  const _BarDivider(),
                  if (_output != null)
                    _BarButton(
                      key: const ValueKey('open preview'),
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'Preview and export (Ctrl+P)',
                      onPressed: () => unawaited(_showPreview()),
                    ),
                  _OverflowMenu(
                    onTitlePage: () => unawaited(_showTitlePage()),
                    onSpelling: () => unawaited(_showSpelling()),
                    onBackups: () => unawaited(_showBackups()),
                    onSave: () => unawaited(save()),
                    onSaveAs: () => unawaited(save(forcePath: true)),
                    onImportFdx: widget.onImportFdx == null
                        ? null
                        : () =>
                              unawaited(_runScriptAction(widget.onImportFdx!)),
                    onShortcuts: widget.onShowShortcuts == null
                        ? null
                        : _showShortcuts,
                    onPaginationDebug: kDebugMode && _output != null
                        ? () => unawaited(_showPaginationDebug())
                        : null,
                  ),
                  const _BarDivider(),
                  _BarButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Preferences (Ctrl+,)',
                    onPressed: widget.onOpenPreferences == null
                        ? null
                        : _openPreferences,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
        body: Row(
          children: [
            if (!_compactLayout &&
                _navigatorVisible &&
                !widget.distractionFree) ...[
              SizedBox(width: navigatorWidth, child: _navigatorSidebar()),
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
                                  key: _surfaceKey,
                                  controller: widget.controller,
                                  textSize: widget.textSize,
                                  pageView: widget.pageView,
                                  boldSceneHeadings:
                                      widget.initialPageSetup.boldSceneHeadings,
                                  pageIndicator: _pageIndicator,
                                  initialScrollRow: widget.initialScrollRow,
                                  highlightMatches: _panel == _Panel.find,
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
                              if (_panel == _Panel.find)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  left: 8,
                                  bottom: 8,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: SingleChildScrollView(
                                      child: FindBar(
                                        controller: widget.controller,
                                        onDismiss: _dismiss,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_panel == _Panel.palette)
                                Positioned.fill(
                                  child: CommandPalette(
                                    commands: editorCommands(
                                      controller: widget.controller,
                                      newScript: widget.onNewScript == null
                                          ? null
                                          : () => unawaited(
                                              _runScriptAction(
                                                widget.onNewScript!,
                                              ),
                                            ),
                                      openScript: widget.onOpenScript == null
                                          ? null
                                          : () => unawaited(
                                              _runScriptAction(
                                                widget.onOpenScript!,
                                              ),
                                            ),
                                      importFdx: widget.onImportFdx == null
                                          ? null
                                          : () => unawaited(
                                              _runScriptAction(
                                                widget.onImportFdx!,
                                              ),
                                            ),
                                      closeScript: widget.onClosed == null
                                          ? null
                                          : () => unawaited(
                                              _runScriptAction(_closeScript),
                                            ),
                                      openFind: () => _show(_Panel.find),
                                      openNavigator: widget.distractionFree
                                          ? null
                                          : _showNavigatorSearch,
                                      goToPage: _pageIndicator == null
                                          ? null
                                          : () => unawaited(_showGoToPage()),
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
                                      openPreferences:
                                          widget.onOpenPreferences == null
                                          ? null
                                          : () => unawaited(_openPreferences()),
                                      showSpelling: () =>
                                          unawaited(_showSpelling()),
                                      showShortcuts:
                                          widget.onShowShortcuts == null
                                          ? null
                                          : () => unawaited(_showShortcuts()),
                                      toggleNavigator: widget.distractionFree
                                          ? null
                                          : () => _setNavigatorVisible(
                                              _compactLayout ||
                                                  !_navigatorVisible,
                                            ),
                                      navigatorVisible:
                                          !_compactLayout && _navigatorVisible,
                                      toggleDistractionFree:
                                          widget.onDistractionFreeChanged ==
                                              null
                                          ? null
                                          : () => unawaited(
                                              widget.onDistractionFreeChanged!(
                                                !widget.distractionFree,
                                              ),
                                            ),
                                      distractionFree: widget.distractionFree,
                                      togglePageView:
                                          widget.onPageViewChanged == null
                                          ? null
                                          : () => unawaited(
                                              widget.onPageViewChanged!(
                                                !widget.pageView,
                                              ),
                                            ),
                                      pageView: widget.pageView,
                                      increaseTextSize:
                                          widget.onTextSizeChanged != null &&
                                              widget.textSize.round() < 24
                                          ? () => _changeTextSize(1)
                                          : null,
                                      decreaseTextSize:
                                          widget.onTextSizeChanged != null &&
                                              widget.textSize.round() > 12
                                          ? () => _changeTextSize(-1)
                                          : null,
                                      showPaginationDebug:
                                          kDebugMode && _output != null
                                          ? () => unawaited(
                                              _showPaginationDebug(),
                                            )
                                          : null,
                                    ),
                                    onDismiss: _dismiss,
                                  ),
                                ),
                              if ((_compactLayout || !_navigatorVisible) &&
                                  !widget.distractionFree &&
                                  !hasTopBar)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: IconButton.filledTonal(
                                    key: const ValueKey('show navigator'),
                                    tooltip: 'Show navigator (Ctrl+J)',
                                    style: _floatingButton(colours),
                                    onPressed: () => _setNavigatorVisible(true),
                                    icon: const Icon(
                                      Icons.format_list_bulleted,
                                    ),
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
                                    style: _floatingButton(colours),
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
                            sceneCount: _navigator.scenes.length,
                            textSize: widget.textSize,
                            onTextSizeChanged: widget.onTextSizeChanged,
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

  Widget _navigatorSidebar() {
    Widget sidebar() => NavigatorSidebar(
      key: _navigatorKey,
      data: _navigator,
      scenePagination: _pageIndicator?.scenePagination ?? const {},
      currentSceneBlock: _currentSceneBlock,
      onSceneSelected: _jumpToScene,
      onSceneReordered: _reorderScene,
      onCharacterSelected: _jumpToCharacter,
      onCollapse: () => _setNavigatorVisible(false),
    );
    final indicator = _pageIndicator;
    return indicator == null
        ? sidebar()
        : ListenableBuilder(
            listenable: indicator,
            builder: (context, _) => sidebar(),
          );
  }
}

enum _Panel { none, find, palette }

/// One button in the top bar.
///
/// Small icon, large target. §Item 4 asks for a 40×40 hit area around an 18–20
/// pixel glyph, which is the difference between a bar that looks light and a bar
/// that is hard to hit — those are not the same decision and this is the widget
/// that keeps them apart.
///
/// The colour is the second weight of text at rest and the first under the
/// pointer, so the row reads as quiet until it is being used. [selected] is for
/// the two buttons that toggle something on screen — the navigator and the find
/// panel — and is the accent, because what is showing right now *is* a selected
/// state (see [SluglineColors.accent]).
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    return IconButton(
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return colours.accent;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colours.textPrimary;
          }
          return colours.textSecondary;
        }),
      ),
    );
  }
}

/// The hairline between two clusters of buttons, with room either side.
class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: context.colours.border,
  );
}

/// The script's name, and whether the file has it.
///
/// The `.fountain` extension is omitted: it is how the script is stored, not
/// what it is called. Other extensions are still shown, faded. The dot beside
/// the title appears only when there is something unsaved.
class _ScriptTitle extends StatelessWidget {
  const _ScriptTitle({required this.name, required this.status});

  final String name;
  final SaveStatus? status;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    final theme = Theme.of(context);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    final extension = ext == '.fountain' ? '' : ext;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: stem),
          if (extension.isNotEmpty)
            TextSpan(
              text: extension,
              style: TextStyle(color: colours.textTertiary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(color: colours.textPrimary),
    );
    final status = this.status;
    if (status == null) return title;
    return AnimatedBuilder(
      animation: status,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: title),
          if (!status.isPlainSaved)
            Container(
              key: const ValueKey('unsaved indicator'),
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: status.isError ? colours.danger : colours.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

/// Everything that is worth a menu entry and not worth a permanent button.
///
/// Save is here rather than in the bar on purpose: it has a keystroke everybody
/// knows, the autosave already runs it, and the status bar says whether it has
/// happened — three answers to "is my work safe" before a toolbar button is the
/// fourth. The same reasoning removes history, spell checking, the title page
/// and the shortcut list from the row, none of which is reached mid-sentence.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.onTitlePage,
    required this.onSpelling,
    required this.onBackups,
    required this.onSave,
    required this.onSaveAs,
    required this.onShortcuts,
    required this.onPaginationDebug,
    required this.onImportFdx,
  });

  final VoidCallback onTitlePage;
  final VoidCallback onSpelling;
  final VoidCallback onBackups;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final Future<void> Function()? onShortcuts;
  final VoidCallback? onPaginationDebug;
  final VoidCallback? onImportFdx;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('editor overflow'),
      tooltip: 'More actions',
      icon: Icon(Icons.more_horiz, size: 19, color: colours.textSecondary),
      constraints: const BoxConstraints(minWidth: 220),
      position: PopupMenuPosition.under,
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        _entry(context, 'Save', 'Ctrl+S', onSave),
        _entry(context, 'Save as…', 'Ctrl+Shift+S', onSaveAs),
        _entry(context, 'Previous versions…', '', onBackups),
        if (onImportFdx case final action?)
          _entry(context, 'Import FDX…', '', action),
        const PopupMenuDivider(),
        _entry(context, 'Title page…', '', onTitlePage),
        _entry(
          context,
          'Spell checking…',
          '',
          onSpelling,
          key: 'spell settings',
        ),
        const PopupMenuDivider(),
        _entry(
          context,
          'Keyboard shortcuts',
          'F1',
          () => unawaited(onShortcuts?.call()),
        ),
        if (onPaginationDebug case final debug?) ...[
          const PopupMenuDivider(),
          _entry(context, 'Pagination debug', '', debug),
        ],
      ],
    );
  }

  /// A label on the left, its keystroke on the right in the third weight.
  ///
  /// The shortcut is here for the same reason the element menu carries its
  /// digits: someone who opens this menu twice for the same thing should come
  /// away knowing how not to open it a third time.
  PopupMenuItem<VoidCallback> _entry(
    BuildContext context,
    String label,
    String shortcut,
    VoidCallback action, {
    String? key,
  }) {
    final colours = context.colours;
    return PopupMenuItem<VoidCallback>(
      key: key == null ? null : ValueKey(key),
      value: action,
      height: 36,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (shortcut.isNotEmpty)
            Text(
              shortcut,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colours.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// The two buttons that float over the script itself.
///
/// Neither marks a selection and neither is the primary action in a group, so
/// neither wears the accent (see [SluglineColors.accent]). They are overlays,
/// and they look like every other overlay: the overlay surface and a hairline.
ButtonStyle _floatingButton(SluglineColors colours) => IconButton.styleFrom(
  backgroundColor: colours.surfaceOverlay,
  foregroundColor: colours.textSecondary,
  side: hairline(colours),
);
