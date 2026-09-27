import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../painting/grid_system.dart';
import '../painting/physical_scale.dart';
import '../painting/base_component_painter.dart';
import '../painting/port_provider.dart';
import '../models/part_model.dart';
import '../models/port_model.dart';

/// Draws a hobby servo motor: a 3-pin connector (GND/VCC/Signal) with wires
/// running down behind a white cross-shaped control horn, over a blue gearbox
/// body with toothed gear circles, corner mounting tabs and a bottom cable
/// notch. Purely visual/wiring for now — no simulation behavior is wired up
/// (see `PartNames.servoMotor`).
class ServoMotorPainter extends BaseComponentPainter with PortProvider {
  final Map<String, dynamic>? properties;

  ServoMotorPainter({this.properties, super.isOutline});

  // SG90 hobby servo, drawn face-on: a real case is 22.8 × 12.2 × 28.5 mm, and
  // what faces the viewer here is the narrow 12.2 mm side, not the 22.8 mm one.
  // Drawn 12 × 24 against that real 12.2 × 28.5 face — a little under, so the
  // cross horn reads clearly overhanging it left and right.
  static const bodyWidthMm = 12.0;
  static const bodyHeightMm = 24.0;
  // The cross horn that ships with an SG90: a long axis of 32 mm and a short
  // one of 19 mm, so it reaches above the case but stays inside its width.
  static const hornLongMm = 32.0;
  static const hornShortMm = 19.0;

  static const bodyWidth = bodyWidthMm * PhysicalScale.pxPerMm;
  static const bodyHeight = bodyHeightMm * PhysicalScale.pxPerMm;
  static const hornLong = hornLongMm * PhysicalScale.pxPerMm;
  static const hornShort = hornShortMm * PhysicalScale.pxPerMm;

  // Bounds: the case plus the horn reaching past its top, and the lead plug
  // hanging below it, ending on the connection lattice.
  static const width = GridSystem.pitch * 10;
  static const height = GridSystem.pitch * 18 + GridSystem.cellCenter;
  static const componentSize = Size(width, height);

  // The whole servo is drawn on the middle pin's lattice line: pins must sit
  // on the shared connection lattice (≡ cellCenter mod pitch), which no
  // width/2 line can, so instead of offsetting the connector from the body we
  // shift the entire drawing half a cell right — body, horn and connector all
  // share one center line.
  static const _centerX = width / 2 + GridSystem.cellCenter;

  // Connector (bottom plug) geometry — sits under the body, pin holes facing
  // down toward the ports on the component's bottom edge, centered under the
  // body like the middle pin.
  static const _connectorW = 58.0;
  static const _connectorH = 48.0;
  static const _connectorRect = Rect.fromLTWH(
    _pinVccX - _connectorW / 2,
    height - _connectorH,
    _connectorW,
    _connectorH,
  );
  // Pins one breadboard hole pitch apart, on the connection lattice so wires
  // to grid-snapped parts stay straight.
  static const _pinVccX = _centerX;
  static const _pinGndX = _pinVccX - GridSystem.pitch;
  static const _pinSignalX = _pinVccX + GridSystem.pitch;
  static const _pinXs = [_pinGndX, _pinVccX, _pinSignalX];
  // Socket centers double as the wire ports, so they must sit on the
  // connection lattice (≡ cellCenter mod pitch). `height` itself is on it,
  // and stepping up one full pitch keeps it there while landing inside the
  // connector's socket band.
  static const _socketY = height - GridSystem.pitch;

  // Horn/shaft geometry. The horn is centred on the output shaft and reaches
  // to just inside the top of the bounds; the case then hangs below it, with
  // the shaft about a third of the way down the case (where the SG90's gear
  // train puts it).
  static const _hornTop = 4.0;
  static const _hornBottom = _hornTop + hornLong;
  static const _shaftY = _hornTop + hornLong / 2;
  static const _shaftCenter = Offset(_centerX, _shaftY);
  static const _shaftRadius = 16.0;
  // Radius of the hub zone around the shaft that the link holes stay clear
  // of (the concave webs between blades dip to about this distance too).
  static const _bossRadius = 27.0;
  static const _hornLeft = _centerX - hornShort / 2;
  static const _hornRight = _centerX + hornShort / 2;

  // Case geometry: sits under the shaft, with the connector plug below it.
  static const _bodyTop = _shaftY - bodyHeight * 0.31;
  static const _bodyRect = Rect.fromLTRB(
    _centerX - bodyWidth / 2,
    _bodyTop,
    _centerX + bodyWidth / 2,
    _bodyTop + bodyHeight,
  );

