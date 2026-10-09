import 'dart:async';

import 'package:slugline/core/document_core.dart';

/// A [DocumentCore] for widget tests.
///
/// `flutter test` runs on the Dart VM with no native library loaded, so a widget
/// test cannot reach the real core. This stands in for it and does **list
/// surgery only**: split a string, join two strings, drop a range. It infers
/// nothing, re-classifies nothing, and knows no Fountain — every rule about what
/// a screenplay is stays in Rust, where `cargo test` covers it (§2.1).
///
/// What it is for is the half of the behaviour that genuinely lives in Dart:
/// that Enter issues a split at the caret, that Backspace at offset 0 issues a
/// merge with the block above, that the patch coming back is applied rather than
/// the document refetched. It records every command so a test can assert on the
/// *command*, not just on the text it happened to produce.
class FakeCore implements DocumentCore {
  FakeCore(List<BlockView> blocks) : _blocks = List.of(blocks) {
    _nextId =
        _blocks.fold(0, (highest, b) => b.id > highest ? b.id : highest) + 1;
  }

  /// A one-block document of the given kind.
  factory FakeCore.single(BlockKind kind, String text) => FakeCore([
    BlockView(
      id: 1,
      kind: kind,
      sectionLevel: 0,
      text: text,
      forced: false,
      dual: false,
      readOnly: false,
      inlineRuns: const [],
    ),
  ]);

  final List<BlockView> _blocks;

  @override
  int eventHandle = 0;
  late int _nextId;

  /// Every command the editor sent, in order.
  final List<EditCommand> commands = [];

  @override
  EditOutcome formatSelection(DocSelection at, InlineStyle style) =>
      const EditOutcome.rejected(
        reason: EditRejection.badRange,
        message: 'Formatting semantics require the native core.',
      );

  /// Selections handed in with commands, for the undo-caret assertions.
  final List<DocSelection?> priorSelections = [];

  /// Set to refuse the next edit, the way an Opaque block would.
  EditRejection? refuseWith;

  /// Completion answers are empty unless a test opts into the popup branch.
  /// Keep at least one such test: the real entity index is commonly non-empty.
  List<Completion> completions = const [];

  /// Explicit navigator data for widget tests. The double does not derive this
  /// from blocks: scene parsing and entity indexing belong to Rust.
  NavigatorView navigatorData = const NavigatorView(
    scenes: [],
    characters: [],
    outline: [],
  );

  /// Explicit semantic answers: this double applies supplied text patches, it
  /// does not recognise or generate Fountain scene-number suffixes.
  Map<int, String> numberedSceneTexts = {};
  Map<int, String> removedSceneNumberTexts = {};
  DocSelection? numberedSceneSelection;
  DocSelection? removedSceneNumberSelection;

  SpellStatus spellStatusData = const SpellStatus(
    enabled: false,
    language: null,
    languages: [],
    message: 'Spell checking is off.',
  );

  final Map<int, List<Misspelling>> spellings = {};
  int spellChecks = 0;
  Duration spellCheckDelay = Duration.zero;
  final List<(String, String)> spellActions = [];

  @override
  NavigatorView navigator() => navigatorData;

  @override
  SpellStatus spellStatus() => spellStatusData;

  @override
  Future<SpellActionResult> configureSpelling({
    required bool enabled,
    String? language,
  }) async {
    spellStatusData = SpellStatus(
      enabled: enabled,
      language: language ?? spellStatusData.language,
      languages: spellStatusData.languages,
      message: enabled ? 'Checking.' : 'Spell checking is off.',
    );
    return const SpellActionResult.applied();
  }

  @override
  Future<SpellCheckResult> spellCheckBlock(int block) async {
    spellChecks++;
    if (spellCheckDelay != Duration.zero) {
      await Future<void>.delayed(spellCheckDelay);
    }
    return SpellCheckResult(
      block: block,
      current: true,
      cached: false,
      misspellings: List.of(spellings[block] ?? const []),
    );
  }

  @override
  Future<List<String>> spellSuggest(String word) async => ['$word-suggestion'];

  @override
  SpellActionResult spellIgnoreOnce(Misspelling misspelling) {
    spellActions.add(('once', misspelling.word));
    spellings[misspelling.block]?.remove(misspelling);
    return const SpellActionResult.applied();
  }

