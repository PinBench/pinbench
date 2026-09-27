import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';

import '../../../../features/workspace/providers/workspace_files_provider.dart';

PlatformMenuItemGroup saveActions({
  required WidgetRef ref,
  required bool hasOpenFiles,
  required bool hasUnsavedChanges,
}) => PlatformMenuItemGroup(
  members: [
    // Save / Save All light up only when there's actually something unsaved,
    // matching VS Code — so the greyed-out state now reflects real state.
    PlatformMenuItem(
      label: AppStrings.saveButtonLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
      onSelected: !hasUnsavedChanges
          ? null
          : () async {
              await ref.read(workspaceFilesProvider.notifier).saveCurrentWorkspace();
            },
    ),
    PlatformMenuItem(
      label: AppStrings.saveAsMenuLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
      onSelected: !hasOpenFiles
          ? null
          : () async {
              await ref.read(workspaceFilesProvider.notifier).saveWorkspaceToLocation();
            },
    ),
    PlatformMenuItem(
      label: AppStrings.saveAllMenuLabel,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, alt: true),
      onSelected: !hasUnsavedChanges
          ? null
          : () async {
              await ref.read(workspaceFilesProvider.notifier).saveAll();
            },
    ),
    PlatformMenuItem(
      label: AppStrings.autoSaveMenuLabel,
      onSelected: !hasOpenFiles
          ? null
          : () {
              ref.read(workspaceFilesProvider.notifier).toggleAutoSave();
            },
    ),
  ],
);
