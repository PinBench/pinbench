import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import '../features/canvas/controller/canvas_controller.dart';
import '../features/workspace/services/syncable_canvas.dart';

/// Binds the `.cdl` sync's [SyncableCanvas] port to the live canvas.
///
/// The last of the four adapters that live at this layer, and the same shape as
/// the other three: the workspace says what it needs from a canvas, the canvas
/// knows nothing about it, and the one file allowed to know both sides puts
/// them together.
class ControllerSyncableCanvas extends ChangeNotifier implements SyncableCanvas {
  ControllerSyncableCanvas(this._controller);

  final CanvasController _controller;

  @override
  bool get isReadOnly => _controller.isReadOnly;

  @override
  List<ComponentInstance> get nodes => _controller.nodes;

  @override
  List<WireModel> get wires => _controller.wires;

  @override
  Key? get selectedNodeKey =>
      _controller.selectedNodes.isEmpty ? null : _controller.selectedNodes.first.key;

  @override
  String? get selectedWireId =>
      _controller.selectedWireIds.isEmpty ? null : _controller.selectedWireIds.first;

  @override
  void replaceCircuit(List<ComponentInstance> nodes, List<WireModel> wires) =>
      _controller.updateCircuit(nodes, wires);

  @override
  void applyValidatedProperties(LocalKey nodeKey, Map<String, dynamic> properties) =>
      _controller.updateNodeProperties(nodeKey, properties, recordHistory: false);

  @override
  Listenable get changes => this;

  /// Called by the binding when the canvas controller emits new state.
  void onCanvasChanged() => notifyListeners();
}

/// Wires the sync port to the canvas. Spread into the root scope in
/// `bootstrap.dart`, beside the simulation's and the chrome's.
final canvasSyncBindings = [
  syncableCanvasProvider.overrideWith((ref) {
    final adapter = ControllerSyncableCanvas(ref.watch(canvasControllerProvider.notifier));

    // `listen`, not `watch`: a canvas edit must reach the sync service without
    // rebuilding this provider, because rebuilding it rebuilds the service
    // watching it — and two services on one file would fight over the editor
    // buffer they both write to.
    ref.listen(canvasControllerProvider, (_, _) => adapter.onCanvasChanged());
    ref.onDispose(adapter.dispose);
    return adapter;
  }),
];
