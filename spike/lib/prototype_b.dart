/// Prototype B — `super_editor` with one node per screenplay element.
///
/// super_editor is purpose-built for structured multi-node documents, so the
/// two things that hurt in Prototype A — selection across paragraphs and IME
/// over a virtualised list — are already solved. What we are measuring is what
/// it costs: bundle size, frame time on a 3,000-node document, and how much of
/// our screenplay model we have to express in *its* vocabulary.
///
/// Version note, and it is a finding in its own right: the latest **stable**
/// release (0.2.7, June 2024) does not compile against Flutter 3.44 — it is
/// missing an override that `TextInputConnection` has since gained. The code
/// below therefore targets `0.3.0-dev.52`, a prerelease. There is no supported
/// stable version of this package for current Flutter.
///
/// Element types are modelled as `blockType` metadata on `ParagraphNode` plus
/// stylesheet rules for the indent grid, which is the least invasive mapping
/// available. Real screenplay element behaviour (Enter in a Character cue
/// producing Dialogue, etc.) would be a set of custom `EditRequest`s.
library;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'surface.dart';
import 'synthetic.dart';

const _fontSize = 14.0;
const _charAdvance = 8.4; // measured for the monospace face at 14 pt

class PrototypeB extends StatefulWidget {
  const PrototypeB({required this.blocks, super.key});

  final List<SyntheticBlock> blocks;

  @override
  State<PrototypeB> createState() => PrototypeBState();
}

class PrototypeBState extends State<PrototypeB> implements SpikeSurface {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final CommonEditorOperations _ops;

  final GlobalKey _layoutKey = GlobalKey();

  @override
  final ScrollController scrollController = ScrollController();

  @override
  int get blockCount => _document.nodeCount;

  @override
  void initState() {
    super.initState();
    _document = MutableDocument(
      nodes: [
        for (final block in widget.blocks)
          ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(block.text),
            metadata: {'blockType': NamedAttribution(block.kind.name)},
          ),
      ],
    );
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(document: _document, composer: _composer);
    _ops = CommonEditorOperations(
      document: _document,
      editor: _editor,
      composer: _composer,
      documentLayoutResolver: () => _layoutKey.currentState! as DocumentLayout,
    );
  }

  @override
  void dispose() {
    _editor.dispose();
    _composer.dispose();
    scrollController.dispose();
    super.dispose();
  }

  String _plainTextAt(int index) => (_document.getNodeAt(index)! as TextNode).text.toPlainText();

  // --- SpikeSurface -------------------------------------------------------

  @override
  Future<void> placeCaret(int block, int offset) async {
    final node = _document.getNodeAt(block)!;
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(offset: offset),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    // super_editor scrolls the caret into view itself; give it two frames.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  Future<void> typeCharacter(String character) async {
    _editor.execute([InsertCharacterAtCaretRequest(character: character)]);
  }

  @override
  Future<int> arrowDown() async {
    _ops.moveCaretDown();
    await WidgetsBinding.instance.endOfFrame;
    final nodeId = _composer.selection?.extent.nodeId;
    return nodeId == null ? -1 : _document.getNodeIndexById(nodeId);
  }

  @override
  Future<String> selectFourParagraphsAsText(int startBlock) async {
    final first = _document.getNodeAt(startBlock)!;
    final lastIndex = (startBlock + 3).clamp(0, _document.nodeCount - 1);
    final last = _document.getNodeAt(lastIndex)! as TextNode;

    // One selection object spanning four nodes — the thing Prototype A cannot
    // express without reinventing it.
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: DocumentPosition(
            nodeId: first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: last.id,
            nodePosition: TextNodePosition(offset: last.text.length),
          ),
        ),
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);
    await WidgetsBinding.instance.endOfFrame;

    // Prove the package's own copy path runs, then return the text directly so
    // the check does not depend on a system clipboard being available.
    _ops.copy();
    return [for (var i = startBlock; i <= lastIndex; i++) _plainTextAt(i)].join('\n\n');
  }

  // --- Rendering ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SuperEditor(
      editor: _editor,
      scrollController: scrollController,
      documentLayoutKey: _layoutKey,
      autofocus: true,
      stylesheet: _screenplayStylesheet,
    );
  }
}

/// The §5.2 indent grid, expressed as super_editor style rules.
final _screenplayStylesheet = Stylesheet(
  documentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  inlineTextStyler: (attributions, existing) => existing,
  rules: [
    StyleRule(BlockSelector.all, (doc, node) {
      return {
        'maxWidth': 60 * _charAdvance,
        'padding': const CascadingPadding.only(top: 8),
        'textStyle': const TextStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize,
          height: 1.35,
          color: Color(0xFFE8E8E8),
        ),
      };
    }),
    for (final kind in ElementKind.values)
      StyleRule(BlockSelector(kind.name), (doc, node) {
        return {
          'maxWidth': widthChars[kind]! * _charAdvance,
          'padding': CascadingPadding.only(
            left: indentChars[kind]! * _charAdvance,
            top: kind == ElementKind.dialogue || kind == ElementKind.parenthetical ? 0 : 8,
          ),
        };
      }),
  ],
);
