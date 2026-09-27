import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../painting/base_component_painter.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/part_palette.dart';

/// Draws an LED, lit by `isOn` and dimmed by `brightness` (PWM duty), in the
/// `Color` chosen in the property panel. Provides `anode`/`cathode` ports.
class LEDPainter extends BaseComponentPainter with PortProvider, PaintTreeComponent {
  final Map<String, dynamic>? properties;

  LEDPainter({this.properties, super.isOutline});

  bool get isOn {
    final value = properties?[ComponentProps.isOn];
    if (value is bool) return value;
    if (value is String) return value == 'true';
    return false;
  }

  Color get color =>
      _getColorFromString(properties?[ComponentProps.color]?.toString()) ?? PartPalette.redAccent;

  bool get hasError {
    final value = properties?[ComponentProps.hasError];
    if (value is bool) return value;
    if (value is String) return value == 'true';
    return false;
  }

  /// LED brightness (0.0–1.0) from the PWM duty cycle. Defaults to fully bright
  /// when the LED is on but no explicit brightness was set.
  double get brightnessFraction {
    final value = properties?[ComponentProps.brightness];
    if (value is num) return value.toDouble().clamp(0.0, 1.0);
    return 1.0;
  }

  bool get drawGlow => true;

  Color? _getColorFromString(String? colorString, {bool dark = false}) {
    if (colorString == null) return null;
    switch (colorString.toLowerCase()) {
      case 'red':
        return dark ? const Color(0xFF990000) : PartPalette.red;
      case 'green':
        return dark ? const Color(0xFF006600) : PartPalette.green;
      case 'blue':
        return dark ? const Color(0xFF000099) : PartPalette.blue;
      case 'yellow':
        return dark ? const Color(0xFF999900) : PartPalette.yellow;
      case 'cyan':
        return dark ? const Color(0xFF009999) : PartPalette.cyan;
      case 'pink':
        return dark ? const Color(0xFF99004D) : PartPalette.pink;
      case 'orange':
        return dark ? const Color(0xFF994C00) : PartPalette.orange;
      default:
        return null;
    }
  }

  // Standard 5 mm through-hole LED. The lens is the real Ø5 mm; the body is
  // drawn a little shorter than the real 8.7 mm so the lens does not tower
  // over the short leads.
  static const bodyWidthMm = 5.0;
  static const bodyHeightMm = 6.5;

  static const bodyHeight = bodyHeightMm * PhysicalScale.pxPerMm;
  static const bodyWidth = bodyWidthMm * PhysicalScale.pxPerMm;

  // Leads one hole pitch apart (real LED lead spacing is 2.54 mm), sitting on
  // the connection lattice. The body is wider than that pitch, so the legs run
  // one full pitch in from the component's edges to leave the lens room —
  // which is what puts the leg columns on the lattice too.
  static const width = GridSystem.pitch * 3.5;
  static const leftLegX = GridSystem.pitch + GridSystem.cellCenter;
  static const rightLegX = leftLegX + GridSystem.pitch;

  // Leg tips sit on the lattice one pitch below the body, so the legs stay
  // visible under the (now taller) lens.
  static const legTipY = GridSystem.pitch * 3 + GridSystem.cellCenter;
  static const legsHeight = legTipY - bodyHeight;
  static const height = legTipY + GridSystem.cellCenter;

  static const componentSize = Size(width, height);

  /// The lens, centred across the bounds and sitting at the top. The pitch of
  /// air either side of it belongs to the board underneath.
  @override
  Rect bodyRect(Size size) => Rect.fromLTWH((size.width - bodyWidth) / 2, 0, bodyWidth, bodyHeight);

  @override
  List<ComponentPort> getPorts() {
    const cathodeEndY = legTipY;
    const anodeEndY = cathodeEndY;

    return [
      const ComponentPort(id: 'anode', name: 'Anode', localOffset: Offset(rightLegX, anodeEndY)),
      const ComponentPort(
        id: 'cathode',
        name: 'Cathode',
        localOffset: Offset(leftLegX, cathodeEndY),
      ),
    ];
  }

  @override
  PaintNode buildTree() => CanvasStack(
    size: componentSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: _LEDLegsNode()),
      CanvasPositioned(left: 0, top: 0, child: _LEDBodyNode(this)),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant LEDPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (oldDelegate.isOn != isOn ||
          oldDelegate.color != color ||
          oldDelegate.hasError != hasError ||
          oldDelegate.brightnessFraction != brightnessFraction);

  @override
  bool? hitTest(Offset position) => true; // Accept clicks anywhere within the component bounds
}

class _LEDBodyNode extends PaintNode {
  final LEDPainter painter;
  final _paint = Paint();

  _LEDBodyNode(this.painter);

  @override
  Size get size => const Size(LEDPainter.width, LEDPainter.bodyHeight);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    // Body is narrower than the leg span, so center it between the legs.
    const leftPad = (LEDPainter.width - LEDPainter.bodyWidth) / 2;
    canvas.translate(offset.dx + leftPad, offset.dy);

