// Checks that every example template's precompiled firmware is the build of
// its sketch.
//
// The web app runs an untouched example's bundled `<name>.ino.hex` instead of
// compiling it, so a sketch edited without rebuilding its hex would run the old
// program, silently. This compiles each template with `arduino-cli` and
// compares the memory image the two describe: byte for byte, whatever the HEX
// file's record layout or line endings.
//
//   dart tools/check_template_firmware.dart            # every template
//   dart tools/check_template_firmware.dart blink oled # some of them
//   dart tools/check_template_firmware.dart --write    # rebuild what differs
//
// Needs `arduino-cli` with the cores and libraries the compile service has
// (.github/workflows/template-firmware.yml installs the pinned set). A build
// is only reproducible with the same toolchain, so rebuild with --write after
// changing those versions. Builds here map their source folders to fixed
// names, so they match on any machine (and carry no one's home directory).
import 'dart:io';

/// The board each template's circuit is built on, by its `.cdl` type, and the
/// board `arduino-cli` builds for it: BoardProfile's `fqbn`, in
/// packages/pinbench_parts/lib/models/board_profile.dart.
const fqbnByBoard = {'ArduinoUno': 'arduino:avr:uno', 'RaspberryPiPicoW': 'rp2040:rp2040:rpipico'};

/// Where a core that emits only a `.bin` loads it: the RP2040's XIP flash. The
/// compile service converts it to Intel HEX at the same address.
const binLoadAddress = {'rp2040:rp2040:rpipico': 0x10000000};

/// The boards whose builds embed source paths, and so get [pathIndependence].
/// Not AVR: its builds carry none, and its GCC 7 predates -ffile-prefix-map.
const pathMappedBoards = {'rp2040:rp2040:rpipico'};

/// Compiler flags that keep a build from depending on where it ran.
///
/// Assertions bake the path of their source file into the firmware: the
/// Pico SDK's do, through Wire, so pico_oled carried the builder's home
/// directory, and built differently on any other machine. Each folder a
/// source can come from is mapped to a fixed name instead.
Future<List<String>> pathIndependence(String sketchRoot) async {
  Future<String> dir(String key) async =>
      ((await Process.run('arduino-cli', ['config', 'get', key])).stdout as String).trim();
  final flags = [
    '-ffile-prefix-map=${await dir('directories.data')}=/arduino',
    '-ffile-prefix-map=${await dir('directories.user')}=/arduino-user',
    '-ffile-prefix-map=$sketchRoot=/sketch',
  ].join(' ');
  return [
    for (final kind in ['c', 'cpp', 'S']) ...[
      '--build-property',
      'compiler.$kind.extra_flags=$flags',
    ],
  ];
}

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  final only = args.where((a) => !a.startsWith('--')).toSet();
  final templates = Directory('assets/templates').listSync().whereType<Directory>().where((d) {
    final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
    return File('${d.path}/$name.ino').existsSync() && (only.isEmpty || only.contains(name));
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  var failures = 0;
  for (final dir in templates) {
    final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final result = await check(dir, name, write: write);
    stdout.writeln('${result.ok ? 'ok  ' : 'FAIL'}  $name: ${result.message}');
    if (!result.ok) failures++;
  }
  if (failures > 0) {
    stderr.writeln(
      '\n$failures template(s) do not match their firmware. Rebuild them with\n'
      '  dart tools/check_template_firmware.dart --write <name>…\n'
      'with the toolchain in .github/workflows/template-firmware.yml, and commit the .ino.hex.',
    );
    exit(1);
  }
  stdout.writeln('\n${templates.length} templates match their firmware.');
}

Future<({bool ok, String message})> check(Directory dir, String name, {required bool write}) async {
  final cdl = File('${dir.path}/circuit.cdl').readAsStringSync();
  final board = fqbnByBoard.keys.where((b) => RegExp(':=\\s*$b\\b').hasMatch(cdl)).firstOrNull;
  if (board == null) {
    return (
      ok: false,
      message: 'no board in circuit.cdl that this tool knows (add it to fqbnByBoard)',
    );
  }
  final fqbn = fqbnByBoard[board]!;

  // A copy of just the sketch, so the build writes nothing into the template.
  final work = Directory.systemTemp.createTempSync('template_firmware_');
  try {
    final sketch = Directory('${work.path}/$name')..createSync();
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ino'))) {
      f.copySync('${sketch.path}/${f.uri.pathSegments.last}');
    }
    final out = Directory('${work.path}/out')..createSync();
    final build = await Process.run('arduino-cli', [
      'compile',
      '--fqbn',
      fqbn,
      if (pathMappedBoards.contains(fqbn)) ...await pathIndependence(work.path),
      '--output-dir',
      out.path,
      sketch.path,
    ]);
    if (build.exitCode != 0) {
      return (ok: false, message: 'does not compile for $fqbn:\n${build.stdout}${build.stderr}');
    }

    final builtHex = File('${out.path}/$name.ino.hex');
    final String built;
    if (builtHex.existsSync()) {
      built = builtHex.readAsStringSync();
    } else {
      final address = binLoadAddress[fqbn];
      if (address == null) {
        return (
          ok: false,
          message: '$fqbn built no .hex, and no load address is known for its .bin',
        );
      }
      built = toIntelHex(File('${out.path}/$name.ino.bin').readAsBytesSync(), address);
    }

    final hexFile = File('${dir.path}/$name.ino.hex');
    if (hexFile.existsSync() &&
        sameImage(memoryImage(hexFile.readAsStringSync()), memoryImage(built))) {
      return (ok: true, message: 'matches ($fqbn)');
    }
    if (write) {
      hexFile.writeAsStringSync(built);
      return (ok: true, message: 'rebuilt ($fqbn)');
    }
    return (
      ok: false,
      message: hexFile.existsSync()
          ? '$name.ino.hex is not the build of the sketch ($fqbn)'
          : 'no $name.ino.hex',
    );
  } finally {
    work.deleteSync(recursive: true);
  }
}

