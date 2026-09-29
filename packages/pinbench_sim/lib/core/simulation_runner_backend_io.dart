import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import 'sim_io.dart';
import 'simulation_output.dart';
import '../diagnostics/frame_profiler.dart';
import '../isolate/sim_isolate.dart';
import '../isolate/sim_messages.dart';
import 'simulation_runner_backend.dart';

/// Native backend: spawns a dedicated long-lived background isolate running
/// the AVR+SPICE engine, ships the compiled sketch and circuit over, and
/// routes events back. Extracted from `SimulationRunner`.
class SimulationRunnerBackendImpl({
  required final SimulationOutput circuit,
  required final ToneOutput tone,
  required final MicrophoneDevice microphone,
  required final void Function(String)? _onSerialPrint,
  required final void Function(String)? _onSpiceLog,
  required final void Function(String)? _onDebugLog,
  required final void Function(FrameStats stats)? _onFrameStats,
  required final void Function(Map<String, double> currents)? _onWireCurrents,
  required final void Function() _onSelfStop,
}) implements SimulationRunnerBackend {
  Isolate? _isolate;
  SendPort? _toSim;
  ReceivePort? _fromSim;
  Completer<void>? _ready;

  // Maps the serialised node id (see [nodeKeyToId]) back to the live canvas
  // node key, so frame updates from the isolate apply to the real nodes —
  // whose keys may be UniqueKey (parser-loaded) rather than ValueKey<String>.
  final Map<String, LocalKey> _keyById = {};

  // Guards against SimStopped firing onSelfStop more than once per run (a
  // user-initiated stop() already cleared the flag on SimulationRunner's
  // side, so a subsequent SimStopped from the isolate must stay silent).
  var _selfStopped = false;

  Future<void> _ensureSpawned() async {
    if (_toSim != null) return;
    if (_ready != null) return _ready!.future;

    final ready = _ready = Completer<void>();
    final fromSim = _fromSim = ReceivePort();
    fromSim.listen(_handleEvent);
    _isolate = await Isolate.spawn(simIsolateMain, fromSim.sendPort);
    return ready.future;
  }

  void _handleEvent(Object? message) {
    if (message is! SimEvent) return;
    switch (message) {
      case final IsolateReady r:
        _toSim = r.commandPort;
        _ready?.complete();
      case final FrameUpdates f:
        if (f.updates.isEmpty) return;
        final updates = <LocalKey, Map<String, dynamic>>{};
        for (final e in f.updates.entries) {
          final key = _keyById[e.key];
          if (key != null) updates[key] = e.value;
        }
        if (updates.isNotEmpty) circuit.applyNodeUpdates(updates);
      case final WireCurrents w:
        _onWireCurrents?.call(w.currents);
      case final SerialPrint p:
        _onSerialPrint?.call(p.text);
      case final SpiceLog l:
        _onSpiceLog?.call(l.text);
      case final DebugLog l:
        _onDebugLog?.call(l.text);
      case final BuzzerFreq b:
        if (b.hz != null) {
          tone.playTone(b.hz!);
        } else {
          tone.stopTone();
        }
      case final FrameStatsEvent s:
        _onFrameStats?.call(
          FrameStats(
            avgFps: s.avgFps,
            avgTotalMs: s.avgTotalMs,
            avgAvrMs: s.avgAvrMs,
            avgSpiceMs: s.avgSpiceMs,
            droppedFrames: s.droppedFrames,
            sampleCount: 60,
          ),
        );
      case SimStopped _:
        // Self-stop (sketch finished / crashed): a user-initiated stop()
        // already cleared SimulationRunner's flag, so this only fires
        // onSelfStop the first time it's seen for this run.
        if (!_selfStopped) {
          _selfStopped = true;
          _onSelfStop();
        }
      case final SimError e:
        _onSerialPrint?.call(e.message);
        _onSpiceLog?.call(e.message);
    }
  }

  void _send(SimCommand cmd) => _toSim?.send(cmd);

  /// Refreshes the id→key index from the current node snapshot. Must run
  /// before shipping a circuit so incoming frame updates can be mapped back.
  void _rebuildKeyIndex(List<ComponentInstance> nodes) {
    _keyById
      ..clear()
      ..addEntries([for (final n in nodes) MapEntry(nodeKeyToId(n.key), n.key)]);
  }

  @override
  Future<void> warmUp() => _ensureSpawned();

  @override
  Future<void> start(
    String compiledHex, {
    required List<ComponentInstance> nodes,
    required List<WireModel> wires,
    required void Function() startMicStream,
  }) async {
    _selfStopped = false;
    await _ensureSpawned();

    // Bring up the UI-isolate audio/mic plugins for this run — but never on
    // the way in. Both open a real host device through platform channels /
    // FFI on the UI isolate, which stalls the frame that is drawing the Run
    // spinner; neither is needed for the first millisecond of the run, and
    // both no-op safely until they are ready (`playTone` checks `isReady`,
    // the mic reads as silence). So they are kicked off and left to finish
    // alongside the sim rather than awaited before it.
    //
    // Only for circuits that actually use them, mirroring the web backend: a
    // plain LED sketch has no reason to open an audio device at all.
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

    _rebuildKeyIndex(nodes);
    _send(
      StartSim(
        hex: compiledHex,
        nodesJson: [for (final n in nodes) n.toJson()],
        wiresJson: [for (final w in wires) w.toJson()],
      ),
    );
  }

  @override
  void stop() => _send(StopSim());

  @override
  void pause() => _send(PauseSim());

  @override
  void resume() => _send(ResumeSim());

  @override
  void sendSerialInput(String text) => _send(SerialInput(text));

  @override
  void rebuildCircuit({required List<ComponentInstance> nodes, required List<WireModel> wires}) {
    _rebuildKeyIndex(nodes);
    _send(
      RebuildCircuit(
        nodesJson: [for (final n in nodes) n.toJson()],
        wiresJson: [for (final w in wires) w.toJson()],
      ),
    );
  }

  @override
  void forwardButtonStates(Map<String, bool> states) {
    if (states.isNotEmpty) _send(ButtonStates(states));
  }

  @override
  void feedMicReading(double analogVoltage, {required bool isHigh}) =>
      _send(MicReading(analogVoltage, isHigh: isHigh));

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromSim?.close();
    _fromSim = null;
    _toSim = null;
    _ready = null;
  }
}
