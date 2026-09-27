import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interactive_viewer_plus/interactive_viewer_plus.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../controller/canvas_controller.dart';
import '../painters/box_selection_painter.dart';
import 'canvas_context_menu.dart';
import 'canvas_layout_delegate.dart';
import 'canvas_node_widget.dart';
import 'canvas_shortcuts.dart';
import '../painters/grid_painter.dart';
import '../painters/guidelines_painter.dart';
import '../events/pointer_event.dart';
import '../painters/wire_flow.dart';
import '../painters/wire_painter.dart';
import '../../../simulation/providers/simulation_provider.dart';

class Canvas extends ConsumerStatefulWidget {
  const Canvas({super.key});

  @override
  ConsumerState<Canvas> createState() => _CanvasState();
}

class _CanvasState extends ConsumerState<Canvas> with SingleTickerProviderStateMixin {
  final gridSize = const Size.square(50);

  var _isCentered = false;
  late WireFlowClock _flowClock;
  late FocusNode _focusNode;

  // Stable shortcut/action maps — computed once since [CanvasController] and
  // [Intent] classes live for the app's lifetime, avoiding 40+ Map allocations
  // and 20+ CallbackAction allocations on every canvas state change.
  Map<LogicalKeySet, Intent>? _shortcuts;
  Map<Type, Action<Intent>>? _actions;
  CanvasController? _lastController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'CanvasFocusNode');
    _flowClock = WireFlowClock(this);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _flowClock.dispose();
    super.dispose();
  }

  void _ensureActions(CanvasController controller) {
    if (_actions != null && identical(_lastController, controller)) return;
    _lastController = controller;
    _shortcuts = CanvasShortcuts.shortcuts();
    _actions = CanvasShortcuts.actions(controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(canvasControllerProvider.notifier);
    final state = ref.watch(canvasControllerProvider);
    final simulationState = ref.watch(simulationProvider);
    final isRunning = simulationState == SimulationState.running;

    // Dots keep moving only while the circuit is actually being solved; a
    // paused run freezes them where they are, which is what "paused" should
    // look like.
    if (isRunning) {
      _flowClock.start();
    } else {
      _flowClock.stop();
    }

    _ensureActions(controller);

    // Outer layout: just a Stack so the first frame's constraints reach us.
    return Stack(
      children: [
        // Boundaried, or the grid repaints on somebody else's schedule. A
        // `CustomPaint` marks the *enclosing* repaint boundary dirty, so with
        // none between here and the wires, every flow-clock tick — sixty a
        // second while a simulation runs — redrew the whole viewport lattice
        // as well. The grid's own listenable is pan and zoom; that is all it
        // should ever redraw for.
        RepaintBoundary(
          child: CustomPaint(size: Size.infinite, painter: GridPainter(context, controller)),
        ),
        // LayoutBuilder only wraps the InteractiveViewerPlus — not the
        // Shortcuts/Actions/context menu tree — so layout changes don't
        // rebuild the entire canvas widget.
        LayoutBuilder(
          builder: (context, constraints) {
            controller.viewportSize = constraints.biggest;
            if (!_isCentered) {
              _isCentered = true;
              if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  controller.fitToContent(constraints.biggest);
                });
              }
            }
            return Shortcuts(
              shortcuts: _shortcuts!,
              child: Actions(
                actions: _actions!,
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: true,
                  child: GestureDetector(
                    onTapDown: (_) => _focusNode.requestFocus(),
                    // Pointer handling sits ABOVE the context menu, not inside
                    // it. A menu that returns its child bare when it has no
                    // items, and wrapped when it has some, moves everything
                    // below it to a different depth as the item list changes.
                    // The canvas menu's items depend on the selection,
                    // so the wrapper appears and disappears as you select —
                    // which moves everything below it to a different depth in
                    // the element tree, unmounting it. Mid-gesture that is
                    // fatal: grabbing a selected wire's endpoint clears the
                    // selection, the menu emptied, and `CanvasPointerEvent` was
                    // disposed on the spot — its render object gone, so no
                    // further move or up event ever arrived and the wire sprang
                    // back. Nothing below here may depend on the selection.
                    child: CanvasPointerEvent(
                      controller: controller,
                      child: AppContextMenu(
                        controller: controller.contextMenuController,
                        entries: CanvasContextMenu.buildItems(context, controller),
                        child: ClipRect(
                          child: Stack(
                            children: [
                              InteractiveViewerPlus(
                                controller: controller.viewerController,
                                alignment: Alignment.topLeft,
                                boundaryMargin: const EdgeInsets.all(double.infinity),
                                minScale: controller.minScale,
                                maxScale: controller.maxScale,
                                panEnabled: controller.canvasMoveEnabled,
                                clipBehavior: Clip.none,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    SizedBox.expand(
                                      child: CustomMultiChildLayout(
                                        delegate: InfiniteCanvasNodesDelegate(controller.nodes),
                                        children: controller.nodes
                                            .map(
                                              (canvasComponentModel) => LayoutId(
                                                id: canvasComponentModel,
                                                key: canvasComponentModel.key,
                                                child: CanvasNodeWidget(
                                                  controller: controller,
                                                  node: canvasComponentModel,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                    // The one painter here that animates, so
                                    // it gets a layer of its own rather than
                                    // dirtying everything it shares one with.
                                    IgnorePointer(
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: WirePainter(
                                            wires: controller.wires,
                                            nodes: controller.nodes,
                                            pendingStart: controller.wiringManager.startPort,
                                            pendingEndMouse:
                                                controller.wiringManager.currentDragPosition,
                                            hoveredPort: controller.hoveredPort,
                                            hoveredWireId:
                                                controller.selectionManager.hoveredWireId,
                                            selectedWireIds:
                                                controller.selectionManager.selectedWireIds,
                                            selectionColor: context.appColors.primary,
                                            pendingColor:
                                                controller.wiringManager.activeDragColor ??
                                                AppPalette.yellow,
                                            pendingBendPoints:
                                                controller.wiringManager.pendingBendPoints,
                                            isMovingExistingWire:
                                                controller.wiringManager.isMovingWireEndpoint,
                                            isSimulating: isRunning,
                                            currents: ref
                                                .watch(simulationProvider.notifier)
                                                .wireCurrents,
                                            flowClock: _flowClock,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (state.verticalGuidelines.isNotEmpty ||
                                        state.horizontalGuidelines.isNotEmpty)
                                      IgnorePointer(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: GuidelinesPainter(
                                            verticalGuidelines: state.verticalGuidelines,
                                            horizontalGuidelines: state.horizontalGuidelines,
                                          ),
                                        ),
                                      ),
                                    if (controller.boxSelectionRect != null)
                                      IgnorePointer(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: BoxSelectionPainter(
                                            rect: controller.boxSelectionRect,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
