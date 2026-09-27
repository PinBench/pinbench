import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

@immutable
class CanvasState {
  final List<ComponentInstance> nodes;
  final List<WireModel> wires;

  final List<ComponentInstance> selectedNodes;
  // Wire selection lives on SelectionManager.selectedWireIds, not here — see
  // CanvasContext.selectedWireIds.

  final Rect? boxSelectionRect;
  final List<ComponentInstance>? clipboardNodes;
  final List<WireModel>? clipboardWires;

  final ComponentInstance? hoveredNode;
  final PortLocation? hoveredPort;
  final String? hoveredWireId;

  final bool snapToGrid;
  final bool showGrid;

  final List<double> verticalGuidelines;
  final List<double> horizontalGuidelines;

  final bool mouseDown;
  final Offset? dragStartOffset;

  /// True while a simulation owns the canvas, which refuses edits.
  final bool isReadOnly;

  /// Whether dragging the background pans the canvas.
  ///
  /// False while the pointer is down on something, or while a box selection is
  /// being dragged out — in both cases the drag already means something else.
  bool get canvasMoveEnabled => !mouseDown && boxSelectionRect == null;

  const CanvasState({
    this.nodes = const [],
    this.wires = const [],
    this.selectedNodes = const [],
    this.boxSelectionRect,
    this.clipboardNodes,
    this.clipboardWires,
    this.hoveredNode,
    this.hoveredPort,
    this.hoveredWireId,
    this.snapToGrid = true,
    this.showGrid = true,
    this.verticalGuidelines = const [],
    this.horizontalGuidelines = const [],
    this.mouseDown = false,
    this.isReadOnly = false,
    this.dragStartOffset,
  });

  CanvasState copyWith({
    List<ComponentInstance>? nodes,
    List<WireModel>? wires,
    List<ComponentInstance>? selectedNodes,
    Rect? boxSelectionRect,
    bool clearBoxSelection = false,
    List<ComponentInstance>? clipboardNodes,
    List<WireModel>? clipboardWires,
    ComponentInstance? hoveredNode,
    bool clearHoveredNode = false,
    PortLocation? hoveredPort,
    bool clearHoveredPort = false,
    String? hoveredWireId,
    bool clearHoveredWireId = false,
    bool? snapToGrid,
    bool? showGrid,
    List<double>? verticalGuidelines,
    List<double>? horizontalGuidelines,
    bool? mouseDown,
    bool? isReadOnly,
    Offset? dragStartOffset,
    bool clearDragStartOffset = false,
  }) => CanvasState(
    nodes: nodes ?? this.nodes,
    wires: wires ?? this.wires,
    selectedNodes: selectedNodes ?? this.selectedNodes,
    boxSelectionRect: clearBoxSelection ? null : (boxSelectionRect ?? this.boxSelectionRect),
    clipboardNodes: clipboardNodes ?? this.clipboardNodes,
    clipboardWires: clipboardWires ?? this.clipboardWires,
    hoveredNode: clearHoveredNode ? null : (hoveredNode ?? this.hoveredNode),
    hoveredPort: clearHoveredPort ? null : (hoveredPort ?? this.hoveredPort),
    hoveredWireId: clearHoveredWireId ? null : (hoveredWireId ?? this.hoveredWireId),
    snapToGrid: snapToGrid ?? this.snapToGrid,
    showGrid: showGrid ?? this.showGrid,
    verticalGuidelines: verticalGuidelines ?? this.verticalGuidelines,
    horizontalGuidelines: horizontalGuidelines ?? this.horizontalGuidelines,
    mouseDown: mouseDown ?? this.mouseDown,
    isReadOnly: isReadOnly ?? this.isReadOnly,
    dragStartOffset: clearDragStartOffset ? null : (dragStartOffset ?? this.dragStartOffset),
  );

  Map<String, dynamic> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'wires': wires.map((w) => w.toJson()).toList(),
    'snapToGrid': snapToGrid,
    'showGrid': showGrid,
  };

  factory CanvasState.fromJson(Map<String, dynamic> json) => CanvasState(
    nodes: (json['nodes'] as List)
        .map((n) => ComponentInstance.fromJson(n as Map<String, dynamic>))
        .toList(),
    wires: (json['wires'] as List)
        .map((w) => WireModel.fromJson(w as Map<String, dynamic>))
        .toList(),
    snapToGrid: json['snapToGrid'] as bool? ?? true,
    showGrid: json['showGrid'] as bool? ?? true,
  );
}
