import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

/// The circuit a run drives, and the lock that stops it being edited mid-run.
///
/// [SimulationOutput] is the engine's own port — the placed parts, the wires,
/// and where per-frame results go. This adds the two things that are the
/// *app's* business rather than the engine's: a run takes the canvas
/// read-only, and it wants telling when the placed circuit changes (a button
/// press, a potentiometer turn) so it can forward that into the isolate.
///
/// Declared here, on the simulation's side of the boundary, so the feature
/// names what it needs rather than reaching for whichever widget tree happens
/// to hold it today — see `lib/app/simulation/` for the canvas binding.
abstract interface class SimulationCanvas implements SimulationOutput {
  /// Locks the circuit against user edits for the duration of a run.
  ///
  /// The simulation owns this while it holds it, and releasing it is part of
  /// every path back to `stopped` — including the ones that fail.
  abstract bool isReadOnly;

  /// Fires when the placed circuit changes.
  ///
  /// Deliberately a bare signal with no payload — the runner re-reads
  /// [SimulationOutput.simulationNodes] to see what actually moved. Anything
  /// richer would make this port describe canvas edits, which is the coupling
  /// it exists to remove.
  Listenable get changes;
}

/// The live canvas binding. Has no default: an app that runs simulations must
/// say what they run *on*.
///
/// Overridden in `buildGlobalScope` (see `lib/app/simulation/`). A test that
/// only renders a widget reading `simulationProvider` can override it with a
/// stand-in — `test/helpers/simulation_bindings.dart` has one.
final simulationCanvasProvider = Provider<SimulationCanvas>(
  (ref) => throw UnimplementedError(
    'simulationCanvasProvider has no binding. Override it with the adapter in '
    'lib/app/simulation/, or with a fake from test/helpers/simulation_bindings.dart.',
  ),
);
