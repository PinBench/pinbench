import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_ui/strings.dart';

import '../../../../features/workspace/providers/recent_workspaces_provider.dart';
import '../../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../../features/workspace/services/file_picker_actions.dart';

PlatformMenuItemGroup buildOpenActions({required WidgetRef ref}) => PlatformMenuItemGroup(
  members: [
    PlatformMenuItem(
      label: AppStrings.openMenuLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
      onSelected: () => pickAndOpenFile(ref.read(workspaceFilesProvider.notifier)),
    ),
    PlatformMenuItem(
      label: AppStrings.openFolderMenuLabel,
      onSelected: () async {
        final dir = await getDirectoryPath();
        if (dir != null) {
          await ref.read(workspaceFilesProvider.notifier).openWorkspace(dir);
        }
      },
    ),
    PlatformMenuItem(
      label: AppStrings.openWorkspaceFromFileMenuLabel,
      onSelected: () async {
        // No bespoke workspace-file format: pick any file and open its folder.
        final file = await openFile();
        if (file != null) {
          await ref.read(workspaceFilesProvider.notifier).openWorkspace(p.dirname(file.path));
        }
      },
    ),
    PlatformMenu(
      label: AppStrings.openRecentMenuLabel,
      menus: [
        PlatformMenuItem(
          label: AppStrings.clearRecentlyOpenedMenuLabel,
          onSelected: () async {
            await ref.read(recentWorkspacesProvider.notifier).clearRecentWorkspaces();
          },
        ),
      ],
    ),
  ],
);
