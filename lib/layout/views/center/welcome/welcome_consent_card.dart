import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_card.dart';

import '../../../../core/platform/open_external_url.dart';
import '../../../../core/telemetry/telemetry_consent.dart';

/// Asks, once, whether to share usage statistics and crash reports.
///
/// Only in a build that has telemetry, and only until the user answers: nothing
/// is collected while the answer is unknown, so the question is not in the way
/// of anything. The welcome screen is where every session starts, which makes
/// it the one place the question is sure to be seen without interrupting work.
/// Settings keeps the switch for changing the answer later.
class const WelcomeConsentCard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(telemetryControlProvider);
    final consent = ref.watch(telemetryConsentProvider);
    if (!control.available || consent != TelemetryConsent.unknown) return const SizedBox.shrink();

    final consentController = ref.read(telemetryConsentProvider.notifier);
    final policy = control.privacyPolicyUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.telemetryConsentTitle, style: AppTextStyles.largePrimary(context)),
            Gap.vSm,
            Text(AppStrings.telemetryConsentBody, style: AppTextStyles.smallMuted(context)),
            Gap.vMd,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton(
                  size: AppButtonSize.sm,
                  onPressed: () => unawaited(consentController.choose(granted: true)),
                  child: const Text(AppStrings.telemetryConsentAccept),
                ),
                AppButton(
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.sm,
                  onPressed: () => unawaited(consentController.choose(granted: false)),
                  child: const Text(AppStrings.telemetryConsentDecline),
                ),
                if (policy != null)
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => openExternalUrl(policy),
                    child: const Text(AppStrings.privacyPolicyLink),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
