import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';

class CapacitorNode({@override final Size size = const Size(20.0, 20.0)}) extends PaintNode {
  static const _baseRadius = 10.0;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    final scaleX = bounds.width / (_baseRadius * 2);
    final scaleY = bounds.height / (_baseRadius * 2);
    final uniformScale = math.min(scaleX, scaleY);

    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(uniformScale);

    // Drop shadow
    paint.color = const Color(0x66000000);
    canvas.drawCircle(const Offset(0, 2.0), _baseRadius, paint);

    // Outer rim
    paint.color = const Color(0xFFB0B0B0);
    canvas.drawCircle(Offset.zero, _baseRadius, paint);

    // Inner surface
    paint.color = const Color(0xFFDEDEDE);
    const innerRadius = _baseRadius - 1.5;
    canvas.drawCircle(Offset.zero, innerRadius, paint);

    // Dark polarity mark
    paint.color = const Color(0xFF4A4A4A);
    final path = Path();

    const chordY = innerRadius * 0.5;
    final chordX = math.sqrt(innerRadius * innerRadius - chordY * chordY);

    path.moveTo(-chordX, chordY);
    path.lineTo(chordX, chordY);

    final rect = Rect.fromCircle(center: Offset.zero, radius: innerRadius);
    final startAngle = math.atan2(chordY, chordX);
    final sweepAngle = math.pi - 2 * startAngle;

    path.arcTo(rect, startAngle, sweepAngle, false);
    path.close();

    canvas.drawPath(path, paint);

    canvas.restore();
  }
}
