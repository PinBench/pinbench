import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import 'package:pinbench_parts/part_registry.dart';

/// The transistor: one `.pdl`, seven configurations, one palette entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('every configuration loads, in the order its Type lists them', () {
    final npn = PartRegistry.getPart('transistor_npn')!;
    expect(PartRegistry.configurationsOf(npn).map((d) => d.id), [
      'transistor_npn',
      'transistor_pnp',
      'transistor_nmos',
      'transistor_pmos',
      'tip120',
      'power_nmos',
      'power_pmos',
    ]);
    expect(
      PartRegistry.configurationFor(npn, 'Darlington (TIP120)')?.id,
      'tip120',
      reason: 'a Type picks its configuration',
    );
  });

  test('the palette shows one Transistor, found by any of its names', () {
    final transistors = PartRegistry.paletteParts().where((p) => p.name == 'Transistor').toList();
    expect(transistors, hasLength(1));
    expect(transistors.single.definitionId, 'transistor_npn', reason: 'the default Type');
    expect(transistors.single.aliases, containsAll(['2N7000', 'TIP120', 'IRF9540N']));
  });

  group('changing Type moves each wire to the pin doing the same job', () {
    Map<String, String> moving(String from, String to) =>
        PartRegistry.pinCorrespondence(PartRegistry.getPart(from)!, PartRegistry.getPart(to)!);

    test('a pin the other has keeps its wires, wherever it now sits', () {
      expect(moving('transistor_npn', 'transistor_pnp'), {
        'collector': 'collector',
        'base': 'base',
        'emitter': 'emitter',
      });
    });

    test('bipolar to MOSFET: collector to drain, base to gate, emitter to source', () {
      expect(moving('transistor_npn', 'power_nmos'), {
        'collector': 'drain',
        'base': 'gate',
        'emitter': 'source',
      });
      expect(moving('transistor_pmos', 'tip120'), {
        'source': 'emitter',
        'gate': 'base',
        'drain': 'collector',
      });
    });
  });

  test('a .cdl keeps which Type a transistor is, though it saves the name', () {
    final pnp = PartRegistry.getPart('transistor_pnp')!;
    final board = ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == PartNames.arduinoUno),
    );
    final q = ComponentInstance(
      key: const ValueKey('q1'),
      position: const Offset(200, 0),
      part: PartModel.fromDefinition(pnp),
      properties: {'type': 'PNP (2N3906)'},
    );
    final wire = WireModel(
      id: 'w1',
      start: PortLocation(nodeKey: q.key, portId: 'collector'),
      end: PortLocation(nodeKey: board.key, portId: 'GND_1'),
    );

    final cdl = CircuitParser.generate([board, q], [wire]);
    expect(cdl, contains('q1 := Transistor {'));
    expect(cdl, contains('type: "PNP (2N3906)";'));
    final loaded = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), [
      ...PartRegistry.paletteParts(),
      ...standardParts,
    ]);
    final back = loaded.nodes.firstWhere((n) => n.key == q.key);
    expect(back.part.definitionId, 'transistor_pnp');
    expect(loaded.wires.single.start.portId, 'collector');
  });
}
