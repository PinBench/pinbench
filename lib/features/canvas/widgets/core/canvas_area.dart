import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/component_instance.dart';

import '../../controller/canvas_controller.dart';
import '../../managers/breadboard_snap_helper.dart';
import '../../managers/snap_guide_helper.dart';
import 'canvas.dart';
import '../../../../core/parts/part_registry_provider.dart';

class CanvasArea extends ConsumerStatefulWidget {
  const CanvasArea({super.key});

  @override
  ConsumerState<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends ConsumerState<CanvasArea> {
  CanvasController get controller => ref.watch(canvasControllerProvider.notifier);

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => true,
    onAcceptWithDetails: (details) {
      final componentName = details.data;
      final renderBox = context.findRenderObject()! as RenderBox;

      final components = ref.read(partRegistryProvider).value ?? [];
      final part = components.firstWhere((type) => type.name == componentName).clone();

      final pointerLocal = renderBox.globalToLocal(details.offset);

      // Map the cursor's screen position to scene coordinates
      final pointerCanvas = controller.screenToCanvasCoordinates(pointerLocal);

      var canvasComponentModel = ComponentInstance(position: pointerCanvas, part: part);

      // Snap the drop so the part's legs land on the connection lattice.
      var canvasPosition = SnapGuideHelper.snapNodeToLattice(canvasComponentModel, pointerCanvas);
      canvasComponentModel = canvasComponentModel.copyWith(position: canvasPosition);

      // Dropped over a board, the board's holes decide instead: the grid alone
      // can leave the legs on the blank moulding between two rail blocks, off
      // the holes entirely if the board is rotated, or half a pitch out on a
      // half board's staggered rails. Measured from where it was dropped.
      final toHole = BreadboardSnapHelper.holeAdjustment(
        node: canvasComponentModel,
        position: pointerCanvas,
        boards: controller.nodes,
      );
      if (toHole != null) {
        canvasPosition = pointerCanvas + toHole;
        canvasComponentModel = canvasComponentModel.copyWith(position: canvasPosition);
      }

      controller.add(canvasComponentModel);
    },
    builder: (context, candidateData, rejectedData) => const Canvas(),
  );
}
