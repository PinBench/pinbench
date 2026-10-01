import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/engine_pin_api.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/core/updaters/part_behavior_frame_updater.dart';

/// The 7-segment display solved for real: a die per segment on one cathode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('drives the segments it is given, through either cathode pin', () {
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final display = ComponentInstance(
      key: const ValueKey('disp'),
      position: const Offset(200, 0),
      part: PartModel(
        name: '7-Segment Display',
        size: const Size(104, 136),
        definitionId: 'seven_segment',
      ),
    );
    ComponentInstance resistor(String id) => ComponentInstance(
      key: ValueKey(id),
      position: const Offset(400, 0),
      part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
      properties: {ComponentProps.resistance: '220'},
    );
    WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
      id: '${a.key}:$ap-${b.key}:$bp',
      start: PortLocation(nodeKey: a.key, portId: ap),
      end: PortLocation(nodeKey: b.key, portId: bp),
    );

    // Segments a and b through their own resistors; the cathode grounded only
    // through the *second* COM pin, which must be tied to the first inside.
    final rA = resistor('r_a');
    final rB = resistor('r_b');
    final nodes = [uno, display, rA, rB];
    final wires = [
      wire(uno, '9', rA, 'left'),
      wire(rA, 'right', display, 'a'),
      wire(uno, '10', rB, 'left'),
      wire(rB, 'right', display, 'b'),
      wire(display, 'com2', uno, 'GND_1'),
    ];
    final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, nodes);
    spice
      ..setPinVoltage('9', 5)
      ..setPinVoltage('10', 5)
      ..solve();

    expect(spice.getPortVoltage(display.key, 'a'), inInclusiveRange(1.7, 2.2));
    expect(spice.portCurrent(display.key, 'a'), inInclusiveRange(0.008, 0.013));
    expect(spice.portCurrent(display.key, 'c'), closeTo(0, 1e-9));

    final lastState = <LocalKey, Map<String, Object?>>{};
    PartBehaviorFrameUpdater.update(
      nodes: nodes,
      spiceEngine: spice,
      isSpiceActive: true,
      lastState: lastState,
      elapsed: Duration.zero,
      netlist: netlist,
      unoNode: uno,
      measurements: EmulatorMeasurements(),
      queueUpdate: (_, _) {},
    );
    final state = lastState[display.key]!;
    expect(state['a'], greaterThan(0.3));
    expect(state['b'], greaterThan(0.3));
    for (final dark in ['c', 'd', 'e', 'f', 'g', 'dp']) {
      expect(state[dark], 0.0, reason: '$dark has no current');
    }
  });
}
