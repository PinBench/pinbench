import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';

import '../../../core/telemetry/telemetry_providers.dart';
import 'base_controller.dart';
import 'canvas_state.dart';
import 'clipboard_ops.dart';
import 'viewport_ops.dart';
import '../managers/canvas_commands.dart';
import '../managers/canvas_context.dart';
import '../managers/history_manager.dart';
import '../managers/breadboard_snap_helper.dart';
import '../managers/selection_manager.dart';
import '../managers/snap_guide_helper.dart';
import '../managers/wiring_manager.dart';

part 'canvas_controller.g.dart';

/// Central state + behavior for the schematic canvas: the nodes/wires, the
/// current selection, clipboard and guidelines.
///
/// It owns the [HistoryManager], [SelectionManager] and [WiringManager] and
/// implements [CanvasContext] so they can drive it. All mutations go through
/// commands (for undo/redo) or [updateState]; the simulation reads the same
/// node/wire lists and writes visual updates back via `batchSimulationUpdate`.
@Riverpod(keepAlive: true)
class CanvasController()
    extends _$CanvasController
    with CanvasControllerMixin
    implements CanvasContext {
  late final HistoryManager historyManager;
  late final SelectionManager selectionManager;
  late final WiringManager wiringManager;
  late final ClipboardOps _clipboardOps;
  late final ViewportOps _viewportOps;
  final contextMenuController = AppContextMenuController();

  /// Which node the context menu was opened on, or null for the background.
  ///
  /// Deliberately not in [CanvasState]: it is set while a secondary-tap
  /// gesture is in flight, and routing that through the state would rebuild
  /// the canvas subtree mid-gesture — the shape of more than one past
  /// dropped-drag bug. A listenable reaches the menu without touching anyone
  /// else.
  final contextMenuNode = ValueNotifier<ComponentInstance?>(null);

  @override
  List<WireModel> get wires => state.wires;

  @override
  List<ComponentInstance> get nodes => state.nodes;

  /// Centralizes the analytics call sites that were previously interleaved
  /// directly through nearly every public method.
  void _track(String action) => ref.read(analyticsProvider).canvasAction(action);

  this {
    historyManager = HistoryManager();
    selectionManager = SelectionManager(this);
    wiringManager = WiringManager(this);
    _clipboardOps = ClipboardOps(this);
    _viewportOps = ViewportOps(this);
  }

  @override
  CanvasState build() {
    ref.onDispose(viewerController.dispose);
    return const CanvasState();
  }

  void updateCircuit(List<ComponentInstance> newNodes, List<WireModel> newWires) {
    state = state.copyWith(nodes: newNodes, wires: newWires);
  }

  @override
  String? get hoveredWireId => selectionManager.hoveredWireId;
  @override
  set hoveredWireId(String? id) => selectionManager.hoveredWireId = id;

  @override
  List<String> get selectedWireIds => selectionManager.selectedWireIds;
  @override
  set selectedWireIds(List<String> ids) => selectionManager.selectedWireIds = ids;

  @override
  void selectWire(String? id) => selectionManager.selectWire(id);

  @override
  bool get isWiring => wiringManager.isWiring;

  @override
  bool checkWireInteraction(Offset canvasPosition) =>
      wiringManager.checkWireInteraction(canvasPosition);

  @override
  double? selectedBendHandleDistance(Offset canvasPosition) =>
      wiringManager.selectedBendHandleDistance(canvasPosition);

  @override
  bool isSelectedWireEndpoint(PortLocation port) => wiringManager.isSelectedWireEndpoint(port);

  @override
  PortLocation? selectedEndpointAt(Offset canvasPosition) =>
      wiringManager.selectedEndpointAt(canvasPosition);

  @override
  void forceUpdate() {
    state = state.copyWith();
  }

  @override
  void executeCommand(CanvasCommand command) {
    historyManager.execute(command, this);
  }

  @override
  void updateState({
    List<ComponentInstance>? nodes,
    List<WireModel>? wires,
    List<ComponentInstance>? selectedNodes,
    List<ComponentInstance>? clipboardNodes,
    List<WireModel>? clipboardWires,
    List<double>? verticalGuidelines,
    List<double>? horizontalGuidelines,
  }) {
    state = state.copyWith(
      nodes: nodes,
      wires: wires,
      selectedNodes: selectedNodes,
      clipboardNodes: clipboardNodes,
      clipboardWires: clipboardWires,
      verticalGuidelines: verticalGuidelines,
      horizontalGuidelines: horizontalGuidelines,
    );
    if (nodes != null) _pruneLiveProperties(nodes);
  }

  void clearGuidelines() {
    state = state.copyWith(verticalGuidelines: const [], horizontalGuidelines: const []);
  }

  void undo() {
    if (isReadOnly) return;
    _track('undo');
    historyManager.undo(this);
  }

  void redo() {
    if (isReadOnly) return;
    _track('redo');
    historyManager.redo(this);
  }

  void copy() {
    if (isReadOnly) return;
    _clipboardOps.copy();
  }

  void paste() {
    if (isReadOnly) return;
    _clipboardOps.paste();
  }

  void add(ComponentInstance child) {
    if (isReadOnly) return;
    if (nodes.length >= 200) {
      // Component count cap — prevents OOM with many thousands of nodes.
      return;
    }
    ref.read(analyticsProvider).componentAdded(child.part.definitionId ?? child.part.name);
    executeCommand(AddNodeCommand(child));
  }

  void remove() {
    if (isReadOnly) return;
    _track('delete');
    final toRemoveNodes = nodes.where((n) => selectedNodes.any((sel) => sel.key == n.key)).toList();
    final toRemoveWires = wires
        .where(
          (w) =>
              selectedWireIds.contains(w.id) ||
              selectedNodes.any((n) => w.start.nodeKey == n.key || w.end.nodeKey == n.key),
        )
        .toList();

    if (toRemoveNodes.isNotEmpty || toRemoveWires.isNotEmpty) {
      executeCommand(
        RemoveSelectionCommand(removedNodes: toRemoveNodes, removedWires: toRemoveWires),
      );
    }
  }

  // ── Wiring delegates (analytics-wrapped) ──────────────────────────────────────

  void startWiring(
    PortLocation port,
    Offset canvasPos, {
    List<Offset>? bendPoints,
    bool isMovingExisting = false,
    PortLocation? originalDetachedPort,
    String? movingWireId,
  }) {
    _track('wire_start');
    wiringManager.startWiring(
      port,
      canvasPos,
      bendPoints: bendPoints,
      isMovingExisting: isMovingExisting,
      originalDetachedPort: originalDetachedPort,
      movingWireId: movingWireId,
    );
  }

  void cancelWiring() {
    _track('wire_cancel');
    wiringManager.cancelWiring();
  }

  /// Updates multiple nodes' properties in a single state write.
  /// Used by the simulation loop to batch all per-frame visual changes
  /// into one Riverpod notification instead of N separate rebuilds.
  /// Per-node visual state written by a running simulation — an LED's `isOn`,
  /// a servo's angle, an OLED's picture.
  ///
  /// Deliberately *not* part of [state]. The engine flushes these at 60fps, and
  /// while they lived in the canvas state every frame replaced the node list
  /// and notified every watcher of this provider: the whole canvas subtree
  /// rebuilt, the minimap repainted all its nodes, and the toolbar recomputed
  /// its enabled flags — sixty times a second, to light one LED.
  ///
  /// One notifier per node, so only the component that changed rebuilds. They
  /// are also transient by construction: nothing here reaches undo history or
  /// the `.cdl` a workspace saves, which is what a blink state should never
  /// have been part of.
  final Map<LocalKey, ValueNotifier<Map<String, dynamic>>> _liveProperties = {};

  /// The live visual state for [key], created on first use.
  ///
  /// Read by `CanvasNodeWidget`, which merges it over the node's own
  /// properties — the engine sends only the keys that changed, and user-set
  /// keys like `Color` must survive.
  ValueListenable<Map<String, dynamic>> liveProperties(LocalKey key) =>
      _liveProperties.putIfAbsent(key, () => ValueNotifier(const {}));

  void batchSimulationUpdate(Map<LocalKey, Map<String, dynamic>> updates) {
    if (updates.isEmpty) return;
    for (final entry in updates.entries) {
      final notifier = _liveProperties.putIfAbsent(entry.key, () => ValueNotifier(const {}));
      notifier.value = {...notifier.value, ...entry.value};
    }
  }

  /// Drops live state for nodes that no longer exist. Called wherever the node
  /// list is replaced wholesale — opening a circuit, or undoing back past the
  /// part that was lit.
  void _pruneLiveProperties(List<ComponentInstance> currentNodes) {
    if (_liveProperties.isEmpty) return;
    final live = currentNodes.map((n) => n.key).toSet();
    _liveProperties.removeWhere((key, notifier) {
      if (live.contains(key)) return false;
      notifier.dispose();
      return true;
    });
  }

  void updateNodeProperties(
    LocalKey key,
    Map<String, dynamic> newProperties, {
    bool recordHistory = true,
  }) {
    final index = nodes.indexWhere((n) => n.key == key);
    if (index != -1) {
      final oldNode = nodes[index];
      final newNode = oldNode.copyWith(properties: newProperties);
      if (recordHistory) {
        executeCommand(UpdateNodeCommand(key, oldNode, newNode));
      } else {
        UpdateNodeCommand(key, oldNode, newNode).execute(this);
      }
    }
  }

  /// Changes the part [key] is placed as to its configuration whose
  /// choosing property is [value] — a transistor to another Type.
  ///
  /// Each wire on it moves to the pin doing the same job in the new
  /// configuration (see `PartRegistry.pinCorrespondence`); one whose pin has
  /// no counterpart is removed. One step to undo, wires and all.
  void reconfigureNode(LocalKey key, String value) {
    final oldNode = nodes.where((n) => n.key == key).firstOrNull;
    final from = PartRegistry.getPart(oldNode?.part.definitionId ?? '');
    final configuration = from?.configuration;
    if (oldNode == null || from == null || configuration == null) return;
    final to = PartRegistry.configurationFor(from, value);
    if (to == null || to.id == from.id) return;

    final pins = PartRegistry.pinCorrespondence(from, to);
    PortLocation? moved(PortLocation end) {
      if (end.nodeKey != key) return end;
      final pin = pins[end.portId];
      return pin == null ? null : PortLocation(nodeKey: key, portId: pin);
    }

    final oldWires = wires.where((w) => w.start.nodeKey == key || w.end.nodeKey == key).toList();
    final newWires = [
      for (final wire in oldWires)
        if ((moved(wire.start), moved(wire.end)) case (final start?, final end?))
          wire.copyWith(start: start, end: end),
    ];
    executeCommand(
      ReplaceNodeCommand(
        oldNode: oldNode,
        newNode: oldNode.copyWith(
          part: PartModel.fromDefinition(to),
          properties: {...oldNode.properties, configuration.property: value},
        ),
        oldWires: oldWires,
        newWires: newWires,
      ),
    );
  }

  void updateNode(
    LocalKey key, {
    Offset? position,
    double? rotationAngle,
    bool? flipHorizontal,
    bool? flipVertical,
    double? customWidth,
    double? customHeight,
    bool clearCustomWidth = false,
    bool clearCustomHeight = false,
  }) {
    if (isReadOnly) return;
    final index = nodes.indexWhere((n) => n.key == key);
    if (index != -1) {
      final oldNode = nodes[index];
      final newNode = oldNode.copyWith(
        position: position ?? oldNode.position,
        rotationAngle: rotationAngle ?? oldNode.rotationAngle,
        flipHorizontal: flipHorizontal ?? oldNode.flipHorizontal,
        flipVertical: flipVertical ?? oldNode.flipVertical,
        customWidth: customWidth,
        customHeight: customHeight,
        clearCustomWidth: clearCustomWidth,
        clearCustomHeight: clearCustomHeight,
      );
      executeCommand(UpdateNodeCommand(key, oldNode, newNode));
    }
  }

  void fitToContent(Size viewportSize) => _viewportOps.fitToContent(viewportSize);

  void completeWiring(PortLocation endPort) {
    _track('wire_complete');
    wiringManager.completeWiring(endPort);
  }

  void createBendPointAt(Offset canvasPosition) {
    wiringManager.toggleBendPointAt(canvasPosition);
  }

  void updateWireColor(Color? newColor) {
    if (newColor != null && selectionManager.selectedWireIds.isNotEmpty) {
      final oldWires = <WireModel>[];
      final updatedWires = <WireModel>[];

      for (final id in selectionManager.selectedWireIds) {
        final wireIndex = wires.indexWhere((w) => w.id == id);
        if (wireIndex != -1) {
          final wire = wires[wireIndex];
          oldWires.add(wire);
          updatedWires.add(wire.copyWith(color: newColor));
        }
      }

      if (updatedWires.isNotEmpty) {
        executeCommand(UpdateWiresCommand(oldWires, updatedWires));
      }
      return;
    }
    wiringManager.updateWireColor(newColor);
  }

  void _updateSelectedNodes(ComponentInstance Function(ComponentInstance) updater) {
    if (isReadOnly || selectedNodes.isEmpty) return;

    final oldNodesList = <ComponentInstance>[];
    final newNodesList = <ComponentInstance>[];

    for (final oldNode in selectedNodes) {
      oldNodesList.add(oldNode);
      newNodesList.add(updater(oldNode));
    }

    executeCommand(UpdateNodesCommand(oldNodesList, newNodesList));
  }

  /// One press of rotate. Eight steps to the full turn, so the four axis
  /// alignments a part is normally wired at are all reachable, with the
  /// diagonals in between.
  static const rotationStep = math.pi / 4;

  void _rotateSelected(double angleDelta) {
    _updateSelectedNodes((oldNode) {
      final oldPivotCanvas = oldNode.position + oldNode.pivotOffset;
      final updatedNode = oldNode.copyWith(
        rotationAngle: _normalizeAngle(oldNode.rotationAngle + angleDelta),
      );
      var newPosition = oldPivotCanvas - updatedNode.pivotOffset;

      // Turning about the pivot keeps the part where you put it, but the pivot
      // is the top-centre of its bounding box and the legs are somewhere else
      // — so a part that was plugged in comes out of its holes by whatever the
      // rotation moved the legs by. Put them back: into the board's own holes
      // if it's on one (they need not be on the grid — a rotated board's
      // aren't, nor a half board's rails), otherwise onto the lattice.
      if (snapToGrid) {
        final toHole = BreadboardSnapHelper.holeAdjustment(
          node: updatedNode.copyWith(position: newPosition),
          position: newPosition,
          boards: nodes.where((n) => n.key != oldNode.key).toList(),
        );
        newPosition = toHole != null
            ? newPosition + toHole
            : SnapGuideHelper.snapNodeToLattice(updatedNode, newPosition);
      }
      return updatedNode.copyWith(position: newPosition);
    });
  }

  /// Keeps the angle in [0, 2π). Rotation is periodic, so this changes nothing
  /// on the canvas — it stops a part that's been spun a few times from being
  /// written out as `1080deg`, and lets a full turn back to square write no
  /// rotation at all (see `CdlWriter`).
  static double _normalizeAngle(double radians) {
    const turn = 2 * math.pi;
    final wrapped = radians % turn;
    final positive = wrapped < 0 ? wrapped + turn : wrapped;
    // Eight steps of π/4 need not add up to exactly 2π in binary floating
    // point; landing a hair short would otherwise persist as `360deg`.
    return (turn - positive).abs() < 1e-9 ? 0.0 : positive;
  }

  void rotateRight() => _rotateSelected(rotationStep);
  void rotateLeft() => _rotateSelected(-rotationStep);
  void flipHorizontal() =>
      _updateSelectedNodes((node) => node.copyWith(flipHorizontal: !node.flipHorizontal));
  void flipVertical() =>
      _updateSelectedNodes((node) => node.copyWith(flipVertical: !node.flipVertical));

  @override
  void toggleGrid() {
    super.toggleGrid();
    _track('grid_toggle');
  }

  @override
  void zoomIn() {
    _track('zoom_in');
    super.zoomIn();
  }

  @override
  void zoomOut() {
    _track('zoom_out');
    super.zoomOut();
  }

  /// Guard helper: executes [action] only when the canvas is not in read-only
  /// mode. Replaces the repeated `if (isReadOnly) return;` boilerplate.
  void _executeIfWritable(void Function() action) {
    if (isReadOnly) return;
    action();
  }

  void layerUp() => _executeIfWritable(() {
    if (selectedWireIds.isNotEmpty) {
      _reorderSelectedWires(1);
    } else if (selectedNodes.isNotEmpty) {
      _reorderSelected(1);
    }
  });

  void layerDown() => _executeIfWritable(() {
    if (selectedWireIds.isNotEmpty) {
      _reorderSelectedWires(-1);
    } else if (selectedNodes.isNotEmpty) {
      _reorderSelected(-1);
    }
  });

  /// Moves all [selectedNodes] up or down by [delta] positions in the [nodes]
  /// list. A delta of +1 moves nodes toward the top of the render stack
  /// (painted last); -1 moves them toward the bottom.
  void _reorderSelected(int delta) {
    final newNodes = List<ComponentInstance>.from(nodes);
    final isUp = delta > 0;
    final sorted = List<ComponentInstance>.from(selectedNodes)
      ..sort((a, b) {
        final cmp = newNodes.indexOf(a).compareTo(newNodes.indexOf(b));
        return isUp ? -cmp : cmp;
      });

    for (final oldNode in sorted) {
      final index = newNodes.indexOf(oldNode);
      final boundary = isUp ? newNodes.length - 1 : 0;
      if (index == -1 || index == boundary) continue;
      final node = newNodes.removeAt(index);
      newNodes.insert(index + delta, node);
    }

    executeCommand(ReorderNodesCommand(nodes, newNodes));
  }

  /// Moves the selected wires up or down by [delta] positions in the [wires]
  /// list — the paint order among wires, since `WirePainter` draws them in
  /// list order. +1 is toward the top of the stack (painted last), -1 toward
  /// the bottom.
  void _reorderSelectedWires(int delta) {
    final newWires = List<WireModel>.from(wires);
    final isUp = delta > 0;
    final sorted = newWires.where((w) => selectedWireIds.contains(w.id)).toList()
      ..sort((a, b) {
        final cmp = newWires.indexOf(a).compareTo(newWires.indexOf(b));
        return isUp ? -cmp : cmp;
      });

    for (final wire in sorted) {
      final index = newWires.indexOf(wire);
      final boundary = isUp ? newWires.length - 1 : 0;
      if (index == -1 || index == boundary) continue;
      newWires.removeAt(index);
      newWires.insert(index + delta, wire);
    }

    executeCommand(ReorderWiresCommand(wires, newWires));
  }

  Offset? _boxSelectionStart;

  void startBoxSelection(Offset canvasPos) {
    _boxSelectionStart = canvasPos;
    boxSelectionRect = Rect.fromPoints(canvasPos, canvasPos);
    selectionManager.clearSelection();
  }

  void updateBoxSelection(Offset canvasPos) {
    if (_boxSelectionStart != null) {
      final newRect = Rect.fromPoints(_boxSelectionStart!, canvasPos);

      final newSelectedNodes = <ComponentInstance>[];
      for (final node in nodes) {
        if (newRect.overlaps(node.rect)) {
          newSelectedNodes.add(node);
        }
      }

      final newSelectedWireIds = <String>[];
      for (final wire in wires) {
        if (_wireOverlapsRect(wire, newRect)) {
          newSelectedWireIds.add(wire.id);
        }
      }

      selectionManager.selectedWireIds = newSelectedWireIds;
      state = state.copyWith(boxSelectionRect: newRect, selectedNodes: newSelectedNodes);
    }
  }

  bool _wireOverlapsRect(WireModel wire, Rect rect) {
    final startPos = wiringManager.getPortPosition(wire.start);
    final endPos = wiringManager.getPortPosition(wire.end);
    if (startPos == null || endPos == null) return false;

    final points = <Offset>[startPos, ...wire.bendPoints, endPos];
    for (var i = 0; i < points.length - 1; i++) {
      if (rect.overlaps(Rect.fromPoints(points[i], points[i + 1]))) {
        return true;
      }
    }
    return false;
  }

  void endBoxSelection() {
    _boxSelectionStart = null;
    state = state.copyWith(clearBoxSelection: true);
  }
}
