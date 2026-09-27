import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import 'activity_target.dart';
import '../../controllers/app_layout_controller.dart';

class ActivityBarButton extends ConsumerWidget {
  final ActivityBarTab tab;

  const ActivityBarButton({super.key, required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLayoutController = ref.watch(appLayoutControllerProvider);
    final isActive = appLayoutController.isActivityTabSelected(tab);
    return AppIconButton(
      icon: tab.icon,
      size: AppIconButtonSize.large,
      tooltip: 'Open ${tab.title}',
      ghost: !isActive,
      onPressed: () => appLayoutController.openActivityTab(tab),
      // Pinned to the window's left edge, so the tip goes beside it.
      tooltipSide: AppTooltipSide.right,
    );
  }
}

/// The Settings button. Not an [ActivityBarButton] because settings is not a
/// sidebar: it opens as a tab in the center pane, the way VS Code opens its
/// settings editor, which is the only place a three-column form has room.
class SettingsTabButton extends ConsumerWidget {
  const SettingsTabButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(appLayoutControllerProvider);

    // The tab's own selection is what "active" means here, and that lives in
    // the Plat controller rather than in a provider — so listen to it directly
    // or the button would stay lit after the user switched tabs.
    return ListenableBuilder(
      listenable: layout.platController,
      builder: (context, _) => AppIconButton(
        icon: AppIcons.settings,
        size: AppIconButtonSize.large,
        tooltip: AppStrings.settingsTitle,
        shortcutLabel: '⌘,',
        ghost: !layout.isSettingsTabSelected(),
        onPressed: layout.openSettingsTab,
        tooltipSide: AppTooltipSide.right,
      ),
    );
  }
}
