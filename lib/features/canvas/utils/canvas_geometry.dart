import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/part_registry.dart';

/// Shared geometric utilities for the canvas.
///
/// Extracted here to avoid duplicating logic across WirePainter and
/// WiringManager, both of which need to resolve a [PortLocation] to an
/// absolute canvas-space [Offset], and the hover label, which names one.
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

  /// What [loc]'s port is called, for a person — `GP15`, `Anode`,
  /// `Terminal Strip left A12` — or null when the node or port is gone.
  ///
  /// Ports are declared three ways, so three places are asked: a `.pdl` part's
  /// pins, a painter's [PortProvider.getPorts], and the breadboard, which
  /// lists none — its holes are worked out from a position, not enumerated —
  /// so it is asked what hole sits at the port's own position, and that hole
  /// is the port when the ids agree.
  static String? getPortName(PortLocation loc, List<ComponentInstance> nodes) {
    final node = nodes.firstWhereOrNull((n) => n.key == loc.nodeKey);
    if (node == null) return null;

    if (node.part.definitionId case final definitionId?) {
      final pin = PartRegistry.getPart(definitionId)?.pins
          .firstWhereOrNull((p) => p.id == loc.portId);
      if (pin != null) return pin.name;
    }

    if (node.part.getPainter() case final PortProvider provider) {
      final listed = provider.getPorts().firstWhereOrNull((p) => p.id == loc.portId);
      if (listed != null) return listed.name;
      final at = provider.getPortOffsetById(loc.portId);
      final found = at == null ? null : provider.getPortAt(at);
      if (found != null && found.id == loc.portId) return found.name;
    }
    return null;
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
