// The Piezo Buzzer template, run the way a user runs it: its `.cdl` applied to
// a canvas, its bundled .hex on the AVR emulator, and the buzzer checked
// through what the engine writes back to it.
//
// The template once placed a servo instead of a buzzer, which nothing caught:
// the sketch still ran, and only the canvas showed the wrong part. So the
// part list is pinned here as well as the tone.
//
// Uses the bundled .hex rather than invoking arduino-cli, so it needs no
// toolchain, and it checks the same artefact the web build ships.
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
  final sounding = <LocalKey, List<bool>>{};
  final pitch = <LocalKey, num>{};

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      final Object? isOn = value[ComponentProps.isOn];
      if (isOn case final bool on) {
        final states = sounding.putIfAbsent(key, () => []);
        if (states.isEmpty || states.last != on) states.add(on);
      }
      final Object? frequency = value[ComponentProps.frequency];
      if (frequency case final num hz) pitch[key] = hz;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dir = 'assets/templates/piezo_buzzer';

  test('the template is an Uno and a piezo buzzer on pin 8', () {
    final parsed = CircuitParser.applyToCanvas(
      CircuitParser.parse(File('$dir/circuit.cdl').readAsStringSync()),
      standardParts,
    );
    expect(
      parsed.nodes.map((n) => n.part.name),
      unorderedEquals([PartNames.arduinoUno, PartNames.piezoBuzzer]),
    );
  });

  test('the sketch sounds the buzzer at 85 Hz, then silences it', () {
    final parsed = CircuitParser.applyToCanvas(
      CircuitParser.parse(File('$dir/circuit.cdl').readAsStringSync()),
      standardParts,
    );
    final buzzer = parsed.nodes.singleWhere((n) => n.part.name == PartNames.piezoBuzzer);

    final serial = <String>[];
    final output = _RecordingOutput(parsed.nodes, parsed.wires);
    final engine = SimulationEngine(output: output, onSerialPrint: serial.add)
      ..prepareForFrameStepping(File('$dir/piezo_buzzer.ino.hex').readAsStringSync());
    addTearDown(engine.stop);

    // 2.5 s of the Uno's 16 MHz clock, a 60th of a second at a time: one
    // second of tone, one of silence, and into the next tone.
    for (var frame = 0; frame < 150; frame++) {
      engine.runFrame(cycles: 16000000 ~/ 60);
    }

    expect(serial.join(), contains('Running Piezo Buzzer Template Code'));
    expect(output.sounding[buzzer.key], containsAllInOrder([true, false, true]));
    expect(output.pitch[buzzer.key], closeTo(85, 2));
  });
}
