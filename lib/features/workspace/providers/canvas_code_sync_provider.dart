import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/parts/part_registry_provider.dart';
import '../../../core/telemetry/telemetry_providers.dart';
import '../../../core/chrome/active_circuit_file.dart';
import '../services/canvas_code_sync_service.dart';
import '../services/syncable_canvas.dart';
import 'editor_state_provider.dart';
import 'problems_provider.dart';

part 'canvas_code_sync_provider.g.dart';

/// Keeps the `.cdl` file and the canvas in agreement.
///
/// It named `canvasControllerProvider` until the sync service got a port. Now
/// it reads `syncableCanvasProvider`, which the canvas implements without
/// knowing it does — retiring the last `workspace -> canvas` edge, and with it
/// the last cycle between any two features.
@Riverpod(keepAlive: true)
CanvasCodeSyncService canvasCodeSyncService(Ref ref) {
  // Tolerate the registry still loading: build with no components for now and
  // rebuild (via the watch) once it resolves. Using requireValue here crashed
  // the app at startup when anything touched this service before the async
  // component registry had loaded (e.g. the recent-workspace auto-open).
  final components = ref.watch(partRegistryProvider).value ?? [];
  final canvas = ref.watch(syncableCanvasProvider);
  final editorStateController = ref.watch(editorStateControllerProvider);

  final service = CanvasCodeSyncService(
    canvas: canvas,
    editorStateController: editorStateController,
    components: components,
    onCircuitError: (err) {
      final problems = ref.read(problemsProvider.notifier);
      if (err.isEmpty) {
        problems.clearSource(ProblemSource.circuit);
      } else {
        problems.setForSource(ProblemSource.circuit, [
          Problem(
            severity: ProblemSeverity.error,
            source: ProblemSource.circuit,
            message: err.replaceFirst(RegExp(r'^\[.*?\]\s*'), ''),
          ),
        ]);
      }
    },
    onCircuitValidation: (type) {
      if (type != null) ref.read(analyticsProvider).circuitError(type);
    },
    onActiveCircuitChanged: (path) => ref.read(activeCircuitFileProvider.notifier).set(path),
    onParseError: (err) {
      final problems = ref.read(problemsProvider.notifier);
      if (err == null) {
        problems.clearSource(ProblemSource.parser);
      } else {
        problems.setForSource(ProblemSource.parser, [
          Problem(
            severity: ProblemSeverity.error,
            source: ProblemSource.parser,
            message: 'Invalid circuit syntax',
            detail: err,
          ),
        ]);
      }
    },
  );

  ref.onDispose(service.dispose);
  return service;
}
