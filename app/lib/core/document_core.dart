import 'package:slugline/src/rust/api/doc.dart' as rust;
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/src/rust/api/layout.dart' as layout;
import 'package:slugline/src/rust/api/spell.dart' as spell;

export 'package:slugline/src/rust/api/files.dart'
    show
        BackupView,
        BackupReadOutcome,
        BackupReadOutcome_Read,
        BackupReadOutcome_Failed,
        FdxExportOutcome,
        FdxExportOutcome_Finished,
        FdxExportOutcome_NeedsConfirmation,
        SaveFailure,
        SaveOutcome,
        SaveOutcome_Failed,
        SaveOutcome_Saved,
        SaveOutcome_Unchanged;

export 'package:slugline/src/rust/api/layout.dart'
    show
        EmphasisRunView,
        LayoutLineKind,
        LayoutLineView,
        PageSetup,
        PageView,
        PaginationOutcome,
        PaginationOutcome_Current,
        PaginationOutcome_NoSuchDocument,
        PaginationOutcome_Stale,
        PaginationStats,
        PaginationView,
        PaperSize,
        ScenePaginationView,
        SceneNumbers;

export 'package:slugline/src/rust/api/doc.dart'
    show
        BlockKind,
        BlockView,
        Completion,
        CompletionKind,
        DocPosition,
        DocSelection,
        DocumentHandle,
        EditCommand,
        EditCommand_DeleteRange,
        EditCommand_InsertBlocks,
        EditCommand_MergeBlocks,
        EditCommand_MoveScene,
        EditCommand_ReplaceText,
        EditCommand_SetDual,
        EditCommand_SetKind,
        EditCommand_SplitBlock,
        EditOutcome,
        EditOutcome_Applied,
        EditOutcome_Rejected,
        EditRejection,
        EditResult,
        FindMatch,
        FindQuery,
        InsertedBlock,
        InlineRunView,
        InlineStyle,
        NewBlock,
        NavigatorCharacter,
        NavigatorNode,
        NavigatorScene,
        NavigatorView,
        TitleEntryView;

export 'package:slugline/src/rust/api/spell.dart'
    show
        Misspelling,
        SpellActionResult,
        SpellActionResult_Applied,
        SpellActionResult_Failed,
        SpellActionResult_NoScriptPath,
        SpellActionResult_NoSuchDocument,
        SpellCheckResult,
        SpellLanguage,
        SpellStatus;

/// Everything that turns a script into pages: the preview and the PDF.
///
/// Deliberately separate from [DocumentCore], and it stays separate. Pagination
/// is not part of editing and must never become a per-keystroke dependency —
/// the editor is fluid and unpaginated (ADR 0018), and nothing on the typing
/// path may reach through here. The real core implements it; a widget test
/// driving the editor does not have to pretend it can lay out a screenplay.
///
/// The preview and the PDF read the **same** [layout.PaginationView], which is
/// §Phase 7's "never a second layout implementation" written as a type: there is
/// one paginator, it is in Rust, and both consumers are downstream of it.
abstract interface class ScreenplayOutput {
  /// Lays the document out on the page grid (§6's `paginate`).
  Future<layout.PaginationOutcome> paginate(layout.PageSetup setup);

  /// Writes a PDF (§6's `export_pdf`).
  ///
  /// An export, so ADR 0029 applies: the session stays where it is, a
  /// destination that already exists comes back as
  /// [files.SaveFailure.alreadyExists] until [overwrite] says otherwise, and one
  /// that is a script open here is refused outright.
  Future<files.SaveOutcome> exportPdf(
    String path, {
    required layout.PageSetup setup,
    bool overwrite = false,
  });
}

/// One open script, as the editor sees it.
///
/// Everything the editor knows about screenplay semantics is behind this
/// interface, because §2.1 says Flutter does not derive them: the editor asks
/// what a block is, it never decides. Offsets are **UTF-16 code units** in both
/// directions (§2.4), which is what Dart's own `String` uses, so no conversion
/// happens on this side of the bridge at all.
///
/// It is an interface rather than a class so that a widget test can drive the
/// editor without `libslugline_bridge.so` — `flutter test` runs on the Dart VM
/// with no native library loaded. The double in `test/support/` does list
/// surgery and nothing else; every rule about what a screenplay *is* stays in
/// Rust, where it is tested.
abstract class DocumentCore {
  /// Identity used only to route asynchronous core notifications.
  int get eventHandle;

