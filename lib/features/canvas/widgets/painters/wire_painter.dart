import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../utils/canvas_geometry.dart';
import 'wire_flow.dart';

class WirePainter extends CustomPainter {
  final List<WireModel> wires;
  final List<ComponentInstance> nodes;
  final PortLocation? pendingStart;
  final Offset? pendingEndMouse;
  final PortLocation? hoveredPort;
  final String? hoveredWireId;
  final List<String> selectedWireIds;
  final Color pendingColor;
  final Color selectionColor;
  final List<Offset> pendingBendPoints;

  /// Whether the wire in flight is an existing wire having one end moved,
  /// rather than a brand-new wire being drawn. It's still the wire the user
  /// selected — it just can't live in the wire list while one of its ends is
  /// off a port — so it is drawn the way a selected wire is drawn: full
  /// strength, selection outline, handles on every point.
  final bool isMovingExistingWire;

  final bool isSimulating;

  /// Solved current (amps) per wire id, signed so a positive value runs from the
  /// wire's `start` port to its `end`. Held as a listenable rather than a plain
  /// map so a new solve repaints this painter without rebuilding the canvas.
  final ValueListenable<Map<String, double>>? currents;

  /// Monotonic seconds driving the dot travel. See [WireFlowClock].
  final ValueListenable<double>? flowClock;

  // Pre-allocated paint objects — never allocated inside paint().
  static const _maskFilter = MaskFilter.blur(BlurStyle.normal, 5);

  static final _flowGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final _flowDotPaint = Paint()..style = PaintingStyle.fill;

  static final _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round;

  static final _outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7.0
    ..strokeCap = StrokeCap.round;

  static final _handleFillPaint = Paint()
    ..color = AppPalette.white
    ..style = PaintingStyle.fill;

  static final _hoverGlowPaint = Paint()
    ..color = AppPalette.white
    ..style = PaintingStyle.fill
    ..maskFilter = _maskFilter;

  static final _hoverBorderPaint = Paint()
    ..color = AppPalette.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  WirePainter({
    required this.wires,
    required this.nodes,
    this.pendingStart,
    this.pendingEndMouse,
    this.hoveredPort,
    this.hoveredWireId,
    this.selectedWireIds = const [],
    this.selectionColor = AppPalette.blue,
    this.pendingColor = AppPalette.yellow,
    this.pendingBendPoints = const [],
    this.isMovingExistingWire = false,
    this.isSimulating = false,
    this.currents,
    this.flowClock,
  }) : super(repaint: Listenable.merge([currents, flowClock]));

  @override
  void paint(Canvas canvas, Size size) {
    final flow = isSimulating ? currents?.value : null;
    final clock = flowClock?.value ?? 0;

    // Draw established wires
    for (final wire in wires) {
      final startPos = _getPortPosition(wire.start);
      final endPos = _getPortPosition(wire.end);

      if (startPos != null && endPos != null) {
        final isHovered = wire.id == hoveredWireId;
        final isSelected = selectedWireIds.contains(wire.id);
        final highlighted = isSelected || isHovered;

        final allPoints = _wirePoints(wire, startPos, endPos);

        // Current runs *under* the wire: the halo reads as the wire glowing,
        // and the dots on top read as travelling along it rather than beside it.
        final amps = flow == null ? 0.0 : (flow[wire.id] ?? 0.0);
        final intensity = WireFlow.intensity(amps);
        if (intensity > 0) {
          _flowGlowPaint
            ..color = WireFlow.dotColor(
              intensity,
            ).withValues(alpha: WireFlow.glowOpacity(intensity))
            ..strokeWidth = WireFlow.glowWidth(intensity)
            ..maskFilter = _maskFilter;
          _drawPolyline(canvas, allPoints, _flowGlowPaint, false);
        }

        _linePaint.color = wire.color;
        _linePaint.strokeWidth = highlighted ? 4.0 : 3.0;
        _drawPolyline(canvas, allPoints, _linePaint, highlighted);

        if (intensity > 0) {
          _drawFlowDots(canvas, allPoints, amps, intensity, clock);
        }

        if (isSelected) {
          _drawHandles(canvas, allPoints, wire.color);
        }
      }
    }

    // Draw pending wire — either a new one being drawn, or an existing one
    // with an end in hand. The second keeps looking like the selected wire it
    // is: dragging an end should feel no different from dragging a bend, and
    // the handles are what tell you where the rest of the wire is pinned while
    // you move one point of it.
    if (pendingStart != null && pendingEndMouse != null) {
      final startPos = _getPortPosition(pendingStart!);
      if (startPos != null) {
        final points = [startPos, ...pendingBendPoints, pendingEndMouse!];
        _linePaint.color = isMovingExistingWire
            ? pendingColor
            : pendingColor.withValues(alpha: 0.7);
        _linePaint.strokeWidth = isMovingExistingWire ? 4.0 : 3.0;
        _drawPolyline(canvas, points, _linePaint, isMovingExistingWire);
        _drawHandles(canvas, points, pendingColor);
      }
    }

    // Draw hovered port indicator
    if (hoveredPort != null) {
      final portPos = _getPortPosition(hoveredPort!);
      if (portPos != null) {
        canvas.drawCircle(portPos, 8, _hoverGlowPaint);
        canvas.drawCircle(portPos, 4, _hoverBorderPaint);
      }
    }
  }

