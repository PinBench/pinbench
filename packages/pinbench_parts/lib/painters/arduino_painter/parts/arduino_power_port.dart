import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';

class PowerPortNode extends PaintNode {
  @override
  final Size size;

  PowerPortNode({this.size = const Size(40.0, 30.0)});

  static const _baseOverhang = 8.0;
  static const _baseInnerWidth = 32.0;
  static const _basePortWidth = 40.0;
  static const _basePortHeight = 30.0;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    final scaleX = bounds.width / _basePortWidth;
    final scaleY = bounds.height / _basePortHeight;
    final uniformScale = math.min(scaleX, scaleY);

    const internalCenterX = (_baseInnerWidth - _baseOverhang) / 2;

    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(uniformScale);
    canvas.translate(-internalCenterX, 0);

    const collarColor = Color(0xFF2B2E31);
    const bodyColor = Color(0xFF383B3D);
    const shadowColor = Color(0xFF222426);
    const lineColor = Color(0xFF5A5D5F);

    const collarWidth = _baseOverhang + 6.0;
    paint.color = collarColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-_baseOverhang, -_basePortHeight / 2, collarWidth, _basePortHeight),
        const Radius.circular(2.0),
      ),
      paint,
    );

    const bodyStartX = 6.0;
    const bodyWidth = 24.0;
    const bodyHeight = 26.0;
    paint.color = bodyColor;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(bodyStartX, -bodyHeight / 2, bodyWidth, bodyHeight),
        topRight: const Radius.circular(3.0),
        bottomRight: const Radius.circular(3.0),
      ),
      paint,
    );

    paint.color = shadowColor;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(-_baseOverhang, _basePortHeight / 2 - 4.0, collarWidth, 4.0),
        bottomLeft: const Radius.circular(2.0),
        bottomRight: const Radius.circular(2.0),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(bodyStartX, bodyHeight / 2 - 4.0, bodyWidth, 4.0),
        bottomRight: const Radius.circular(3.0),
      ),
      paint,
    );

    const tabWidth = 2.0;
    const tabHeight = 16.0;
    paint.color = bodyColor;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(bodyStartX + bodyWidth, -tabHeight / 2, tabWidth, tabHeight),
        topRight: const Radius.circular(1.5),
        bottomRight: const Radius.circular(1.5),
      ),
      paint,
    );
    paint.color = shadowColor;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(bodyStartX + bodyWidth, tabHeight / 2 - 2.0, tabWidth, 2.0),
        bottomRight: const Radius.circular(1.5),
      ),
      paint,
    );

    paint.color = lineColor;
    canvas.drawRect(
      const Rect.fromLTWH(bodyStartX + bodyWidth - 3.0, -bodyHeight / 2, 1.5, bodyHeight),
      paint,
    );

    canvas.restore();
  }
}
