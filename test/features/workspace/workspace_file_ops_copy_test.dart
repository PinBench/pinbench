import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:pinbench/features/workspace/data/workspace_fs.dart';
import 'package:pinbench/features/workspace/services/workspace_file_ops_service.dart';

/// `copyDirectory` backs "Duplicate Workspace", so the copy has to be the whole
/// workspace: nested folders included, and the original left untouched.
void main() {
  late Directory source;
  late Directory destination;
  late WorkspaceFileOpsService ops;

  setUp(() {
    source = Directory.systemTemp.createTempSync('copy_dir_source');
    destination = Directory.systemTemp.createTempSync('copy_dir_dest');
    ops = WorkspaceFileOpsService(WorkspaceFs());
  });

  tearDown(() {
    for (final dir in [source, destination]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  void write(Directory root, String relativePath, String content) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  List<String> contentsOf(Directory root) => [
    for (final entity in root.listSync(recursive: true).whereType<File>())
      p.relative(entity.path, from: root.path),
  ]..sort();

  test('copies nested files and folders', () async {
    write(source, 'sketch.ino', 'void setup() {}');
    write(source, 'circuit.cdl', 'Circuit {\n}\n');
    write(source, 'lib/helper/pin_map.h', '#define LED 13');

    await ops.copyDirectory(source.path, destination.path);

    expect(contentsOf(destination), ['circuit.cdl', 'lib/helper/pin_map.h', 'sketch.ino']);
    expect(
      File(p.join(destination.path, 'lib/helper/pin_map.h')).readAsStringSync(),
      '#define LED 13',
    );
  });

  test('leaves the original alone', () async {
    write(source, 'sketch.ino', 'original');

    await ops.copyDirectory(source.path, destination.path);
    File(p.join(destination.path, 'sketch.ino')).writeAsStringSync('edited copy');

    expect(File(p.join(source.path, 'sketch.ino')).readAsStringSync(), 'original');
  });

  test('an empty workspace copies to an empty one', () async {
    await ops.copyDirectory(source.path, destination.path);

    expect(contentsOf(destination), isEmpty);
  });
}
