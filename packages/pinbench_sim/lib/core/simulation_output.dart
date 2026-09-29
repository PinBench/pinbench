import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

/// Interface that decouples SimulationEngine from the concrete canvas layer.
///
/// SimulationEngine reads circuit topology through simulationNodes/simulationWires
/// and writes visual state back through applyNodeUpdates. Any implementation —
/// including a test mock — satisfies the engine's dependencies.
abstract class SimulationOutput {
  List<ComponentInstance> get simulationNodes;
  List<WireModel> get simulationWires;

  /// Applies a batch of property changes to the named nodes in a single
  /// state write. The map keys are node keys; values are the full new
  /// property maps to set on each node.
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates);
}
