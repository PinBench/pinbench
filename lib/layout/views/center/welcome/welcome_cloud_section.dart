import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';

import 'welcome_list_tile.dart';
import '../../../../app/router.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/cloud/project_providers.dart';

/// The Welcome screen's "Cloud Projects" card, shown only when auth is
/// enabled (see the caller's `authServiceProvider.enabled` check).
class WelcomeCloudSection extends ConsumerWidget {
  const WelcomeCloudSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxxl),
        child: Center(
          child: Text(AppStrings.cloudSignInPromptMessage, textAlign: TextAlign.center),
        ),
      );
    }

    final recentsAsync = ref.watch(cloudRecentProjectsProvider);
    return recentsAsync.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: AppSpinner()),
      ),
      error: (err, _) => const Text(AppStrings.cloudProjectsLoadErrorMessage),
      data: (recents) {
        if (recents.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xxxl),
            child: Center(
              child: Text(AppStrings.noCloudProjectsMessage, textAlign: TextAlign.center),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: recents
              .map(
                (recent) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: WelcomeListTile(
                    icon: AppIcons.cloud,
                    title: recent.name,
                    subtitle: 'Opened ${recent.lastOpenedAt}',
                    onTap: () => ProjectRoute(projectId: recent.id).go(context),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
