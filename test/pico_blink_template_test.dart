// The Pico Blink template, run the way a user runs it: its `.cdl` applied to
// a canvas, its bundled .hex on the RP2040 emulator, and the LED on GP21 and
// the board's own LED checked through what the engine writes back.
//
// Uses the bundled .hex rather than invoking arduino-cli, so it needs no
// toolchain — and it checks the same artefact the web build ships.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

class _RecordingOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  final lit = <LocalKey, List<bool>>{};

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      final Object? isOn = value[ComponentProps.isOn];
      if (isOn case final bool on) {
        final states = lit.putIfAbsent(key, () => []);
        if (states.isEmpty || states.last != on) states.add(on);
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the template blinks the LED on GP21 and the on-board LED', () {
    final parsed = CircuitParser.applyToCanvas(
      CircuitParser.parse(File('assets/templates/pico_blink/circuit.cdl').readAsStringSync()),
      standardParts,
    );
    final pico = parsed.nodes.singleWhere((n) => n.part.name == PartNames.picoW);
    final led = parsed.nodes.singleWhere((n) => n.part.name == PartNames.led);

    final serial = <String>[];
    final output = _RecordingOutput(parsed.nodes, parsed.wires);
    final engine = SimulationEngine(output: output, onSerialPrint: serial.add)
      ..prepareForFrameStepping(
        File('assets/templates/pico_blink/pico_blink.ino.hex').readAsStringSync(),
      );
    addTearDown(engine.stop);

    // 2.5 s of the Pico's 125 MHz clock, a 60th of a second at a time.
    for (var frame = 0; frame < 150; frame++) {
      engine.runFrame(cycles: 125000000 ~/ 60);
    }

    expect(serial, contains('Hello from the Pico W'));
    expect(output.lit[led.key], containsAllInOrder([true, false, true, false]));
    expect(output.lit[pico.key], containsAllInOrder([true, false, true, false]));
  });
}
