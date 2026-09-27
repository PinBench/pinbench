import 'dart:io';

void main() {
  final templatesDir = Directory('assets/templates');
  if (!templatesDir.existsSync()) {
    stdout.writeln('No templates directory found.');
    return;
  }

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stdout.writeln('No pubspec.yaml found.');
    return;
  }

  final directories = templatesDir
      .listSync()
      .whereType<Directory>()
      .map((e) => e.path.replaceAll(r'\', '/'))
      .toList();
  directories.sort();

  final lines = pubspecFile.readAsLinesSync();
  final newLines = <String>[];
  var insideAssets = false;
  var replacedTemplates = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.trim() == 'assets:') {
      insideAssets = true;
      newLines.add(line);
      continue;
    }

    if (insideAssets) {
      // Skip existing template declarations
      if (line.trim().startsWith('- assets/templates/')) {
        continue;
      }
      
      // If it's another asset line (e.g., - assets/parts/arduino/)
      if (line.trim().startsWith('- ')) {
        newLines.add(line);
        continue;
      }

      // End of assets section
      if (line.trim().isEmpty || !line.startsWith(' ')) {
        if (!replacedTemplates) {
          for (final dir in directories) {
            final folderName = dir.split('/').last;
            newLines.add('    - assets/templates/$folderName/');
          }
          replacedTemplates = true;
        }
        insideAssets = false;
        newLines.add(line);
        continue;
      }
      
      newLines.add(line);
    } else {
      newLines.add(line);
    }
  }

  if (insideAssets && !replacedTemplates) {
    for (final dir in directories) {
      final folderName = dir.split('/').last;
      newLines.add('    - assets/templates/$folderName/');
    }
  }

  pubspecFile.writeAsStringSync('${newLines.join('\n')}\n');
  stdout.writeln('✅ Updated pubspec.yaml with latest templates.');
}
