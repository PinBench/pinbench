import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:pinbench/features/workspace/data/workspace_fs.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';

/// Characterization tests for the template-provenance ("pristine hash")
/// piece of [CompilerService] (see docs/plans/radiant-mixing-pudding.md
/// Phase 0), written before Phase 2 extracts it into its own
/// `TemplateProvenanceService`.
///
/// `compileWorkspace`'s web-only pristine-hash fallback branch itself can't
/// be exercised here: `dart test`/`flutter test` runs on the native VM, where
/// `PlatformCapabilities.supportsLocalCompile` is always true, so that branch
/// is unreachable outside an actual web run. These tests instead pin down the
/// on-disk contract the branch depends on: the `.pristine_hash` sidecar file
/// name/format and the `pristineSourceHashes` in-memory map, both of which
/// Phase 2's extraction must preserve exactly (other code, e.g.
/// `WorkspaceFiles._scanFiles`, filters the sidecar out of the file tree by
/// this exact name).
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('compiler_service_test_');
    CompilerService.pristineSourceHashes.clear();
  });

  tearDown(() {
    CompilerService.pristineSourceHashes.clear();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('pristineHashFileName is the stable sidecar name other code filters by', () {
    expect(CompilerService.pristineHashFileName, '.pristine_hash');
  });

  test('pristineSourceHashes is a plain in-memory map keyed by workspace directory', () {
    final dirPath = tempDir.path;
    expect(CompilerService.pristineSourceHashes[dirPath], isNull);

    CompilerService.pristineSourceHashes[dirPath] = 'pristine source'.hashCode;

    expect(CompilerService.pristineSourceHashes[dirPath], 'pristine source'.hashCode);
  });

  test('the on-disk sidecar file round-trips an int hash via int.tryParse', () async {
    final fs = WorkspaceFs();
    final sidecarPath = p.join(tempDir.path, CompilerService.pristineHashFileName);
    final hash = 'void setup() {}\nvoid loop() {}\n'.hashCode;

    await fs.writeString(sidecarPath, hash.toString());

    expect(fs.existsFile(sidecarPath), isTrue);
    expect(int.tryParse(fs.readStringSync(sidecarPath)), hash);
  });

  test(
    'compileWorkspace throws a CompilerException when no .ino/.hex exists (native path)',
    () async {
      // On native (this test's platform), PlatformCapabilities.supportsLocalCompile
      // is true, so compileWorkspace takes the arduino-cli subprocess path. With
      // no arduino-cli reachable in a bare temp dir and no sketch to compile,
      // it must fail with a CompilerException rather than hang or crash.
      await expectLater(
        CompilerService.compileWorkspace(tempDir.path),
        throwsA(isA<CompilerException>()),
      );
    },
  );
}
