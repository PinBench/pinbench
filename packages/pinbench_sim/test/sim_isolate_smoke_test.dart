@Tags(['isolate'])
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_sim/isolate/sim_isolate.dart';
import 'package:pinbench_sim/isolate/sim_messages.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// End-to-end smoke test of the simulation isolate transport: spawn it, run a
/// minimal Arduino-only circuit with an (empty) program, and confirm the
/// handshake → start → stop lifecycle round-trips over the ports.
///
/// Tagged `isolate` because the child isolate loads ngspice via FFI.

// Intel HEX with only an end-of-file record: an all-NOP program, enough to drive
// the run loop without a real sketch.
const _emptyHex = ':00000001FF';

void main() {
  test('isolate handshakes, runs and stops cleanly', () async {
    final fromSim = ReceivePort();
    final events = StreamController<SimEvent>.broadcast();
    fromSim.listen((m) {
      if (m is SimEvent) events.add(m);
    });

    final isolate = await Isolate.spawn(simIsolateMain, fromSim.sendPort);
    addTearDown(() {
      isolate.kill(priority: Isolate.immediate);
      fromSim.close();
      unawaited(events.close());
    });

    Future<T> waitFor<T extends SimEvent>() => events.stream
        .firstWhere((e) => e is T)
        .then((e) => e as T)
        .timeout(const Duration(seconds: 15));

    // 1. Handshake: the isolate hands back its command port.
    final ready = await waitFor<IsolateReady>();
    final toSim = ready.commandPort;

    // 2. Start a run with an Arduino-only circuit.
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final started = waitFor<DebugLog>();
    toSim.send(StartSim(hex: _emptyHex, nodesJson: [uno.toJson()], wiresJson: const []));

    // The engine logs '[Run] ...' lines once the loop is live.
    final firstLog = await started;
    expect(firstLog.text, contains('[Run]'));

    // 3. Stop and confirm the loop reports it finished.
    toSim.send(StopSim());
    await waitFor<SimStopped>();
  });
}
