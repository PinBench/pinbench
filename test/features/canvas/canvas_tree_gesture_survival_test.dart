import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench/features/canvas/widgets/core/canvas.dart' as fap;
import 'package:pinbench/features/canvas/widgets/events/pointer_event.dart';
import 'package:pinbench/features/canvas/widgets/painters/wire_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import '../../support/harness.dart';
import '../../support/simulation_bindings.dart';
import 'package:pinbench_ui/theme/theme.dart';

/// These exercise the *whole* canvas widget tree, not just the pointer layer.
///
/// A drag is a conversation across many frames: press, move, move, release. It
/// only survives if the widget that started it is still mounted when the last
/// word arrives — and a rebuild that re-parents that widget silently ends the
/// conversation after the first word. The canvas menu's items depend on the
/// selection, so a menu that reshapes with its item list moves everything
/// below it to a different depth as the selection changes — which is why
/// `AppContextMenu` holds its child at a fixed depth, and why pointer handling
/// lives *above* it regardless. Nothing that handles a gesture may sit under a
/// widget that reshapes with the selection.
PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CanvasController controller;

  setUp(() {
    // The canvas reads run state to draw its play button and its read-only
    // lock, and the simulation's ports have no default binding — see
    // `test/support/simulation_bindings.dart`. Nothing here starts a run.
    container = ProviderContainer(overrides: fakeSimulationBindings());
    controller = container.read(canvasControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  Future<void> pumpRealCanvas(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // The shared harness, so the canvas gets the theme its widgets expect
        // — the context menu's popover reads an accessibility scope from it
        // and throws without one.
        child: appTestApp(const fap.Canvas()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("dragging a selected wire's endpoint survives the rebuild it causes", (tester) async {
    await pumpRealCanvas(tester);

    final board = ComponentInstance(
      part: _model(PartNames.breadboardHalf),
      position: const Offset(100, 100),
    );
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
    await tester.pumpAndSettle();

    final origin = tester.getTopLeft(find.byType(fap.Canvas));
    Offset screen(Offset canvasPos) => origin + controller.canvasToScreenCoordinates(canvasPos);

    final endCanvas = board.position + board.getPortOffset('sig_right_g_5')!;
    final targetCanvas = board.position + board.getPortOffset('sig_right_j_10')!;

    // Click the wire to select it. This *fills* the context menu (a wire has
    // layer/delete items), which is what makes the next gesture dangerous.
    final onWire = screen(endCanvas + const Offset(0, -6));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: onWire);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(onWire);
    await tester.pumpAndSettle();
    await gesture.down(onWire);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selectionManager.selectedWireIds, ['w1']);

    final pointerStateBefore = tester.state(find.byType(CanvasPointerEvent));

    // Grab the end. This clears the selection, which empties the menu — the
    // rebuild that used to dispose the pointer layer out from under the drag.
    final endScreen = screen(endCanvas);
    await gesture.moveTo(endScreen);
    await tester.pumpAndSettle();
    await gesture.down(endScreen);
    await tester.pump();
    expect(controller.wiringManager.isMovingWireEndpoint, isTrue);

    expect(
      tester.state(find.byType(CanvasPointerEvent)),
      same(pointerStateBefore),
      reason: 'the widget holding the drag must survive the rebuild the drag caused',
    );

    // ...and the rest of the drag actually arrives.
    await gesture.moveTo(screen(endCanvas + const Offset(0, -30)));
    await tester.pump();

    // Mid-flight it must still be drawn as the wire it is — same treatment a
    // bend-point drag gets, handles and all — not as a faint new wire.
    final inFlight = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<WirePainter>()
        .single;
    expect(inFlight.isMovingExistingWire, isTrue);
    expect(inFlight.pendingEndMouse, isNotNull);

    await gesture.moveTo(screen(targetCanvas));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.wires.length, 1);
    expect(
      controller.wires.single.end.portId,
      'sig_right_j_10',
      reason: 'the end followed the pointer to its new hole',
    );
    expect(controller.wires.single.start.portId, 'sig_right_g_0', reason: 'the other end stayed');

    // Moving an end edits the wire you had selected — it is the same wire
    // afterwards, and still the selected one. Losing either reads as "it
    // vanished", and takes the handles you need for the next drag with it.
    expect(controller.wires.single.id, 'w1', reason: 'same wire, not a replacement');
    expect(controller.selectionManager.selectedWireIds, ['w1'], reason: 'still selected');
  });

  testWidgets('releasing an endpoint drag over nothing puts the wire back, still selected', (
    tester,
  ) async {
    await pumpRealCanvas(tester);

    final board = ComponentInstance(
      part: _model(PartNames.breadboardHalf),
      position: const Offset(100, 100),
    );
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
    await tester.pumpAndSettle();

    final origin = tester.getTopLeft(find.byType(fap.Canvas));
    Offset screen(Offset canvasPos) => origin + controller.canvasToScreenCoordinates(canvasPos);
    final endCanvas = board.position + board.getPortOffset('sig_right_g_5')!;

    controller.selectWire('w1');
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: screen(endCanvas));
    addTearDown(gesture.removePointer);
    await gesture.moveTo(screen(endCanvas));
    await tester.pumpAndSettle();
    await gesture.down(screen(endCanvas));
    await tester.pump();
    expect(controller.wiringManager.isMovingWireEndpoint, isTrue);

    // Let go over empty canvas, far from any hole.
    await gesture.moveTo(screen(const Offset(-400, -400)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.wires.length, 1, reason: 'a missed drop must not delete the wire');
    expect(controller.wires.single.end.portId, 'sig_right_g_5', reason: 'back where it was');
    expect(controller.selectionManager.selectedWireIds, ['w1']);
  });
}