  int get blockCount;

  /// Blocks `from..to`, clamped to what exists.
  List<rust.BlockView> blocks(int from, int to);

  /// Rust's source-ordered outline, scenes and entity-index characters (ADR 0058).
  rust.NavigatorView navigator();

  /// The whole document as Fountain — what a save would write.
  String source();

  /// The title page, in the order a save would write it (§6's `doc_title_page`).
  List<rust.TitleEntryView> titlePage();

  /// Sets one title-page field; an empty [value] removes it. One undo step per
  /// call, and setting a field to what it already holds is not an edit at all.
  ///
  /// [key] is matched case-insensitively against the keys Fountain names, and
  /// kept verbatim otherwise — the format allows any key and a writer's
  /// `Revision Colour:` is theirs.
  rust.EditOutcome setTitleField(String key, String value);

  /// Applies one command. [before] is the selection the user had before the
  /// edit, so that undo restores the caret as well as the text (§3.4).
  rust.EditOutcome apply(rust.EditCommand command, {rust.DocSelection? before});

  /// Explicit whole-document suffix edits, each an isolated undo transaction.
  /// Rust preserves heading text and returns the mapped selection in its patch.
  rust.EditOutcome numberScenes(rust.DocSelection at);
  rust.EditOutcome removeSceneNumbers(rust.DocSelection at);

  /// Replaces [at] with [text] in one undo transaction. [plain] is
  /// `Ctrl+Shift+V`: Action blocks, no element inference.
  rust.EditOutcome paste(
    rust.DocSelection at,
    String text, {
    required bool plain,
  });

  /// Enter: the block splits and whatever appears below it takes the element
  /// type `docs/KEYMAP.md` says follows this one. One undo step, even though it
  /// may be a delete, a split and a kind change.
  rust.EditOutcome enter(rust.DocSelection at);

  /// Shift+Enter: Rust chooses a hard line break or the normal Enter workflow.
  /// Replaces the selection in one isolated undo transaction.
  rust.EditOutcome lineBreak(rust.DocSelection at);

  /// Wraps the selected source through Rust's inline semantics, atomically.
  rust.EditOutcome formatSelection(
    rust.DocSelection at,
    rust.InlineStyle style,
  );

  /// Lossless, isolated boneyard gestures; Rust owns fragments and scene bounds.
  rust.EditOutcome omitSelection(rust.DocSelection at);
  rust.EditOutcome omitScene(rust.DocSelection at);
  rust.EditOutcome restoreOmitted(rust.DocSelection at);

  /// Tab, or Shift+Tab, on the block the caret is in. `null` where the table
  /// says Tab does nothing there — not a refusal, just no next element type.
  rust.EditOutcome? tab(rust.DocSelection at, {required bool shift});

  /// The element type Tab would move to, without moving. For the element bar.
  rust.BlockKind? tabTarget(int block, {required bool shift});

  /// A character cue the script already has whose name this block's text
  /// matches. A suggestion: the core never acts on it.
  String? characterSuggestion(int block);

  /// Ranked, read-only candidates at the caret. Text changes only when Dart
  /// explicitly accepts one with an edit command.
  List<rust.Completion> complete(
    int block,
    int offsetUtf16,
    List<String> suppressed,
  );

  bool setEntityPinned(rust.CompletionKind kind, String value, bool pinned);

  // --- spelling (§Phase 9) -------------------------------------------------

  spell.SpellStatus spellStatus();

  Future<spell.SpellActionResult> configureSpelling({
    required bool enabled,
    String? language,
  });

  Future<spell.SpellCheckResult> spellCheckBlock(int block);

  Future<List<String>> spellSuggest(String word);

  spell.SpellActionResult spellIgnoreOnce(spell.Misspelling misspelling);

  spell.SpellActionResult spellIgnoreAll(String word);

  Future<spell.SpellActionResult> spellAddPersonal(String word);

  Future<spell.SpellActionResult> spellAddProject(String word);

  /// Every match of [query], in document order.
  List<rust.FindMatch> find(rust.FindQuery query);

  /// Replaces every match with [with_], as one undo transaction.
  rust.EditOutcome replaceAll(rust.FindQuery query, String with_);

  /// The Fountain text between two positions, for the clipboard.
  String? extract(rust.DocPosition from, rust.DocPosition to);

  rust.EditResult? undo();
  rust.EditResult? redo();

