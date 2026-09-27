import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';

import '../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../features/workspace/services/file_picker_actions.dart';
import 'actions/closed.dart';
import 'actions/new.dart';
import 'actions/open.dart';
import 'actions/saved.dart';
import 'actions/workspace.dart';

PlatformMenu fileMenu({
  required WidgetRef ref,
  required bool hasWorkspace,
  required bool hasEditorTab,
  required bool hasUnsavedChanges,
}) => PlatformMenu(
  label: AppStrings.fileMenuLabel,
  menus: <PlatformMenuItem>[
    buildNewActions(ref: ref, hasWorkspace: hasWorkspace),
    buildOpenActions(ref: ref),
    workspaceActions(ref: ref, hasWorkspace: hasWorkspace),
    // Saving needs something to save (a file open), not merely a workspace folder
    // — so it stays disabled on the welcome screen even if a recent folder lingers.
    saveActions(ref: ref, hasOpenFiles: hasEditorTab, hasUnsavedChanges: hasUnsavedChanges),
    closeActions(ref: ref, hasWorkspace: hasWorkspace, hasEditorTab: hasEditorTab),
    _buildShareActions(ref: ref, hasWorkspace: hasWorkspace),
  ],
);

PlatformMenuItemGroup _buildShareActions({required WidgetRef ref, required bool hasWorkspace}) =>
    PlatformMenuItemGroup(
      members: [
        PlatformMenu(
          label: AppStrings.shareMenuLabel,
          menus: [
            PlatformMenuItem(
              label: AppStrings.exportZipMenuLabel,
              onSelected: !hasWorkspace
                  ? null
                  : () => pickAndExportWorkspaceZip(ref.read(workspaceFilesProvider.notifier)),
            ),
          ],
        ),
      ],
    );
