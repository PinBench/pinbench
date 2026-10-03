import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_parts/models/board_profile.dart';

import 'package:pinbench/features/workspace/data/workspace_fs.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';

/// Characterization tests for the template-provenance ("pristine hash")
/// piece of [CompilerService] (see docs/plans/radiant-mixing-pudding.md
/// Phase 0), written before Phase 2 extracts it into its own
/// `TemplateProvenanceService`.
///
/// `dart test`/`flutter test` runs on the native VM, where
/// `PlatformCapabilities.supportsLocalCompile` is always true, so the web
/// branch of `compileWorkspace` is tested through `compileWorkspaceOnWeb`.
/// The rest pins down the on-disk contract that branch depends on: the
/// `.pristine_hash` sidecar file name/format and the `pristineSourceHashes`
/// in-memory map (other code, e.g. `WorkspaceFiles._scanFiles`, filters the
/// sidecar out of the file tree by this exact name).
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

  group('compileWorkspaceOnWeb', () {
    const source = 'void setup() {}\nvoid loop() {}\n';
    const hex = ':00000001FF\n';
    late String dir;
    late List<String> remoteCalls;

    Future<String> remote(
      String directoryPath,
      String compileApiUrl, {
      BoardProfile board = BoardProfile.arduinoUno,
    }) async {
      remoteCalls.add(compileApiUrl);
      return 'remote hex';
    }

    Future<String> build({String compileApiUrl = 'https://compile.example'}) =>
        CompilerService.compileWorkspaceOnWeb(
          dir,
          board: BoardProfile.arduinoUno,
          compileApiUrl: compileApiUrl,
          remote: remote,
        );

    setUp(() {
      remoteCalls = [];
      dir = p.join(tempDir.path, 'blink');
      Directory(dir).createSync();
      File(p.join(dir, 'blink.ino')).writeAsStringSync(source);
      File(p.join(dir, 'blink.ino.hex')).writeAsStringSync(hex);
    });

    test('an untouched example runs its bundled hex, without the compile service', () async {
      CompilerService.pristineSourceHashes[dir] = source.hashCode;
      expect(await build(), hex);
      expect(remoteCalls, isEmpty);
    });

    test('an edited example goes to the compile service', () async {
      CompilerService.pristineSourceHashes[dir] = 'the template as shipped'.hashCode;
      expect(await build(), 'remote hex');
      expect(remoteCalls, ['https://compile.example']);
    });

    test('a sketch of unknown provenance goes to the compile service', () async {
      expect(await build(), 'remote hex');
      expect(remoteCalls, hasLength(1));
    });

    test('an edited example without a compile service fails, never running the old hex', () async {
      CompilerService.pristineSourceHashes[dir] = 'the template as shipped'.hashCode;
      await expectLater(
        build(compileApiUrl: ''),
        throwsA(
          isA<CompilerException>().having(
            (e) => e.message,
            'message',
            contains("You've edited this sketch"),
          ),
        ),
      );
    });

    test('a sketch that is no template fails without a compile service', () async {
      File(p.join(dir, 'blink.ino.hex')).deleteSync();
      await expectLater(
        build(compileApiUrl: ''),
        throwsA(
          isA<CompilerException>().having(
            (e) => e.message,
            'message',
            contains('bundled example templates'),
          ),
        ),
      );
    });
  });
}
