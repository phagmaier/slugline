import 'package:flutter/material.dart';

Future<String?> renameProjectDialog(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(current: current),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.current});
  final String current;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename script'),
    content: TextField(
      controller: _name,
      autofocus: true,
      onSubmitted: (name) => Navigator.pop(context, name),
      decoration: const InputDecoration(labelText: 'Display name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('Rename'),
      ),
    ],
  );
}