  @override
  SpellActionResult spellIgnoreAll(String word) {
    spellActions.add(('all', word));
    for (final words in spellings.values) {
      words.removeWhere((misspelling) => misspelling.word == word);
    }
    return const SpellActionResult.applied();
  }

  @override
  Future<SpellActionResult> spellAddPersonal(String word) async {
    spellActions.add(('personal', word));
    return const SpellActionResult.applied();
  }

  @override
  Future<SpellActionResult> spellAddProject(String word) async {
    spellActions.add(('project', word));
    return const SpellActionResult.applied();
  }

  @override
  List<Completion> complete(
    int block,
    int offsetUtf16,
    List<String> suppressed,
  ) => completions
      .where((candidate) => !suppressed.contains(candidate.value))
      .toList();

  @override
  bool setEntityPinned(CompletionKind kind, String value, bool pinned) {
    final index = completions.indexWhere(
      (candidate) => candidate.kind == kind && candidate.value == value,
    );
    if (index < 0) return false;
    final candidate = completions[index];
    completions[index] = Completion(
      kind: candidate.kind,
      value: candidate.value,
      startUtf16: candidate.startUtf16,
      endUtf16: candidate.endUtf16,
      frequency: candidate.frequency,
      pinned: pinned,
    );
    return true;
  }

  @override
  int get blockCount => _blocks.length;

  /// How many times the editor has read blocks out of the core. §6 says an edit
  /// is applied as a patch and not refetched, so a test can watch this stay at 1.
  int blockReads = 0;

  @override
  List<BlockView> blocks(int from, int to) {
    blockReads++;
    return _blocks.sublist(
      from.clamp(0, _blocks.length),
      to.clamp(0, _blocks.length),
    );
  }

  @override
  String source() => _blocks.map((b) => b.text).join('\n\n');

  /// The title page, as `Key: value` in the order it was written.
  ///
  /// A list rather than a map so that the order a save would write is the order
  /// this hands back — and list surgery, like everything else here. Which keys
  /// mean the same thing, and what canonical order is, are Fountain questions
  /// and are answered in Rust (ADR 0011).
  final List<TitleEntryView> title = [];

  /// Every field the editor set, in order, as `(key, value)`.
  final List<(String, String)> titleEdits = [];

  @override
  List<TitleEntryView> titlePage() => List.of(title);

  @override
  EditOutcome setTitleField(String key, String value) {
    titleEdits.add((key, value));
    final at = title.indexWhere((entry) => entry.key == key);
    // The real core answers "nothing happened" for a value that is already
    // there, and the dialog leans on it — so this does too.
    if (at < 0 ? value.isEmpty : title[at].value == value) {
      return _applied(caret: null);
    }
    if (value.isEmpty) {
      title.removeAt(at);
    } else if (at < 0) {
      title.add(TitleEntryView(key: key, value: value));
    } else {
      title[at] = TitleEntryView(key: key, value: value);
    }
    _dirty = true;
    _journalled++;
    return _applied(caret: null);
  }

  @override
  String? extract(DocPosition from, DocPosition to) {
    final first = _indexOf(from.block);
    final last = _indexOf(to.block);
    if (first == last) {
      return _blocks[first].text.substring(from.offsetUtf16, to.offsetUtf16);
    }
    return [
      _blocks[first].text.substring(from.offsetUtf16),
      for (var i = first + 1; i < last; i++) _blocks[i].text,
      _blocks[last].text.substring(0, to.offsetUtf16),
    ].join('\n\n');
  }

  @override
  EditOutcome numberScenes(DocSelection at) =>
      _sceneNumbers(numberedSceneTexts, at, numberedSceneSelection ?? at);

  @override
  EditOutcome removeSceneNumbers(DocSelection at) => _sceneNumbers(
    removedSceneNumberTexts,
    at,
    removedSceneNumberSelection ?? at,
  );

