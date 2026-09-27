import 'dart:ui';

/// Tidying for the points a wire is actually made of.
///
/// There is deliberately no routing here any more. Wires used to be forced
/// into L-shapes — a corner invented for any diagonal — first at paint time
/// and later baked in when the wire was created. Both are gone: a wire runs
/// straight from port to port and bends only where you bend it.
class RoutingUtils {
  static const tolerance = 1.0;

  /// Removes redundant points from the path (collinear or coincident).
  static List<Offset> simplify(List<Offset> points) {
    if (points.length <= 2) return points;

    final simplified = <Offset>[points.first];

    for (var i = 1; i < points.length - 1; i++) {
      final prev = simplified.last;
      final curr = points[i];
      final next = points[i + 1];

      // 1. Remove coincident points
      if ((curr - prev).distance < tolerance) continue;

      // 2. Remove collinear points (Horizontal or Vertical alignment)
      final isCollinearH =
          (prev.dy - curr.dy).abs() < tolerance && (curr.dy - next.dy).abs() < tolerance;
      final isCollinearV =
          (prev.dx - curr.dx).abs() < tolerance && (curr.dx - next.dx).abs() < tolerance;

      if (!isCollinearH && !isCollinearV) {
        simplified.add(curr);
      }
    }

    // Add back the last point if it's not too close to the previous one
    if ((points.last - simplified.last).distance > tolerance) {
      simplified.add(points.last);
    } else if (simplified.length > 1) {
      // If last is too close, ensure the previous point is the ACTUAL end point
      simplified[simplified.length - 1] = points.last;
    }

    return simplified;
  }
}
