import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:super_tree/super_tree.dart';
import 'package:pinbench_ui/strings.dart';

import '../models/workspace_state.dart';

/// Pure file-tree construction for the Explorer sidebar: converting a flat
/// [WorkspaceState.files] list into a [TreeNode] hierarchy, and resolving a
/// tree node back to its full filesystem path. Extracted from
/// `ExplorerSidebarView` — has no widget dependency, so it's directly
/// unit-testable (it wasn't, before this extraction).
abstract final class ExplorerTreeBuilder {
  /// Sorts [FileSystemEntity] items folders-first, then alphabetically by
  /// name within each group.
  static int fsEntityComparator(FileSystemEntity a, FileSystemEntity b) {
    final aIsDir = a is Directory;
    final bIsDir = b is Directory;
    if (aIsDir && !bIsDir) return -1;
    if (!aIsDir && bIsDir) return 1;
    return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
  }

  /// Builds a hierarchical tree of [TreeNode<FileSystemItem>] from a flat
  /// file list.
  static List<TreeNode<FileSystemItem>> buildTreeNodes(WorkspaceState state) {
    final workspacePath = state.workspacePath!;
    final rootName = state.isTemporary
        ? AppStrings.untitledProjectLabel
        : p.basename(workspacePath);

    // Build a map of path -> children
    final childrenMap = <String, List<FileSystemEntity>>{};
    childrenMap[workspacePath] = [];

    for (final file in state.files) {
      final parent = p.dirname(file.path);
      childrenMap.putIfAbsent(parent, () => []);
      childrenMap[parent]!.add(file);
    }

    // Also collect directories that contain files
    final allDirs = <String>{};
    for (final file in state.files) {
      var dir = p.dirname(file.path);
      while (dir != workspacePath && dir.startsWith(workspacePath)) {
        allDirs.add(dir);
        dir = p.dirname(dir);
      }
    }

    // Sort directories into their parent's children map
    for (final dirPath in allDirs) {
      final parent = p.dirname(dirPath);
      childrenMap.putIfAbsent(parent, () => []);
      // Add directory entity if not already present
      if (!childrenMap[parent]!.any((e) => e.path == dirPath)) {
        childrenMap[parent]!.add(Directory(dirPath));
      }
    }

    TreeNode<FileSystemItem> buildNode(FileSystemEntity entity) {
      final name = p.basename(entity.path);
      final isDir = entity is Directory;

      if (isDir) {
        final children = childrenMap[entity.path] ?? [];
        // Sort: folders first, then files, alphabetically within each group
        children.sort(fsEntityComparator);

        return TreeNode<FileSystemItem>(
          data: FolderItem(name),
          children: children.map(buildNode).toList(),
        );
      } else {
        return TreeNode<FileSystemItem>(data: FileItem(name));
      }
    }

    // Build root children
    final rootChildren = childrenMap[workspacePath] ?? [];
    rootChildren.sort(fsEntityComparator);

    return [
      TreeNode<FileSystemItem>(
        data: FolderItem(rootName),
        isExpanded: true,
        children: rootChildren.map(buildNode).toList(),
      ),
    ];
  }

  /// Resolves the full path from a tree node by walking up the parent chain.
  static String resolveFullPath(TreeNode<FileSystemItem> node, String workspacePath) {
    final parts = <String>[];
    TreeNode<FileSystemItem>? current = node;
    while (current != null) {
      parts.insert(0, current.data.name);
      current = current.parent;
    }
    // The first part is the root folder name, which corresponds to workspacePath
    if (parts.isNotEmpty) parts.removeAt(0);
    return '$workspacePath/${parts.join('/')}';
  }
}
