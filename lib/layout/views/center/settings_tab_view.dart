import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_divider.dart';

import '../../../core/edition/edition_provider.dart';
import '../../../core/telemetry/telemetry_consent.dart';
import '../../updates/update_panel.dart';
import 'privacy_panel.dart';

/// App settings, as a document in the center pane.
///
/// It used to be a sidebar, which is the wrong shape for it: a model URL, a
/// key and a model name in a 200px column wrap onto three lines each, and the
/// panel closed the moment the user opened the explorer to check something.
/// As a tab it gets the width of the editor, stays open beside the work, and
/// is the *one* place these settings live — anything else that needs a setting
/// changed sends people here rather than carrying its own copy of the form.
class SettingsTabView extends ConsumerWidget {
  const SettingsTabView({super.key});

  /// Settings read as a form, not as a wall: past roughly this width the eye
  /// loses the line, so the content column stops and the pane keeps the rest.
  static const _contentWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
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
            // The edition's side panel settings, when it has any.
            if (ref.watch(editionPanelProvider)?.settings case final section?)
              _Section(
                icon: section.icon,
                title: section.title,
                description: section.description,
                child: Builder(builder: section.build),
              ),
            const _Section(
              icon: AppIcons.update,
              title: AppStrings.updatesSectionTitle,
              description: AppStrings.settingsUpdatesDescription,
              child: UpdatePanel(),
            ),
            // Only a build with telemetry has anything to share.
            if (ref.watch(telemetryControlProvider).available)
              const _Section(
                icon: AppIcons.info,
                title: AppStrings.privacySectionTitle,
                description: AppStrings.settingsPrivacyDescription,
                child: PrivacyPanel(),
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
