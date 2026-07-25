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
    _nextId = _blocks.fold(0, (highest, b) => b.id > highest ? b.id : highest) + 1;
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

  @override
  int get blockCount => _blocks.length;

  /// How many times the editor has read blocks out of the core. §6 says an edit
  /// is applied as a patch and not refetched, so a test can watch this stay at 1.
  int blockReads = 0;

  @override
  List<BlockView> blocks(int from, int to) {
    blockReads++;
    return _blocks.sublist(
        from.clamp(0, _blocks.length), to.clamp(0, _blocks.length));
  }

  @override
  String source() => _blocks.map((b) => b.text).join('\n\n');

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
      return EditOutcome.rejected(reason: reason, message: 'refused by the test');
    }
    _undo.add(List.of(_blocks));
    return switch (command) {
      EditCommand_ReplaceText(:final block, :final startUtf16, :final endUtf16, :final with_) =>
        _replaceText(block, startUtf16, endUtf16, with_),
      EditCommand_SplitBlock(:final block, :final atUtf16) => _split(block, atUtf16),
      EditCommand_MergeBlocks(:final first) => _merge(first),
      EditCommand_SetKind(:final block, :final kind, :final forced) =>
        _setKind(block, kind, forced),
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
      final joined = _blocks[first].text.substring(0, start.offsetUtf16) +
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
      text: _blocks[index]
          .text
          .replaceRange(start.offsetUtf16, start.offsetUtf16, flat),
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

  (DocPosition, DocPosition) _ordered(DocSelection selection) {
    final anchor = _indexOf(selection.anchor.block);
    final focus = _indexOf(selection.focus.block);
    final anchorFirst = anchor < focus ||
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

  @override
  void close() {}

  // --- the surgery ---------------------------------------------------------

  int _indexOf(int id) => _blocks.indexWhere((block) => block.id == id);

  EditOutcome _replaceText(int id, int start, int end, String with_) {
    final index = _indexOf(id);
    final block = _blocks[index];
    _blocks[index] = _copy(block, text: block.text.replaceRange(start, end, with_));
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
    final text = _blocks[first].text.substring(0, from.offsetUtf16) +
        _blocks[last].text.substring(to.offsetUtf16);
    final removed = [
      for (var i = first + 1; i <= last; i++) _blocks[i].id,
    ];
    _blocks.removeRange(first + 1, last + 1);
    _blocks[first] = _copy(_blocks[first], text: text);
    return _applied(
      changed: [_blocks[first]],
      removed: removed,
      caret: from,
    );
  }

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
  }) =>
      EditOutcome.applied(
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

  BlockView _copy(BlockView block, {int? id, BlockKind? kind, String? text, bool? forced}) =>
      BlockView(
        id: id ?? block.id,
        kind: kind ?? block.kind,
        sectionLevel: block.sectionLevel,
        text: text ?? block.text,
        forced: forced ?? block.forced,
        dual: block.dual,
        readOnly: block.readOnly,
      );
}