  // --- persistence (§Phase 4) ------------------------------------------------
  //
  // The editor asks the core to write the file; it never writes one itself. That
  // is the same division as everything else here — Rust owns the document, and a
  // file *is* the document — and it is what puts the atomic save, the journal
  // and the backups all on one path with no way round them.

  /// Whether there are edits the file does not have (§6's `doc_dirty`).
  bool get dirty;

  /// The file this document is, or null for one that has never been saved.
  String? get path;

  /// `(edits in the journal since the last save, whether the journal is
  /// broken)`. The status bar shows both.
  (int, bool) get journalState;

  /// Whether another program writing this file would be noticed *promptly*.
  ///
  /// False on a machine where the watch could not be placed — no inotify, no
  /// watch descriptors left, a filesystem that cannot be watched. It is not a
  /// statement about safety: a save checks the file it is replacing either way,
  /// and refuses one it does not recognise. It is a statement about warning, and
  /// the status bar says it for the whole session because a writer who thinks
  /// they will be told will not go looking.
  bool get watched;

  /// Writes the file. Never throws: a failure comes back as
  /// [files.SaveOutcome_Failed] with the reason, because §Phase 4 wants
  /// read-only, full-disk and permission-denied each handled with their own
  /// message and a Save As escape hatch.
  Future<files.SaveOutcome> save();

  /// Writes the file somewhere else, and **follows it there**: path, journal,
  /// backups, watch and library entry all move.
  ///
  /// Refuses a destination that already exists — unless it is this script's own
  /// file, or [overwrite] says otherwise — and refuses one that is a *different*
  /// script open here at all. Both refusals are the core's, so the confirmation
  /// below is a question the dialog asks rather than a check it performs.
  Future<files.SaveOutcome> saveAs(String path, {bool overwrite = false});

  /// Writes a copy somewhere else and **stays where it is** (§6's
  /// `doc_export_fountain`). The session, its path, its journal and its dirty
  /// flag are all untouched, so this is what an export command calls and
  /// [saveAs] is what Save As calls — they are not interchangeable (ADR 0029).
  ///
  /// Refuses a destination that already exists unless [overwrite] says
  /// otherwise, and refuses one that is a script open here at all.
  Future<files.SaveOutcome> exportFountain(
    String path, {
    bool overwrite = false,
  });

  /// Write an interchange copy only after warnings for this exact revision
  /// have been approved. A changed snapshot requires fresh confirmation.
  Future<files.FdxExportOutcome> exportFdx(
    String path, {
    bool overwrite = false,
    int? confirmedRevision,
  });

  /// The same as [save] but quieter: changed backup snapshots are throttled to
  /// ten minutes, and nothing to write is [files.SaveOutcome_Unchanged].
  Future<files.SaveOutcome> autosave();

  /// `(the document has unsaved edits, the file on disk differs)` — the two
  /// facts §Phase 4's external-modification rule turns on. Null when there is no
  /// file to compare against.
  Future<(bool, bool)?> externalChange();

  /// "Take Theirs": drops what is in memory, including the undo history, and
  /// reads the file again. [onlyIfClean] makes an automatic reload refuse an
  /// edit that landed after its external-change check.
  Future<bool> reload({bool onlyIfClean = false});

  /// "Keep mine": the writer has seen what is in the file and chosen their own
  /// version, so the next save may replace it.
  ///
  /// A save refuses a file it does not recognise
  /// ([SaveFailure.changedOnDisk]), which is what keeps an autosave off
  /// somebody else's edit on a machine with no watcher. This is the answer to
  /// that refusal, and the only one that keeps both the writer's text and their
  /// ability to save it.
  Future<bool> acceptDiskState();

  /// Every rolling backup of this script, newest first.
  Future<List<files.BackupView>> backups();

  /// Reads a literal, immutable snapshot without changing this script.
  Future<files.BackupReadOutcome> readBackup(String backupPath);

  /// Writes that viewed snapshot to a new file; never replaces an existing file.
  /// The current path, dirty flag, journal and history remain untouched.
  Future<files.SaveOutcome> copyBackup(String source, String path);

  /// Restores one, having first backed up what is there now (§Phase 4).
  Future<files.SaveOutcome> restoreBackup(String backupPath);

  /// Tells the core where the writer is, so that a quit comes back to it. In
  /// memory only: this runs for every row scrolled past.
  void setScrollRow(int row);

