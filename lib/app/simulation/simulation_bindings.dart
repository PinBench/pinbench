import '../../features/canvas/controller/canvas_controller.dart';
import '../../features/simulation/ports/simulation_canvas.dart';
import '../../features/simulation/ports/simulation_diagnostics.dart';
import '../../features/simulation/ports/simulation_sketch.dart';
import '../../features/workspace/providers/workspace_files_provider.dart';
import 'canvas_simulation_canvas.dart';
import 'workspace_simulation_diagnostics.dart';
import 'workspace_simulation_sketch.dart';

/// Wires the simulation's three ports to the features that implement them.
///
/// This is the whole of what the simulation knows about the rest of the app,
/// in one file, at the one layer allowed to know both sides. The ports
/// themselves have no default binding on purpose: a missing override fails
/// loudly the first time something starts a run, rather than quietly
/// simulating nothing.
///
/// Untyped on purpose: Riverpod 3 does not export `Override`, so the element
/// type has to be inferred rather than written down.
final simulationBindings = [
  simulationCanvasProvider.overrideWith((ref) {
    final adapter = CanvasSimulationCanvas(ref.watch(canvasControllerProvider.notifier));

    // `listen`, not `watch`: a canvas edit must reach the running simulation
    // without rebuilding this provider, because rebuilding it rebuilds the
    // `Simulation` notifier watching it — and a second run loop on the same
    // circuit is the bug this shape exists to prevent.
    ref.listen(canvasControllerProvider, (_, _) => adapter.onCanvasChanged());
    ref.onDispose(adapter.dispose);
    return adapter;
  }),

  simulationSketchProvider.overrideWith((ref) {
    final adapter = WorkspaceSimulationSketch(ref);

    // Only a *replaced* workspace counts. Editing a file in the open project
    // changes this state too, and stopping the run on every keystroke is not
    // what the simulation asked to hear about.
    ref.listen(workspaceFilesProvider, (previous, next) {
      if (previous?.workspacePath != next.workspacePath) adapter.onWorkspaceChanged();
    });
    ref.onDispose(adapter.dispose);
    return adapter;
  }),

  simulationDiagnosticsProvider.overrideWith(WorkspaceSimulationDiagnostics.new),
];
