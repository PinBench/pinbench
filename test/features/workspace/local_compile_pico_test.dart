/// The local build for a Pico, end to end: `arduino-cli` with the arduino-pico
/// core writes a `.bin`, the service hands back Intel HEX at the flash's
/// address, and the Pico emulator runs it.
///
/// Needs `arduino-cli` and the `rp2040:rp2040` core, so it is tagged like the
/// other compiling tests (CI runs `--exclude-tags arduino`), and skips on a
/// machine without the core rather than fail for want of a toolchain.
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:pinbench/features/workspace/services/local_compile_service.dart';
import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_sim/core/board/pico_board.dart';

void main() {
  final skip = _missingPicoCore();

  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('pico_')..createSync(recursive: true);
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  test(
    'a sketch built for the Pico runs on the Pico emulator',
    () async {
      final name = p.basename(workspace.path);
      File(p.join(workspace.path, '$name.ino')).writeAsStringSync('''
void setup() { Serial1.begin(115200); Serial1.println("hello from the pico"); }
void loop() {}
''');
      // An earlier build for an Uno, still in the build folder: the Pico build
      // must not pick it up.
      Directory(p.join(workspace.path, 'build')).createSync();
      File(p.join(workspace.path, 'build', '$name.ino.hex')).writeAsStringSync(':00000001FF\n');

      final hex = await LocalCompileService.compileWorkspace(
        workspace.path,
        board: BoardProfile.picoW,
      );
      expect(hex, startsWith(':020000041000EA'), reason: 'loads at 0x10000000');

      final lines = <String>[];
      final pico = PicoBoardEmulator()..loadHex(hex, onSerialPrint: lines.add);
      for (var ms = 0; ms < 50 && lines.isEmpty; ms++) {
        pico.tick(125000);
      }
      expect(lines, contains('hello from the pico'));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Why the test cannot run here, or null when it can.
String? _missingPicoCore() {
  try {
    final result = Process.runSync('arduino-cli', ['core', 'list']);
    if (result.exitCode != 0) return 'arduino-cli failed';
    return result.stdout.toString().contains('rp2040:rp2040') ? null : 'no rp2040:rp2040 core';
  } on ProcessException {
    return 'no arduino-cli';
  }
}
