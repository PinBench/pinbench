import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/core/sketch_compiler.dart';

/// Where the code for a run comes from, and how it becomes runnable bytes.
///
/// Every member here is a question with a workspace-shaped answer — which of
/// the open buffers is the main sketch, whether there is a directory on disk
/// to build instead of a buffer, whether a template shipped a prebuilt `.hex`
/// — and the simulation had been answering all of them itself by reaching
/// into the workspace's providers. It only ever needed the answers.
abstract interface class SimulationSketch {
  /// The sketch source to run: the configured main `.ino` if there is one,
  /// otherwise whichever open `.ino` the host considers current. Empty when
  /// there is nothing to run.
  String get source;

  /// The sketch directory to build, if the sketch is on disk. Null for a
  /// buffer-only sketch, which the compiler builds as a single file.
  ///
  /// Multi-file sketches and bundled libraries only build when this travels —
  /// see `sketch_compiler_port_test.dart`.
  String? get workspacePath;

  /// A prebuilt image to run as-is, skipping compilation entirely. This is how
  /// the web preview runs bundled templates without a compile service.
  String? get precompiledHex;

  /// How a sketch becomes an Intel HEX image. The engine's own port, surfaced
  /// here because choosing a compiler is the same host decision as choosing
  /// what to compile.
  SketchCompiler get compiler;

  /// Flushes unsaved edits, so a run never executes stale code.
  Future<void> save();

  /// Fires when the open workspace is *replaced* — a different project or
  /// template opened, not a file edited within the current one.
  ///
  /// A run outlives the circuit it was started against unless something stops
  /// it: this provider is kept alive by shell-level watchers, so returning to
  /// the welcome screen and opening another template would otherwise leave the
  /// previous sketch's loop ticking and driving pin updates onto the new
  /// circuit.
  Listenable get workspaceChanges;
}

/// The live workspace binding. Has no default — see `simulationCanvasProvider`
/// for why, and `lib/app/simulation/` for the implementation.
final simulationSketchProvider = Provider<SimulationSketch>(
  (ref) => throw UnimplementedError(
    'simulationSketchProvider has no binding. Override it with the adapter in '
    'lib/app/simulation/, or with a fake from test/helpers/simulation_bindings.dart.',
  ),
);
