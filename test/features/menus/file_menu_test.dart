import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/shell/menus/file/file_menu.dart';

/// Flattens a PlatformMenu tree into a label -> onSelected map so we can assert
/// which items are enabled (non-null callback) vs disabled (null) in each state.
Map<String, VoidCallback?> _collect(List<PlatformMenuItem> items) {
  final out = <String, VoidCallback?>{};
  for (final item in items) {
    if (item is PlatformMenuItemGroup) {
      out.addAll(_collect(item.members));
    } else if (item is PlatformMenu) {
      out.addAll(_collect(item.menus));
    } else {
      out[item.label] = item.onSelected;
    }
  }
  return out;
}

Future<Map<String, VoidCallback?>> _items(
  WidgetTester tester, {
  required bool hasWorkspace,
  required bool hasEditorTab,
  bool hasUnsavedChanges = false,
}) async {
  late Map<String, VoidCallback?> result;
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          final menu = fileMenu(
            ref: ref,
            hasWorkspace: hasWorkspace,
            hasEditorTab: hasEditorTab,
            hasUnsavedChanges: hasUnsavedChanges,
          );
          result = _collect(menu.menus);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('no workspace: save/new-file/workspace/close-folder/export are disabled', (
    tester,
  ) async {
    final items = await _items(tester, hasWorkspace: false, hasEditorTab: false);

    for (final label in [
      'Save',
      'Save As...',
      'Save All',
      'Auto Save',
      'New Text File',
      'New File...',
      'Save Workspace As...',
      'Duplicate Workspace',
      'Close Folder',
      'Export to zip...',
    ]) {
      expect(items[label], isNull, reason: '"$label" should be disabled with no workspace');
    }

    // Always-available regardless of workspace.
    expect(items['Open...'], isNotNull);
    expect(items['New Window'], isNotNull);
    expect(items['Close Window'], isNotNull);
    expect(items['Add Folder to Workspace...'], isNotNull);
  });

  testWidgets('welcome with a lingering workspace: save + close-editor disabled', (tester) async {
    // A recent workspace folder may be open while the welcome tab is showing and
    // no file is open. Saving has nothing to save, so it must be disabled.
    final items = await _items(tester, hasWorkspace: true, hasEditorTab: false);

    for (final label in [
      'Save',
      'Save As...',
      'Save All',
      'Auto Save',
      'Revert File',
      'Close Editor',
    ]) {
      expect(items[label], isNull, reason: '"$label" should be disabled with no file open');
    }

    // Folder-level actions remain available because a folder is open.
    expect(items['New File...'], isNotNull);
    expect(items['Close Folder'], isNotNull);
    expect(items['Export to zip...'], isNotNull);
  });

  testWidgets('workspace + editor tab: everything enabled', (tester) async {
    final items = await _items(
      tester,
      hasWorkspace: true,
      hasEditorTab: true,
      hasUnsavedChanges: true,
    );

    for (final label in [
      'Save',
      'Save As...',
      'Save All',
      'New Text File',
      'New File...',
      'Save Workspace As...',
      'Duplicate Workspace',
      'Close Folder',
      'Export to zip...',
      'Revert File',
      'Close Editor',
    ]) {
      expect(items[label], isNotNull, reason: '"$label" should be enabled');
    }
  });
}
