import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../painting/base_component_painter.dart';
import 'parts/component_legs_node.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/part_palette.dart';

/// Draws a piezo buzzer, animated while sounding (`isOn`) at the detected
/// `frequency`. Provides `plus`/`minus` ports.
class PiezoBuzzerPainter({final Map<String, dynamic>? properties, super.isOutline})
    extends BaseComponentPainter
    with PortProvider, PaintTreeComponent {
  bool get isOn {
    final value = properties?[ComponentProps.isOn];
    if (value is bool) return value;
    if (value is String) return value == 'true';
    return false;
  }

  double? get frequency {
    final value = properties?[ComponentProps.frequency];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }

  // Ø15 mm breadboard piezo buzzer — the larger of the two common can sizes,
  // chosen deliberately so the buzzer reads clearly next to its neighbours.
  static const bodyDiameterMm = 15.0;
  static const bodyDiameter = bodyDiameterMm * PhysicalScale.pxPerMm;

  // The bounds stay one hole pitch wider than the leg span so both leads keep
  // their lattice columns; the (smaller) body is centred in them, with the
  // leads emerging just below it and ending on the next lattice row down.
  static const width = GridSystem.pitch * 6 + GridSystem.cellSize;
  static const height = GridSystem.pitch * 6 + GridSystem.cellSize;

  // To align with breadboard holes the X coordinates must sit on the
  // connection lattice (≡ cellCenter mod pitch). Leg spacing of 4 hole
  // pitches (10.16 mm) perfectly spans from column 'a' to 'e'.
  static const leftLegX = width / 2 - GridSystem.pitch * 1;
  static const rightLegX = width - leftLegX;

  static const componentSize = Size(width, height);

  /// The can, centred across the bounds and sitting at the top.
  @override
  Rect bodyRect(Size size) =>
      Rect.fromLTWH((size.width - bodyDiameter) / 2, 0, bodyDiameter, bodyDiameter);

  @override
  List<ComponentPort> getPorts() {
    const bottomY = height - GridSystem.cellCenter;

    return [
      const ComponentPort(id: 'plus', name: 'Positive', localOffset: Offset(leftLegX, bottomY)),
      const ComponentPort(id: 'minus', name: 'Negative', localOffset: Offset(rightLegX, bottomY)),
    ];
  }

  @override
  PaintNode buildTree() => CanvasStack(
    size: componentSize,
    children: [
      CanvasPositioned(
        left: 0,
        top: 0,
        child: ComponentLegsNode(
          componentSize: componentSize,
          legs: [
            (
              const Offset(leftLegX, bodyDiameter / 2),
              const Offset(leftLegX, height - GridSystem.cellCenter),
            ),
            (
              const Offset(rightLegX, bodyDiameter / 2),
              const Offset(rightLegX, height - GridSystem.cellCenter),
            ),
          ],
        ),
      ),
      CanvasPositioned(left: 0, top: 0, child: _PiezoBuzzerBodyNode(this)),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant PiezoBuzzerPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (oldDelegate.isOn != isOn || oldDelegate.frequency != frequency);
}

class _PiezoBuzzerBodyNode(final PiezoBuzzerPainter painter) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => const Size(PiezoBuzzerPainter.width, PiezoBuzzerPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    const bodyCenter = Offset(PiezoBuzzerPainter.width / 2, PiezoBuzzerPainter.bodyDiameter / 2);
    const bodyRadius = PiezoBuzzerPainter.bodyDiameter / 2;

    if (painter.isOn) {
      // Draw a glowing sound aura
      final glowPaint = Paint()
        ..color = PartPalette.blueAccent.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0);
      canvas.drawCircle(bodyCenter, bodyRadius + 15, glowPaint);
    }

    // Main body (dark grey circle)
    _paint.style = PaintingStyle.fill;
    _paint.color = const Color(0xFF333333); // Dark grey
    canvas.drawCircle(bodyCenter, bodyRadius, _paint);

    // Center dot (tan color)
    _paint.color = const Color(0xFFAFA67B);
    canvas.drawCircle(bodyCenter, bodyRadius * 0.25, _paint);

    if (painter.isOn) {
      // Draw concentric sound waves vibrating from center
      _paint.style = PaintingStyle.stroke;
      _paint.color = PartPalette.blue300.withValues(alpha: 0.8);
      _paint.strokeWidth = 3.0;

      canvas.drawCircle(bodyCenter, bodyRadius * 0.4, _paint);
      canvas.drawCircle(bodyCenter, bodyRadius * 0.6, _paint);
      canvas.drawCircle(bodyCenter, bodyRadius * 0.8, _paint);
    }

    // Symbols (+ on left, - on right)
    // Polarity marks sit over each lead, kept inside the can's rim.
    const symbolRadius = 7.0;
    const symbolY = PiezoBuzzerPainter.bodyDiameter * 0.72;
    const symbolInset = PiezoBuzzerPainter.bodyDiameter * 0.22;
    const leftSymbolX = PiezoBuzzerPainter.width / 2 - symbolInset;
    const rightSymbolX = PiezoBuzzerPainter.width / 2 + symbolInset;

    // + Symbol outline
    _paint.style = PaintingStyle.stroke;
    _paint.strokeWidth = 1.0;
    _paint.color = PartPalette.grey600;
    canvas.drawCircle(const Offset(leftSymbolX, symbolY), symbolRadius, _paint);

    // - Symbol outline
    canvas.drawCircle(const Offset(rightSymbolX, symbolY), symbolRadius, _paint);

    // Draw '+'
    _paint.color = PartPalette.white;
    _paint.strokeWidth = 1.0;
    _paint.strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(leftSymbolX - 5, symbolY),
      const Offset(leftSymbolX + 5, symbolY),
      _paint,
    );
    canvas.drawLine(
      const Offset(leftSymbolX, symbolY - 5),
      const Offset(leftSymbolX, symbolY + 5),
      _paint,
    );

    // Draw '-'
    canvas.drawLine(
      const Offset(rightSymbolX - 5, symbolY),
      const Offset(rightSymbolX + 5, symbolY),
      _paint,
    );

    canvas.restore();
  }
}
