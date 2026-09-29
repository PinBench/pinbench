import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Regression tests for the simulation run-loop lifecycle.
///
/// The "LED blink stops working after a re-run" bug was caused by a quick
/// stop→start launching a SECOND run loop while the first was still mid-frame:
/// two loops then double-ticked the shared AVR + ngspice state. These tests pin
/// down the invariant that **at most one run loop ever runs**, that a superseded
/// loop stays silent, and that a genuine stop reports exactly once — so the bug
/// cannot be reintroduced by future refactors.

ComponentInstance _uno() => ComponentInstance(
  key: const ValueKey('uno'),
  position: Offset.zero,
  part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
);

class _FakeOutput implements SimulationOutput {
  @override
  final List<ComponentInstance> simulationNodes = [_uno()];
  @override
  final List<WireModel> simulationWires = const [];
  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}
}

// Minimal all-NOP program (Intel HEX end-of-file record only).
const _hex = ':00000001FF';

void main() {
  test('a fresh start runs exactly one loop', () async {
    final engine = SimulationEngine(output: _FakeOutput());
    expect(engine.activeLoopCount, 0);

    await engine.start(_hex, onStop: () {});
    expect(engine.isSimulating, isTrue);
    expect(engine.activeLoopCount, 1);

    engine.stop();
    await engine.loopDone;
    expect(engine.activeLoopCount, 0);
  });

  test('re-running without awaiting the stop never leaves two loops', () async {
    final engine = SimulationEngine(output: _FakeOutput());
    var stopsRun1 = 0;
    var stopsRun2 = 0;

    await engine.start(_hex, onStop: () => stopsRun1++);
    expect(engine.activeLoopCount, 1);

    // Immediately re-run (the exact stop→start race that caused the bug).
    await engine.start(_hex, onStop: () => stopsRun2++);
    expect(engine.activeLoopCount, 1, reason: 'a superseded loop must have exited');

    // The superseded first run must NOT report a stop (it would tear down run 2).
    expect(stopsRun1, 0);

    engine.stop();
    await engine.loopDone;
    expect(engine.activeLoopCount, 0);
    // The genuine stop of the active run reports exactly once.
    expect(stopsRun2, 1);
  });

  test('many rapid re-runs keep the single-loop invariant', () async {
    final engine = SimulationEngine(output: _FakeOutput());
    for (var i = 0; i < 5; i++) {
      await engine.start(_hex, onStop: () {});
      expect(engine.activeLoopCount, 1, reason: 're-run $i should leave one loop');
    }
    engine.stop();
    await engine.loopDone;
    expect(engine.activeLoopCount, 0);
  });

  test('stop then start re-runs cleanly with a single active loop', () async {
    final engine = SimulationEngine(output: _FakeOutput());
    await engine.start(_hex, onStop: () {});
    engine.stop();
    // Do not await the stop — start again right away.
    await engine.start(_hex, onStop: () {});
    expect(engine.activeLoopCount, 1);
    expect(engine.isSimulating, isTrue);

    engine.stop();
    await engine.loopDone;
    expect(engine.activeLoopCount, 0);
  });
}
