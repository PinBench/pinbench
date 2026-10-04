import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/canvas/controller/canvas_controller.dart';
import '../features/workspace/providers/log_providers.dart';
import '../features/workspace/providers/problems_provider.dart';
import '../features/workspace/providers/workspace_files_provider.dart';

/// Clears what belongs to one workspace when another replaces it.
///
/// The bottom panes and the canvas outlive the workspace they show: the logs,
/// Problems and the undo history are app-wide state, so opening a template
/// after running another left its serial output on screen, its compile errors
/// listed, and ⌘Z ready to replay its edits onto the new circuit.
///
/// Keyed on the workspace *path*, which every way of switching changes: a
/// template or a blank project opens in a fresh temporary folder, another
/// folder has its own path, and Close Folder sets it to null. Reopening the
/// folder already open changes nothing, and nothing needs clearing then.
///
/// Here, at the app layer, because the state it clears belongs to three
/// features that may not import one another (`test/architecture/`). Already
/// handled elsewhere, so not repeated: a running simulation stops itself on a
/// workspace change (`simulation_bindings.dart`), the editor's tabs close as
/// the workspace opens (`openWorkspace`), and the Serial Plotter is drawn from
/// the serial log. The terminal is deliberately left alone: its shell is not
/// tied to the workspace, and ending it would end whatever runs in it.
class const WorkspaceSessionReset({required final Widget child, super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(workspaceFilesProvider.select((s) => s.workspacePath), (previous, next) {
      if (previous == next) return;
      ref.read(logsRepositoryProvider).clearAll();
      ref.read(problemsProvider.notifier).clearAll();
      ref.read(canvasControllerProvider.notifier).historyManager.clear();
    });
    return child;
  }
}
