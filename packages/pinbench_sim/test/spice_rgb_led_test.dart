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

/// The RGB LED solved for real: three dies on one cathode, each lit from the
/// current through it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('each colour conducts at its own forward voltage and lights on its own', () {
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final led = ComponentInstance(
      key: const ValueKey('rgb'),
      position: const Offset(200, 0),
      part: PartModel(name: 'RGB LED', size: const Size(56, 72), definitionId: 'rgb_led'),
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

    // Red on pin 9 and green on pin 10, each through its own 220 Ω; blue open.
    final rRed = resistor('r_red');
    final rGreen = resistor('r_green');
    final nodes = [uno, led, rRed, rGreen];
    final wires = [
      wire(uno, '9', rRed, 'left'),
      wire(rRed, 'right', led, 'red'),
      wire(uno, '10', rGreen, 'left'),
      wire(rGreen, 'right', led, 'green'),
      wire(led, 'cathode', uno, 'GND_1'),
    ];
    final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, nodes);
    spice
      ..setPinVoltage('9', 5)
      ..setPinVoltage('10', 5)
      ..solve();

    expect(spice.getPortVoltage(led.key, 'red'), inInclusiveRange(1.7, 2.2));
    expect(spice.getPortVoltage(led.key, 'green'), inInclusiveRange(2.6, 3.2));
    final red = spice.portCurrent(led.key, 'red');
    final green = spice.portCurrent(led.key, 'green');
    expect(red, inInclusiveRange(0.008, 0.013), reason: '(5 - 2 V) across 260 Ω');
    expect(green, lessThan(red), reason: 'the green die drops more, so passes less');
    expect(spice.portCurrent(led.key, 'blue'), closeTo(0, 1e-6));
    expect(
      spice.portCurrent(led.key, 'cathode'),
      closeTo(-(red + green), 1e-6),
      reason: 'everything in through the anodes leaves through the cathode',
    );

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
    final state = lastState[led.key]!;
    expect(state['red'], greaterThan(0.3));
    expect(state['green'], greaterThan(0));
    expect(state['blue'], 0.0);
  });
}
