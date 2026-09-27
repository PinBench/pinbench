import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'canvas_commands.dart';

/// The surface the canvas managers (selection, wiring, history) operate on.
///
/// `CanvasController` implements it, but the managers depend only on this
/// narrow interface — keeping them decoupled from the controller and testable in
/// isolation. Commands mutate state exclusively through [updateState].
abstract class CanvasContext {
  List<ComponentInstance> get nodes;
  List<WireModel> get wires;
  bool get snapToGrid;
  void forceUpdate();
  void executeCommand(CanvasCommand command);
  void updateState({
    List<ComponentInstance>? nodes,
    List<WireModel>? wires,
    List<ComponentInstance>? selectedNodes,
    List<ComponentInstance>? clipboardNodes,
    List<WireModel>? clipboardWires,
    List<double>? verticalGuidelines,
    List<double>? horizontalGuidelines,
  });

  List<ComponentInstance> get selectedNodes;
  set selectedNodes(List<ComponentInstance> nodes);

  Rect? get boxSelectionRect;
  set boxSelectionRect(Rect? rect);

  List<ComponentInstance>? get clipboardNodes;
  set clipboardNodes(List<ComponentInstance>? nodes);

  ComponentInstance? get hoveredNode;
  set hoveredNode(ComponentInstance? key);

  Offset get mouseLocalPosition;
  Offset screenToCanvasCoordinates(Offset screenPosition);
  double get scale;

  String? get hoveredWireId;
  set hoveredWireId(String? id);

  List<String> get selectedWireIds;
  set selectedWireIds(List<String> ids);

  void selectWire(String? id);

  PortLocation? get hoveredPort;
  set hoveredPort(PortLocation? port);

  Offset? get dragStartOffset;
  set dragStartOffset(Offset? offset);

  /// True while a wire is being drawn — hit-testing is more forgiving then
  /// (see `SelectionManager._portHitRadius`).
  bool get isWiring;

  bool checkWireInteraction(Offset canvasPosition);

  /// Distance to the nearest bend-point handle of a *selected* wire within
  /// grabbing range, or null. Idle hover uses it to let a handle win over a
  /// port when the handle is the nearer target — a selected wire's handles
  /// are what the user is manifestly working with (see
  /// `SelectionManager.checkHover`).
  double? selectedBendHandleDistance(Offset canvasPosition);

  /// Whether [port] is where one of the *selected* wires ends (by identity or
  /// position). Such a port must never lose hover to a bend handle: grabbing
  /// the end of the wire you selected is the whole point of selecting it.
  bool isSelectedWireEndpoint(PortLocation port);

  /// The endpoint of a *selected* wire within handle-grabbing range of
  /// [canvasPosition], or null. Hover resolves this FIRST: a selected wire's
  /// end circles are drawn like bend handles and must grab like them —
  /// generous screen-px radius, endpoint beating everything else nearby.
  PortLocation? selectedEndpointAt(Offset canvasPosition);
}