  EditOutcome _sceneNumbers(
    Map<int, String> texts,
    DocSelection before,
    DocSelection after,
  ) {
    final changed = [
      for (final block in _blocks)
        if (texts.containsKey(block.id) && texts[block.id] != block.text)
          _copy(block, text: texts[block.id]),
    ];
    if (changed.isNotEmpty) {
      final snapshot = List<BlockView>.of(_blocks);
      _dualSelections[snapshot] = before;
      _oppositeSelections[snapshot] = after;
      _undo.add(snapshot);
      _redo.clear();
      for (final block in changed) {
        _blocks[_indexOf(block.id)] = block;
      }
    }
    return _applied(changed: changed, caret: null, selection: after);
  }

  @override
  EditOutcome apply(EditCommand command, {DocSelection? before}) {
    commands.add(command);
    priorSelections.add(before);
    if (refuseWith case final reason?) {
      refuseWith = null;
      return EditOutcome.rejected(
        reason: reason,
        message: 'refused by the test',
      );
    }
    if (command case EditCommand_SetDual(:final block, :final dual)) {
      return _setDual(block, dual, before);
    }
    _undo.add(List.of(_blocks));
    return switch (command) {
      EditCommand_ReplaceText(
        :final block,
        :final startUtf16,
        :final endUtf16,
        :final with_,
      ) =>
        _replaceText(block, startUtf16, endUtf16, with_),
      EditCommand_SplitBlock(:final block, :final atUtf16) => _split(
        block,
        atUtf16,
      ),
      EditCommand_MergeBlocks(:final first) => _merge(first),
      EditCommand_SetKind(:final block, :final kind, :final forced) => _setKind(
        block,
        kind,
        forced,
      ),
      EditCommand_DeleteRange(:final from, :final to) => _deleteRange(from, to),
      EditCommand_MoveScene(:final scene, :final before) => _moveScene(
        scene,
        before,
      ),
      _ => _unchanged(),
    };
  }

  EditOutcome _moveScene(int scene, int? before) {
    final start = _indexOf(scene);
    final nextScene = navigatorData.scenes
        .map((candidate) => candidate.block)
        .where((block) => _indexOf(block) > start)
        .firstOrNull;
    final end = nextScene == null
        ? _blocks.length - 1
        : _indexOf(nextScene) - 1;
    final target = before == null ? _blocks.length : _indexOf(before);
    if (start > end || (target >= start && target <= end + 1)) {
      return _unchanged();
    }
    final oldOrder = _blocks.map((block) => block.id).toList();
    final moved = _blocks.sublist(start, end + 1);
    _blocks.removeRange(start, end + 1);
    final destination = target > end ? target - moved.length : target;
    _blocks.insertAll(destination, moved);
    final newOrder = _blocks.map((block) => block.id).toList();
    _syncNavigatorOrder();
    final relocated = [
      for (var i = 0; i < oldOrder.length; i++)
        if (oldOrder[i] != newOrder[i]) oldOrder[i],
    ];
    final inserted = [
      for (final id in relocated)
        InsertedBlock(index: _indexOf(id), block: _blocks[_indexOf(id)]),
    ]..sort((a, b) => a.index.compareTo(b.index));
    return _applied(
      removed: relocated,
      inserted: inserted,
      caret: DocPosition(block: scene, offsetUtf16: 0),
    );
  }

  /// Replaces the selection with the text, as one patch — which is the only
  /// part of the real paste this needs to imitate. Newlines become spaces: what
  /// text turns into which blocks is Fountain's business, and Fountain is in
  /// Rust.
  @override
  EditOutcome paste(DocSelection at, String text, {required bool plain}) {
    pastes.add((at, text, plain));
    _undo.add(List.of(_blocks));
    final (start, end) = _ordered(at);

    final removed = <int>[];
    if (start != end) {
      final first = _indexOf(start.block);
      final last = _indexOf(end.block);
      final joined =
          _blocks[first].text.substring(0, start.offsetUtf16) +
          _blocks[last].text.substring(end.offsetUtf16);
      for (var i = first + 1; i <= last; i++) {
        removed.add(_blocks[i].id);
      }
      _blocks.removeRange(first + 1, last + 1);
      _blocks[first] = _copy(_blocks[first], text: joined);
    }

    final index = _indexOf(start.block);
    final flat = text.replaceAll('\n', ' ');
    _blocks[index] = _copy(
      _blocks[index],
      text: _blocks[index].text.replaceRange(
        start.offsetUtf16,
        start.offsetUtf16,
        flat,
      ),
    );
    return _applied(
      changed: [_blocks[index]],
      removed: removed,
      caret: DocPosition(
        block: start.block,
        offsetUtf16: start.offsetUtf16 + flat.length,
      ),
    );
  }

