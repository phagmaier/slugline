import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/library/recovery_dialog.dart';
import 'package:slugline/src/rust/api/files.dart' as files;

/// The application: the library, one open script at a time, and the startup
/// sequence that decides which of them you see first.
///
/// ## Startup order, and why it is this order
///
/// 1. **Crash recovery.** Before anything else, because it is the only thing
///    that can lose work by being late — a session restore that reopens a file
///    the journal was recorded against would put a second document over it.
///    §Phase 4 requires the offer and forbids applying it automatically.
/// 2. **Session restore.** The scripts that were open last time, reopened with
///    their scroll positions.
/// 3. **The library**, if neither of those produced a script.
class SluglineApp extends StatefulWidget {
  const SluglineApp({required this.core, super.key});

  final Core core;

  @override
  State<SluglineApp> createState() => _SluglineAppState();
}

class _SluglineAppState extends State<SluglineApp> {
  /// The script on screen, or null for the library.
  _OpenScript? _open;

  StreamSubscription<CoreEvent>? _events;
  final GlobalKey<EditorPageState> _editorKey = GlobalKey<EditorPageState>();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Catches the window's close button, so that a clean quit looks like one.
  late final AppLifecycleListener _lifecycle;

  bool _startedUp = false;

  @override
  void initState() {
    super.initState();
    _events = widget.core.events.listen(_onCoreEvent);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startUp()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_events?.cancel());
    _open?.dispose();
    super.dispose();
  }

  /// The window's close button, and anything else that asks the application to
  /// go away.
  ///
  /// Two things have to happen here and both are §10's:
  ///
  /// * **Unsaved work is never silently discarded.** The editor asks, and
  ///   `cancel` really cancels the quit.
  /// * **The journals are discarded.** A journal left on disk is what says the
  ///   previous session crashed, so a clean exit that skipped this would greet
  ///   the writer next launch with a recovery offer for edits that are already
  ///   in their file. Harmless, and wrong — and a prompt that cries wolf is a
  ///   prompt that gets dismissed the one time it matters.
  Future<AppExitResponse> _onExitRequested() async {
    final editor = _editorKey.currentState;
    if (editor != null && !await editor.confirmClose()) {
      return AppExitResponse.cancel;
    }
    _open?.dispose();
    _open = null;
    await widget.core.shutdown();
    return AppExitResponse.exit;
  }

  // --- startup ---------------------------------------------------------------

  Future<void> _startUp() async {
    if (_startedUp) return;
    _startedUp = true;

    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;

    final offers = await widget.core.pendingRecoveries();
    if (offers.isNotEmpty && context.mounted) {
      final choices = await RecoveryDialog.show(context, offers);
      for (final entry in choices.entries) {
        switch (entry.value) {
          case RecoveryChoice.recover:
            final outcome = await files.recoveryAccept(journalPath: entry.key);
            switch (outcome) {
              case files.RecoveryOutcome_Recovered(:final handle):
                await _adopt(RustDocumentCore.of(handle));
                // One at a time: the editor holds one script. The rest of the
                // offers stay on disk and are offered again next launch, which
                // is better than silently dropping them.
                return;
              case files.RecoveryOutcome_Degraded(
                  :final handle,
                  :final message
                ):
                // The text is here and the old journal is still on disk, but
                // nothing typed from now on is being recorded. That is not a
                // thing to discover later.
                await _adopt(RustDocumentCore.of(handle));
                if (context.mounted) {
                  await showRecoveryNotJournalled(context, message);
                }
                return;
              case files.RecoveryOutcome_Failed(:final message):
                if (context.mounted) {
                  await showRecoveryFailed(context, message);
                }
            }
          case RecoveryChoice.discard:
            await widget.core.discardRecovery(entry.key);
        }
      }
    }

    if (_open != null) return;
    final session = await widget.core.sessionToRestore();
    if (session.isEmpty) return;
    await _openPath(session.first.path);
  }

  // --- opening and closing ---------------------------------------------------

  Future<void> _openPath(String path) async {
    final handle = await files.libraryOpen(path: path);
    if (handle == null) {
      final created = await files.libraryCreate(path: path);
      if (created == null) return;
      await _adopt(RustDocumentCore.of(created));
      return;
    }
    await _adopt(RustDocumentCore.of(handle));
  }

  Future<void> _adopt(DocumentCore core) async {
    _open?.dispose();
    final preferences = widget.core.preferences();
    final controller = EditorController(core);
    final status = SaveStatus(core: core);
    final autosave = AutosaveDriver(
      core: core,
      changes: controller,
      enabled: preferences.autosaveEnabled,
      idle: Duration(milliseconds: preferences.autosaveIdleMs),
      interval: Duration(milliseconds: preferences.autosaveIntervalMs),
      onOutcome: status.record,
    );
    // The status line reads the core's dirty flag, so it has to be told when
    // anything might have moved it.
    controller.addListener(status.refresh);
    // A document can arrive already dirty — crash recovery is the case that
    // matters — and no edit event will ever fire for the edits it arrived with.
    // Without this the autosave clock would not start until the writer typed,
    // which is exactly the moment they are least likely to.
    autosave.documentAdopted();
    setState(() {
      _open = _OpenScript(
        core: core,
        controller: controller,
        autosave: autosave,
        status: status,
      );
    });
  }

  Future<void> _closeScript() async {
    _open?.dispose();
    setState(() => _open = null);
  }

  // --- events from the core --------------------------------------------------

  void _onCoreEvent(CoreEvent event) {
    switch (event) {
      case CoreEvent_FileChangedOnDisk(:final path):
        // §Phase 4's watcher fires for any watched file. Only the one on screen
        // has an editor that can do anything about it.
        if (_open?.core.path == path) {
          unawaited(_editorKey.currentState?.handleExternalChange());
        }
      case CoreEvent_SaveStateChanged():
      case CoreEvent_BackupWritten():
      case CoreEvent_EntityIndexUpdated():
        _open?.status.refresh();
      case CoreEvent_AutosaveFailed(:final message):
        // Not a modal: an autosave is not something the writer asked for. The
        // status line goes red and says why, which is §Phase 4's "never a silent
        // toast" without being a dialog that interrupts a sentence.
        _open?.status.refresh();
        _say(message);
      case CoreEvent_JournalBroken():
        _open?.status.refresh();
        _say(
          'The crash-recovery record for this script stopped working. '
          'Saving still works; save more often until you can restart.',
        );
    }
  }

  void _say(String message) {
    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Slugline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B6EA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: open == null
          ? LibraryPage(core: widget.core, onOpen: _openPath)
          : EditorPage(
              key: _editorKey,
              controller: open.controller,
              autosave: open.autosave,
              saveStatus: open.status,
              onClosed: _closeScript,
              title: _titleOf(open.core),
            ),
    );
  }
}

String _titleOf(DocumentCore core) {
  final path = core.path;
  if (path == null) return 'Untitled';
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// One script and everything attached to it, so that closing one cannot leave a
/// timer or a listener behind pointing at a document that is gone.
class _OpenScript {
  _OpenScript({
    required this.core,
    required this.controller,
    required this.autosave,
    required this.status,
  });

  final DocumentCore core;
  final EditorController controller;
  final AutosaveDriver autosave;
  final SaveStatus status;

  void dispose() {
    autosave.dispose();
    controller.removeListener(status.refresh);
    controller.dispose();
    status.dispose();
    core.close();
  }
}
