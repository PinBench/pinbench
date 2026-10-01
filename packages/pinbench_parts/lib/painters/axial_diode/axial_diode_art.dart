// Generated: vector paths exported from the PinBench Parts Figma file by
// the Flutter Da Vinci plugin, one layer per colour, each shifted to where it
// sits in the part's frame. Redraw the part there and regenerate this file
// rather than editing the coordinates by hand.

import 'dart:ui';

import '../../painting/path_art.dart';

/// The artwork `AxialDiodePainter` draws.
abstract final class AxialDiodeArt {
  /// The leads, one wire through the body.
  static final leads = PathArtPainter.layer(const Offset(18.3729, 4), [
    Path()
      ..moveTo(0, 1.63)
      ..cubicTo(0, 0.73, 0.73, 0, 1.63, 0)
      ..cubicTo(2.53, 0, 3.25, 0.73, 3.25, 1.63)
      ..lineTo(3.25, 62.37)
      ..cubicTo(3.25, 63.27, 2.53, 64, 1.63, 64)
      ..cubicTo(0.73, 64, 0, 63.27, 0, 62.37)
      ..lineTo(0, 1.63)
      ..close(),
  ]);

  /// The moulded body of a DO-41 rectifier or Schottky.
  static final body = PathArtPainter.layer(const Offset(12.7322, 17.017), [
    Path()
      ..moveTo(0, 1.08)
      ..cubicTo(0, 0.49, 0.49, 0, 1.08, 0)
      ..lineTo(13.45, 0)
      ..cubicTo(14.05, 0, 14.54, 0.49, 14.54, 1.08)
      ..lineTo(14.54, 36.88)
      ..cubicTo(14.54, 37.48, 14.05, 37.97, 13.45, 37.97)
      ..lineTo(1.08, 37.97)
      ..cubicTo(0.49, 37.97, 0, 37.48, 0, 36.88)
      ..lineTo(0, 1.08)
      ..close(),
  ]);

  /// The cathode band, at the end nearer the cathode pin — the same place on
  /// every kind, in each kind's colour.
  static final cathodeBand = PathArtPainter.layer(const Offset(12.7322, 44.3525), [
    Path()
      ..moveTo(0, 0)
      ..lineTo(14.54, 0)
      ..lineTo(14.54, 3.47)
      ..lineTo(0, 3.47)
      ..lineTo(0, 0)
      ..close(),
  ]);

  /// The 1N4148's clear glass envelope, the leads showing through it.
  static final glass = PathArtPainter.layer(const Offset(12.7322, 17.017), [
    Path()
      ..moveTo(0, 1.08)
      ..cubicTo(0, 0.48, 0.48, 0, 1.08, 0)
      ..lineTo(13.46, 0)
      ..cubicTo(14.05, 0, 14.54, 0.48, 14.54, 1.08)
      ..lineTo(14.54, 36.89)
      ..cubicTo(14.54, 37.48, 14.05, 37.97, 13.46, 37.97)
      ..lineTo(1.08, 37.97)
      ..cubicTo(0.48, 37.97, 0, 37.48, 0, 36.89)
      ..lineTo(0, 1.08)
      ..close(),
  ]);

  /// The orange-coated die inside the glass, short of both ends.
  static final glassCore = PathArtPainter.layer(const Offset(13.9322, 20.217), [
    Path()
      ..moveTo(0, 0.8)
      ..cubicTo(0, 0.36, 0.36, 0, 0.8, 0)
      ..lineTo(11.34, 0)
      ..cubicTo(11.78, 0, 12.14, 0.36, 12.14, 0.8)
      ..lineTo(12.14, 30.77)
      ..cubicTo(12.14, 31.21, 11.78, 31.57, 11.34, 31.57)
      ..lineTo(0.8, 31.57)
      ..cubicTo(0.36, 31.57, 0, 31.21, 0, 30.77)
      ..lineTo(0, 0.8)
      ..close(),
  ]);
}
