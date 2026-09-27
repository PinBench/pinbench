/// End-to-end servo simulation test: loads the bundled servo template
/// (circuit + compiled sweep hex), steps the engine frame by frame, and
/// asserts the horn's decoded angle actually sweeps. Covers the whole chain:
/// netlist signal-pin tracing -> AVR pulse-width measurement ->
/// ServoFrameUpdater -> canvas property updates.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';
import 'package:pinbench_parts/models/part_model.dart';

class _RecordingOutput implements SimulationOutput {
  _RecordingOutput(this.simulationNodes, this.simulationWires);

  @override
  final List<ComponentInstance> simulationNodes;
  @override
  final List<WireModel> simulationWires;

  final angles = <double>[];

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final props in updates.values) {
      final angle = props[ComponentProps.servoAngle];
      if (angle is num) angles.add(angle.toDouble());
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('servo horn angle follows the sketch pulses', () {
    final source = File('assets/templates/servo/circuit.cdl').readAsStringSync();
    final circuit = CircuitParser.applyToCanvas(CircuitParser.parse(source), standardParts);
    final hex = File('assets/templates/servo/servo.ino.hex').readAsStringSync();

    final output = _RecordingOutput(circuit.nodes, circuit.wires);
    final engine = SimulationEngine(output: output);

    engine.prepareForFrameStepping(hex);

    // Step ~2 simulated seconds in 16 ms slices (16 MHz clock). The sketch's
    // sweep covers 0->180 in ~1s, so the recorded angles must move.
    const cyclesPerSlice = 256000; // 16 ms
    for (var i = 0; i < 125; i++) {
      engine.runFrame(cycles: cyclesPerSlice, solveSpice: false);
    }
    engine.stop();

    expect(output.angles, isNotEmpty, reason: 'no servo angle updates were emitted');
    final min = output.angles.reduce((a, b) => a < b ? a : b);
    final max = output.angles.reduce((a, b) => a > b ? a : b);
    expect(max - min, greaterThan(45), reason: 'horn did not sweep (min=$min max=$max)');
  });
}
