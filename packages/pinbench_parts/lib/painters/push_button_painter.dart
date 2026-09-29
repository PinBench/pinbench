import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../painting/base_component_painter.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/part_palette.dart';

/// Draws a momentary push button, pressed-down when `isPressed`. Provides its
/// four legs (`leg1`–`leg4`).
class PushButtonPainter({final Map<String, dynamic>? properties, super.isOutline})
    extends BaseComponentPainter
    with PortProvider, PaintTreeComponent {
  bool get isPressed {
    final value = properties?[ComponentProps.isPressed];
    if (value is bool) return value;
    if (value is String) return value == 'true';
    return false;
  }

  // Standard 6 × 6 mm tactile switch body.
  static const bodySizeMm = 6.0;
  static const bodySize = bodySizeMm * PhysicalScale.pxPerMm;

  // Legs 2 hole pitches apart in x and 3 in y — the pitches a 6 × 6 tact
  // switch's leads are bent to so it straddles a breadboard's centre channel.
  // The bounds are sized so all four leg tips land on the connection lattice
  // (≡ cellCenter mod pitch), with the body centred inside them.
  static const width = GridSystem.pitch * 2 + GridSystem.cellCenter * 2;
  static const height = GridSystem.pitch * 3 + GridSystem.cellCenter * 2;

  static const leftLegX = GridSystem.cellCenter;
  static const rightLegX = width - GridSystem.cellCenter;

  static const componentSize = Size(width, height);

  /// The switch body, centred in the bounds; the four legs bend out from it
  /// to the lattice and [BaseComponentPainter.hitArea] adds them.
  @override
  Rect bodyRect(Size size) =>
      Rect.fromCenter(center: size.center(Offset.zero), width: bodySize, height: bodySize);

  @override
  List<ComponentPort> getPorts() {
    const centerY = height / 2;
    const legHeight = height - GridSystem.cellCenter * 2;

    const topY = centerY - legHeight / 2;
    const bottomY = centerY + legHeight / 2;

    return [
      const ComponentPort(id: 'leg1', name: 'Leg 1', localOffset: Offset(leftLegX, topY)),
      const ComponentPort(id: 'leg2', name: 'Leg 2', localOffset: Offset(rightLegX, topY)),
      const ComponentPort(id: 'leg3', name: 'Leg 3', localOffset: Offset(leftLegX, bottomY)),
      const ComponentPort(id: 'leg4', name: 'Leg 4', localOffset: Offset(rightLegX, bottomY)),
    ];
  }

  @override
  PaintNode buildTree() => CanvasStack(
    size: componentSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: _PushButtonLegsNode()),
      CanvasPositioned(left: 0, top: 0, child: _PushButtonBodyNode(this)),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant PushButtonPainter oldDelegate) =>
      oldDelegate.isPressed != isPressed;
}

class _PushButtonLegsNode extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => const Size(PushButtonPainter.width, PushButtonPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    const centerY = PushButtonPainter.height / 2;
    const legHeight = PushButtonPainter.height - GridSystem.cellCenter * 2;
    const leftLegX = PushButtonPainter.leftLegX;
    const rightLegX = PushButtonPainter.rightLegX;

    _paint.strokeWidth = 4;
    _paint.color = PartPalette.grey400;
    _paint.strokeCap = StrokeCap.round;

    for (final x in [leftLegX, rightLegX]) {
      canvas.drawLine(
        Offset(x, centerY - legHeight / 2),
        Offset(x, centerY + legHeight / 2),
        _paint,
      );
    }

    canvas.restore();
  }
}

class _PushButtonBodyNode(final PushButtonPainter parent) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => const Size(PushButtonPainter.width, PushButtonPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    const bodyFillColor = PartPalette.grey400;
    const bodyBorderColor = PartPalette.grey500;
    const cornerDotColor = PartPalette.grey800;
    final buttonFillColor = parent.isPressed ? PartPalette.grey800 : PartPalette.grey900;
    const buttonBorderColor = PartPalette.grey700;

    const bodyRadius = Radius.circular(6);
    const innerRadius = Radius.circular(5);
    const center = Offset(PushButtonPainter.width / 2, PushButtonPainter.height / 2);

    canvas.save();
    canvas.translate(offset.dx + center.dx, offset.dy + center.dy);

    // Main body border
    _paint.color = bodyBorderColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: PushButtonPainter.bodySize,
          height: PushButtonPainter.bodySize,
        ),
        bodyRadius,
      ),
      _paint,
    );

    // Main body fill
    _paint.color = bodyFillColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: PushButtonPainter.bodySize - 3,
          height: PushButtonPainter.bodySize - 3,
        ),
        innerRadius,
      ),
      _paint,
    );

    // Corner dots
    _paint.color = cornerDotColor;
    const cornerInset = PushButtonPainter.bodySize / 2 - 7; // 8 in from each corner
    const dotRadius = 3.0;

    for (final dx in [-cornerInset, cornerInset]) {
      for (final dy in [-cornerInset, cornerInset]) {
        canvas.drawCircle(Offset(dx, dy), dotRadius, _paint);
      }
    }

    // Button border
    _paint.color = buttonBorderColor;
    canvas.drawCircle(Offset.zero, parent.isPressed ? 10 : 11, _paint);

    // Button fill
    _paint.color = buttonFillColor;
    canvas.drawCircle(Offset.zero, parent.isPressed ? 9 : 10, _paint);

    canvas.restore();
  }
}
