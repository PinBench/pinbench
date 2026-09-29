import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';
import '../../../painting/part_palette.dart';

class BreadboardUtils {
  static const backgroundColor = PartPalette.grey300;
  static const holeBevelLight = PartPalette.grey200;
  static const holeBevelDark = PartPalette.grey400;
  static const holeCenterDark = PartPalette.grey800;

  /// Centre notch: a flat band a shade darker than the board, no bevel — the
  /// channel reads as a gap because the surface changes, not because it's
  /// drawn as an object.
  static const notchFloorColor = PartPalette.grey400;

  static void drawHole(
    Canvas canvas,
    Offset offset,
    Paint paint, {
    bool isHighlighted = false,
    Color highlightColor = PartPalette.green,
  }) {
    const dotRadiusInner = 3.0;
    const dotRadiusOuter = 5.0;

    const halfCircleSweep = math.pi;
    const topHalfStart = math.pi;
    const bottomHalfStart = 0.0;

    if (isHighlighted) {
      paint.color = highlightColor;
      canvas.drawCircle(offset, dotRadiusOuter + 2, paint);
    }

    paint.color = holeBevelLight;
    canvas.drawArc(
      Rect.fromCircle(center: offset, radius: dotRadiusOuter),
      topHalfStart,
      halfCircleSweep,
      true,
      paint,
    );

    paint.color = holeBevelDark;
    canvas.drawArc(
      Rect.fromCircle(center: offset, radius: dotRadiusOuter),
      bottomHalfStart,
      halfCircleSweep,
      true,
      paint,
    );

    paint.color = holeCenterDark;
    canvas.drawCircle(offset, dotRadiusInner, paint);
  }

  static void drawLabel(Canvas canvas, String text, double x, double y, double fontSize) {
    canvas.save();
    canvas.translate(x, y);

    final style = GoogleFonts.jetBrainsMono(color: PartPalette.black, fontSize: fontSize);

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    textPainter.dispose();

    canvas.restore();
  }
}
