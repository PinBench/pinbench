import 'dart:math' as math;

import 'package:pinbench/features/canvas/managers/selection_manager.dart' show SelectionManager;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench/features/canvas/managers/snap_guide_helper.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Characterization tests for [SelectionManager] (see
/// docs/plans/radiant-mixing-pudding.md Phase 0), written before Phase 3
/// moves `checkHover`'s inline sin/cos unrotation math into
/// `canvas_geometry.dart` — these lock in current behavior first.
///
/// `checkHover`'s manual unrotation is cross-checked here against
/// [ComponentInstance.absoluteToLocal], an independent implementation of the
/// same inverse transform already living on the model — if the two ever
/// disagree that's a pre-existing bug worth surfacing, not a reason to loosen
/// this test.
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

  group('checkHover', () {
    test('detects an unrotated node under the cursor', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      controller.add(node);

      final center = node.rect.center;
      controller.mouseLocalPosition = center;
      controller.selectionManager.checkHover();

      expect(controller.hoveredNode?.key, node.key);
    });

    test('clears hover when the cursor moves off every node', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      controller.add(node);

      controller.mouseLocalPosition = node.rect.center;
      controller.selectionManager.checkHover();
      expect(controller.hoveredNode, isNotNull);

      controller.mouseLocalPosition = const Offset(5000, 5000);
      controller.selectionManager.checkHover();
      expect(controller.hoveredNode, isNull);
    });

    test('unrotates hover position for a rotated node consistently with ComponentInstance.absoluteToLocal', () {
      final node = ComponentInstance(
        position: const Offset(100, 100),
        part: _model(PartNames.resistor),
        rotationAngle: math.pi / 2,
      );
      controller.add(node);

      // A point offset from the node's rotated-bounding-box center, well
      // inside the rotated rect regardless of orientation.
      final probePoint = node.rect.center + const Offset(5, 3);
      controller.mouseLocalPosition = probePoint;
      controller.selectionManager.checkHover();

      final expectedLocal = node.absoluteToLocal(probePoint);
      expect(controller.hoveredNode?.key, node.key);
      expect(node.hoveredLocalPosition?.dx, closeTo(expectedLocal.dx, 0.5));
      expect(node.hoveredLocalPosition?.dy, closeTo(expectedLocal.dy, 0.5));
    });
  });

  group('moveSelection', () {
    // snapToGrid defaults to true (CanvasState) and has no public toggle in
    // this codebase today, so these tests exercise the real default rather
    // than forcing a snapToGrid=false state that the app never actually has.
    test('snaps a dragged node to the grid (default snapToGrid=true)', () {
      expect(controller.snapToGrid, isTrue);
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      controller.add(node);
      controller.selectedNodes = [node];

      final cellSize = controller.gridCellSize;
      controller.selectionManager.moveSelection(Offset(cellSize * 2.4, 0));

      final moved = controller.nodes.firstWhere((n) => n.key == node.key);
      expect(moved.position.dx % cellSize, closeTo(0, 0.001));
    });

    test('snapping aligns a dragged node to a nearby node on the same axis', () {
      final anchor = ComponentInstance(
        position: const Offset(200, 0),
        part: _model(PartNames.resistor),
      );
      final moving = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      controller.add(anchor);
      controller.add(moving);
      controller.selectedNodes = [moving];

      // Move close to (but not exactly onto) anchor's x. snapToGrid rounds
      // 202 to the nearest 10px cell (200) first, landing exactly within the
      // 10px alignment-guide threshold against the anchor.
      controller.selectionManager.moveSelection(const Offset(202, 0));

      final movedNode = controller.nodes.firstWhere((n) => n.key == moving.key);
      expect(
        movedNode.position.dx,
        anchor.position.dx,
        reason: "should snap-align to the anchor node's x",
      );
    });

    test("a leg lines up exactly with another part's pin, off-grid if need be", () {
      // The case that makes wires slant: a part sitting half a pitch off this
      // part's grid stops, so no whole-pitch drag can ever line the two up and
      // every wire between them comes out diagonal. The grid can't reach it —
      // leg-to-leg alignment has to.
      final uno = ComponentInstance(
        position: const Offset(300, 400) + const Offset(GridSystem.cellSize, 0),
        part: _model(PartNames.arduinoUno),
      );
      final led = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(uno);
      controller.add(led);
      controller.selectedNodes = [led];

      final pin = uno.position + uno.getPortOffset(uno.ports.first.id)!;
      final legOffset = led.getPortOffset('cathode')!;

      // Drag the LED so its cathode lands a few pixels off that pin, above it.
      final target = pin - legOffset - const Offset(3, 120);
      controller.selectionManager.moveSelection(target - led.position);

      final moved = controller.nodes.firstWhere((n) => n.key == led.key);
      final leg = moved.position + moved.getPortOffset('cathode')!;

      expect(
        leg.dx,
        closeTo(pin.dx, 0.001),
        reason: "the leg has to share the pin's x exactly, or the wire slants",
      );
      // ...and that means giving up the grid, which is the whole point.
      expect(moved.position.dx % GridSystem.pitch, isNot(closeTo(0, 0.001)));
    });

    test('a leg lines up with a breadboard hole column from above the board', () {
      // A part sitting *over* a board gets seated in its holes by
      // BreadboardSnapHelper. This is the other case: a part hovering above the
      // board with wires running down into it, over no hole at all, which still
      // has to share the hole's column or every one of those wires slants.
      final board = ComponentInstance(
        position:
            const Offset(400, 600) + const Offset(3, 0), // off the grid, as a template leaves it
        part: _model(PartNames.breadboardHalf),
      );
      final led = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(board);
      controller.add(led);
      controller.selectedNodes = [led];

      final boardPainter = board.part.getPainter()! as BreadboardPainter;
      final hole =
          board.position +
          board.localToNodeOffset(
            Offset(boardPainter.config.firstRowX, boardPainter.config.topTerminalStripY),
          );
      final legOffset = led.getPortOffset('cathode')!;

      // Aim a couple of hole rows ABOVE the board's first row: nowhere near a
      // hole, so nothing seats the part — only the column can be shared.
      final target = hole - legOffset - const Offset(4, 200);
      controller.selectionManager.moveSelection(target - led.position);

      final moved = controller.nodes.firstWhere((n) => n.key == led.key);
      final leg = moved.position + moved.getPortOffset('cathode')!;

      expect(leg.dy, lessThan(hole.dy - 100), reason: 'must still be above the board');
      expect(
        leg.dx,
        closeTo(hole.dx, 0.001),
        reason: 'the leg has to share the hole column, or the wire down to it slants',
      );
    });

    test('a turned board still lines a distant leg up with its strip holes', () {
      // With the board on its side the canvas-x alignment comes from the
      // board's *rows*, and the rails are its outermost columns — so a part
      // hovering off the edge is nearest a rail, whose rows are staggered half
      // a pitch from the strips'. Taking that rail's rows left every wire down
      // to a strip hole half a pitch out of true, and only from far away:
      // close up the strip section is nearer and it came good. The board has
      // to offer both, and the nearest one on the axis wins.
      final rawBoard = ComponentInstance(
        position: Offset.zero,
        part: _model(PartNames.breadboardHalf),
      ).copyWith(rotationAngle: math.pi / 2);
      final board = rawBoard.copyWith(
        position: SnapGuideHelper.snapNodeToLattice(rawBoard, const Offset(400, 600)),
      );
      final painter = board.part.getPainter()! as BreadboardPainter;
      final config = painter.config;
      // A strip hole a few rows in, which is what a part above the board gets
      // wired down to.
      final hole =
          board.position +
          board.localToNodeOffset(
            Offset(config.firstRowX + 3 * config.gridCellStep, config.topTerminalStripY),
          );

      for (final away in [200.0, 400.0]) {
        // A fresh controller per distance: one drag from rest, like a real
        // one. `moveSelection` keeps a drag accumulator that only resets on
        // the next press, so successive drags in one test would inherit the
        // last one's rounding residue and drift a row.
        final scratch = ProviderContainer();
        addTearDown(scratch.dispose);
        final dragging = scratch.read(canvasControllerProvider.notifier);

        final led = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
        dragging.updateState(nodes: [board, led]);
        dragging.selectedNodes = [led];

        final legOffset = led.getPortOffset('cathode')!;
        // 3px off the strip column, not more: the rail column is only half a
        // pitch (8px) beside it, and with the grid now stopping at every cell
        // whichever real column is nearest wins — aim further off than the
        // midpoint and the rail is the honest answer.
        final target = hole - legOffset - Offset(3, away);
        dragging.selectionManager.moveSelection(target - led.position);

        final moved = dragging.nodes.firstWhere((n) => n.key == led.key);
        final leg = moved.position + moved.getPortOffset('cathode')!;
        expect(
          leg.dx,
          closeTo(hole.dx, 0.001),
          reason: 'from ${away}px away the leg drifted ${leg.dx - hole.dx} px off the hole column',
        );
      }
    });
  });

  group('wire selection', () {
    test('selectWire sets the single selected wire id, null clears it', () {
      controller.selectionManager.selectWire('wire-1');
      expect(controller.selectionManager.selectedWireIds, ['wire-1']);

      controller.selectionManager.selectWire(null);
      expect(controller.selectionManager.selectedWireIds, isEmpty);
    });
  });
}