  /// Writes that position down, so that a process that dies comes back to it
  /// as well. Asked for once scrolling has settled, because it is a file write.
  Future<void> parkScrollRow();

  void close();
}

/// The real thing: a handle into the Rust core.
class RustDocumentCore implements DocumentCore, ScreenplayOutput {
  RustDocumentCore._(this._handle);

  /// A new, empty script.
  factory RustDocumentCore.create() => RustDocumentCore._(rust.docNew());

  /// A script parsed from Fountain source.
  factory RustDocumentCore.parse(String source) =>
      RustDocumentCore._(rust.docParse(source: source));

  /// A script the core already has open — what `library_open` and
  /// `recovery_accept` hand back.
  factory RustDocumentCore.of(rust.DocumentHandle handle) =>
      RustDocumentCore._(handle);

  final rust.DocumentHandle _handle;
  @override
  int get eventHandle => _handle.id;

  @override
  Future<layout.PaginationOutcome> paginate(layout.PageSetup setup) =>
      layout.docPaginate(handle: _handle, setup: setup);

  @override
  Future<files.SaveOutcome> exportPdf(
    String path, {
    required layout.PageSetup setup,
    bool overwrite = false,
  }) => files.docExportPdf(
    handle: _handle,
    setup: setup,
    path: path,
    overwrite: overwrite,
  );

  @override
  int get blockCount => rust.docBlockCount(handle: _handle);

  @override
  List<rust.BlockView> blocks(int from, int to) =>
      rust.docBlocks(handle: _handle, from: from, to: to);

  @override
  rust.NavigatorView navigator() => rust.docNavigator(handle: _handle);

  @override
  String source() => rust.docSource(handle: _handle);

  @override
  List<rust.TitleEntryView> titlePage() => rust.docTitlePage(handle: _handle);

  @override
  rust.EditOutcome setTitleField(String key, String value) =>
      rust.docSetTitleField(handle: _handle, key: key, value: value);

  @override
  rust.EditOutcome apply(
    rust.EditCommand command, {
    rust.DocSelection? before,
  }) => rust.docApply(handle: _handle, command: command, before: before);

  @override
  rust.EditOutcome numberScenes(rust.DocSelection at) =>
      rust.docNumberScenes(handle: _handle, at: at);

  @override
  rust.EditOutcome removeSceneNumbers(rust.DocSelection at) =>
      rust.docRemoveSceneNumbers(handle: _handle, at: at);

  @override
  rust.EditOutcome paste(
    rust.DocSelection at,
    String text, {
    required bool plain,
  }) => rust.docPaste(handle: _handle, at: at, text: text, plain: plain);

  @override
  rust.EditOutcome enter(rust.DocSelection at) =>
      rust.docEnter(handle: _handle, at: at);

  @override
  rust.EditOutcome lineBreak(rust.DocSelection at) =>
      rust.docLineBreak(handle: _handle, at: at);

  @override
  rust.EditOutcome formatSelection(
    rust.DocSelection at,
    rust.InlineStyle style,
  ) => rust.docFormatSelection(handle: _handle, at: at, style: style);

  @override
  rust.EditOutcome omitSelection(rust.DocSelection at) =>
      rust.docOmitSelection(handle: _handle, at: at);

  @override
  rust.EditOutcome omitScene(rust.DocSelection at) =>
      rust.docOmitScene(handle: _handle, at: at);

  @override
  rust.EditOutcome restoreOmitted(rust.DocSelection at) =>
      rust.docRestoreOmitted(handle: _handle, at: at);

  @override
  rust.EditOutcome? tab(rust.DocSelection at, {required bool shift}) =>
      rust.docTab(handle: _handle, at: at, shift: shift);

  @override
  rust.BlockKind? tabTarget(int block, {required bool shift}) =>
      rust.docTabTarget(handle: _handle, block: block, shift: shift);

  @override
  String? characterSuggestion(int block) =>
      rust.docCharacterSuggestion(handle: _handle, block: block);

  @override
  List<rust.Completion> complete(
    int block,
    int offsetUtf16,
    List<String> suppressed,
  ) => rust.docComplete(
    handle: _handle,
    block: block,
    offsetUtf16: offsetUtf16,
    suppressed: suppressed,
  );

  @override
  bool setEntityPinned(rust.CompletionKind kind, String value, bool pinned) =>
      rust.docSetEntityPinned(
        handle: _handle,
        kind: kind,
        value: value,
        pinned: pinned,
      );

