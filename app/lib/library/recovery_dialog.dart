import 'package:flutter/material.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/identity.dart';
import 'package:slugline/theme.dart';
import 'package:slugline/widgets/escape_dismissible.dart';

/// §Phase 4's crash-recovery prompt.
///
/// > On startup, an un-truncated journal means the previous session crashed →
/// > offer recovery. Recovery presents a diff summary ("14 edits since last
/// > save") and Recover / Discard, **never auto-applies**.
///
/// The "never auto-applies" is the load-bearing part, and it is why this is a
/// dialog and not a splash screen. Nothing has been done to any file by the time
/// this appears: the core has read the journals and counted them, and that is
/// all. Recovering opens a *dirty* document — the file on disk is still the one
/// from before the crash — so even after choosing Recover, the writer still has
/// to say yes by saving.
///
/// Discard is deliberately not the default and deliberately not first. It
/// deletes the only copy of work that is not anywhere else.
class RecoveryDialog extends StatelessWidget {
  const RecoveryDialog({required this.offers, super.key});

  final List<RecoveryOffer> offers;

  /// Shows the prompt and returns what to do with each offer, keyed by its
  /// journal path. Absent means "leave it alone" — which is what closing the
  /// dialog does, and which is the safe answer.
  static Future<Map<String, RecoveryChoice>> show(
    BuildContext context,
    List<RecoveryOffer> offers,
  ) async {
    if (offers.isEmpty) return const {};
    final chosen = await showDialog<Map<String, RecoveryChoice>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EscapeDismissible(
        child: RecoveryDialog(offers: offers),
      ),
    );
    return chosen ?? const {};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = <String, RecoveryChoice>{};

    return AlertDialog(
      icon: const Icon(Icons.restore_page_outlined),
      title: Text(
        offers.length == 1
            ? '$applicationName closed unexpectedly'
            : '$applicationName closed unexpectedly with ${offers.length} scripts open',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These edits were made after the last save. Nothing has been '
              'written to any of your files.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final offer in offers)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.title, style: theme.textTheme.titleSmall),
                      if (offer.script.isNotEmpty)
                        Text(
                          offer.script,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 6),
                      Text(
                        summaryOf(offer),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (offer.blocked case final why?) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Cannot be recovered: $why',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.colours.danger,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              choices[offer.journal] = RecoveryChoice.discard;
                              Navigator.of(context).pop(choices);
                            },
                            child: const Text('Discard'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: offer.blocked != null
                                ? null
                                : () {
                                    choices[offer.journal] = RecoveryChoice.recover;
                                    Navigator.of(context).pop(choices);
                                  },
                            child: const Text('Recover'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(choices),
          child: const Text('Decide later'),
        ),
      ],
    );
  }

  /// §Phase 4's "14 edits since last save", with the two things that change what
  /// it means: whether the script was ever saved, and whether the last record
  /// was cut off.
  static String summaryOf(RecoveryOffer offer) {
    final edits = offer.edits == 1 ? '1 edit' : '${offer.edits} edits';
    final since = offer.script.isEmpty ? 'in a script never saved' : 'since the last save';
    final damaged = offer.damaged
        ? ' The very last keystroke was not written in full and is gone.'
        : '';
    return '$edits $since.$damaged';
  }
}

enum RecoveryChoice { recover, discard }

/// Recovery replayed the edits but could not write the journal that would carry
/// them through a *second* crash.
///
/// The old journal is deliberately still on disk, so what is on screen is not at
/// risk; what is at risk is everything typed from here, which is not being
/// recorded by anything. Saying so is the whole point — §Phase 4 treats losing
/// user text as a P0 defect, and a session that has quietly stopped journalling
/// looks exactly like one that has not.
Future<void> showRecoveryNotJournalled(
  BuildContext context,
  String message,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => EscapeDismissible(child: AlertDialog(
      icon: const Icon(Icons.warning_amber_outlined),
      title: const Text('Recovered, but not protected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your recovered text is here and the crash journal it came from is '
            'still on disk. But a new journal could not be written, so nothing '
            'you type from now on would survive another crash.',
          ),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(
            'Save this script somewhere writable, or restart $applicationName — the '
            'recovery will be offered again.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue'),
        ),
      ],
    )),
  );
}

/// Recovery could not be taken at all. Nothing was opened and nothing was
/// deleted, so the offer will still be there next launch — which is what the
/// last line says, because otherwise a failed recovery reads like a lost script.
Future<void> showRecoveryFailed(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => EscapeDismissible(child: AlertDialog(
      icon: const Icon(Icons.error_outline),
      title: const Text('That recovery could not be opened'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          Text(
            'Nothing was changed and nothing was deleted. The crash journal is '
            'still on disk and will be offered again next time you start.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    )),
  );
}
