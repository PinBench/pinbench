import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';
import '../breadboard_painter.dart';
import 'breadboard_utils.dart';

/// The centre notch: the moulded channel running the length of the board
/// between the `a`–`e` and `f`–`j` terminal strips.
///
/// It is drawn, not just left blank, because it is the visible reason a row's
/// two halves are separate nodes — and it is the gap a DIP chip straddles,
/// which is why it is exactly wide enough for one — see
/// `BreadboardConfig.centerNotchCells`.
class BreadboardCenterNotchNode extends PaintNode {
  final BreadboardPainter painter;
  final _paint = Paint();

  BreadboardCenterNotchNode(this.painter);

  @override
  Size get size => Size(painter.config.boardLength, painter.config.centerNotchThickness);

  @override
  void paint(Canvas canvas, Offset offset) {
    // A flat band, square-cornered, running the whole length of the board and
    // out to both edges — the moulded gutter itself, not a drawing of one.
    // No rounded ends, no wall hairlines, no marker pill: the channel is a
    // change of surface, and anything more reads as an object sitting on the
    // board rather than a gap in it.
    _paint.style = PaintingStyle.fill;
    _paint.color = BreadboardUtils.notchFloorColor;
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height), _paint);
  }
}
