import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:super_tree/super_tree.dart';
import 'package:pinbench_ui/widgets/sidebar_scaffold.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_empty_state.dart';
import 'package:pinbench_ui/ui/app_toast.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../../core/utils/logger.dart';
import '../data/workspace_fs.dart';
import '../models/workspace_state.dart';
import '../providers/workspace_files_provider.dart';
import '../providers/editor_state_provider.dart';
import '../providers/canvas_code_sync_provider.dart';
import 'explorer_context_menu.dart';
import 'explorer_intents.dart';
import 'explorer_tree_builder.dart';
import '../../../core/chrome/chrome_commands.dart';

const _log = AppLogger('app.layout.sidebar');

class const ExplorerSidebarView({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ExplorerSidebarView> createState() => _ExplorerSidebarViewState();
}

class _ExplorerSidebarViewState extends ConsumerState<ExplorerSidebarView> {
  TreeController<FileSystemItem>? _treeController;
  String? _lastWorkspacePath;
  List<FileSystemEntity>? _lastFiles;
  late final FocusNode _focusNode;

  final _contextMenuController = AppContextMenuController();
  List<AppMenuEntry> _contextMenuEntries = [];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ExplorerFocusNode');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _treeController?.dispose();
    super.dispose();
  }

  Future<void> _handleDeleteAction(WidgetRef ref, String workspacePath) async {
    _log.debug('Handling delete action');
    if (_treeController == null) return;
    final selectedIds = _treeController!.selectedNodeIds;
    if (selectedIds.isEmpty) return;
    final node = _treeController!.findNodeById(selectedIds.first);
    if (node != null) {
      final filePath = _resolveFullPath(node, workspacePath);
      await ExplorerContextMenu.deleteItem(context, ref, filePath);
    }
  }

  Future<void> _handleRenameAction(WidgetRef ref, String workspacePath) async {
    _log.debug('Handling rename action');
    if (_treeController == null) return;
    final selectedIds = _treeController!.selectedNodeIds;
    if (selectedIds.isEmpty) return;
    final node = _treeController!.findNodeById(selectedIds.first);
    if (node != null) {
      final filePath = _resolveFullPath(node, workspacePath);
      await ExplorerContextMenu.renameItem(context, ref, filePath);
    }
  }

  Future<void> _handleNewFileAction(WidgetRef ref, String workspacePath) async {
    _log.debug('Handling new file action');
    if (_treeController == null) return;
    final selectedIds = _treeController!.selectedNodeIds;
    var targetPath = workspacePath;
    if (selectedIds.isNotEmpty) {
      final node = _treeController!.findNodeById(selectedIds.first);
      if (node != null) {
        final filePath = _resolveFullPath(node, workspacePath);
        targetPath = WorkspaceFs().isDirectory(filePath) ? filePath : p.dirname(filePath);
      }
    }
    await ExplorerContextMenu.createNewFile(context, ref, targetPath);
  }

  Future<void> _handleNewFolderAction(WidgetRef ref, String workspacePath) async {
    _log.debug('Handling new folder action');
    if (_treeController == null) return;
    final selectedIds = _treeController!.selectedNodeIds;
    var targetPath = workspacePath;
    if (selectedIds.isNotEmpty) {
      final node = _treeController!.findNodeById(selectedIds.first);
      if (node != null) {
        final filePath = _resolveFullPath(node, workspacePath);
        targetPath = WorkspaceFs().isDirectory(filePath) ? filePath : p.dirname(filePath);
      }
    }
    await ExplorerContextMenu.createNewFolder(context, ref, targetPath);
  }

  List<TreeNode<FileSystemItem>> _buildTreeNodes(WorkspaceState state) =>
      ExplorerTreeBuilder.buildTreeNodes(state);

  String _resolveFullPath(TreeNode<FileSystemItem> node, String workspacePath) =>
      ExplorerTreeBuilder.resolveFullPath(node, workspacePath);

  void _rebuildController(WorkspaceState state) {
    final expandedPaths = <String>{};
    if (_treeController != null && _lastWorkspacePath == state.workspacePath) {
      void collectExpanded(TreeNode<FileSystemItem> node) {
        if (node.isExpanded && node.data.isFolder) {
          expandedPaths.add(_resolveFullPath(node, _lastWorkspacePath!));
        }
        node.children.forEach(collectExpanded);
      }

      _treeController!.roots.forEach(collectExpanded);
    }

    _treeController?.dispose();

    final newRoots = _buildTreeNodes(state);

    if (expandedPaths.isNotEmpty) {
      void restoreExpanded(TreeNode<FileSystemItem> node) {
        if (node.data.isFolder) {
          final path = _resolveFullPath(node, state.workspacePath!);
          if (expandedPaths.contains(path)) {
            node.isExpanded = true;
          }
        }
        node.children.forEach(restoreExpanded);
      }

      newRoots.forEach(restoreExpanded);
    }

    _treeController = TreeController<FileSystemItem>(roots: newRoots);
    _lastWorkspacePath = state.workspacePath;
    _lastFiles = state.files;
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceFilesProvider);

    final child = workspaceState.workspacePath == null
        ? _buildEmptyState(context, ref)
        : _buildFileTree(context, ref, workspaceState);

    return SidebarScaffold(
      title: AppStrings.explorerSidebarTitle,
      toolbar: workspaceState.workspacePath != null
          ? Row(
              children: [
                AppIconButton(
                  icon: AppIcons.newFile,
                  tooltip: AppStrings.newFileTooltip,
                  shortcutLabel: '⌘N',
                  onPressed: () => _handleNewFileAction(ref, workspaceState.workspacePath!),
                ),
                AppIconButton(
                  icon: AppIcons.newFolder,
                  tooltip: AppStrings.newFolderTooltip,
                  shortcutLabel: '⇧⌘N',
                  onPressed: () => _handleNewFolderAction(ref, workspaceState.workspacePath!),
                ),
              ],
            )
          : null,
      child: child,
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) => AppEmptyState(
    icon: AppIcons.folderOpen,
    title: AppStrings.explorerEmptyStateMessage,
    children: [
      AppButton(
        onPressed: () async {
          if (kIsWeb) {
            showAppToast(
              context,
              title: AppStrings.webPreviewUnavailableTitle,
              message: AppStrings.webPreviewFolderUnavailableMessage,
            );
            return;
          }
          final directoryPath = await getDirectoryPath();
          if (directoryPath != null) {
            await ref.read(workspaceFilesProvider.notifier).openWorkspace(directoryPath);
          }
        },
        child: const Text(AppStrings.openFolderButtonLabel),
      ),
    ],
  );

  Widget _buildFileTree(BuildContext context, WidgetRef ref, WorkspaceState state) {
    // Rebuild controller when workspace or files change
    if (_treeController == null ||
        _lastWorkspacePath != state.workspacePath ||
        _lastFiles != state.files) {
      _rebuildController(state);
    }

    final colorScheme = context.appColors;

    return Focus(
      focusNode: _focusNode,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.backspace): DeleteNodeIntent(),
          SingleActivator(LogicalKeyboardKey.enter): RenameNodeIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: true): NewFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true): NewFolderIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DeleteNodeIntent: CallbackAction<DeleteNodeIntent>(
              onInvoke: (intent) => _handleDeleteAction(ref, state.workspacePath!),
            ),
            RenameNodeIntent: CallbackAction<RenameNodeIntent>(
              onInvoke: (intent) => _handleRenameAction(ref, state.workspacePath!),
            ),
            NewFileIntent: CallbackAction<NewFileIntent>(
              onInvoke: (intent) => _handleNewFileAction(ref, state.workspacePath!),
            ),
            NewFolderIntent: CallbackAction<NewFolderIntent>(
              onInvoke: (intent) => _handleNewFolderAction(ref, state.workspacePath!),
            ),
          },
          child: AppContextMenu(
            controller: _contextMenuController,
            entries: _contextMenuEntries,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                if (_contextMenuController.isOpen) {
                  _contextMenuController.hide();
                }
                _focusNode.requestFocus();
              },
              child: Container(
                constraints: const BoxConstraints.expand(),
                color: AppPalette.transparent,
                child: SuperTreeView<FileSystemItem>(
                  controller: _treeController,
                  style: TreeViewStyle(
                    indentAmount: 8,
                    hoverColor: colorScheme.accent,
                    selectedColor: colorScheme.accent,
                  ),
                  logic: TreeViewConfig<FileSystemItem>(
                    onNodeTap: (id) async {
                      _focusNode.requestFocus();
                      final node = _treeController!.findNodeById(id);
                      if (node != null && !node.data.isFolder) {
                        await _openFile(ref, node, state.workspacePath!);
                      }
                    },
                  ),
                  prefixBuilder: (context, node) {
                    final item = node.data;
                    final icon = item.isFolder
                        ? (node.isExpanded ? AppIcons.folderOpen : AppIcons.folder)
                        : _getIconForFile(item.name);
                    return Icon(icon, size: AppIconSize.md, color: colorScheme.primary);
                  },
                  contentBuilder: (context, node, renameField) {
                    if (renameField != null) return renameField;
                    final filePath = _resolveFullPath(node, state.workspacePath!);
                    return GestureDetector(
                      onSecondaryTapDown: (details) {
                        setState(() {
                          _contextMenuEntries = ExplorerContextMenu.buildItems(
                            context,
                            ref,
                            node,
                            filePath,
                          );
                        });
                        _contextMenuController.showAt(details.globalPosition);
                      },
                      child: Container(
                        width: double.infinity,
                        color: AppPalette.transparent,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          node.data.name,
                          maxLines: 1,
                          style: AppTextStyles.body(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(WidgetRef ref, TreeNode<FileSystemItem> node, String workspacePath) async {
    final filePath = _resolveFullPath(node, workspacePath);

    try {
      final contents = await WorkspaceFs().readString(filePath);
      final controller = ref.read(editorStateControllerProvider).openFile(filePath, contents);

      final chrome = ref.read(chromeCommandsProvider);
      if (filePath.endsWith('.cdl')) {
        ref.read(canvasCodeSyncServiceProvider).attachCdlListener(filePath, controller);
        chrome.openCanvasTab(filePath);
      } else {
        chrome.openEditorTab(filePath);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: AppStrings.fileReadErrorMessage(e), isError: true);
      }
    }
  }

  IconData _getIconForFile(String fileName) {
    if (fileName.endsWith('.ino')) return AppIcons.sketch;
    if (fileName.endsWith('.cpp') || fileName.endsWith('.h')) return AppIcons.code;
    if (fileName.endsWith('.cdl')) return AppIcons.circuit;
    if (fileName.endsWith('.md')) return AppIcons.fileText;
    if (fileName.endsWith('.json')) return AppIcons.fileJson;
    if (fileName.endsWith('.yaml') || fileName.endsWith('.yml')) {
      return AppIcons.fileConfig;
    }
    if (fileName.endsWith('.dart')) return AppIcons.code;
    if (fileName.endsWith('.lock')) return AppIcons.locked;
    return AppIcons.file;
  }
}
