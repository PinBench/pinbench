import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_terminal/pty/pty_service.dart';
import 'package:pinbench_terminal/pty/pty_service_io.dart';

/// A test double for [Pty] that records interactions and exposes a
/// controllable output stream. It cannot extend [Pty] (whose only constructor
/// spawns a native process), so it `implements` the interface and routes any
/// unused members through [noSuchMethod].
class _FakePty implements Pty {
  _FakePty(this._output);

  final Stream<Uint8List> _output;

  final writes = <Uint8List>[];
  final resizes = <List<int>>[];
  var killed = false;

  @override
  Stream<Uint8List> get output => _output;

  @override
  void write(Uint8List data) => writes.add(data);

  @override
  void resize(int rows, int cols) => resizes.add(<int>[rows, cols]);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PtyService service;

  setUp(() => service = PtyService());

  // resolveShell is specific to the native (`dart:io`) implementation.
  group('resolveShell', () {
    final io = PtyServiceImpl();

    test('returns the SHELL environment variable when present', () {
      final shell = Platform.environment['SHELL'];
      if (shell == null) {
        // Nothing to assert against on this host; covered by the fallback test.
        return;
      }
      expect(io.resolveShell(), shell);
    });

    test('never returns an empty string', () {
      expect(io.resolveShell(), isNotEmpty);
    });
  });

  group('write', () {
    test('UTF-8 encodes the data before writing to the pty', () {
      final pty = _FakePty(const Stream<Uint8List>.empty());

      service.write(pty, 'café'); // 'é' is two bytes in UTF-8.

      expect(pty.writes, hasLength(1));
      expect(pty.writes.single, equals(<int>[0x63, 0x61, 0x66, 0xC3, 0xA9]));
    });

    test('encodes plain ASCII one byte per character', () {
      final pty = _FakePty(const Stream<Uint8List>.empty());

      service.write(pty, 'ls\n');

      expect(pty.writes.single, equals('ls\n'.codeUnits));
    });
  });

  group('output', () {
    test('UTF-8 decodes the pty byte stream', () async {
      final controller = StreamController<Uint8List>();
      final pty = _FakePty(controller.stream);

      final decoded = service.output(pty).toList();
      controller
        ..add(Uint8List.fromList(<int>[0x68, 0x69])) // 'hi'
        ..add(Uint8List.fromList(<int>[0xC3, 0xA9])); // 'é'
      await controller.close();

      expect(await decoded, equals(<String>['hi', 'é']));
    });

    test('tolerates malformed bytes instead of tearing down the stream', () async {
      final controller = StreamController<Uint8List>();
      final pty = _FakePty(controller.stream);

      final decoded = service.output(pty).toList();
      controller
        ..add(Uint8List.fromList(<int>[0xFF])) // invalid UTF-8 lead byte
        ..add(Uint8List.fromList(<int>[0x6F, 0x6B])); // 'ok'
      await controller.close();

      final result = await decoded;
      // The stream must complete normally and still deliver the valid data.
      expect(result.join(), contains('ok'));
    });
  });

  group('delegation', () {
    test('resize forwards rows and cols to the pty', () {
      final pty = _FakePty(const Stream<Uint8List>.empty());

      service.resize(pty, 40, 120);

      expect(pty.resizes.single, equals(<int>[40, 120]));
    });

    test('kill terminates the pty process', () {
      final pty = _FakePty(const Stream<Uint8List>.empty());

      service.kill(pty);

      expect(pty.killed, isTrue);
    });
  });
}
