import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/paint_node.dart';
import '../resistor_calculator.dart';
import '../painting/base_component_painter.dart';
import 'parts/component_legs_node.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';

/// Draws a resistor, with colour bands derived from its `Resistance` value
/// (see `ResistorCalculator`). Provides `left`/`right` ports.
class ResistorPainter extends BaseComponentPainter with PortProvider, PaintTreeComponent {
  final Map<String, dynamic>? properties;

  ResistorPainter({this.properties, super.isOutline});

  String get resistanceString => (properties?[ComponentProps.resistance] ?? '220').toString();
  double get resistance => ResistorCalculator.parseResistanceValue(resistanceString) ?? 220.0;

  double get tolerance {
    final t = properties?['tolerance'];
    if (t is double) return t;
    if (t is String) return double.tryParse(t) ?? 5.0;
    if (t is int) return t.toDouble();
    return 5.0;
  }

  int get bandCount {
    final b = properties?['bandCount'];
    if (b is int) return b;
    if (b is String) return int.tryParse(b) ?? 4;
    return 4;
  }

  static const double gridCellSize = GridSystem.cellSize;
  static const double gridCellCenter = GridSystem.cellCenter;

  // Axial resistor body, leads excluded. Real ¼ W is 6.3 × 2.3 mm; drawn a
  // little slimmer so the colour bands read cleanly at canvas scale.
  static const bodyWidthMm = 6.3;
  static const bodyHeightMm = 1.6;

  static const bodyWidth = bodyWidthMm * PhysicalScale.pxPerMm;
  static const bodyHeight = bodyHeightMm * PhysicalScale.pxPerMm;

  // Leads 3 hole pitches apart on the connection lattice (7.62 mm — how a
  // ¼ W resistor is bent to straddle a breadboard), with the body centred
  // between them; height keeps the leg row (height/2) on the lattice too
  // (≡ cellCenter mod pitch).
  static const width = GridSystem.pitch * 3 + GridSystem.cellCenter * 2;
  static const height = GridSystem.pitch * 2 + GridSystem.cellCenter * 2;

  static const bandWidth = 3.0;

  static const componentSize = Size(width, height);

  /// The barrel, centred between the leads. Everything above and below it is
  /// air — a resistor straddling a breadboard leaves whole rows of holes
  /// inside its bounds that should stay hoverable.
  @override
  Rect bodyRect(Size size) =>
      Rect.fromCenter(center: size.center(Offset.zero), width: bodyWidth, height: bodyHeight);

  @override
  List<ComponentPort> getPorts() {
    const centerY = height / 2;
    const leftLegX = gridCellCenter;
    const rightLegX = width - gridCellCenter;

    return [
      const ComponentPort(id: 'left', name: 'Left Leg', localOffset: Offset(leftLegX, centerY)),
      const ComponentPort(id: 'right', name: 'Right Leg', localOffset: Offset(rightLegX, centerY)),
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
              const Offset(ResistorPainter.gridCellCenter, height / 2),
              const Offset(width - ResistorPainter.gridCellCenter, height / 2),
            ),
          ],
        ),
      ),
      CanvasPositioned(left: 0, top: 0, child: _ResistorBodyNode(this)),
    ],
  );

  @override
  bool shouldRepaintComponent(covariant ResistorPainter oldDelegate) =>
      oldDelegate.resistanceString != resistanceString ||
      oldDelegate.tolerance != tolerance ||
      oldDelegate.bandCount != bandCount;
}

class _ResistorBodyNode extends PaintNode {
  final ResistorPainter painter;
  final _paint = Paint();

  _ResistorBodyNode(this.painter);

  @override
  Size get size => const Size(ResistorPainter.width, ResistorPainter.height);

  @override
  void paint(Canvas canvas, Offset offset) {
    const center = Offset(ResistorPainter.width / 2, ResistorPainter.height / 2);

    canvas.save();
    canvas.translate(offset.dx + center.dx, offset.dy + center.dy);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: ResistorPainter.bodyWidth,
      height: ResistorPainter.bodyHeight,
    );
    final bodyRRect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Main body (Tan/Beige)
    _paint.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFE6D5B8), // Highlight
        Color(0xFFB89B77), // Shadow
      ],
    ).createShader(rect);

    canvas.drawRRect(bodyRRect, _paint);
    _paint.shader = null;

    _drawBands(canvas, bodyRRect);

    canvas.restore();
  }

  void _drawBands(Canvas canvas, RRect bodyRRect) {
    canvas.save();
    canvas.clipRRect(bodyRRect);

    final bands = ResistorCalculator.getBandColors(
      painter.resistance,
      bandCount: painter.bandCount,
      tolerance: painter.tolerance,
    );

    final bandCount = bands.length;
    const startX = -ResistorPainter.bodyWidth / 2 + 6.0;

    // Tolerance band (last band) is positioned slightly apart at the end
    const lastBandX = ResistorPainter.bodyWidth / 2 - 6.0 - ResistorPainter.bandWidth;

    if (bandCount > 0) {
      if (bandCount == 1) {
        _drawBand(canvas, 0 - ResistorPainter.bandWidth / 2, bands[0]);
      } else {
        final regularBands = bandCount - 1;
        const spacing = 6.0; // Keep bands close to each other

        for (var i = 0; i < regularBands; i++) {
          _drawBand(canvas, startX + (i * spacing), bands[i]);
        }
        // Draw tolerance band
        _drawBand(canvas, lastBandX, bands.last);
      }
    }

    canvas.restore();
  }

  void _drawBand(Canvas canvas, double x, Color color) {
    _paint.color = color;
    _paint.style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        x.roundToDouble(),
        -ResistorPainter.bodyHeight / 2,
        ResistorPainter.bandWidth,
        ResistorPainter.bodyHeight,
      ),
      _paint,
    );
  }
}
