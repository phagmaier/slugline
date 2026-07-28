import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/save_status.dart';

/// The bar along the bottom: what element the caret is in, what Tab would do
/// next, and whether the last edit was refused.
///
/// §Phase 3 asks for a "visible element selector in the UI showing the current
/// block's type". It is a menu, so it also *sets* the type — and the digit beside
/// each entry is there to teach the shortcut, because a writer who uses the menu
/// twice should never need it a third time.
class ElementBar extends StatelessWidget {
  const ElementBar({required this.controller, this.saveStatus, super.key});

  final EditorController controller;

  /// What the save state is, in a few words. Null before Phase 4's persistence
  /// is attached — which is what a widget test driving the bar alone does.
  final SaveStatus? saveStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 34,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final block = controller.focusedBlock;
            final rejection = controller.lastRejection;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Flexible(
                    child: _ElementSelector(controller: controller, block: block),
                  ),
                  const SizedBox(width: 10),
                  // The hint takes the slack the `Spacer` used to, so that the
                  // counts on the right stay right-aligned — and it is the first
                  // thing to give up room, because it is the one thing here the
                  // writer can also read off the keyboard. Both it and the
                  // rejection ellipsize: a bar that overflows paints nothing at
                  // all where the text was, and this bar's job is to be read.
                  Expanded(child: _TabHint(controller: controller)),
                  if (rejection != null)
                    Flexible(
                      child: Text(
                        rejectionMessage(rejection),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      '${controller.blocks.length} blocks',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.disabledColor),
                    ),
                  ),
                  if (saveStatus case final status?) ...[
                    const SizedBox(width: 12),
                    Flexible(child: _SaveStatusLabel(status: status)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Whether the file has what is on screen.
///
/// Words rather than an icon, because the two states a writer needs to tell
/// apart — "saved" and "not saved yet" — are worth being unambiguous about, and
/// because a dot in a corner is exactly the kind of thing people stop seeing.
class _SaveStatusLabel extends StatelessWidget {
  const _SaveStatusLabel({required this.status});

  final SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: status,
      builder: (context, _) => Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: status.isError ? theme.colorScheme.error : theme.disabledColor,
        ),
      ),
    );
  }
}

/// Two of these are ordinary things to try, not bugs, so they get a sentence a
/// writer can act on. The rest are the core telling us we asked wrongly.
String rejectionMessage(EditRejection rejection) => switch (rejection) {
      EditRejection.notEditable =>
        'That block round-trips verbatim and cannot be edited.',
      EditRejection.noBlockAfter => 'Nothing to join this to.',
      _ => 'That edit was refused.',
    };

class _ElementSelector extends StatelessWidget {
  const _ElementSelector({required this.controller, required this.block});

  final EditorController controller;
  final BlockView block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = kindLabel(block.kind, block.sectionLevel);
    return PopupMenuButton<ElementChoice>(
      key: const Key('element-selector'),
      tooltip: 'Element type',
      // Read-only content has no type to set (§3.2), so the menu says the type
      // and offers nothing.
      enabled: !block.readOnly,
      onSelected: (choice) =>
          controller.setKind(choice.kind, sectionLevel: choice.sectionLevel),
      itemBuilder: (context) => [
        for (final choice in elementChoices)
          PopupMenuItem(
            value: choice,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: choice.kind == block.kind
                      ? const Icon(Icons.check, size: 15)
                      : null,
                ),
                Expanded(child: Text(choice.label)),
                if (choice.shortcut.isNotEmpty)
                  Text(
                    choice.shortcut,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.disabledColor),
                  ),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          // `forced` is Fountain's own record that a human said so, and it is
          // visible in the file as a `.`, `@`, `>` or `!` — so it is worth
          // saying on screen too.
          if (block.forced)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.push_pin, size: 13, color: theme.disabledColor),
            ),
          if (!block.readOnly) const Icon(Icons.arrow_drop_up, size: 18),
        ],
      ),
    );
  }
}

/// What Tab would do from here, and the character cue the core suggests.
///
/// Both come from the core: the Tab target from `document/src/workflow.rs`, the
/// suggestion from `Document::character_suggestion`. Dart shows them; it does not
/// work them out (§2.1).
class _TabHint extends StatelessWidget {
  const _TabHint({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = controller.characterSuggestion;
    final target = controller.tabTarget();
    final label = switch ((suggestion, target)) {
      (final name?, _) => 'Tab: Character — $name',
      (null, final kind?) => 'Tab: ${kindLabel(kind, 1)}',
      _ => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      key: const Key('tab-hint'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(color: theme.disabledColor),
    );
  }
}
