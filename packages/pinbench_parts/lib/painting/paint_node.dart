import 'dart:math' as math;

import 'package:flutter/widgets.dart';

abstract class PaintNode {
  Size get size;
  void paint(Canvas canvas, Offset offset);
}

class CanvasPositioned {
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final PaintNode child;

  const CanvasPositioned({this.left, this.top, this.right, this.bottom, required this.child});
}

class CanvasStack extends PaintNode {
  @override
  final Size size;
  final List<CanvasPositioned> children;

  CanvasStack({this.size = Size.zero, required this.children});

  @override
  void paint(Canvas canvas, Offset offset) {
    for (final pos in children) {
      var dx = offset.dx;
      var dy = offset.dy;

      if (pos.left != null) {
        dx += pos.left!;
      } else if (pos.right != null) {
        dx += size.width - pos.right! - pos.child.size.width;
      }

      if (pos.top != null) {
        dy += pos.top!;
      } else if (pos.bottom != null) {
        dy += size.height - pos.bottom! - pos.child.size.height;
      }

      pos.child.paint(canvas, Offset(dx, dy));
    }
  }
}

class CanvasRow extends PaintNode {
  final double spacing;
  final List<PaintNode> children;

  CanvasRow({this.spacing = 0.0, required this.children});

  @override
  Size get size {
    if (children.isEmpty) return Size.zero;
    var width = (children.length - 1) * spacing;
    double height = 0;
    for (final child in children) {
      width += child.size.width;
      height = math.max(height, child.size.height);
    }
    return Size(width, height);
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    var currentX = offset.dx;
    for (final child in children) {
      // Center vertically within the row height by default
      final childY = offset.dy + (size.height - child.size.height) / 2;
      child.paint(canvas, Offset(currentX, childY));
      currentX += child.size.width + spacing;
    }
  }
}

class CanvasColumn extends PaintNode {
  final double spacing;
  final List<PaintNode> children;

  CanvasColumn({this.spacing = 0.0, required this.children});

  @override
  Size get size {
    if (children.isEmpty) return Size.zero;
    var height = (children.length - 1) * spacing;
    double width = 0;
    for (final child in children) {
      height += child.size.height;
      width = math.max(width, child.size.width);
    }
    return Size(width, height);
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    var currentY = offset.dy;
    for (final child in children) {
      // Center horizontally within the column width by default
      final childX = offset.dx + (size.width - child.size.width) / 2;
      child.paint(canvas, Offset(childX, currentY));
      currentY += child.size.height + spacing;
    }
  }
}
