import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/base_component_painter.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';
import '../painting/part_palette.dart';

/// Draws a 3-terminal rotary potentiometer: a round trimmer body (blue rim,
/// dark dial face with tick marks and a pointer) with three legs exiting the
/// bottom. Terminals `term1`/`term2` are the resistive-track ends; `wiper` is
/// the centre tap. Wiring term1→5 V, term2→GND and wiper→an analog pin makes
/// `analogRead` return `position × 5 V`.
class PotentiometerPainter extends BaseComponentPainter with PortProvider {
  final Map<String, dynamic>? properties;

  PotentiometerPainter({this.properties, super.isOutline});

  /// Wiper position clamped to 0.0–1.0 (defaults to mid-travel).
  double get position {
    final v = properties?[ComponentProps.potentiometerValue];
    if (v is num) return v.toDouble().clamp(0.0, 1.0);
    if (v is String) return (double.tryParse(v) ?? 0.5).clamp(0.0, 1.0);
    return 0.5;
  }

  // WH148 / B10K rotary pot, shaft excluded. The real body is 16 × 17 mm;
  // drawn slightly smaller so it does not dwarf the parts around it.
  static const bodyWidthMm = 13.0;
  static const bodyHeightMm = 14.0;
  static const bodyWidth = bodyWidthMm * PhysicalScale.pxPerMm;
  static const bodyHeight = bodyHeightMm * PhysicalScale.pxPerMm;

  // Bounds hold the round body plus the leg run down to the port row.
  static const width = GridSystem.pitch * 6 + GridSystem.cellSize; // 104
  static const height = GridSystem.pitch * 7 + GridSystem.cellSize; // 120
  static const componentSize = Size(width, height);

  static const _cellStep = GridSystem.pitch; // breadboard hole pitch

  // Leg X positions. The three legs are spaced one breadboard-hole pitch
  // apart and sit on the connection lattice (≡ cellCenter mod pitch), exactly
  // like the LED's legs — so when the part snaps to the grid all three land on
  // adjacent breadboard holes. The body is centred on the middle (wiper) leg.
  static const _wiperPortX = width / 2; // 52 — ≡ 4 mod 16, body centre
  static const _leftLegX = _wiperPortX - _cellStep; // 36
  static const _rightLegX = _wiperPortX + _cellStep; // 68

  // Port row Y. Connection points live on the shared lattice (≡ cellCenter
  // mod pitch); the port must sit on it too, otherwise leg tips land
  // permanently off every hole.
  static const _portY = GridSystem.pitch * 6 + GridSystem.cellCenter; // 116

  // Round body geometry, centred on the wiper leg. The legs are drawn from
  // _legTop (up inside the body) down to the port row, then the body is painted
  // on top — so the round rim hides the legs' upper ends and they appear to
  // emerge from underneath it, even the outer two.
  //
  // The trimmer is drawn face-on: the 16 mm body width is the bezel diameter,
  // and the extra millimetre of the 17 mm height is the collar the legs leave
  // through, below the bezel.
  static const _bezelR = bodyWidth / 2; // dark slate bezel (fills the body)
  static const _center = Offset(_wiperPortX, _bezelR);
  static const _dotRingR = _bezelR * 0.85; // outer ring: the mounting dots
  static const _dialR = _bezelR * 0.62; // light dial face
  static const _legTop = _bezelR; // legs start up under the body

  /// Collar under the bezel the legs leave through — the millimetre by which
  /// the 17 mm body is taller than it is wide.
  static const _collarRect = Rect.fromLTRB(
    _wiperPortX - _cellStep * 1.4,
    _bezelR,
    _wiperPortX + _cellStep * 1.4,
    bodyHeight,
  );

  // Body colours, tuned to the trimmer reference (dark slate bezel, blue dial).
  static const _bezelColor = Color(0xFF37444F);
  static const _dotColor = Color(0xFF5C7C9C);
  static const _dialColor = Color(0xFF7E9FC4);
  static const _tickColor = Color(0xFF6E8CB0);
  static const _pointerColor = Color(0xFF2A3744);

  // Knob sweep: 270° centred on 12 o'clock.
  static const _sweep = 1.5 * math.pi;
  static const _startAngle = -0.75 * math.pi;

  @override
  /// The bezel and its collar, centred on the wiper leg — not the leg run
  /// below them, which [BaseComponentPainter.hitArea] adds from the ports.
  @override
  Rect bodyRect(Size size) =>
      const Rect.fromLTWH(_wiperPortX - bodyWidth / 2, 0, bodyWidth, bodyHeight);

  @override
  List<ComponentPort> getPorts() => const [
    ComponentPort(id: 'term1', name: 'Terminal 1', localOffset: Offset(_leftLegX, _portY)),
    ComponentPort(id: 'wiper', name: 'Wiper', localOffset: Offset(_wiperPortX, _portY)),
    ComponentPort(id: 'term2', name: 'Terminal 2', localOffset: Offset(_rightLegX, _portY)),
  ];

  @override
  void paintComponent(Canvas canvas, Size size) {
    final paint = Paint();

    // ── Legs (standard grey rounded style, matching other components) ──────
    final legPaint = Paint()
      ..color = PartPalette.grey400
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final port in getPorts()) {
      canvas.drawLine(Offset(port.localOffset.dx, _legTop), port.localOffset, legPaint);
    }

    paint.style = PaintingStyle.fill;

    // ── Dark slate bezel (fills the whole body) ─────────────────────────────
    paint.color = _bezelColor;
    canvas.drawRRect(RRect.fromRectAndRadius(_collarRect, const Radius.circular(4)), paint);
    canvas.drawCircle(_center, _bezelR, paint);

    // ── Outer ring of mounting dots ─────────────────────────────────────────
    paint.color = _dotColor;
    const dotCount = 8;
    for (var i = 0; i < dotCount; i++) {
      final a = (i / dotCount) * 2 * math.pi - math.pi / 2;
      final c = _center + Offset(math.cos(a), math.sin(a)) * (_dotRingR + 1);
      canvas.drawCircle(c, _bezelR * 0.070, paint);
    }

    // ── Light dial face ────────────────────────────────────────────────────
    paint.color = _dialColor;
    canvas.drawCircle(_center, _dialR, paint);

    // ── Inner tick ring just outside the dial (clears the dot ring) ─────────
    final tickPaint = Paint()
      ..color = _tickColor
      ..strokeWidth = _bezelR * 0.035
      ..strokeCap = StrokeCap.round;
    const tickCount = 48;
    const tickInner = _dialR + _bezelR * 0.06;
    const tickOuter = _dialR + _bezelR * 0.12;
    for (var i = 0; i < tickCount; i++) {
      final a = (i / tickCount) * 2 * math.pi - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(_center + dir * tickInner, _center + dir * tickOuter, tickPaint);
    }

    if (!isOutline) {
      // ── Tapered needle pointer ──────────────────────────────────────────
      // Maps 0→bottom-left, 0.5→top, 1→bottom-right (270° sweep from 12 o'clock).
      final angle = _startAngle + _sweep * position - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final perp = Offset(-dir.dy, dir.dx);
      const baseHalf = _bezelR * 0.13;
      final tip = _center + dir * (_dialR - _bezelR * 0.06);
      final p1 = _center + perp * baseHalf;
      final p2 = _center - perp * baseHalf;
      final needle = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      paint.color = _pointerColor;
      canvas.drawPath(needle, paint);
      canvas.drawCircle(_center, baseHalf, paint); // rounded hub
    }
  }

  @override
  bool shouldRepaintComponent(covariant PotentiometerPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.isOutline != isOutline;
}