  /// Enter, as **list surgery only**: delete the selection, split at the caret.
  ///
  /// The real core also gives the block it creates the element type
  /// `docs/KEYMAP.md` says follows this one, and this deliberately does not.
  /// That table is screenplay semantics, it lives in `document/src/workflow.rs`,
  /// and `cargo test` covers it there — a second copy of it here would be a
  /// second copy that can disagree. What a widget test can prove is what this
  /// records: that Enter reaches the core at all, with the right caret.
  @override
  EditOutcome enter(DocSelection at) {
    enters.add(at);
    final (start, end) = _ordered(at);
    if (start != end) {
      final outcome = start.block == end.block
          ? apply(
              EditCommand.replaceText(
                block: start.block,
                startUtf16: start.offsetUtf16,
                endUtf16: end.offsetUtf16,
                with_: '',
              ),
            )
          : apply(EditCommand.deleteRange(from: start, to: end));
      if (outcome is EditOutcome_Rejected) return outcome;
    }
    return apply(
      EditCommand.splitBlock(block: start.block, atUtf16: start.offsetUtf16),
    );
  }

  /// Every Enter, in order.
  final List<DocSelection> enters = [];

  /// Only list surgery; Rust tests cover which kinds fall back to Enter.
  @override
  EditOutcome lineBreak(DocSelection at) {
    lineBreaks.add(at);
    final (start, end) = _ordered(at);
    _undo.add(List.of(_blocks));
    if (start != end) {
      _deleteRange(start, end);
    }
    final command = EditCommand.replaceText(
      block: start.block,
      startUtf16: start.offsetUtf16,
      endUtf16: start.offsetUtf16,
      with_: '\n',
    );
    commands.add(command);
    priorSelections.add(at);
    return _replaceText(
      start.block,
      start.offsetUtf16,
      start.offsetUtf16,
      '\n',
    );
  }

  final List<DocSelection> lineBreaks = [];

  /// Every Tab, as `(selection, shift)`.
  final List<(DocSelection, bool)> tabs = [];

  /// What [tab] and [tabTarget] answer. `null` — the default — is "Tab does
  /// nothing here", which is what the real core says for most element types.
  BlockKind? tabAnswer;

  @override
  EditOutcome? tab(DocSelection at, {required bool shift}) {
    tabs.add((at, shift));
    final kind = tabAnswer;
    if (kind == null) return null;
    return apply(
      EditCommand.setKind(
        block: at.focus.block,
        kind: kind,
        sectionLevel: 0,
        forced: true,
      ),
    );
  }

  @override
  BlockKind? tabTarget(int block, {required bool shift}) {
    tabTargetCalls++;
    return tabAnswer;
  }

  /// How many times the editor asked for the Tab hint or the suggestion. The
  /// controller caches both across caret motion, so a test can prove the bar
  /// does not cross the bridge on every arrow key.
  int tabTargetCalls = 0;
  int suggestionCalls = 0;

  /// What [characterSuggestion] answers, for the element bar's hint.
  String? suggestion;

  @override
  String? characterSuggestion(int block) {
    suggestionCalls++;
    return suggestion;
  }

  /// Every query [find] was asked, in order.
  final List<FindQuery> queries = [];

  /// Plain substring search over the block texts. Enough for the find bar's own
  /// behaviour — match count, next, previous — and no more: the case, word and
  /// element-type rules are `document/src/find.rs`'s and are tested there.
  @override
  List<FindMatch> find(FindQuery query) {
    queries.add(query);
    if (query.text.isEmpty) return const [];
    final hits = <FindMatch>[];
    for (final block in _blocks) {
      var from = 0;
      while (true) {
        final at = block.text.indexOf(query.text, from);
        if (at < 0) break;
        hits.add(
          FindMatch(
            block: block.id,
            startUtf16: at,
            endUtf16: at + query.text.length,
          ),
        );
        from = at + query.text.length;
      }
    }
    return hits;
  }

  /// Every replacement, as `(query, replacement)`.
  final List<(FindQuery, String)> replacements = [];

