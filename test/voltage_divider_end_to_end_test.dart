// The Voltage Divider template, run the way a user runs it: the real
// `SimulationEngine`, real firmware on the emulator, a real solved circuit,
// checked through what actually reaches the Serial Monitor.
//
// Driving `SimulationEngine` rather than re-implementing its frame loop is the
// point of this test, not an incidental choice. An earlier version stepped the
// emulator and the solver by hand in the same order the engine uses, and it
// passed while the app printed `analogRead(A0) = 0` forever — because the bug
// was in a frame step the hand-rolled loop simply did not have
// (`MicFrameUpdater` stamping silence into ADC channel 0 with no mic present).
// A test that rebuilds the pipeline can only ever check the pipeline it
// rebuilt.
//
// Uses the bundled .hex rather than invoking arduino-cli, so it needs no
// toolchain — and it checks the same artefact the web build ships.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/config/avr_config.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

class _CollectingOutput implements SimulationOutput {
  _CollectingOutput(this.simulationNodes, this.simulationWires);

  @override
  final List<ComponentInstance> simulationNodes;
  @override
  final List<WireModel> simulationWires;

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the template prints the divider reading, on every line', () {
    final parsed = CircuitParser.applyToCanvas(
      CircuitParser.parse(File('assets/templates/voltage_divider/circuit.cdl').readAsStringSync()),
      standardParts,
    );

    final serial = <String>[];
    final engine = SimulationEngine(
      output: _CollectingOutput(parsed.nodes, parsed.wires),
      onSerialPrint: serial.add,
    );

    engine.prepareForFrameStepping(
      File('assets/templates/voltage_divider/voltage_divider.ino.hex').readAsStringSync(),
    );
    addTearDown(engine.stop);

    expect(engine.isSpiceActive, isTrue, reason: 'an analog input should arm the solver');

    // ~2.5 s of simulated time: the sketch settles for 250 ms, then prints
    // once a second.
    for (var frame = 0; frame < 150; frame++) {
      engine.runFrame(cycles: AVRConfig.cyclesPerFrame);
    }

    expect(serial, isNotEmpty, reason: 'the sketch printed nothing at all');

    for (final line in serial) {
      expect(
        line,
        contains('= 510'),
        reason: 'expected the mid-rail reading on every line, got: $line',
      );
      expect(line, isNot(contains('inf')), reason: 'voltage rendered as "inf": $line');
      expect(line, contains('2.49'), reason: 'expected ~2.49 V, got: $line');
    }
  });
}
