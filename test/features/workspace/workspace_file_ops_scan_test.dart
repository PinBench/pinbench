import 'dart:io';

import 'package:pinbench/features/workspace/data/workspace_fs.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';
import 'package:pinbench/features/workspace/services/workspace_file_ops_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `scanFiles` decides two things at once, which is why its exclusions are
/// worth pinning: it is both what the explorer renders *and* the exact set of
/// paths `pushAllFiles` uploads to a cloud project. A file added here is a file
/// stored in the database.
void main() {
  late Directory tempDir;
  late WorkspaceFileOpsService ops;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('scan_files_test');
    ops = WorkspaceFileOpsService(WorkspaceFs());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void write(String relativePath, [String content = 'x']) {
    final file = File(p.join(tempDir.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  List<String> scan() => [
    for (final entity in ops.scanFiles(tempDir.path)) p.relative(entity.path, from: tempDir.path),
  ];

  test('keeps the files a project is actually made of', () {
    write('sketch.ino');
    write('circuit.cdl');
    write('README.md');

    expect(scan(), containsAll(['sketch.ino', 'circuit.cdl', 'README.md']));
  });

  test('excludes compiled .hex, so build output is neither shown nor synced', () {
    write('sketch.ino');
    write('sketch.ino.hex');

    expect(scan(), ['sketch.ino']);
  });

  test('excludes .hex regardless of case', () {
    // Windows workspaces and hand-renamed files produce these.
    write('FIRMWARE.HEX');
    write('Sketch.Hex');
    write('sketch.ino');

    expect(scan(), ['sketch.ino']);
  });

  test('does not exclude a file merely containing "hex"', () {
    // The filter is an extension check, not a substring one — a sketch about
    // hexadecimal conversion is a source file like any other.
    write('hex_display.ino');
    write('hexdump.cdl');

    expect(scan(), containsAll(['hex_display.ino', 'hexdump.cdl']));
  });

  test('excludes the provenance sidecar and build/VCS directories', () {
    write(CompilerService.pristineHashFileName);
    write('build/output.txt');
    write('.git/config');
    write('.dart_tool/package_config.json');
    write('sketch.ino');

    expect(scan(), ['sketch.ino']);
  });
}
