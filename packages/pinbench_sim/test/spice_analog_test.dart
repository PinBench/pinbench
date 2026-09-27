import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

ComponentInstance _node(String name, String id, [Offset pos = Offset.zero]) => ComponentInstance(
  key: ValueKey(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
);

WireModel _wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
  id: '${a.key}:$ap-${b.key}:$bp',
  start: PortLocation(nodeKey: a.key, portId: ap),
  end: PortLocation(nodeKey: b.key, portId: bp),
);

void main() {
  test('analogRead: A0 reflects the circuit voltage at the analog pin', () {
    final uno = _node(PartNames.arduinoUno, 'uno');

    // A0 wired to a driven digital pin: analogRead should track that voltage.
    final netlist = CircuitNetlist()..buildStatic([uno], [_wire(uno, '8', uno, 'A0')]);
    final spice = SpiceEngine()..build(netlist, [uno]);

    expect(spice.isPortConnected(uno.key, 'A0'), isTrue);

    spice.setPinVoltage('8', 5.0);
    spice.solve();
    expect(spice.getPortVoltage(uno.key, 'A0'), greaterThan(4.5));

    spice.setPinVoltage('8', 0.0);
    spice.solve();
    expect(spice.getPortVoltage(uno.key, 'A0'), lessThan(0.5));
  });

  test('resistor divider into A0 reads a mid-rail voltage (resistors are real)', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final r1 = _node(PartNames.resistor, 'r1', const Offset(200, 0));
    final r2 = _node(PartNames.resistor, 'r2', const Offset(400, 0));

    // pin8 -- R1 -- A0 -- R2 -- GND. With un-bridged resistors (as the engine
    // builds for SPICE), this is a genuine divider rather than a short.
    final wires = [
      _wire(uno, '8', r1, 'left'),
      _wire(r1, 'right', uno, 'A0'),
      _wire(uno, 'A0', r2, 'left'),
      _wire(r2, 'right', uno, 'GND_1'),
    ];

    final netlist = CircuitNetlist()..buildStatic([uno, r1, r2], wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, [uno, r1, r2]);

    spice.setPinVoltage('8', 5.0);
    spice.solve();

    final a0 = spice.getPortVoltage(uno.key, 'A0');
    // Equal resistors => roughly half the drive voltage (minus the GPIO source R).
    expect(a0, greaterThan(1.5));
    expect(a0, lessThan(3.5));
  });

  test('potentiometer wiper voltage tracks its position (analogRead a pot)', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final pot = ComponentInstance(
      key: const ValueKey('pot1'),
      position: const Offset(200, 0),
      part: PartModel(name: PartNames.potentiometer, size: const Size(60, 50)),
      properties: {ComponentProps.potentiometerValue: '0.75'},
    );

    // term1 -> pin8 (5V), term2 -> GND, wiper -> A0.
    final wires = [
      _wire(uno, '8', pot, 'term1'),
      _wire(pot, 'term2', uno, 'GND_1'),
      _wire(pot, 'wiper', uno, 'A0'),
    ];

    final netlist = CircuitNetlist()..buildStatic([uno, pot], wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, [uno, pot]);

    spice.setPinVoltage('8', 5.0);
    spice.solve();

    // wiper ≈ position * 5V (10k track dwarfs the 40Ω GPIO source resistance).
    final wiper = spice.getPortVoltage(uno.key, 'A0');
    expect(wiper, closeTo(3.75, 0.2));
  });

  test('PWM pin 5 drives an attached LED (pin is now simulated)', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final led = _node(PartNames.led, 'led1', const Offset(200, 0));

    final wires = [_wire(uno, '5', led, 'anode'), _wire(led, 'cathode', uno, 'GND_1')];

    final netlist = CircuitNetlist()..buildStatic([uno, led], wires);
    final spice = SpiceEngine()..build(netlist, [uno, led]);

    spice.setPinVoltage('5', 5.0);
    spice.solve();
    expect(spice.getLedCurrent(led.key.toString()).abs(), greaterThan(1e-6));

    spice.setPinVoltage('5', 0.0);
    spice.solve();
    expect(spice.getLedCurrent(led.key.toString()).abs(), lessThan(1e-6));
  });
}
