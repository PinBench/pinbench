import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_terminal/terminal_controller.dart';
import 'package:pinbench_terminal/pty/pty_service.dart';
import 'package:pinbench_terminal/pty/pty_service_io.dart';

/// Minimal [Pty] stand-in (see pty_service_test for the rationale).
class _FakePty(final Stream<Uint8List> _output) implements Pty {
  var killed = false;

  @override
  Stream<Uint8List> get output => _output;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [PtyService] whose [start] hands back a fake pty instead of spawning a
/// real native process, so the controller's lifecycle can be exercised without
/// any IO. All other behaviour (output decoding, write/resize/kill delegation)
/// runs through the real [PtyService] against the fake pty.
class _FakePtyService implements PtyService {
  // Real native delegate for the non-start operations (output decoding,
  // write/resize/kill) so they run for real against the fake pty.
  final _real = PtyServiceImpl();
  var startCount = 0;
  _FakePty? lastPty;

  @override
  Object start([String? shell]) {
    startCount++;
    return lastPty = _FakePty(const Stream<Uint8List>.empty());
  }

  @override
  Stream<String> output(Object pty) => _real.output(pty as Pty);

  @override
  void write(Object pty, String data) => _real.write(pty as Pty, data);

  @override
  void resize(Object pty, int rows, int cols) => _real.resize(pty as Pty, rows, cols);

  @override
  void kill(Object pty) => _real.kill(pty as Pty);
}

void main() {
  late _FakePtyService fakeService;
  late ProviderContainer container;

  setUp(() {
    fakeService = _FakePtyService();
    container = ProviderContainer(overrides: [ptyServiceProvider.overrideWithValue(fakeService)]);
    addTearDown(container.dispose);
  });

  // build() schedules startTerminal() in a microtask; let it run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts a shell process on build', () async {
    final state = container.read(terminalControllerProvider);
    expect(state.terminal, isNotNull);

    await settle();

    expect(fakeService.startCount, 1);
    expect(container.read(terminalControllerProvider).pty, isNotNull);
  });

  test('killTerminal kills the process and clears the pty', () async {
    container.read(terminalControllerProvider);
    await settle();
    final startedPty = fakeService.lastPty!;

    container.read(terminalControllerProvider.notifier).killTerminal();

    expect(startedPty.killed, isTrue);
    expect(container.read(terminalControllerProvider).pty, isNull);
  });

  test('killTerminal preserves the same terminal buffer', () async {
    final before = container.read(terminalControllerProvider).terminal;
    await settle();

    container.read(terminalControllerProvider.notifier).killTerminal();

    expect(container.read(terminalControllerProvider).terminal, same(before));
  });

  test('restartTerminal kills the old process and starts a fresh one', () async {
    container.read(terminalControllerProvider);
    await settle();
    final firstPty = fakeService.lastPty!;

    container.read(terminalControllerProvider.notifier).restartTerminal();

    expect(firstPty.killed, isTrue);
    expect(fakeService.startCount, 2);
    final state = container.read(terminalControllerProvider);
    expect(state.pty, isNotNull);
    expect(state.pty, isNot(same(firstPty)));
  });
}
