import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench/features/canvas/widgets/events/pointer_event.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/theme/testing.dart';

/// Re-routing a wire means grabbing the end you want to move and dropping it
/// somewhere else. Two things used to stop that:
///
/// 1. Hover checked wires before ports, and a wire's endpoint sits exactly on
///    the port it connects to — so that port was permanently unhoverable and
///    pressing it just re-selected the wire.
/// 2. Grabbing an end detaches (removes) the wire, and letting go anywhere
///    that wasn't a port cancelled the wiring, deleting the whole thing.
PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CanvasController controller;

  Future<Offset> pumpCanvas(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(
          CanvasPointerEvent(
            controller: controller,
            child: const SizedBox(width: 800, height: 600),
          ),
        ),
      ),
    );
    return tester.getTopLeft(find.byType(CanvasPointerEvent));
  }

  setUp(() {
    container = ProviderContainer();
    controller = container.read(canvasControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  testWidgets('a wire end can be grabbed and re-joined to another port', (tester) async {
    final origin = await pumpCanvas(tester);

    final led1 = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final led2 = ComponentInstance(part: _model(PartNames.led), position: const Offset(300, 100));
    final led3 = ComponentInstance(part: _model(PartNames.led), position: const Offset(500, 100));

    controller.updateState(
      nodes: [led1, led2, led3],
      wires: [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: led1.key, portId: 'anode'),
          end: PortLocation(nodeKey: led2.key, portId: 'cathode'),
          color: AppPalette.red,
        ),
      ],
    );

    final grabAt = led2.position + led2.getPortOffset('cathode')!;
    final dropAt = led3.position + led3.getPortOffset('cathode')!;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + grabAt);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + grabAt);
    await tester.pump();

    // The port wins over the wire that ends on it — otherwise there is no way
    // to take hold of the end.
    expect(controller.hoveredPort?.portId, 'cathode');
    expect(controller.selectionManager.hoveredWireId, isNull);

    await gesture.down(origin + grabAt);
    await tester.pump();
    expect(controller.wiringManager.isMovingWireEndpoint, isTrue);

    await gesture.moveTo(origin + grabAt + const Offset(0, -40));
    await tester.pump();
    await gesture.moveTo(origin + dropAt);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1);
    final rejoined = controller.wires.single;
    expect(rejoined.start.nodeKey, led1.key, reason: 'the far end stays put');
    expect(rejoined.end.nodeKey, led3.key, reason: 'the grabbed end moved to the new part');
    expect(rejoined.end.portId, 'cathode');
  });

  testWidgets('a wire end can be re-joined to a breadboard hole', (tester) async {
    final origin = await pumpCanvas(tester);

    final board = ComponentInstance(
      part: _model(PartNames.breadboardHalf),
      position: const Offset(20, 20),
    );
    final led = ComponentInstance(part: _model(PartNames.led), position: const Offset(500, 100));

    controller.updateState(
      nodes: [board, led],
      wires: [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: led.key, portId: 'anode'),
          end: PortLocation(nodeKey: board.key, portId: 'sig_right_g_3'),
          color: AppPalette.red,
        ),
      ],
    );

    final grabAt = board.position + board.getPortOffset('sig_right_g_3')!;
    final dropAt = board.position + board.getPortOffset('sig_left_b_12')!;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + grabAt);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + grabAt);
    await tester.pump();
    expect(controller.hoveredPort?.portId, 'sig_right_g_3');

    await gesture.down(origin + grabAt);
    await tester.pump();
    await gesture.moveTo(origin + grabAt + const Offset(0, -40));
    await tester.pump();
    await gesture.moveTo(origin + dropAt);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1);
    expect(controller.wires.single.end.portId, 'sig_left_b_12');
  });

  testWidgets('dropping a grabbed end on empty space puts the wire back', (tester) async {
    final origin = await pumpCanvas(tester);

    final led1 = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final led2 = ComponentInstance(part: _model(PartNames.led), position: const Offset(300, 100));

    controller.updateState(
      nodes: [led1, led2],
      wires: [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: led1.key, portId: 'anode'),
          end: PortLocation(nodeKey: led2.key, portId: 'cathode'),
          color: AppPalette.red,
        ),
      ],
    );

    final grabAt = led2.position + led2.getPortOffset('cathode')!;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + grabAt);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + grabAt);
    await tester.pump();
    await gesture.down(origin + grabAt);
    await tester.pump();
    await gesture.moveTo(origin + const Offset(700, 500));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1, reason: 'a missed drop must not delete the wire');
    expect(controller.wires.single.end.nodeKey, led2.key);
    expect(controller.wires.single.end.portId, 'cathode');
  });
}