    // Top is a true semicircle dome, so the reflection arc below can match its curvature exactly.
    const topRadius = Radius.circular(LEDPainter.bodyWidth / 2);
    const bottomRadius = Radius.circular(4);

    // We create a darker version for when it's off
    final hsl = HSLColor.fromColor(painter.color);
    final darkColor = hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
    final highlight = hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();

    final lit = painter.isOn && !painter.hasError;
    final brightness = painter.brightnessFraction;
    // Fade the lit body between off (dark) and full colour by the duty cycle.
    final litColor = Color.lerp(darkColor, painter.color, brightness) ?? painter.color;
    final baseColor = lit ? litColor : darkColor;
    final highlightColor = lit ? PartPalette.white70 : highlight;

    if (lit && brightness > 0 && painter.drawGlow && !painter.isOutline) {
      // Draw a glowing effect, its intensity scaled by the duty cycle.
      final glowPaint = Paint()
        ..color = painter.color.withValues(alpha: 0.5 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(-10, -10, LEDPainter.bodyWidth + 20, LEDPainter.bodyHeight + 20),
          topLeft: topRadius,
          topRight: topRadius,
          bottomLeft: bottomRadius,
          bottomRight: bottomRadius,
        ),
        glowPaint,
      );
    }

    // Main body (slightly transparent to look like real LED plastic)
    _paint.color = baseColor.withAlpha(210);
    _paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(0, 0, LEDPainter.bodyWidth, LEDPainter.bodyHeight),
        topLeft: topRadius,
        topRight: topRadius,
        bottomLeft: bottomRadius,
        bottomRight: bottomRadius,
      ),
      _paint,
    );

    // Vector-style shine (curved stroke on top-left) matching the capacitor
    _paint.style = PaintingStyle.stroke;
    _paint.strokeWidth = 3.0;
    _paint.strokeCap = StrokeCap.round;
    _paint.color = highlightColor;

    canvas.drawArc(
      Rect.fromCircle(
        center: const Offset(LEDPainter.bodyWidth / 2, LEDPainter.bodyWidth / 2),
        radius: LEDPainter.bodyWidth / 2 - 4.0,
      ),
      3.14159 + 3.14159 / 6, // ~210 degrees
      3.14159 / 3.5, // ~50 degrees
      false,
      _paint,
    );

    // Secondary vertical reflection on the right side
    // _paint.strokeWidth = 2.0;
    // _paint.color = highlightColor.withAlpha(50);
    // canvas.drawLine(
    //   const Offset(LEDPainter.bodyWidth - 4, 18),
    //   const Offset(LEDPainter.bodyWidth - 4, LEDPainter.bodyHeight - 8),
    //   _paint,
    // );

    if (painter.hasError) {
      _paint.color = PartPalette.red;
      _paint.style = PaintingStyle.stroke;
      _paint.strokeWidth = 3;
      canvas.drawLine(
        const Offset(5, 5),
        const Offset(LEDPainter.bodyWidth - 5, LEDPainter.bodyHeight - 5),
        _paint,
      );
      canvas.drawLine(
        const Offset(LEDPainter.bodyWidth - 5, 5),
        const Offset(5, LEDPainter.bodyHeight - 5),
        _paint,
      );
    }

    canvas.restore();
  }
}

class _LEDLegsNode extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => const Size(LEDPainter.width, LEDPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    _paint.strokeWidth = 4;
    _paint.strokeCap = StrokeCap.round;
    _paint.color = PartPalette.grey400;
    _paint.style = PaintingStyle.stroke;

    const leftLegX = LEDPainter.leftLegX;
    const rightLegX = LEDPainter.rightLegX;

    // Legs extend up into the transparent LED dome to simulate the internal anvil/post
    const startY = LEDPainter.bodyHeight * 0.45;

    // Both leads end on the connection lattice, one hole pitch apart.
    const legEndY = LEDPainter.legTipY;

    // The posts inside the dome sit closer together than the leads do, and
    // each kinks out to its own lead column just below the plastic.
    //
    // Both sides do this. Only the anode used to, which left the pair of posts
    // showing through the lens off-centre by half their inset — enough that
    // the whole part read as leaning, even though its ink is centred to the
    // pixel and its legs land on the lattice either side of the middle.
    const postInset = 5.0;
    const bendStartY = LEDPainter.bodyHeight - 6.0; // Bends just inside the plastic
    const bendEndY = LEDPainter.bodyHeight + 4.0; // Finishes bending outside

    Path leg(double postX, double leadX) => Path()
      ..moveTo(postX, startY)
      ..lineTo(postX, bendStartY)
      ..lineTo(leadX, bendEndY)
      ..lineTo(leadX, legEndY);

    canvas.drawPath(leg(leftLegX + postInset, leftLegX), _paint);
    canvas.drawPath(leg(rightLegX - postInset, rightLegX), _paint);

    canvas.restore();
  }
}
