import 'package:flutter/widgets.dart';

import '../../painting/paint_node.dart';
import '../../painting/part_palette.dart';

class ComponentLegsNode({
  required final Size componentSize,
  required final List<(Offset start, Offset end)> legs,
}) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => componentSize;

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    _paint.strokeWidth = 4;
    _paint.color = PartPalette.grey400;
    _paint.strokeCap = StrokeCap.round;

    for (final leg in legs) {
      canvas.drawLine(leg.$1, leg.$2, _paint);
    }

    canvas.restore();
  }
}
