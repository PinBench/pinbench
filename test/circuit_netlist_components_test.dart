import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/painting/dsl_component_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Verifies the connected-component connectivity that backs
/// [CircuitNetlist.findConnectedPorts] (the O(1) component-label rewrite).
/// Two wired nets must stay distinct, connected ports must resolve to the same
/// component set, and an unknown port must resolve to just itself.
void main() {
  testWidgets('findConnectedPorts groups ports into electrical nets', (tester) async {
    await PartRegistry.initializeAsync();

    final pdlParts = PartRegistry.getAllParts()
        .map(
          (def) => PartModel(
            name: def.name,
            size: Size(def.visual.width, def.visual.height),
            definitionId: def.id,
            painterBuilder: ({isOutline = false, properties}) =>
                DSLComponentPainter(definition: def, isOutline: isOutline, properties: properties),
          ),
        )
        .toList();
    final components = [...pdlParts, ...standardParts];

    const cdl = '''
Circuit {
    breadboard := HalfBreadboard {
        position: (x: -210, y: -210);
    }
    uno := ArduinoUno {
        position: (x: -140, y: -130);
    }
    led1 := LED {
        position: (x: 20, y: -230);
        color: red;
    }
    Wire {
        from: breadboard.sig_right_f_0;
        to: uno.GND_1;
        color: black;
    }
    Wire {
        from: uno.13;
        to: breadboard.sig_right_i_1;
        color: red;
    }
}
''';

    final parsed = CircuitParser.parse(cdl);
    final data = CircuitParser.applyToCanvas(parsed, components);

    final netlist = CircuitNetlist();
    netlist.buildStatic(data.nodes, data.wires);

    final uno = data.nodes.firstWhere((n) => n.part.name == 'Arduino Uno');
    final part1 = data.nodes.firstWhere((n) => n.part.name.contains('Breadboard'));

    final pin13 = PortLocation(nodeKey: uno.key, portId: '13');
    final gnd = PortLocation(nodeKey: uno.key, portId: 'GND_1');
    final sigI1 = PortLocation(nodeKey: part1.key, portId: 'sig_right_i_1');
    final sigF0 = PortLocation(nodeKey: part1.key, portId: 'sig_right_f_0');

    final pin13Net = netlist.findConnectedPorts(pin13);
    final gndNet = netlist.findConnectedPorts(gnd);

    // Reflexive: a port is always in its own net.
    expect(pin13Net.contains(pin13), isTrue);

    // The wired connection puts pin 13 and the breadboard hole in one net.
    expect(pin13Net.contains(sigI1), isTrue);
    expect(gndNet.contains(sigF0), isTrue);

    // The two nets are electrically distinct and must not overlap (the LED
    // bridges them only through its diode, which is not a topological edge).
    expect(pin13Net.contains(gnd), isFalse);
    expect(gndNet.contains(pin13), isFalse);

    // Symmetric: any two connected ports resolve to the same component set.
    expect(netlist.findConnectedPorts(sigI1), equals(pin13Net));

    // An unknown/unconnected port resolves to just itself.
    final lonely = PortLocation(nodeKey: uno.key, portId: 'NOT_A_REAL_PORT');
    expect(netlist.findConnectedPorts(lonely), equals({lonely}));
  });
}
