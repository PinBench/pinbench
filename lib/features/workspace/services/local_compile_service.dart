import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'compiler_service.dart' show CompilerException;

/// Compiles Arduino sketches to Intel-HEX by shelling out to `arduino-cli`
/// (located on PATH or common install dirs). Native platforms only — the
/// browser cannot run `arduino-cli` locally (see `RemoteCompileService` for
/// the web path). Throws [CompilerException] on failure.
abstract final class LocalCompileService {
  static Future<String> compileWorkspace(String directoryPath) async {
    final outDir = Directory(p.join(directoryPath, 'build'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final cliPath = await _findArduinoCli();
    if (cliPath == null) {
      throw CompilerException('arduino-cli not found.');
    }

    final result = await Process.run(cliPath, [
      'compile',
      '--fqbn',
      'arduino:avr:uno',
      '--output-dir',
      outDir.path,
      directoryPath,
    ]);

    if (result.exitCode != 0) {
      throw CompilerException('Compilation failed:\n${result.stderr}\n${result.stdout}');
    }

    // arduino-cli names the output hex file after the directory name.
    final dirName = p.basename(directoryPath);
    var hexFile = File(p.join(outDir.path, '$dirName.ino.hex'));

    // Fallbacks: a sketch named sketch.ino, then any .hex in the output dir.
    if (!hexFile.existsSync()) {
      hexFile = File(p.join(outDir.path, 'sketch.ino.hex'));
    }

    if (!hexFile.existsSync()) {
      final hexFiles = outDir.listSync().where((e) => e.path.endsWith('.hex')).toList();
      if (hexFiles.isNotEmpty) {
        hexFile = File(hexFiles.first.path);
      } else {
        throw CompilerException(
          'Compilation succeeded but HEX file was not generated in ${outDir.path}.',
        );
      }
    }

    return hexFile.readAsString();
  }

  static Future<String> compile(String code) async {
    final tempDir = await getTemporaryDirectory();
    final buildDir = Directory(p.join(tempDir.path, 'arduino_build'));
    if (!buildDir.existsSync()) {
      buildDir.createSync(recursive: true);
    }

    final sketchDir = Directory(p.join(buildDir.path, 'sketch'));
    if (sketchDir.existsSync()) {
      sketchDir.deleteSync(recursive: true);
    }
    sketchDir.createSync(recursive: true);

    final sketchFile = File(p.join(sketchDir.path, 'sketch.ino'));
    await sketchFile.writeAsString(code);

    final outDir = Directory(p.join(buildDir.path, 'out'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    try {
      final cliPath = await _findArduinoCli();
      if (cliPath == null) {
        throw CompilerException(
          'arduino-cli not found. Please install arduino-cli and ensure it is in your PATH, or installed via Homebrew.',
        );
      }

      final result = await Process.run(cliPath, [
        'compile',
        '--fqbn',
        'arduino:avr:uno',
        '--output-dir',
        outDir.path,
        sketchDir.path,
      ]);

      if (result.exitCode != 0) {
        throw CompilerException('Compilation failed:\n${result.stderr}\n${result.stdout}');
      }

      final hexFile = File(p.join(outDir.path, 'sketch.ino.hex'));
      if (!hexFile.existsSync()) {
        throw CompilerException('Compilation succeeded but HEX file was not generated.');
      }

      return await hexFile.readAsString();
    } finally {
      // Clean up the temporary sketch directory.
      if (sketchDir.existsSync()) {
        sketchDir.deleteSync(recursive: true);
      }
    }
  }

  static Future<String?> _findArduinoCli() async {
    final exe = Platform.isWindows ? 'arduino-cli.exe' : 'arduino-cli';

    // 1. Resolve via PATH (`where` on Windows, `which` elsewhere).
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(locator, [exe]);
      if (result.exitCode == 0) {
        // `where` may return several lines; take the first non-empty one.
        final first = result.stdout.toString().split('\n').first.trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final commonPaths = <String>[
      if (Platform.isMacOS) ...['/opt/homebrew/bin/arduino-cli', '/usr/local/bin/arduino-cli'],
      if (Platform.isLinux) ...['/usr/local/bin/arduino-cli', '/usr/bin/arduino-cli'],
      if (Platform.isWindows) ...[
        if (localAppData != null) p.join(localAppData, 'Arduino15', 'arduino-cli.exe'),
        r'C:\Program Files\Arduino CLI\arduino-cli.exe',
      ],
    ];

    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return null;
  }
}
