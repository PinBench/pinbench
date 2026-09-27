import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'canvas_controller.dart';
import '../managers/canvas_commands.dart';

/// Copy/paste for the canvas: snapshotting selected nodes/wires to the
/// clipboard, and pasting them back with remapped keys so pasted wires
/// connect to the *pasted* nodes rather than the originals. Extracted from
/// `CanvasController`, which still owns the read-only guard and calls into
/// this for the actual mechanics.
class ClipboardOps {
  final CanvasController controller;
  ClipboardOps(this.controller);

  void copy() {
    if (controller.selectedNodes.isEmpty) return;
    controller.clipboardNodes = controller.selectedNodes.map((n) => n.copyWith()).toList();

    final selectedKeys = controller.selectedNodes.map((n) => n.key).toSet();
    controller.clipboardWires = controller.wires
        .where(
          (w) => selectedKeys.contains(w.start.nodeKey) && selectedKeys.contains(w.end.nodeKey),
        )
        .map((w) => w.copyWith())
        .toList();
  }

  void paste() {
    final clipboardNodes = controller.clipboardNodes;
    if (clipboardNodes == null || clipboardNodes.isEmpty) return;

    final keyMap = <LocalKey, LocalKey>{};

    final pastedNodes = clipboardNodes.map((n) {
      final newKey = UniqueKey();
      keyMap[n.key] = newKey;
      return n.copyWith(key: newKey, position: n.position + const Offset(20, 20));
    }).toList();

    final pastedWires = (controller.clipboardWires ?? <WireModel>[]).map((w) {
      final newStart = PortLocation(nodeKey: keyMap[w.start.nodeKey]!, portId: w.start.portId);
      final newEnd = PortLocation(nodeKey: keyMap[w.end.nodeKey]!, portId: w.end.portId);
      final newBendPoints = w.bendPoints.map((p) => p + const Offset(20, 20)).toList();
      return w.copyWith(
        id: WireModel.generateId(),
        start: newStart,
        end: newEnd,
        bendPoints: newBendPoints,
      );
    }).toList();

    controller.executeCommand(PasteCommand(pastedNodes, pastedWires: pastedWires));
    controller.updateState(clipboardNodes: pastedNodes, clipboardWires: pastedWires);
  }
}
