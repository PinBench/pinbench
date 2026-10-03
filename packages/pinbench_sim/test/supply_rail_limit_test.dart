/// A supply rail asked for more than its board can give: the solver happily
/// delivers it, so the engine compares each rail's current with the board's
/// rating and says so — once when the load appears, and again when it goes.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  /// [ohms] across [board]'s [rail] and GND, run for a few frames; returns
  /// every warnings list the engine reported, then stops.
  List<List<String>> load(String board, String rail, String ohms, {String gnd = 'GND_1'}) {
    final boardNode = ComponentInstance(
      key: const ValueKey('board'),
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == board),
    );
    final r = ComponentInstance(
      key: const ValueKey('r'),
      position: const Offset(600, 0),
      part: standardParts.firstWhere((p) => p.name == PartNames.resistor),
      properties: {ComponentProps.resistance: ohms},
    );
    final reports = <List<String>>[];
    final engine =
        SimulationEngine(
          output: _Output(
            [boardNode, r],
            [
              WireModel(
                start: PortLocation(nodeKey: boardNode.key, portId: rail),
                end: PortLocation(nodeKey: r.key, portId: 'left'),
              ),
              WireModel(
                start: PortLocation(nodeKey: r.key, portId: 'right'),
                end: PortLocation(nodeKey: boardNode.key, portId: gnd),
              ),
            ],
          ),
          onCircuitWarnings: reports.add,
        )..prepareForFrameStepping(
          // An empty program for the Uno; a Pico refuses a file with nothing to
          // load into flash, so it runs a real one, whose pins this ignores.
          board == PartNames.picoW
              ? File('test/fixtures/pico/pico.hex').readAsStringSync()
              : ':00000001FF',
        );
    for (var i = 0; i < 3; i++) {
      engine.runFrame(cycles: 1000);
    }
    engine.stop();
    return reports;
  }

  test("10 Ω on the Uno's 3.3V draws ~330 mA, past its regulator's 150 mA", () {
    final reports = load(PartNames.arduinoUno, '3.3V', '10');
    // Reported once on the first frame that solves it — a steady overload
    // does not repeat — and cleared when the run stops.
    expect(reports, hasLength(2));
    expect(reports.first.single, contains("Arduino Uno's 3.3V supply"));
    expect(reports.first.single, contains('150 mA'));
    expect(reports.last, isEmpty);
  });

  test('a 1 kΩ load is well within it: nothing to report', () {
    expect(load(PartNames.arduinoUno, '3.3V', '1k'), isEmpty);
  });

  test("the Pico's 3V3 OUT allows 300 mA, so 20 Ω (165 mA) is fine and 10 Ω is not", () {
    expect(load(PartNames.picoW, '3.3V', '20'), isEmpty);
    expect(load(PartNames.picoW, '3.3V', '10').first.single, contains('300 mA'));
  });
}

class _Output(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}
}
