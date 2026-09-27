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

/// Wiring is only usable if you can actually point at a port. Two things used
/// to stop that, and both are easy to reintroduce by accident:
///
/// 1. Port hit-testing asked only the topmost node whose *bounds* contained
///    the pointer. Component bounds are mostly empty space — an LED is a box
///    holding a thin lens and two legs — so any breadboard hole under that box
///    became impossible to land a wire on the moment a part was dropped near
///    it. Now a wire in flight sees through parts; idle hover still doesn't,
///    which is what keeps those parts draggable.
/// 2. The hit radius was a fixed canvas distance, so it shrank on screen as
///    you zoomed out until a leg was a couple of pixels wide.
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

  String? portAt(Offset canvasPosition) {
    controller.mouseLocalPosition = controller.canvasToScreenCoordinates(canvasPosition);
    controller.hoveredPort = null;
    controller.selectionManager.checkHover();
    return controller.hoveredPort?.portId;
  }

  testWidgets('a wire can land on a hole under a part, but idle hover cannot', (tester) async {
    await pumpCanvas(tester);

    final board = ComponentInstance(part: _model(PartNames.breadboardHalf), position: Offset.zero);
    // Dropped with its top-left corner on hole f5. The board lies landscape,
    // so the row axis is x: the holes the lens covers are the next rows
    // along, not the next letters down.
    final led = ComponentInstance(part: _model(PartNames.led), position: const Offset(116, 196));
    controller.updateState(nodes: [board, led]);

    // A hole under the LED's lens — actually hidden by it.
    final masked = board.position + board.getPortOffset('sig_right_f_6')!;
    expect(led.covers(masked), isTrue, reason: 'the hole must be under the LED itself');

    // Idle, the LED shadows it — that's what leaves the LED grabbable where
    // it's drawn.
    expect(portAt(masked), isNull);

    // With a wire in flight there's nothing to protect, so the hole is a
    // legitimate target and the wire can be landed on it.
    controller.startWiring(
      PortLocation(nodeKey: led.key, portId: 'anode'),
      led.position + led.getPortOffset('anode')!,
    );
    expect(portAt(masked), 'sig_right_f_6');
    controller.cancelWiring();

    // The LED's own legs still win where they actually are.
    expect(portAt(led.position + led.getPortOffset('anode')!), 'anode');
    expect(portAt(led.position + led.getPortOffset('cathode')!), 'cathode');
  });

  testWidgets('holes beside a part, inside its bounds, still hover', (tester) async {
    await pumpCanvas(tester);

    final board = ComponentInstance(part: _model(PartNames.breadboardHalf), position: Offset.zero);
    final led = ComponentInstance(part: _model(PartNames.led), position: const Offset(116, 196));
    controller.updateState(nodes: [board, led]);

    // A 5 mm LED sits in a 56×56 box, so there's a hole pitch of air either
    // side of its lens. Those holes used to be dead — inside the LED's bounds,
    // so the LED swallowed them — even though nothing was drawn over them.
    // Hole f5 is the LED's own top-left corner: bounds, but no ink.
    final beside = board.position + board.getPortOffset('sig_right_f_5')!;
    expect(led.rect.contains(beside), isTrue, reason: 'still inside the LED bounds');
    expect(led.covers(beside), isFalse, reason: 'but not under the LED itself');

    expect(portAt(beside), 'sig_right_f_5');
  });

  testWidgets('a wire in flight stays landable when zoomed out', (tester) async {
    await pumpCanvas(tester);

    final led1 = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final led2 = ComponentInstance(part: _model(PartNames.led), position: const Offset(300, 100));
    controller.updateState(nodes: [led1, led2]);
    final target = led2.position + led2.getPortOffset('anode')!;

    controller.zoomAt(0.4, const Offset(400, 300));
    // Six screen pixels off the leg: an ordinary aim for a hand, and the same
    // aim at any zoom. It used to miss below 100%, because the radius was a
    // canvas distance and so shrank on screen along with the leg.
    final offBy6ScreenPx = target + Offset(0, 6 / controller.scale);
    expect(portAt(offBy6ScreenPx), isNull, reason: 'idle stays precise, so parts stay draggable');

    controller.startWiring(
      PortLocation(nodeKey: led1.key, portId: 'anode'),
      led1.position + led1.getPortOffset('anode')!,
    );
    expect(portAt(offBy6ScreenPx), 'anode');
  });

  testWidgets('at 100% zoom an idle pointer still has to be on the port', (tester) async {
    await pumpCanvas(tester);

    final led = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    controller.updateState(nodes: [led]);
    final anode = led.position + led.getPortOffset('anode')!;

    // The idle radius is tight — about the size of a hole as it's drawn — so
    // the LED's body stays grabbable for dragging rather than being one big
    // wire-starting target, and a port only lights up when the pointer is
    // really on it rather than merely nearer to it than to its neighbour.
    expect(portAt(anode + const Offset(3, 0)), 'anode');
    expect(portAt(anode + const Offset(5, 0)), isNull);
    expect(portAt(anode + const Offset(10, 0)), isNull);
  });

  testWidgets('a wire in flight snaps to the nearest port', (tester) async {
    final origin = await pumpCanvas(tester);

    final led1 = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final led2 = ComponentInstance(part: _model(PartNames.led), position: const Offset(300, 100));
    controller.updateState(nodes: [led1, led2]);

    final from = led1.position + led1.getPortOffset('anode')!;
    final to = led2.position + led2.getPortOffset('cathode')!;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + from);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + from);
    await tester.pump();
    expect(controller.hoveredPort?.portId, 'anode', reason: 'hovering the source leg');

    await gesture.down(origin + from);
    await tester.pump();
    expect(controller.wiringManager.isWiring, isTrue);

    await gesture.moveTo(origin + from + const Offset(0, -40));
    await tester.pump();

    // Released a full 10 px short of the target leg — while wiring that still
    // lands, because there is nothing else the drag could mean. (Sideways it
    // would snap to the other leg instead, which is the point of nearest-wins.)
    await gesture.moveTo(origin + to + const Offset(0, 10));
    await tester.pump();
    expect(controller.hoveredPort?.portId, 'cathode');

    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1);
    expect(controller.wires.single.start.portId, 'anode');
    expect(controller.wires.single.end.portId, 'cathode');
  });

  testWidgets("a selected wire's bend handle beats the port under it", (tester) async {
    await pumpCanvas(tester);

    final led = ComponentInstance(part: _model(PartNames.led), position: Offset.zero);
    controller.add(led);
    final anodeCanvas = led.position + led.getPortOffset('anode')!;

    // A bend point parked exactly on the LED's anode — bend points snap to
    // the same lattice ports live on, so this is an everyday layout.
    final wire = WireModel(
      id: WireModel.generateId(),
      start: const PortLocation(nodeKey: ValueKey('a'), portId: 'p1'),
      end: const PortLocation(nodeKey: ValueKey('b'), portId: 'p2'),
      bendPoints: [anodeCanvas],
      color: AppPalette.blue,
    );
    controller.updateState(wires: [wire]);

    expect(portAt(anodeCanvas), 'anode', reason: 'wire not selected: port hovers as usual');

    controller.selectWire(wire.id);
    expect(
      portAt(anodeCanvas),
      isNull,
      reason: 'wire selected: its handle must win, or pressing it starts a wire from the port',
    );
    expect(controller.hoveredWireId, wire.id, reason: 'the handle hover belongs to the wire');

    controller.selectWire(null);
    expect(portAt(anodeCanvas), 'anode', reason: 'deselecting gives the port back');
  });

  testWidgets('an endpoint stays grabbable when a bend elbows right next to it', (tester) async {
    await pumpCanvas(tester);

    final led = ComponentInstance(part: _model(PartNames.led), position: Offset.zero);
    controller.add(led);
    final anodeCanvas = led.position + led.getPortOffset('anode')!;

    // The everyday elbow: a bend one grid cell from the endpoint, well inside
    // the handle's generous grab radius. Suppressing every port within that
    // radius made the endpoint itself ungrabbable on any selected wire with a
    // corner near its end — nearest-target-wins is what keeps both alive.
    final wire = WireModel(
      id: WireModel.generateId(),
      start: PortLocation(nodeKey: led.key, portId: 'anode'),
      end: const PortLocation(nodeKey: ValueKey('b'), portId: 'p2'),
      bendPoints: [anodeCanvas + const Offset(8, 0)],
      color: AppPalette.blue,
    );
    controller.updateState(wires: [wire]);
    controller.selectWire(wire.id);

    expect(
      portAt(anodeCanvas),
      'anode',
      reason: 'on the endpoint the port is the nearer target and must win',
    );
    expect(
      portAt(anodeCanvas + const Offset(8, 0)),
      isNull,
      reason: 'on the bend the handle is the nearer target and must win',
    );
    expect(controller.hoveredWireId, wire.id);
  });

  testWidgets("a bend on the selected wire's own endpoint never blocks grabbing it", (
    tester,
  ) async {
    final origin = await pumpCanvas(tester);

    final led1 = ComponentInstance(part: _model(PartNames.led), position: const Offset(100, 100));
    final led2 = ComponentInstance(part: _model(PartNames.led), position: const Offset(300, 100));
    controller.updateState(nodes: [led1, led2]);
    final grabAt = led2.position + led2.getPortOffset('cathode')!;

    // A bend parked exactly on the wire's own end — dragging and simplify can
    // leave one there. The bend-beats-port rule must NOT apply to the wire's
    // own endpoint port, or the end becomes ungrabbable precisely when the
    // wire is selected (and works again when it isn't — maximum confusion).
    final wire = WireModel(
      id: 'w1',
      start: PortLocation(nodeKey: led1.key, portId: 'anode'),
      end: PortLocation(nodeKey: led2.key, portId: 'cathode'),
      bendPoints: [grabAt],
      color: AppPalette.red,
    );
    controller.updateState(wires: [wire]);
    controller.selectWire(wire.id);

    expect(portAt(grabAt), 'cathode', reason: 'the endpoint port must survive its own bend');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + grabAt);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + grabAt);
    await tester.pump();
    await gesture.down(origin + grabAt);
    await tester.pump();

    expect(
      controller.wiringManager.isMovingWireEndpoint,
      isTrue,
      reason: 'pressing the end of a selected wire grabs the end, not the bend on it',
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('clicking a wire then pressing its end grabs it, without moving the mouse', (
    tester,
  ) async {
    final origin = await pumpCanvas(tester);

    // A wire between two breadboard holes — the everyday case, and the one
    // the tight idle port radius makes hardest: a press a few pixels off the
    // hole is a wire hover, not a port hover.
    final board = ComponentInstance(part: _model(PartNames.breadboardHalf), position: Offset.zero);
    controller.updateState(
      nodes: [board],
      wires: [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: board.key, portId: 'sig_right_g_0'),
          end: PortLocation(nodeKey: board.key, portId: 'sig_right_g_5'),
          color: AppPalette.red,
        ),
      ],
    );
    final endAt = board.position + board.getPortOffset('sig_right_g_5')!;
    final target = board.position + board.getPortOffset('sig_right_j_10')!;

    // Six pixels up the wire from its end: inside the end handle's grab
    // radius, outside the tight idle port radius. One spot, two meanings —
    // and which one it has depends on whether the wire is selected.
    final grabAt = endAt + const Offset(0, -6);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + grabAt);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + grabAt);
    await tester.pump();

    // Click once: selects the wire.
    await gesture.down(origin + grabAt);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.selectionManager.selectedWireIds, ['w1']);

    // Press again on the same pixel, with NO pointer movement in between —
    // which is exactly what a hand does. Hover is only recomputed on movement,
    // so this press used to be judged against hover from before the selection
    // existed: it did nothing at all, and a press a hair further out
    // deselected the wire instead of grabbing it.
    await gesture.down(origin + grabAt);
    await tester.pump();
    expect(
      controller.wiringManager.isMovingWireEndpoint,
      isTrue,
      reason: 'the second press must pick the end up, not fall through to nothing',
    );
    expect(
      controller.selectionManager.selectedWireIds,
      isEmpty,
      reason: 'the wire is in hand now, not selected',
    );

    await gesture.moveTo(origin + grabAt + const Offset(0, -40));
    await tester.pump();
    await gesture.moveTo(origin + target);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1);
    expect(controller.wires.single.end.portId, 'sig_right_j_10');
    expect(controller.wires.single.start.portId, 'sig_right_g_0', reason: 'the other end stayed');
  });

  testWidgets("a neighbouring hole never outranks a selected wire's end", (tester) async {
    final origin = await pumpCanvas(tester);

    final board = ComponentInstance(part: _model(PartNames.breadboardHalf), position: Offset.zero);
    controller.updateState(
      nodes: [board],
      wires: [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: board.key, portId: 'sig_right_g_0'),
          end: PortLocation(nodeKey: board.key, portId: 'sig_right_g_5'),
          color: AppPalette.red,
        ),
      ],
    );

    final endAt = board.position + board.getPortOffset('sig_right_g_5')!;
    final neighbour = board.position + board.getPortOffset('sig_right_h_5')!;
    expect(
      (neighbour - endAt).distance,
      lessThan(16.1),
      reason: 'holes are one pitch apart — nearer than the end handle reaches',
    );

    // Most of the way to the hole next door: that hole is the *nearer*
    // port, and it used to take the hover, so the press started a new wire
    // from it. While the wire is selected its end handle owns this ground.
    final offCentre = endAt + (neighbour - endAt) * 0.8;

    controller.selectWire(null);
    controller.mouseLocalPosition = controller.canvasToScreenCoordinates(offCentre);
    controller.selectionManager.checkHover();
    expect(
      controller.hoveredPort?.portId,
      'sig_right_h_5',
      reason: 'unselected, the nearer hole is simply the nearer hole',
    );

    controller.selectWire('w1');
    controller.mouseLocalPosition = controller.canvasToScreenCoordinates(offCentre);
    controller.selectionManager.checkHover();
    expect(
      controller.hoveredPort?.portId,
      'sig_right_g_5',
      reason: "selected, the wire's own end wins outright",
    );

    // And the press follows the hover: it grabs the end rather than starting
    // a wire from the hole next door.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + offCentre);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + offCentre);
    await tester.pump();
    await gesture.down(origin + offCentre);
    await tester.pump();
    expect(controller.wiringManager.isMovingWireEndpoint, isTrue);
    expect(
      controller.wires,
      isEmpty,
      reason: 'the wire is in hand, not a second wire on the board',
    );
    await gesture.up();
    await tester.pump();
    expect(controller.wires.length, 1, reason: 'released without moving: put back as it was');
  });

  testWidgets("a selected wire's end grabs with handle tolerance, and re-joins", (tester) async {
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

    final endAt = led2.position + led2.getPortOffset('cathode')!;
    // A real hand's press: 8px off the drawn end circle — outside the tight
    // 4px idle port radius, well inside the 15px handle radius. Unselected,
    // this is nothing (the tight radius is what keeps parts draggable)...
    final nearEnd = endAt + const Offset(8, 4);
    expect(portAt(nearEnd), isNull, reason: 'unselected: a near-miss stays a miss');

    // ...selected, the visible end circle is a handle and must grab like one.
    controller.selectWire('w1');
    expect(portAt(nearEnd), 'cathode', reason: 'selected: the end grabs with handle tolerance');

    final dropAt = led3.position + led3.getPortOffset('cathode')!;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + nearEnd);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(origin + nearEnd);
    await tester.pump();
    await gesture.down(origin + nearEnd);
    await tester.pump();
    expect(controller.wiringManager.isMovingWireEndpoint, isTrue);

    await gesture.moveTo(origin + nearEnd + const Offset(0, -40));
    await tester.pump();
    await gesture.moveTo(origin + dropAt);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.wires.length, 1);
    expect(controller.wires.single.end.nodeKey, led3.key, reason: 'the end re-joined led3');
  });
}
