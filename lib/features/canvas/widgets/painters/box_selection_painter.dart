import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/theme.dart';

class BoxSelectionPainter({required final Rect? rect}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (rect == null) return;

    final fillPaint = Paint()
      ..color = AppPalette.blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = AppPalette.blue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRect(rect!, fillPaint);
    canvas.drawRect(rect!, borderPaint);
  }

  @override
  bool shouldRepaint(covariant BoxSelectionPainter oldDelegate) =>
      !identical(this, oldDelegate) && oldDelegate.rect != rect;
}
