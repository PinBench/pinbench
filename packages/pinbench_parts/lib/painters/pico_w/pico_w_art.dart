import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../painting/physical_scale.dart';

/// The Raspberry Pi Pico W's top side as flat-colour paths, laid out from its
/// mechanical drawing rather than traced from a Figma frame: the board is a
/// rectangle of known size with parts at known places, so the geometry is
/// easier to read as numbers than as exported curves.
///
/// Drawn lying down, micro-USB to the left, the way the Uno lies. That puts
/// pins 1–20 (GP0–GP15) along the bottom edge, left to right, and pins 40–21
/// (VBUS to GP16) along the top.
///
/// Positions are in millimetres from the board's top-left corner and placed
/// with [at]; every path is in the part's own canvas units.
abstract final class PicoWArt {
  /// The board: 51 × 21 mm.
  static const boardMm = Size(51, 21);

  /// One header pitch, 0.1".
  static const pitchMm = PhysicalScale.holePitchMm;

  /// Where the board's corner sits in the part, chosen so every pin lands on
  /// the connection lattice: pins at x = 20 + 16·i and y = 20 or 132.
  ///
  /// The part is a little bigger than the board for it — 344 × 152 against
  /// 321 × 132 — because the pins are 1.37 mm in from the ends and 1.61 mm in
  /// from the long edges, and no lattice-aligned rectangle hugs both. Keeping
  /// the board its true size and giving the margin to the part is the same
  /// trade the Uno made the other way, trimming its board to fit.
  static final origin = Offset(
    20 - (mm(boardMm.width) - 19 * 16) / 2,
    20 - (mm(boardMm.height) - 112) / 2,
  );

  static double mm(double millimetres) => millimetres * PhysicalScale.pxPerMm;

  /// A point [x], [y] millimetres from the board's top-left corner.
  static Offset at(double x, double y) => origin + Offset(mm(x), mm(y));

  static Rect _rect(double x, double y, double w, double h) => at(x, y) & Size(mm(w), mm(h));

  static Path _box(double x, double y, double w, double h) => Path()..addRect(_rect(x, y, w, h));

  static Path _rrect(double x, double y, double w, double h, double r) =>
      Path()..addRRect(RRect.fromRectAndRadius(_rect(x, y, w, h), Radius.circular(mm(r))));

  static Path _circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: at(x, y), radius: mm(r)));

  /// Centre of pin [index] along a row, 0 at the USB end, in millimetres.
  static double pinX(int index) => (boardMm.width - 19 * pitchMm) / 2 + index * pitchMm;

  /// The two rows' centres, in millimetres from the top edge.
  static const topRowY = 1.61;
  static const bottomRowY = 21 - 1.61;

  static final board = [_rrect(0, 0, 51, 21, 1)];

  /// The copper-free strip under the antenna at the far end.
  static final antennaKeepOut = [_box(46.1, 5.6, 4.4, 9.8)];

  /// Castellated pads: a ring round each hole running out to the board edge,
  /// plus the three debug pads.
  static final pads = [
    for (var i = 0; i < 20; i++) ...[
      _circle(pinX(i), topRowY, 0.85),
      _box(pinX(i) - 0.85, 0, 1.7, topRowY),
      _circle(pinX(i), bottomRowY, 0.85),
      _box(pinX(i) - 0.85, bottomRowY, 1.7, 21 - bottomRowY),
    ],
    for (final y in const [8.5, 10.5, 12.5]) _circle(31.0, y, 0.55),
  ];

  /// Bare, unplated, and under the end pins' labels, which print over them as
  /// the silkscreen would if it ran there.
  static const _mountingHoles = [(2.0, 4.8), (2.0, 16.2), (49.0, 4.8), (49.0, 16.2)];

  static final holes = [
    for (var i = 0; i < 20; i++) ...[
      _circle(pinX(i), topRowY, 0.5),
      _circle(pinX(i), bottomRowY, 0.5),
    ],
    for (final (x, y) in _mountingHoles) _circle(x, y, 1.05),
  ];

  /// The printed inverted-F antenna, a meander in the keep-out strip.
  static final antenna = () {
    const x0 = 46.6;
    const x1 = 50.0;
    const top = 6.2;
    const step = 1.7;
    const w = 0.35;
    final paths = <Path>[];
    var y = top;
    for (var i = 0; i < 6; i++) {
      paths.add(_box(x0, y, x1 - x0, w));
      final side = i.isEven ? x1 - w : x0;
      if (i < 5) paths.add(_box(side, y, w, step));
      y += step;
    }
    return paths;
  }();

  static final usbShell = [_rrect(-1.3, 6.75, 5.7, 7.5, 0.4)];
  static final usbPlate = [
    _rrect(-0.6, 7.6, 4.3, 5.8, 0.3),
    for (final y in const [8.6, 12.0]) _box(3.6, y, 0.9, 0.5),
  ];

  /// The RP2040, the QSPI flash, the switching regulator's inductor and its
  /// two neighbours: everything printed black.
  static final chips = [
    _rrect(20.0, 7.0, 7.0, 7.0, 0.3),
    _rrect(12.2, 10.6, 4.4, 3.4, 0.3),
    _rrect(11.5, 6.2, 3.0, 3.0, 0.3),
    _rrect(15.2, 6.6, 1.6, 2.4, 0.2),
    _rrect(17.4, 7.0, 1.2, 1.8, 0.2),
  ];

  /// The flash's and the regulator's pins, and the crystal's can.
  static final metal = [
    for (var i = 0; i < 4; i++) ...[
      _box(12.6 + i * 1.1, 10.1, 0.4, 0.5),
      _box(12.6 + i * 1.1, 14.0, 0.4, 0.5),
    ],
    _rrect(17.6, 10.6, 2.0, 3.2, 0.5),
  ];

  /// BOOTSEL: a square switch body under a round cap.
  static final buttonBody = [_rrect(6.5, 9.0, 3.6, 3.6, 0.3)];
  static final buttonCap = [_circle(8.3, 10.8, 1.1)];

  /// The CYW43439 radio's can, its rim, then its lid.
  static final shield = [_rrect(33.0, 5.8, 12.6, 9.4, 0.5)];
  static final shieldLid = [_rrect(33.5, 6.3, 11.6, 8.4, 0.3)];

  /// The on-board LED's package, unlit.
  static final led = [_rrect(5.4, 13.6, 1.6, 0.9, 0.15)];
  static Offset get ledCentre => at(6.2, 14.05);

  /// Where a pin's label is printed: just inside its pad, reading up the board.
  static Offset labelCentre(int index, {required bool top}) =>
      at(pinX(index), top ? topRowY + 2.75 : bottomRowY - 2.75);

  /// Text reading up the board, as a rotated label does.
  static const labelAngle = -math.pi / 2;
}
