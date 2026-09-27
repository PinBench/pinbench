import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import 'canvas_context.dart';

/// A reversible canvas edit (the Command pattern behind undo/redo).
///
/// The history manager pushes each command and calls [execute]; [undo] restores
/// the prior state. Commands capture the before/after data they need so they can
/// be replayed in either direction without consulting current state.
abstract class CanvasCommand {
  void execute(CanvasContext controller);
  void undo(CanvasContext controller);
}

/// Adds a single node and selects it.
class AddNodeCommand implements CanvasCommand {
  final ComponentInstance node;

  AddNodeCommand(this.node);

  @override
  void execute(CanvasContext controller) {
    controller.updateState(nodes: [...controller.nodes, node], selectedNodes: [node]);
  }

  @override
  void undo(CanvasContext controller) {
    controller.updateState(
      nodes: controller.nodes.where((n) => n.key != node.key).toList(),
      selectedNodes: [],
    );
  }
}

/// Deletes the selected nodes and wires together (restores them on undo).
class RemoveSelectionCommand implements CanvasCommand {
  final List<ComponentInstance> removedNodes;
  final List<WireModel> removedWires;

  RemoveSelectionCommand({required this.removedNodes, required this.removedWires});

  @override
  void execute(CanvasContext controller) {
    final removedNodeKeys = removedNodes.map((n) => n.key).toSet();
    final removedWireIds = removedWires.map((w) => w.id).toSet();

    controller.updateState(
      nodes: controller.nodes.where((n) => !removedNodeKeys.contains(n.key)).toList(),
      wires: controller.wires.where((w) => !removedWireIds.contains(w.id)).toList(),
      selectedNodes: [],
    );
    controller.selectedWireIds = [];
  }

  @override
  void undo(CanvasContext controller) {
    controller.updateState(
      nodes: [...controller.nodes, ...removedNodes],
      wires: [...controller.wires, ...removedWires],
      selectedNodes: removedNodes,
    );
    controller.selectedWireIds = removedWires.map((w) => w.id).toList();
  }
}

/// Replaces one node with an edited version (e.g. rotation, properties).
class UpdateNodeCommand implements CanvasCommand {
  final LocalKey nodeKey;
  final ComponentInstance oldNode;
  final ComponentInstance newNode;

  UpdateNodeCommand(this.nodeKey, this.oldNode, this.newNode);

  @override
  void execute(CanvasContext controller) {
    _updateNode(controller, newNode);
  }

  @override
  void undo(CanvasContext controller) {
    _updateNode(controller, oldNode);
  }

  void _updateNode(CanvasContext controller, ComponentInstance node) {
    final index = controller.nodes.indexWhere((n) => n.key == nodeKey);
    if (index != -1) {
      final newNodes = List<ComponentInstance>.from(controller.nodes);
      newNodes[index] = node;

      final newSelectedNodes = List<ComponentInstance>.from(controller.selectedNodes);
      final selIndex = newSelectedNodes.indexWhere((n) => n.key == nodeKey);
      if (selIndex != -1) {
        newSelectedNodes[selIndex] = node;
      }

      controller.updateState(nodes: newNodes, selectedNodes: newSelectedNodes);
    }
  }
}

/// Adds a single wire.
class AddWireCommand implements CanvasCommand {
  final WireModel wire;

  AddWireCommand(this.wire);

  @override
  void execute(CanvasContext controller) {
    controller.updateState(wires: [...controller.wires, wire]);
  }

  @override
  void undo(CanvasContext controller) {
    controller.updateState(wires: controller.wires.where((w) => w.id != wire.id).toList());
  }
}

/// Replaces one wire with an edited version (e.g. moved bend points).
class UpdateWireCommand implements CanvasCommand {
  final String wireId;
  final WireModel oldWire;
  final WireModel newWire;

  UpdateWireCommand(this.wireId, this.oldWire, this.newWire);

  @override
  void execute(CanvasContext controller) {
    _updateWire(controller, newWire);
  }

  @override
  void undo(CanvasContext controller) {
    _updateWire(controller, oldWire);
  }

  void _updateWire(CanvasContext controller, WireModel wire) {
    final index = controller.wires.indexWhere((w) => w.id == wireId);
    if (index != -1) {
      final newWires = List<WireModel>.from(controller.wires);
      newWires[index] = wire;
      controller.updateState(wires: newWires);
    }
  }
}