  @override
  EditOutcome replaceAll(FindQuery query, String with_) {
    replacements.add((query, with_));
    _undo.add(List.of(_blocks));
    final changed = <BlockView>[];
    for (var i = 0; i < _blocks.length; i++) {
      if (!_blocks[i].text.contains(query.text)) continue;
      _blocks[i] = _copy(
        _blocks[i],
        text: _blocks[i].text.replaceAll(query.text, with_),
      );
      changed.add(_blocks[i]);
    }
    return _applied(changed: changed, caret: null);
  }

  (DocPosition, DocPosition) _ordered(DocSelection selection) {
    final anchor = _indexOf(selection.anchor.block);
    final focus = _indexOf(selection.focus.block);
    final anchorFirst =
        anchor < focus ||
        (anchor == focus &&
            selection.anchor.offsetUtf16 <= selection.focus.offsetUtf16);
    return anchorFirst
        ? (selection.anchor, selection.focus)
        : (selection.focus, selection.anchor);
  }

  /// Every paste, as `(selection, text, plain)`.
  final List<(DocSelection, String, bool)> pastes = [];

  final List<List<BlockView>> _undo = [];
  final List<List<BlockView>> _redo = [];
  final Expando<DocSelection> _dualSelections = Expando<DocSelection>();
  final Expando<DocSelection> _oppositeSelections = Expando<DocSelection>();

  @override
  EditResult? undo() {
    if (_undo.isEmpty) return null;
    final snapshot = _undo.removeLast();
    final current = List<BlockView>.of(_blocks);
    _dualSelections[current] =
        _oppositeSelections[snapshot] ?? _dualSelections[snapshot];
    _oppositeSelections[current] = _dualSelections[snapshot];
    _redo.add(current);
    return _restore(snapshot);
  }

  @override
  EditResult? redo() {
    if (_redo.isEmpty) return null;
    final snapshot = _redo.removeLast();
    final current = List<BlockView>.of(_blocks);
    _dualSelections[current] =
        _oppositeSelections[snapshot] ?? _dualSelections[snapshot];
    _oppositeSelections[current] = _dualSelections[snapshot];
    _undo.add(current);
    return _restore(snapshot);
  }

  /// How many times this session has been closed. One is the only right answer:
  /// the real core's close ends an actor thread, and a second one is a side
  /// effect applied to a session that is not there any more (F12).
  int closes = 0;

  @override
  void close() => closes++;

  // --- the surgery ---------------------------------------------------------

  int _indexOf(int id) => _blocks.indexWhere((block) => block.id == id);

  EditOutcome _replaceText(int id, int start, int end, String with_) {
    final index = _indexOf(id);
    final block = _blocks[index];
    _blocks[index] = _copy(
      block,
      text: block.text.replaceRange(start, end, with_),
    );
    return _applied(
      changed: [_blocks[index]],
      caret: DocPosition(block: id, offsetUtf16: start + with_.length),
    );
  }

  EditOutcome _split(int id, int at) {
    final index = _indexOf(id);
    final block = _blocks[index];
    final tail = _copy(block, id: _nextId++, text: block.text.substring(at));
    _blocks[index] = _copy(block, text: block.text.substring(0, at));
    _blocks.insert(index + 1, tail);
    return _applied(
      changed: [_blocks[index]],
      inserted: [InsertedBlock(index: index + 1, block: tail)],
      caret: DocPosition(block: tail.id, offsetUtf16: 0),
    );
  }

  EditOutcome _merge(int id) {
    final index = _indexOf(id);
    if (index + 1 >= _blocks.length) {
      return EditOutcome.rejected(
        reason: EditRejection.noBlockAfter,
        message: 'nothing to merge with',
      );
    }
    final first = _blocks[index];
    final second = _blocks.removeAt(index + 1);
    _blocks[index] = _copy(first, text: first.text + second.text);
    return _applied(
      changed: [_blocks[index]],
      removed: [second.id],
      caret: DocPosition(block: id, offsetUtf16: first.text.length),
    );
  }

