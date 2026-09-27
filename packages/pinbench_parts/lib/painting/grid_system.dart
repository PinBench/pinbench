import 'dart:ui';

import 'package:pinbench_pdl/pinbench_pdl.dart';

class GridSystem {
  /// One grid cell. Connection points (breadboard holes, component legs,
  /// Arduino pins) sit 2 cells apart — the "hole pitch" ([pitch] = 16px) —
  /// and every one of them is ≡ [cellCenter] mod [pitch] in the part's own
  /// geometry. Node positions snap in [snapStep] (one cell) increments, so
  /// ANY two grid-snapped parts have their connection points on the same
  /// [cellSize] sub-lattice: a hole over a pin is exactly over it, and the
  /// wire between them is perfectly vertical.
  ///
  /// The numbers are the `.pdl` format's ([PdlUnits]): a part file and the
  /// canvas have to agree on where a pin is.
  static const cellSize = PdlUnits.cellSize;
  static const cellCenter = PdlUnits.cellCenter;
  static const pitch = PdlUnits.pitch;

  /// The step a dragged part moves in: one grid cell — the finest level the
  /// grid actually draws — so a part can stop on every visible line, not just
  /// every other one.
  ///
  /// This is half a hole pitch, so ports of grid-snapped parts live on the
  /// ≡ [cellCenter] mod [cellSize] sub-lattice: any two snapped parts still
  /// agree mod [cellSize], which is what keeps a wire between their legs
  /// perfectly straight. A part CAN now rest half a pitch off the breadboard
  /// hole lattice — that's fine on open canvas, and over a board it doesn't
  /// decide anything: `BreadboardSnapHelper.holeAdjustment` runs after the
  /// grid on both the drop and drag paths and seats the leg in the actual
  /// nearest hole (which the grid alone never fully could anyway — rail
  /// blanks, rotated boards, staggered half-board rails).
  static const snapStep = cellSize;

  static double snap(double value) => (value / snapStep).round() * snapStep;

  static double snapToCenter(double value) => (value / cellSize).floor() * cellSize + cellCenter;

  static Offset snapOffset(Offset offset) => Offset(snap(offset.dx), snap(offset.dy));

  static Offset snapToCenterOffset(Offset offset) =>
      Offset(snapToCenter(offset.dx), snapToCenter(offset.dy));

  /// Snaps a *connection point* — a leg, a pin, a hole — to the nearest point
  /// of the connection lattice (≡ [cellCenter] mod [snapStep]).
  ///
  /// [snap] is its counterpart for node *positions*, and the two only agree
  /// while a part is unrotated: rotating a part changes the offset from its
  /// bounding box to its legs by whatever its own size happens to be, so
  /// quantizing the box no longer puts the legs anywhere in particular. Snap
  /// the port and derive the position from it — see `SnapGuideHelper`.
  static double snapConnectionPoint(double value) =>
      ((value - cellCenter) / snapStep).round() * snapStep + cellCenter;

  static Offset snapConnectionPointOffset(Offset offset) =>
      Offset(snapConnectionPoint(offset.dx), snapConnectionPoint(offset.dy));

  static double snapToHalfGrid(double value) => (value / cellCenter).round() * cellCenter;

  static Offset snapToHalfGridOffset(Offset offset) =>
      Offset(snapToHalfGrid(offset.dx), snapToHalfGrid(offset.dy));
}
