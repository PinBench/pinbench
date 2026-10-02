import 'dart:async';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';

import '../diagnostics/frame_profiler.dart';
import 'sim_io.dart';
import 'simulation_engine.dart';
import 'simulation_output.dart';
import 'simulation_runner_backend.dart';

/// Web only: the engine runs on the UI isolate and shares the live
/// [CanvasController]: topology is read straight from it and visual updates
/// are written straight back, with no serialisation across an isolate
/// boundary (unlike the native backend, which ships JSON across to a real
/// background isolate).

/// Web backend: `Isolate.spawn` is unavailable, so the engine runs inline on
/// the UI isolate against the live canvas. Audio/mic plugins may be
/// unsupported in the browser, so their setup is best-effort and never fails
/// the run. Extracted from `SimulationRunner`.
class SimulationRunnerBackendImpl({
  required final SimulationOutput circuit,
  required final ToneOutput tone,
  required final MicrophoneDevice microphone,
  required final void Function(String)? _onSerialPrint,
  required final void Function(String)? _onSpiceLog,
  required final void Function(String)? _onDebugLog,
  required final void Function(FrameStats stats)? _onFrameStats,
  required final void Function(Map<String, double> currents)? _onWireCurrents,
  required final void Function(List<String> warnings)? _onCircuitWarnings,
  required final void Function() _onSelfStop,
}) implements SimulationRunnerBackend {
  SimulationEngine? _engine;
  final _mic = MutableMicInput();
  var _selfStopped = false;

  @override
  Future<void> warmUp() async {
    // Nothing to spawn: the engine runs inline on the UI isolate.
  }

  @override
  Future<void> start(
    String compiledHex, {
    required List<ComponentInstance> nodes,
    required List<WireModel> wires,
    required void Function() startMicStream,
  }) async {
    _selfStopped = false;

    // Only spin up the audio/mic plugins when the circuit actually uses them
    // (they may be unsupported in the browser), so a plain LED sketch never
    // trips a plugin error. Not awaited: opening a device is slow enough to
    // be visible as a stall on the Run click, and the run does not need
    // either to be ready — see the native backend for the full reasoning.
    if (nodes.any((n) => n.part.name == PartNames.piezoBuzzer)) {
      unawaited(
        tone.init().catchError((Object _) {
          _onDebugLog?.call('[Audio] Buzzer plugin init failed (non-fatal).');
        }),
      );
    }
    if (nodes.any((n) => n.part.name == PartNames.ky037MicSensor)) {
      unawaited(
        microphone.init().then((_) => startMicStream()).catchError((Object _) {
          _onDebugLog?.call('[Audio] Mic plugin init failed (non-fatal).');
        }),
      );
    }

    final engine = _engine ??= SimulationEngine(
      output: circuit,
      onSerialPrint: _onSerialPrint,
      onSpiceLog: _onSpiceLog,
      onDebugLog: _onDebugLog,
      onBuzzerFrequency: (hz) {
        try {
          if (hz != null) {
            tone.playTone(hz);
          } else {
            tone.stopTone();
          }
        } catch (_) {}
      },
      onWireCurrents: (currents) => _onWireCurrents?.call(currents),
      onCircuitWarnings: (warnings) => _onCircuitWarnings?.call(warnings),
      onFrameStats: (stats) => _onFrameStats?.call(stats),
      micInput: _mic,
    );
    await engine.start(
      compiledHex,
      onStop: () {
        if (!_selfStopped) {
          _selfStopped = true;
          _onSelfStop();
        }
      },
    );
  }

  @override
  void stop() => _engine?.stop();

  @override
  void pause() => _engine?.pause();

  @override
  void resume() => _engine?.resume();

  @override
  void sendSerialInput(String text) => _engine?.sendSerialInput(text);

  @override
  void rebuildCircuit({required List<ComponentInstance> nodes, required List<WireModel> wires}) {
    // The inline engine reads the live canvas, so it picks up topology/value
    // changes on the next frame after a rebuild — nodes/wires are unused
    // here (only the native backend needs them serialized across).
    _engine?.rebuildCircuit();
  }

  @override
  void forwardButtonStates(Map<String, bool> states) {
    // The inline web engine reads button state straight from the live
    // canvas each frame, so there is nothing to forward.
  }

  @override
  void sendPartEvent(String nodeId, String event) => _engine?.handlePartEvent(nodeId, event);

  @override
  void forwardPropertyEdits(Map<String, Map<String, dynamic>> byNode) =>
      _engine?.applyPropertyEdits(byNode);

  @override
  void feedMicReading(double analogVoltage, {required bool isHigh}) =>
      _mic.set(analogVoltage, isHigh: isHigh);

  @override
  void dispose() {
    _engine = null;
  }
}
