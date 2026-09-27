import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Shared geometric utilities for the canvas.
///
/// Extracted here to avoid duplicating logic across WirePainter and
/// WiringManager, both of which need to resolve a [PortLocation] to an
/// absolute canvas-space [Offset].
abstract final class CanvasGeometry {
  /// Returns the canvas-space position of a [PortLocation] by looking up the
  /// node in [nodes] and combining the node's [ComponentInstance.position] with
  /// the port's local offset.
  ///
  /// Returns `null` if the node or port cannot be found.
  static Offset? getPortPosition(PortLocation loc, List<ComponentInstance> nodes) {
    final node = nodes.firstWhereOrNull((n) => n.key == loc.nodeKey);
    if (node == null) return null;
    final localOffset = node.getPortOffset(loc.portId);
    if (localOffset == null) return null;
    return node.position + localOffset;
  }

  /// Shortest distance from point [p] to the line segment `a`-`b`.
  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final l2 = (a - b).distanceSquared;
    if (l2 == 0.0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2).clamp(
      0.0,
      1.0,
    );
    final projection = a + (b - a) * t;
    return (p - projection).distance;
  }
}