/// The bytes an Intel HEX file loads, by absolute address.
Map<int, int> memoryImage(String hex) {
  final memory = <int, int>{};
  var base = 0;
  for (final line in hex.split(RegExp(r'\s+')).where((l) => l.startsWith(':'))) {
    final b = [
      for (var i = 1; i + 1 < line.length; i += 2) int.parse(line.substring(i, i + 2), radix: 16),
    ];
    final (count, offset, type) = (b[0], (b[1] << 8) | b[2], b[3]);
    final data = b.sublist(4, 4 + count);
    switch (type) {
      case 0x00:
        for (var i = 0; i < data.length; i++) {
          memory[base + offset + i] = data[i];
        }
      case 0x02:
        base = ((data[0] << 8) | data[1]) << 4;
      case 0x04:
        base = ((data[0] << 8) | data[1]) << 16;
    }
  }
  return memory;
}

bool sameImage(Map<int, int> a, Map<int, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// [bytes] as Intel HEX loaded at [base], laid out as the compile service
/// writes it: 16-byte records, an extended linear address record whenever the
/// upper 16 bits change.
String toIntelHex(List<int> bytes, int base) {
  final lines = <String>[];
  void record(int type, int offset, List<int> data) {
    final fields = [data.length, (offset >> 8) & 0xff, offset & 0xff, type, ...data];
    fields.add(-fields.fold(0, (a, b) => a + b) & 0xff);
    lines.add(':${fields.map((f) => f.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}');
  }

  int? upper;
  for (var i = 0; i < bytes.length; i += 16) {
    final address = base + i;
    final high = address >> 16;
    if (high != upper) {
      upper = high;
      record(0x04, 0, [(high >> 8) & 0xff, high & 0xff]);
    }
    record(0x00, address & 0xffff, bytes.sublist(i, i + 16 > bytes.length ? bytes.length : i + 16));
  }
  record(0x01, 0, []);
  return '${lines.join('\n')}\n';
}
