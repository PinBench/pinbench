import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_sim/core/simulation_runner.dart';
import 'package:pinbench_sim/models/simulation_state.dart';

import '../../../core/telemetry/telemetry_providers.dart';
import '../ports/simulation_canvas.dart';
import '../ports/simulation_diagnostics.dart';
import '../ports/simulation_sketch.dart';
import '../services/mic_sensor_service.dart';
import '../services/buzzer_service.dart';

part 'simulation_provider.g.dart';

/// Owns the run: what state it is in, and the transitions between them.
///
/// Everything outside the run itself arrives through the three ports in
/// `../ports/` — the circuit to drive, the sketch to run, and where output
/// goes. That is why this file names no other feature: which widget holds the
/// circuit, which provider holds the open files, and which pane shows the
/// serial output are all host decisions, bound in `lib/app/simulation/`.
@riverpod
class Simulation extends _$Simulation {
  late final SimulationRunner _runner;

  /// Latest solved current (amps) in each wire, keyed by wire id and signed so
  /// a positive value runs from the wire's `start` port to its `end`.
  ///
  /// Deliberately *not* part of [SimulationState]: this changes many times a
  /// second, and the run state is watched by the whole canvas subtree. As a
  /// listenable it reaches the one painter that wants it without rebuilding a
  /// single widget.
  final wireCurrents = ValueNotifier<Map<String, double>>(const {});

  @override
  SimulationState build() {
    final canvas = ref.watch(simulationCanvasProvider);
    final sketch = ref.watch(simulationSketchProvider);
    final diagnostics = ref.watch(simulationDiagnosticsProvider);

    _runner = SimulationRunner(
      compiler: sketch.compiler,
      circuit: canvas,
      tone: BuzzerService.instance,
      microphone: MicSensorService.instance,
      onSerialPrint: diagnostics.serial,
      onSpiceLog: diagnostics.spice,
      onDebugLog: diagnostics.debug,
      onCompileError: diagnostics.reportCompileError,
      onCircuitWarnings: diagnostics.reportCircuitWarnings,
      onWireCurrents: (currents) => wireCurrents.value = currents,
      onFrameStats: (stats) {
        final tracing = ref.read(tracingProvider);
        tracing.gauge('sim.fps', stats.avgFps);
        tracing.gauge('sim.frame_ms', stats.avgTotalMs);
        tracing.gauge('sim.avr_ms', stats.avgAvrMs);
        tracing.gauge('sim.spice_ms', stats.avgSpiceMs);
        tracing.gauge('sim.dropped_frames', stats.droppedFrames.toDouble());
      },
    );

    // Spawn the sim isolate now rather than on the first Run: `Isolate.spawn`
    // costs the UI isolate real time, and paying it from `toggle()` shows up
    // as the Run button freezing on its own spinner.
    unawaited(_runner.warmUp());

    // Forward mid-run circuit edits (push-button presses) to the sim isolate.
    void onCircuitChanged() => _runner.onCanvasChanged();
    canvas.changes.addListener(onCircuitChanged);

    // Stop and reset whenever a different workspace is opened — see
    // `SimulationSketch.workspaceChanges` for why this outlives the circuit.
    void onWorkspaceChanged() => stop(reason: 'workspace_change');
    sketch.workspaceChanges.addListener(onWorkspaceChanged);

    ref.onDispose(() {
      canvas.changes.removeListener(onCircuitChanged);
      sketch.workspaceChanges.removeListener(onWorkspaceChanged);
      _runner.dispose();
      wireCurrents.dispose();
    });

    return SimulationState.stopped;
  }

  /// Stops the simulation and returns to a clean stopped state, releasing the
  /// canvas read-only lock. Idempotent: a no-op when nothing is running, so it's
  /// safe to call on workspace switches regardless of current state.
  void stop({String reason = 'stop'}) {
    if (state == SimulationState.stopped) return;
    ref.read(analyticsProvider).simulationEnded(reason);
    _runner.stop();
    state = SimulationState.stopped;
    ref.read(simulationCanvasProvider).isReadOnly = false;
  }

