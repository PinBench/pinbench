import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painting/grid_system.dart';

/// Snaps a dragged part onto the holes of the breadboard under it.
///
/// The connection lattice gets a part *close* — see `SnapGuideHelper` — but it
/// is a canvas-wide grid, and there are two things it can't express:
///
///  * Power rails are punched in blocks of five with a blank row of moulding
///    between blocks, so one lattice row in six is not a hole at all.
///  * A rotated board's holes need not sit on the lattice. A half breadboard is
///    a real 51.5 mm wide, which is 324.41 px — not a whole number of hole
///    pitches. Turned a half or three-quarter turn, that leftover 3.59 px goes
///    into every hole position on it, and no grid-snapped part can reach one.
///
/// So this asks the board itself where its nearest hole is and puts the leg
/// exactly there, whatever the board's rotation. It's the board that decides,
/// not the grid — which is also why it needs no special case for rails.
abstract final class BreadboardSnapHelper {
  /// How far a leg may be from a hole and still be pulled into it. A little
  /// over one hole pitch, so that a leg on the blank moulding between two rail
  /// blocks — exactly one pitch from the nearest hole — is still reached.
  static const _reach = GridSystem.pitch * 1.1;

  /// The nudge that puts one of [node]'s legs exactly into a hole of whichever
  /// board in [boards] it's over — or null if it's over none, which is the
  /// caller's cue to fall back to the canvas grid. A zero [Offset] means it's
  /// over a board and already seated, which is not the same thing.
  ///
  /// [position] should be where the *pointer* wants the part, not a
  /// grid-snapped position: quantizing first throws away which hole was being
  /// aimed at. On a half board's rails that matters — their rows are staggered
  /// half a pitch, so every grid position is an exact tie between two of them.
  ///
  /// Aligning one leg aligns them all whenever the part and the board agree on
  /// a quarter turn, because the holes and the part's own legs are then the
  /// same rigid lattice. When they don't (a part at 45°, or a board at 45°),
  /// one leg in a hole is the best there is.
  static Offset? holeAdjustment({
    required ComponentInstance node,
    required Offset position,
    required List<ComponentInstance> boards,
  }) {
    final ports = node.ports;
    if (ports.isEmpty) return null;

    Offset? best;
    var bestDistance = double.infinity;

    for (final board in boards) {
      if (identical(board, node) || board.key == node.key) continue;
      final boardPainter = board.part.getPainter();
      if (boardPainter is! BreadboardPainter) continue;

      for (final port in ports) {
        final portOffset = node.getPortOffset(port.id);
        if (portOffset == null) continue;

        final legCanvas = position + portOffset;
        final hole = boardPainter.getPortAt(board.absoluteToLocal(legCanvas), hitRadius: _reach);
        if (hole == null) continue;

        // Back out through the board's own transform rather than assuming the
        // hole's local offset is also its canvas offset — that assumption is
        // exactly what breaks on a rotated board.
        final holeOffset = board.getPortOffset(hole.id);
        if (holeOffset == null) continue;
        final adjustment = board.position + holeOffset - legCanvas;

        // Legs can straddle two boards, and a part has several legs: take the
        // smallest move that lands one of them.
        final distance = adjustment.distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = adjustment;
        }
      }
    }
    return best;
  }
}
