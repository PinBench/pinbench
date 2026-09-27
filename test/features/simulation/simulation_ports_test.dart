import 'dart:async';

import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/simulation/ports/simulation_canvas.dart';
import 'package:pinbench/features/simulation/ports/simulation_diagnostics.dart';
import 'package:pinbench/features/simulation/ports/simulation_sketch.dart';
import 'package:pinbench/features/simulation/providers/simulation_provider.dart';

import '../../support/simulation_bindings.dart';

/// The three ports the simulation reaches the rest of the app through.
///
/// These were direct imports of `CanvasController` and four workspace
/// providers until the ports existed, which is why the behaviour below had no
/// tests: reaching `running` needs a real compile, and everything short of
/// that needed a real canvas and a real workspace. With ports it needs
/// neither, so the two invariants that have actually regressed before are
/// finally pinned:
///
///  - a circuit edit must not rebuild the notifier (two run loops), and
///  - opening a different workspace must stop the run (a dead sketch driving
///    the newly-loaded circuit).
///
/// Nothing here reaches the emulator: every run either hangs in the compiler
/// or fails in it, so no isolate is ever spawned.
void main() {
  // `configure` runs before the notifier is built, which matters: the runner
  // captures the compiler once, at construction, so a test cannot swap it in
  // afterwards.
  ({ProviderContainer container, FakeSimulationCanvas canvas, FakeSimulationSketch sketch}) build({
    void Function(FakeSimulationSketch sketch)? configure,
  }) {
    final canvas = FakeSimulationCanvas();
    final sketch = FakeSimulationSketch();
    configure?.call(sketch);
    final container = ProviderContainer(
      overrides: [
        simulationCanvasProvider.overrideWithValue(canvas),
        simulationSketchProvider.overrideWithValue(sketch),
        simulationDiagnosticsProvider.overrideWithValue(FakeSimulationDiagnostics()),
      ],
    );
    addTearDown(container.dispose);

    // `Simulation` is auto-dispose, and in the app it is the shell's watchers
    // that keep a stopped run alive between builds. Without an equivalent here
    // the notifier is thrown away the moment a test awaits anything, and the
    // next `read` silently hands back a fresh one in `stopped`.
    container.listen(simulationProvider, (_, _) {}, fireImmediately: true);

    return (container: container, canvas: canvas, sketch: sketch);
  }

  test('a circuit edit reaches the run without rebuilding the notifier', () {
    // The bug this guards: if a canvas change rebuilt `Simulation`, a second
    // `SimulationRunner` would be constructed alongside the first and both
    // would tick the same circuit. See the single-run-loop invariant in
    // the module map.
    final harness = build();
    final notifier = harness.container.read(simulationProvider.notifier);

    harness.canvas.emitChange();
    harness.canvas.emitChange();

    expect(harness.container.read(simulationProvider.notifier), same(notifier));
    expect(harness.container.read(simulationProvider), SimulationState.stopped);
  });

  test('the canvas is subscribed to for as long as the simulation exists', () {
    final harness = build();
    harness.container.read(simulationProvider.notifier);
    expect(harness.canvas.isObserved, isTrue);

    harness.container.dispose();
    expect(harness.canvas.isObserved, isFalse, reason: 'the listener outlived the simulation');
  });

  test('opening a different workspace stops the run and unlocks the circuit', () async {
    // A run started against one project must not keep ticking onto the next
    // one's circuit. `Simulation` is kept alive by shell-level watchers, so
    // nothing disposes it when the user goes back to the welcome screen.
    // Park the run in `compiling` with a compile that never returns: enough to
    // be stoppable, without reaching the emulator.
    final harness = build(
      configure: (sketch) =>
          sketch.compiler = ({workspacePath, required code}) => Completer<String>().future,
    );

    unawaited(harness.container.read(simulationProvider.notifier).toggle());
    await pumpEventQueue();

    expect(harness.container.read(simulationProvider), SimulationState.compiling);
    expect(harness.canvas.isReadOnly, isTrue, reason: 'a run should lock the circuit');

    harness.sketch.emitWorkspaceChange();

    expect(harness.container.read(simulationProvider), SimulationState.stopped);
    expect(harness.canvas.isReadOnly, isFalse, reason: 'the lock outlived the run');
  });

  test('a failed compile leaves the circuit editable', () async {
    // The lock is taken before compiling, so every path out of a failed build
    // has to give it back — otherwise the canvas is stuck read-only with
    // nothing running and no obvious way out.
    final harness = build();

    await harness.container.read(simulationProvider.notifier).toggle();

    expect(harness.container.read(simulationProvider), SimulationState.stopped);
    expect(harness.canvas.isReadOnly, isFalse);
  });

  test('open files are saved before the source is read', () async {
    // Running stale code is the symptom; the cause is reading the buffer
    // before flushing it, which only shows up when the host compiles the
    // sketch *directory* rather than the buffer it was handed.
    String? compiledSource;
    final harness = build(
      configure: (sketch) {
        sketch.source = 'stale';
        // Standing in for the editor buffer reaching disk.
        sketch.onSave = () => sketch.source = 'void setup() {}';
        sketch.compiler = ({workspacePath, required code}) async {
          compiledSource = code;
          throw const FormatException('stop here');
        };
      },
    );

    await harness.container.read(simulationProvider.notifier).toggle();

    expect(harness.sketch.saveCount, 1);
    expect(compiledSource, 'void setup() {}');
  });
}
