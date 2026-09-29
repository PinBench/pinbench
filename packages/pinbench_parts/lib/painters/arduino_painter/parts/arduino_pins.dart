import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../painting/paint_node.dart';
import '../../../painting/part_palette.dart';

class PinBlockNode extends PaintNode {
  final List<String> labels;
  final bool isTop;

  PinBlockNode({required this.labels, this.isTop = true});

  // Pitch is 8 internal units = 16 canvas px — the breadboard hole pitch —
  // so wires from parts whose legs follow the grid drop into the pins
  // vertically straight.
  static const _basePinSize = 6.0;
  static const _basePinPitch = 8.0;
  static const _baseBorderThickness = 2.0;
  static const _baseBlockRadius = 1.5;
  static const _baseHoleRadius = 1.0;

  /// Padding between the strip's rounded ends and the outer edge of the end
  /// holes — matched to the gap between adjacent holes so the strip reads
  /// with the same spacing at its ends as in between.
  static const _endPadding = _basePinPitch - _basePinSize;

  /// Distance from the block's LEFT edge to the first pin's center — position
  /// a block at `firstPinCenter - centerInsetX` to line its holes up with the
  /// port coordinates.
  static const centerInsetX = _endPadding + _basePinSize / 2;

  /// Distance from the block's TOP edge to the pin-row center.
  static const centerInsetY = (_basePinSize + _baseBorderThickness) / 2;

  @override
  Size get size {
    final count = labels.length;
    const baseBlockHeight = _basePinSize + _baseBorderThickness;
    final baseBlockWidth = (count - 1) * _basePinPitch + _basePinSize + 2 * _endPadding;
    return Size(baseBlockWidth, baseBlockHeight);
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    final count = labels.length;
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    canvas.translate(bounds.center.dx, bounds.center.dy);

    const blockRadius = Radius.circular(_baseBlockRadius);
    final blockRect = Rect.fromLTWH(-size.width / 2, -size.height / 2, size.width, size.height);

    paint.color = const Color(0xFF303030); // dark grey
    canvas.drawRRect(RRect.fromRectAndRadius(blockRect, blockRadius), paint);

    drawHoles(canvas, paint, count);
    canvas.restore();

    drawLabels(canvas, offset);
  }

  void drawHoles(Canvas canvas, Paint paint, int pinsCount) {
    const holeRadius = Radius.circular(_baseHoleRadius);
    const outerSize = _basePinSize;
    const innerSize = outerSize * 0.5;

    final startX = -(pinsCount - 1) * _basePinPitch / 2;

    for (var i = 0; i < pinsCount; i++) {
      final xOffset = startX + i * _basePinPitch;

      final outerRect = Rect.fromCenter(
        center: Offset(xOffset, 0),
        width: outerSize,
        height: outerSize,
      );
      final innerRect = Rect.fromCenter(
        center: Offset(xOffset, 0),
        width: innerSize,
        height: innerSize,
      );

      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(outerRect, holeRadius));

      paint.color = const Color(0xFF595959);
      canvas.drawRect(outerRect, paint);

      final darkBevelPath = Path()
        ..moveTo(outerRect.left, outerRect.top)
        ..lineTo(outerRect.right, outerRect.top)
        ..lineTo(innerRect.right, innerRect.top)
        ..lineTo(innerRect.left, innerRect.top)
        ..lineTo(innerRect.left, innerRect.bottom)
        ..lineTo(outerRect.left, outerRect.bottom)
        ..close();

      paint.color = const Color(0xFF1A1A1A);
      canvas.drawPath(darkBevelPath, paint);

      paint.color = const Color(0xFF000000);
      canvas.drawRect(innerRect, paint);
      canvas.restore();
    }
  }

  void drawLabels(Canvas canvas, Offset offset) {
    final count = labels.length;
    final labelStyle = GoogleFonts.jetBrainsMono(
      color: PartPalette.white,
      fontSize: 4.5,
      fontWeight: FontWeight.bold,
    );

    final holeCenterY = offset.dy + size.height / 2;
    final firstHoleX = offset.dx + centerInsetX;

    for (var i = 0; i < count; i++) {
      if (labels[i].isEmpty) continue;

      final x = firstHoleX + i * _basePinPitch;

      canvas.save();
      if (isTop) {
        canvas.translate(x, holeCenterY + _basePinSize + 2.0);
      } else {
        canvas.translate(x, holeCenterY - _basePinSize - 2.0);
      }
      canvas.rotate(-math.pi / 2);

      final textPainter = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: isTop ? TextAlign.end : TextAlign.start,
      );
      textPainter.layout();

      if (isTop) {
        textPainter.paint(canvas, Offset(-textPainter.width, -textPainter.height / 2));
      } else {
        textPainter.paint(canvas, Offset(0, -textPainter.height / 2));
      }
      canvas.restore();
    }
  }
}

class BoardLabelLineNode extends PaintNode {
  final double width;
  final String text;
  final bool textAbove;
  @override
  final Size size;

  BoardLabelLineNode({required this.width, required this.text, this.textAbove = false})
    : size = Size(width, 10.0);

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = PartPalette.white
      ..strokeCap = StrokeCap.round;

    final lineY = offset.dy + size.height / 2;
    canvas.drawLine(Offset(offset.dx, lineY), Offset(offset.dx + width, lineY), paint);

    final labelStyle = GoogleFonts.jetBrainsMono(
      color: PartPalette.white,
      fontSize: 5.0,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textX = offset.dx + (width - textPainter.width) / 2;
    final textY = textAbove ? lineY - textPainter.height - 2.0 : lineY + 2.0;

    textPainter.paint(canvas, Offset(textX, textY));
  }
}
