import 'package:flutter/material.dart';

import 'package:slugline/editor/command_palette.dart';
import 'package:slugline/editor/commands.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/editor/element_bar.dart';
import 'package:slugline/editor/find_bar.dart';

/// The editor, the two panels that can sit over it, and the element bar.
///
/// The panels are children of this page rather than routes or dialogs. §Phase 3
/// requires that Escape dismisses whichever is open "and never loses text", and
/// the only way to be sure of that is for the same widget to own both the panel
/// and the surface underneath it: closing one is `setState`, and the document is
/// not involved at all.
class EditorPage extends StatefulWidget {
  const EditorPage({required this.controller, super.key});

  final EditorController controller;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: EditorSurface(
                    controller: widget.controller,
                    focusNode: _editorFocus,
                    // The surface has the focus, so it sees these keys first and
                    // hands the ones that are not editing back up here.
                    onOpenPalette: () => _show(_Panel.palette),
                    onOpenFind: () => _show(_Panel.find),
                    onEscape: _dismiss,
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
                      ),
                      onDismiss: _dismiss,
                    ),
                  ),
              ],
            ),
          ),
          ElementBar(controller: widget.controller),
        ],
      ),
    );
  }
}

enum _Panel { none, find, palette }
