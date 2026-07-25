import 'package:slugline/src/rust/api/doc.dart' as rust;

export 'package:slugline/src/rust/api/doc.dart'
    show
        BlockKind,
        BlockView,
        DocPosition,
        DocSelection,
        DocumentHandle,
        EditCommand,
        EditCommand_DeleteRange,
        EditCommand_InsertBlocks,
        EditCommand_MergeBlocks,
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
        NewBlock;

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
  int get blockCount;

  /// Blocks `from..to`, clamped to what exists.
  List<rust.BlockView> blocks(int from, int to);

  /// The whole document as Fountain — what a save would write.
  String source();

  /// Applies one command. [before] is the selection the user had before the
  /// edit, so that undo restores the caret as well as the text (§3.4).
  rust.EditOutcome apply(rust.EditCommand command, {rust.DocSelection? before});

  /// Replaces [at] with [text] in one undo transaction. [plain] is
  /// `Ctrl+Shift+V`: Action blocks, no element inference.
  rust.EditOutcome paste(rust.DocSelection at, String text, {required bool plain});

  /// Enter: the block splits and whatever appears below it takes the element
  /// type `docs/KEYMAP.md` says follows this one. One undo step, even though it
  /// may be a delete, a split and a kind change.
  rust.EditOutcome enter(rust.DocSelection at);

  /// Tab, or Shift+Tab, on the block the caret is in. `null` where the table
  /// says Tab does nothing there — not a refusal, just no next element type.
  rust.EditOutcome? tab(rust.DocSelection at, {required bool shift});

  /// The element type Tab would move to, without moving. For the element bar.
  rust.BlockKind? tabTarget(int block, {required bool shift});

  /// A character cue the script already has whose name this block's text
  /// matches. A suggestion: the core never acts on it.
  String? characterSuggestion(int block);

  /// Every match of [query], in document order.
  List<rust.FindMatch> find(rust.FindQuery query);

  /// Replaces every match with [with_], as one undo transaction.
  rust.EditOutcome replaceAll(rust.FindQuery query, String with_);

  /// The Fountain text between two positions, for the clipboard.
  String? extract(rust.DocPosition from, rust.DocPosition to);

  rust.EditResult? undo();
  rust.EditResult? redo();

  void close();
}

/// The real thing: a handle into the Rust core.
class RustDocumentCore implements DocumentCore {
  RustDocumentCore._(this._handle);

  /// A new, empty script.
  factory RustDocumentCore.create() => RustDocumentCore._(rust.docNew());

  /// A script parsed from Fountain source.
  factory RustDocumentCore.parse(String source) =>
      RustDocumentCore._(rust.docParse(source: source));

  final rust.DocumentHandle _handle;

  @override
  int get blockCount => rust.docBlockCount(handle: _handle);

  @override
  List<rust.BlockView> blocks(int from, int to) =>
      rust.docBlocks(handle: _handle, from: from, to: to);

  @override
  String source() => rust.docSource(handle: _handle);

  @override
  rust.EditOutcome apply(rust.EditCommand command, {rust.DocSelection? before}) =>
      rust.docApply(handle: _handle, command: command, before: before);

  @override
  rust.EditOutcome paste(rust.DocSelection at, String text, {required bool plain}) =>
      rust.docPaste(handle: _handle, at: at, text: text, plain: plain);

  @override
  rust.EditOutcome enter(rust.DocSelection at) => rust.docEnter(handle: _handle, at: at);

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
  void close() => rust.docClose(handle: _handle);
}
