import 'package:flutter/widgets.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Convenience factory for creating test [WireModel]s.
///
/// Replaces the `_wire()` helpers duplicated across 9+ test files.
WireModel createWire(ComponentInstance a, String aPort, ComponentInstance b, String bPort) =>
    WireModel(
      id: 'wire_${a.key.hashCode}_${b.key.hashCode}_$aPort',
      start: PortLocation(nodeKey: a.key, portId: aPort),
      end: PortLocation(nodeKey: b.key, portId: bPort),
      color: const Color(0xFF000000),
    );
