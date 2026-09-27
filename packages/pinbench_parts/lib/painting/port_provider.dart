import 'dart:ui';

import '../models/port_model.dart';

/// How close a point has to be to a port to count as being on it, in canvas
/// units, when the caller doesn't say otherwise.
///
/// Geometry callers (the netlist working out which hole a leg is plugged
/// into) rely on this default; pointer callers pass their own, because what
/// matters for a pointer is the distance *on screen*, which changes with
/// zoom — see `SelectionManager.checkHover`.
const kPortHitRadius = 6.0;

/// Mixin for painters that expose connection ports. Supplies hit-testing
/// ([getPortAt]) and lookup ([getPortOffsetById]) on top of [getPorts], so the
/// canvas can resolve wires and snap to a component's terminals.
mixin PortProvider {
  /// The component's ports in its local coordinate space.
  List<ComponentPort> getPorts();

  /// The port nearest [localOffset] within [hitRadius], or null if none is.
  ///
  /// Nearest rather than first: with a radius wide enough to be comfortable
  /// to aim at, two neighbouring ports' catchment areas overlap, and picking
  /// whichever happened to come first in [getPorts] would hand back the wrong
  /// one — an LED's anode when the pointer is plainly closer to its cathode.
  ComponentPort? getPortAt(Offset localOffset, {double? hitRadius}) {
    ComponentPort? nearest;
    var nearestDistance = hitRadius ?? kPortHitRadius;
    for (final port in getPorts()) {
      final distance = (port.localOffset - localOffset).distance;
      if (distance < nearestDistance) {
        nearest = port;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  Offset? getPortOffsetById(String id) {
    for (final port in getPorts()) {
      if (port.id == id) return port.localOffset;
    }
    return null;
  }
}
