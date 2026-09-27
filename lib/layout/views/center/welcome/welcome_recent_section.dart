import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_empty_state.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import 'welcome_list_tile.dart';
import '../../../../features/workspace/providers/recent_workspaces_provider.dart';
import '../../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../controllers/app_layout_controller.dart';

/// The Welcome screen's "Recent Workspaces" card. Hidden entirely on the web
/// by the caller, since recent workspaces are local folders the web preview
/// has no access to.
class WelcomeRecentSection extends ConsumerWidget {
  const WelcomeRecentSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentWorkspaces = ref.watch(recentWorkspacesProvider);

    if (recentWorkspaces.isEmpty) {
      return const AppEmptyState(
        icon: AppIcons.recent,
        title: AppStrings.noRecentWorkspacesMessage,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: recentWorkspaces.map((path) {
        final folderName = p.basename(path);
        final home = Platform.environment['HOME'] ?? '';
        final parentPath = p.dirname(path);
        final displayPath = home.isNotEmpty && parentPath.startsWith(home)
            ? '~${parentPath.substring(home.length)}'
            : parentPath;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: WelcomeListTile(
            icon: AppIcons.folder,
            title: folderName,
            subtitle: displayPath,
            onTap: () async {
              await ref.read(workspaceFilesProvider.notifier).openWorkspace(path);
              ref.read(appLayoutControllerProvider).closeWelcome();
            },
          ),
        );
      }).toList(),
    );
  }
}
