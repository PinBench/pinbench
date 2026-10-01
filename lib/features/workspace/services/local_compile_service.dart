import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_sim/core/board/intel_hex.dart';

import 'compiler_service.dart' show CompilerException;

/// Compiles Arduino sketches to Intel-HEX by shelling out to `arduino-cli`
/// (located on PATH or common install dirs), for whichever board is on the
/// canvas. Native platforms only — the browser cannot run `arduino-cli`
/// locally (see `RemoteCompileService` for the web path). Throws
/// [CompilerException] on failure.
abstract final class LocalCompileService {
  static Future<String> compileWorkspace(
    String directoryPath, {
    BoardProfile board = BoardProfile.arduinoUno,
  }) async {
    final outDir = Directory(p.join(directoryPath, 'build'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final cliPath = await _findArduinoCli();
    if (cliPath == null) {
      throw CompilerException('arduino-cli not found.');
    }

    // arduino-cli names its outputs after the directory. A build for one board
    // leaves files another board's build does not overwrite — an Uno's `.hex`
    // beside a Pico's `.bin` — so last run's are cleared rather than risk
    // running a program built for the board that was on the canvas before.
    final dirName = p.basename(directoryPath);
    for (final entry in outDir.listSync()) {
      final name = p.basename(entry.path);
      if (entry is File && (name.startsWith('$dirName.ino.') || name.startsWith('sketch.ino.'))) {
        entry.deleteSync();
      }
    }

    final result = await Process.run(cliPath, [
      'compile',
      '--fqbn',
      board.fqbn,
      '--output-dir',
      outDir.path,
      directoryPath,
    ]);

    if (result.exitCode != 0) {
      throw CompilerException(_failure(result, board));
    }

    // Named after the directory; a sketch named sketch.ino is the fallback.
    for (final base in ['$dirName.ino', 'sketch.ino']) {
      final program = await _readProgram(outDir.path, base, board);
      if (program != null) return program;
    }

    final hexFiles = outDir.listSync().where((e) => e.path.endsWith('.hex')).toList();
    if (hexFiles.isNotEmpty) return File(hexFiles.first.path).readAsString();
    throw CompilerException(
      'Compilation succeeded but HEX file was not generated in ${outDir.path}.',
    );
  }

  static Future<String> compile(String code, {BoardProfile board = BoardProfile.arduinoUno}) async {
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
    if (outDir.existsSync()) {
      // A shared scratch folder: the last build may have been for another board.
      outDir.deleteSync(recursive: true);
    }
    outDir.createSync(recursive: true);

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
        board.fqbn,
        '--output-dir',
        outDir.path,
        sketchDir.path,
      ]);

      if (result.exitCode != 0) {
        throw CompilerException(_failure(result, board));
      }

      final program = await _readProgram(outDir.path, 'sketch.ino', board);
      if (program == null) {
        throw CompilerException('Compilation succeeded but HEX file was not generated.');
      }
      return program;
    } finally {
      // Clean up the temporary sketch directory.
      if (sketchDir.existsSync()) {
        sketchDir.deleteSync(recursive: true);
      }
    }
  }

  /// The program `arduino-cli` wrote as `<base>.hex` or, for a board whose
  /// toolchain writes a raw image instead, `<base>.bin` turned into Intel HEX
  /// at [BoardProfile.binLoadAddress] — the one format the emulator takes.
  static Future<String?> _readProgram(String outDir, String base, BoardProfile board) async {
    final hex = File(p.join(outDir, '$base.hex'));
    if (hex.existsSync()) return hex.readAsString();
    final loadAddress = board.binLoadAddress;
    final bin = File(p.join(outDir, '$base.bin'));
    if (loadAddress != null && bin.existsSync()) {
      return IntelHex.encode(await bin.readAsBytes(), baseAddress: loadAddress);
    }
    return null;
  }

  /// The compiler's output, and — when the board's core is what is missing —
  /// how to install it, which is the one failure the output alone does not
  /// explain to someone who has never added a board package.
  static String _failure(ProcessResult result, BoardProfile board) {
    final output = '${result.stderr}\n${result.stdout}';
    final core = board.fqbn.split(':').take(2).join(':');
    final missingCore = RegExp(
      'platform not installed|unknown package|invalid FQBN',
      caseSensitive: false,
    ).hasMatch(output);
    if (!missingCore || board.coreIndexUrl == null) return 'Compilation failed:\n$output';
    return 'Compilation failed: the $core core for the ${board.partName} is not installed. '
        'Install it with:\n'
        '  arduino-cli core install $core --additional-urls ${board.coreIndexUrl}\n\n'
        '$output';
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
