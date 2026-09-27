import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_ui/widgets/color_select.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../controller/routing_utils.dart';
import 'canvas_commands.dart';
import 'canvas_context.dart';
import '../utils/canvas_geometry.dart';

/// Drives interactive wiring: starting a wire from a port, live-routing it to
/// the cursor, completing or cancelling it, and dragging existing wires' bend
/// points. Operates on canvas state via the [CanvasContext].
class WiringManager {
  final CanvasContext context;
  WiringManager(this.context);

  PortLocation? startPort;
  Offset? currentDragPosition;
  Color? currentWireColor; // null means Auto
  Color? activeDragColor; // Holds the assigned random or current color during dragging
  List<Offset> pendingBendPoints = [];
  var isMovingWireEndpoint = false;
  PortLocation? originalDetachedPort;

  /// The id of the wire whose end is currently in hand, so the wire that lands
  /// is the same wire that was picked up — same identity, and selected again
  /// when it settles. Moving an end is editing one wire, not deleting one and
  /// drawing another, even though that's how it's implemented underneath.
  String? movingWireId;

  void updateWireColor(Color? newColor) {
    currentWireColor = newColor;
    if (newColor != null && context.selectedWireIds.isNotEmpty) {
      final newWires = List<WireModel>.from(context.wires);
      var modified = false;
      for (final id in context.selectedWireIds) {
        final wireIndex = newWires.indexWhere((w) => w.id == id);
        if (wireIndex != -1) {
          final wire = newWires[wireIndex];
          newWires[wireIndex] = wire.copyWith(color: newColor);
          modified = true;
        }
      }
      if (modified) {
        context.updateState(wires: newWires);
      }
    }
    context.forceUpdate();
  }

  Color _getRandomColor() => colorsList[math.Random().nextInt(colorsList.length)];

  // State for dragging a bend point or segment
  String? draggingWireId;
  WireModel? originalDraggingWire;
  int? draggingBendPointIndex;
  int? draggingSegmentIndex; // Index in the full points list (including ports)
  var isDraggingSegment = false;
  // Set once an actual PointerMoveEvent repositions the grabbed/inserted
  // point (see updateDraggingBendPoint). Distinct from "the wire's
  // bendPoints differ from originalDraggingWire's", which is also true right
  // after toggleBendPointAt inserts a brand-new point on a segment click —
  // that fresh point sits exactly on the (now former) straight segment, so
  // simplify() would otherwise treat it as a redundant collinear point and
  // strip it back out before the user ever got to drag it anywhere.
  var _hasDraggedSinceGrab = false;

  bool get isWiring => startPort != null;
  bool get isDraggingBendPoint =>
      draggingWireId != null && (draggingBendPointIndex != null || isDraggingSegment);

  // Hit-test tolerances are defined in screen pixels and converted to
  // canvas-space units by dividing by the current zoom. Comparing raw canvas
  // distances against a fixed threshold made handles/segments effectively
  // unclickable when zoomed out (the threshold shrinks on screen along with
  // everything else) and overly generous when zoomed in.
  static const _handleHitRadiusPx = 15.0;
  static const _segmentHitRadiusPx = 12.0;
  double get _handleHitRadius => _handleHitRadiusPx / context.scale;
  double get _segmentHitRadius => _segmentHitRadiusPx / context.scale;

  /// Returns the wire ID that should be the target of interactive actions:
  /// prefers the hovered wire if it is also selected, otherwise falls back to
  /// the first selected wire.
  String? get _resolveActiveWireId =>
      context.hoveredWireId != null && context.selectedWireIds.contains(context.hoveredWireId)
      ? context.hoveredWireId
      : context.selectedWireIds.firstOrNull;

