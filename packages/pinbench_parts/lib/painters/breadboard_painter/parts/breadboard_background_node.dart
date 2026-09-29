import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';
import '../breadboard_painter.dart';
import 'breadboard_utils.dart';

class BreadboardBackgroundNode(final BreadboardPainter painter) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => painter.config.boardSize;

  @override
  void paint(Canvas canvas, Offset offset) {
    _paint.color = BreadboardUtils.backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
        Radius.circular(painter.config.gridCellSize),
      ),
      _paint,
    );
  }
}
