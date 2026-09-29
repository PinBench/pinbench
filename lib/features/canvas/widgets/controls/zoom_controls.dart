import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../providers/canvas_controller_provider.dart';
import 'canvas_tool_group_divider.dart';
import '../../../../core/chrome/active_circuit_file.dart';
import '../../../../core/chrome/chrome_commands.dart';

class const ZoomControls({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvasControllerProvider.notifier);
    final showGrid = ref.watch(canvasControllerProvider).showGrid;

    return Positioned(
      right: 8,
      bottom: 8,
      child: AppCard(
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: AppIcons.code,
                tooltip: AppStrings.viewCodeTooltip,
                shortcutLabel: r'⌘\',
                onPressed: () {
                  final path = ref.read(activeCircuitFileProvider);
                  if (path != null) {
                    ref.read(chromeCommandsProvider).openEditorTab(path);
                  }
                },
              ),
              const CanvasToolGroupDivider(),
              AppIconButton(
                icon: AppIcons.add,
                onPressed: controller.zoomIn,
                tooltip: AppStrings.zoomInTooltip,
                shortcutLabel: '⌘+',
              ),
              AppIconButton(
                icon: AppIcons.remove,
                onPressed: controller.zoomOut,
                tooltip: AppStrings.zoomOutTooltip,
                shortcutLabel: '⌘−',
              ),
              const CanvasToolGroupDivider(),
              AppIconButton(
                tooltip: AppStrings.toggleGridTooltip,
                onPressed: controller.toggleGrid,
                shortcutLabel: "⌘'",
                icon: showGrid ? AppIcons.gridHidden : AppIcons.gridShown,
              ),
              AppIconButton(
                tooltip: AppStrings.resetViewTooltip,
                icon: AppIcons.fitToScreen,
                shortcutLabel: '⌘0',
                onPressed: () {
                  controller.fitToContent(controller.viewportSize);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
