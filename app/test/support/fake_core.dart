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
    ),
  ]);

  final List<BlockView> _blocks;
  late int _nextId;

  /// Every command the editor sent, in order.
  final List<EditCommand> commands = [];

  /// Selections handed in with those commands, for the undo-caret assertions.
  final List<DocSelection?> priorSelections = [];

  /// Set to refuse the next edit, the way an Opaque block would.
  EditRejection? refuseWith;

  /// Completion answers are empty unless a test opts into the popup branch.
  /// Keep at least one such test: the real entity index is commonly non-empty.
  List<Completion> completions = const [];

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
      _ => _unchanged(),
    };
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
  BlockKind? tabTarget(int block, {required bool shift}) => tabAnswer;

  /// What [characterSuggestion] answers, for the element bar's hint.
  String? suggestion;

  @override
  String? characterSuggestion(int block) => suggestion;

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

  @override
  EditResult? undo() {
    if (_undo.isEmpty) return null;
    _redo.add(List.of(_blocks));
    return _restore(_undo.removeLast());
  }

  @override
  EditResult? redo() {
    if (_redo.isEmpty) return null;
    _undo.add(List.of(_blocks));
    return _restore(_redo.removeLast());
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
  (int, bool) get journalState => (_journalled, false);

  @override
  Future<SaveOutcome> save() async => _write(filePath, autosave: false);

  @override
  Future<SaveOutcome> saveAs(String path) async {
    filePath = path;
    return _write(path, autosave: false);
  }

  @override
  Future<SaveOutcome> autosave() async {
    if (!_dirty) return const SaveOutcome.unchanged();
    return _write(filePath, autosave: true);
  }

  /// Every export the editor asked for, in order, as `(path, overwrite)`.
  final List<(String, bool)> exports = [];

  /// The destinations an export must refuse: what `AlreadyExists` and
  /// `ScriptIsOpen` are for in the real core, without a filesystem to have them
  /// in.
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
  Future<List<BackupView>> backups() async => const [];

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
    final beforeIds = before.map((b) => b.id).toSet();
    return EditResult(
      changed: [
        for (final block in _blocks)
          if (beforeIds.contains(block.id)) block,
      ],
      removed: [
        for (final block in before)
          if (!_blocks.any((other) => other.id == block.id)) block.id,
      ],
      inserted: [
        for (var i = 0; i < _blocks.length; i++)
          if (!beforeIds.contains(_blocks[i].id))
            InsertedBlock(index: i, block: _blocks[i]),
      ],
      selection: DocSelection(
        anchor: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
        focus: DocPosition(block: _blocks.first.id, offsetUtf16: 0),
      ),
      blockCount: _blocks.length,
    );
  }

  EditOutcome _applied({
    List<BlockView> changed = const [],
    List<int> removed = const [],
    List<InsertedBlock> inserted = const [],
    required DocPosition? caret,
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
        selection: caret == null
            ? null
            : DocSelection(anchor: caret, focus: caret),
        blockCount: _blocks.length,
      ),
    );
  }

  BlockView _copy(
    BlockView block, {
    int? id,
    BlockKind? kind,
    String? text,
    bool? forced,
  }) => BlockView(
    id: id ?? block.id,
    kind: kind ?? block.kind,
    sectionLevel: block.sectionLevel,
    text: text ?? block.text,
    forced: forced ?? block.forced,
    dual: block.dual,
    readOnly: block.readOnly,
  );
}
