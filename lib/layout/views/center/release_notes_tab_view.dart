import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_checkbox.dart';
import 'package:pinbench_ui/ui/app_divider.dart';
import 'package:pinbench_ui/ui/app_markdown.dart';
import 'package:pinbench_ui/ui/app_selection_area.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';

import '../../../core/platform/open_external_url.dart';
import '../../../core/updates/release_notes.dart';
import '../../../core/updates/update_config.dart';
import '../../../core/updates/update_providers.dart';

/// What changed in the running build, as a document in the center pane — the
/// shape of VS Code's "Release Notes: 1.x" tab.
///
/// Read from the changelog bundled with the app, so the notes are the ones
/// for this build and appear with no network. Opened from Help ▸ Release
/// Notes, and on its own on the first launch after an update unless the box
/// at the top is cleared.
class const ReleaseNotesTabView({super.key}) extends ConsumerWidget {
  /// Prose, so the column stops where a line stops being readable, as the
  /// settings tab's does.
  static const _contentWidth = 820.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final notes = ref.watch(releaseNotesProvider);
    final showAfterUpdate = ref.watch(showReleaseNotesAfterUpdateProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                version == null ? AppStrings.appName : AppStrings.releaseNotesHeading(version),
                style: AppTextStyles.h1LargePrimary(context),
              ),
              Gap.vLg,
              const AppDivider.section(),
              Gap.vLg,
              Row(
                children: [
                  // Given the row's free space: the box lays its label out
                  // against the width it is offered, and a row offers none.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppCheckbox(
                        value: showAfterUpdate,
                        label: AppStrings.releaseNotesShowAfterUpdate,
                        onChanged: (enabled) => ref
                            .read(showReleaseNotesAfterUpdateProvider.notifier)
                            .set(enabled: enabled),
                      ),
                    ),
                  ),
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    onPressed: () => openExternalUrl(UpdateConfig.changelogUrl),
                    child: const Text(AppStrings.releaseNotesViewOnline),
                  ),
                ],
              ),
              Gap.vLg,
              const AppDivider.section(),
              Gap.vXl,
              switch (notes) {
                AsyncData(value: final notes?) => AppSelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (notes.date case final date?) ...[
                        Text(
                          AppStrings.releaseNotesDate(date),
                          style: AppTextStyles.smallMuted(context)
                              .copyWith(fontStyle: FontStyle.italic),
                        ),
                        Gap.vLg,
                      ],
                      AppMarkdown(data: notes.body, onTapLink: openExternalUrl),
                    ],
                  ),
                ),
                AsyncLoading() => const Center(child: AppSpinner()),
                _ => Text(
                  AppStrings.releaseNotesUnavailable,
                  style: AppTextStyles.smallMuted(context),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
