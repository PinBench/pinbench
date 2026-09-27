import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import '../../features/canvas/controller/canvas_controller.dart';
import '../../features/simulation/ports/simulation_canvas.dart';

/// Binds the simulation's [SimulationCanvas] port to the live canvas.
///
/// The adapter lives on this side of the boundary deliberately: it is the only
/// place that needs to know both that a simulation exists and that a canvas
/// does. `SimulationRunner` and its backends used to hold a `CanvasController`
/// directly, which meant the emulator — including the code that runs inside a
/// background isolate — depended on the app's canvas state. Closing that left
/// the *feature* still holding one, which is what this file finishes.
class CanvasSimulationCanvas extends ChangeNotifier implements SimulationCanvas {
  CanvasSimulationCanvas(this._controller);

  final CanvasController _controller;

  @override
  List<ComponentInstance> get simulationNodes => _controller.nodes;

  @override
  List<WireModel> get simulationWires => _controller.wires;

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) =>
      _controller.batchSimulationUpdate(updates);

  @override
  bool get isReadOnly => _controller.isReadOnly;

  @override
  set isReadOnly(bool value) => _controller.isReadOnly = value;

  @override
  Listenable get changes => this;

  /// Called by the binding provider when the canvas controller emits new state.
  ///
  /// A `ChangeNotifier` rather than forwarding the Riverpod provider itself:
  /// the simulation must not rebuild when the canvas changes — that would
  /// construct a second `SimulationRunner` and leave two run loops ticking —
  /// so it needs a signal it can subscribe to without watching.
  void onCanvasChanged() => notifyListeners();
}
