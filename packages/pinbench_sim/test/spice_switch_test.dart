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

/// The SPDT slide switch solved for real, and thrown mid-run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('common meets a, then b once the lever is thrown, without a rebuild', () {
    final uno = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    );
    final sw = ComponentInstance(
      key: const ValueKey('sw'),
      position: const Offset(200, 0),
      part: PartModel(
        name: 'Slide Switch (SPDT)',
        size: const Size(72, 88),
        definitionId: 'slide_switch_spdt',
      ),
      properties: {'position': 'A'},
    );
    ComponentInstance load(String id) => ComponentInstance(
      key: ValueKey(id),
      position: const Offset(400, 0),
      part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
      properties: {ComponentProps.resistance: '1000'},
    );
    WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
      id: '${a.key}:$ap-${b.key}:$bp',
      start: PortLocation(nodeKey: a.key, portId: ap),
      end: PortLocation(nodeKey: b.key, portId: bp),
    );

    // Pin 9 into common; each throw into its own 1 kΩ to ground.
    final loadA = load('load_a');
    final loadB = load('load_b');
    final nodes = [uno, sw, loadA, loadB];
    final wires = [
      wire(uno, '9', sw, 'common'),
      wire(sw, 'a', loadA, 'left'),
      wire(loadA, 'right', uno, 'GND_1'),
      wire(sw, 'b', loadB, 'left'),
      wire(loadB, 'right', uno, 'GND_2'),
    ];
    final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, nodes);
    spice
      ..setPinVoltage('9', 5)
      ..solve();
    expect(spice.getPortVoltage(sw.key, 'a'), greaterThan(4.5));
    expect(spice.getPortVoltage(sw.key, 'b'), lessThan(0.01));

    sw.properties['position'] = 'B';
    PartBehaviorFrameUpdater.update(
      nodes: nodes,
      spiceEngine: spice,
      isSpiceActive: true,
      lastState: {},
      elapsed: Duration.zero,
      netlist: netlist,
      unoNode: uno,
      measurements: EmulatorMeasurements(),
      queueUpdate: (_, _) {},
    );
    spice.solve();
    expect(spice.getPortVoltage(sw.key, 'a'), lessThan(0.01));
    expect(spice.getPortVoltage(sw.key, 'b'), greaterThan(4.5));
  });
}
