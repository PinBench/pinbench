import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_ui/theme/theme.dart';

/// Wires draw in list order (`WirePainter` iterates `wires`), so "layer
/// up/down" for a wire is reordering it in that list. ⌘]/⌘[ route to wires
/// whenever a wire is selected — same shortcuts the nodes use.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CanvasController controller;

  WireModel wire(String id) => WireModel(
    id: id,
    start: PortLocation(nodeKey: ValueKey('$id-a'), portId: 'p1'),
    end: PortLocation(nodeKey: ValueKey('$id-b'), portId: 'p2'),
    color: AppPalette.blue,
  );

  List<String> order() => controller.wires.map((w) => w.id).toList();

  setUp(() {
    container = ProviderContainer();
    controller = container.read(canvasControllerProvider.notifier);
    controller.updateState(wires: [wire('w1'), wire('w2'), wire('w3')]);
  });

  tearDown(() => container.dispose());

  test('layerUp moves the selected wire toward the top of the paint order', () {
    controller.selectWire('w1');
    controller.layerUp();
    expect(order(), ['w2', 'w1', 'w3']);
    controller.layerUp();
    expect(order(), ['w2', 'w3', 'w1']);
    controller.layerUp();
    expect(order(), ['w2', 'w3', 'w1'], reason: 'already topmost — no wraparound');
  });

  test('layerDown moves the selected wire toward the bottom, and undo restores', () {
    controller.selectWire('w3');
    controller.layerDown();
    expect(order(), ['w1', 'w3', 'w2']);

    controller.undo();
    expect(order(), ['w1', 'w2', 'w3'], reason: 'reorder is a single undoable command');
    controller.redo();
    expect(order(), ['w1', 'w3', 'w2']);
  });

  test('a selected wire wins the shortcut over a selected node', () {
    final node = ComponentInstance(
      position: Offset.zero,
      part: standardParts.firstWhere((c) => c.name == PartNames.led),
    );
    controller.add(node);
    controller.selectedNodes = [node];
    controller.selectWire('w1');

    controller.layerUp();
    expect(order(), ['w2', 'w1', 'w3'], reason: 'wire selection routes ⌘] to the wire');
    expect(controller.nodes.single.key, node.key, reason: 'node order untouched');
  });
}
