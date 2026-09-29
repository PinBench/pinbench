import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../../app/router.dart';
import '../../core/shortcuts/app_intents.dart';
import '../../features/canvas/providers/canvas_controller_provider.dart';
import '../../features/canvas/utils/canvas_exporter.dart';
import '../../features/simulation/providers/simulation_provider.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import '../../features/workspace/widgets/leave_temporary_project_dialog.dart';
import '../../features/workspace/providers/editor_state_provider.dart';
import '../../layout/controllers/app_layout_controller.dart';
import '../menus/shared_menu_actions.dart';
import '../../core/chrome/active_circuit_file.dart';

class _GlobalAction<T extends Intent>({required final void Function(T intent) onInvoke})
    extends Action<T> {
  @override
  void invoke(T intent) => onInvoke(intent);
}

/// Asks about an unsaved temporary project, then goes home.
///
/// Detached from the intent handler, which cannot await: an [Action] returns
/// immediately and the dialog outlives it.
Future<void> _leaveHome(BuildContext context, WidgetRef ref) async {
  if (!await confirmLeavingTemporaryProject(context, ref)) return;
  if (!context.mounted) return;
  ref.read(workspaceFilesProvider.notifier).closeFolder();
  const HomeRoute().go(context);
}

/// Wraps the application with global keyboard shortcuts and their actions.
///
/// These fire wherever focus happens to be — see [_AppShortcutsState] for what
/// that takes. Canvas-scoped shortcuts (undo, zoom, rotate, …) live in
/// `CanvasShortcuts`.
class const AppShortcuts({super.key, required final Widget child}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts> {
  /// The scope every shortcut below is reachable from.
  final _scope = FocusScopeNode(debugLabel: 'AppShortcuts');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reclaimFocusIfLoose);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimFocusIfLoose);
    _scope.dispose();
    super.dispose();
  }

  /// Pulls focus back down into the app when it comes to rest above it.
  ///
  /// A key event travels *up* from the focused node, so `Shortcuts` only sees
  /// one when focus is inside its subtree. Clicking something that takes focus
  /// and then drops it — a tab strip, a toolbar button — leaves focus on the
  /// enclosing route scope, which is an ancestor of this widget, so every
  /// app-wide shortcut goes dead until the user clicks back into the editor.
  ///
  /// Only for focus resting on an ancestor, which means nothing in the app
  /// holds it. A dialog, a menu or a text field owns a node that is not an
  /// ancestor of this scope, and stealing focus from those would break typing
  /// and dismissal.
  void _reclaimFocusIfLoose() {
    if (!mounted || _scope.context == null || !_scope.canRequestFocus) return;

    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && !_scope.ancestors.contains(focused)) return;
    if (focused == _scope) return;

    _scope.requestFocus();
  }

  /// Binds both the ⌘ (macOS) and Ctrl (Windows/Linux) variants of [key]
  /// (optionally with [shift]/[alt]) to [intent].
  static void _bindMod(
    Map<LogicalKeySet, Intent> map,
    LogicalKeyboardKey key,
    Intent intent, {
    bool shift = false,
    bool alt = false,
  }) {
    for (final mod in [LogicalKeyboardKey.meta, LogicalKeyboardKey.control]) {
      map[LogicalKeySet.fromSet({
            mod,
            key,
            if (shift) LogicalKeyboardKey.shift,
            if (alt) LogicalKeyboardKey.alt,
          })] =
          intent;
    }
  }

  static Map<LogicalKeySet, Intent> _shortcuts() {
    final map = <LogicalKeySet, Intent>{};
    _bindMod(map, LogicalKeyboardKey.keyS, const SaveIntent());
    _bindMod(map, LogicalKeyboardKey.keyO, const OpenIntent());
    _bindMod(map, LogicalKeyboardKey.keyN, const NewIntent());
    _bindMod(map, LogicalKeyboardKey.keyE, const ExportCircuitIntent());
    _bindMod(map, LogicalKeyboardKey.keyW, const CloseTabIntent());
    _bindMod(map, LogicalKeyboardKey.keyB, const ToggleLeftPaneIntent());
    _bindMod(map, LogicalKeyboardKey.keyJ, const ToggleBottomPaneIntent());
    _bindMod(map, LogicalKeyboardKey.keyB, const ToggleRightPaneIntent(), alt: true);
    _bindMod(map, LogicalKeyboardKey.keyL, const ToggleThemeIntent(), shift: true);
    _bindMod(map, LogicalKeyboardKey.keyH, const GoHomeIntent(), shift: true);
    _bindMod(map, LogicalKeyboardKey.backslash, const ViewCodeIntent());
    _bindMod(map, LogicalKeyboardKey.comma, const OpenSettingsIntent());
    map[LogicalKeySet(LogicalKeyboardKey.f5)] = const ToggleSimulationIntent();
    map[LogicalKeySet(LogicalKeyboardKey.f8)] = const PauseSimulationIntent();
    return map;
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _shortcuts(),
    child: Actions(
      actions: <Type, Action<Intent>>{
        SaveIntent: _GlobalAction<SaveIntent>(
          onInvoke: (intent) async {
            final workspacePath = ref.read(workspaceFilesProvider).workspacePath;
            if (workspacePath != null) {
              await ref.read(workspaceFilesProvider.notifier).saveWorkspace(workspacePath);
            } else {
              final dir = await getDirectoryPath();
              if (dir != null) {
                await ref.read(workspaceFilesProvider.notifier).saveWorkspace(dir);
                await ref.read(workspaceFilesProvider.notifier).openWorkspace(dir);
              }
            }
          },
        ),
        OpenIntent: _GlobalAction<OpenIntent>(
          onInvoke: (intent) async {
            final dir = await getDirectoryPath();
            if (dir != null) {
              await ref.read(workspaceFilesProvider.notifier).openWorkspace(dir);
            }
          },
        ),
        NewIntent: _GlobalAction<NewIntent>(
          onInvoke: (intent) {
            final editorState = ref.read(editorStateControllerProvider);
            var count = 1;
            while (editorState.openFileControllers.containsKey('Untitled-$count')) {
              count++;
            }
            final newFileName = 'Untitled-$count';

            editorState.openFile(newFileName, '');
            ref.read(appLayoutControllerProvider).openEditorTab(newFileName);
          },
        ),
        ToggleSimulationIntent: _GlobalAction<ToggleSimulationIntent>(
          onInvoke: (intent) => ref.read(simulationProvider.notifier).toggle(),
        ),
        PauseSimulationIntent: _GlobalAction<PauseSimulationIntent>(
          onInvoke: (intent) => ref.read(simulationProvider.notifier).togglePause(),
        ),
        ToggleLeftPaneIntent: _GlobalAction<ToggleLeftPaneIntent>(
          onInvoke: (intent) => ref.read(appLayoutControllerProvider).togglePane('left_slot'),
        ),
        ToggleBottomPaneIntent: _GlobalAction<ToggleBottomPaneIntent>(
          onInvoke: (intent) => ref.read(appLayoutControllerProvider).togglePane('bottom_pane'),
        ),
        ToggleRightPaneIntent: _GlobalAction<ToggleRightPaneIntent>(
          onInvoke: (intent) => ref.read(appLayoutControllerProvider).togglePane('right_pane'),
        ),
        ToggleThemeIntent: _GlobalAction<ToggleThemeIntent>(
          onInvoke: (intent) {
            final isDark = ref.read(themeModeProvider) == AppThemeMode.dark;
            ref
                .read(themeModeProvider.notifier)
                .setMode(isDark ? AppThemeMode.light : AppThemeMode.dark);
          },
        ),
        CloseTabIntent: _GlobalAction<CloseTabIntent>(
          onInvoke: (intent) => closeActiveEditorTab(ref),
        ),
        GoHomeIntent: _GlobalAction<GoHomeIntent>(
          onInvoke: (intent) {
            if (ref.read(workspaceFilesProvider).workspacePath == null) return;
            // Same prompt as the title bar's home button: the shortcut is the
            // same action, and a temporary project is lost either way. The
            // action itself is synchronous, so the dialog runs detached.
            unawaited(_leaveHome(context, ref));
          },
        ),
        OpenSettingsIntent: _GlobalAction<OpenSettingsIntent>(
          onInvoke: (intent) => ref.read(appLayoutControllerProvider).openSettingsTab(),
        ),
        ViewCodeIntent: _GlobalAction<ViewCodeIntent>(
          onInvoke: (intent) {
            final path = ref.read(activeCircuitFileProvider);
            if (path != null) ref.read(appLayoutControllerProvider).openEditorTab(path);
          },
        ),
        ExportCircuitIntent: _GlobalAction<ExportCircuitIntent>(
          onInvoke: (intent) async {
            final controller = ref.read(canvasControllerProvider.notifier);
            final success = await CanvasExporter.exportToPng(controller);
            if (!context.mounted) return;
            showAppToast(
              context,
              title: success ? AppStrings.exportSuccessTitle : AppStrings.exportFailedTitle,
              message: success ? AppStrings.exportSuccessMessage : AppStrings.exportFailedMessage,
              isError: !success,
            );
          },
        ),
      },
      // A `FocusScope` that grabs focus on startup, so the shortcuts above are
      // reachable from the very first keystroke and stay reachable afterwards.
      //
      // `Shortcuts` only sees a key event when the focused node sits inside
      // its subtree. Clicking something that takes focus and then gives it up
      // — a tab strip, a toolbar button — otherwise leaves focus on the root
      // scope, which is *above* this widget, and every app-wide shortcut goes
      // dead until the user clicks back into the editor. Unfocusing moves
      // focus to the nearest enclosing scope, so putting one here means that
      // lands inside the subtree rather than outside it.
      child: FocusScope(node: _scope, autofocus: true, child: widget.child),
    ),
  );
}
