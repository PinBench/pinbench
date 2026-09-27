import 'package:pinbench/features/canvas/managers/wiring_manager.dart' show WiringManager;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Characterization tests for [WiringManager] (see
/// docs/plans/radiant-mixing-pudding.md Phase 0), written before Phase 3
/// moves its hit-test geometry (`_isPointNearWire`/`_distanceToSegment`) into
/// `canvas_geometry.dart` — these lock in current behavior first.
PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CanvasController controller;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(canvasControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('wire lifecycle', () {
    test('start/complete wiring adds a wire connecting the two ports', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      final b = ComponentInstance(position: const Offset(100, 0), part: _model(PartNames.resistor));
      controller.add(a);
      controller.add(b);

      final startLoc = PortLocation(nodeKey: a.key, portId: 'anode');
      final endLoc = PortLocation(nodeKey: b.key, portId: 'left');

      controller.wiringManager.startWiring(startLoc, Offset.zero);
      expect(controller.wiringManager.isWiring, isTrue);

      controller.wiringManager.completeWiring(endLoc);

      expect(controller.wiringManager.isWiring, isFalse);
      expect(controller.wires, hasLength(1));
      expect(controller.wires.first.start, startLoc);
      expect(controller.wires.first.end, endLoc);
    });

    test('completing a wire onto its own start port cancels instead of connecting', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(a);
      final loc = PortLocation(nodeKey: a.key, portId: 'anode');

      controller.wiringManager.startWiring(loc, Offset.zero);
      controller.wiringManager.completeWiring(loc);

      expect(controller.wiringManager.isWiring, isFalse);
      expect(controller.wires, isEmpty);
    });

    test(
      'completing a wire between diagonal ports leaves it straight, with no invented corner',
      () {
        final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
        final b = ComponentInstance(
          position: const Offset(100, 100),
          part: _model(PartNames.resistor),
        );
        controller.add(a);
        controller.add(b);

        final startLoc = PortLocation(nodeKey: a.key, portId: 'anode');
        final endLoc = PortLocation(nodeKey: b.key, portId: 'left');

        controller.wiringManager.startWiring(startLoc, Offset.zero);
        controller.wiringManager.completeWiring(endLoc);

        // A wire bends where you bend it and nowhere else. Diagonal ports
        // used to get an elbow baked in on the way past; a wire drawn between
        // two ports that don't line up is now simply diagonal, which is the
        // honest picture of what's connected to what.
        expect(
          controller.wires.first.bendPoints,
          isEmpty,
          reason: 'no corner should be invented for the user',
        );
      },
    );

    test('cancelWiring resets wiring state without adding a wire', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(a);
      controller.wiringManager.startWiring(
        PortLocation(nodeKey: a.key, portId: 'anode'),
        Offset.zero,
      );

      controller.wiringManager.cancelWiring();

      expect(controller.wiringManager.isWiring, isFalse);
      expect(controller.wires, isEmpty);
    });
  });

  // Two resistors placed on the same y so their 'left'/'right' ports (both at
  // the component's vertical centerY) line up, producing a straight
  // horizontal wire segment instead of an orthogonal L-shaped route.
  (ComponentInstance, ComponentInstance, PortLocation, PortLocation) straightWirePair(
    CanvasController controller,
  ) {
    final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
    final b = ComponentInstance(position: const Offset(200, 0), part: _model(PartNames.resistor));
    controller.add(a);
    controller.add(b);
    return (
      a,
      b,
      PortLocation(nodeKey: a.key, portId: 'right'),
      PortLocation(nodeKey: b.key, portId: 'left'),
    );
  }

  group('hit-testing', () {
    test('checkWireInteraction is true directly on a wire segment, false far away', () {
      final (_, _, startLoc, endLoc) = straightWirePair(controller);
      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      final endPos = controller.wiringManager.getPortPosition(endLoc)!;

      controller.updateState(
        wires: [WireModel(start: startLoc, end: endLoc)],
      );

      final midpoint = Offset.lerp(startPos, endPos, 0.5)!;
      expect(controller.wiringManager.checkWireInteraction(midpoint), isTrue);
      expect(
        controller.wiringManager.checkWireInteraction(midpoint + const Offset(0, 500)),
        isFalse,
      );
    });
  });

  group('bend points', () {
    test('toggleBendPointAt inserts a bend point when a wire segment is hit', () {
      final (_, _, startLoc, endLoc) = straightWirePair(controller);
      final wire = WireModel(start: startLoc, end: endLoc);
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];

      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      final endPos = controller.wiringManager.getPortPosition(endLoc)!;
      final midpoint = Offset.lerp(startPos, endPos, 0.5)!;

      controller.wiringManager.toggleBendPointAt(midpoint);

      expect(controller.wires.first.bendPoints, hasLength(1));
    });

    test('a bend point inserted by toggleBendPointAt survives stopDraggingBendPoint '
        'when released without any further drag', () {
      final (_, _, startLoc, endLoc) = straightWirePair(controller);
      final wire = WireModel(start: startLoc, end: endLoc);
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];

      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      final endPos = controller.wiringManager.getPortPosition(endLoc)!;
      final midpoint = Offset.lerp(startPos, endPos, 0.5)!;

      // toggleBendPointAt inserts the point AND grabs it as the active drag
      // handle (so it can be dragged in the same gesture); releasing
      // immediately, as a real double-click does, must not simplify() the
      // freshly-inserted point back out just because it starts out
      // collinear with its neighbors.
      controller.wiringManager.toggleBendPointAt(midpoint);
      expect(controller.wiringManager.isDraggingBendPoint, isTrue);
      controller.wiringManager.stopDraggingBendPoint();

      expect(controller.wires.first.bendPoints, hasLength(1));
    });

    test('toggleBendPointAt on an existing bend point removes it', () {
      final (_, _, startLoc, endLoc) = straightWirePair(controller);
      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      final bendPoint = startPos + const Offset(50, 0);
      final wire = WireModel(start: startLoc, end: endLoc, bendPoints: [bendPoint]);
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];

      controller.wiringManager.toggleBendPointAt(bendPoint);

      expect(controller.wires.first.bendPoints, isEmpty);
    });

    test('stopDraggingBendPoint after a plain click-release (no movement) leaves a '
        'collinear bend point untouched, instead of simplify() silently deleting it', () {
      final (_, _, startLoc, endLoc) = straightWirePair(controller);
      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      // Collinear with start->end (straight horizontal pair), so it's the
      // case `RoutingUtils.simplify` would strip as "redundant".
      final bendPoint = startPos + const Offset(50, 0);
      final wire = WireModel(start: startLoc, end: endLoc, bendPoints: [bendPoint]);
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];

      // Grab the handle (as a real click-down would) then release without
      // ever calling updateDraggingBendPoint (no pointer movement).
      controller.wiringManager.startDraggingBendPoint(bendPoint);
      expect(controller.wiringManager.isDraggingBendPoint, isTrue);
      controller.wiringManager.stopDraggingBendPoint();

      expect(
        controller.wires.first.bendPoints,
        [bendPoint],
        reason:
            'a mere click-release must not delete the point, so a later '
            'double-click can still find and remove it on purpose',
      );
    });
  });
}
