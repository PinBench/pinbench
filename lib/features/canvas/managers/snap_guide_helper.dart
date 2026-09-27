import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painting/grid_system.dart';

/// Result of [SnapGuideHelper.snap]: the resolved position plus alignment
/// guideline coordinates to draw.
typedef SnapResult = ({
  Offset position,
  List<double> verticalGuidelines,
  List<double> horizontalGuidelines,
});

/// Snap-to-grid and smart alignment-to-other-nodes for a dragged node
/// position. Extracted from `SelectionManager.moveSelection` — a plain
/// helper, not a `*Manager` (that suffix is reserved for the 3 collaborators
/// `CanvasController` composes).
abstract final class SnapGuideHelper {
  /// How close an edge/center has to be to another node's edge/center before
  /// the drag pulls them into line. Deliberately under half the grid step
  /// ([GridSystem.snapStep] / 2): two grid-snapped parts are either already in
  /// line (delta 0 — guide shows, nothing moves) or a whole step apart (no
  /// match), so smart alignment can only ever nudge a part off the grid to
  /// meet something that is itself off the grid — it never fights the grid
  /// over a part that could sit on it. The old 10px threshold was wider than
  /// a grid step, so alignment routinely overrode the grid snap entirely.
  static const _alignmentThreshold = GridSystem.snapStep / 2;

  /// Where [node] should sit if it's to be placed at [position] and land on
  /// the connection lattice.
  ///
  /// Snapping the node's *position* (its bounding-box corner) to whole pitches
  /// only puts the legs on the lattice while the part is unrotated. Rotating
  /// changes the offset from the box to the legs by whatever the part's own
  /// width and height happen to be — a 5mm LED is 56×56, so at 90° that offset
  /// moves by half a pitch — and quantizing the box then guarantees nothing.
  /// So the *port* is what gets snapped, and the position follows from it.
  ///
  /// At 45° there is nothing to be done: no rotation that isn't a multiple of
  /// 90° maps a square lattice onto itself, so only the reference leg can be
  /// in a hole. Aligning that one is still better than aligning neither.
  ///
  /// Parts with no listable ports (the breadboard, whose holes are found by
  /// hit-testing) fall back to snapping the position, which is correct for
  /// them: their holes are a whole number of pitches from their own corner.
  static Offset snapNodeToLattice(ComponentInstance node, Offset position) {
    final reference = node.ports.isEmpty ? null : node.getPortOffset(node.ports.first.id);
    if (reference == null) return GridSystem.snapOffset(position);
    return GridSystem.snapConnectionPointOffset(position + reference) - reference;
  }

  /// Snaps [position] to the grid (if [snapToGrid]), then Figma-style to the
  /// nearest edge/center alignment against [otherNodes], then leg-to-leg —
  /// collecting at most one guideline per axis, at the coordinate the part
  /// actually ended up aligned to.
  static SnapResult snap({
    required ComponentInstance node,
    required Offset position,
    required List<ComponentInstance> otherNodes,
    required bool snapToGrid,
  }) {
    var newPosition = position;

    if (snapToGrid) {
      newPosition = snapNodeToLattice(node, newPosition);
    }

    final box = _alignBounds(node, newPosition, otherNodes);
    newPosition = box.position;

    // Legs last, because lining up two parts' legs is what actually makes the
    // wire between them come out straight — and that beats lining up the boxes
    // those legs happen to sit in. It can pull the part off the grid by a few
    // pixels; a wire you can see is vertical is worth more than a round number.
    // When it moves an axis, its guide replaces the box guide on that axis:
    // the box coordinate no longer matches where the part is, and a line at a
    // place nothing aligns to is exactly the "random guides" this replaced.
    final legs = _alignLegs(node, newPosition, otherNodes);
    newPosition = legs.position;
    final guideX = legs.guideX ?? box.guideX;
    final guideY = legs.guideY ?? box.guideY;

    return (position: newPosition, verticalGuidelines: [?guideX], horizontalGuidelines: [?guideY]);
  }

