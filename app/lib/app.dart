import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/identity.dart';
import 'package:slugline/library/library_page.dart';
import 'package:slugline/library/file_chooser.dart';
import 'package:slugline/library/fdx_warnings_dialog.dart';
import 'package:slugline/library/quick_open_dialog.dart';
import 'package:slugline/library/recovery_dialog.dart';
import 'package:slugline/settings/preferences_dialog.dart';
import 'package:slugline/settings/shortcuts_dialog.dart';
import 'package:slugline/settings/window_mode.dart';
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/theme.dart';

/// Which of the scripts that were open last time the session restore may
/// reopen, given the crash offers and what the writer did about them.
///
/// A script named by an offer that is still on disk is skipped, and this is the
/// half of a P0 the rest of startup cannot fix. An undecided journal is the only
/// copy of the edits in it; opening its script starts a session over the top of
/// it, and a session wants a journal at exactly that name. The core now refuses
/// to take one over — so the worst case is a session that is not being recorded
/// rather than an offer that has been erased — but refusing is not the same as
/// being right to ask. Nothing about pressing Escape says "reopen that script",
/// so nothing here does.
///
/// `resolved` is the journals the writer discarded. Those are gone and their
/// scripts are ordinary again. An accepted offer never reaches here: it opens
/// its own script and startup stops there.
@visibleForTesting
files.ScriptView? scriptToRestore({
  required List<files.ScriptView> session,
  required List<files.RecoveryOffer> offers,
  required Set<String> resolved,
}) {
  final undecided = {
    for (final offer in offers)
      if (!resolved.contains(offer.journal)) offer.script,
  };
  for (final restored in session) {
    if (!undecided.contains(restored.path)) return restored;
  }
  return null;
}

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
///    their scroll positions — except any the writer has not decided about,
///    because an undecided offer's journal is still the only copy of the edits
///    in it and opening its script would start a session over the top.
/// 3. **The library**, if neither of those produced a script.
class SluglineApp extends StatefulWidget {
  const SluglineApp({required this.core, this.initialPath, super.key});

  final Core core;

  /// A screenplay named on the command line, already made absolute.
  ///
  /// It takes the place of the session restore — someone who typed a file name
  /// has said which script they want, and reopening yesterday's over the top of
  /// it would be ignoring them. It does *not* take the place of crash recovery,
  /// which still comes first: an undecided journal is the only copy of those
  /// edits whichever script was asked for.
  final String? initialPath;

  @override
  State<SluglineApp> createState() => _SluglineAppState();
}

class _SluglineAppState extends State<SluglineApp> {
  /// The script on screen, or null for the library.
  _OpenScript? _open;

  StreamSubscription<CoreEvent>? _events;
  GlobalKey<EditorPageState> _editorKey = GlobalKey<EditorPageState>();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Catches the window's close button, so that a clean quit looks like one.
  late final AppLifecycleListener _lifecycle;

  bool _startedUp = false;
  bool _importActive = false;
  bool _deferredJournalFailure = false;
  late files.PreferencesView _preferences;

  /// Set once a quit has been agreed to. The core is about to drop every
  /// document it holds, so from here nothing is opened and nothing is adopted.
  bool _exiting = false;

  /// Documents the core has been asked for and has not yet handed back.
  int _opensActive = 0;
  Completer<void>? _opensSettled;

