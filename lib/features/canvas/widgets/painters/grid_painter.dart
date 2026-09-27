import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../controller/canvas_controller.dart';

class GridPainter extends CustomPainter {
  GridPainter(this.context, this.controller) : super(repaint: controller.viewerController);

  final BuildContext context;
  final CanvasController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.showGrid) return;

    final s = controller.scale;

    // Get visible bounds in canvas space by mapping screen corners
    final p1 = controller.screenToCanvasCoordinates(Offset.zero);
    final p2 = controller.screenToCanvasCoordinates(Offset(size.width, 0));
    final p3 = controller.screenToCanvasCoordinates(Offset(0, size.height));
    final p4 = controller.screenToCanvasCoordinates(Offset(size.width, size.height));

    final left = [p1.dx, p2.dx, p3.dx, p4.dx].reduce((a, b) => a < b ? a : b) - 100;
    final right = [p1.dx, p2.dx, p3.dx, p4.dx].reduce((a, b) => a > b ? a : b) + 100;
    final top = [p1.dy, p2.dy, p3.dy, p4.dy].reduce((a, b) => a < b ? a : b) - 100;
    final bottom = [p1.dy, p2.dy, p3.dy, p4.dy].reduce((a, b) => a > b ? a : b) + 100;

    canvas.save();
    canvas.transform(controller.transform.storage);

    final baseStep = controller.gridCellSize;
    final colorScheme = context.appColors;

    void drawLevel(
      double multiplier,
      double baseWidth,
      double alphaFactor,
      double maxAlpha,
      Color levelColor,
    ) {
      final spacing = baseStep * multiplier;
      final screenStep = spacing * s;

      // 1. Adaptive Visibility (Lowered threshold to ensure visibility at minScale 0.5)
      const minSpacing = 5.0;
      if (screenStep <= minSpacing) return;

      // 2. Opacity Calculation (fade in between 5px and 50px of screen spacing)
      const maxSpacing = 50.0;
      double opacity;
      if (screenStep >= maxSpacing) {
        opacity = 1.0;
      } else {
        opacity = (screenStep - minSpacing) / (maxSpacing - minSpacing);
      }

      // 3. Zoom Boost: past 50px spacing this level is the dominant visible
      // grid, so ramp its alpha from the base factor up to maxAlpha by 250px.
      const boostEnd = 250.0;
      final boost = ((screenStep - maxSpacing) / (boostEnd - maxSpacing)).clamp(0.0, 1.0);
      final levelAlpha = alphaFactor + (maxAlpha - alphaFactor) * boost;

      // Use the level color with the adaptive opacity
      final finalColor = levelColor.withValues(alpha: opacity * levelAlpha);

      // 4. Scale-Inverse Thickness, slightly thicker once the level dominates
      final screenWidth = baseWidth + 0.4 * boost;
      final thickness = (screenWidth / s).clamp(0.6 / s, 5.0 / s);

      final paint = Paint()
        ..color = finalColor
        ..strokeWidth = thickness;

      // Vertical lines
      final startX = (left / spacing).floor() * spacing;
      for (var x = startX; x <= right; x += spacing) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
      }

      // Horizontal lines
      final startY = (top / spacing).floor() * spacing;
      for (var y = startY; y <= bottom; y += spacing) {
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
      }
    }

    // Define levels with increasing spacing, baseWidth, distinct opacities and
    // colors. Mid-tone hues so each level reads on both light and dark themes.

    // Level 3: coarsest
    drawLevel(50, 1.3, 0.2, 0.55, colorScheme.foreground);
    // Level 2: medium
    drawLevel(10, 1.2, 0.3, 0.5, AppPalette.deepOrange);
    // Level 1: component step
    drawLevel(2, 1.1, 0.4, 0.45, AppPalette.green);
    // Level 0: finest
    drawLevel(1, 1.0, 0.5, 0.8, AppPalette.purple);

    // Center Axes (x=0, y=0)
    final axisPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.4)
      ..strokeWidth = (2.0 / s).clamp(1.0 / s, 4.0 / s);

    if (0 >= left && 0 <= right) {
      canvas.drawLine(Offset(0, top), Offset(0, bottom), axisPaint);
    }
    if (0 >= top && 0 <= bottom) {
      canvas.drawLine(Offset(left, 0), Offset(right, 0), axisPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.controller.scale != controller.scale ||
      oldDelegate.controller.offset != controller.offset ||
      oldDelegate.controller.showGrid != controller.showGrid;
}
