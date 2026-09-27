import 'package:flutter/widgets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';

import '../../../../features/workspace/providers/workspace_files_provider.dart';

PlatformMenuItemGroup workspaceActions({required WidgetRef ref, required bool hasWorkspace}) =>
    PlatformMenuItemGroup(
      members: [
        PlatformMenuItem(
          label: AppStrings.addFolderToWorkspaceMenuLabel,
          onSelected: () async {
            // Single-root workspaces: open the chosen folder as the workspace.
            final dir = await getDirectoryPath();
            if (dir != null) {
              await ref.read(workspaceFilesProvider.notifier).openWorkspace(dir);
            }
          },
        ),
        PlatformMenuItem(
          label: AppStrings.saveWorkspaceAsMenuLabel,
          onSelected: !hasWorkspace
              ? null
              : () async {
                  await ref.read(workspaceFilesProvider.notifier).saveWorkspaceToLocation();
                },
        ),
        PlatformMenuItem(
          label: AppStrings.duplicateWorkspaceMenuLabel,
          onSelected: !hasWorkspace
              ? null
              : () async {
                  final parentDir = await getDirectoryPath();
                  if (parentDir != null) {
                    await ref.read(workspaceFilesProvider.notifier).duplicateWorkspace(parentDir);
                  }
                },
        ),
      ],
    );
