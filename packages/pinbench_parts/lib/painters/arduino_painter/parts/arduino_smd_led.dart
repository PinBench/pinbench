import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../painting/paint_node.dart';
import '../../../painting/part_palette.dart';

class SmdLedNode extends PaintNode {
  final String label;
  final Color ledColor;
  final bool labelOnRight;
  @override
  final Size size;

  SmdLedNode({
    required this.label,
    this.ledColor = const Color(0xFFF9F1A5),
    this.labelOnRight = false,
    this.size = const Size(14.0, 8.0),
  });

  static const _baseLedWidth = 10.0;
  static const _baseLedHeight = 4.0;
  static const _basePadWidth = 2.0;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    canvas.translate(bounds.center.dx, bounds.center.dy);

    final scaleX = bounds.width / _baseLedWidth;
    final scaleY = bounds.height / _baseLedHeight;
    final uniformScale = math.min(scaleX, scaleY);
    canvas.scale(uniformScale);

    // Draw main body
    paint.color = ledColor;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: _baseLedWidth, height: _baseLedHeight),
      paint,
    );

    // Draw pads
    paint.color = const Color(0xFFCCBC82);
    canvas.drawRect(
      const Rect.fromLTWH(-_baseLedWidth / 2, -_baseLedHeight / 2, _basePadWidth, _baseLedHeight),
      paint,
    );
    canvas.drawRect(
      const Rect.fromLTWH(
        _baseLedWidth / 2 - _basePadWidth,
        -_baseLedHeight / 2,
        _basePadWidth,
        _baseLedHeight,
      ),
      paint,
    );

    if (label.isEmpty) {
      canvas.restore();
      return;
    }

    final labelStyle = GoogleFonts.jetBrainsMono(
      color: PartPalette.white,
      fontSize: 4,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    const gap = 2;
    if (labelOnRight) {
      textPainter.paint(canvas, Offset(_baseLedWidth / 2 + gap, -textPainter.height / 2));
    } else {
      textPainter.paint(
        canvas,
        Offset(-_baseLedWidth / 2 - gap - textPainter.width, -textPainter.height / 2),
      );
    }

    canvas.restore();
  }
}
