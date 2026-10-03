import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import '../../controller/canvas_controller.dart';
import 'pointer_interaction_mode.dart';
import 'pointer_mode_resolver.dart';

class const CanvasPointerEvent({
  super.key,
  required final Widget child,
  required final CanvasController controller,
}) extends StatefulWidget {
  @override
  State<CanvasPointerEvent> createState() => _CanvasPointerEventState();
}

class _CanvasPointerEventState extends State<CanvasPointerEvent> {
  CanvasController get controller => widget.controller;

  Offset _getLocalPosition(PointerEvent event) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      return renderBox.globalToLocal(event.position);
    }
    return event.localPosition;
  }

  var _isDraggingDuringWiring = false;
  Offset? _startDownPos;
  var _lastClickTime = 0;
  var _hasSavedHistoryForDrag = false;
  var _isBoxSelecting = false;
  var _isPanning = false;

  /// A middle-button drag, or a left drag with Space held, pans the view
  /// with the mouse. A plain left drag already means box select, so panning
  /// needs a button or key of its own, as in Figma or KiCad.
  bool _startsPan(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.mouse &&
      (event.buttons == kMiddleMouseButton ||
          (event.buttons == kPrimaryMouseButton &&
              HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space)));

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerUp: onPointerUp,
    onPointerDown: onPointerDown,
    onPointerMove: onPointerMove,
    onPointerHover: onPointerHover,
    onPointerCancel: onPointerCancel,
    child: widget.child,
  );

  void onPointerCancel(PointerCancelEvent event) {
    _isPanning = false;
    if (_isBoxSelecting) {
      controller.endBoxSelection();
      _isBoxSelecting = false;
    }
    controller.mouseDown = false;
    controller.dragStartOffset = null;
  }

  void onPointerHover(PointerHoverEvent event) {
    final localPosition = _getLocalPosition(event);
    controller.mouseLocalPosition = localPosition;
    final canvasPos = controller.screenToCanvasCoordinates(localPosition);

    if (controller.isReadOnly) {
      if (controller.hoveredNode != null ||
          controller.hoveredPort != null ||
          controller.hoveredWireId != null) {
        controller.hoveredNode?.breadboardHover = null;
        controller.hoveredNode?.hoveredLocalPosition = null;
        controller.hoveredNode = null;
        controller.hoveredPort = null;
        controller.hoveredWireId = null;
        controller.forceUpdate();
      }
      return;
    }

    if (controller.wiringManager.isWiring) {
      controller.selectionManager.checkHover();
      controller.wiringManager.updateWiring(canvasPos);
    } else if (!controller.mouseDown) {
      controller.selectionManager.checkHover();
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    final localPosition = _getLocalPosition(event);
    controller.mouseLocalPosition = localPosition;

    // Moving the view is not an edit, so it works while a simulation runs.
    if (_isPanning) {
      controller.panByScreen(event.delta);
      return;
    }

    final canvasPos = controller.screenToCanvasCoordinates(localPosition);

    if (controller.isReadOnly) return;

    if (controller.wiringManager.isWiring) {
      controller.selectionManager.checkHover();
      controller.wiringManager.updateWiring(canvasPos);

      if (_startDownPos != null && (localPosition - _startDownPos!).distance > 5) {
        _isDraggingDuringWiring = true;
      }
    } else if (controller.wiringManager.isDraggingBendPoint) {
      if (!_hasSavedHistoryForDrag) {
        _hasSavedHistoryForDrag = true;
      }
      controller.wiringManager.updateDraggingBendPoint(canvasPos);
    } else if (_isBoxSelecting) {
      controller.updateBoxSelection(canvasPos);
    } else {
      if (controller.selectedNodes.isNotEmpty &&
          !_hasSavedHistoryForDrag &&
          _startDownPos != null &&
          (localPosition - _startDownPos!).distance > 2) {
        controller.selectionManager.startDragSelection();
        _hasSavedHistoryForDrag = true;
      }
      controller.selectionManager.moveSelection(event.delta);
    }
  }

  void onPointerUp(PointerUpEvent event) {
    if (_isPanning) {
      _isPanning = false;
      controller.mouseDown = false;
      controller.dragStartOffset = null;
      return;
    }

    if (controller.interactingNodeKey != null) {
      final node = controller.nodes.firstWhereOrNull((n) => n.key == controller.interactingNodeKey);
      if (node != null) {
        final props = Map<String, dynamic>.from(node.properties)
          ..remove(ComponentProps.pressedRegion);
        if (node.part.name == PartNames.pushButton) props[ComponentProps.isPressed] = false;
        controller.updateNodeProperties(node.key, props, recordHistory: false);
      }
      controller.interactingNodeKey = null;
    }

    if (controller.isReadOnly) {
      controller.mouseDown = false;
      controller.dragStartOffset = null;
      return;
    }

    if (controller.wiringManager.isWiring) {
      if (_isDraggingDuringWiring && controller.hoveredPort != null) {
        controller.completeWiring(controller.hoveredPort!);
      } else if (controller.wiringManager.isMovingWireEndpoint &&
          controller.wiringManager.originalDetachedPort != null) {
        // Moving an existing wire's end: it was detached (removed) on grab, so
        // letting go anywhere that isn't a port has to put it back where it
        // was. Dropping it into empty space used to delete the whole wire —
        // a click's worth of imprecision losing work that was never asked to
        // be deleted.
        controller.completeWiring(controller.wiringManager.originalDetachedPort!);
      } else if (_isDraggingDuringWiring) {
        controller.cancelWiring();
      }
    } else if (controller.wiringManager.isDraggingBendPoint) {
      controller.wiringManager.stopDraggingBendPoint();
    } else if (_isBoxSelecting) {
      controller.endBoxSelection();
      _isBoxSelecting = false;
    } else {
      if (_hasSavedHistoryForDrag) {
        controller.selectionManager.commitDragSelection();
      }
    }

    controller.clearGuidelines();
    controller.mouseDown = false;
    controller.dragStartOffset = null;
  }

  void onPointerDown(PointerDownEvent event) {
    final localPosition = _getLocalPosition(event);
    controller.mouseDown = true;
    controller.mouseLocalPosition = localPosition;
    final canvasPos = controller.screenToCanvasCoordinates(localPosition);
    _startDownPos = localPosition;
    _isDraggingDuringWiring = false;
    _hasSavedHistoryForDrag = false;
    _isBoxSelecting = false;
    _isPanning = false;

    if (controller.contextMenuController.isOpen) {
      controller.contextMenuController.hide();
    }

    // Before anything that reads the press as a selection, a wire grab or a
    // button push: a pan touches none of them.
    if (_startsPan(event)) {
      _isPanning = true;
      return;
    }

    // Re-resolve hover against the *current* state before deciding what this
    // press means. Hover is only recomputed when the pointer moves, but what a
    // pixel means changes without it moving: the click that selects a wire
    // turns its end circles into grabbable handles, and the hand that clicked
    // is already parked on one. Pressing again — the natural "now drag that
    // end somewhere else" — used to be judged against hover from before the
    // selection, where the end was just wire: the press fell through to
    // "start a bend-point drag" and did nothing, or missed the segment by a
    // pixel and deselected the wire it was trying to grab.
    if (!controller.isReadOnly) {
      controller.selectionManager.checkHover();
    }

    if (event.buttons == kSecondaryMouseButton) {
      _handleContextMenuClick(event.position);
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleClick = now - _lastClickTime < 300;
    _lastClickTime = now;

    final mode = PointerModeResolver.resolveForPointerDown(
      isReadOnly: controller.isReadOnly,
      isWiring: controller.wiringManager.isWiring,
      isDoubleClick: isDoubleClick,
      hoveredWireId: controller.selectionManager.hoveredWireId,
      hoveredPort: controller.hoveredPort,
    );

    switch (mode) {
      case PointerInteractionMode.readOnlyTap:
        _handleReadOnlyTap(canvasPos);
      case PointerInteractionMode.continueWiring:
        _handleContinueWiring();
      case PointerInteractionMode.toggleBendPoint:
        controller.wiringManager.toggleBendPointAt(canvasPos);
      case PointerInteractionMode.startWiring:
        _handleStartWiring(controller.hoveredPort!, canvasPos);
      case PointerInteractionMode.needsSelectionCheck:
        _handleAfterSelectionCheck(canvasPos);
    }
  }

  /// Resolves a [PointerInteractionMode.needsSelectionCheck] pointer-down
  /// into one of [PostSelectionMode]'s values — these can only be told apart
  /// after `checkSelection()` runs (see that mode's doc comment).
  void _handleAfterSelectionCheck(Offset canvasPos) {
    if (controller.selectionManager.hoveredWireId != null) {
      controller.selectionManager.checkSelection();
      if (controller.selectionManager.hoveredWireId != null &&
          controller.selectionManager.selectedWireIds.contains(
            controller.selectionManager.hoveredWireId,
          )) {
        // PostSelectionMode.startBendPointDrag
        controller.wiringManager.startDraggingBendPoint(canvasPos);
        return;
      }
    }

    // PostSelectionMode.nodeSelect / PostSelectionMode.boxSelect — fallback
    // node interaction, or empty space.
    _handleNodeOrBoxSelect(canvasPos);
  }

  void _handleContextMenuClick(Offset globalPosition) {
    if (controller.isReadOnly) return;
    // checkSelection gives wires priority: a right-click on a wire selects it
    // (and clears any node selection), which is what routes the menu — and
    // ⌘]/⌘[ — to the wire.
    controller.selectionManager.checkSelection();

    if (controller.hoveredNode != null) {
      if (!controller.selectedNodes.any((n) => n.key == controller.hoveredNode!.key)) {
        controller.selectedNodes = [controller.hoveredNode!];
      }
      controller.contextMenuNode.value = controller.hoveredNode;
    } else if (controller.selectionManager.selectedWireIds.isNotEmpty) {
      controller.contextMenuNode.value = null;
    } else {
      return;
    }

    // Nudged clear of the cursor so the first item is not already under it.
    controller.contextMenuController.showAt(globalPosition + const Offset(4, 4));
    controller.forceUpdate();
  }

  void _handleReadOnlyTap(Offset canvasPos) {
    // Only allow interacting with PushButton
    ComponentInstance? found;
    for (final node in controller.nodes.reversed) {
      if (node.rect.contains(canvasPos)) {
        found = node;
        break;
      }
    }

    if (found == null) return;
    if (_pressRegion(found, canvasPos)) return;
    if (found.part.name == PartNames.pushButton) {
      controller.interactingNodeKey = found.key;
      final props = Map<String, dynamic>.from(found.properties);
      props[ComponentProps.isPressed] = true;
      controller.updateNodeProperties(found.key, props, recordHistory: false);
    }
  }

  /// Presses the clickable region of [node] under [canvasPos] — a remote's
  /// button — if there is one there, and says whether it did. Released in
  /// [onPointerUp].
  bool _pressRegion(ComponentInstance node, Offset canvasPos) {
    final painter = node.part.getPainter(properties: node.properties);
    final region = painter?.regionAt(node.absoluteToLocal(canvasPos), node.baseSize);
    if (region == null) return false;
    controller.interactingNodeKey = node.key;
    final props = Map<String, dynamic>.from(node.properties)
      ..[ComponentProps.pressedRegion] = region;
    controller.updateNodeProperties(node.key, props, recordHistory: false);
    return true;
  }

  void _handleContinueWiring() {
    if (controller.hoveredPort != null) {
      controller.completeWiring(controller.hoveredPort!);
    } else {
      controller.cancelWiring();
    }
  }

  void _handleStartWiring(PortLocation port, Offset canvasPos) {
    // A wire already ending here? Then the press means "pick that end up",
    // not "start another wire on top of it". `wireAt` matches by position
    // too, since the hovered port and the wire's recorded endpoint can be
    // two names for the same spot (a leg seated in a board hole).
    final attached = controller.wiringManager.wireAt(port);

    if (attached != null) {
      // Detach this end and start dragging it.
      final wire = attached.wire;
      final newStart = attached.atStart ? wire.end : wire.start;
      final newBendPoints = attached.atStart
          ? wire.bendPoints.reversed.toList()
          : wire.bendPoints.toList();
      // Restore against the wire's own recorded endpoint, not the hovered
      // port — they can differ, and a cancelled drag must put back exactly
      // what was there.
      final originalPort = attached.atStart ? wire.start : wire.end;

      controller.wiringManager.removeWire(wire.id);
      controller.wiringManager.currentWireColor = wire.color;
      controller.startWiring(
        newStart,
        canvasPos,
        bendPoints: newBendPoints,
        isMovingExisting: true,
        originalDetachedPort: originalPort,
        movingWireId: wire.id,
      );
    } else {
      // Start a new wire
      controller.startWiring(port, canvasPos);
    }
  }

  void _handleNodeOrBoxSelect(Offset canvasPos) {
    controller.selectionManager.checkSelection();

    // Check if clicked node is interactive
    if (controller.hoveredNode != null) {
      final node = controller.hoveredNode!;
      // A control on the part — a remote's button — is pressed, not dragged.
      if (_pressRegion(node, canvasPos)) return;
      if (node.part.name == PartNames.pushButton) {
        controller.interactingNodeKey = node.key;
        final props = Map<String, dynamic>.from(node.properties);
        props[ComponentProps.isPressed] = true;
        controller.updateNodeProperties(node.key, props, recordHistory: false);
        return; // Stop event, don't drag
      }
    }

    if (controller.selectionManager.selectedWireIds.isNotEmpty &&
        !controller.wiringManager.isDraggingBendPoint) {
      controller.wiringManager.startDraggingBendPoint(canvasPos);
    } else if (controller.selectedNodes.isEmpty &&
        controller.selectionManager.selectedWireIds.isEmpty) {
      // Clicked on empty space
      _isBoxSelecting = true;
      controller.startBoxSelection(canvasPos);
    }
  }
}
