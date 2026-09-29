import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../providers/canvas_controller_provider.dart';

class _MinimapData(
  final double minX,
  final double minY,
  final double maxX,
  final double maxY,
  final double scale,
  final double dx,
  final double dy,
);

_MinimapData? _calculateMinimapData(List<ComponentInstance> nodes, Rect visibleRect, Size size) {
  if (nodes.isEmpty) return null;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;

  for (final node in nodes) {
    if (node.rect.left < minX) minX = node.rect.left;
    if (node.rect.top < minY) minY = node.rect.top;
    if (node.rect.right > maxX) maxX = node.rect.right;
    if (node.rect.bottom > maxY) maxY = node.rect.bottom;
  }

  if (visibleRect.left < minX) minX = visibleRect.left;
  if (visibleRect.top < minY) minY = visibleRect.top;
  if (visibleRect.right > maxX) maxX = visibleRect.right;
  if (visibleRect.bottom > maxY) maxY = visibleRect.bottom;

  const padding = 100.0;
  minX -= padding;
  minY -= padding;
  maxX += padding;
  maxY += padding;

  final boundsWidth = maxX - minX;
  final boundsHeight = maxY - minY;

  if (boundsWidth <= 0 || boundsHeight <= 0) return null;

  final scaleX = size.width / boundsWidth;
  final scaleY = size.height / boundsHeight;
  final scale = math.min(scaleX, scaleY);

  final mapContentWidth = boundsWidth * scale;
  final mapContentHeight = boundsHeight * scale;
  final dx = (size.width - mapContentWidth) / 2;
  final dy = (size.height - mapContentHeight) / 2;

  return _MinimapData(minX, minY, maxX, maxY, scale, dx, dy);
}

class const MinimapView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(canvasControllerProvider);
    final controller = ref.read(canvasControllerProvider.notifier);
    final colors = context.appColors;

    if (state.nodes.isEmpty) return const SizedBox.shrink();

    const minimapSize = Size(200, 120);

    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final data = _calculateMinimapData(state.nodes, controller.visibleRect, minimapSize);
          if (data == null) return;

          final tapLocal = details.localPosition;
          final canvasX = (tapLocal.dx - data.dx) / data.scale + data.minX;
          final canvasY = (tapLocal.dy - data.dy) / data.scale + data.minY;

          controller.centerOn(Offset(canvasX, canvasY));
        },
        onPanUpdate: (details) {
          final data = _calculateMinimapData(state.nodes, controller.visibleRect, minimapSize);
          if (data == null) return;

          // Calculate the actual delta to move the interactive viewer
          // Inverse panning: removing the negative sign so moving right pans right
          final canvasDelta = details.delta / data.scale;
          controller.viewerController.pan(canvasDelta * controller.scale);
        },
        child: SizedBox(
          width: minimapSize.width,
          height: minimapSize.height,
          child: AppCard(
            padding: EdgeInsets.zero,
            clipContent: true,
            child: ListenableBuilder(
              listenable: controller.viewerController,
              builder: (context, child) => CustomPaint(
                painter: _MinimapPainter(
                  nodes: state.nodes,
                  visibleRect: controller.visibleRect,
                  foregroundColor: colors.foreground,
                  accentColor: colors.primary,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter({
  required final List<ComponentInstance> nodes,
  required final Rect visibleRect,
  required final Color foregroundColor,
  required final Color accentColor,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final data = _calculateMinimapData(nodes, visibleRect, size);
    if (data == null) return;

    canvas.save();
    canvas.translate(data.dx, data.dy);
    canvas.scale(data.scale);
    canvas.translate(-data.minX, -data.minY);

    // Draw nodes
    final nodePaint = Paint()
      ..color = foregroundColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (final node in nodes) {
      canvas.drawRect(node.rect, nodePaint);
    }

    // Draw visible rect
    final visibleRectPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / data.scale; // Keep stroke width consistent regardless of scale

    canvas.drawRect(visibleRect, visibleRectPaint);

    // Draw a subtle fill for the visible rect
    final visibleFillPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawRect(visibleRect, visibleFillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.visibleRect != visibleRect ||
      oldDelegate.foregroundColor != foregroundColor ||
      oldDelegate.accentColor != accentColor;
}
