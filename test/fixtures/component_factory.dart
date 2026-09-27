import 'package:flutter/widgets.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Convenience factory for creating test [ComponentInstance]s.
///
/// Replaces the `_node()` helpers duplicated across 9+ test files.
ComponentInstance createNode(
  String name,
  String id, [
  Offset pos = Offset.zero,
  Map<String, dynamic>? properties,
]) => ComponentInstance(
  key: ValueKey<String>(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
  properties: properties,
);
