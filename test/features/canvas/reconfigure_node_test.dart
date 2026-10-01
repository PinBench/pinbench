import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';

/// Changing a transistor's Type: the placed part becomes another
/// configuration of it, its wires following to the pins doing the same job.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  late ProviderContainer container;
  late CanvasController controller;
  late ComponentInstance q;
  late ComponentInstance board;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(canvasControllerProvider.notifier);
    board = ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == PartNames.arduinoUno),
    );
    q = ComponentInstance(
      position: const Offset(300, 0),
      part: PartModel.fromDefinition(PartRegistry.getPart('transistor_npn')!),
    );
    controller
      ..add(board)
      ..add(q)
      ..updateState(
        wires: [
          for (final (pin, to) in [('collector', '9'), ('base', '8'), ('emitter', 'GND_1')])
            WireModel(
              id: pin,
              start: PortLocation(nodeKey: q.key, portId: pin),
              end: PortLocation(nodeKey: board.key, portId: to),
            ),
        ],
      );
  });

  tearDown(() => container.dispose());

  ComponentInstance placed() => controller.nodes.firstWhere((n) => n.key == q.key);
  Map<String, String> wired() => {for (final w in controller.wires) w.id: w.start.portId};

  test('becomes the configuration it is changed to, in place', () {
    controller.reconfigureNode(q.key, 'Power N-MOSFET (IRLZ44N)');
    expect(placed().part.definitionId, 'power_nmos');
    expect(placed().part.size, const Size(72, 88), reason: 'a TO-220 now');
    expect(placed().position, q.position);
    expect(placed().properties['type'], 'Power N-MOSFET (IRLZ44N)');
  });

  test('its wires move to the pins doing the same job', () {
    controller.reconfigureNode(q.key, 'N-MOSFET (2N7000)');
    expect(wired(), {'collector': 'drain', 'base': 'gate', 'emitter': 'source'});
    expect(controller.wires.map((w) => w.end.portId), [
      '9',
      '8',
      'GND_1',
    ], reason: 'the board ends stay put');
  });

  test('one undo puts the part and its wires back', () {
    controller.reconfigureNode(q.key, 'P-MOSFET (BS250)');
    controller.undo();
    expect(placed().part.definitionId, 'transistor_npn');
    expect(wired(), {'collector': 'collector', 'base': 'base', 'emitter': 'emitter'});
    controller.redo();
    expect(placed().part.definitionId, 'transistor_pmos');
    expect(wired(), {'collector': 'drain', 'base': 'gate', 'emitter': 'source'});
  });

  test('picking the Type it already is changes nothing', () {
    controller.reconfigureNode(q.key, 'NPN (2N3904)');
    expect(placed().part.definitionId, 'transistor_npn');
    controller.undo();
    expect(controller.nodes, hasLength(1), reason: 'nothing was recorded, so undo takes the add');
  });
}
