import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';
import '../../../painting/part_palette.dart';

class ChipNode extends PaintNode {
  @override
  final Size size;

  ChipNode({this.size = const Size(100.0, 20.0)});

  static const _width = 100.0;
  static const _height = 20.0;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    canvas.translate(bounds.center.dx, bounds.center.dy);

    final scaleX = bounds.width / _width;
    final scaleY = bounds.height / _height;
    final uniformScale = math.min(scaleX, scaleY);
    canvas.scale(uniformScale);

    darwBody(canvas, paint);
    drawPins(canvas, paint);
    drawMainChip(canvas, paint);
    drawCircles(canvas, paint);

    canvas.restore();
  }

  void darwBody(Canvas canvas, Paint paint) {
    paint.color = PartPalette.grey900;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: _width, height: _height),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  void drawMainChip(Canvas canvas, Paint paint) {
    paint.color = PartPalette.grey800;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: _width - 3, height: 14),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  void drawCircles(Canvas canvas, Paint paint) {
    const dx = 35.0;
    const radius = 2.5;

    paint.color = PartPalette.grey900;

    canvas.drawCircle(const Offset(-dx, 0), radius, paint);
    canvas.drawCircle(const Offset(dx, 0), radius, paint);
  }

  void drawPins(Canvas canvas, Paint paint) {
    const pinsCount = 14;
    const pinOffset = 6.0;

    const gaps = 6.75;
    const pinWidth = 4.0;
    const pinHeight = 4.0;

    const radius = Radius.circular(1);

    paint.color = PartPalette.grey400;

    const startX = -(pinsCount - 1) * gaps / 2;

    for (var i = 0; i < pinsCount; i++) {
      final px = startX + i * gaps;
      // Top pin
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(px, -pinOffset), width: pinWidth, height: pinHeight),
          radius,
        ),
        paint,
      );
      // Bottom pin
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(px, pinOffset), width: pinWidth, height: pinHeight),
          radius,
        ),
        paint,
      );
    }
  }
}
