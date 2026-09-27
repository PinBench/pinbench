import 'package:path/path.dart' as p;

import '../../../core/platform/platform_capabilities.dart';
import '../data/workspace_fs.dart';
import 'local_compile_service.dart';
import 'remote_compile_service.dart';
import 'template_provenance_service.dart';

/// Thrown when compiling an Arduino sketch fails (locally via `arduino-cli`
/// or remotely via the compile service); [message] carries the compiler
/// output for display in the Problems pane / serial monitor.
class CompilerException implements Exception {
  final String message;
  CompilerException(this.message);
  @override
  String toString() => message;
}

/// Compiles Arduino sketches to Intel-HEX. Dispatches to [LocalCompileService]
/// (native, via `arduino-cli`) or [RemoteCompileService] (web, via a
/// configured compile API), and exposes [TemplateProvenanceService]'s pristine
/// hash tracking under its original names for existing callers.
class CompilerService {
  /// Base URL of the remote `arduino-cli` compile service used on the web (the
  /// browser cannot run `arduino-cli` locally). Set at build time with
  /// `--dart-define=COMPILE_API_URL=https://your-service`. When empty, the web
  /// build falls back to the bundled precompiled template hex.
  // ignore: do_not_use_environment
  static const _compileApiUrl = String.fromEnvironment('COMPILE_API_URL');

  static Map<String, int> get pristineSourceHashes =>
      TemplateProvenanceService.pristineSourceHashes;

  static String get pristineHashFileName => TemplateProvenanceService.pristineHashFileName;

  static Future<String> compileWorkspace(String directoryPath) async {
    // The browser cannot run `arduino-cli`. When a remote compile service is
    // configured, send the (edited) sketch there; otherwise fall back to the
    // bundled precompiled template hex so the examples still run offline.
    if (!PlatformCapabilities.supportsLocalCompile) {
      if (_compileApiUrl.isNotEmpty) {
        return RemoteCompileService.compile(directoryPath, _compileApiUrl);
      }
      final dirName = p.basename(directoryPath);
      final hexPath = p.join(directoryPath, '$dirName.ino.hex');
      final inoPath = p.join(directoryPath, '$dirName.ino');
      final fs = WorkspaceFs();
      if (fs.existsFile(hexPath)) {
        final pristineHash = TemplateProvenanceService.pristineHashFor(directoryPath, fs);
        final currentSource = fs.existsFile(inoPath) ? fs.readStringSync(inoPath) : null;
        // Only serve the bundled hex when we can *confirm* the source still
        // matches the pristine template. If provenance is unknown (no
        // recorded/persisted pristine hash — e.g. the workspace was reopened
        // or wasn't created from a template), fail closed instead of risking
        // silently running stale code that doesn't match the editor.
        if (pristineHash != null && currentSource?.hashCode == pristineHash) {
          return fs.readString(hexPath);
        }
        throw CompilerException(
          "You've edited this sketch, but the web preview can't compile custom "
          'code without a compile service — running the old precompiled result '
          'would silently ignore your changes. Set COMPILE_API_URL or use the '
          'desktop app to compile edited sketches.',
        );
      }
      throw CompilerException(
        'The web preview can only run the bundled example templates, which ship '
        'precompiled. Compiling new or edited sketches needs a compile service '
        '(set COMPILE_API_URL) or the desktop app.',
      );
    }

    return LocalCompileService.compileWorkspace(directoryPath);
  }

  static Future<String> compile(String code) async {
    if (!PlatformCapabilities.supportsLocalCompile) {
      throw CompilerException(
        'Compiling custom sketches is not available in the web preview. Open a '
        'bundled example template to run a simulation, or use the desktop app.',
      );
    }
    return LocalCompileService.compile(code);
  }
}
