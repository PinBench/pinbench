import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:pinbench_ui/strings.dart';

import '../../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../../layout/controllers/app_layout_controller.dart';
import '../../shared_menu_actions.dart';

PlatformMenuItemGroup closeActions({
  required WidgetRef ref,
  required bool hasWorkspace,
  required bool hasEditorTab,
}) => PlatformMenuItemGroup(
  members: [
    PlatformMenuItem(
      label: AppStrings.revertFileMenuLabel,
      onSelected: !hasEditorTab
          ? null
          : () async {
              final path = activeEditorFile(ref.read(appLayoutControllerProvider));
              if (path == null) return;
              await ref.read(workspaceFilesProvider.notifier).revertFile(path);
            },
    ),
    PlatformMenuItem(
      label: AppStrings.closeEditorMenuLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
      onSelected: !hasEditorTab ? null : () => closeActiveEditorTab(ref),
    ),
    PlatformMenuItem(
      label: AppStrings.closeFolderMenuLabel,
      onSelected: !hasWorkspace
          ? null
          : () {
              ref.read(workspaceFilesProvider.notifier).closeFolder();
            },
    ),
    PlatformMenuItem(
      label: AppStrings.closeWindowMenuLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true),
      onSelected: () async {
        final context = FocusManager.instance.primaryFocus?.context;
        if (context != null) {
          await MultiViewDesktop.of(context).closeWindow();
        }
      },
    ),
  ],
);
