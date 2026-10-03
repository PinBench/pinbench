import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:pinbench_parts/models/board_profile.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../data/workspace_fs.dart';
import 'local_compile_service.dart';
import 'remote_compile_service.dart';
import 'template_provenance_service.dart';

/// Thrown when compiling an Arduino sketch fails (locally via `arduino-cli`
/// or remotely via the compile service); [message] carries the compiler
/// output for display in the Problems pane / serial monitor.
class CompilerException(final String message) implements Exception {
  @override
  String toString() => message;
}

/// A local build that failed because `arduino-cli` has no core for [board] —
/// the arduino-pico core, the first time someone builds for a Pico.
///
/// Its own type rather than a sentence to match in the message, because it is
/// the one failure the app can fix rather than only explain: the Problems pane
/// offers to install the core (see [LocalCompileService.installCore]). The
/// message still says how to do it by hand.
class MissingBoardCoreException(super.message, {required final BoardProfile board})
    extends CompilerException;

/// Compiles Arduino sketches to Intel-HEX. Dispatches to [LocalCompileService]
/// (native, via `arduino-cli`) or [RemoteCompileService] (web, via a
/// configured compile API), and exposes [TemplateProvenanceService]'s pristine
/// hash tracking under its original names for existing callers.
class CompilerService {
  /// Base URL of the remote `arduino-cli` compile service used on the web (the
  /// browser cannot run `arduino-cli` locally). Set at build time with
  /// `--dart-define=COMPILE_API_URL=https://your-service`. An unedited example
  /// runs its bundled precompiled hex either way (see [compileWorkspaceOnWeb]);
  /// without a service, nothing else can be built on the web.
  // ignore: do_not_use_environment
  static const _compileApiUrl = String.fromEnvironment('COMPILE_API_URL');

  static Map<String, int> get pristineSourceHashes =>
      TemplateProvenanceService.pristineSourceHashes;

  static String get pristineHashFileName => TemplateProvenanceService.pristineHashFileName;

  static Future<String> compileWorkspace(
    String directoryPath, {
    BoardProfile board = BoardProfile.arduinoUno,
  }) async {
    // The browser cannot run `arduino-cli`.
    if (!PlatformCapabilities.supportsLocalCompile) {
      return compileWorkspaceOnWeb(
        directoryPath,
        board: board,
        compileApiUrl: _compileApiUrl,
        remote: RemoteCompileService.compile,
      );
    }

    return LocalCompileService.compileWorkspace(directoryPath, board: board);
  }

  /// The browser's build of the workspace at [directoryPath].
  ///
  /// An example nobody has edited runs the precompiled hex it ships with:
  /// that is the very build of its source, it starts at once, and it works
  /// when the compile service is slow, down, or refuses the page's origin.
  /// Anything else goes to the compile service at [compileApiUrl] through
  /// [remote], and without one it fails with a message that says why; the
  /// shipped hex is never run for code it was not built from.
  ///
  /// Separate from [compileWorkspace] so tests on the native VM, where
  /// [PlatformCapabilities.supportsLocalCompile] is always true, can reach it.
  @visibleForTesting
  static Future<String> compileWorkspaceOnWeb(
    String directoryPath, {
    required BoardProfile board,
    required String compileApiUrl,
    required Future<String> Function(
      String directoryPath,
      String compileApiUrl, {
      BoardProfile board,
    })
    remote,
  }) async {
    final dirName = p.basename(directoryPath);
    final hexPath = p.join(directoryPath, '$dirName.ino.hex');
    final inoPath = p.join(directoryPath, '$dirName.ino');
    final fs = WorkspaceFs();
    final hasHex = fs.existsFile(hexPath);
    if (hasHex) {
      final pristineHash = TemplateProvenanceService.pristineHashFor(directoryPath, fs);
      final currentSource = fs.existsFile(inoPath) ? fs.readStringSync(inoPath) : null;
      // Only when the source is *confirmed* to be the pristine template's. If
      // provenance is unknown (no recorded or persisted pristine hash, e.g. a
      // workspace not created from a template), the hex may not match it.
      if (pristineHash != null && currentSource?.hashCode == pristineHash) {
        return fs.readString(hexPath);
      }
    }
    if (compileApiUrl.isNotEmpty) {
      return remote(directoryPath, compileApiUrl, board: board);
    }
    if (hasHex) {
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

  static Future<String> compile(String code, {BoardProfile board = BoardProfile.arduinoUno}) async {
    if (!PlatformCapabilities.supportsLocalCompile) {
      throw CompilerException(
        'Compiling custom sketches is not available in the web preview. Open a '
        'bundled example template to run a simulation, or use the desktop app.',
      );
    }
    return LocalCompileService.compile(code, board: board);
  }
}
