import 'dart:io';

/// Exports a workspace directory to a zip archive using the platform's
/// archiver. Extracted from `WorkspaceFiles.exportWorkspaceToZip`, which
/// previously ran this subprocess logic directly inside the Riverpod
/// provider — this is plain Dart with no Riverpod dependency, so it's
/// unit-testable without a `ProviderContainer`.
abstract final class WorkspaceExportService {
  /// Zips the contents of [sourceDir] to [savePath]. Returns true on success.
  static Future<bool> zipDirectory(String sourceDir, String savePath) async {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Compress-Archive -Path "$sourceDir\\*" -DestinationPath "$savePath" -Force',
      ]);
    } else {
      // Zip the contents (relative paths) by running from inside the workspace.
      result = await Process.run('zip', ['-r', savePath, '.'], workingDirectory: sourceDir);
    }
    return result.exitCode == 0;
  }
}