  // The literal points of the wire: start, its real bend points, end. No
  // corners are invented — not here, and not when the wire is created either
  // (see `WiringManager.completeWiring`). Both used to, which meant a wire
  // could show a bend its own `bendPoints` — and its `.cdl` — didn't have.
  List<Offset> _wirePoints(WireModel wire, Offset start, Offset end) => [
    start,
    ...wire.bendPoints,
    end,
  ];

  Offset? _getPortPosition(PortLocation loc) => CanvasGeometry.getPortPosition(loc, nodes);

  void _drawPolyline(Canvas canvas, List<Offset> allPoints, Paint paint, bool highlighted) {
    if (allPoints.length <= 2) {
      canvas.drawLine(allPoints.first, allPoints.last, paint);
      if (highlighted) {
        _outlinePaint.color = selectionColor;
        canvas.drawLine(allPoints.first, allPoints.last, _outlinePaint);
        canvas.drawLine(allPoints.first, allPoints.last, paint);
      }
      return;
    }

    final path = Path();
    const preferredRadius = 12.0;

    path.moveTo(allPoints[0].dx, allPoints[0].dy);

    for (var i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1];
      final curr = allPoints[i];
      final next = allPoints[i + 1];

      final vPrev = prev - curr;
      final vNext = next - curr;

      final dPrev = vPrev.distance;
      final dNext = vNext.distance;

      if (dPrev == 0 || dNext == 0) continue;

      var radius = preferredRadius;
      if (dPrev < radius * 2) radius = dPrev / 2;
      if (dNext < radius * 2) radius = dNext / 2;

      final entry = curr + (vPrev / dPrev) * radius;
      final exit = curr + (vNext / dNext) * radius;

      path.lineTo(entry.dx, entry.dy);
      path.quadraticBezierTo(curr.dx, curr.dy, exit.dx, exit.dy);
    }

    path.lineTo(allPoints.last.dx, allPoints.last.dy);

    if (highlighted) {
      _outlinePaint.color = selectionColor;
      canvas.drawPath(path, _outlinePaint);
    }

    canvas.drawPath(path, paint);
  }

  /// Walks evenly-spaced dots along [points] and draws one at each.
  ///
  /// Deliberately measured on the raw polyline rather than on the rounded
  /// [Path] the wire is stroked from: extracting `PathMetrics` for every wire
  /// on every frame is far more expensive than this, and the only difference is
  /// that a dot cuts a corner by up to the 12 px corner radius.
  ///
  /// A negative [amps] means the wire carries current from its `end` port back
  /// to its `start`, so the dots run the other way.
  void _drawFlowDots(
    Canvas canvas,
    List<Offset> points,
    double amps,
    double intensity,
    double clock,
  ) {
    const spacing = WireFlow.dotSpacing;
    final travelled = (clock * WireFlow.speed(intensity)) % spacing;
    // Reversed flow counts down instead of up, which walks the dots backwards
    // along the same distances.
    var distance = amps < 0 ? spacing - travelled : travelled;

    _flowDotPaint.color = WireFlow.dotColor(
      intensity,
    ).withValues(alpha: WireFlow.dotOpacity(intensity));
    final radius = WireFlow.dotRadius(intensity);

    var segment = 0;
    var segmentStart = 0.0;
    var segmentLength = (points[1] - points[0]).distance;

    while (true) {
      while (distance >= segmentStart + segmentLength) {
        segmentStart += segmentLength;
        segment++;
        if (segment >= points.length - 1) return;
        segmentLength = (points[segment + 1] - points[segment]).distance;
      }
      // The loop above always steps past a zero-length segment (two bend points
      // on the same spot), so the division below is safe.
      canvas.drawCircle(
        Offset.lerp(
          points[segment],
          points[segment + 1],
          (distance - segmentStart) / segmentLength,
        )!,
        radius,
        _flowDotPaint,
      );
      distance += spacing;
    }
  }

  void _drawHandles(Canvas canvas, List<Offset> points, Color color) {
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final point in points) {
      canvas.drawCircle(point, 3.5, _handleFillPaint);
      canvas.drawCircle(point, 3.5, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WirePainter oldDelegate) =>
      !identical(wires, oldDelegate.wires) ||
      !identical(nodes, oldDelegate.nodes) ||
      pendingStart != oldDelegate.pendingStart ||
      pendingEndMouse != oldDelegate.pendingEndMouse ||
      hoveredPort != oldDelegate.hoveredPort ||
      hoveredWireId != oldDelegate.hoveredWireId ||
      selectedWireIds != oldDelegate.selectedWireIds ||
      pendingColor != oldDelegate.pendingColor ||
      selectionColor != oldDelegate.selectionColor ||
      !identical(pendingBendPoints, oldDelegate.pendingBendPoints) ||
      isMovingExistingWire != oldDelegate.isMovingExistingWire ||
      isSimulating != oldDelegate.isSimulating ||
      // Only matters when the listenables themselves are swapped; their own
      // notifications already drive repaints through [repaint].
      !identical(currents, oldDelegate.currents) ||
      !identical(flowClock, oldDelegate.flowClock);
}