  static const _connectorColor = Color(0xFF2B2B2B);
  static const _connectorBorder = Color(0xFF161616);
  static const _bodyFill = Color(0xFF3A72B0);
  static const _bodyBorder = Color(0xFF27578F);
  static const _gearFill = Color(0xFF8FB8E0);
  static const _hornFill = Color(0xFFF2F2F0);
  static const _hornBorder = Color(0xFF6B6D70);
  static const _shaftFill = Color(0xFFCBCBCB);
  static const _shaftBorder = Color(0xFF58595B);

  static const _wireGnd = Color(0xFF5C3A28); // brown
  static const _wireVcc = Color(0xFF8B2020); // dark red
  static const _wireSignal = Color(0xFFC9803D); // orange

  @override
  /// Case, horn and connector plug — everything drawn, which for a servo is
  /// nearly all of its bounds. The strips left over are the air either side
  /// of the plug.
  @override
  Rect bodyRect(Size size) => _bodyRect
      .expandToInclude(const Rect.fromLTRB(_hornLeft, _hornTop, _hornRight, _hornBottom))
      .expandToInclude(_connectorRect);

  @override
  List<ComponentPort> getPorts() => const [
    ComponentPort(id: 'gnd', name: 'GND', localOffset: Offset(_pinGndX, _socketY)),
    ComponentPort(id: 'vcc', name: 'VCC', localOffset: Offset(_pinVccX, _socketY)),
    ComponentPort(id: 'signal', name: 'Signal', localOffset: Offset(_pinSignalX, _socketY)),
  ];

  @override
  void paintComponent(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Wires first so they slip in BEHIND the case: visible only in the gap
    // between the case's bottom edge and the connector plug.
    _paintWires(canvas, paint);
    _paintBody(canvas, paint);
    _paintConnector(canvas, paint);
    _paintHorn(canvas, paint);
  }

  void _paintBody(Canvas canvas, Paint paint) {
    final bodyRRect = RRect.fromRectAndRadius(_bodyRect, const Radius.circular(10));

    paint.color = _bodyFill;
    canvas.drawRRect(bodyRRect, paint);

    canvas.save();
    canvas.clipRRect(bodyRRect);

    // Two gears matching the reference art: the big output gear centered
    // exactly on the horn shaft, and a smaller gear tangent to it directly
    // below (tangent: the two outer radii summed), so they read as meshed.
    const outputGearR = 35.0;
    const idlerGearR = 28.0;
    const gears = [
      (center: _shaftCenter, outer: outputGearR, inner: 32.0, teeth: 44),
      (
        center: Offset(_centerX, _shaftY + outputGearR + idlerGearR),
        outer: idlerGearR,
        inner: 25.0,
        teeth: 36,
      ),
    ];
    for (final gear in gears) {
      paint.color = _gearFill;
      canvas.drawPath(
        _gearPath(gear.center, innerRadius: gear.inner, outerRadius: gear.outer, teeth: gear.teeth),
        paint,
      );
    }

    canvas.restore();

    // Case border on top of the clipped fills.
    final borderPaint = Paint()
      ..color = _bodyBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(bodyRRect, borderPaint);
  }

