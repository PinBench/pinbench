import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../painting/base_component_painter.dart';
import 'arduino_painter/parts/arduino_smd_led.dart';
import 'parts/component_legs_node.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/painter_text_styles.dart';
import '../painting/part_palette.dart';
import '../models/part_properties.dart';

/// Draws a KY-037 microphone sound sensor, with its digital-out LED reflecting
/// `isDigitalHigh`. Exposes analog (`A0`) and digital (`D0`) output ports.
class Ky037MicSensorPainter({final Map<String, dynamic>? properties, super.isOutline})
    extends BaseComponentPainter
    with PortProvider, PaintTreeComponent {
  bool get isDigitalHigh => properties.flag(ComponentProps.isDigitalHigh);

  // KY-037 module: a real 36 × 15 mm board, drawn end-on with the mic capsule
  // at the top and the 4-pin header at the bottom — so the module's length
  // runs down the component and its 15 mm width across it. The length is drawn
  // at 34 mm, deliberately under the real 36, to sit better against its
  // neighbours.
  static const pcbWidthMm = 15.0;
  static const pcbLengthMm = 34.0;

  static const pcbWidth = pcbWidthMm * PhysicalScale.pxPerMm;
  static const pcbHeight = pcbLengthMm * PhysicalScale.pxPerMm;

  static const width = pcbWidth;
  // Rounded up to the next lattice row so the leg tips stay on it, which
  // leaves the header pins the ~3 mm of exposed lead they really have.
  static const height = GridSystem.pitch * 14 + GridSystem.cellSize;
  static const legsHeight = height - pcbHeight;

  // To align with breadboard holes, leg X coordinates sit on the connection
  // lattice (≡ cellCenter mod pitch), spaced one hole pitch apart.
  static const legA0X = GridSystem.pitch + GridSystem.cellCenter;
  static const legGX = legA0X + GridSystem.pitch;
  static const legPlusX = legGX + GridSystem.pitch;
  static const legD0X = legPlusX + GridSystem.pitch;

  static const componentSize = Size(width, height);

  @override
  List<ComponentPort> getPorts() {
    const bottomY = height - GridSystem.cellCenter;

    return [
      const ComponentPort(id: 'A0', name: 'Analog Out', localOffset: Offset(legA0X, bottomY)),
      const ComponentPort(id: 'G', name: 'Ground', localOffset: Offset(legGX, bottomY)),
      const ComponentPort(id: '+', name: 'VCC', localOffset: Offset(legPlusX, bottomY)),
      const ComponentPort(id: 'D0', name: 'Digital Out', localOffset: Offset(legD0X, bottomY)),
    ];
  }

  @override
  PaintNode buildTree() => CanvasStack(
    size: componentSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: _Ky037BodyNode(this)),
      CanvasPositioned(
        left: 0,
        top: 0,
        child: ComponentLegsNode(
          componentSize: componentSize,
          legs: [
            (
              const Offset(legA0X, pcbHeight - 8.0),
              const Offset(legA0X, height - GridSystem.cellCenter),
            ),
            (
              const Offset(legGX, pcbHeight - 8.0),
              const Offset(legGX, height - GridSystem.cellCenter),
            ),
            (
              const Offset(legPlusX, pcbHeight - 8.0),
              const Offset(legPlusX, height - GridSystem.cellCenter),
            ),
            (
              const Offset(legD0X, pcbHeight - 8.0),
              const Offset(legD0X, height - GridSystem.cellCenter),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant Ky037MicSensorPainter oldDelegate) =>
      !identical(this, oldDelegate) && (oldDelegate.isDigitalHigh != isDigitalHigh);
}

class _Ky037BodyNode(final Ky037MicSensorPainter painter) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => const Size(Ky037MicSensorPainter.width, Ky037MicSensorPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    // Simplified take on the real module: only the parts that read at canvas
    // scale — mic capsule up top, blue sensitivity trimmer, LM393 comparator,
    // the two SMD indicator LEDs, and the centre mounting hole.
    const w = Ky037MicSensorPainter.pcbWidth;
    const h = Ky037MicSensorPainter.pcbHeight;
    const centerX = w / 2;
    const margin = 1.5 * PhysicalScale.pxPerMm;

    // Mic drawn side-on: an upright Ø9.7 mm capsule cylinder standing proud
    // of the board's top edge, so the PCB itself starts a little lower.
    const pcbTop = 3.5 * PhysicalScale.pxPerMm;
    const capsuleWidth = 9.7 * PhysicalScale.pxPerMm;
    const capsuleCapHeight = 0.5 * PhysicalScale.pxPerMm;
    const capsuleBodyBottom = 8 * PhysicalScale.pxPerMm;
    const trimmerWidth = 6 * PhysicalScale.pxPerMm;
    const trimmerHeight = 9.5 * PhysicalScale.pxPerMm;
    const trimmerTop = 12.0 * PhysicalScale.pxPerMm;
    const icWidth = 5.0 * PhysicalScale.pxPerMm;
    const icHeight = 4.0 * PhysicalScale.pxPerMm;
    const icTop = 14.0 * PhysicalScale.pxPerMm;
    const ledWidth = 1.6 * PhysicalScale.pxPerMm;
    const ledHeight = 2.8 * PhysicalScale.pxPerMm;
    const ledTop = 25.0 * PhysicalScale.pxPerMm;
    const headerHeight = 2.5 * PhysicalScale.pxPerMm;

    // PCB body (bright red, rounded corners), top edge below the mic cap
    _paint.style = PaintingStyle.fill;
    _paint.color = const Color(0xFFD2333A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, pcbTop, w, h - pcbTop),
        const Radius.circular(6.0),
      ),
      _paint,
    );

    // Mic capsule, side view: dark cap over a silver cylinder body with
    // vertical highlights, standing proud of the board's top edge.
    const capsuleLeft = centerX - capsuleWidth / 2;
    const capsuleBodyRect = Rect.fromLTRB(
      capsuleLeft,
      capsuleCapHeight,
      capsuleLeft + capsuleWidth,
      capsuleBodyBottom,
    );
    // Polished-metal look: horizontal gradient with a bright centre highlight
    _paint.shader = const LinearGradient(
      colors: [
        Color(0xFF7E7E7E),
        Color(0xFFE8E8E8),
        Color(0xFFB6B6B6),
        Color(0xFFDCDCDC),
        Color(0xFF8A8A8A),
      ],
      stops: [0.0, 0.28, 0.5, 0.72, 1.0],
    ).createShader(capsuleBodyRect);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        capsuleBodyRect,
        bottomLeft: const Radius.circular(2.0),
        bottomRight: const Radius.circular(2.0),
      ),
      _paint,
    );
    _paint.shader = null;
    // Dark top cap, slightly wider than the body
    _paint.color = const Color(0xFF3A3A3A);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTRB(
          capsuleLeft + 2.0,
          0,
          capsuleLeft + capsuleWidth - 2.0,
          capsuleCapHeight,
        ),
        topLeft: const Radius.circular(2.0),
        topRight: const Radius.circular(2.0),
      ),
      _paint,
    );

    // Blue multiturn trimmer (3296-style, top view): lighter blue frame,
    // darker inner panel with the "W104" marking, brass slotted screw in
    // the bottom-left corner.
    const trimmerRect = Rect.fromLTWH(margin, trimmerTop, trimmerWidth, trimmerHeight);
    _paint.color = const Color(0xFF3F6FD8);
    canvas.drawRRect(RRect.fromRectAndRadius(trimmerRect, const Radius.circular(1.5)), _paint);
    _paint.color = const Color(0xFF1E4FB5);
    final trimmerPanel = Rect.fromLTRB(
      trimmerRect.left + 2.5,
      trimmerRect.top + 2.5,
      trimmerRect.right - 2.5,
      trimmerRect.bottom - trimmerWidth * 0.55,
    );
    // canvas.drawRect(trimmerPanel, _paint);
    final trimmerText = TextPainter(
      text: const TextSpan(
        text: 'W104',
        style: TextStyle(color: Color(0xB0FFFFFF), fontSize: 9, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(trimmerPanel.center.dx, trimmerPanel.center.dy);
    canvas.rotate(-1.5707963267948966);
    trimmerText.paint(canvas, Offset(-trimmerText.width / 2, -trimmerText.height / 2));
    canvas.restore();
    // Brass adjustment screw, bottom-left corner
    final screwCenter = Offset(
      trimmerRect.left + trimmerWidth * 0.32,
      trimmerRect.bottom - trimmerWidth * 0.30,
    );
    const screwRadius = trimmerWidth * 0.18;
    _paint.color = const Color(0xFFE0C048);
    canvas.drawCircle(screwCenter, screwRadius, _paint);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF9A7B1C);
    canvas.drawLine(
      screwCenter + const Offset(-screwRadius * 0.65, screwRadius * 0.65),
      screwCenter + const Offset(screwRadius * 0.65, -screwRadius * 0.65),
      _paint,
    );
    _paint.style = PaintingStyle.fill;

    // LM393 comparator: black body, silver pins out the top and bottom edges,
    // part label
    const icLeft = w - margin - icWidth;
    const icRect = Rect.fromLTWH(icLeft, icTop, icWidth, icHeight);
    _paint.color = const Color(0xFF9E9E9E);
    const icPin = 4.0;
    for (var i = 0; i < 4; i++) {
      final x = icLeft + icWidth * 0.12 + (i * icWidth * 0.24);
      canvas.drawRect(Rect.fromLTWH(x, icTop - icPin, icPin, icPin), _paint);
      canvas.drawRect(Rect.fromLTWH(x, icTop + icHeight, icPin, icPin), _paint);
    }
    _paint.color = const Color(0xFF1C1C1C);
    canvas.drawRRect(RRect.fromRectAndRadius(icRect, const Radius.circular(1.0)), _paint);
    final chipText = TextPainter(
      text: const TextSpan(
        text: 'LM393',
        style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 7),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    chipText.paint(canvas, icRect.center - Offset(chipText.width / 2, chipText.height / 2));

    // SMD LEDs reuse the Arduino board's SmdLedNode style (coloured package
    // body with brass solder pads at each end), rotated upright to match the
    // module. L2 (left) is the D0 indicator, L1 (right) is power (always on).
    void drawSmdLed(Offset center, Color emitter) {
      final node = SmdLedNode(label: '', ledColor: emitter, size: const Size(ledHeight, ledWidth));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(1.5707963267948966);
      node.paint(canvas, const Offset(-ledHeight / 2, -ledWidth / 2));
      canvas.restore();
    }

    const d0LedCenter = Offset(margin + ledWidth / 2, ledTop + ledHeight / 2);
    const powerLedCenter = Offset(w - margin - ledWidth / 2, ledTop + ledHeight / 2);

    drawSmdLed(powerLedCenter, PartPalette.white);

    if (painter.isDigitalHigh) {
      drawSmdLed(d0LedCenter, PartPalette.white);
      final glowPaint = Paint()
        ..color = PartPalette.redAccent.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(d0LedCenter, ledHeight, glowPaint);
    } else {
      drawSmdLed(d0LedCenter, PartPalette.white);
    }

    // Silkscreen labels beside the LEDs, running along the board like the
    // real module's "LED2"/"LED1" markings.
    void drawSilkscreen(String text, Offset center) {
      final silkText = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: PartPalette.white,
            fontSize: 6,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-1.5707963267948966);
      silkText.paint(canvas, Offset(-silkText.width / 2, -silkText.height / 2));
      canvas.restore();
    }

    drawSilkscreen('LED2', d0LedCenter + const Offset(ledWidth + 3.0, 0));
    drawSilkscreen('LED1', powerLedCenter - const Offset(ledWidth + 3.0, 0));

    // Centre mounting hole: white pad ring with a transparent-looking core.
    // Disabled — the hole reads as visual noise at canvas scale. Its geometry
    // lives here rather than with the other constants so it does not sit unused.
    // const holeCenterY = 27.5 * PhysicalScale.pxPerMm;
    // const holeRadius = 2.4 * PhysicalScale.pxPerMm;
    // _paint.color = const Color(0xFFF2F2F2);
    // canvas.drawCircle(const Offset(centerX, holeCenterY), holeRadius, _paint);
    // _paint.color = const Color(0xFF7A1F24); // darker board through the hole
    // canvas.drawCircle(const Offset(centerX, holeCenterY), holeRadius * 0.62, _paint);

    // Header pins plastic base (black)
    _paint.color = const Color(0xFF222222);
    canvas.drawRect(
      const Rect.fromLTRB(
        Ky037MicSensorPainter.legA0X - GridSystem.cellCenter - 4,
        h - headerHeight,
        Ky037MicSensorPainter.legD0X + GridSystem.cellCenter + 4,
        h,
      ),
      _paint,
    );

    // Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawLabel(String text, double x, double y) {
      textPainter.text = TextSpan(text: text, style: PainterTextStyles.readout);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y));
    }

    const labelY = h - headerHeight - 12.0;
    drawLabel('A0', Ky037MicSensorPainter.legA0X, labelY);
    drawLabel('G', Ky037MicSensorPainter.legGX, labelY);
    drawLabel('+', Ky037MicSensorPainter.legPlusX, labelY);
    drawLabel('D0', Ky037MicSensorPainter.legD0X, labelY);

    canvas.restore();
  }
}
