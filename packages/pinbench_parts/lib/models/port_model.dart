import 'package:flutter/widgets.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart' show PortType;

export 'package:pinbench_pdl/pinbench_pdl.dart' show PortType;

/// A stable string id for a node [Key], used everywhere node keys are serialised
/// so that a node and the wire endpoints referencing it always map to the same
/// id. The app's normal [ValueKey] keys round-trip exactly; other keys (e.g. a
/// parser-assigned [UniqueKey]) fall back to their per-instance string form,
/// which is consistent as long as the same key instance is reused (it is — the
/// node and its wires share one key object).
String nodeKeyToId(Key key) => key is ValueKey<String> ? key.value : key.toString();

/// A connection point on a component (e.g. an LED's `anode`, an Arduino pin),
/// defined in the component's own local coordinate space.
class const ComponentPort({
  required final String id,
  required final String name,

  /// Position of the port relative to the component's origin (top-left), before
  /// the node's rotation/flip/scale are applied.
  required final Offset localOffset,
  final PortType type = PortType.biDirectional,
});

/// Identifies a specific port on a specific placed node: the pair
/// `(node key, port id)`. This is the atom the netlist and wires are built from,
/// so it implements value equality to be usable as a map/set key.
@immutable
class const PortLocation({required final Key nodeKey, required final String portId}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortLocation &&
          runtimeType == other.runtimeType &&
          nodeKey == other.nodeKey &&
          portId == other.portId;

  @override
  int get hashCode => nodeKey.hashCode ^ portId.hashCode;

  @override
  String toString() => 'PortLocation(node: $nodeKey, port: $portId)';

  Map<String, dynamic> toJson() => {'nodeId': nodeKeyToId(nodeKey), 'portId': portId};

  factory fromJson(Map<String, dynamic> json) => PortLocation(
    nodeKey: ValueKey<String>(json['nodeId'] as String),
    portId: json['portId'] as String,
  );
}
