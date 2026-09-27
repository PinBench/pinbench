import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Regression test for the run-time crash
/// `type 'UniqueKey' is not a subtype of type 'ValueKey<String>'` hit when the
/// simulation serialised a parser-loaded circuit (whose nodes carry a
/// [UniqueKey]) to ship into the sim isolate.

void main() {
  test('toJson handles a UniqueKey node and stays consistent with its wires', () {
    final key = UniqueKey();
    final node = ComponentInstance(
      key: key,
      position: const Offset(10, 20),
      part: PartModel(name: PartNames.led, size: const Size(30, 80)),
    );
    final wire = WireModel(
      id: 'w1',
      start: PortLocation(nodeKey: key, portId: 'anode'),
      end: const PortLocation(nodeKey: ValueKey('gnd'), portId: 'GND_1'),
    );

    // The crash was here: toJson cast the key to ValueKey<String>.
    final nodeJson = node.toJson();
    final wireJson = wire.toJson();

    // A node and the wire endpoint that references it must serialise to the same
    // id, otherwise connectivity breaks after rehydration in the isolate.
    expect(nodeJson['id'], nodeKeyToId(key));
    expect((wireJson['start'] as Map)['nodeId'], nodeJson['id']);
  });

  test('round-trips a UniqueKey node and wire to matching ValueKey ids', () {
    final key = UniqueKey();
    final node = ComponentInstance(
      key: key,
      position: Offset.zero,
      part: PartModel(name: PartNames.led, size: const Size(30, 80)),
    );
    final wire = WireModel(
      id: 'w1',
      start: PortLocation(nodeKey: key, portId: 'anode'),
      end: const PortLocation(nodeKey: ValueKey('gnd'), portId: 'GND_1'),
    );

    final node2 = ComponentInstance.fromJson(node.toJson());
    final wire2 = WireModel.fromJson(wire.toJson());

    expect(node2.key, isA<ValueKey<String>>());
    // The rehydrated node key equals the rehydrated wire endpoint key, so the
    // netlist still connects them.
    expect(wire2.start.nodeKey, node2.key);
  });
}
