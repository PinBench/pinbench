import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../painting/paint_node.dart';
import '../arduino_painter.dart';
import '../../../painting/part_palette.dart';

class LogoNode({@override final Size size = const Size(150, 50)}) extends PaintNode {
  @override
  void paint(Canvas canvas, Offset offset) {
    final image = ArduinoPainter.image;

    if (image != null) {
      final paint = Paint()
        ..colorFilter = const ColorFilter.mode(PartPalette.white, BlendMode.srcIn);

      canvas.save();

      final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      canvas.translate(bounds.center.dx, bounds.center.dy);

      final scaleX = bounds.width / image.width;
      final scaleY = bounds.height / image.height;
      final uniformScale = math.min(scaleX, scaleY);

      canvas.scale(uniformScale);

      canvas.drawImage(image, Offset(-image.width / 2, -image.height / 2), paint);

      canvas.restore();
    } else {
      final logoStyle = GoogleFonts.jetBrainsMono(
        color: PartPalette.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      );
      final textPainter = TextPainter(
        text: TextSpan(text: 'ARDUINO', style: logoStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
      textPainter.paint(
        canvas,
        Offset(bounds.center.dx - textPainter.width / 2, bounds.center.dy - textPainter.height / 2),
      );
    }
  }
}
