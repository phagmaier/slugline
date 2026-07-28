import 'dart:async';

import 'package:flutter/material.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/elements.dart';
import 'package:slugline/editor/metrics.dart';
import 'package:slugline/editor/page_indicator.dart';
import 'package:slugline/editor/save_status.dart';
import 'package:slugline/theme.dart';

/// The bar along the bottom: what element the caret is in, how big the script
/// is, and whether the file has what is on screen.
///
/// §Phase 3 asks for a "visible element selector in the UI showing the current
/// block's type". It is a menu, so it also *sets* the type — and the digit beside
/// each entry is there to teach the shortcut, because a writer who uses the menu
/// twice should never need it a third time.
///
/// Everything to the right of it answers "how much have I written", and answers
/// it in a screenwriter's units. It used to say "2880 blocks", which is this
/// program's word for a paragraph and nobody else's: a block is how the document
/// is stored, and a writer who wants to know how long their script is means
/// pages, then scenes, then words. The counts are Rust's — pages and words from
/// the paginated snapshot, scenes from the navigator — and none of them is
/// computed here.
class ElementBar extends StatelessWidget {
  const ElementBar({
    required this.controller,
    this.saveStatus,
    this.pageIndicator,
    this.sceneCount,
    super.key,
  });

  final EditorController controller;

  /// What the save state is, in a few words. Null before Phase 4's persistence
  /// is attached — which is what a widget test driving the bar alone does.
  final SaveStatus? saveStatus;

  final PageIndicator? pageIndicator;

