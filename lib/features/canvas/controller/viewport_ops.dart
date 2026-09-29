import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'canvas_controller.dart';

/// Viewport/matrix math for the canvas: fitting the visible content into a
/// given viewport size. Extracted from `CanvasController`.
class ViewportOps(final CanvasController controller) {
  void fitToContent(Size viewportSize) {
    if (controller.nodes.isEmpty) {
      controller.centerOrigin(viewportSize);
      return;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final node in controller.nodes) {
      final rect = node.rect;
      if (rect.left < minX) minX = rect.left;
      if (rect.top < minY) minY = rect.top;
      if (rect.right > maxX) maxX = rect.right;
      if (rect.bottom > maxY) maxY = rect.bottom;
    }

    for (final wire in controller.wires) {
      for (final bendPoint in wire.bendPoints) {
        if (bendPoint.dx < minX) minX = bendPoint.dx;
        if (bendPoint.dy < minY) minY = bendPoint.dy;
        if (bendPoint.dx > maxX) maxX = bendPoint.dx;
        if (bendPoint.dy > maxY) maxY = bendPoint.dy;
      }
    }

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    final contentCenterX = minX + contentWidth / 2;
    final contentCenterY = minY + contentHeight / 2;

    const padding = 100.0;
    var scaleX = viewportSize.width / (contentWidth + padding);
    var scaleY = viewportSize.height / (contentHeight + padding);

    if (!scaleX.isFinite) scaleX = 1.0;
    if (!scaleY.isFinite) scaleY = 1.0;

    final targetScale = math.min(scaleX, scaleY).clamp(0.05, controller.maxScale);

    final matrix = Matrix4.identity()
      ..translateByDouble(viewportSize.width / 2, viewportSize.height / 2, 0.0, 1.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
      ..translateByDouble(-contentCenterX, -contentCenterY, 0.0, 1.0);

    controller.viewerController.value = matrix;
  }
}
