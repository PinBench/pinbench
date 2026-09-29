import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';

class BoardBackgroundNode({@override final Size size = const Size(250.0, 200.0)})
    extends PaintNode {
  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    paint.color = const Color(0xFF0F7391);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    final w = size.width;
    final h = size.height;
    const r = 8.0;

    final path = Path()
      ..moveTo(w * (228.5 / 242.9), 0)
      ..lineTo(w * (233.9 / 242.9), h * (5.4 / 188.9))
      ..lineTo(w * (233.9 / 242.9), h * (45.9 / 188.9))
      ..lineTo(w, h * (54.9 / 188.9))
      ..lineTo(w, h * (171.0 / 188.9))
      ..lineTo(w * (233.9 / 242.9), h * (180.0 / 188.9))
      ..lineTo(w * (233.9 / 242.9), h - r)
      ..arcToPoint(Offset(w * (233.9 / 242.9) - r, h), radius: const Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }
}
