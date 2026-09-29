import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../painting/base_component_painter.dart';
import 'parts/component_legs_node.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/part_palette.dart';

/// Draws a capacitor labelled with its `Capacitance` value.
class CapacitorPainter extends BaseComponentPainter with PortProvider, PaintTreeComponent {
  final Map<String, dynamic>? properties;

  CapacitorPainter({this.properties, super.isOutline});

  String get capacitanceString => (properties?[ComponentProps.capacitance] ?? '100nF').toString();

  static const double gridCellSize = GridSystem.cellSize;
  static const double gridCellCenter = GridSystem.cellCenter;

  // Ø7 mm ceramic disc (104 / 100 nF). The disc is 3 mm thick, which is the
  // depth we don't see: face-on it reads as a 7 mm circle.
  static const bodyDiameterMm = 7.0;
  static const bodyDiameter = bodyDiameterMm * PhysicalScale.pxPerMm;
  static const bodyHeight = bodyDiameter;

  static const width = 56.0;
  static const height = 52.0;

  // Legs one hole pitch apart on the connection lattice (≡ cellCenter mod
  // pitch, in x and y — width/height are chosen to make that come out).
  static const leftLegX = width / 2 - GridSystem.cellSize;
  static const rightLegX = width / 2 + GridSystem.cellSize;

  static const componentSize = Size(width, height);

  /// The disc, centred across the bounds and sitting at the top.
  @override
  Rect bodyRect(Size size) =>
      Rect.fromLTWH((size.width - bodyDiameter) / 2, 0, bodyDiameter, bodyHeight);

  @override
  List<ComponentPort> getPorts() => [
    const ComponentPort(id: 'left', name: 'Left Leg', localOffset: Offset(leftLegX, height)),
    const ComponentPort(id: 'right', name: 'Right Leg', localOffset: Offset(rightLegX, height)),
  ];

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
            (const Offset(leftLegX, bodyDiameter / 2), const Offset(leftLegX, height)),
            (const Offset(rightLegX, bodyDiameter / 2), const Offset(rightLegX, height)),
          ],
        ),
      ),
      CanvasPositioned(left: 0, top: 0, child: _CapacitorBodyNode(this)),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant CapacitorPainter oldDelegate) =>
      oldDelegate.capacitanceString != capacitanceString;
}

class _CapacitorBodyNode extends PaintNode {
  final CapacitorPainter painter;
  final _paint = Paint();

  _CapacitorBodyNode(this.painter);

  @override
  Size get size => const Size(CapacitorPainter.width, CapacitorPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    const center = Offset(CapacitorPainter.width / 2, CapacitorPainter.bodyHeight / 2);
    const radius = CapacitorPainter.bodyHeight / 2;

    // Draw rounded box behind circle to mimic epoxy dripping onto legs
    _paint.style = PaintingStyle.fill;
    _paint.color = const Color(0xFF1C87D9); // Bright Cerulean Blue

    const leftLegX = CapacitorPainter.leftLegX;
    const rightLegX = CapacitorPainter.rightLegX;
    const epoxyTop = CapacitorPainter.bodyDiameter * 0.7;
    const epoxyBottom = CapacitorPainter.bodyDiameter + 2.0;

    for (final legX in const [leftLegX, rightLegX]) {
      canvas.drawRRect(
        RRect.fromLTRBR(legX - 4.0, epoxyTop, legX + 4.0, epoxyBottom, const Radius.circular(3.5)),
        _paint,
      );
    }

    // Draw the solid main circle body
    canvas.drawCircle(center, radius, _paint);

    // Vector-style shine (curved stroke on top-left)
    _paint.style = PaintingStyle.stroke;
    _paint.strokeWidth = 3.5;
    _paint.strokeCap = StrokeCap.round;
    _paint.color = PartPalette.white.withAlpha(120);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4.5),
      3.14159 + 3.14159 / 6, // ~210 degrees
      3.14159 / 3.5, // ~50 degrees
      false,
      _paint,
    );

    // Draw the text code
    final code = _getCapacitorCode(painter.capacitanceString);
    final textPainter = TextPainter(
      text: TextSpan(
        text: code,
        style: GoogleFonts.jetBrainsMono(
          color: PartPalette.white,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position text in center, slightly pushed down to visually balance with the top shine
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2 + 2.0),
    );

    canvas.restore();
  }

  String _getCapacitorCode(String input) {
    final str = input.trim().toUpperCase().replaceAll(' ', '');
    var multiplier = 1.0;

    if (str.contains('P')) {
      multiplier = 1.0;
    } else if (str.contains('N')) {
      multiplier = 1000.0;
    } else if (str.contains('U') || str.contains('Μ')) {
      // Greek letter mu
      multiplier = 1000000.0;
    } else if (str.contains('M')) {
      multiplier = 1000000000.0;
    } else {
      if (str.contains('F') &&
          !str.contains('P') &&
          !str.contains('N') &&
          !str.contains('U') &&
          !str.contains('M')) {
        multiplier = 1e12;
      } else {
        multiplier = 1e12; // Assume Farads if no valid prefix
      }
    }

    final numStr = str.replaceAll(RegExp(r'[^0-9\.eE\-]'), '');
    if (numStr.isEmpty) return '104';

    final valF = double.tryParse(numStr);
    if (valF == null) return '104';

    final pF = valF * multiplier;
    if (pF < 1.0) return '1';
    if (pF < 100.0) return pF.round().toString();

    var exponent = (math.log(pF) / math.ln10).floor() - 1;
    if (exponent < 0) exponent = 0;
    if (exponent > 9) exponent = 9;

    final sigVal = pF / math.pow(10, exponent);
    var sigDigits = sigVal.round();
    if (sigDigits >= 100) {
      sigDigits = sigDigits ~/ 10;
      exponent++;
    }

    return '$sigDigits$exponent';
  }
}
