import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Characterization tests for [CanvasController] (see
/// docs/plans/radiant-mixing-pudding.md Phase 0), written *before* Phase 3
/// splits clipboard/viewport logic out of this file — these lock in current
/// behavior so that refactor has something to catch it.
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

  group('node CRUD', () {
    test('add appends a node and records history', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(node);
      expect(controller.nodes, hasLength(1));
      expect(controller.nodes.first.key, node.key);
    });

    test('add is a no-op past the 200-node cap', () {
      for (var i = 0; i < 200; i++) {
        controller.add(ComponentInstance(position: Offset.zero, part: _model(PartNames.led)));
      }
      expect(controller.nodes, hasLength(200));
      controller.add(ComponentInstance(position: Offset.zero, part: _model(PartNames.led)));
      expect(
        controller.nodes,
        hasLength(200),
        reason: 'component count cap prevents unbounded growth',
      );
    });

    test('remove deletes selected nodes and any wires touching them', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      final b = ComponentInstance(position: const Offset(50, 0), part: _model(PartNames.resistor));
      controller.add(a);
      controller.add(b);
      final wire = WireModel(
        start: PortLocation(nodeKey: a.key, portId: 'anode'),
        end: PortLocation(nodeKey: b.key, portId: 'p1'),
      );
      controller.updateState(wires: [wire]);

      controller.selectedNodes = [a];
      controller.remove();

      expect(controller.nodes.map((n) => n.key), isNot(contains(a.key)));
      expect(
        controller.wires,
        isEmpty,
        reason: 'wires touching a removed node must be removed too',
      );
    });

    test('removing a selected wire clears its selection, undo restores it', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      final b = ComponentInstance(position: const Offset(50, 0), part: _model(PartNames.resistor));
      controller.add(a);
      controller.add(b);
      final wire = WireModel(
        start: PortLocation(nodeKey: a.key, portId: 'anode'),
        end: PortLocation(nodeKey: b.key, portId: 'p1'),
      );
      controller.updateState(wires: [wire]);
      controller.selectedWireIds = [wire.id];

      controller.remove();

      expect(controller.wires, isEmpty);
      // Regression: the removed wire's id must not linger as "selected" in
      // the real selection state (SelectionManager), which used to be
      // silently unreachable via the dead CanvasState field.
      expect(controller.selectedWireIds, isEmpty);

      controller.undo();

      expect(controller.wires, hasLength(1));
      expect(controller.selectedWireIds, [wire.id]);
    });
  });

  group('undo/redo', () {
    test('undo reverses the last add, redo replays it', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(node);
      expect(controller.nodes, hasLength(1));

      controller.undo();
      expect(controller.nodes, isEmpty);

      controller.redo();
      expect(controller.nodes, hasLength(1));
      expect(controller.nodes.first.key, node.key);
    });

    test('undo/redo are no-ops in read-only mode', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(node);
      controller.isReadOnly = true;

      controller.undo();
      expect(controller.nodes, hasLength(1), reason: 'undo must not run while read-only');
    });
  });

  group('copy/paste', () {
    test('paste creates new node keys and remaps wire endpoints to them', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      final b = ComponentInstance(position: const Offset(50, 0), part: _model(PartNames.resistor));
      controller.add(a);
      controller.add(b);
      final wire = WireModel(
        start: PortLocation(nodeKey: a.key, portId: 'anode'),
        end: PortLocation(nodeKey: b.key, portId: 'p1'),
      );
      controller.updateState(wires: [wire]);

      controller.selectedNodes = [a, b];
      controller.copy();
      controller.paste();

      // Pasted nodes must be new commands, i.e. added on top of the originals
      // via a PasteCommand — the originals must remain untouched.
      expect(controller.nodes, hasLength(4));
      final originalKeys = {a.key, b.key};
      final pastedNodes = controller.nodes.where((n) => !originalKeys.contains(n.key)).toList();
      expect(pastedNodes, hasLength(2));

      // A pasted wire's endpoints must point at the *pasted* node keys, not
      // the originals, and not at a bare UniqueKey with no mapping.
      final pastedWires = controller.wires.where((w) => w.id != wire.id).toList();
      expect(pastedWires, hasLength(1));
      final pastedWire = pastedWires.first;
      final pastedKeys = pastedNodes.map((n) => n.key).toSet();
      expect(pastedKeys, contains(pastedWire.start.nodeKey));
      expect(pastedKeys, contains(pastedWire.end.nodeKey));

      // Regression: paste must select the pasted wire in the real selection
      // state (SelectionManager), not just the dead CanvasState field that
      // used to silently swallow this.
      expect(controller.selectedWireIds, [pastedWire.id]);
    });

    test('copy/paste are no-ops in read-only mode', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      controller.add(node);
      controller.selectedNodes = [node];
      controller.isReadOnly = true;

      controller.copy();
      controller.paste();

      expect(controller.nodes, hasLength(1), reason: 'paste must not run while read-only');
    });
  });

  group('fitToContent', () {
    test('centers the origin when there are no nodes', () {
      const viewportSize = Size(800, 600);
      controller.fitToContent(viewportSize);
      final translation = controller.viewerController.value.getTranslation();
      expect(translation.x, viewportSize.width / 2);
      expect(translation.y, viewportSize.height / 2);
    });

    test('scales the viewport to fit a fixed node layout', () {
      final a = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      final b = ComponentInstance(
        position: const Offset(500, 500),
        part: _model(PartNames.resistor),
      );
      controller.add(a);
      controller.add(b);

      controller.fitToContent(const Size(800, 600));

      final scale = controller.viewerController.value.getMaxScaleOnAxis();
      expect(scale, greaterThan(0));
      expect(scale, lessThanOrEqualTo(controller.maxScale));
    });
  });

  group('zoom', () {
    test('zoomIn increases the scale, zoomOut decreases it', () {
      controller.viewportSize = const Size(800, 600);
      final before = controller.scale;

      controller.zoomIn();
      expect(controller.scale, closeTo(before * 1.1, 1e-9));

      controller.zoomOut();
      expect(controller.scale, closeTo(before * 1.1 * 0.9, 1e-9));
    });

    test('zoomAt keeps the canvas point under the focal point fixed', () {
      controller.viewportSize = const Size(800, 600);
      const focal = Offset(200, 150);
      final canvasPointBefore = controller.screenToCanvasCoordinates(focal);

      controller.zoomAt(1.5, focal);

      final canvasPointAfter = controller.screenToCanvasCoordinates(focal);
      expect(canvasPointAfter.dx, closeTo(canvasPointBefore.dx, 1e-6));
      expect(canvasPointAfter.dy, closeTo(canvasPointBefore.dy, 1e-6));
    });

    test('zoomAt clamps to maxScale and minScale', () {
      controller.viewportSize = const Size(800, 600);

      controller.zoomAt(100, const Offset(400, 300));
      expect(controller.scale, closeTo(controller.maxScale, 1e-9));

      controller.zoomAt(0.000001, const Offset(400, 300));
      expect(controller.scale, closeTo(controller.minScale, 1e-9));
    });
  });

  group('rotation', () {
    ComponentInstance select() {
      final node = ComponentInstance(
        // A position a grid-snapped drag would actually produce — its legs are
        // on the connection lattice. Rotation snaps the legs back onto that
        // lattice, so starting off it would (correctly) move the part.
        position: const Offset(160, 96),
        part: _model(PartNames.led),
      );
      controller.add(node);
      controller.selectedNodes = [node];
      return node;
    }

    double angleOf(ComponentInstance node) =>
        controller.nodes.firstWhere((n) => n.key == node.key).rotationAngle;

    test('each press turns the part 45°', () {
      final node = select();

      controller.rotateRight();
      expect(angleOf(node), closeTo(math.pi / 4, 1e-9));

      controller.rotateRight();
      expect(angleOf(node), closeTo(math.pi / 2, 1e-9), reason: 'two presses reach a quarter turn');
    });

    test('rotateLeft is the same step the other way', () {
      final node = select();

      controller.rotateLeft();
      // Normalized into [0, 2π), so a left turn from square reads as 315°.
      expect(angleOf(node), closeTo(2 * math.pi - math.pi / 4, 1e-9));

      controller.rotateRight();
      expect(angleOf(node), 0.0, reason: 'back to square');
    });

    test('a full turn comes back to exactly zero, not 360°', () {
      final node = select();

      for (var i = 0; i < 8; i++) {
        controller.rotateRight();
      }
      // Exactly 0: anything else persists as a `360deg` rotation in the .cdl.
      expect(angleOf(node), 0.0);
    });

    test('rotating leaves the legs on the connection lattice', () {
      // What you see on the canvas: a part sitting in its holes, rotated, and
      // still in holes — without having to nudge it afterwards. Turning about
      // the pivot alone left the legs half a pitch out, because the pivot is
      // the top-centre of the bounding box and the legs are somewhere else.
      select();
      // The snap lattice is one cell (8px) fine now — see GridSystem.snapStep
      // — so a rotated part's legs land ≡ cellCenter mod cellSize.
      bool onLattice(double v) => ((v % 8) - 4).abs() < 1e-9;

      for (var quarterTurns = 1; quarterTurns <= 4; quarterTurns++) {
        controller.rotateRight();
        controller.rotateRight(); // two 45° steps = a quarter turn
        final node = controller.nodes.first;

        for (final port in node.ports) {
          final absolute = node.position + node.getPortOffset(port.id)!;
          expect(
            onLattice(absolute.dx),
            isTrue,
            reason: '${port.id} x=${absolute.dx} after ${quarterTurns * 90}°',
          );
          expect(
            onLattice(absolute.dy),
            isTrue,
            reason: '${port.id} y=${absolute.dy} after ${quarterTurns * 90}°',
          );
        }
      }
    });

    test('a full turn puts the part back exactly where it started', () {
      final node = select();
      final startPosition = controller.nodes.first.position;

      for (var i = 0; i < 8; i++) {
        controller.rotateRight();
      }

      expect(controller.nodes.first.position, startPosition);
      expect(angleOf(node), 0.0);
    });

    test('rotating turns the part about its pivot, give or take the lattice', () {
      final node = select();
      final before = controller.nodes.first;
      final pivotBefore = before.position + before.pivotOffset;

      controller.rotateRight();

      // The part turns about its pivot rather than drifting across the canvas,
      // but landing the legs back in holes can move it by up to half a pitch
      // — that quantization is the point, not drift.
      final after = controller.nodes.first;
      final pivotAfter = after.position + after.pivotOffset;
      expect((pivotAfter.dx - pivotBefore.dx).abs(), lessThanOrEqualTo(GridSystem.pitch / 2));
      expect((pivotAfter.dy - pivotBefore.dy).abs(), lessThanOrEqualTo(GridSystem.pitch / 2));
      expect(angleOf(node), closeTo(math.pi / 4, 1e-9));
    });
  });
}
