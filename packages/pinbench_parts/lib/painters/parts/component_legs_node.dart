import 'package:flutter/widgets.dart';

import '../../painting/paint_node.dart';
import '../../painting/part_palette.dart';

class ComponentLegsNode extends PaintNode {
  final Size componentSize;
  final List<(Offset start, Offset end)> legs;
  final _paint = Paint();

  ComponentLegsNode({required this.componentSize, required this.legs});

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
