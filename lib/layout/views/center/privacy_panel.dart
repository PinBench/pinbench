import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_switch.dart';

import '../../../core/platform/open_external_url.dart';
import '../../../core/telemetry/telemetry_consent.dart';

/// The settings for what this build shares: one switch for usage statistics
/// and crash reports, and the policy that covers them. Shown only in a build
/// with telemetry (see [TelemetryControl.available]).
class PrivacyPanel extends ConsumerWidget {
  const PrivacyPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(telemetryConsentProvider) == TelemetryConsent.granted;
    final policy = ref.watch(telemetryControlProvider).privacyPolicyUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.telemetrySwitchLabel, style: context.appText.sm),
                  Gap.vXs,
                  Text(
                    AppStrings.telemetrySwitchDescription,
                    style: AppTextStyles.smallMuted(context),
                  ),
                ],
              ),
            ),
            Gap.hSm,
            AppSwitch(
              value: granted,
              onChanged: (value) =>
                  unawaited(ref.read(telemetryConsentProvider.notifier).choose(granted: value)),
            ),
          ],
        ),
        if (policy != null) ...[
          Gap.vMd,
          AppButton(
            variant: AppButtonVariant.outline,
            size: AppButtonSize.sm,
            onPressed: () => openExternalUrl(policy),
            child: const Text(AppStrings.privacyPolicyLink),
          ),
        ],
      ],
    );
  }
}
