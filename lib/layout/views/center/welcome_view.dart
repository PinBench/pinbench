import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_card.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/edition/edition_provider.dart';
import 'welcome/welcome_cloud_section.dart';
import 'welcome/welcome_consent_card.dart';
import 'welcome/welcome_recent_section.dart';
import 'welcome/welcome_start_section.dart';
import 'welcome/welcome_templates_section.dart';

class const WelcomeView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return DecoratedBox(
      // A wash, not a spotlight. At a quarter opacity the brand teal turned the
      // whole lower half of the first screen green, which is the loudest thing
      // a tool can do before the user has done anything.
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.85,
          stops: const [0.0, 1.0],
          center: Alignment.bottomCenter,
          colors: [colors.primary.withValues(alpha: 0.05), colors.surface],
        ),
      ),
      child: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const WelcomeConsentCard(),
                  // The side panel's entry point, when the edition has one. The
                  // pane itself stays closed here; see `closeWelcome`.
                  if (ref.watch(editionPanelProvider)?.welcome case final welcome?) ...[
                    Builder(builder: welcome),
                    Gap.vLg,
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column (Start & Templates)
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSectionCard(
                              context: context,
                              title: AppStrings.startSectionTitle,
                              icon: AppIcons.upload,
                              child: const WelcomeStartSection(),
                            ),
                            Gap.vLg,
                            _buildSectionCard(
                              context: context,
                              title: AppStrings.templatesSectionTitle,
                              icon: AppIcons.templates,
                              child: const WelcomeTemplatesSection(),
                            ),
                          ],
                        ),
                      ),
                      Gap.hLg,
                      // Right Column (Recent)
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Recent workspaces are local folders, which the web
                            // preview has no access to — the list is always empty
                            // there, so hide the card entirely on the web.
                            if (!kIsWeb)
                              _buildSectionCard(
                                context: context,
                                title: AppStrings.recentWorkspacesSectionTitle,
                                icon: AppIcons.history,
                                child: const WelcomeRecentSection(),
                              ),
                            if (ref.watch(authServiceProvider).enabled) ...[
                              if (!kIsWeb) Gap.vLg,
                              _buildSectionCard(
                                context: context,
                                title: AppStrings.cloudProjectsSectionTitle,
                                icon: AppIcons.cloud,
                                child: const WelcomeCloudSection(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Row(
      children: [
        // Sized to the two lines of text beside it. At 80 it was the largest
        // thing on the screen and read as a splash screen, not a workspace.
        Icon(AppIcons.board, size: AppIconSize.display, color: context.appColors.primary),
        Gap.hXl,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.welcomeHeaderTitle, style: AppTextStyles.h1LargePrimary(context)),
              Text(AppStrings.welcomeHeaderSubtitle, style: AppTextStyles.largeMuted(context)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) => AppCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: AppSpacing.lg,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon, size: AppIconSize.xxxl, color: context.appColors.primary),
            ),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.largePrimary(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Gap.vMd,
        child,
      ],
    ),
  );
}
