/// A Raspberry Pi Pico W on the canvas, end to end: the engine picks the
/// RP2040 emulator for it, runs a real arduino-pico program
/// (`test/fixtures/pico/`), and the circuit around the board sees it — an LED
/// lit from GP15 at the Pico's 3.3 V, a divider read back through the ADC on
/// GP26, and the board's own LED drawn from GP25.
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

  final hex = File('test/fixtures/pico/pico.hex').readAsStringSync();

  // Spread out, so no leg lands on another part's pin by overlap.
  var nextX = 0.0;
  ComponentInstance place(String name, String id, {Map<String, dynamic>? properties}) =>
      ComponentInstance(
        key: ValueKey(id),
        position: Offset(nextX += 1000, 0),
        part: standardParts.firstWhere((p) => p.name == name).clone(),
        properties: properties,
      );

  WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
    start: PortLocation(nodeKey: a.key, portId: ap),
    end: PortLocation(nodeKey: b.key, portId: bp),
  );

  test('a Pico W runs its sketch and drives the circuit at 3.3 V', () {
    final pico = place(PartNames.picoW, 'pico');
    final r1 = place(PartNames.resistor, 'r1', properties: {ComponentProps.resistance: '220'});
    final led = place(PartNames.led, 'led');
    final top = place(PartNames.resistor, 'top', properties: {ComponentProps.resistance: '10k'});
    final bottom = place(
      PartNames.resistor,
      'bottom',
      properties: {ComponentProps.resistance: '10k'},
    );

    final output = _RecordingOutput(
      [pico, r1, led, top, bottom],
      [
        // GP15 → 220 Ω → LED → GND
        wire(pico, '15', r1, 'left'),
        wire(r1, 'right', led, 'anode'),
        wire(led, 'cathode', pico, 'GND_4'),
        // GP16 → 10k → GP26 (A0) → 10k → GND. Off GP16, whose PWM the
        // solver sees as a held 3.3 V, so the LED's load on GP15 does not sag
        // the divider's supply through the pin's 100 Ω.
        wire(pico, '16', top, 'left'),
        wire(top, 'right', pico, '26'),
        wire(pico, '26', bottom, 'left'),
        wire(bottom, 'right', pico, 'GND_6'),
      ],
    );
    final lines = <String>[];
    final engine = SimulationEngine(output: output, onSerialPrint: lines.add)
      ..prepareForFrameStepping(hex);

    // A 60th of a second of the Pico's 125 MHz clock, as the run loop does.
    const frame = 125000000 ~/ 60;
    for (var i = 0; i < 60 && !lines.contains('DONE'); i++) {
      engine.runFrame(cycles: frame);
    }

    expect(lines, containsAll(['usb 0', 'DONE']));

    // Half of 3.3 V less the pin's drop — 3.3 × 10k / 20.1k ≈ 1.64 V — read
    // at arduino-pico's default 10 bits. The first reading comes before any
    // frame has solved the circuit.
    final readings = [
      for (final l in lines)
        if (l.startsWith('a0=')) int.parse(l.substring(3).split(' ').first),
    ];
    expect(readings.skip(1), everyElement(inInclusiveRange(500, 515)));

    // The LED on GP15 lit and went out with the pin.
    final ledStates = output.history(led.key, ComponentProps.isOn);
    expect(ledStates, containsAllInOrder([true, false, true]));

    // The board's own LED followed GP25, `LED_BUILTIN`.
    final builtin = output.history(pico.key, ComponentProps.isOn);
    expect(builtin, containsAllInOrder([true, false, true, false]));

    engine.stop();
    expect(output.history(pico.key, ComponentProps.isOn).last, isFalse);
  });

  test('a program built for the other board is refused, not run', () {
    final pico = place(PartNames.picoW, 'pico');
    final lines = <String>[];
    final engine = SimulationEngine(output: _RecordingOutput([pico], []), onSerialPrint: lines.add);
    final uno = File('test/fixtures/sensors/sensors.hex').readAsStringSync();
    expect(() => engine.prepareForFrameStepping(uno), throwsFormatException);
  });
}

/// Keeps every update the engine writes, so a test can read a property's
/// history.
class _RecordingOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  final _updates = <(LocalKey, Map<String, dynamic>)>[];

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      _updates.add((key, Map.of(value)));
    }
  }

  /// Each value [property] of [key] was set to, in order, repeats collapsed.
  List<Object?> history(LocalKey key, String property) {
    final values = <Object?>[];
    for (final (k, props) in _updates) {
      if (k != key || !props.containsKey(property)) continue;
      final value = props[property];
      if (values.isEmpty || values.last != value) values.add(value);
    }
    return values;
  }
}