  @override
  spell.SpellStatus spellStatus() => spell.spellStatus();

  @override
  Future<spell.SpellActionResult> configureSpelling({
    required bool enabled,
    String? language,
  }) => spell.spellConfigure(enabled: enabled, language: language);

  @override
  Future<spell.SpellCheckResult> spellCheckBlock(int block) =>
      spell.spellCheckBlock(handle: _handle, block: block);

  @override
  Future<List<String>> spellSuggest(String word) =>
      spell.spellSuggest(word: word);

  @override
  spell.SpellActionResult spellIgnoreOnce(spell.Misspelling misspelling) =>
      spell.spellIgnoreOnce(
        handle: _handle,
        block: misspelling.block,
        startUtf16: misspelling.startUtf16,
        endUtf16: misspelling.endUtf16,
        word: misspelling.word,
      );

  @override
  spell.SpellActionResult spellIgnoreAll(String word) =>
      spell.spellIgnoreAll(handle: _handle, word: word);

  @override
  Future<spell.SpellActionResult> spellAddPersonal(String word) =>
      spell.spellAddPersonal(word: word);

  @override
  Future<spell.SpellActionResult> spellAddProject(String word) =>
      spell.spellAddProject(handle: _handle, word: word);

  @override
  List<rust.FindMatch> find(rust.FindQuery query) =>
      rust.docFind(handle: _handle, query: query);

  @override
  rust.EditOutcome replaceAll(rust.FindQuery query, String with_) =>
      rust.docReplaceAll(handle: _handle, query: query, with_: with_);

  @override
  String? extract(rust.DocPosition from, rust.DocPosition to) =>
      rust.docExtract(handle: _handle, from: from, to: to);

  @override
  rust.EditResult? undo() => rust.docUndo(handle: _handle);

  @override
  rust.EditResult? redo() => rust.docRedo(handle: _handle);

  @override
  bool get dirty => files.docDirty(handle: _handle);

  @override
  String? get path => files.docPath(handle: _handle);

  @override
  (int, bool) get journalState => files.docJournalState(handle: _handle);

  @override
  bool get watched => files.docWatchState(handle: _handle);

  @override
  Future<files.SaveOutcome> save() => files.docSave(handle: _handle);

  @override
  Future<files.SaveOutcome> saveAs(String path, {bool overwrite = false}) =>
      files.docSaveAs(handle: _handle, path: path, overwrite: overwrite);

  @override
  Future<files.SaveOutcome> exportFountain(
    String path, {
    bool overwrite = false,
  }) => files.docExportFountain(
    handle: _handle,
    path: path,
    overwrite: overwrite,
  );

  @override
  Future<files.FdxExportOutcome> exportFdx(
    String path, {
    bool overwrite = false,
    int? confirmedRevision,
  }) => files.docExportFdx(
    handle: _handle,
    path: path,
    overwrite: overwrite,
    confirmedRevision: confirmedRevision,
  );

  @override
  Future<files.SaveOutcome> autosave() => files.docAutosave(handle: _handle);

  @override
  Future<(bool, bool)?> externalChange() =>
      files.docExternalChange(handle: _handle);

  @override
  Future<bool> reload({bool onlyIfClean = false}) =>
      files.docReload(handle: _handle, onlyIfClean: onlyIfClean);

  @override
  Future<bool> acceptDiskState() => files.docAcceptDiskState(handle: _handle);

  @override
  Future<List<files.BackupView>> backups() =>
      files.backupsList(handle: _handle);

  @override
  Future<files.BackupReadOutcome> readBackup(String backupPath) =>
      files.backupRead(backupPath: backupPath);

  @override
  Future<files.SaveOutcome> copyBackup(String source, String path) =>
      files.backupCopy(handle: _handle, source: source, path: path);

  @override
  Future<files.SaveOutcome> restoreBackup(String backupPath) =>
      files.backupRestore(handle: _handle, backupPath: backupPath);

  @override
  void setScrollRow(int row) => files.docSetScroll(handle: _handle, row: row);

  @override
  Future<void> parkScrollRow() => files.sessionPark();

  @override
  void close() => rust.docClose(handle: _handle);
}

/// A script that is already open in the core.
///
/// `library_open` and `recovery_accept` hand back a handle rather than source,
/// because the core has already parsed the file and started its journal. This is
/// how the editor picks one up.
extension OpenedScript on rust.DocumentHandle {
  DocumentCore get core => RustDocumentCore.of(this);
}
