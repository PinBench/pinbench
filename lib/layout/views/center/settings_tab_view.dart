import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_divider.dart';

import '../../../features/ai/widgets/ai_settings_panel.dart';
import '../../updates/update_panel.dart';

/// App settings, as a document in the center pane.
///
/// It used to be a sidebar, which is the wrong shape for it: a model URL, a
/// key and a model name in a 200px column wrap onto three lines each, and the
/// panel closed the moment the user opened the explorer to check something.
/// As a tab it gets the width of the editor, stays open beside the work, and
/// is the *one* place these settings live — the welcome screen and the
/// assistant pane now send people here rather than each carrying a copy of the
/// same form.
class SettingsTabView extends StatelessWidget {
  const SettingsTabView({super.key});

  /// Settings read as a form, not as a wall: past roughly this width the eye
  /// loses the line, so the content column stops and the pane keeps the rest.
  static const _contentWidth = 720.0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xxxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.settingsTitle, style: AppTextStyles.h1LargePrimary(context)),
            Gap.vXs,
            Text(AppStrings.settingsSubtitle, style: AppTextStyles.smallMuted(context)),
            Gap.vXxxl,
            const _Section(
              icon: AppIcons.assistant,
              title: AppStrings.buildWithAgentHeading,
              description: AppStrings.settingsAssistantDescription,
              child: AiSettingsPanel(),
            ),
            const _Section(
              icon: AppIcons.update,
              title: AppStrings.updatesSectionTitle,
              description: AppStrings.settingsUpdatesDescription,
              child: UpdatePanel(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One settings group: a heading, a line saying what it is for, and the
/// controls, separated from the next group by a rule rather than by a card —
/// stacked cards on a full-width surface read as a dashboard, not as settings.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: AppIconSize.md, color: colors.primary),
              Gap.hMd,
              Text(title, style: AppTextStyles.largePrimary(context)),
            ],
          ),
          Gap.vXs,
          Text(description, style: AppTextStyles.smallMuted(context)),
          Gap.vXl,
          child,
          Gap.vXxl,
          const AppDivider.section(),
        ],
      ),
    );
  }
}
