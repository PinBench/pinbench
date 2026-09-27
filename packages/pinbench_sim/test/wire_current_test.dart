import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/core/wire_current_solver.dart';

ComponentInstance _node(String name, String id, [Offset pos = Offset.zero]) => ComponentInstance(
  key: ValueKey(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
);

WireModel _wire(String id, ComponentInstance a, String ap, ComponentInstance b, String bp) =>
    WireModel(
      id: id,
      start: PortLocation(nodeKey: a.key, portId: ap),
      end: PortLocation(nodeKey: b.key, portId: bp),
    );

/// Builds the same model the engine does: an un-bridged netlist for SPICE and a
/// flow solver over that same graph.
({SpiceEngine spice, WireCurrentSolver flow}) _build(
  List<ComponentInstance> nodes,
  List<WireModel> wires, {
  required Key boardKey,
}) {
  final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
  return (
    spice: SpiceEngine()..build(netlist, nodes),
    flow: WireCurrentSolver(netlist, wires, boardKey: boardKey),
  );
}

void main() {
  group('LED + series resistor from a driven pin', () {
    // pin9 --w1-- R --w2-- LED anode ... cathode --w3-- GND.
    final uno = _node(PartNames.arduinoUno, 'uno');
    final resistor = _node(PartNames.resistor, 'r1', const Offset(200, 0));
    final led = _node(PartNames.led, 'led1', const Offset(400, 0));
    final nodes = [uno, resistor, led];
    final wires = [
      _wire('w1', uno, '9', resistor, 'left'),
      _wire('w2', resistor, 'right', led, 'anode'),
      _wire('w3', led, 'cathode', uno, 'GND_1'),
    ];

    test('every wire in the loop carries the same current when the pin is high', () {
      final built = _build(nodes, wires, boardKey: uno.key);
      built.spice
        ..setPinVoltage('9', 5.0)
        ..solve();

      final currents = built.flow.solve(built.spice.portInjections());

      // A 220 Ω resistor with an LED across 5 V lands in the low tens of mA.
      final w1 = currents['w1']!;
      expect(w1, greaterThan(1e-3));
      expect(w1, lessThan(5e-2));

      // Kirchhoff: one series loop, one current.
      expect(currents['w2'], closeTo(w1, w1 * 0.01));
      expect(currents['w3'], closeTo(w1, w1 * 0.01));
    });

    test('current runs pin → resistor → LED → ground, and each sign says so', () {
      final built = _build(nodes, wires, boardKey: uno.key);
      built.spice
        ..setPinVoltage('9', 5.0)
        ..solve();

      final currents = built.flow.solve(built.spice.portInjections());

      // Every wire here is drawn in the direction the current actually flows
      // (start is upstream of end), so all three read positive. A sign flip
      // anywhere in the chain would run the canvas animation backwards.
      expect(currents['w1'], isPositive, reason: 'pin 9 sources into the resistor');
      expect(currents['w2'], isPositive, reason: 'resistor feeds the LED anode');
      expect(currents['w3'], isPositive, reason: 'LED cathode returns to GND');
    });

    test('a wire drawn the other way round reports the same current, negated', () {
      final reversed = [
        wires[0],
        wires[1],
        // Same connection as w3, drawn cathode-last instead of cathode-first.
        _wire('w3', uno, 'GND_1', led, 'cathode'),
      ];
      final forward = _build(nodes, wires, boardKey: uno.key);
      final backward = _build(nodes, reversed, boardKey: uno.key);

      for (final built in [forward, backward]) {
        built.spice
          ..setPinVoltage('9', 5.0)
          ..solve();
      }

      final a = forward.flow.solve(forward.spice.portInjections())['w3']!;
      final b = backward.flow.solve(backward.spice.portInjections())['w3']!;
      expect(b, closeTo(-a, a.abs() * 0.01));
    });

    test('a pin driven low leaves the loop dead', () {
      final built = _build(nodes, wires, boardKey: uno.key);
      built.spice
        ..setPinVoltage('9', 0.0)
        ..solve();

      final currents = built.flow.solve(built.spice.portInjections());
      for (final id in ['w1', 'w2', 'w3']) {
        expect(currents[id]!.abs(), lessThan(1e-6), reason: '$id should be dead');
      }
    });
  });

  test('resistance decides magnitude: 10 kΩ carries far less than 220 Ω', () {
    double currentThrough(String ohms) {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final resistor = ComponentInstance(
        key: const ValueKey('r1'),
        position: const Offset(200, 0),
        part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
        properties: {ComponentProps.resistance: ohms},
      );
      final wires = [
        _wire('w1', uno, '9', resistor, 'left'),
        _wire('w2', resistor, 'right', uno, 'GND_1'),
      ];
      final built = _build([uno, resistor], wires, boardKey: uno.key);
      built.spice
        ..setPinVoltage('9', 5.0)
        ..solve();
      return built.flow.solve(built.spice.portInjections())['w1']!;
    }

    final small = currentThrough('220');
    final large = currentThrough('10000');
    expect(small, closeTo(5.0 / 260, 1e-3)); // 220 Ω + the pin's 40 Ω
    expect(large, closeTo(5.0 / 10040, 1e-4));
    // Two decades apart — the range the log scaling in `WireFlow` exists for.
    expect(small / large, greaterThan(30));
  });

  test('a stub hanging off a live net reads zero while the net conducts', () {
    // pin9 -- R -- GND, plus a spur from the resistor's far leg to A1. A1 is
    // not a driven pin and holds no element, so nothing flows down the spur
    // however busy the net it hangs off is.
    final uno = _node(PartNames.arduinoUno, 'uno');
    final resistor = _node(PartNames.resistor, 'r1', const Offset(200, 0));
    final wires = [
      _wire('feed', uno, '9', resistor, 'left'),
      _wire('return', resistor, 'right', uno, 'GND_1'),
      _wire('stub', resistor, 'right', uno, 'A1'),
    ];

    final built = _build([uno, resistor], wires, boardKey: uno.key);
    built.spice
      ..setPinVoltage('9', 5.0)
      ..solve();

    final currents = built.flow.solve(built.spice.portInjections());
    expect(currents['feed'], greaterThan(1e-3));
    expect(currents['return'], greaterThan(1e-3));
    expect(currents['stub']!.abs(), lessThan(1e-9));
  });

  test('a wire the solver cannot attribute is absent rather than wrong', () {
    // Both ends on the same port: no edge, so no current to report.
    final uno = _node(PartNames.arduinoUno, 'uno');
    final wires = [_wire('degenerate', uno, '9', uno, '9')];
    final built = _build([uno], wires, boardKey: uno.key);
    built.spice.solve();

    expect(built.flow.solve(built.spice.portInjections()).containsKey('degenerate'), isFalse);
  });

  test('a circuit with no wires solves to nothing without throwing', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final built = _build([uno], [], boardKey: uno.key);
    built.spice.solve();
    expect(built.flow.solve(built.spice.portInjections()), isEmpty);
  });
}
