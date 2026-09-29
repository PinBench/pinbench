import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_switch.dart';

import '../../core/platform/open_external_url.dart';
import '../../core/updates/update_config.dart';
import '../../core/updates/update_providers.dart';
import '../../core/updates/update_status.dart';

/// The whole update surface in one widget: which version is running, whether
/// the app looks for new ones on its own, and what to do about the one it
/// found.
///
/// Shared by the Settings sidebar and the "Check for Updates…" dialog rather
/// than written twice — a settings panel and a dialog disagreeing about the
/// state of the same check is exactly the bug this avoids.
class const UpdatePanel({
  super.key,

  /// The dialog hides the preference: someone who opened it pressed a button
  /// to ask a question, and answering it with a settings control is a change
  /// of subject.
  final bool showAutomaticToggle = true,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final version = ref.watch(appVersionProvider).value;
    final supported = ref.watch(updateServiceProvider).isSupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (version != null)
          Text(
            AppStrings.updatesInstalledVersion(version),
            style: AppTextStyles.smallMuted(context),
          ),
        if (!supported) ...[
          Gap.vSm,
          Text(AppStrings.updatesUnsupported, style: AppTextStyles.smallMuted(context)),
        ] else ...[
          Gap.vMd,
          _StatusLine(status: status),
          Gap.vMd,
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.outline,
                size: AppButtonSize.sm,
                onPressed: status is UpdateChecking ? null : () => unawaited(controller.checkNow()),
                child: Text(
                  status is UpdateChecking
                      ? AppStrings.updatesCheckingLabel
                      : AppStrings.updatesCheckButtonLabel,
                ),
              ),
              if (status is UpdateAvailable) ...[Gap.hSm, _ActOnUpdate(update: status)],
            ],
          ),
          if (showAutomaticToggle) ...[Gap.vLg, const _AutomaticChecksRow()],
        ],
      ],
    );
  }
}

/// One line saying where the check got to. Renders nothing when idle — an
/// empty panel is the honest depiction of "no check has run yet".
class const _StatusLine({required final UpdateStatus status}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final (IconData icon, String text, Color? color, String? footnote) = switch (status) {
      UpdateIdle() => (AppIcons.info, '', null, null),
      UpdateChecking() => (AppIcons.refresh, AppStrings.updatesCheckingLabel, null, null),
      UpdateUpToDate() => (AppIcons.success, AppStrings.updatesUpToDate, null, null),
      UpdateAvailable(:final version, :final installable) => (
        AppIcons.update,
        AppStrings.updatesAvailable(version?.toString()),
        colors.primary,
        installable ? null : AppStrings.updatesManualInstall,
      ),
      UpdateFailed(:final message) => (AppIcons.warning, message, colors.destructive, null),
    };
    if (text.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppIconSize.xs, color: color ?? colors.mutedForeground),
        Gap.hSm,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: context.appText.sm.copyWith(color: color)),
              if (footnote != null) ...[
                Gap.vXs,
                Text(footnote, style: AppTextStyles.smallMuted(context)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The button that does something about an available update.
///
/// On Sparkle platforms the update is already downloading — Sparkle started
/// the moment the check found it — so all a button can usefully do is
/// re-check with the native UI visible, which brings up Sparkle's own
/// progress-and-restart window. On Linux it opens the download page.
class const _ActOnUpdate({required final UpdateAvailable update}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppButton(
        size: AppButtonSize.sm,
        prefix: const Icon(AppIcons.update, size: AppIconSize.xs),
        onPressed: () {
          if (update.installable) {
            unawaited(ref.read(updateControllerProvider.notifier).checkNow());
          } else {
            openExternalUrl(update.downloadUrl ?? UpdateConfig.downloadPageUrl);
          }
        },
        child: Text(
          update.installable ? AppStrings.updatesInstallLabel : AppStrings.updatesDownloadLabel,
        ),
      ),
      if (update.notesUrl case final notes?) ...[
        Gap.hSm,
        AppButton(
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: () => openExternalUrl(notes),
          child: const Text(AppStrings.updatesReleaseNotesLabel),
        ),
      ],
    ],
  );
}

class const _AutomaticChecksRow() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(automaticUpdateChecksProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.updatesAutomaticLabel, style: context.appText.sm),
              Gap.vXs,
              Text(
                AppStrings.updatesAutomaticDescription,
                style: AppTextStyles.smallMuted(context),
              ),
            ],
          ),
        ),
        Gap.hSm,
        AppSwitch(
          value: enabled,
          onChanged: (value) =>
              unawaited(ref.read(automaticUpdateChecksProvider.notifier).set(enabled: value)),
        ),
      ],
    );
  }
}
