import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

ComponentInstance _node(String name, String id) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: name, size: const Size(40, 40)),
);

bool _connected(CircuitNetlist n, PortLocation a, PortLocation b) =>
    n.findConnectedPorts(a).contains(b);

void main() {
  group('CircuitNetlist pass-through components', () {
    test('a resistor connects its left and right terminals internally', () {
      final r = _node(PartNames.resistor, 'r1');
      // A wire is needed so the resistor ports enter the adjacency graph.
      final uno = _node(PartNames.arduinoUno, 'uno');
      final netlist = CircuitNetlist()
        ..buildStatic(
          [uno, r],
          [
            WireModel(
              id: 'w',
              start: PortLocation(nodeKey: uno.key, portId: '13'),
              end: PortLocation(nodeKey: r.key, portId: 'left'),
            ),
          ],
        );

      expect(
        _connected(
          netlist,
          PortLocation(nodeKey: r.key, portId: 'left'),
          PortLocation(nodeKey: r.key, portId: 'right'),
        ),
        isTrue,
      );
    });

    test('a push button connects vertical legs statically, bridge only when pressed', () {
      final btn = _node(PartNames.pushButton, 'b1');
      final uno = _node(PartNames.arduinoUno, 'uno');
      final wires = [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: uno.key, portId: '2'),
          end: PortLocation(nodeKey: btn.key, portId: 'leg1'),
        ),
        WireModel(
          id: 'w2',
          start: PortLocation(nodeKey: uno.key, portId: 'GND_1'),
          end: PortLocation(nodeKey: btn.key, portId: 'leg2'),
        ),
      ];
      final netlist = CircuitNetlist()..buildStatic([uno, btn], wires);

      final leg1 = PortLocation(nodeKey: btn.key, portId: 'leg1');
      final leg2 = PortLocation(nodeKey: btn.key, portId: 'leg2');
      final leg3 = PortLocation(nodeKey: btn.key, portId: 'leg3');

      // Static internal connection: leg1 <-> leg3 (same vertical side).
      expect(_connected(netlist, leg1, leg3), isTrue);
      // Released: the two sides are not bridged.
      expect(_connected(netlist, leg1, leg2), isFalse);

      // Press the button -> the dynamic bridge connects leg1 <-> leg2.
      btn.properties[ComponentProps.isPressed] = true;
      netlist.updateDynamic([uno, btn]);
      expect(_connected(netlist, leg1, leg2), isTrue);
    });
  });
}
