import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/workspace_fs.dart';
import 'compiler_service.dart';

/// File-tree scanning and new-file starter content for a workspace. Extracted
/// from `WorkspaceFiles`, which previously inlined this directly in the
/// Riverpod provider — this is plain Dart (given a [WorkspaceFs]), so it's
/// unit-testable without a `ProviderContainer`.
class WorkspaceFileOpsService(final WorkspaceFs _fs) {
  /// Starter content for a new blank `.ino` sketch, also used when a cloud
  /// project with no files yet is opened for the first time.
  static const blankInoTemplate =
      'void setup() {\n  // put your setup code here, to run once:\n}\n\n'
      'void loop() {\n  // put your main code here, to run repeatedly:\n}\n';

  // Matches the canonical output of CircuitParser.generate for an empty circuit
  // so a new `.cdl` round-trips cleanly. Draw on the canvas and components/wires
  // fill in as `id := Type { … }` / `Wire { … }` blocks inside the braces.
  static const _blankCdlTemplate =
      '// Circuit description (.cdl) — kept in sync with the canvas.\n'
      '// Edit components and wires here or on the canvas; both update together.\n'
      'Circuit {\n}\n';

  /// Lists files under [dirPath] for the explorer tree, filtering out VCS/build
  /// directories, compiled `.hex` firmware and the pristine-hash provenance
  /// sidecar.
  ///
  /// This list is not only what the explorer renders — `pushAllFiles` syncs
  /// exactly these paths to the cloud, so anything excluded here is also
  /// excluded from a saved project. That makes it the right place to drop
  /// compiler output: a `.hex` is regenerable from its `.ino`, and the largest
  /// bundled one is ~30 KB, several times the rest of a project put together.
  ///
  /// Nothing reads a workspace `.hex` through this method, so hiding it is
  /// safe. The web compile fallback resolves it by direct path
  /// ([CompilerService.compileWorkspace]), which a scan filter doesn't touch,
  /// and a user-supplied hex is read through the file picker into memory —
  /// it never has to live in the workspace at all.
  List<FileSystemEntity> scanFiles(String dirPath) {
    if (!_fs.existsDir(dirPath)) return [];

    final files = _fs.listFiles(dirPath).where((path) {
      final lower = path.toLowerCase();
      return !lower.contains('/.git/') &&
          !lower.contains('/build/') &&
          !lower.contains('/.dart_tool/') &&
          !lower.endsWith('.hex') &&
          p.basename(path) != CompilerService.pristineHashFileName;
    }).toList();

    // Sort files alphabetically, then wrap as entities for the explorer tree.
    files.sort();
    return [for (final path in files) File(path)];
  }

  /// Recursively copies the directory at [sourcePath] into [destinationPath],
  /// which must already exist. Backs "Duplicate Workspace".
  ///
  /// Goes straight to `dart:io` rather than through [WorkspaceFs]: duplicating
  /// a folder is a local-filesystem operation, guarded by
  /// `PlatformCapabilities.supportsLocalFilesystem` at the call site.
  Future<void> copyDirectory(String sourcePath, String destinationPath) async {
    final source = Directory(sourcePath);
    await for (final entity in source.list(recursive: true)) {
      final destPath = '$destinationPath${entity.path.replaceFirst(source.path, '')}';
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await File(destPath).parent.create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }

  /// Writes starter content for [filePath] if it doesn't already exist, based
  /// on its extension (blank sketch for `.ino`, blank circuit for `.cdl`,
  /// empty otherwise).
  Future<void> writeStarterFileIfAbsent(String filePath) async {
    if (_fs.existsFile(filePath)) return;
    final lower = filePath.toLowerCase();
    final starter = lower.endsWith('.ino')
        ? blankInoTemplate
        : lower.endsWith('.cdl')
        ? _blankCdlTemplate
        : '';
    await _fs.writeString(filePath, starter);
  }
}
