import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import '../../controller/canvas_controller.dart';
import '../components/component_widget.dart';

class const CanvasNodeWidget({
  super.key,
  required final ComponentInstance node,
  required final CanvasController controller,
}) extends StatelessWidget {
  Widget _generateSmoothOutline(Widget child, Color color, double thickness, double blurSigma) {
    final offsets = [
      Offset(-thickness, -thickness),
      Offset(thickness, -thickness),
      Offset(-thickness, thickness),
      Offset(thickness, thickness),
    ];

    final children = <Widget>[];
    for (final offset in offsets) {
      children.add(Positioned(left: offset.dx, top: offset.dy, child: child));
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: TileMode.decal,
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, dynamic>>(
    // A running simulation writes an LED's `isOn`, a servo's angle and an
    // OLED's picture here at 60fps. Listening per node means one component
    // rebuilding rather than the whole canvas — see
    // `CanvasController.liveProperties`.
    valueListenable: controller.liveProperties(node.key),
    builder: (context, live, _) => _build(context, live),
  );

  Widget _build(BuildContext context, Map<String, dynamic> live) {
    // The engine sends only what changed, so the node's own properties stay
    // underneath: a user-set `Color` outlives every frame written over it.
    final properties = live.isEmpty ? node.properties : {...node.properties, ...live};
    final isSelected = controller.selectionManager.isSelected(node.key);
    final isHovered = controller.selectionManager.isHovered(node.key);
    final primaryColor = context.appColors.primary;
    final outlineColor = isSelected ? primaryColor : primaryColor.withValues(alpha: 0.5);

    final baseComponent = ComponentWidget(
      part: node.part,
      hoveredLocalPosition: node.hoveredLocalPosition,
      breadboardHover: node.breadboardHover,
      properties: properties,
      customSize: node.baseSize,
    );

    final outlineComponent = ComponentWidget(
      part: node.part,
      hoveredLocalPosition: node.hoveredLocalPosition,
      breadboardHover: node.breadboardHover,
      properties: properties,
      isOutline: true,
      customSize: node.baseSize,
    );

    return RepaintBoundary(
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
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: (isSelected || isHovered) ? 1.0 : 0.0),
                    builder: (context, value, child) {
                      final outline = value == 0
                          ? const SizedBox.shrink()
                          : _generateSmoothOutline(
                              outlineComponent,
                              outlineColor.withValues(alpha: outlineColor.a * value),
                              1.0 + (value * 1.5),
                              1.0 + (value * 1.5),
                            );

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [if (value > 0) outline, child!],
                      );
                    },
                    child: baseComponent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
