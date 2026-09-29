import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../painting/paint_node.dart';

class ResetButtonNode extends PaintNode {
  @override
  final Size size;

  ResetButtonNode({this.size = const Size(25.2, 22.5)});

  static const _baseButtonSize = 30.0;
  static const _baseTabWidth = 1.8;
  static const _baseTabHeight = 6.6;

  static const double _baseTotalWidth = _baseButtonSize + 2 * _baseTabWidth;
  static const double _baseTotalHeight = _baseButtonSize;

  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint();
    canvas.save();

    final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    canvas.translate(bounds.center.dx, bounds.center.dy);

    final scaleX = bounds.width / _baseTotalWidth;
    final scaleY = bounds.height / _baseTotalHeight;
    final uniformScale = math.min(scaleX, scaleY);
    canvas.scale(uniformScale);

    const cornerRadius = Radius.circular(3.75);

    // Main body shadow
    paint.color = const Color(0xFF1D455F); // Dark teal shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0, 3.75),
          width: _baseButtonSize,
          height: _baseButtonSize,
        ),
        cornerRadius,
      ),
      paint,
    );

    // Metal tabs
    paint.color = const Color(0xFFD0D0D0);
    const tabRadius = Radius.circular(0.9);

    // Left tabs (3)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(-_baseButtonSize / 2 - _baseTabWidth / 2, -_baseButtonSize / 3.5),
          width: _baseTabWidth,
          height: _baseTabHeight,
        ),
        tabRadius,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(-_baseButtonSize / 2 - _baseTabWidth / 2, 0),
          width: _baseTabWidth,
          height: _baseTabHeight,
        ),
        tabRadius,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(-_baseButtonSize / 2 - _baseTabWidth / 2, _baseButtonSize / 3.5),
          width: _baseTabWidth,
          height: _baseTabHeight,
        ),
        tabRadius,
      ),
      paint,
    );

    // Right tabs (2)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(_baseButtonSize / 2 + _baseTabWidth / 2, -_baseButtonSize / 3.5),
          width: _baseTabWidth,
          height: _baseTabHeight,
        ),
        tabRadius,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(_baseButtonSize / 2 + _baseTabWidth / 2, _baseButtonSize / 3.5),
          width: _baseTabWidth,
          height: _baseTabHeight,
        ),
        tabRadius,
      ),
      paint,
    );

    // Main body
    paint.color = const Color(0xFFD6D6D6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: _baseButtonSize, height: _baseButtonSize),
        cornerRadius,
      ),
      paint,
    );

    // Hole shadow
    paint.color = const Color(0xFF9A9A9A);
    canvas.drawCircle(const Offset(0, 1.8), 10.35, paint);

    // Red button dark edge
    paint.color = const Color(0xFF8F3928);
    canvas.drawCircle(Offset.zero, 9.3, paint);

    // Inner red highlight
    paint.color = const Color(0xFFA64A35);
    canvas.drawCircle(Offset.zero, 7.8, paint);

    canvas.restore();
  }
}