  Future<void> toggle() async {
    if (state == SimulationState.running ||
        state == SimulationState.paused ||
        state == SimulationState.compiling) {
      ref.read(analyticsProvider)
        ..simulationToggled(started: false)
        ..simulationEnded('user_stop');
      _runner.stop();
      state = SimulationState.stopped;
      ref.read(simulationCanvasProvider).isReadOnly = false;
    } else {
      ref.read(analyticsProvider).simulationToggled(started: true);
      final sketch = ref.read(simulationSketchProvider);
      final diagnostics = ref.read(simulationDiagnosticsProvider);

      // Enter `compiling` before any of the work below, so the button shows
      // its spinner and the canvas locks on the click itself — the save that
      // follows regenerates the code from the canvas and writes the
      // workspace, which is long enough to read as a dead button.
      state = SimulationState.compiling;
      ref.read(simulationCanvasProvider).isReadOnly = true;

      // Auto-save all open files before running so nothing runs stale, then
      // read the source — in that order, since saving is what makes the two
      // agree when the host builds a directory rather than a buffer.
      await sketch.save();
      final code = sketch.source;

      // Start each run with a clean diagnostic surface.
      diagnostics.clearRunLogs();

      final tracing = ref.read(tracingProvider)..increment('simulation.run');
      // Trace the compile + launch as one span so its duration and outcome are
      // visible in OpenTelemetry (native platforms, incl. Windows/Linux), and
      // time it so the same outcome lands in Analytics as `compile_result`.
      final stopwatch = Stopwatch()..start();
      bool success;
      try {
        success = await tracing.trace(
          'simulation.start',
          () => _runner.start(
            code,
            workspacePath: sketch.workspacePath,
            precompiledHex: sketch.precompiledHex,
            onStop: () {
              // Triggered when the simulation stops itself (e.g. error or finish).
              ref.read(analyticsProvider).simulationEnded('self_stop');
              state = SimulationState.stopped;
              ref.read(simulationCanvasProvider).isReadOnly = false;
            },
          ),
          attributes: {'code.bytes': code.length},
        );
      } catch (e, st) {
        // An unexpected exception during compile/launch (not a normal "didn't
        // compile"): surface it as a non-fatal so it's visible in Crashlytics.
        ref.read(crashReporterProvider).recordError(e, st, fatal: false);
        success = false;
      }
      stopwatch.stop();

      ref
          .read(analyticsProvider)
          .compileResult(
            success: success,
            durationMs: stopwatch.elapsedMilliseconds,
            errorCount: diagnostics.problemCount,
            codeBytes: code.length,
            errorType: success ? null : diagnostics.compileErrorType,
          );

      if (success) {
        state = SimulationState.running;
        ref.read(milestonesProvider).fireOnce('first_simulation_success');
      } else {
        state = SimulationState.stopped;
        ref.read(simulationCanvasProvider).isReadOnly = false;
      }
    }
  }

  void togglePause() {
    if (state == SimulationState.running) {
      ref.read(analyticsProvider).simulationPaused(paused: true);
      _runner.pause();
      state = SimulationState.paused;
    } else if (state == SimulationState.paused) {
      ref.read(analyticsProvider).simulationPaused(paused: false);
      _runner.resume();
      state = SimulationState.running;
    }
  }

  /// Rebuilds circuit netlist + SPICE from the current canvas without
  /// recompiling the sketch. No-op when the simulation is not running.
  void rebuildCircuit() {
    ref.read(analyticsProvider).action('circuit_rebuild');
    _runner.rebuildCircuit();
  }

  /// Sends a line of input to the running sketch's serial receiver and echoes it
  /// to the Serial Monitor so the user sees what they sent. A trailing newline
  /// is appended (Arduino IDE "Newline" convention).
  void sendSerialInput(String text) {
    if (state != SimulationState.running) return;
    _runner.sendSerialInput('$text\n');
    ref.read(simulationDiagnosticsProvider).serial('→ $text');
  }
}
