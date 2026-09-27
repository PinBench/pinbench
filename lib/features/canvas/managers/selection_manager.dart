import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/pdl_flutter.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/painters/breadboard_painter/logic/breadboard_hit_tester.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'canvas_commands.dart';
import 'canvas_context.dart';
import 'breadboard_snap_helper.dart';
import 'snap_guide_helper.dart';
import '../utils/canvas_geometry.dart';

/// Handles hover detection, click/box selection, and dragging of the selected
/// nodes on the canvas (including breadboard hole snapping). Reads/writes canvas
/// state through the [CanvasContext].
class SelectionManager {
  final CanvasContext context;
  SelectionManager(this.context);
  Offset _dragAccumulator = Offset.zero;

  bool isSelected(Key key) => context.selectedNodes.any((n) => n.key == key);

  bool isHovered(Key key) => context.hoveredNode != null && context.hoveredNode!.key == key;

  void clearSelection() {
    if (context.selectedNodes.isNotEmpty) {
      context.selectedNodes.clear();
      context.forceUpdate();
    }
  }

  List<ComponentInstance>? _dragInitialNodes;
  List<WireModel>? _dragInitialWires;

  void startDragSelection() {
    if (context.selectedNodes.isNotEmpty) {
      _dragInitialNodes = context.selectedNodes.map((n) => n.copyWith()).toList();
    }
    if (context.selectedWireIds.isNotEmpty) {
      _dragInitialWires = context.wires
          .where((w) => context.selectedWireIds.contains(w.id))
          .map((w) => w.copyWith())
          .toList();
    }
  }

  void commitDragSelection() {
    if (_dragInitialNodes != null && _dragInitialNodes!.isNotEmpty) {
      final currentNodes = context.selectedNodes.map((n) => n.copyWith()).toList();
      context.executeCommand(UpdateNodesCommand(_dragInitialNodes!, currentNodes));
      _dragInitialNodes = null;
    }

    if (_dragInitialWires != null && _dragInitialWires!.isNotEmpty) {
      final currentWires = context.wires
          .where((w) => context.selectedWireIds.contains(w.id))
          .map((w) => w.copyWith())
          .toList();
      context.executeCommand(UpdateWiresCommand(_dragInitialWires!, currentWires));
      _dragInitialWires = null;
    }
  }