  EditOutcome _setDual(int id, bool dual, DocSelection? before) {
    final index = _indexOf(id);
    if (index < 0) {
      return const EditOutcome.rejected(
        reason: EditRejection.unknownBlock,
        message: 'unknown block',
      );
    }
    final block = _blocks[index];
    if (block.kind != BlockKind.character || block.readOnly) {
      return EditOutcome.rejected(
        reason: block.readOnly
            ? EditRejection.notEditable
            : EditRejection.invalidBlock,
        message: 'dual requires an editable Character',
      );
    }
    final snapshot = List<BlockView>.of(_blocks);
    _dualSelections[snapshot] = before;
    _undo.add(snapshot);
    _redo.clear();
    _blocks[index] = _copy(block, dual: dual);
    return _applied(
      changed: [_blocks[index]],
      caret: before?.focus ?? DocPosition(block: id, offsetUtf16: 0),
    );
  }

  EditOutcome _setKind(int id, BlockKind kind, bool forced) {
    final index = _indexOf(id);
    _blocks[index] = _copy(_blocks[index], kind: kind, forced: forced);
    return _applied(
      changed: [_blocks[index]],
      caret: DocPosition(block: id, offsetUtf16: _blocks[index].text.length),
    );
  }

  EditOutcome _deleteRange(DocPosition from, DocPosition to) {
    final first = _indexOf(from.block);
    final last = _indexOf(to.block);
    final text =
        _blocks[first].text.substring(0, from.offsetUtf16) +
        _blocks[last].text.substring(to.offsetUtf16);
    final removed = [for (var i = first + 1; i <= last; i++) _blocks[i].id];
    _blocks.removeRange(first + 1, last + 1);
    _blocks[first] = _copy(_blocks[first], text: text);
    return _applied(changed: [_blocks[first]], removed: removed, caret: from);
  }

  // --- persistence (§Phase 4) ------------------------------------------------
  //
  // In memory, but with the same shape as the real thing: a save clears the
  // dirty flag and can be made to fail, an autosave is quiet, and the journal
  // count grows with edits and resets on save. That is enough to drive the
  // autosave timers, the save-error dialogs and the status bar in a widget test
  // — which is exactly the half of §Phase 4 that lives in Dart. The half that
  // lives on disk is proved in `cargo test`, where the disk is (ADR 0011).

  /// What the file on disk says, for the external-change tests.
  String onDisk = '';

  /// Set to hold one external-change comparison while an autosave timer fires.
  Completer<void>? holdExternalChanges;

  bool _dirty = false;
  int _journalled = 0;

  /// Set to make the next save fail, the way a full disk would.
  SaveFailure? refuseSaveWith;

  /// Set for a session the core is not journalling: one whose journal broke
  /// mid-session, or one that never got a journal at all because the state
  /// directory would not take it. The core reports both the same way, and so
  /// does this.
  bool journalUnavailable = false;

  /// Set for a session whose file could not be watched — no inotify, no watch
  /// descriptors left. The save path still checks the file it replaces, so this
  /// costs the warning and not the protection, and the status line says so.
  bool watchUnavailable = false;

  /// How many times the editor has said "keep mine" — the answer to a save the
  /// core refused because the file was not the one it last read.
  int diskStateAccepted = 0;

  /// Set to hold the next write open between planning its bytes and committing
  /// them, and cleared as soon as that write takes it.
  ///
  /// A save in the real core is three steps across two threads, and a test that
  /// cannot stop one halfway cannot say anything about what a second save does
  /// while the first is in flight. Completing this is the write reaching the
  /// disk.
  Completer<void>? holdWrites;

  /// Marks the document saved without writing anything — what an undo back to
  /// the last saved revision looks like from outside.
  void markClean() {
    _dirty = false;
    _journalled = 0;
  }

  /// Every save the editor asked for, in order, as `(path, wasAutosave)`.
  final List<(String, bool)> saves = [];

  /// What a `library_open` would have handed back: the path this is a file for.
  String? filePath;

  /// The scroll row the editor last parked.
  int scrollRow = 0;

  @override
  bool get dirty => _dirty;

  @override
  String? get path => filePath;

  @override
  (int, bool) get journalState =>
      journalUnavailable ? (0, true) : (_journalled, false);

  @override
  bool get watched => !watchUnavailable;

  @override
  Future<SaveOutcome> save() async => _write(filePath, autosave: false);