  /// How many scenes the navigator found. Null when there is no navigator data
  /// yet, which is not the same as zero and is not shown as one.
  final int? sceneCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = context.colours;
    return Material(
      // A region: the same raised surface as the top bar and the navigator, and
      // a hairline where it meets the script rather than a shadow over it.
      color: colours.surfaceRaised,
      shape: Border(top: hairline(colours)),
      child: SizedBox(
        // Shorter than it was. A status bar is read at a glance and never
        // typed into, so it gives its height back to the script.
        height: 28,
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
                    flex: 2,
                    child: _ElementSelector(
                      controller: controller,
                      block: block,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The hint takes the slack a `Spacer` would, so that the
                  // counts on the right stay right-aligned — and it is the first
                  // thing to give up room, because it is the one thing here the
                  // writer can also read off the keyboard. Both it and the
                  // rejection ellipsize: a bar that overflows paints nothing at
                  // all where the text was, and this bar's job is to be read.
                  // The weights are the priority order, and they matter: every
                  // child of this row is flexible, so an equal share each meant
                  // the longest label — the counts — was the one that got
                  // ellipsized while a hint the writer can read off the keyboard
                  // kept its room. The hint gives up space first because it is
                  // the only thing here said twice.
                  Expanded(child: _TabHint(controller: controller)),
                  if (rejection != null)
                    Flexible(
                      child: Text(
                        rejectionMessage(rejection),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _statusStyle(theme, colours.danger),
                      ),
                    ),
                  if (pageIndicator != null || sceneCount != null) ...[
                    const SizedBox(width: 16),
                    // Flexible, like everything else along here: a `Row` that
                    // overflows does not shrink, it paints past its edge and
                    // drops what is left — which is how the counts went missing
                    // from a tiled window in the first place.
                    Flexible(
                      flex: 4,
                      child: _ScriptSize(
                        indicator: pageIndicator,
                        sceneCount: sceneCount,
                      ),
                    ),
                  ],
                  if (saveStatus case final status?) ...[
                    const SizedBox(width: 12),
                    Flexible(flex: 2, child: _SaveStatusLabel(status: status)),
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

/// One size for everything in this bar, and the third weight of text.
///
/// The bar is furniture: it has to be legible when looked at and silent when
/// not. Stating it once here is what keeps the four labels along it from
/// drifting into four different sizes, which is what they had done.
TextStyle? _statusStyle(ThemeData theme, Color colour) =>
    theme.textTheme.labelSmall?.copyWith(fontSize: 11, color: colour);

/// Pages, scenes and words — the three answers to "how long is this".
///
/// Separated by a middle dot rather than boxed or spaced apart: they are one
/// reading, taken together, and three bordered cells along a 28-pixel bar would
/// be three times the furniture for the same three numbers.
class _ScriptSize extends StatelessWidget {
  const _ScriptSize({required this.indicator, required this.sceneCount});

  /// Null before Phase 4's pagination is attached — a widget test driving the
  /// bar alone — and then there are no pages and no words to report, only
  /// whatever the navigator knows.
  final PageIndicator? indicator;
  final int? sceneCount;

  @override
  Widget build(BuildContext context) {
    final indicator = this.indicator;
    if (indicator == null) return _text(context, const []);
    return AnimatedBuilder(
      animation: indicator,
      builder: (context, _) => _text(context, [
        indicator.label,
        // Absent until the first pagination lands, like the page count and for
        // the same reason: there is no honest number yet, and a zero would be a
        // wrong one rather than a missing one.
        if (indicator.words case final words?) '${_grouped(words)} words',
      ]),
    );
  }

  Widget _text(BuildContext context, List<String> fromPagination) {
    final theme = Theme.of(context);
    final colours = context.colours;
    final parts = <String>[
      if (fromPagination.isNotEmpty) fromPagination.first,
      if (sceneCount case final scenes?)
        '$scenes ${scenes == 1 ? 'scene' : 'scenes'}',
      ...fromPagination.skip(1),
    ];
    return Text(
      parts.join('  ·  '),
      key: const ValueKey('editor-page-indicator'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: parts.join(', '),
      style: _statusStyle(theme, colours.textTertiary)?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// `12345` as `12,345`. A five-figure word count is the normal case for a
/// feature, and unseparated it is the one number on this bar that has to be
/// counted rather than read.
String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Whether the file has what is on screen.
///
/// A dot and a relative time in the ordinary case — "saved 2 minutes ago" —
/// because that is the question actually being asked, and "saved" alone never
/// said how long ago.
///
/// **Only in the ordinary case.** [SaveStatus.label] carries sentences that have
/// to be read rather than summarised: a write that failed and why, the count of
/// edits the journal is holding, and the two that describe the whole session and
/// go on being said for the rest of it — "recovery record unavailable" and
/// "external changes not watched". [SaveStatus.isPlainSaved] is what says a
/// timestamp may stand in, and when it does not, the sentence is shown whole.
class _SaveStatusLabel extends StatefulWidget {
  const _SaveStatusLabel({required this.status});

  final SaveStatus status;

  @override
  State<_SaveStatusLabel> createState() => _SaveStatusLabelState();
}

class _SaveStatusLabelState extends State<_SaveStatusLabel> {
  /// "2 minutes ago" goes stale on its own, without anything notifying: an idle
  /// script fires no edit, no save and no core event, so nothing else here would
  /// ever rebuild this line. A minute is the resolution the text is written to,
  /// and this is the clock ADR 0014 says such things are allowed to keep — in
  /// Dart, where every other "in N seconds" in this application already lives.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = context.colours;
    final status = widget.status;
    return AnimatedBuilder(
      animation: status,
      builder: (context, _) {
        final plain = status.isPlainSaved;
        final colour = status.isError
            ? colours.danger
            : plain
            ? colours.textTertiary
            : colours.textSecondary;
        final since = plain ? _ago(status.savedAtMillis) : null;
        final text = switch ((plain, since)) {
          (true, final ago?) => 'saved $ago',
          // Saved, but not by this session — the file was opened and has not
          // been written since. "saved" is the whole of what is known.
          (true, null) => 'saved',
          _ => status.label,
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Small, and never the accent: the accent marks what is selected,
            // and a save state is not a selection. The colour it does carry is
            // the one that matters — a failure is the only thing on this bar
            // allowed to be red.
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            Flexible(
              child: Text(
                text,
                key: const ValueKey('save-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _statusStyle(theme, colour),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// How long ago, in the coarsest unit that is still true.
///
/// A save whose time nobody recorded — the status has never seen one land, which
/// is every session that opened a clean file and has not written it — says
/// nothing rather than "56 years ago".
String? _ago(int millis) {
  if (millis <= 0) return null;
  final seconds = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(millis))
      .inSeconds;
  if (seconds < 45) return 'just now';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  final hours = (minutes / 60).round();
  if (hours < 24) return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  final days = (hours / 24).round();
  return '$days ${days == 1 ? 'day' : 'days'} ago';
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
    final colours = context.colours;
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colours.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
      ],
      // A control, and made to look like one. It was bare text with a caret
      // beside it, which is the same shape as the three read-only counts
      // further along the bar — the one thing here that can be clicked looked
      // exactly like the things that cannot. A border and a chevron are what
      // say "this opens".
      child: Container(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(hairline(colours)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _statusStyle(theme, colours.textSecondary),
              ),
            ),
            // `forced` is Fountain's own record that a human said so, and it is
            // visible in the file as a `.`, `@`, `>` or `!` — so it is worth
            // saying on screen too.
            if (block.forced)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.push_pin,
                  size: 12,
                  color: colours.textTertiary,
                ),
              ),
            if (!block.readOnly)
              Icon(
                Icons.expand_less,
                size: 14,
                color: colours.textTertiary,
              ),
          ],
        ),
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
    final colours = context.colours;
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
      style: _statusStyle(theme, colours.textTertiary),
    );
  }
}