  void checkHover() {
    // Convert screen coordinates to canvas coordinates
    final canvasPosition = context.screenToCanvasCoordinates(context.mouseLocalPosition);

    var changed = false;

    // 1. Priority Hover: a selected wire's own handles, then ports, then wires.
    //
    // A selected wire is the thing being edited, so its drawn handles own
    // their radius outright: an end circle within grabbing range takes the
    // hover even when some port is nearer. It has to be outright. On a
    // breadboard the neighbouring hole is one pitch away — nearer than the
    // handle reaches from most of the places a hand actually lands — so
    // letting the nearer port win left the end grabbable only from dead
    // centre, and a press a few pixels out silently started a brand-new wire
    // from the hole next door. Nothing is lost by yielding the port: deselect
    // the wire and every port answers normally again.
    //
    // `selectedEndpointAt` already yields to a bend handle that is strictly
    // closer, so a wire's ends and its bends stay reachable side by side.
    final selectedEnd = context.selectedEndpointAt(canvasPosition);

    // Then ports, before wires, because a wire's endpoint sits exactly on the
    // port it connects to. Letting the wire win there made that port
    // permanently unhoverable, so an end could never be grabbed and re-joined
    // somewhere else — pressing it just selected the wire again.
    //
    // One exception: a *selected* wire's bend-point handle beats the port
    // when the handle is the NEARER target (ties go to the handle — a bend
    // parked exactly on a port is the case this exists for; without it,
    // pressing that handle started a wire from the port under it). Nearer,
    // not merely in range: the handle's grab radius is generous, and a bend
    // usually sits one elbow — one grid cell — from the wire's endpoint, so
    // suppressing every port inside the radius made the ports around a corner
    // unhoverable.
    //
    // And one exception to the exception: a port a selected wire's own END
    // sits on is never suppressed — not even by a bend parked exactly on it.
    // Grabbing the end of the wire you selected is the whole point of
    // selecting it, and the endpoint handle drawn there looks identical to a
    // bend handle, so losing that press to a bend reads as "endpoint grab is
    // broken". A bend that close to its own end has no routing meaning a
    // fresh drag couldn't recreate.
    var portLoc = selectedEnd ?? _findPortAt(canvasPosition);
    final handleDistance = context.selectedBendHandleDistance(canvasPosition);
    if (selectedEnd == null &&
        portLoc != null &&
        handleDistance != null &&
        !context.isSelectedWireEndpoint(portLoc)) {
      final portPos = CanvasGeometry.getPortPosition(portLoc, context.nodes);
      if (portPos == null || handleDistance <= (canvasPosition - portPos).distance) {
        portLoc = null;
      }
    }

    if (portLoc != null) {
      if (context.hoveredWireId != null) {
        context.hoveredWireId = null;
        changed = true;
      }
    } else {
      final hitWire = context.checkWireInteraction(canvasPosition);
      if (hitWire) {
        if (context.hoveredNode != null || context.hoveredPort != null) {
          context.hoveredNode?.hoveredLocalPosition = null;
          context.hoveredNode?.breadboardHover = null;
          context.hoveredNode = null;
          context.hoveredPort = null;
          changed = true;
        }
        if (changed) {
          context.forceUpdate();
        }
        return;
      } else {
        if (context.hoveredWireId != null) {
          context.hoveredWireId = null;
          changed = true;
        }
      }
    }

    // 2. Node Hover
    //
    // `covers`, not `rect.contains`: a part's bounds reach out to its leads, so
    // most of a small part's box is air. Hovering that air belongs to whatever
    // is under it — on a breadboard, the holes beside the part.
    ComponentInstance? found;
    for (final node in context.nodes.reversed) {
      if (node.covers(canvasPosition)) {
        found = node;
        break;
      }
    }

    // Selection logic handles context.selectedNodes in controller.dart checkSelection()
    // and box selection methods, so we don't set context.selectedNodes here.
    if (context.hoveredNode != found) {
      context.hoveredNode?.hoveredLocalPosition = null;
      context.hoveredNode?.breadboardHover = null;
      context.hoveredNode = found;
      context.hoveredPort = null;
      changed = true;
    }

    // Update hover position and port for current node
    if (found != null) {
      // Unrotate/un-flip canvasPosition into the component's own local space
      // to match the unrotated component painters. Reuses the same inverse
      // transform ComponentInstance.absoluteToLocal already implements
      // (verified identical via a rotated-node characterization test) rather
      // than keeping a second copy of this math here.
      final localPos = found.absoluteToLocal(canvasPosition);

      // Update breadboard-specific hover
      final painter = found.part.getPainter();
      if (painter is BreadboardPainter) {
        // Same radius the port lookup above used: the hole that lights up has
        // to be the one a click would actually wire to. And precise on both
        // axes while idle, so a terminal-strip row lights up only when the
        // pointer is on one of its holes rather than anywhere across the strip
        // — which is how the rails have always behaved.
        final newBreadboardHover = BreadboardHitTester.hitTest(
          localPos,
          painter.config,
          hitRadius: _portHitRadius,
          preciseColumns: !context.isWiring,
        );
        if (found.breadboardHover != newBreadboardHover) {
          found.breadboardHover = newBreadboardHover;
          changed = true;
        }
      }

      if (found.hoveredLocalPosition != localPos) {
        found.hoveredLocalPosition = localPos;
        changed = true;
      }
    }

    if (context.hoveredPort != portLoc) {
      context.hoveredPort = portLoc;
      changed = true;
    }

    if (changed) {
      context.forceUpdate();
    }
  }

  /// How close the pointer has to be to a port, in *screen* pixels.
  ///
  /// Screen rather than canvas, because that's the distance the hand has to
  /// be accurate to: a fixed canvas radius shrinks along with everything else
  /// as you zoom out, until a leg is a target a couple of pixels wide. The
  /// wire handles already work this way — see `WiringManager._handleHitRadius`.
  ///
  /// Only while wiring, though. Idle hover uses [_idlePortHitRadius], a fixed
  /// canvas distance at every zoom, because a breadboard's holes are one hole
  /// pitch apart: growing the radius as you zoom out closes the gaps between
  /// them, and those gaps are the only thing left to grab when you want to
  /// drag the board rather than wire to it. Starting a wire therefore still
  /// wants a reasonably precise press — but landing one, which is what a drag
  /// ends with, no longer does.
  static const _wiringPortHitRadiusPx = 18.0;

