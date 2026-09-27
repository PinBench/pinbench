import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:super_tree/super_tree.dart';
import 'package:pinbench_ui/ui/app_alert_dialog.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/widgets/text_input_dialog.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../providers/editor_state_provider.dart';
import '../../../core/telemetry/telemetry_providers.dart';

class ExplorerContextMenu {
  static List<AppMenuEntry> buildItems(
    BuildContext context,
    WidgetRef ref,
    TreeNode<FileSystemItem> node,
    String filePath,
  ) {
    final isFolder = node.data.isFolder;

    return <AppMenuEntry>[
      if (isFolder)
        AppContextMenuItem(
          text: AppStrings.explorerContextNewFile,
          icon: AppIcons.file,
          shortcut: '⌘N',
          onPressed: () async => createNewFile(context, ref, filePath),
        ),
      if (isFolder)
        AppContextMenuItem(
          text: AppStrings.explorerContextNewFolder,
          icon: AppIcons.newFolder,
          shortcut: '⇧⌘N',
          onPressed: () async => createNewFolder(context, ref, filePath),
        ),
      if (isFolder) const AppMenuSeparator(),
      AppContextMenuItem(
        text: AppStrings.explorerContextRename,
        icon: AppIcons.rename,
        shortcut: '↵',
        onPressed: () async => renameItem(context, ref, filePath),
      ),
      const AppMenuSeparator(),
      AppContextMenuItem(
        text: AppStrings.explorerContextDelete,
        icon: AppIcons.delete,
        iconColor: context.appColors.destructive,
        textColor: context.appColors.destructive,
        shortcut: '⌫',
        onPressed: () async => deleteItem(context, ref, filePath),
      ),
    ];
  }

  static Future<void> createNewFile(BuildContext context, WidgetRef ref, String folderPath) async {
    final name = await showTextInputDialog(
      context,
      title: AppStrings.newFileDialogTitle,
      confirmLabel: AppStrings.okButtonLabel,
    );
    if (name != null && name.isNotEmpty) {
      final newFilePath = '$folderPath/$name';
      final file = File(newFilePath);
      if (!file.existsSync()) {
        await file.create();
        ref.read(analyticsProvider).fileCreated(p.extension(name));
      }
    }
  }

  static Future<void> createNewFolder(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
  ) async {
    final name = await showTextInputDialog(
      context,
      title: AppStrings.newFolderDialogTitle,
      confirmLabel: AppStrings.okButtonLabel,
    );
    if (name != null && name.isNotEmpty) {
      final newDirPath = '$folderPath/$name';
      final dir = Directory(newDirPath);
      if (!dir.existsSync()) {
        await dir.create();
        ref.read(analyticsProvider).action('folder_created');
      }
    }
  }

  static Future<void> renameItem(BuildContext context, WidgetRef ref, String filePath) async {
    final currentName = p.basename(filePath);
    final parentDir = p.dirname(filePath);
    final isDir = FileSystemEntity.isDirectorySync(filePath);

    final newName = await showTextInputDialog(
      context,
      title: AppStrings.renameDialogTitle,
      confirmLabel: AppStrings.okButtonLabel,
      initialValue: currentName,
    );
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final newPath = '$parentDir/$newName';
      final entity = isDir ? Directory(filePath) : File(filePath);

      await entity.rename(newPath);
      ref
          .read(analyticsProvider)
          .fileRenamed(
            isDir ? 'folder' : p.extension(currentName),
            isDir ? 'folder' : p.extension(newName),
          );

      // Also rename the open tab if it is open
      final editorState = ref.read(editorStateControllerProvider);
      if (editorState.openFileControllers.containsKey(filePath)) {
        final content = editorState.openFileControllers[filePath]!.text;
        editorState.closeFile(filePath);
        editorState.openFile(newPath, content);
      }
    }
  }

  static Future<void> deleteItem(BuildContext context, WidgetRef ref, String filePath) async {
    final isDir = Directory(filePath).existsSync();
    final entity = isDir ? Directory(filePath) : File(filePath);
    if (!entity.existsSync()) return;

    // Ask first. This deletes straight off the filesystem — recursively for a
    // folder — with no undo and no trash, off a single context-menu item.
    final name = p.basename(filePath);
    final confirmed = await showConfirmDialog(
      context,
      title: isDir ? AppStrings.deleteFolderDialogTitle : AppStrings.deleteFileDialogTitle,
      message: isDir
          ? AppStrings.deleteFolderDialogMessage(name)
          : AppStrings.deleteFileDialogMessage(name),
      confirmLabel: AppStrings.delete,
      isDestructive: true,
    );
    if (!confirmed) return;

    // Re-check: the dialog was open for a while and the file may be gone now.
    if (entity.existsSync()) {
      await entity.delete(recursive: true);
      ref.read(analyticsProvider).fileDeleted(isDir ? 'folder' : p.extension(filePath));

      // Also close the tab if open
      final editorState = ref.read(editorStateControllerProvider);
      if (editorState.openFileControllers.containsKey(filePath)) {
        editorState.closeFile(filePath);
      }
    }
  }
}
