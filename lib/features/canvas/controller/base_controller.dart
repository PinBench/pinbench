import 'package:flutter/widgets.dart';

import 'package:interactive_viewer_plus/interactive_viewer_plus.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'canvas_state.dart';

mixin CanvasControllerMixin {
  final viewerController = InteractiveViewerPlusController();

  CanvasState get state;
  set state(CanvasState value);

  double get gridCellSize => GridSystem.cellSize;
  bool get snapToGrid => state.snapToGrid;
  bool get showGrid => state.showGrid;

  void toggleGrid() {
    state = state.copyWith(showGrid: !state.showGrid);
  }

  var minScale = 0.02;
  var maxScale = 8.0;

  double get scale => viewerController.value.getMaxScaleOnAxis();

  Offset get offset {
    final translation = viewerController.value.getTranslation();
    return Offset(translation.x, translation.y);
  }

  void centerOrigin(Size size) {
    viewerController.value = Matrix4.translationValues(size.width / 2, size.height / 2, 0.0);
  }

  Size viewportSize = Size.zero;

  Rect get visibleRect {
    if (viewportSize == Size.zero) return Rect.zero;
    final topLeft = screenToCanvasCoordinates(Offset.zero);
    final bottomRight = screenToCanvasCoordinates(Offset(viewportSize.width, viewportSize.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  // Not in state because it updates frequently on mouse move
  Offset mouseLocalPosition = Offset.zero;

  // Track currently interacted node (e.g., clicking and holding a push button)
  Key? interactingNodeKey;

  Matrix4 get transform => viewerController.value;

  void zoomIn() => zoomAt(1.1, _zoomFocalPoint);
  void zoomOut() => zoomAt(0.9, _zoomFocalPoint);
  void zoomReset() => viewerController.value = Matrix4.identity();

  /// Zoom about the cursor when it has been over the canvas; otherwise (e.g.
  /// zoom buttons clicked before any canvas hover) about the viewport center.
  Offset get _zoomFocalPoint => mouseLocalPosition == Offset.zero && viewportSize != Size.zero
      ? Offset(viewportSize.width / 2, viewportSize.height / 2)
      : mouseLocalPosition;

  /// Scales the view by [factor] about [focalPointScreen] (in viewport
  /// coordinates), so the canvas point under the focal point stays put.
  /// The resulting scale is clamped to [minScale]..[maxScale].
  void zoomAt(double factor, Offset focalPointScreen) {
    final current = scale;
    final target = (current * factor).clamp(minScale, maxScale);
    final effective = target / current;
    if ((effective - 1).abs() < 1e-9) return;

    viewerController.value = Matrix4.identity()
      ..translateByDouble(focalPointScreen.dx, focalPointScreen.dy, 0, 1)
      ..scaleByDouble(effective, effective, effective, 1)
      ..translateByDouble(-focalPointScreen.dx, -focalPointScreen.dy, 0, 1)
      ..multiply(viewerController.value);
  }

  void panUp() => viewerController.pan(const Offset(0, 50));
  void panDown() => viewerController.pan(const Offset(0, -50));
  void panLeft() => viewerController.pan(const Offset(50, 0));
  void panRight() => viewerController.pan(const Offset(-50, 0));

  bool get mouseDown => state.mouseDown;
  set mouseDown(bool value) {
    if (value == state.mouseDown) return;
    state = state.copyWith(mouseDown: value);
  }

  Offset? get dragStartOffset => state.dragStartOffset;
  set dragStartOffset(Offset? offset) {
    state = state.copyWith(dragStartOffset: offset, clearDragStartOffset: offset == null);
  }

  List<ComponentInstance> get selectedNodes => state.selectedNodes;
  set selectedNodes(List<ComponentInstance> nodes) {
    state = state.copyWith(selectedNodes: nodes);
  }

  /// Whether dragging the background pans the canvas, rather than starting a
  /// box selection or continuing a drag. Derived from [CanvasState], so it
  /// lives there and is read through here like every other state accessor.
  bool get canvasMoveEnabled => state.canvasMoveEnabled;

  /// True while a simulation owns the canvas: edits are refused so the running
  /// circuit cannot be changed underneath the engine.
  bool get isReadOnly => state.isReadOnly;
  set isReadOnly(bool value) {
    if (value == state.isReadOnly) return;
    state = state.copyWith(isReadOnly: value);
  }

  Rect? get boxSelectionRect => state.boxSelectionRect;
  set boxSelectionRect(Rect? rect) {
    state = state.copyWith(boxSelectionRect: rect, clearBoxSelection: rect == null);
  }

  List<ComponentInstance>? get clipboardNodes => state.clipboardNodes;
  set clipboardNodes(List<ComponentInstance>? nodes) {
    state = state.copyWith(clipboardNodes: nodes);
  }

  List<WireModel>? get clipboardWires => state.clipboardWires;
  set clipboardWires(List<WireModel>? wires) {
    state = state.copyWith(clipboardWires: wires);
  }

  ComponentInstance? get hoveredNode => state.hoveredNode;
  set hoveredNode(ComponentInstance? node) {
    state = state.copyWith(hoveredNode: node, clearHoveredNode: node == null);
  }

  PortLocation? get hoveredPort => state.hoveredPort;
  set hoveredPort(PortLocation? port) {
    state = state.copyWith(hoveredPort: port, clearHoveredPort: port == null);
  }

  Offset screenToCanvasCoordinates(Offset screenPosition) =>
      viewerController.toScene(screenPosition);

  Offset canvasToScreenCoordinates(Offset canvasPosition) => (canvasPosition * scale) + offset;

  void centerOn(Offset canvasPosition) {
    if (viewportSize == Size.zero) return;

    final currentScale = scale;
    final screenCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final targetOffset = screenCenter - (canvasPosition * currentScale);

    viewerController.value = Matrix4.diagonal3Values(currentScale, currentScale, 1.0)
      ..setTranslationRaw(targetOffset.dx, targetOffset.dy, 0.0);
  }
}