  /// How close an *idle* pointer has to be to a port to light it up, in canvas
  /// units — tighter than [kPortHitRadius], and deliberately so.
  ///
  /// [kPortHitRadius] is a geometry constant: it's what the netlist means by
  /// "this leg is plugged into that hole", so it has to be generous enough to
  /// tolerate a part sitting a hair off its hole. Reusing it for hover made
  /// the highlight fire from most of a hole pitch away, so ports lit up while
  /// the pointer was plainly between two of them. This is sized to the hole as
  /// it's *drawn* instead (see `BreadboardUtils.drawHole`, outer radius 5), so
  /// the pointer has to actually be on the thing that lights up.
  static const _idlePortHitRadius = 4.0;

  double? get _portHitRadius {
    if (!context.isWiring) return _idlePortHitRadius;
    // Zooming *in* never tightens the radius below the painter's own default:
    // that default is also what the netlist means by "plugged in", and a port
    // you can't point at is worse than one that's easy to hit.
    return _wiringPortHitRadiusPx * math.max(1.0, 1 / context.scale);
  }

  /// The port under [canvasPosition], nearest wins.
  ///
  /// While a wire is in flight every node is asked, not just the topmost one
  /// whose bounds contain the point, because a component's bounds are mostly
  /// empty: an LED is a 56×56 box holding a thin lens and two legs. Letting it
  /// mask what's underneath made every breadboard hole in that box impossible
  /// to land a wire on as soon as a part was placed over it — the part didn't
  /// even have to be drawn there.
  ///
  /// When idle the search stops at the topmost node, which is what keeps a
  /// part sitting on a breadboard draggable: roughly half of a small part's
  /// bounds has a hole somewhere under it, and if those holes could be hovered
  /// through the part, pressing the part would start a wire from the board
  /// instead of picking the part up.
  PortLocation? _findPortAt(Offset canvasPosition) {
    final radius = _portHitRadius;
    final searchRadius = radius ?? kPortHitRadius;
    final searchBeneath = context.isWiring;
    PortLocation? nearest;
    var nearestDistance = double.infinity;

    // Reversed: topmost node first, so it wins ties against parts below it.
    for (final node in context.nodes.reversed) {
      if (!node.rect.inflate(searchRadius).contains(canvasPosition)) continue;
      // Bounds reached that the pointer is inside of, and we're not allowed to
      // see through it: whatever is under it stays hidden.
      // Only the part's own ink hides what's under it — see [checkHover].
      final blocks = !searchBeneath && node.covers(canvasPosition);
      final localPos = node.absoluteToLocal(canvasPosition);

      ComponentPort? port;
      if (node.part.definitionId != null) {
        final def = PartRegistry.getPart(node.part.definitionId!);
        if (def != null) {
          for (final pin in def.pins) {
            final distance = (pin.localOffset - localPos).distance;
            if (distance < searchRadius) {
              port = ComponentPort(id: pin.id, name: pin.name, localOffset: pin.localOffset);
              break;
            }
          }
        }
      }

      final painter = node.part.getPainter();
      if (port == null && painter is BreadboardPainter) {
        // Idle, the pointer has to be on a hole; with a wire in flight the
        // strip's whole row is a legitimate target again, because landing a
        // wire should be forgiving.
        port = painter.getPortAt(localPos, hitRadius: radius, preciseColumns: !context.isWiring);
      } else if (port == null && painter is PortProvider) {
        port = (painter! as PortProvider).getPortAt(localPos, hitRadius: radius);
      }
      if (port == null) {
        if (blocks) break;
        continue;
      }

      final distance = (port.localOffset - localPos).distance;
      if (distance < nearestDistance) {
        nearest = PortLocation(nodeKey: node.key, portId: port.id);
        nearestDistance = distance;
      }
      if (blocks) break;
    }

    return nearest;
  }