  void startWiring(
    PortLocation port,
    Offset initialPosition, {
    List<Offset>? bendPoints,
    bool isMovingExisting = false,
    PortLocation? originalDetachedPort,
    String? movingWireId,
  }) {
    context.selectedWireIds.clear();
    startPort = port;
    currentDragPosition = initialPosition;
    activeDragColor = currentWireColor ?? _getRandomColor();
    pendingBendPoints = bendPoints ?? [];
    isMovingWireEndpoint = isMovingExisting;
    this.originalDetachedPort = originalDetachedPort;
    this.movingWireId = movingWireId;
    context.forceUpdate();
  }

  void updateWiring(Offset position) {
    if (startPort == null) return;
    currentDragPosition = context.snapToGrid ? GridSystem.snapToHalfGridOffset(position) : position;
    context.forceUpdate();
  }

  void completeWiring(PortLocation endPort) {
    if (startPort == null) return;

    // Dropped on the port the wire's other end already occupies. A fresh wire
    // there would be a loop, so there's nothing to add — but an end being
    // *moved* was detached from the canvas when it was picked up, so simply
    // cancelling would take the whole wire with it. Put it back where it came
    // from instead: a drop that means nothing should cost nothing.
    if (startPort == endPort) {
      final restoreTo = originalDetachedPort;
      if (isMovingWireEndpoint && restoreTo != null && restoreTo != startPort) {
        completeWiring(restoreTo);
        return;
      }
      cancelWiring();
      return;
    }

    // A wire runs straight from port to port unless you bend it yourself.
    // Diagonal connections used to get an elbow baked in here, on the theory
    // that the canvas only draws orthogonal segments — but it draws whatever
    // points the wire has, and an invented corner is a bend nobody asked for
    // in a file nobody edited. Parts snap so their legs line up (see
    // `SnapGuideHelper`), which is what makes a run come out straight; where
    // it doesn't, a diagonal is the honest picture of what's connected.
    // A moved end keeps the wire's own id: it is the same wire, so anything
    // holding onto it (the selection, most of all) still means it afterwards.
    final movedId = movingWireId;
    final newWire = WireModel(
      id: movedId ?? WireModel.generateId(),
      start: startPort!,
      end: endPort,
      bendPoints: pendingBendPoints,
      color: activeDragColor ?? AppPalette.yellow,
    );

    context.executeCommand(AddWireCommand(newWire));
    cancelWiring();

    // Re-select it. Dragging an end is editing the wire you had selected, and
    // having it go blank the moment you touch it reads as "I lost it" — the
    // selection is also what keeps its handles on screen for the next drag.
    if (movedId != null) context.selectWire(movedId);
  }

  void cancelWiring() {
    startPort = null;
    currentDragPosition = null;
    activeDragColor = null;
    pendingBendPoints = [];
    isMovingWireEndpoint = false;
    originalDetachedPort = null;
    movingWireId = null;
    context.forceUpdate();
  }

  void removeWire(String id) {
    final wireIndex = context.wires.indexWhere((w) => w.id == id);
    if (wireIndex != -1) {
      final wire = context.wires[wireIndex];
      context.executeCommand(RemoveSelectionCommand(removedNodes: [], removedWires: [wire]));
    }
    if (context.hoveredWireId == id) context.hoveredWireId = null;
  }

  /// The endpoint of a *selected* wire within handle-grabbing range of
  /// [canvasPosition] — nearest one wins, and a bend handle strictly closer
  /// than every endpoint takes precedence (returns null so the bend gets the
  /// press).
  ///
  /// This is what makes a selected wire's visible end circles actually
  /// grabbable: they're drawn exactly like bend handles, so they must grab
  /// like them — with the handle's generous screen-px radius, not the tight
  /// idle port radius (4 canvas px, deliberately small so parts stay
  /// draggable). Without this, a press a few pixels off the end missed the
  /// port, fell through to the wire's segment, and read as "endpoint grab is
  /// broken" — but only while the wire was selected, because only then are
  /// the handles on screen inviting the press.
  PortLocation? selectedEndpointAt(Offset canvasPosition) {
    if (isWiring) return null;
    PortLocation? nearest;
    var nearestDistance = _handleHitRadius;
    for (final wire in context.wires) {
      if (!context.selectedWireIds.contains(wire.id)) continue;
      for (final end in [wire.start, wire.end]) {
        final pos = getPortPosition(end);
        if (pos == null) continue;
        final distance = (canvasPosition - pos).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = end;
        }
      }
    }
    if (nearest == null) return null;

