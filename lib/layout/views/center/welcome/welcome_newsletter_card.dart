import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_card.dart';

import '../../../../core/newsletter/newsletter.dart';

/// Offers the newsletter on the welcome screen, until the user either goes to
/// sign up or says no thanks.
///
/// Below the consent card rather than beside it: that one is a question the
/// app needs answered, this is an offer that can wait.
class const WelcomeNewsletterCard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(newsletterUrlProvider) == null) return const SizedBox.shrink();
    if (!ref.watch(newsletterPromptsProvider).showWelcomeCard) return const SizedBox.shrink();

    final controller = ref.read(newsletterPromptsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.newsletter, size: AppIconSize.md, color: context.appColors.primary),
            Gap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.newsletterTitle, style: AppTextStyles.largePrimary(context)),
                  Gap.vSm,
                  Text(AppStrings.newsletterBody, style: AppTextStyles.smallMuted(context)),
                  Gap.vMd,
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      AppButton(
                        size: AppButtonSize.sm,
                        onPressed: () => unawaited(controller.open(NewsletterEntry.welcome)),
                        child: const Text(AppStrings.newsletterSignUp),
                      ),
                      AppButton(
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => unawaited(controller.dismissWelcome()),
                        child: const Text(AppStrings.newsletterDismiss),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
