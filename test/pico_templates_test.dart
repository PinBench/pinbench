// The Pico templates beyond Blink, each run the way a user runs it: its `.cdl`
// applied to a canvas and its bundled .hex on the RP2040 emulator, checked
// through what the engine writes back to the parts.
//
// Uses the bundled .hex rather than invoking arduino-cli, so it needs no
// toolchain — and it checks the same artefact the web build ships.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/logic/ssd1306.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

/// Every update the engine writes, by node and property, repeats collapsed.
class _RecordingOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  final _history = <(LocalKey, String), List<Object?>>{};

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      for (final MapEntry(key: property, value: Object? v) in value.entries) {
        final values = _history.putIfAbsent((key, property), () => []);
        if (values.isEmpty || values.last != v) values.add(v);
      }
    }
  }

  List<Object?> history(LocalKey key, String property) => _history[(key, property)] ?? const [];
}

/// [template] on the canvas and its program loaded, ready to step.
({
  SimulationEngine engine,
  _RecordingOutput output,
  List<ComponentInstance> nodes,
  List<String> serial,
})
_open(String template) {
  final parsed = CircuitParser.applyToCanvas(
    CircuitParser.parse(File('assets/templates/$template/circuit.cdl').readAsStringSync()),
    standardParts,
  );
  final serial = <String>[];
  final output = _RecordingOutput(parsed.nodes, parsed.wires);
  final engine = SimulationEngine(output: output, onSerialPrint: serial.add)
    ..prepareForFrameStepping(
      File('assets/templates/$template/$template.ino.hex').readAsStringSync(),
    );
  addTearDown(engine.stop);
  return (engine: engine, output: output, nodes: parsed.nodes, serial: serial);
}

/// A 60th of a second of the Pico's 125 MHz clock, as the run loop slices it.
const _frame = 125000000 ~/ 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  test('Pico Button: the LED lights while the button is held', () {
    final run = _open('pico_button');
    final button = run.nodes.singleWhere((n) => n.part.name == PartNames.pushButton);
    final led = run.nodes.singleWhere((n) => n.part.name == PartNames.led);

    for (var i = 0; i < 30; i++) {
      run.engine.runFrame(cycles: _frame);
    }
    expect(run.output.history(led.key, ComponentProps.isOn), isNot(contains(true)));

    // The canvas holds the press in the button's properties; the engine reads
    // them live each frame.
    button.properties[ComponentProps.isPressed] = true;
    for (var i = 0; i < 10; i++) {
      run.engine.runFrame(cycles: _frame);
    }
    button.properties[ComponentProps.isPressed] = false;
    for (var i = 0; i < 10; i++) {
      run.engine.runFrame(cycles: _frame);
    }

    expect(run.output.history(led.key, ComponentProps.isOn), containsAllInOrder([true, false]));
    expect(run.serial, containsAllInOrder(['pressed', 'released']));
  });

  test('Pico Fade: the LED moves through its brightnesses', () {
    final run = _open('pico_fade');
    final led = run.nodes.singleWhere((n) => n.part.name == PartNames.led);

    // A full fade up and down is 2 × 52 steps of 20 ms, about 2.1 s.
    for (var i = 0; i < 130; i++) {
      run.engine.runFrame(cycles: _frame);
    }

    final levels = run.output
        .history(led.key, ComponentProps.brightness)
        .whereType<num>()
        .map((b) => b.toDouble())
        .toSet();
    expect(levels.length, greaterThan(5), reason: 'a fade passes through many levels: $levels');
    expect(levels.any((b) => b > 0 && b < 1), isTrue, reason: 'some in between: $levels');
  });

  test('Pico OLED: the display on Wire1 (GP26/GP27) shows real pixels', () {
    final run = _open('pico_oled');
    final oled = run.nodes.singleWhere((n) => n.part.name == PartNames.oledDisplay);

    for (var i = 0; i < 90; i++) {
      run.engine.runFrame(cycles: _frame, solveSpice: false);
    }

    final frames = run.output.history(oled.key, ComponentProps.oledFrame).whereType<String>();
    expect(frames, isNotEmpty, reason: 'the display was never written to');
    final display = Ssd1306Controller.unpack(frames.last);
    expect(display.displayOn, isTrue);
    var lit = 0;
    for (var y = 0; y < Ssd1306Controller.height; y++) {
      for (var x = 0; x < Ssd1306Controller.width; x++) {
        if (display.pixelAt(x, y)) lit++;
      }
    }
    expect(lit, greaterThan(100), reason: 'only $lit pixels lit');
  });
}