  @override
  void initState() {
    super.initState();
    _preferences = widget.core.preferences();
    _events = widget.core.events.listen(_onCoreEvent);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    if (_preferences.distractionFree) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(WindowMode.setFullscreen(true)),
      );
    }
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
    _exiting = true;
    // Shutdown closes the documents the core knows about, and one still being
    // opened is not among them yet. Left to race, it arrives afterwards as a
    // handle that is already closed — or the process goes while its journal is
    // half written.
    if (_opensActive > 0) {
      await (_opensSettled ??= Completer<void>()).future;
    }
    _open?.dispose();
    _open = null;
    await widget.core.shutdown();
    return AppExitResponse.exit;
  }

  /// Asks the core for a document where a quit can wait for the answer. Null
  /// without asking once a quit is under way.
  Future<T?> _opening<T>(Future<T?> Function() request) async {
    if (_exiting) return null;
    _opensActive += 1;
    try {
      return await request();
    } finally {
      _opensActive -= 1;
      if (_opensActive == 0) {
        final settled = _opensSettled;
        _opensSettled = null;
        settled?.complete();
      }
    }
  }

  // --- startup ---------------------------------------------------------------

  Future<void> _startUp() async {
    if (_startedUp) return;
    _startedUp = true;

    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;

    final offers = await widget.core.pendingRecoveries();
    // The offers that stop being offers: discarding one deletes its journal, so
    // its script is an ordinary script again. Everything else the dialog can
    // produce leaves the journal where it is.
    final resolved = <String>{};
    if (offers.isNotEmpty && context.mounted) {
      final choices = await RecoveryDialog.show(context, offers);
      for (final entry in choices.entries) {
        switch (entry.value) {
          case RecoveryChoice.recover:
            final outcome = await _opening(
              () => files.recoveryAccept(journalPath: entry.key),
            );
            switch (outcome) {
              case null:
                return;
              case files.RecoveryOutcome_Recovered(:final handle):
                await _adopt(RustDocumentCore.of(handle));
                // One at a time: the editor holds one script. The rest of the
                // offers stay on disk and are offered again next launch, which
                // is better than silently dropping them.
                return;
              case files.RecoveryOutcome_Degraded(
                :final handle,
                :final message,
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
            // Only a delete that reported success frees the script: a journal
            // that could not be removed is still a journal on disk.
            if (await widget.core.discardRecovery(entry.key)) {
              resolved.add(entry.key);
            }
        }
      }
    }

    if (_open != null) return;

    // A file named on the command line wins over the session, but not over a
    // recovery that has already put a script on screen above.
    final named = widget.initialPath;
    if (named != null) {
      await _openPath(named);
      return;
    }

    final restored = scriptToRestore(
      session: await widget.core.sessionToRestore(),
      offers: offers,
      resolved: resolved,
    );
    if (restored == null) return;
    await _openPath(restored.path, initialScrollRow: restored.scrollRow);
  }

  // --- opening and closing ---------------------------------------------------

  Future<void> _openPath(String path, {int initialScrollRow = 0}) async {
    final core = await _opening(() => widget.core.openDocument(path));
    if (core == null) {
      _say('The script could not be opened or created.');
      return;
    }
    if (!mounted) {
      core.close();
      return;
    }
    await _adopt(core, initialScrollRow: initialScrollRow);
  }

  Future<void> _switchPath(String? path) async {
    if (path == null || !mounted || path == _open?.core.path) return;
    final editor = _editorKey.currentState;
    if (editor != null && !await editor.confirmClose()) return;
    if (!mounted) return;
    // The page holds input and autosave for this action. Keep its session
    // until the destination has loaded successfully.
    final next = await _opening(() => widget.core.openDocument(path));
    if (next == null) {
      _say('The script could not be opened or created.');
      return;
    }
    if (!mounted) {
      next.close();
      return;
    }
    await _adopt(next);
  }

  Future<void> _newScript() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    await _switchPath(
      await FileChooser.show(
        context,
        title: 'New script',
        action: 'Create',
        suggestedName: 'untitled.fountain',
        directory: _scriptDirectory,
      ),
    );
  }

  Future<void> _quickOpen() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    await _switchPath(
      await QuickOpenDialog.show(
        context,
        widget.core,
        directory: _scriptDirectory,
      ),
    );
  }

  Future<void> _importFdx() async {
    if (_importActive) return;
    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;
    _importActive = true;
    DocumentCore? candidate;
    try {
      final path = await FileChooser.show(
        context,
        title: 'Import FDX',
        action: 'Import',
        directory: _scriptDirectory,
        mustExist: true,
        extension: 'fdx',
      );
      if (path == null || !mounted || !context.mounted) return;
      final result = await _opening(() => widget.core.importFdx(path));
      switch (result) {
        case null:
          return;
        case FdxImportFailed(:final message):
          _say('Could not import FDX: $message');
          return;
        case FdxImported(:final document, :final warnings):
          candidate = document;
          if (!mounted || !context.mounted) return;
          if (warnings.isNotEmpty &&
              !await confirmFdxWarnings(context, warnings, importing: true)) {
            return;
          }
          if (!mounted) return;
          final editor = _editorKey.currentState;
          if (editor != null && !await editor.confirmClose()) return;
          if (!mounted) return;
          await _adopt(document);
          candidate = null;
          // The candidate's JournalBroken can precede adoption. Its sticky
          // state, not event timing, is authoritative for the new status line.
          if (document.journalState.$2) _deferredJournalFailure = true;
      }
    } catch (failure) {
      _say('Could not import FDX: $failure');
    } finally {
      candidate?.close();
      _importActive = false;
      if (mounted && _deferredJournalFailure) {
        _open?.status.refresh();
        if (_open?.core.journalState.$2 == true) _sayJournalFailure();
      }
      _deferredJournalFailure = false;
    }
  }

  void _sayJournalFailure() {
    _say(
      'The crash-recovery record for this script is unavailable. '
      'Saving still works; save more often until you can restart.',
    );
  }

  String? get _scriptDirectory {
    final path = _open?.core.path;
    return path == null ? null : File(path).parent.path;
  }

  Future<void> _adopt(DocumentCore core, {int initialScrollRow = 0}) async {
    if (_exiting) {
      core.close();
      return;
    }
    _open?.dispose();
    final preferences = _preferences;
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
      // A different document gets a fresh page, including focus, scroll and
      // panel state. Nothing from the closed script may survive the switch.
      _editorKey = GlobalKey<EditorPageState>();
      _open = _OpenScript(
        core: core,
        controller: controller,
        autosave: autosave,
        status: status,
        initialScrollRow: initialScrollRow,
        navigatorVisible: preferences.navigatorVisible,
      );
    });
  }

  Future<void> _setNavigatorVisible(bool visible) async {
    final open = _open;
    if (open != null) open.navigatorVisible = visible;
    final next = _copyPreferences(_preferences, navigatorVisible: visible);
    if (await widget.core.setPreferences(next) && mounted) {
      setState(() => _preferences = widget.core.preferences());
    }
  }

  Future<void> _openPreferences() async {
    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;
    final chosen = await PreferencesDialog.show(
      context,
      preferences: _preferences,
      spelling: widget.core.spellStatus(),
    );
    if (chosen == null || !context.mounted) return;

    final oldFocusMode = _preferences.distractionFree;
    if (!await widget.core.setPreferences(chosen)) {
      _say(
        'Preferences could not be saved. Your previous settings are still active.',
      );
      return;
    }
    final spelling = await widget.core.configureSpelling(
      enabled: chosen.spellEnabled,
      language: chosen.spellLanguage,
    );
    final saved = widget.core.preferences();
    _open?.autosave.reconfigure(
      enabled: saved.autosaveEnabled,
      idle: Duration(milliseconds: saved.autosaveIdleMs),
      interval: Duration(milliseconds: saved.autosaveIntervalMs),
    );
    if (oldFocusMode != saved.distractionFree) {
      await WindowMode.setFullscreen(saved.distractionFree);
    }
    if (!mounted) return;
    setState(() => _preferences = saved);
    if (spelling case SpellActionResult_Failed(:final message)) {
      _say(message);
    }
  }

  Future<void> _setDistractionFree(bool enabled) async {
    final next = _copyPreferences(_preferences, distractionFree: enabled);
    if (!await widget.core.setPreferences(next)) {
      _say('The display preference could not be saved.');
      return;
    }
    await WindowMode.setFullscreen(enabled);
    if (mounted) setState(() => _preferences = widget.core.preferences());
  }

  Future<void> _setEditorTextSize(int size) async {
    final next = _copyPreferences(_preferences, editorTextSize: size);
    if (!await widget.core.setPreferences(next)) {
      _say('The editor text size could not be saved.');
      return;
    }
    if (mounted) setState(() => _preferences = widget.core.preferences());
  }

  Future<void> _setPageView(bool enabled) async {
    final next = _copyPreferences(_preferences, pageView: enabled);
    if (!await widget.core.setPreferences(next)) {
      _say('The display preference could not be saved.');
      return;
    }
    if (mounted) setState(() => _preferences = widget.core.preferences());
  }

  Future<void> _showShortcuts() async {
    final context = _navigator.currentContext;
    if (context != null && context.mounted) {
      await ShortcutsDialog.show(context);
    }
  }

  Future<void> _closeScript() async {
    _open?.dispose();
    setState(() => _open = null);
  }

  /// The script's name is read from its path when this builds, and Save As
  /// moves the path without anything else here changing.
  void _scriptSaved() {
    if (mounted) setState(() {});
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
      case CoreEvent_JournalBroken(:final handle):
        if (_importActive) {
          _deferredJournalFailure = true;
        } else if (_open?.core.eventHandle == handle) {
          _open?.status.refresh();
          _sayJournalFailure();
        }
      case CoreEvent_ExternalWatchUnavailable():
        // Not a loss of protection — a save still refuses to replace a file it
        // does not recognise — but a loss of *warning*, and the writer is the
        // one who has to know that nothing will interrupt them if another
        // program edits this script. The status line goes on saying it; this is
        // the once.
        _open?.status.refresh();
        _say(
          'This script cannot be watched for changes by other programs. '
          'Saving still checks the file before replacing it, but nothing will '
          'tell you at the time.',
        );
    }
  }

  void _say(String message) {
    final context = _navigator.currentContext;
    if (context == null || !context.mounted || _exiting) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return MaterialApp(
      navigatorKey: _navigator,
      title: applicationName,
      debugShowCheckedModeBanner: false,
      theme: sluglineTheme(Brightness.light),
      darkTheme: sluglineTheme(Brightness.dark),
      themeMode: _themeMode(_preferences.appearance),
      home: open == null
          ? LibraryPage(
              core: widget.core,
              onOpen: _openPath,
              onImportFdx: _importFdx,
              onOpenPreferences: _openPreferences,
              onShowShortcuts: _showShortcuts,
            )
          : EditorPage(
              key: _editorKey,
              controller: open.controller,
              autosave: open.autosave,
              saveStatus: open.status,
              initialScrollRow: open.initialScrollRow,
              navigatorVisible: open.navigatorVisible,
              textSize: _preferences.editorTextSize.toDouble(),
              distractionFree: _preferences.distractionFree,
              pageView: _preferences.pageView,
              initialPageSetup: _pageSetup(_preferences),
              onNavigatorVisibilityChanged: _setNavigatorVisible,
              onOpenPreferences: _openPreferences,
              onShowShortcuts: _showShortcuts,
              onDistractionFreeChanged: _setDistractionFree,
              onTextSizeChanged: _setEditorTextSize,
              onPageViewChanged: _setPageView,
              onClosed: _closeScript,
              onNewScript: _newScript,
              onOpenScript: _quickOpen,
              onImportFdx: _importFdx,
              onSaved: _scriptSaved,
              title: _titleOf(open.core),
            ),
    );
  }
}

