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
import 'package:pinbench_ui/theme/testing.dart';

/// Characterization tests for [CanvasPointerEvent] (see
/// docs/plans/radiant-mixing-pudding.md Phase 0/5). `onPointerDown`'s nested
/// if/else-if branches are now named via `PointerInteractionMode` and split
/// into per-mode handler methods (`_handleReadOnlyTap`, `_handleStartWiring`,
/// etc.), with the 4 side-effect-free modes resolved up front by the pure
/// `PointerModeResolver` (see `pointer_mode_resolver_test.dart` for its
/// direct unit tests). The remaining ambiguous case
/// (`PointerInteractionMode.needsSelectionCheck`) still runs
/// `SelectionManager.checkSelection()` before deciding between
/// `PostSelectionMode`'s three values, since that decision depends on
/// selection state the check itself mutates. These tests lock in the 5
/// mutually-exclusive end-to-end modes' dispatch behavior.
///
/// Pointer positions are chosen so that screen == canvas coordinates (the
/// `InteractiveViewerPlusController` starts at the identity transform), and
/// hover/selection state that would normally be set by a prior
/// `onPointerHover`/`onPointerMove` call is set directly where a test needs
/// to isolate a specific mode (this mirrors the fact that `onPointerDown`
/// itself never calls `checkHover()` — it dispatches on whatever hover state
/// is already there).
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

  testWidgets('mode: box-select — pointer-down on empty canvas starts a box selection', (
    tester,
  ) async {
    final origin = await pumpCanvas(tester);

    final gesture = await tester.startGesture(origin + const Offset(400, 300));
    addTearDown(gesture.removePointer);

    expect(controller.boxSelectionRect, isNotNull);

    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();
    expect(controller.boxSelectionRect!.width, greaterThan(0));

    await gesture.up();
    await tester.pump();
    expect(controller.boxSelectionRect, isNull, reason: 'endBoxSelection clears the rect');
  });

  testWidgets('mode: node-select — pointer-down on a node selects it via checkSelection', (
    tester,
  ) async {
    final node = ComponentInstance(
      position: const Offset(100, 100),
      part: _model(PartNames.resistor),
    );
    controller.add(node);
    final origin = await pumpCanvas(tester);

    final nodeCenter = node.rect.center;
    final gesture = await tester.startGesture(origin + nodeCenter);
    addTearDown(gesture.removePointer);

    expect(controller.selectedNodes.map((n) => n.key), contains(node.key));

    await gesture.up();
  });

  testWidgets('mode: wiring — pointer-down while hovering a free port starts wiring', (
    tester,
  ) async {
    final node = ComponentInstance(position: const Offset(100, 100), part: _model(PartNames.led));
    controller.add(node);
    final origin = await pumpCanvas(tester);

    final port = PortLocation(nodeKey: node.key, portId: 'anode');
    controller.hoveredPort = port;
    final portPos = controller.wiringManager.getPortPosition(port)!;

    final gesture = await tester.startGesture(origin + portPos);
    addTearDown(gesture.removePointer);

    expect(controller.wiringManager.isWiring, isTrue);
    expect(controller.wiringManager.startPort, port);

    await gesture.up();
  });

  testWidgets(
    'mode: bend-point-drag — pointer-down on a hovered, selected wire starts dragging its bend point',
    (tester) async {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      final b = ComponentInstance(position: const Offset(200, 0), part: _model(PartNames.resistor));
      controller.add(a);
      controller.add(b);
      final startLoc = PortLocation(nodeKey: a.key, portId: 'right');
      final endLoc = PortLocation(nodeKey: b.key, portId: 'left');
      final startPos = controller.wiringManager.getPortPosition(startLoc)!;
      final bendPoint = startPos + const Offset(50, 0);
      final wire = WireModel(start: startLoc, end: endLoc, bendPoints: [bendPoint]);
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];
      controller.selectionManager.hoveredWireId = wire.id;

      final origin = await pumpCanvas(tester);
      final gesture = await tester.startGesture(origin + bendPoint);
      addTearDown(gesture.removePointer);

      expect(controller.wiringManager.isDraggingBendPoint, isTrue);

      await gesture.up();
    },
  );

  testWidgets(
    'mode: read-only push-button — pointer-down on a push button presses it, other nodes are inert',
    (tester) async {
      final button = ComponentInstance(
        position: const Offset(100, 100),
        part: _model(PartNames.pushButton),
      );
      final resistor = ComponentInstance(
        position: const Offset(300, 100),
        part: _model(PartNames.resistor),
      );
      controller.add(button);
      controller.add(resistor);
      controller.isReadOnly = true;
      final origin = await pumpCanvas(tester);

      final buttonGesture = await tester.startGesture(origin + button.rect.center);
      addTearDown(buttonGesture.removePointer);
      expect(controller.interactingNodeKey, button.key);
      await buttonGesture.up();

      controller.interactingNodeKey = null;
      final resistorGesture = await tester.startGesture(origin + resistor.rect.center);
      addTearDown(resistorGesture.removePointer);
      expect(
        controller.interactingNodeKey,
        isNull,
        reason: 'only push buttons are interactive while read-only',
      );
      await resistorGesture.up();
    },
  );
}
