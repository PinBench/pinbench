import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/editor/edit_action_router.dart';
import '../../features/workspace/providers/dirty_files_provider.dart';
import '../../features/simulation/providers/simulation_provider.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import 'app_main_menu.dart';
import 'edit_menu.dart';
import 'file/file_menu.dart';
import 'help_menu.dart';
import 'run_menu.dart';
import 'window_menu.dart';

/// Wraps the entire application at the engine root level with a single
/// native macOS PlatformMenuBar. This prevents multiple windows from fighting
/// over the global menu bar and stopping focus-rebuild bugs.
class const GlobalMenuWrapper({super.key, required final Widget child})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<GlobalMenuWrapper> createState() => _GlobalMenuWrapperState();
}

class _GlobalMenuWrapperState extends ConsumerState<GlobalMenuWrapper> {
  /// Tracks the focused editable surface so the Edit menu's undo/redo and
  /// clipboard actions route to the right place. Owned here because this wrapper
  /// is always mounted at the app root while the native menu exists.
  final _editRouter = EditActionRouter();

  @override
  void initState() {
    super.initState();
    _editRouter.startTracking();
  }

  @override
  void dispose() {
    _editRouter.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch just the state that gates File-menu items so the native menu rebuilds
    // (and items enable/disable) when a workspace is opened/closed or the active
    // editor tab changes — but not on every unrelated frame.
    final workspace = ref.watch(workspaceFilesProvider);
    final hasWorkspace = workspace.workspacePath != null;
    // Derived from the live set of open editor files / dirty files so Save
    // reflects real unsaved state instead of the focused-tab guess it used
    // before (which left Save greyed out even after edits).
    final hasEditorTab = ref.watch(openEditorFilesProvider).isNotEmpty;
    final hasUnsavedChanges = ref.watch(dirtyFilesProvider).isNotEmpty;
    final simState = ref.watch(simulationProvider);

    final menus = <PlatformMenuItem>[
      appMainMenu(),
      fileMenu(
        ref: ref,
        hasWorkspace: hasWorkspace,
        hasEditorTab: hasEditorTab,
        hasUnsavedChanges: hasUnsavedChanges,
      ),
      editMenu(ref, _editRouter),
      runMenu(ref: ref, hasWorkspace: hasWorkspace, simState: simState, workspace: workspace),
      // No native View menu: its one entry, Enter Full Screen, is a window
      // command and lives in the Window menu, where macOS apps keep it.
      windowMenu(),
      helpMenu(ref),
    ];

    return PlatformMenuBar(menus: menus, child: widget.child);
  }
}