/// What runs instead of the editor when the core came up without storage.
///
/// There is no library to list, no journal to record into and nowhere to save,
/// so there is nothing an editor here could honestly offer. It says what is
/// wrong and stops — which is the whole point: the alternative, and what used to
/// happen, is a window that looks like a working editor until the writer finds
/// out otherwise.
class StorageUnavailableApp extends StatelessWidget {
  const StorageUnavailableApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: applicationName,
    debugShowCheckedModeBanner: false,
    theme: sluglineTheme(Brightness.light),
    darkTheme: sluglineTheme(Brightness.dark),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  '$applicationName cannot start',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

ThemeMode _themeMode(String appearance) => switch (appearance) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

PageSetup _pageSetup(files.PreferencesView preferences) => PageSetup(
  paper: preferences.defaultPaper == 'a4' ? PaperSize.a4 : PaperSize.usLetter,
  boldSceneHeadings: preferences.boldSceneHeadings,
  numberFirstPage: preferences.numberFirstPage,
  sceneNumbers: switch (preferences.sceneNumbers) {
    'left' => SceneNumbers.left,
    'right' => SceneNumbers.right,
    'both' => SceneNumbers.both,
    _ => SceneNumbers.off,
  },
  debugLinesPerPage: null,
);

files.PreferencesView _copyPreferences(
  files.PreferencesView value, {
  bool? navigatorVisible,
  int? editorTextSize,
  bool? distractionFree,
  bool? pageView,
}) => files.PreferencesView(
  autosaveEnabled: value.autosaveEnabled,
  autocompleteEnabled: value.autocompleteEnabled,
  navigatorVisible: navigatorVisible ?? value.navigatorVisible,
  spellEnabled: value.spellEnabled,
  spellLanguage: value.spellLanguage,
  appearance: value.appearance,
  editorTextSize: editorTextSize ?? value.editorTextSize,
  defaultPaper: value.defaultPaper,
  sceneNumbers: value.sceneNumbers,
  boldSceneHeadings: value.boldSceneHeadings,
  numberFirstPage: value.numberFirstPage,
  pdfFontPath: value.pdfFontPath,
  distractionFree: distractionFree ?? value.distractionFree,
  pageView: pageView ?? value.pageView,
  autosaveIdleMs: value.autosaveIdleMs,
  autosaveIntervalMs: value.autosaveIntervalMs,
  backupDir: value.backupDir,
  backupKeepVersions: value.backupKeepVersions,
  backupKeepDays: value.backupKeepDays,
);

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
    required this.initialScrollRow,
    required this.navigatorVisible,
  });

  final DocumentCore core;
  final EditorController controller;
  final AutosaveDriver autosave;
  final SaveStatus status;
  final int initialScrollRow;
  bool navigatorVisible;

  /// Ends the session, in the order the pieces depend on each other: the
  /// autosave timers first so nothing fires at a document that is going away,
  /// then the listener, then the controller — which closes [core], because the
  /// controller owns it. This used to close it a second time itself.
  void dispose() {
    autosave.dispose();
    controller.removeListener(status.refresh);
    controller.dispose();
    status.dispose();
  }
}