  void checkSelection() {
    // Convert screen coordinates to canvas coordinates
    final canvasPosition = context.screenToCanvasCoordinates(context.mouseLocalPosition);

    // 1. Priority Selection: Check if we are clicking a wire (even if it's over a node)
    final hitWire = context.checkWireInteraction(canvasPosition);
    if (hitWire && context.hoveredWireId != null) {
      context.selectWire(context.hoveredWireId);
      clearSelection();
      return;
    }

    // 2. Node Selection — the same area that hovers, so that what lights up
    // under the pointer is what a press picks up.
    ComponentInstance? found;
    for (final node in context.nodes.reversed) {
      if (node.covers(canvasPosition)) {
        found = node;
        break;
      }
    }

    if (found == null) {
      clearSelection();
      context.selectWire(null);
      return;
    }

    // Calculate the offset from the node's top-left corner to the click point
    context.dragStartOffset = canvasPosition - found.position;
    _dragAccumulator = Offset.zero;

    if (!context.selectedNodes.contains(found)) {
      context.selectedNodes = [found];
      // Clear wire selection ONLY when selecting a new node
      context.selectWire(null);
    }

    context.forceUpdate();
  }

  void moveSelection(Offset delta) {
    if (context.selectedNodes.isEmpty && context.selectedWireIds.isEmpty) return;

    final canvasDelta = delta / context.scale;
    _dragAccumulator += canvasDelta;

    var actualTranslation = Offset.zero;

    if (context.selectedNodes.isNotEmpty) {
      final referenceNode = context.selectedNodes.first;
      final otherNodes = context.nodes.where((n) => !context.selectedNodes.contains(n)).toList();
      final desiredPosition = referenceNode.position + _dragAccumulator;
      final snapped = SnapGuideHelper.snap(
        node: referenceNode,
        position: desiredPosition,
        otherNodes: otherNodes,
        snapToGrid: context.snapToGrid,
      );
      var newPosition = snapped.position;

      // Over a board, the board's holes win over the canvas grid: rail blocks
      // have blanks the grid knows nothing about, a rotated board's holes
      // needn't be on the grid at all, and a half board's rails are staggered
      // half a pitch. Measured from where the drag actually is, not from the
      // grid-snapped position — that would throw away which hole was meant.
      if (context.snapToGrid && context.selectedNodes.length == 1) {
        final toHole = BreadboardSnapHelper.holeAdjustment(
          node: referenceNode,
          position: desiredPosition,
          boards: otherNodes,
        );
        if (toHole != null) newPosition = desiredPosition + toHole;
      }
      final verticalGuidelines = snapped.verticalGuidelines;
      final horizontalGuidelines = snapped.horizontalGuidelines;

      actualTranslation = newPosition - referenceNode.position;

      if (actualTranslation == Offset.zero) {
        // If we didn't move, we still might need to clear or set guidelines if we just snapped in place
        context.updateState(
          verticalGuidelines: verticalGuidelines,
          horizontalGuidelines: horizontalGuidelines,
        );
        return;
      }

      _dragAccumulator -= actualTranslation;

      for (var i = 0; i < context.selectedNodes.length; i++) {
        final node = context.selectedNodes[i];
        final index = context.nodes.indexOf(node);
        if (index == -1) continue;

        final updatedNode = node.copyWith(position: node.position + actualTranslation);
        context.nodes[index] = updatedNode;
        context.selectedNodes[i] = updatedNode;
      }

      context.updateState(
        verticalGuidelines: verticalGuidelines,
        horizontalGuidelines: horizontalGuidelines,
      );
    } else {
      actualTranslation = _dragAccumulator;
      _dragAccumulator = Offset.zero;
      context.updateState(verticalGuidelines: [], horizontalGuidelines: []);
    }

    if (context.selectedWireIds.isNotEmpty && actualTranslation != Offset.zero) {
      for (final wireId in context.selectedWireIds) {
        final wireIndex = context.wires.indexWhere((w) => w.id == wireId);
        if (wireIndex != -1) {
          final wire = context.wires[wireIndex];
          if (wire.bendPoints.isNotEmpty) {
            final newBendPoints = wire.bendPoints.map((p) => p + actualTranslation).toList();
            context.wires[wireIndex] = wire.copyWith(bendPoints: newBendPoints);
          }
        }
      }
    }

    context.forceUpdate();
  }

  // Wiring Selection State
  String? hoveredWireId;
  List<String> selectedWireIds = [];

  void selectWire(String? id) {
    if (id == null) {
      selectedWireIds.clear();
      context.forceUpdate();
      return;
    }
    if (selectedWireIds.contains(id)) return;
    selectedWireIds = [id];
    context.forceUpdate();
  }
}
