import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/widgets/explorer_tree_builder.dart';

/// Unit tests for [ExplorerTreeBuilder], extracted from
/// `ExplorerSidebarView` in Phase 7 of docs/plans/radiant-mixing-pudding.md
/// — pure data-transform logic that was previously untestable without a
/// `WidgetTester`.
void main() {
  group('buildTreeNodes', () {
    test('nests files under their containing folders', () {
      final state = WorkspaceState(
        workspacePath: '/ws',
        files: [File('/ws/sketch.ino'), File('/ws/src/helper.cpp'), File('/ws/src/helper.h')],
      );

      final roots = ExplorerTreeBuilder.buildTreeNodes(state);

      expect(roots, hasLength(1));
      final root = roots.first;
      expect(root.data.name, 'ws');
      expect(root.data.isFolder, isTrue);

      final rootChildNames = root.children.map((n) => n.data.name).toList();
      expect(rootChildNames, containsAll(['sketch.ino', 'src']));

      final srcNode = root.children.firstWhere((n) => n.data.name == 'src');
      expect(srcNode.data.isFolder, isTrue);
      expect(
        srcNode.children.map((n) => n.data.name).toList(),
        containsAll(['helper.cpp', 'helper.h']),
      );
    });

    test('sorts folders before files, then alphabetically within each group', () {
      final state = WorkspaceState(
        workspacePath: '/ws',
        files: [File('/ws/zebra.txt'), File('/ws/apple.txt'), File('/ws/nested/file.txt')],
      );

      final root = ExplorerTreeBuilder.buildTreeNodes(state).first;
      final names = root.children.map((n) => n.data.name).toList();

      expect(names, ['nested', 'apple.txt', 'zebra.txt']);
    });

    test('an empty workspace has just the root folder node', () {
      const state = WorkspaceState(workspacePath: '/ws');

      final roots = ExplorerTreeBuilder.buildTreeNodes(state);

      expect(roots, hasLength(1));
      expect(roots.first.children, isEmpty);
    });
  });

  group('resolveFullPath', () {
    test('walks the parent chain back to a full path under the workspace', () {
      final state = WorkspaceState(workspacePath: '/ws', files: [File('/ws/src/helper.cpp')]);
      final root = ExplorerTreeBuilder.buildTreeNodes(state).first;
      final srcNode = root.children.firstWhere((n) => n.data.name == 'src');
      final fileNode = srcNode.children.first;

      expect(ExplorerTreeBuilder.resolveFullPath(fileNode, '/ws'), '/ws/src/helper.cpp');
      expect(ExplorerTreeBuilder.resolveFullPath(srcNode, '/ws'), '/ws/src');
    });

    test('the root node itself resolves to the workspace path with a trailing slash', () {
      // Pre-existing quirk of the original (unchanged) join logic: the root
      // node's own name is stripped as "the first part", leaving an empty
      // joined remainder appended after a slash.
      const state = WorkspaceState(workspacePath: '/ws');
      final root = ExplorerTreeBuilder.buildTreeNodes(state).first;

      expect(ExplorerTreeBuilder.resolveFullPath(root, '/ws'), '/ws/');
    });
  });

  group('fsEntityComparator', () {
    test('orders a directory before a file regardless of name', () {
      final dir = Directory('/ws/zzzz');
      final file = File('/ws/aaaa.txt');
      expect(ExplorerTreeBuilder.fsEntityComparator(dir, file), lessThan(0));
      expect(ExplorerTreeBuilder.fsEntityComparator(file, dir), greaterThan(0));
    });

    test('orders same-type entries case-insensitively by basename', () {
      final a = File('/ws/Banana.txt');
      final b = File('/ws/apple.txt');
      expect(ExplorerTreeBuilder.fsEntityComparator(a, b), greaterThan(0));
    });
  });
}
