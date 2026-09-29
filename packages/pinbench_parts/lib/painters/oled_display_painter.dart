import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../logic/ssd1306.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/base_component_painter.dart';
import '../painting/grid_system.dart';
import '../painting/paint_node.dart';
import '../painting/painter_text_styles.dart';
import '../painting/physical_scale.dart';
import '../painting/port_provider.dart';
import 'parts/component_legs_node.dart';

/// Draws a 0.96" SSD1306 OLED module, showing whatever the sketch has actually
/// written into the display's graphics RAM.
///
/// Every other painter here draws a *quantity* — an angle, a brightness, a
/// pressed leg. This one draws 8192 individually addressed pixels, which is
/// why it reads its state through [Ssd1306Controller] rather than off a
/// property: the protocol decoding belongs with the protocol, and this file
/// only has to turn "is this pixel lit" into ink.
///
/// Drawn at true scale like everything else, and that is worth knowing before
/// wondering why the text is small: the real panel's active area is
/// 21.74 × 10.86 mm, so its 128 columns land just over one canvas pixel apart
/// at 100 % zoom. A real 0.96" display is genuinely this tiny next to the
/// breadboard it sits on.
class OledDisplayPainter({final Map<String, dynamic>? properties, super.isOutline})
    extends BaseComponentPainter
    with PortProvider, PaintTreeComponent {
  // --- The module ----------------------------------------------------------

  /// The blue 4-pin module every "OLED tutorial" search returns: 27.3 × 27.8 mm
  /// of PCB with the glass filling most of it.
  static const pcbWidthMm = 27.3;
  static const pcbHeightMm = 27.8;

  static const pcbWidth = pcbWidthMm * PhysicalScale.pxPerMm;
  static const pcbHeight = pcbHeightMm * PhysicalScale.pxPerMm;

  /// Header pins, one hole pitch apart, on the connection lattice.
  ///
  /// The lattice fixes where the pins may sit and the real PCB fixes how wide
  /// it is, and the two do not have to agree — so the *board* moves to centre
  /// itself on the pins rather than the pins drifting off the lattice to
  /// centre themselves on the board. That leaves a sliver of empty box to the
  /// left of the PCB, which [bodyRect] excludes from the part's hit area.
  static const pinCount = 4;
  static const firstPinX = GridSystem.pitch * 4 + GridSystem.cellCenter;
  static const lastPinX = firstPinX + GridSystem.pitch * (pinCount - 1);
  static const pcbLeft = (firstPinX + lastPinX) / 2 - pcbWidth / 2;

  static const width = pcbLeft + pcbWidth;

  /// Rounded up to the next lattice row past the PCB, which leaves the header
  /// pins the ~4 mm of exposed lead they really have.
  static const height = GridSystem.pitch * 12 + GridSystem.cellSize;

  static const componentSize = Size(width, height);

  static const _pinY = height - GridSystem.cellCenter;

  /// The panel glass: a dark slab covering the top two thirds of the board.
  static const glassWidth = 26.0 * PhysicalScale.pxPerMm;
  static const glassHeight = 19.3 * PhysicalScale.pxPerMm;
  static const glassTop = 1.0 * PhysicalScale.pxPerMm;
  static const glassLeft = pcbLeft + (pcbWidth - glassWidth) / 2;

  /// The lit area inside the glass — 128 × 64 pixels across 21.74 × 10.86 mm.
  static const activeWidth = 21.74 * PhysicalScale.pxPerMm;
  static const activeHeight = 10.86 * PhysicalScale.pxPerMm;
  static const activeLeft = glassLeft + (glassWidth - activeWidth) / 2;
  static const activeTop = glassTop + (glassHeight - activeHeight) / 2;

  static const _pixelWidth = activeWidth / Ssd1306Controller.width;
  static const _pixelHeight = activeHeight / Ssd1306Controller.height;

  /// The panel colours modules are sold in.
  static const _pixelColors = {
    'White': Color(0xFFEAF6FF),
    'Blue': Color(0xFF4FC3F7),
    'Yellow': Color(0xFFFFD54F),
  };

  static const _defaultPixelColor = Color(0xFFEAF6FF);

  /// The packed controller state the simulation last wrote, or null before a
  /// run has said anything to this display.
  String? get frame => properties?[ComponentProps.oledFrame] as String?;

  Color get pixelColor =>
      _pixelColors[properties?[ComponentProps.pixelColor]?.toString()] ?? _defaultPixelColor;

  @override
  List<ComponentPort> getPorts() => const [
    ComponentPort(id: 'GND', name: 'Ground', localOffset: Offset(firstPinX, _pinY)),
    ComponentPort(
      id: 'VCC',
      name: 'Supply (3.3–5 V)',
      localOffset: Offset(firstPinX + GridSystem.pitch, _pinY),
    ),
    ComponentPort(
      id: 'SCL',
      name: 'I²C clock (A5)',
      localOffset: Offset(firstPinX + GridSystem.pitch * 2, _pinY),
    ),
    ComponentPort(
      id: 'SDA',
      name: 'I²C data (A4)',
      localOffset: Offset(firstPinX + GridSystem.pitch * 3, _pinY),
    ),
  ];

  @override
  Rect? bodyRect(Size size) => const Rect.fromLTWH(pcbLeft, 0, pcbWidth, pcbHeight);

  @override
  PaintNode buildTree() => CanvasStack(
    size: componentSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: _OledBodyNode(this)),
      CanvasPositioned(
        left: 0,
        top: 0,
        child: ComponentLegsNode(
          componentSize: componentSize,
          legs: [
            for (var i = 0; i < pinCount; i++)
              (
                Offset(firstPinX + GridSystem.pitch * i, pcbHeight - 8.0),
                Offset(firstPinX + GridSystem.pitch * i, _pinY),
              ),
          ],
        ),
      ),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant OledDisplayPainter oldDelegate) =>
      !identical(this, oldDelegate) &&
      (oldDelegate.frame != frame || oldDelegate.pixelColor != pixelColor);
}

