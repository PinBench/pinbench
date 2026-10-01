import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/part_registry.dart';

import 'sim_io.dart';
import 'simulation_output.dart';
import 'sketch_compiler.dart';
import '../diagnostics/frame_profiler.dart';
import 'simulation_runner_backend.dart';

import 'simulation_runner_backend_io.dart'
    if (dart.library.js_interop) 'simulation_runner_backend_web.dart';

/// Bridges the UI isolate to the platform-specific simulation backend (see
/// `SimulationRunnerBackend`): native spawns a background isolate running the
/// AVR + SPICE loop; the web runs it inline on the UI isolate. This class
/// owns everything platform-agnostic — compilation, the isSimulating/isPaused
/// guards, the mic-timer's periodic bookkeeping, and the self-stop teardown
/// sequence — so the owning `SimulationNotifier` needs no rework.
class SimulationRunner({
  /// The circuit to run and where results go. A port, not the canvas itself —
  /// see `CanvasSimulationOutput` for the binding.
  required final SimulationOutput circuit,

  /// How a sketch becomes runnable bytes. Injected rather than called
  /// statically so the engine carries no opinion about arduino-cli, remote
  /// build services, or precompiled template hex.
  required final SketchCompiler compiler,

  /// The host's speaker and microphone. Ports, because both are host devices
  /// the emulator should not have to carry a plugin for.
  required final ToneOutput tone,
  required final MicrophoneDevice microphone,
  final void Function(String)? onSerialPrint,
  final void Function(String)? onSpiceLog,
  final void Function(String)? onDebugLog,

  /// Reports a compilation error (the message), or `null` when compilation
  /// succeeded — used to surface build failures in the Problems pane.
  final void Function(String?)? onCompileError,

  /// Periodic frame-stats callback (~1 Hz). Fired with rolling averages so the
  /// owning provider can push them to the tracing/metrics service.
  final void Function(FrameStats stats)? onFrameStats,

  /// Solved current (amps) per wire id, signed `start → end`, fired whenever it
  /// changes visibly. This is what the canvas animates flow from.
  final void Function(Map<String, double> currents)? onWireCurrents,
}) {
  /// Kept for API compatibility. Per-frame samples now live in the sim isolate,
  /// so this stays empty unless profiling is re-plumbed across the boundary.
  final profiler = FrameProfiler();

  this {
    _backend = SimulationRunnerBackendImpl(
      circuit: circuit,
      tone: tone,
      microphone: microphone,
      onSerialPrint: onSerialPrint,
      onSpiceLog: onSpiceLog,
      onDebugLog: onDebugLog,
      onFrameStats: onFrameStats,
      onWireCurrents: onWireCurrents,
      onSelfStop: _handleSelfStop,
    );
  }

  late final SimulationRunnerBackend _backend;

  var _isSimulating = false;
  var _isPaused = false;
  Timer? _micTimer;
  void Function()? _onStop;

  bool get isSimulating => _isSimulating;
  bool get isPaused => _isPaused;

  /// Prepares the backend ahead of the first run (native: spawns the engine
  /// isolate). Fire-and-forget — a run that beats it simply waits for the
  /// same in-flight spawn.
  Future<void> warmUp() => _backend.warmUp();

  /// The board on the canvas, which the sketch is built for — or an Uno, as
  /// a canvas with no board always ran.
  BoardProfile get _board {
    for (final node in circuit.simulationNodes) {
      if (BoardProfile.of(node.part) case final board?) return board;
    }
    return BoardProfile.arduinoUno;
  }

  Future<bool> start(
    String code, {
    String? workspacePath,
    String? precompiledHex,
    required void Function() onStop,
  }) async {
    if (_isSimulating) return false;

    String compiledHex;
    if (precompiledHex != null && precompiledHex.trim().isNotEmpty) {
      // The user supplied a prebuilt .hex — run it as-is, no compile needed.
      onSerialPrint?.call('Loading precompiled .hex...');
      onDebugLog?.call('[Build] Using precompiled .hex (compilation skipped).');
      compiledHex = precompiledHex;
    } else {
      onSerialPrint?.call('Compiling sketch for the ${_board.partName} with arduino-cli...');
      onDebugLog?.call('[Build] Compiling sketch...');
      try {
        compiledHex = await compiler(workspacePath: workspacePath, code: code, board: _board);
      } catch (e) {
        onSerialPrint?.call('Compilation Failed:\n$e\n');
        onDebugLog?.call('[Build] Compilation failed.');
        onCompileError?.call('$e');
        return false;
      }
    }

    onCompileError?.call(null);
    onDebugLog?.call('[Build] Ready.');

    _onStop = onStop;
    _isSimulating = true;
    _isPaused = false;
    _sentProperties
      ..clear()
      ..addAll({
        for (final node in circuit.simulationNodes) nodeKeyToId(node.key): userProperties(node),
      });
    _pressedRegions.clear();

    await _backend.start(
      compiledHex,
      nodes: circuit.simulationNodes,
      wires: circuit.simulationWires,
      startMicStream: _startMicStream,
    );
    return true;
  }

  /// Called by the backend when the simulation stops itself (sketch
  /// finished/crashed) rather than via a user-initiated [stop]. A
  /// user-initiated stop already cleared [_isSimulating], so this is a no-op
  /// in that case — it can't tear down a run that already ended.
  void _handleSelfStop() {
    if (_isSimulating) {
      _isSimulating = false;
      _isPaused = false;
      _cleanupLocal();
      _onStop?.call();
    }
  }

  void stop() {
    if (!_isSimulating) return;
    _isSimulating = false;
    _isPaused = false;
    _cleanupLocal();
    _backend.stop();
  }

  void pause() {
    if (!_isSimulating) return;
    _isPaused = true;
    _backend.pause();
  }

  void resume() {
    if (!_isSimulating) return;
    _isPaused = false;
    _backend.resume();
  }

  /// Sends text to the running sketch's serial receiver.
  void sendSerialInput(String text) => _backend.sendSerialInput(text);

  /// Rebuilds the netlist + SPICE model in the isolate from the current canvas
  /// (e.g. after a potentiometer turn) without recompiling the sketch.
  void rebuildCircuit() {
    if (!_isSimulating) return;
    final nodes = circuit.simulationNodes;
    final hasMic = nodes.any((n) => n.part.name == PartNames.ky037MicSensor);
    if (hasMic && _micTimer == null) {
      // A mic was added mid-run — bring up the plugin + stream (best-effort on
      // the web, where the plugin may be unsupported).
      unawaited(microphone.init().then((_) => _startMicStream()).catchError((Object _) {}));
    }
    _backend.rebuildCircuit(nodes: nodes, wires: circuit.simulationWires);
  }

  /// Forwards push-button presses to the isolate. Called when the canvas
  /// changes while a run is active (buttons are the only mid-run topology edit
  /// besides the pot, which goes through [rebuildCircuit]).
  void onCanvasChanged() {
    if (!_isSimulating) return;
    final states = <String, bool>{};
    final edits = <String, Map<String, dynamic>>{};
    for (final node in circuit.simulationNodes) {
      _forwardRegionPress(node);
      final id = nodeKeyToId(node.key);
      final properties = userProperties(node);
      if (!mapEquals(properties, _sentProperties[id])) {
        _sentProperties[id] = properties;
        edits[id] = properties;
      }
      if (node.part.name != PartNames.pushButton) continue;
      states[nodeKeyToId(node.key)] =
          node.properties[ComponentProps.isPressed] == true ||
          node.properties[ComponentProps.isPressed] == 'true';
    }
    _backend.forwardButtonStates(states);
    if (edits.isNotEmpty) _backend.forwardPropertyEdits(edits);
  }

  /// What the running engine was last told each part's own properties are.
  final Map<String, Map<String, dynamic>> _sentProperties = {};

  /// The properties of [node] a user sets — not what the simulation writes
  /// back onto the canvas, which must not echo round to it as an edit: a
  /// `.pdl` part's declared PROPERTIES, or a built-in part's every key but
  /// its runtime flags.
  @visibleForTesting
  static Map<String, dynamic> userProperties(ComponentInstance node) {
    final definitionId = node.part.definitionId;
    final declared = definitionId == null
        ? null
        : PartRegistry.getPart(definitionId)?.properties.keys.toSet();
    return {
      for (final MapEntry(:key, :value) in node.properties.entries)
        if (declared != null ? declared.contains(key) : !ComponentProps.runtimeFlags.contains(key))
          key: value,
    };
  }

  /// The region each part last had held down, so a press is sent once, when
  /// it starts, rather than on every canvas change while it is held.
  final Map<String, String?> _pressedRegions = {};

  /// Sends a newly pressed region of [node] — a remote's button — to the
  /// engine as a part event.
  void _forwardRegionPress(ComponentInstance node) {
    final id = nodeKeyToId(node.key);
    final region = node.properties[ComponentProps.pressedRegion] as String?;
    final previous = _pressedRegions[id];
    if (region == previous) return;
    _pressedRegions[id] = region;
    if (region != null) _backend.sendPartEvent(id, region);
  }

  /// Tears down the backend entirely; call when the owning provider disposes.
  void dispose() {
    stop();
    tone.dispose();
    _backend.dispose();
  }

  // --- Internals -------------------------------------------------------------

  void _startMicStream() {
    _micTimer?.cancel();
    _micTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _backend.feedMicReading(microphone.analogVoltage, isHigh: microphone.isDigitalHigh);
    });
  }

  void _cleanupLocal() {
    _micTimer?.cancel();
    _micTimer = null;
    // Silence the buzzer, but keep the audio engine itself alive for the
    // session: tearing it down here means the *next* run has to open the
    // host's audio device again, and that open is slow enough on the UI
    // isolate to show up as a freeze on the Run click. It is disposed for
    // real in [dispose].
    tone.stopTone();
    unawaited(microphone.dispose());
  }
}
