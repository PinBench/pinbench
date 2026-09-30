import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';

/// The three axial diodes solved for real, each forward-biased through 1 kΩ
/// from an Uno pin: their model numbers are what tell them apart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  double forwardDrop(String id) {
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final diode = ComponentInstance(
      key: const ValueKey('d1'),
      position: const Offset(200, 0),
      part: PartModel(name: id, size: const Size(40, 72), definitionId: id),
    );
    final resistor = ComponentInstance(
      key: const ValueKey('r1'),
      position: const Offset(400, 0),
      part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
      properties: {ComponentProps.resistance: '1000'},
    );
    WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
      id: '${a.key}:$ap-${b.key}:$bp',
      start: PortLocation(nodeKey: a.key, portId: ap),
      end: PortLocation(nodeKey: b.key, portId: bp),
    );
    final nodes = [uno, diode, resistor];
    final wires = [
      wire(uno, '9', resistor, 'left'),
      wire(resistor, 'right', diode, 'anode'),
      wire(diode, 'cathode', uno, 'GND_1'),
    ];
    final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, nodes);
    spice
      ..setPinVoltage('9', 5)
      ..solve();
    return spice.getPortVoltage(diode.key, 'anode');
  }

  test('silicon diodes drop about 0.7 V at a few milliamps', () {
    expect(forwardDrop('diode_1n4148'), inInclusiveRange(0.6, 0.8));
    expect(forwardDrop('diode_1n4007'), inInclusiveRange(0.6, 0.8));
  });

  test('the Schottky drops a fraction of that', () {
    final schottky = forwardDrop('diode_1n5819');
    expect(schottky, lessThan(0.35));
    expect(schottky, lessThan(forwardDrop('diode_1n4148') - 0.3));
  });
}
