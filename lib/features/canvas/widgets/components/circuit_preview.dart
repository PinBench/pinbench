import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

import '../painters/wire_painter.dart';
import 'component_widget.dart';

/// Renders a static, non-interactive thumbnail of a parsed circuit — used by
/// the Welcome screen's template gallery so each template shows what it
/// actually looks like instead of a generic icon.
///
/// Positions each node exactly like the live canvas does (`CanvasNodeWidget`
/// / `InfiniteCanvasNodesDelegate`) but without any of the selection/hover/
/// drag state those carry, then crops to the circuit's own bounding box and
/// scales it to fit whatever space the caller gives it via [FittedBox].
class const CircuitPreview({
  super.key,
  required final List<ComponentInstance> nodes,
  required final List<WireModel> wires,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final node in nodes) {
      minX = math.min(minX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxX = math.max(maxX, node.position.dx + node.currentSize.width);
      maxY = math.max(maxY, node.position.dy + node.currentSize.height);
    }
    final boundsSize = Size(maxX - minX, maxY - minY);
    if (boundsSize.width <= 0 || boundsSize.height <= 0) return const SizedBox.shrink();

    return IgnorePointer(
      child: FittedBox(
        child: SizedBox(
          width: boundsSize.width,
          height: boundsSize.height,
          // Wires and nodes are laid out in the circuit's own (possibly
          // negative) coordinate space; translating the whole subtree once
          // crops the view to its bounding box without needing to shift each
          // node/wire endpoint individually.
          child: Transform.translate(
            offset: Offset(-minX, -minY),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: boundsSize,
                  painter: WirePainter(wires: wires, nodes: nodes),
                ),
                for (final node in nodes) _PreviewNode(node: node),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors `CanvasNodeWidget`'s position/rotation/flip geometry, minus the
/// selection/hover outline it also draws — a preview never has either.
class const _PreviewNode({required final ComponentInstance node}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Positioned(
    left: node.position.dx,
    top: node.position.dy,
    child: SizedBox(
      width: node.currentSize.width,
      height: node.currentSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: node.pivotOffset.dx - node.baseSize.width / 2,
            top: node.pivotOffset.dy,
            child: Transform.rotate(
              angle: node.rotationAngle,
              alignment: Alignment.topCenter,
              child: Transform.scale(
                scaleX: node.flipHorizontal ? -1 : 1,
                scaleY: node.flipVertical ? -1 : 1,
                child: ComponentWidget(
                  part: node.part,
                  properties: node.properties,
                  customSize: node.baseSize,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