class _OledBodyNode(final OledDisplayPainter painter) extends PaintNode {
  final _paint = Paint();

  @override
  Size get size => OledDisplayPainter.componentSize;

  static final _pinLabel = PainterTextStyles.readout.copyWith(fontSize: 8);

  /// Above this many lit runs the glow pass is skipped. A screen that full is
  /// a bitmap rather than text, where the glow adds nothing but a second few
  /// hundred blurred rectangles per repaint.
  static const _glowRunLimit = 400;

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    const w = OledDisplayPainter.pcbWidth;
    const h = OledDisplayPainter.pcbHeight;
    const left = OledDisplayPainter.pcbLeft;

    // PCB: the deep blue these modules are almost always sold on.
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF12386B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(left, 0, w, h), const Radius.circular(5.0)),
      _paint,
    );

    _drawMountingHoles(canvas);
    _drawGlass(canvas);
    _drawPixels(canvas);
    _drawSilkscreen(canvas);
    _drawHeader(canvas);

    canvas.restore();
  }

  void _drawMountingHoles(Canvas canvas) {
    const inset = 1.9 * PhysicalScale.pxPerMm;
    const radius = 0.8 * PhysicalScale.pxPerMm;
    const left = OledDisplayPainter.pcbLeft;
    const right = left + OledDisplayPainter.pcbWidth;
    const bottom = OledDisplayPainter.pcbHeight;

    for (final center in const [
      Offset(left + inset, inset),
      Offset(right - inset, inset),
      Offset(left + inset, bottom - inset),
      Offset(right - inset, bottom - inset),
    ]) {
      _paint.color = const Color(0xFFC9D4E0);
      canvas.drawCircle(center, radius, _paint);
      _paint.color = const Color(0xFF0A1F3D);
      canvas.drawCircle(center, radius * 0.55, _paint);
    }
  }

  void _drawGlass(Canvas canvas) {
    const glass = Rect.fromLTWH(
      OledDisplayPainter.glassLeft,
      OledDisplayPainter.glassTop,
      OledDisplayPainter.glassWidth,
      OledDisplayPainter.glassHeight,
    );

    // The glass itself is never pure black — it catches a little light even
    // switched off, which is what stops the part reading as a hole in the PCB.
    _paint
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF14161C), Color(0xFF0A0B0F)],
      ).createShader(glass);
    canvas.drawRRect(RRect.fromRectAndRadius(glass, const Radius.circular(2.0)), _paint);
    _paint.shader = null;

    // The border of the active area, visible on the real panel as the edge of
    // the polariser.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF1E212A);
    canvas.drawRect(
      const Rect.fromLTWH(
        OledDisplayPainter.activeLeft,
        OledDisplayPainter.activeTop,
        OledDisplayPainter.activeWidth,
        OledDisplayPainter.activeHeight,
      ),
      _paint,
    );
    _paint.style = PaintingStyle.fill;
  }

  /// Draws the lit pixels, merging each row's consecutive ones into a single
  /// rectangle.
  ///
  /// A 128 × 64 panel is 8192 pixels and repaints whenever the sketch redraws,
  /// so one `drawRect` per pixel would be 8192 calls a frame. Text — which is
  /// what a display is nearly always showing — collapses into a few hundred
  /// horizontal runs instead.
  void _drawPixels(Canvas canvas) {
    final controller = Ssd1306Controller.unpack(painter.frame);
    if (!controller.displayOn) return;

    final runs = <Rect>[];
    for (var y = 0; y < Ssd1306Controller.height; y++) {
      var runStart = -1;
      for (var x = 0; x <= Ssd1306Controller.width; x++) {
        final lit = x < Ssd1306Controller.width && controller.pixelAt(x, y);
        if (lit) {
          if (runStart < 0) runStart = x;
          continue;
        }
        if (runStart < 0) continue;
        runs.add(
          Rect.fromLTWH(
            OledDisplayPainter.activeLeft + runStart * OledDisplayPainter._pixelWidth,
            OledDisplayPainter.activeTop + y * OledDisplayPainter._pixelHeight,
            (x - runStart) * OledDisplayPainter._pixelWidth,
            OledDisplayPainter._pixelHeight,
          ),
        );
        runStart = -1;
      }
    }
    if (runs.isEmpty) return;

    // Contrast is drawn as opacity, which is what it looks like on the panel.
    final alpha = 0.45 + 0.55 * (controller.contrast / 255);
    final color = painter.pixelColor;

    if (runs.length <= _glowRunLimit) {
      _paint
        ..color = color.withValues(alpha: alpha * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      for (final run in runs) {
        canvas.drawRect(run, _paint);
      }
      _paint.maskFilter = null;
    }

    _paint.color = color.withValues(alpha: alpha);
    for (final run in runs) {
      canvas.drawRect(run, _paint);
    }
  }

  /// The module's marking, on the free board to the right of the header.
  ///
  /// Not centred under the glass, which is where a silkscreen line would
  /// naturally go: that strip is the only room the pin labels have, and a name
  /// nobody needs must not crowd out four labels that decide whether the thing
  /// gets wired up correctly.
  void _drawSilkscreen(Canvas canvas) {
    final text = TextPainter(
      text: const TextSpan(
        text: 'OLED',
        style: TextStyle(color: Color(0x90FFFFFF), fontSize: 7, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const right = OledDisplayPainter.pcbLeft + OledDisplayPainter.pcbWidth;
    const available = right - (OledDisplayPainter.lastPinX + GridSystem.pitch / 2);
    // A wider font than expected: drop the marking rather than let it overlap
    // the pins or run off the board.
    if (text.width > available) return;

    text.paint(
      canvas,
      Offset(
        OledDisplayPainter.lastPinX + GridSystem.pitch / 2 + (available - text.width) / 2,
        OledDisplayPainter.pcbHeight - 3.4 * PhysicalScale.pxPerMm,
      ),
    );
  }

  void _drawHeader(Canvas canvas) {
    const headerHeight = 2.5 * PhysicalScale.pxPerMm;
    const headerTop = OledDisplayPainter.pcbHeight - headerHeight;

    _paint.color = const Color(0xFF1A1A1A);
    canvas.drawRect(
      const Rect.fromLTRB(
        OledDisplayPainter.firstPinX - GridSystem.cellCenter - 4,
        headerTop,
        OledDisplayPainter.lastPinX + GridSystem.cellCenter + 4,
        OledDisplayPainter.pcbHeight,
      ),
      _paint,
    );

    // Turned on their side, reading bottom to top.
    //
    // There is one hole pitch between pins — 2.54 mm — and `GND` set in a
    // legible size is wider than that, so four horizontal labels collide into
    // a single grey smear at any size worth reading. Rotated, each costs its
    // *height* across the header and spends its length running up the free
    // board under the glass, where there is room to spare. Real modules with a
    // tight header print them this way for the same reason.
    final label = TextPainter(textDirection: TextDirection.ltr);
    const names = ['GND', 'VCC', 'SCL', 'SDA'];
    for (var i = 0; i < names.length; i++) {
      label
        // A size down from the shared readout style: rotated labels run *up*
        // the board, and the strip between the header and the glass is only a
        // few millimetres of it.
        ..text = TextSpan(text: names[i], style: _pinLabel)
        ..layout();

      canvas.save();
      canvas.translate(
        OledDisplayPainter.firstPinX + GridSystem.pitch * i + label.height / 2,
        headerTop - 3.0,
      );
      canvas.rotate(-math.pi / 2);
      label.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }
}
