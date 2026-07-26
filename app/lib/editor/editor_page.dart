import 'dart:async';

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
import 'package:slugline/editor/save_status.dart';
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

  int _externalChangeSerial = 0;
  int _externalChangesActive = 0;
  Completer<void>? _externalChangesSettled;

  DocumentCore get _core => widget.controller.core;

  @override
  void dispose() {
    _editorFocus.dispose();
    super.dispose();
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
    if (!keys.isControlPressed) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyS when keys.isShiftPressed:
        unawaited(save(forcePath: true));
      case LogicalKeyboardKey.keyS:
        unawaited(save());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Above the surface, so the surface still sees every editing key first and
      // only what it ignores reaches here.
      onKeyEvent: (_, event) => _onPageKey(event),
      child: Scaffold(
        appBar: widget.onClosed == null
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
                  const SizedBox(width: 8),
                ],
              ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: EditorSurface(
                      controller: widget.controller,
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
                      onScrolled: _core.setScrollRow,
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
                          save: () => unawaited(save()),
                          saveAs: () => unawaited(save(forcePath: true)),
                          showBackups: () => unawaited(_showBackups()),
                        ),
                        onDismiss: _dismiss,
                      ),
                    ),
                ],
              ),
            ),
            ElementBar(
              controller: widget.controller,
              saveStatus: widget.saveStatus,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Panel { none, find, palette }
