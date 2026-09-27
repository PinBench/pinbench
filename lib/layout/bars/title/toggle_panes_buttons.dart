import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../core/edition/edition_provider.dart';
import '../../controllers/app_layout_controller.dart';

class TogglePanesButtons extends ConsumerWidget {
  const TogglePanesButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLayoutController = ref.watch(appLayoutControllerProvider);
    final controller = appLayoutController.platController;
    // No right-hand pane without an edition's side panel, so no toggle for it.
    final hasSidePanel = ref.watch(editionPanelProvider) != null;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLeftPaneActive = !appLayoutController.isPaneHidden('left_slot');
        final isBottomPaneActive = !appLayoutController.isPaneHidden('bottom_pane');
        final isRightPaneActive = !appLayoutController.isPaneHidden('right_pane');

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: AppSpacing.md,
          children: [
            AppIconButton(
              isActive: isLeftPaneActive,
              icon: AppIcons.panelLeft,
              tooltip: AppStrings.toggleLeftPaneTooltip,
              shortcutLabel: '⌘B',
              onPressed: () => appLayoutController.togglePane('left_slot'),
            ),
            AppIconButton(
              isActive: isBottomPaneActive,
              icon: AppIcons.panelBottom,
              tooltip: AppStrings.toggleBottomPaneTooltip,
              shortcutLabel: '⌘J',
              onPressed: () => appLayoutController.togglePane('bottom_pane'),
            ),
            if (hasSidePanel)
              AppIconButton(
                isActive: isRightPaneActive,
                icon: AppIcons.panelRight,
                tooltip: AppStrings.toggleRightPaneTooltip,
                shortcutLabel: '⌥⌘B',
                onPressed: () => appLayoutController.togglePane('right_pane'),
              ),
          ],
        );
      },
    );
  }
}