    final bendDistance = selectedBendHandleDistance(canvasPosition);
    if (bendDistance != null && bendDistance < nearestDistance) return null;
    return nearest;
  }

  /// Whether [port] is where one of the *selected* wires ends — matched by
  /// position as well as identity, for the same reason [wireAt] is: a leg
  /// seated in a board hole is one spot with two names.
  bool isSelectedWireEndpoint(PortLocation port) {
    final selected = context.wires.where((w) => context.selectedWireIds.contains(w.id));
    for (final wire in selected) {
      if (wire.start == port || wire.end == port) return true;
    }
    final portPos = getPortPosition(port);
    if (portPos == null) return false;
    for (final wire in selected) {
      for (final end in [wire.start, wire.end]) {
        final endPos = getPortPosition(end);
        if (endPos != null && (endPos - portPos).distance < kPortHitRadius) return true;
      }
    }
    return false;
  }

  /// Distance from [canvasPosition] to the nearest bend-point handle of a
  /// selected wire, or null when none is within grabbing range
  /// ([_handleHitRadius]) — the handles the canvas is currently drawing for
  /// editing.
  double? selectedBendHandleDistance(Offset canvasPosition) {
    if (isWiring) return null;
    double? nearest;
    for (final wire in context.wires) {
      if (!context.selectedWireIds.contains(wire.id)) continue;
      for (final bend in wire.bendPoints) {
        final distance = (canvasPosition - bend).distance;
        if (distance < _handleHitRadius && (nearest == null || distance < nearest)) {
          nearest = distance;
        }
      }
    }
    return nearest;
  }

  bool checkWireInteraction(Offset canvasPosition) {
    if (isWiring) return false;

    // 1. Check handles first (priority)
    for (final wire in context.wires) {
      if (context.selectedWireIds.contains(wire.id)) {
        for (var i = 0; i < wire.bendPoints.length; i++) {
          if ((canvasPosition - wire.bendPoints[i]).distance < _handleHitRadius) {
            if (context.hoveredWireId != wire.id) {
              context.hoveredWireId = wire.id;
              context.forceUpdate();
            }
            return true;
          }
        }
      }
    }

    // 2. Check segments
    for (final wire in context.wires) {
      if (_isPointNearWire(canvasPosition, wire)) {
        if (context.hoveredWireId != wire.id) {
          context.hoveredWireId = wire.id;
          context.forceUpdate();
        }
        return true;
      }
    }

    if (context.hoveredWireId != null) {
      context.hoveredWireId = null;
      context.forceUpdate();
    }
    return false;
  }

  bool _isPointNearWire(Offset p, WireModel wire) {
    final startPos = getPortPosition(wire.start);
    final endPos = getPortPosition(wire.end);
    if (startPos == null || endPos == null) return false;

    final points = <Offset>[startPos, ...wire.bendPoints, endPos];
    for (var i = 0; i < points.length - 1; i++) {
      if (CanvasGeometry.distanceToSegment(p, points[i], points[i + 1]) < _segmentHitRadius) {
        return true;
      }
    }
    return false;
  }

  Offset? getPortPosition(PortLocation loc) => CanvasGeometry.getPortPosition(loc, context.nodes);

  /// The wire attached at [port] — and which of its two ends is there — or
  /// null if nothing is.
  ///
  /// Matched by *position*, not only by endpoint identity, because two ports
  /// can share a location: a leg seated in a breadboard hole is one spot with
  /// two names. A wire recorded against the hole (template files are wired to
  /// board holes) while idle hover resolves the same spot to the part's leg
  /// used to make this lookup miss — so grabbing the visible endpoint started
  /// a brand-new wire instead of picking the existing one up.
  ///
  /// Selected wires are searched first: when several wires meet at one port,
  /// the one the user selected is the one they mean to re-route.
  ({WireModel wire, bool atStart})? wireAt(PortLocation port) {
    ({WireModel wire, bool atStart})? matchIn(Iterable<WireModel> wires) {
      for (final wire in wires) {
        if (wire.start == port) return (wire: wire, atStart: true);
        if (wire.end == port) return (wire: wire, atStart: false);
      }
      final portPos = getPortPosition(port);
      if (portPos == null) return null;
      for (final wire in wires) {
        final startPos = getPortPosition(wire.start);
        if (startPos != null && (startPos - portPos).distance < kPortHitRadius) {
          return (wire: wire, atStart: true);
        }
        final endPos = getPortPosition(wire.end);
        if (endPos != null && (endPos - portPos).distance < kPortHitRadius) {
          return (wire: wire, atStart: false);
        }
      }
      return null;
    }

    final selected = context.wires.where((w) => context.selectedWireIds.contains(w.id));
    final rest = context.wires.where((w) => !context.selectedWireIds.contains(w.id));
    return matchIn(selected) ?? matchIn(rest);
  }

  void startDraggingBendPoint(Offset canvasPosition) {
    if (context.selectedWireIds.isEmpty) return;

    final wireId = _resolveActiveWireId;
    if (wireId == null) return;
    final wire = context.wires.firstWhere((w) => w.id == wireId);

    // Grab existing bend point handle
    for (var i = 0; i < wire.bendPoints.length; i++) {
      if ((canvasPosition - wire.bendPoints[i]).distance < _handleHitRadius) {
        draggingWireId = wire.id;
        originalDraggingWire = wire.copyWith();
        draggingBendPointIndex = i;
        isDraggingSegment = false;
        _hasDraggedSinceGrab = false;
        context.forceUpdate();
        return;
      }
    }
  }

  void toggleBendPointAt(Offset canvasPosition) {
    if (context.selectedWireIds.isEmpty) return;

    final wireId = _resolveActiveWireId;
    if (wireId == null) return;
    final wire = context.wires.firstWhere((w) => w.id == wireId);

    // 1. Check if double clicking on an EXISTING bend point to delete it
    for (var i = 0; i < wire.bendPoints.length; i++) {
      if ((canvasPosition - wire.bendPoints[i]).distance < _handleHitRadius) {
        final newBendPoints = List<Offset>.from(wire.bendPoints);
        newBendPoints.removeAt(i);
        final newWire = wire.copyWith(bendPoints: newBendPoints);
        context.executeCommand(UpdateWireCommand(wire.id, wire, newWire));
        return;
      }
    }

    final startPos = getPortPosition(wire.start);
    final endPos = getPortPosition(wire.end);
    if (startPos == null || endPos == null) return;

    final points = <Offset>[startPos, ...wire.bendPoints, endPos];
    for (var i = 0; i < points.length - 1; i++) {
      final hitSegment =
          CanvasGeometry.distanceToSegment(canvasPosition, points[i], points[i + 1]) <
          _segmentHitRadius;

      if (hitSegment) {
        final newPoint = context.snapToGrid
            ? GridSystem.snapToHalfGridOffset(canvasPosition)
            : canvasPosition;
        final newBendPoints = List<Offset>.from(wire.bendPoints);
        newBendPoints.insert(i, newPoint);

        final newWires = List<WireModel>.from(context.wires);
        final wireIdx = newWires.indexOf(wire);
        final updatedWire = wire.copyWith(bendPoints: newBendPoints);
        if (wireIdx != -1) {
          newWires[wireIdx] = updatedWire;
        }
        context.updateState(wires: newWires);

        draggingWireId = wire.id;
        originalDraggingWire = wire.copyWith(); // The wire BEFORE this new point was inserted
        draggingBendPointIndex = i;
        isDraggingSegment = false;
        _hasDraggedSinceGrab = false;
        context.forceUpdate();
        return;
      }
    }
  }

  void updateDraggingBendPoint(Offset canvasPosition) {
    if (draggingWireId == null || draggingBendPointIndex == null) return;
    _hasDraggedSinceGrab = true;

    final wireIndex = context.wires.indexWhere((w) => w.id == draggingWireId);
    if (wireIndex == -1) return;

    final wire = context.wires[wireIndex];
    final startPos = getPortPosition(wire.start);
    final endPos = getPortPosition(wire.end);
    if (startPos == null || endPos == null) return;

    final newPoint = context.snapToGrid
        ? GridSystem.snapToHalfGridOffset(canvasPosition)
        : canvasPosition;

    // Freeform handle drag: just move the point
    final points = List<Offset>.from(wire.bendPoints);
    points[draggingBendPointIndex!] = newPoint;
    final newWire = wire.copyWith(bendPoints: points);

    // We only execute a command when we stop dragging, otherwise we flood the undo stack.
    // For live dragging, we mutate directly.
    final newWires = List<WireModel>.from(context.wires);
    newWires[wireIndex] = newWire;
    context.updateState(wires: newWires);

    context.forceUpdate();
  }

  void stopDraggingBendPoint() {
    if (draggingWireId != null) {
      final wireIndex = context.wires.indexWhere((w) => w.id == draggingWireId);
      if (wireIndex != -1) {
        final wire = context.wires[wireIndex];
        // A plain click-and-release grabs the handle but never moves it — skip
        // the commit entirely in that case. Otherwise a collinear bend point
        // gets silently deleted on mere click-release (simplify treats it as
        // "redundant"), which both loses the point without the user ever
        // dragging it and swallows the very click a subsequent double-click
        // needs to see as "existing bend point here" to delete it on purpose.
        //
        // A point freshly inserted by toggleBendPointAt (clicking a segment)
        // also differs from originalDraggingWire even with zero drag — but
        // must still be committed, just without running it through
        // simplify(): the point sits exactly on the (former) straight
        // segment it was inserted into, so simplify would immediately
        // classify it as redundant/collinear and strip it right back out
        // before the user ever got to drag it anywhere.
        final structurallyChanged =
            originalDraggingWire == null || !_sameBendPoints(wire, originalDraggingWire!);

        if (_hasDraggedSinceGrab || structurallyChanged) {
          var finalWire = wire;

          if (_hasDraggedSinceGrab) {
            final startPos = getPortPosition(wire.start);
            final endPos = getPortPosition(wire.end);

            if (startPos != null && endPos != null) {
              // Manual cleanup: only simplify (remove redundant collinear/same points)
              final allPoints = <Offset>[startPos, ...wire.bendPoints, endPos];
              final simplifiedPoints = RoutingUtils.simplify(allPoints);
              if (simplifiedPoints.length >= 2) {
                final updatedBendPoints = simplifiedPoints.sublist(1, simplifiedPoints.length - 1);
                finalWire = wire.copyWith(bendPoints: updatedBendPoints);

                final newWires = List<WireModel>.from(context.wires);
                newWires[wireIndex] = finalWire;
                context.updateState(wires: newWires);
              }
            }
          }

          if (originalDraggingWire != null) {
            context.executeCommand(UpdateWireCommand(wire.id, originalDraggingWire!, finalWire));
          }
        }
      }
    }

    draggingWireId = null;
    originalDraggingWire = null;
    draggingBendPointIndex = null;
    draggingSegmentIndex = null;
    isDraggingSegment = false;
    _hasDraggedSinceGrab = false;
    context.forceUpdate();
  }

  bool _sameBendPoints(WireModel a, WireModel b) {
    if (a.bendPoints.length != b.bendPoints.length) return false;
    for (var i = 0; i < a.bendPoints.length; i++) {
      if (a.bendPoints[i] != b.bendPoints[i]) return false;
    }
    return true;
  }
}
