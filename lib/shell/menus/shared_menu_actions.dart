import 'package:flutter/widgets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/widgets/text_input_dialog.dart';
import 'package:pinbench_ui/strings.dart';

import '../../features/editor/providers/editor_provider.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import '../../features/workspace/providers/editor_state_provider.dart';
import '../../layout/controllers/app_layout_controller.dart';
import '../../layout/updates/update_dialog.dart';

/// Command bodies shared by the native File/Run/Help menus (`shell/menus/`)
/// and the web menu bar (`layout/bars/title/web_menu_bar.dart`), so "what New
/// Sketch does" (etc.) has exactly one implementation instead of two that can
/// drift — each surface still builds its own menu-item tree, since the OS
/// menu and the in-app one are different widgets with different submenu and
/// shortcut mechanics.

const _hexTypeGroups = [
  XTypeGroup(label: AppStrings.hexFileTypeGroupLabel, extensions: ['hex']),
];

/// Prompts for a name pre-filled with [defaultName] (so the user can just
/// press Enter), then creates and opens the file. Backs "New Sketch (.ino)"
/// and "New Circuit (.cdl)" on both menus.
///
/// [context] should be the menu's own `BuildContext` when the caller has one
/// (the web menu bar does). Native `PlatformMenuItem` callbacks have no
/// `BuildContext` of their own — passing `null` falls back to the currently
/// focused widget's context, same as the rest of the native menus already do.
Future<void> createNamedFile(
  WidgetRef ref, {
  required String title,
  required String defaultName,
  BuildContext? context,
}) async {
  final ctx = context ?? FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return;
  final name = await showTextInputDialog(
    ctx,
    title: title,
    initialValue: defaultName,
    placeholder: defaultName,
  );
  if (name == null) return;
  await ref.read(workspaceFilesProvider.notifier).createFile(name);
}

/// Prompts for a `.hex` file and loads it as the precompiled firmware to run.
/// Backs "Load Compiled .hex..." on both menus.
Future<void> loadPrecompiledHexFile(WorkspaceFiles files) async {
  final file = await openFile(acceptedTypeGroups: _hexTypeGroups);
  if (file == null) return;
  final content = await file.readAsString();
  files.loadPrecompiledHex(path: file.path, content: content);
}

/// Closes the active editor tab (and its canvas tab, if it's a `.cdl`).
/// Backs "Close Editor" on both menus. No-op when nothing (or the welcome
/// tab) is active.
void closeActiveEditorTab(WidgetRef ref) {
  final activeTab = ref.read(activeTabProvider);
  if (activeTab.isEmpty || activeTab == 'Welcome') return;
  ref.read(appLayoutControllerProvider).closeTab(activeTab);
  ref.read(editorStateControllerProvider).closeFile(activeTab);
  if (activeTab.endsWith('.cdl')) {
    ref.read(appLayoutControllerProvider).closeTab('canvas_$activeTab');
  }
}

/// Opens the update dialog, which starts a check as it appears. Backs "Check
/// for Updates…" on both menus.
///
/// [context] follows the same rule as [createNamedFile]: the web menu bar has
/// one, native `PlatformMenuItem` callbacks do not.
Future<void> checkForUpdates(WidgetRef ref, {BuildContext? context}) async {
  final ctx = context ?? FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return;
  await showUpdateDialog(ctx, ref);
}

/// Switches back to the Welcome tab. Backs "Welcome" on the Help menu (and
/// the web menu bar's equivalent entry).
void goToWelcomeTab(WidgetRef ref) {
  ref.read(tabsListProvider.notifier).updateTabs(['Welcome']);
  ref.read(activeTabProvider.notifier).setActive('Welcome');
}