  /// Every Save As the editor asked for, in order, as `(path, overwrite)`.
  ///
  /// Kept beside [exports] on purpose: the two look alike from here and are not
  /// the same operation, and a test that means one must be able to say which
  /// one it saw (ADR 0029).
  final List<(String, bool)> saveAsCalls = [];

  @override
  Future<SaveOutcome> saveAs(String path, {bool overwrite = false}) async {
    saveAsCalls.add((path, overwrite));
    // The core's two refusals, with a set standing in for the filesystem. A Save
    // As onto the file this script already is stays allowed — it is a save.
    if (path != filePath && openScripts.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.scriptIsOpen,
        path: path,
        message: '$path is open here',
      );
    }
    if (!overwrite && path != filePath && existingFiles.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.alreadyExists,
        path: path,
        message: '$path is already there',
      );
    }
    filePath = path;
    final outcome = await _write(path, autosave: false);
    if (outcome is SaveOutcome_Saved) existingFiles.add(path);
    return outcome;
  }

  @override
  Future<SaveOutcome> autosave() async {
    if (!_dirty) return const SaveOutcome.unchanged();
    return _write(filePath, autosave: true);
  }

  /// Every export the editor asked for, in order, as `(path, overwrite)`.
  final List<(String, bool)> exports = [];

  /// The destinations an export or a Save As must refuse: what `AlreadyExists`
  /// and `ScriptIsOpen` are for in the real core, without a filesystem to have
  /// them in.
  final Set<String> existingFiles = {};
  final Set<String> openScripts = {};

  @override
  Future<SaveOutcome> exportFountain(
    String path, {
    bool overwrite = false,
  }) async {
    if (openScripts.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.scriptIsOpen,
        path: path,
        message: '$path is open here',
      );
    }
    if (!overwrite && existingFiles.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.alreadyExists,
        path: path,
        message: '$path is already there',
      );
    }
    // Deliberately touches nothing else: an export leaves the path, the dirty
    // flag and the journal count exactly as they were, and a double that
    // cleared them would let a caller confuse it with [saveAs] (ADR 0029).
    exports.add((path, overwrite));
    existingFiles.add(path);
    return SaveOutcome.saved(path: path, bytes: source().length, backup: null);
  }

  /// Scripted bridge responses only; this double does not interpret XML or
  /// decide which document content needs conversion warnings.
  final List<FdxExportOutcome> fdxOutcomes = [];
  final List<String> fdxWrites = [];

  @override
  Future<FdxExportOutcome> exportFdx(
    String path, {
    bool overwrite = false,
    int? confirmedRevision,
  }) async {
    if (fdxOutcomes.isEmpty) {
      throw StateError('The test must supply an FDX bridge response.');
    }
    final result = fdxOutcomes.removeAt(0);
    if (result case FdxExportOutcome_Finished(outcome: SaveOutcome_Saved())) {
      fdxWrites.add(path);
    }
    return result;
  }

  Future<SaveOutcome> _write(String? path, {required bool autosave}) async {
    if (path == null) {
      return const SaveOutcome.failed(
        failure: SaveFailure.noPath,
        path: '',
        message: 'this script has never been saved',
      );
    }
    saves.add((path, autosave));
    // The bytes this save is carrying, taken before it can be held. The real
    // core plans on the actor thread and then lets go of it, so text typed
    // while the file is being written is not in the file when the write lands.
    final planned = source();
    if (holdWrites case final hold?) {
      holdWrites = null;
      await hold.future;
    }
    if (refuseSaveWith case final failure?) {
      return SaveOutcome.failed(
        failure: failure,
        path: path,
        message: 'refused for the test',
      );
    }
    onDisk = planned;
    // Clean only as far as what was written — `mark_saved_at(plan.revision)`.
    if (source() == planned) {
      _dirty = false;
      _journalled = 0;
    }
    return SaveOutcome.saved(path: path, bytes: onDisk.length, backup: null);
  }

  @override
  Future<(bool, bool)?> externalChange() async {
    if (holdExternalChanges case final hold?) {
      holdExternalChanges = null;
      await hold.future;
    }
    return filePath == null ? null : (_dirty, onDisk != source());
  }

  @override
  Future<bool> reload({bool onlyIfClean = false}) async {
    if (filePath == null || (onlyIfClean && _dirty)) return false;
    _dirty = false;
    _journalled = 0;
    return true;
  }

  @override
  Future<bool> acceptDiskState() async {
    if (filePath == null) return false;
    diskStateAccepted += 1;
    // What the core does with it: the file the writer was shown is the one the
    // next save may replace. Here that is enough to stop [refuseSaveWith] from
    // standing in the way of a test that goes on to save.
    if (refuseSaveWith == SaveFailure.changedOnDisk) refuseSaveWith = null;
    return true;
  }

  @override
  Future<List<BackupView>> backups() async => const [];

  @override
  Future<BackupReadOutcome> readBackup(String backupPath) async =>
      const BackupReadOutcome.failed(message: 'that backup cannot be read');

  @override
  Future<SaveOutcome> copyBackup(String source, String path) async =>
      SaveOutcome.saved(path: path, bytes: source.length, backup: null);

  @override
  Future<SaveOutcome> restoreBackup(String backupPath) async =>
      SaveOutcome.saved(path: filePath ?? '', bytes: 0, backup: null);

  @override
  void setScrollRow(int row) => scrollRow = row;

  EditOutcome _unchanged() => _applied(caret: null);

  EditResult _restore(List<BlockView> snapshot) {
    final before = List.of(_blocks);
    _blocks
      ..clear()
      ..addAll(snapshot);
    _syncNavigatorOrder();
    final beforeById = {for (final block in before) block.id: block};
    final beforeIndex = {
      for (var i = 0; i < before.length; i++) before[i].id: i,
    };
    final moved = {
      for (var i = 0; i < _blocks.length; i++)
        if (beforeIndex[_blocks[i].id] case final old? when old != i)
          _blocks[i].id,
    };
    return EditResult(
      changed: [
        for (final block in _blocks)
          if (!moved.contains(block.id) &&
              beforeById.containsKey(block.id) &&
              beforeById[block.id] != block)
            block,
      ],
      removed: [
        for (final block in before)
          if (!_blocks.any((other) => other.id == block.id) ||
              moved.contains(block.id))
            block.id,
      ],
      inserted: [
        for (var i = 0; i < _blocks.length; i++)
          if (!beforeById.containsKey(_blocks[i].id) ||
              moved.contains(_blocks[i].id))
            InsertedBlock(index: i, block: _blocks[i]),
      ],
      selection:
          _dualSelections[snapshot] ??
          DocSelection(
            anchor: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
            focus: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
          ),
      blockCount: _blocks.length,
    );
  }

  void _syncNavigatorOrder() {
    final scenes = List<NavigatorScene>.of(navigatorData.scenes)
      ..sort(
        (a, b) => _blocks
            .indexWhere((block) => block.id == a.block)
            .compareTo(_blocks.indexWhere((block) => block.id == b.block)),
      );
    final outline = List<NavigatorNode>.of(navigatorData.outline)
      ..sort(
        (a, b) => _blocks
            .indexWhere((block) => block.id == a.block)
            .compareTo(_blocks.indexWhere((block) => block.id == b.block)),
      );
    navigatorData = NavigatorView(
      scenes: scenes,
      characters: navigatorData.characters,
      outline: outline,
    );
  }

  EditOutcome _applied({
    List<BlockView> changed = const [],
    List<int> removed = const [],
    List<InsertedBlock> inserted = const [],
    required DocPosition? caret,
    DocSelection? selection,
  }) {
    if (changed.isNotEmpty || removed.isNotEmpty || inserted.isNotEmpty) {
      _dirty = true;
      _journalled++;
    }
    return EditOutcome.applied(
      result: EditResult(
        changed: changed,
        removed: removed,
        inserted: inserted,
        blockCount: _blocks.length,
        selection:
            selection ??
            (caret == null ? null : DocSelection(anchor: caret, focus: caret)),
      ),
    );
  }

  BlockView _copy(
    BlockView block, {
    int? id,
    BlockKind? kind,
    String? text,
    bool? forced,
    bool? dual,
  }) => BlockView(
    id: id ?? block.id,
    kind: kind ?? block.kind,
    sectionLevel: block.sectionLevel,
    text: text ?? block.text,
    forced: forced ?? block.forced,
    dual: dual ?? block.dual,
    readOnly: block.readOnly,
    inlineRuns: text == null ? block.inlineRuns : const [],
  );
}