  /// Builds a gear silhouette: a circle of [teeth] trapezoidal teeth rising
  /// from [innerRadius] to [outerRadius] around [center].
  static Path _gearPath(
    Offset center, {
    required double innerRadius,
    required double outerRadius,
    required int teeth,
  }) {
    final path = Path();
    final pitch = 2 * math.pi / teeth;
    Offset polar(double angle, double radius) =>
        center + Offset(math.cos(angle), math.sin(angle)) * radius;

    for (var i = 0; i < teeth; i++) {
      final a = i * pitch;
      // Tooth top spans the first ~40% of the pitch; the sloped flanks and
      // root valley fill the rest, giving a fine machined-tooth profile.
      final p1 = polar(a, outerRadius);
      final p2 = polar(a + pitch * 0.4, outerRadius);
      final p3 = polar(a + pitch * 0.55, innerRadius);
      final p4 = polar(a + pitch * 0.85, innerRadius);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy);
    }
    path.close();
    return path;
  }

  /// Builds the horn as one outline: four tapered fan blades (wide at the
  /// hub, narrowing to a rounded tip) whose adjacent edges are joined by a
  /// smooth concave web that bends IN toward the shaft — no boss circle in
  /// the silhouette, matching the molded one-piece horn in the reference.
  static Path _hornOutline() {
    const center = _shaftCenter;
    // How far the concave web reaches back along each blade edge from the
    // sharp corner the two edges would otherwise form.
    const webExtent = 14.0;

    // Ordered clockwise. `baseHalf` is the blade's half-width at the shaft,
    // `tipR` the rounded tip's radius (also its half-width there), `len` the
    // blade's reach from the shaft to its end.
    const fins = [
      (d: Offset(0, -1), len: _shaftY - _hornTop, tipR: 13.0, baseHalf: 21.0),
      (d: Offset(1, 0), len: hornShort / 2, tipR: 11.0, baseHalf: 18.0),
      (d: Offset(0, 1), len: _hornBottom - _shaftY, tipR: 13.0, baseHalf: 21.0),
      (d: Offset(-1, 0), len: hornShort / 2, tipR: 11.0, baseHalf: 18.0),
    ];

    Offset perp(Offset d) => Offset(-d.dy, d.dx);
    Offset unit(Offset v) => v / v.distance;
    // Intersection of the lines p1 + t·v1 and p2 + u·v2.
    Offset intersect(Offset p1, Offset v1, Offset p2, Offset v2) {
      final det = v1.dx * v2.dy - v1.dy * v2.dx;
      final t = ((p2.dx - p1.dx) * v2.dy - (p2.dy - p1.dy) * v2.dx) / det;
      return p1 + v1 * t;
    }

    Offset tipCenter(({Offset d, double len, double tipR, double baseHalf}) f) =>
        center + f.d * (f.len - f.tipR);

    // Sharp inside corner where fin i's trailing edge meets fin i+1's leading
    // edge (both extended); the web replaces it with a tangent curve.
    Offset cornerAfter(int i) {
      final fin = fins[i];
      final next = fins[(i + 1) % fins.length];
      final tipR = tipCenter(fin) + perp(fin.d) * fin.tipR;
      final baseR = center + perp(fin.d) * fin.baseHalf;
      final nextTipL = tipCenter(next) - perp(next.d) * next.tipR;
      final nextBaseL = center - perp(next.d) * next.baseHalf;
      return intersect(tipR, baseR - tipR, nextBaseL, nextTipL - nextBaseL);
    }

    final path = Path();
    for (var i = 0; i < fins.length; i++) {
      final fin = fins[i];
      final next = fins[(i + 1) % fins.length];
      final p = perp(fin.d);
      final tip = tipCenter(fin);
      final tipL = tip - p * fin.tipR;
      final tipR = tip + p * fin.tipR;
      final corner = cornerAfter(i);
      // Leave the trailing edge `webExtent` short of the corner, then curve
      // through it (as the control point) onto the next blade's leading edge
      // — a quadratic with the corner as control is tangent to both edges,
      // and its bow dips inward, giving the concave web.
      final webStart = corner + unit(tipR - corner) * webExtent;
      final nextTipL = tipCenter(next) - perp(next.d) * next.tipR;
      final webEnd = corner + unit(nextTipL - corner) * webExtent;

      if (i == 0) {
        final prevCorner = cornerAfter(fins.length - 1);
        final start = prevCorner + unit(tipL - prevCorner) * webExtent;
        path.moveTo(start.dx, start.dy);
      }
      path
        ..lineTo(tipL.dx, tipL.dy)
        ..arcToPoint(tipR, radius: Radius.circular(fin.tipR))
        ..lineTo(webStart.dx, webStart.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, webEnd.dx, webEnd.dy);
    }
    return path..close();
  }

  void _paintWires(Canvas canvas, Paint paint) {
    final wirePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Each wire rises out of the connector, bundles toward the center line
    // and tucks in behind the case's bottom edge (the case is painted after,
    // hiding the ends) — visible only in the connector-to-case gap.
    final wires = [
      (_pinGndX, _wireGnd, -1.0),
      (_pinVccX, _wireVcc, 0.0),
      (_pinSignalX, _wireSignal, 1.0),
    ];
    const connectorTop = height - _connectorH;
    for (final (x, color, side) in wires) {
      wirePaint.color = color;
      final bundleX = _centerX + side * 5;
      final path = Path()
        ..moveTo(x, connectorTop + 4)
        ..cubicTo(x, connectorTop - 22, bundleX, connectorTop - 14, bundleX, _bodyRect.bottom - 14);
      canvas.drawPath(path, wirePaint);
    }
  }

  void _paintConnector(Canvas canvas, Paint paint) {
    final rrect = RRect.fromRectAndRadius(_connectorRect, const Radius.circular(7));
    paint.color = _connectorBorder;
    canvas.drawRRect(rrect, paint);
    paint.color = _connectorColor;
    canvas.drawRRect(rrect.deflate(1.5), paint);

    // Slightly lighter band along the socket edge (facing the ports), like
    // the housing's separate top shell in the reference art.
    const bandH = 26.0;
    canvas.save();
    canvas.clipRRect(rrect.deflate(1.5));
    paint.color = const Color(0xFF333333);
    canvas.drawRect(Rect.fromLTWH(_connectorRect.left, height - bandH, _connectorW, bandH), paint);
    canvas.restore();

    // 3 socket holes in the same style as the Arduino header pins (see
    // PinBlockNode.drawHoles), centered on the ports so wires plug into them.
    for (final x in _pinXs) {
      _paintSocket(canvas, paint, Offset(x, _socketY));
    }

    // Strain-relief stripe (near the connector's top, where the wires enter).
    paint.color = const Color(0xFF3D3D3D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_connectorRect.left + 9, height - 36, _connectorW - 18, 4),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  /// One socket hole centered on [center], drawn exactly like the Arduino
  /// header pins (PinBlockNode.drawHoles) at canvas scale: a rounded outer
  /// square with a light base, a dark bevel "L" over its top and left walls,
  /// and a black square hole in the middle.
  void _paintSocket(Canvas canvas, Paint paint, Offset center) {
    const outerSize = 12.0;
    const innerSize = outerSize * 0.5;

    final outerRect = Rect.fromCenter(center: center, width: outerSize, height: outerSize);
    final innerRect = Rect.fromCenter(center: center, width: innerSize, height: innerSize);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(outerRect, const Radius.circular(2)));

    paint.color = const Color(0xFF595959);
    canvas.drawRect(outerRect, paint);

    final darkBevelPath = Path()
      ..moveTo(outerRect.left, outerRect.top)
      ..lineTo(outerRect.right, outerRect.top)
      ..lineTo(innerRect.right, innerRect.top)
      ..lineTo(innerRect.left, innerRect.top)
      ..lineTo(innerRect.left, innerRect.bottom)
      ..lineTo(outerRect.left, outerRect.bottom)
      ..close();

    paint.color = const Color(0xFF1A1A1A);
    canvas.drawPath(darkBevelPath, paint);

    paint.color = const Color(0xFF000000);
    canvas.drawRect(innerRect, paint);
    canvas.restore();
  }

  void _paintHorn(Canvas canvas, Paint paint) {
    final hornBorderPaint = Paint()
      ..color = _hornBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // The simulation writes the decoded signal angle (0–180°) each frame;
    // 90° is the neutral upright pose, so the horn swings ±90° around it.
    final angle = (properties?[ComponentProps.servoAngle] as num?)?.toDouble();
    canvas.save();
    if (angle != null) {
      canvas
        ..translate(_shaftCenter.dx, _shaftCenter.dy)
        ..rotate((angle - 90) * math.pi / 180)
        ..translate(-_shaftCenter.dx, -_shaftCenter.dy);
    }

    // One explicit outline for the whole horn: four fins with rounded tips,
    // joined by concave webs that dip IN toward the shaft between adjacent
    // blades (no boss circle — a boss would bulge outward in those corners).
    var horn = _hornOutline();

    // The link holes are punched straight through the horn — cut out of the
    // path so they're genuinely transparent and whatever sits underneath
    // (wires, gears, case) shows through.
    // Link holes down each arm, on the ~3 mm pitch the moulded horn uses:
    // four to a long arm, two to a short one, none over the boss itself.
    const holePitch = 3.0 * PhysicalScale.pxPerMm;
    const holeRadius = 0.95 * PhysicalScale.pxPerMm;
    const firstHole = _bossRadius + 7;

    final holeCenters = <Offset>[
      for (var i = 0; i < 4; i++) ...[
        Offset(_centerX, _shaftY - firstHole - i * holePitch),
        Offset(_centerX, _shaftY + firstHole + i * holePitch),
      ],
      // The short arms get two holes each: one just off the hub, and one
      // centered in the rounded tip (not the shared pitch — that would land
      // the outer hole on the tip's edge).
      for (final r in [_bossRadius + 4, hornShort / 2 - 11]) ...[
        Offset(_centerX - r, _shaftY),
        Offset(_centerX + r, _shaftY),
      ],
    ];
    final holes = Path();
    for (final c in holeCenters) {
      holes.addOval(Rect.fromCircle(center: c, radius: holeRadius));
    }
    horn = Path.combine(PathOperation.difference, horn, holes);

    paint.color = _hornFill;
    canvas.drawPath(horn, paint);
    canvas.drawPath(horn, hornBorderPaint);

    // Center shaft with screwdriver "+" mark.
    paint.color = _shaftFill;
    canvas.drawCircle(_shaftCenter, _shaftRadius, paint);
    final shaftBorderPaint = Paint()
      ..color = _shaftBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(_shaftCenter, _shaftRadius, shaftBorderPaint);

    final plusPaint = Paint()
      ..color = _shaftBorder
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      _shaftCenter - const Offset(9, 0),
      _shaftCenter + const Offset(9, 0),
      plusPaint,
    );
    canvas.drawLine(
      _shaftCenter - const Offset(0, 9),
      _shaftCenter + const Offset(0, 9),
      plusPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaintComponent(covariant ServoMotorPainter oldDelegate) =>
      oldDelegate.properties?[ComponentProps.servoAngle] != properties?[ComponentProps.servoAngle];
}
