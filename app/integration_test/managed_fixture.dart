import 'dart:convert';
import 'dart:io';

/// Test-only disk fixtures. Product creation/import stays in the real bridge.
/// Names map to a stable supported sidecar; a second lookup never recreates text.
class ManagedFixtures {
  ManagedFixtures(this.root);
  final Directory root;
  final _paths = <String, String>{};
  String path(String name) => _paths.putIfAbsent(name, () {
    final id = (_paths.length + 1).toRadixString(16).padLeft(32, '0');
    final project = Directory('${root.path}/data/library/$name--$id')
      ..createSync(recursive: true);
    Directory('${project.path}/versions').createSync();
    File('${project.path}/project.json').writeAsStringSync(
      jsonEncode({
        'version': 1,
        'id': id,
        'name': name.replaceFirst(RegExp(r'\.fountain$'), ''),
        'archived': false,
        'pinned_entities': <Object>[],
      }),
    );
    File('${project.path}/script.fountain').writeAsStringSync('');
    return '${project.path}/script.fountain';
  });
}
