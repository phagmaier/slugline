import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gives a deliberately non-click-away dialog Phase 10's Escape route.
///
/// `barrierDismissible: false` is still useful for save/recovery failures: an
/// accidental click outside must not make serious information vanish. Escape
/// is an intentional keyboard action and safely returns the dialog's null
/// result, which every caller already treats as Cancel or Decide later.
class EscapeDismissible extends StatelessWidget {
  const EscapeDismissible({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