/// Inserts pasted nodes + wires and selects them.
class PasteCommand implements CanvasCommand {
  final List<ComponentInstance> pastedNodes;
  final List<WireModel> pastedWires;

  PasteCommand(this.pastedNodes, {this.pastedWires = const []});

  @override
  void execute(CanvasContext controller) {
    controller.updateState(
      nodes: [...controller.nodes, ...pastedNodes],
      wires: [...controller.wires, ...pastedWires],
      selectedNodes: pastedNodes,
    );
    controller.selectedWireIds = pastedWires.map((w) => w.id).toList();
  }

  @override
  void undo(CanvasContext controller) {
    final pastedKeys = pastedNodes.map((n) => n.key).toSet();
    final pastedWireIds = pastedWires.map((w) => w.id).toSet();
    controller.updateState(
      nodes: controller.nodes.where((n) => !pastedKeys.contains(n.key)).toList(),
      wires: controller.wires.where((w) => !pastedWireIds.contains(w.id)).toList(),
      selectedNodes: [],
    );
    controller.selectedWireIds = [];
  }
}

/// Replaces many nodes at once (e.g. dragging a multi-node selection).
class UpdateNodesCommand implements CanvasCommand {
  final List<ComponentInstance> oldNodes;
  final List<ComponentInstance> newNodes;

  UpdateNodesCommand(this.oldNodes, this.newNodes);

  @override
  void execute(CanvasContext controller) {
    _updateNodes(controller, newNodes);
  }

  @override
  void undo(CanvasContext controller) {
    _updateNodes(controller, oldNodes);
  }

  void _updateNodes(CanvasContext controller, List<ComponentInstance> updatedNodesList) {
    final newNodes = List<ComponentInstance>.from(controller.nodes);
    final newSelectedNodes = List<ComponentInstance>.from(controller.selectedNodes);

    for (final updatedNode in updatedNodesList) {
      final index = newNodes.indexWhere((n) => n.key == updatedNode.key);
      if (index != -1) {
        newNodes[index] = updatedNode;
      }

      final selIndex = newSelectedNodes.indexWhere((n) => n.key == updatedNode.key);
      if (selIndex != -1) {
        newSelectedNodes[selIndex] = updatedNode;
      }
    }

    controller.updateState(nodes: newNodes, selectedNodes: newSelectedNodes);
  }
}

/// Replaces many wires at once.
class UpdateWiresCommand implements CanvasCommand {
  final List<WireModel> oldWires;
  final List<WireModel> newWires;

  UpdateWiresCommand(this.oldWires, this.newWires);

  @override
  void execute(CanvasContext controller) {
    _updateWires(controller, newWires);
  }

  @override
  void undo(CanvasContext controller) {
    _updateWires(controller, oldWires);
  }

  void _updateWires(CanvasContext controller, List<WireModel> updatedWiresList) {
    final newWiresState = List<WireModel>.from(controller.wires);

    for (final updatedWire in updatedWiresList) {
      final index = newWiresState.indexWhere((w) => w.id == updatedWire.id);
      if (index != -1) {
        newWiresState[index] = updatedWire;
      }
    }

    controller.updateState(wires: newWiresState);
  }
}

/// Reorders the wire list (paint/z-order among wires) without changing
/// membership.
class ReorderWiresCommand implements CanvasCommand {
  final List<WireModel> oldWires;
  final List<WireModel> newWires;

  ReorderWiresCommand(this.oldWires, this.newWires);

  @override
  void execute(CanvasContext controller) {
    controller.updateState(wires: newWires);
  }

  @override
  void undo(CanvasContext controller) {
    controller.updateState(wires: oldWires);
  }
}

/// Reorders the node list (paint/z-order) without changing membership.
class ReorderNodesCommand implements CanvasCommand {
  final List<ComponentInstance> oldNodes;
  final List<ComponentInstance> newNodes;

  ReorderNodesCommand(this.oldNodes, this.newNodes);

  @override
  void execute(CanvasContext controller) {
    controller.updateState(nodes: newNodes);
  }

  @override
  void undo(CanvasContext controller) {
    controller.updateState(nodes: oldNodes);
  }
}
