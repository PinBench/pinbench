import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/theme.dart';

class GuidelinesPainter extends CustomPainter {
  final List<double> verticalGuidelines;
  final List<double> horizontalGuidelines;
  final Color color;

  GuidelinesPainter({
    required this.verticalGuidelines,
    required this.horizontalGuidelines,
    this.color = AppPalette.blueAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (verticalGuidelines.isEmpty && horizontalGuidelines.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // We can use a dash path for style if we want, or just a solid line.
    for (final x in verticalGuidelines) {
      canvas.drawLine(Offset(x, -10000), Offset(x, 10000), paint);
    }

    for (final y in horizontalGuidelines) {
      canvas.drawLine(Offset(-10000, y), Offset(10000, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GuidelinesPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (oldDelegate.verticalGuidelines != verticalGuidelines ||
          oldDelegate.horizontalGuidelines != horizontalGuidelines ||
          oldDelegate.color != color);
}