  /// Figma-style smart alignment: the dragged node's bounding-box edges and
  /// centers against every other node's, nearest match per axis wins, within
  /// [_alignmentThreshold].
  ///
  /// This replaces aligning raw `position`s (top-left corners): two parts of
  /// different sizes with equal corners don't LOOK aligned, so those guides
  /// read as lines drawn at random. Edges and centers are the things the eye
  /// actually checks. One best candidate per axis also means one guide per
  /// axis, instead of a line for every node that happened to fall inside the
  /// threshold while the loop overwrote its own result.
  static ({Offset position, double? guideX, double? guideY}) _alignBounds(
    ComponentInstance node,
    Offset position,
    List<ComponentInstance> otherNodes,
  ) {
    final bounds = position & node.currentSize;
    final myXs = [bounds.left, bounds.center.dx, bounds.right];
    final myYs = [bounds.top, bounds.center.dy, bounds.bottom];

    double? bestDx;
    double? bestDy;
    double? guideX;
    double? guideY;

    for (final other in otherNodes) {
      final o = other.rect;
      for (final target in [o.left, o.center.dx, o.right]) {
        for (final mine in myXs) {
          final dx = target - mine;
          if (dx.abs() < _alignmentThreshold && (bestDx == null || dx.abs() < bestDx.abs())) {
            bestDx = dx;
            guideX = target;
          }
        }
      }
      for (final target in [o.top, o.center.dy, o.bottom]) {
        for (final mine in myYs) {
          final dy = target - mine;
          if (dy.abs() < _alignmentThreshold && (bestDy == null || dy.abs() < bestDy.abs())) {
            bestDy = dy;
            guideY = target;
          }
        }
      }
    }

    return (position: position.translate(bestDx ?? 0, bestDy ?? 0), guideX: guideX, guideY: guideY);
  }

  /// How close two legs have to be, on an axis, before the drag lines them up
  /// exactly.
  ///
  /// A little over half the grid step, which is all it needs: no target can
  /// be further than half a step from the nearest grid stop, so from that
  /// stop every off-grid leg — a template part at an arbitrary x, a turned
  /// board's holes 3.59px off the lattice — is inside this reach. Still under
  /// a full step, so moving one grid cell over is a deliberate act rather
  /// than a fight with the snap; the old `pitch * 0.6` (9.6px) was wider than
  /// today's 8px step and made exactly that fight.
  static const _legAlignmentThreshold = GridSystem.snapStep * 0.6;

  /// Nudges [position] so one of [node]'s legs lines up exactly with a leg of
  /// some other part, on either axis, and reports where to draw the guide.
  ///
  /// This is what makes a wire perfectly vertical: the wire runs port to port,
  /// so the ports are what have to agree, and lining up bounding boxes only
  /// does that by luck.
  ///
  /// A breadboard doesn't list its holes — they're found by hit-testing — so
  /// it names the ones nearest each leg instead
  /// ([BreadboardPainter.nearestHoles]).
  /// It has to take part even though `BreadboardSnapHelper` already seats parts
  /// that sit *on* a board: a part hovering above one, wired down into it, is
  /// over no hole at all, and without this its legs stay on the canvas grid
  /// while the board's holes are wherever the board happens to be.
  static ({Offset position, double? guideX, double? guideY}) _alignLegs(
    ComponentInstance node,
    Offset position,
    List<ComponentInstance> otherNodes,
  ) {
    final legs = <Offset>[
      for (final port in node.ports)
        if (node.getPortOffset(port.id) case final offset?) position + offset,
    ];
    if (legs.isEmpty) return (position: position, guideX: null, guideY: null);

    double? bestDx;
    double? bestDy;
    double? guideX;
    double? guideY;

    for (final other in otherNodes) {
      for (final leg in legs) {
        for (final target in _targetsNear(other, leg)) {
          final dx = target.dx - leg.dx;
          if (dx.abs() < _legAlignmentThreshold && (bestDx == null || dx.abs() < bestDx.abs())) {
            bestDx = dx;
            guideX = target.dx;
          }
          final dy = target.dy - leg.dy;
          if (dy.abs() < _legAlignmentThreshold && (bestDy == null || dy.abs() < bestDy.abs())) {
            bestDy = dy;
            guideY = target.dy;
          }
        }
      }
    }

    return (position: position.translate(bestDx ?? 0, bestDy ?? 0), guideX: guideX, guideY: guideY);
  }

  /// The connection points of [other] worth lining [leg] up with: its ports,
  /// or — for a board, which has none to list — the single hole nearest the
  /// leg, which is the only one that could line up anyway.
  static Iterable<Offset> _targetsNear(ComponentInstance other, Offset leg) sync* {
    final ports = other.ports;
    if (ports.isNotEmpty) {
      for (final port in ports) {
        final offset = other.getPortOffset(port.id);
        if (offset != null) yield other.position + offset;
      }
      return;
    }

    final painter = other.part.getPainter();
    if (painter is! BreadboardPainter) return;
    for (final hole in painter.nearestHoles(other.absoluteToLocal(leg))) {
      yield other.position + other.localToNodeOffset(hole);
    }
  }
}
