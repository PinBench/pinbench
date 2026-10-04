import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_context_menu.dart';
import 'package:pinbench_ui/ui/app_menu_bar.dart';
import 'package:pinbench_ui/ui/app_about_dialog.dart';

import '../../../features/canvas/providers/canvas_controller_provider.dart';
import '../../../features/editor/edit_action_router.dart';
import '../../../features/workspace/providers/dirty_files_provider.dart';
import '../../../features/simulation/providers/simulation_provider.dart';
import '../../../core/edition/edition_provider.dart';
import '../../../features/workspace/providers/workspace_files_provider.dart';
import '../../../features/workspace/services/file_picker_actions.dart';
import '../../../shell/menus/shared_menu_actions.dart';
import '../../../shell/menus/shortcut_label.dart';
import '../../controllers/app_layout_controller.dart';

/// An operating-system–style menu bar (File / Edit / View / Help) rendered in
/// the title bar on the web.
///
/// Native builds get a real `PlatformMenuBar` via `GlobalMenuWrapper`, which
/// the OS draws in its own menu bar. The web has no such affordance, so we
/// replicate the familiar top-level menus in-app with [AppMenuBar]. The item
/// set mirrors the native menus but drops entries that only make sense for a
/// native window (minimize/zoom, hide, new OS window, etc.).
class const WebMenuBar({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WebMenuBar> createState() => _WebMenuBarState();
}

class _WebMenuBarState extends ConsumerState<WebMenuBar> {
  /// Tracks the focused editable surface so Edit actions route to the right
  /// place. Shared with the native menu (`shell/menus/edit_menu.dart`).
  final _editRouter = EditActionRouter();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _editRouter.startTracking();
  }

  @override
  void dispose() {
    if (kIsWeb) _editRouter.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Native platforms already have a real menu bar; only the web needs this.
    if (!kIsWeb) return const SizedBox.shrink();

    final hasWorkspace = ref.watch(workspaceFilesProvider.select((s) => s.workspacePath != null));
    final hasEditorTab = ref.watch(openEditorFilesProvider).isNotEmpty;
    final hasUnsavedChanges = ref.watch(dirtyFilesProvider).isNotEmpty;

    // Click to open, not hover: a menu that dropped on hover stayed stuck open
    // when the pointer moved away, and click-to-open is what a desktop menu bar
    // does anyway. Flutter's menu bar behaves this way natively — it is only
    // once a menu is open that sliding across the bar moves between them.
    return AppMenuBar(
      menus: [
        AppMenu(
          label: AppStrings.fileMenuLabel,
          entries: _fileItems(hasWorkspace, hasEditorTab, hasUnsavedChanges),
        ),
        AppMenu(label: AppStrings.editMenuLabel, entries: _editItems()),
        AppMenu(label: AppStrings.runMenuLabel, entries: _runItems(hasWorkspace)),
        AppMenu(label: AppStrings.viewMenuLabel, entries: _viewItems()),
        AppMenu(label: AppStrings.helpMenuLabel, entries: _helpItems()),
      ],
    );
  }

  // ── File ───────────────────────────────────────────────────────────────────
  List<AppMenuEntry> _fileItems(bool hasWorkspace, bool hasEditorTab, bool hasUnsavedChanges) {
    final files = ref.read(workspaceFilesProvider.notifier);
    return [
      _action(
        AppStrings.newTextFileMenuLabel,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyN, meta: true)),
        enabled: hasWorkspace,
        onPressed: files.createUntitledTextFile,
      ),
      _action(
        AppStrings.newSketchMenuLabel,
        enabled: hasWorkspace,
        onPressed: () => createNamedFile(
          ref,
          title: AppStrings.newSketchDialogTitle,
          defaultName: 'sketch.ino',
          context: context,
        ),
      ),
      _action(
        AppStrings.newCircuitMenuLabel,
        enabled: hasWorkspace,
        onPressed: () => createNamedFile(
          ref,
          title: AppStrings.newCircuitDialogTitle,
          defaultName: 'circuit.cdl',
          context: context,
        ),
      ),
      _action(
        AppStrings.openFileMenuLabelWeb,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyO, meta: true)),
        onPressed: () => pickAndOpenFile(files),
      ),
      const AppMenuSeparator(),
      _action(
        AppStrings.saveButtonLabel,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyS, meta: true)),
        enabled: hasUnsavedChanges,
        onPressed: files.saveCurrentWorkspace,
      ),
      _action(
        AppStrings.saveAsMenuLabel,
        shortcut: shortcutLabel(
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
        ),
        enabled: hasEditorTab,
        onPressed: files.saveWorkspaceToLocation,
      ),
      _action(
        AppStrings.saveAllMenuLabel,
        shortcut: shortcutLabel(
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true, alt: true),
        ),
        enabled: hasUnsavedChanges,
        onPressed: files.saveAll,
      ),
      const AppMenuSeparator(),
      _action(
        AppStrings.closeEditorMenuLabel,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyW, meta: true)),
        enabled: hasEditorTab,
        onPressed: () => closeActiveEditorTab(ref),
      ),
      const AppMenuSeparator(),
      _action(
        AppStrings.exportZipMenuLabel,
        enabled: hasWorkspace,
        onPressed: () => pickAndExportWorkspaceZip(files),
      ),
    ];
  }

  // ── Run ────────────────────────────────────────────────────────────────────
  List<AppMenuEntry> _runItems(bool hasWorkspace) {
    final sim = ref.watch(simulationProvider);
    final files = ref.read(workspaceFilesProvider.notifier);
    final hexLoaded = ref.watch(workspaceFilesProvider.select((s) => s.precompiledHexPath != null));
    final isSimulating = sim != SimulationState.stopped;
    final isPaused = sim == SimulationState.paused;
    return [
      _action(
        isSimulating ? AppStrings.stopSimulationMenuLabelWeb : AppStrings.runSimulationMenuLabelWeb,
        shortcut: 'F5',
        enabled: hasWorkspace,
        onPressed: () => ref.read(simulationProvider.notifier).toggle(),
      ),
      _action(
        isPaused ? AppStrings.resumeSimulationMenuLabelWeb : AppStrings.pauseSimulationMenuLabelWeb,
        shortcut: 'F8',
        enabled: isSimulating,
        onPressed: () => ref.read(simulationProvider.notifier).togglePause(),
      ),
      const AppMenuSeparator(),
      _action(
        hexLoaded ? AppStrings.loadHexMenuLabelLoadedWeb : AppStrings.loadHexMenuLabel,
        enabled: hasWorkspace,
        onPressed: () => loadPrecompiledHexFile(files),
      ),
      _action(
        AppStrings.useCompilerMenuLabel,
        enabled: hexLoaded,
        onPressed: files.clearPrecompiledHex,
      ),
    ];
  }

  // ── Edit ─────────────────────────────────────────────────────────────────
  //
  // Each action targets whichever surface currently holds focus: a plain text
  // field (via a text intent), the re_editor code editor (via its own
  // controller), or the canvas. So undo/redo and clipboard work everywhere the
  // user can edit — code, inputs, and the circuit.
  List<AppMenuEntry> _editItems() {
    final canvas = ref.read(canvasControllerProvider.notifier);
    return [
      _action(
        AppStrings.undo,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyZ, meta: true)),
        onPressed: () => _editRouter.route(
          textIntent: const UndoTextIntent(SelectionChangedCause.keyboard),
          codeAction: (c) => c.undo(),
          canvasFallback: canvas.undo,
        ),
      ),
      _action(
        AppStrings.redo,
        shortcut: shortcutLabel(
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
        ),
        onPressed: () => _editRouter.route(
          textIntent: const RedoTextIntent(SelectionChangedCause.keyboard),
          codeAction: (c) => c.redo(),
          canvasFallback: canvas.redo,
        ),
      ),
      const AppMenuSeparator(),
      _action(
        AppStrings.cutMenuLabel,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyX, meta: true)),
        onPressed: () => _editRouter.route(
          textIntent: const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
          codeAction: (c) => c.cut(),
          canvasFallback: () {
            canvas.copy();
            canvas.remove();
          },
        ),
      ),
      _action(
        AppStrings.copy,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyC, meta: true)),
        onPressed: () => _editRouter.route(
          textIntent: CopySelectionTextIntent.copy,
          codeAction: (c) => c.copy(),
          canvasFallback: canvas.copy,
        ),
      ),
      _action(
        AppStrings.paste,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyV, meta: true)),
        onPressed: () => _editRouter.route(
          textIntent: const PasteTextIntent(SelectionChangedCause.keyboard),
          codeAction: (c) => c.paste(),
          canvasFallback: canvas.paste,
        ),
      ),
      _action(
        AppStrings.selectAllMenuLabel,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.keyA, meta: true)),
        onPressed: () => _editRouter.route(
          textIntent: const SelectAllTextIntent(SelectionChangedCause.keyboard),
          codeAction: (c) => c.selectAll(),
        ),
      ),
    ];
  }

  // ── View ─────────────────────────────────────────────────────────────────
  List<AppMenuEntry> _viewItems() {
    final layout = ref.read(appLayoutControllerProvider);
    return [
      _action(AppStrings.toggleLeftPaneTooltip, onPressed: () => layout.togglePane('left_slot')),
      _action(
        AppStrings.toggleBottomPaneTooltip,
        onPressed: () => layout.togglePane('bottom_pane'),
      ),
      if (ref.read(editionPanelProvider) != null)
        _action(
          AppStrings.toggleRightPaneTooltip,
          onPressed: () => layout.togglePane('right_pane'),
        ),
      // Under View rather than File: settings is a tab you show, the same as
      // the panes above it.
      _action(
        AppStrings.settingsTitle,
        shortcut: shortcutLabel(const SingleActivator(LogicalKeyboardKey.comma, meta: true)),
        onPressed: layout.openSettingsTab,
      ),
    ];
  }

  // ── Help ─────────────────────────────────────────────────────────────────
  List<AppMenuEntry> _helpItems() => [
    _action('Welcome', onPressed: () => goToWelcomeTab(ref)),
    _action(AppStrings.releaseNotesMenuLabel, onPressed: () => openReleaseNotes(ref)),
    // Present on the web too, where it says the build updates itself on
    // reload — the alternative is a menu whose entries differ per platform
    // for a question every user is entitled to ask.
    _action(
      AppStrings.updatesCheckMenuLabel,
      onPressed: () => unawaited(checkForUpdates(ref, context: context)),
    ),
    const AppMenuSeparator(),
    _action(
      AppStrings.aboutMenuItemLabel,
      onPressed: () => unawaited(showAboutAppDialog(context, applicationName: AppStrings.appName)),
    ),
  ];

  /// Builds a single dropdown row with an optional right-aligned [shortcut].
  AppContextMenuItem _action(
    String label, {
    required VoidCallback onPressed,
    String? shortcut,
    bool enabled = true,
  }) => AppContextMenuItem(text: label, onPressed: onPressed, shortcut: shortcut, enabled: enabled);
}
