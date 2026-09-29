import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';

class UsbPortNode({@override final Size size = const Size(40.0, 33.6)}) extends PaintNode {
  static const _baseOverhang = 10.0;
  static const _baseInnerWidth = 40.0;
  static const _basePortWidth = 50.0;
  static const _basePortHeight = 42.0;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    canvas.translate(bounds.center.dx, bounds.center.dy);

    final scaleX = bounds.width / _basePortWidth;
    final scaleY = bounds.height / _basePortHeight;
    final uniformScale = math.min(scaleX, scaleY);
    canvas.scale(uniformScale);

    const internalCenterX = (_baseInnerWidth - _baseOverhang) / 2;
    canvas.translate(-internalCenterX, 0);

    // Overhang part (opening, darker)
    paint.color = const Color(0xFF9E9E9E);
    canvas.drawRect(
      const Rect.fromLTWH(-_baseOverhang, -_basePortHeight / 2, _baseOverhang, _basePortHeight),
      paint,
    );

    // Main metal body (on the board)
    paint.color = const Color(0xFFB1B1B1);
    canvas.drawRect(
      const Rect.fromLTWH(0, -_basePortHeight / 2, _baseInnerWidth, _basePortHeight),
      paint,
    );

    // Mounting tabs
    const tabWidth = 5.0;
    const tabHeight = 4.0;
    paint.color = const Color(0xFFB1B1B1);

    const tabX = 0.0;

    // Top tab
    canvas.drawRect(
      const Rect.fromLTWH(tabX, -_basePortHeight / 2 - tabHeight, tabWidth, tabHeight),
      paint,
    );
    // Bottom tab
    canvas.drawRect(const Rect.fromLTWH(tabX, _basePortHeight / 2, tabWidth, tabHeight), paint);

    canvas.restore();
  }
}
