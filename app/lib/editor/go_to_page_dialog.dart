import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slugline/editor/page_indicator.dart';

/// Chooses a page from the editor's existing pagination, without paginating or
/// deriving a page boundary in the dialog.
class GoToPageDialog extends StatefulWidget {
  const GoToPageDialog({required this.indicator, super.key});

  final PageIndicator indicator;

  static Future<int?> show(BuildContext context, PageIndicator indicator) =>
      showDialog<int>(
        context: context,
        builder: (_) => GoToPageDialog(indicator: indicator),
      );

  @override
  State<GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<GoToPageDialog> {
  late final TextEditingController _page;
  String? _error;

  @override
  void initState() {
    super.initState();
    final text = '${widget.indicator.current ?? 1}';
    _page = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _submit() {
    final total = widget.indicator.total;
    if (total == null || total < 1) return;
    final page = int.tryParse(_page.text.trim());
    if (page == null || page < 1 || page > total) {
      setState(() => _error = 'Enter a whole page number from 1 to $total.');
      return;
    }
    if (widget.indicator.positionForPage(page) == null) {
      setState(() => _error = 'That page is not available yet. Try again.');
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.indicator,
    builder: (context, _) {
      final total = widget.indicator.total;
      final available = total != null && total > 0;
      return Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
            _submit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: const Text('Go to page'),
          content: SizedBox(
            width: 280,
            child: TextField(
              controller: _page,
              autofocus: true,
              enabled: available,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Page number',
                helperText: total == null
                    ? 'Pages are not available yet.'
                    : total == 0
                    ? 'This script has no printed pages.'
                    : '1–$total',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: available ? _submit : null,
              child: const Text('Go'),
            ),
          ],
        ),
      );
    },
  );
}
