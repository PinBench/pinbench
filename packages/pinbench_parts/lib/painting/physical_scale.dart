import 'dart:ui';

import 'package:pinbench_pdl/pinbench_pdl.dart';

import 'grid_system.dart';

/// Real-world sizing for component painters.
///
/// The canvas already has a physical scale baked in: every connection point
/// sits on the [GridSystem] lattice whose pitch is one breadboard hole, and a
/// breadboard hole pitch is 0.1" = [holePitchMm] in the real world. So
/// [GridSystem.pitch] px ≡ 2.54 mm, which fixes [pxPerMm] for everything else.
///
/// Painters declare their bodies in millimetres (see the `*Mm` constants in
/// each one) and convert with [pxPerMm] / [mm], so a part is drawn at the size
/// it really is next to the holes its legs drop into.
///
/// Note the split between *body* and *legs*: bodies are exact real-world
/// sizes (fractional px is fine — nothing snaps to them), while leg/port
/// offsets must stay on the 16 px connection lattice, so lead spacing is
/// always a whole number of hole pitches (2.54 mm each). Where a real part's
/// lead spacing isn't a multiple of 0.1", it is drawn at the nearest pitch —
/// which is what the physical part is bent to when it goes into a breadboard
/// anyway.
class PhysicalScale {
  const PhysicalScale._();

  /// Breadboard / DIP hole pitch: 0.1".
  static const holePitchMm = PdlUnits.holePitchMm;

  /// Canvas pixels per millimetre (16 px per 2.54 mm ≈ 6.3 px/mm).
  ///
  /// Kept as a `const` so painters can size themselves in `const` expressions:
  /// `static const bodyWidth = bodyWidthMm * PhysicalScale.pxPerMm;`
  static const pxPerMm = PdlUnits.pxPerMm;

  /// [millimetres] in canvas pixels.
  static double mm(double millimetres) => millimetres * pxPerMm;

  /// Canvas pixels back to millimetres — handy in tests and readouts.
  static double toMm(double pixels) => pixels / pxPerMm;

  static Size mmSize(double widthMm, double heightMm) => Size(mm(widthMm), mm(heightMm));
}
