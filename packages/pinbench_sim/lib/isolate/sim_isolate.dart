import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';

import '../core/sim_io.dart';
import '../core/simulation_engine.dart';
import '../core/simulation_output.dart';
import 'sim_messages.dart';

/// Entry point for the simulation isolate.
///
/// Owns the only runtime [SimulationEngine] — and therefore the ngspice FFI
/// singleton and the avr8 emulator — for the life of the app. It receives
/// [SimCommand]s and streams [SimEvent]s (frame updates, logs, buzzer tones)
/// back to the UI isolate, which keeps the canvas and the audio/mic plugins.
void simIsolateMain(SendPort toMain) {
  final commands = ReceivePort();
  // Hand the UI isolate the port it should send commands to.
  toMain.send(IsolateReady(commands.sendPort));
  final worker = _SimWorker(toMain);

  // Process commands strictly one-at-a-time. handle() is async (start() awaits
  // the previous loop's teardown), and ReceivePort.listen would otherwise let a
  // later command re-enter mid-await — e.g. a StartSim overlapping a prior
  // start, racing the shared AVR/ngspice setup. Chaining serialises them.
  var queue = Future<void>.value();
  commands.listen((message) {
    queue = queue.then((_) => worker.handle(message));
  });
}

/// [SimulationOutput] that forwards visual updates to the UI isolate as
/// [FrameUpdates], and serves circuit topology from a locally-held list that is
/// rehydrated on [StartSim]/[RebuildCircuit] and mutated on [ButtonStates].
class _IsolateOutput implements SimulationOutput {
  _IsolateOutput(this._sendEvent);
  final void Function(SimEvent) _sendEvent;

  List<ComponentInstance> nodes = [];
  List<WireModel> wires = [];

  @override
  List<ComponentInstance> get simulationNodes => nodes;

  @override
  List<WireModel> get simulationWires => wires;

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    if (updates.isEmpty) return;
    final out = <String, Map<String, dynamic>>{};
    for (final entry in updates.entries) {
      out[(entry.key as ValueKey<String>).value] = entry.value;
    }
    _sendEvent(FrameUpdates(out));
  }
}

class _SimWorker {
  _SimWorker(this._toMain) {
    _output = _IsolateOutput(_send);
    _engine = SimulationEngine(
      output: _output,
      onSerialPrint: (t) => _send(SerialPrint(t)),
      onSpiceLog: (t) => _send(SpiceLog(t)),
      onDebugLog: (t) => _send(DebugLog(t)),
      onBuzzerFrequency: (hz) => _send(BuzzerFreq(hz)),
      onWireCurrents: (c) => _send(WireCurrents(c)),
      onFrameStats: (s) => _send(
        FrameStatsEvent(
          avgFps: s.avgFps,
          avgTotalMs: s.avgTotalMs,
          avgAvrMs: s.avgAvrMs,
          avgSpiceMs: s.avgSpiceMs,
          droppedFrames: s.droppedFrames,
        ),
      ),
      micInput: _mic,
    );
  }

  final SendPort _toMain;
  final _mic = MutableMicInput();
  late final _IsolateOutput _output;
  late final SimulationEngine _engine;

  void _send(SimEvent e) => _toMain.send(e);

  Future<void> handle(Object? message) async {
    if (message is! SimCommand) return;
    try {
      switch (message) {
        case final StartSim s:
          _output.nodes = s.nodesJson.map(ComponentInstance.fromJson).toList();
          _output.wires = s.wiresJson.map(WireModel.fromJson).toList();
          await _engine.start(s.hex, onStop: () => _send(SimStopped()));
        case StopSim _:
          _engine.stop();
        case PauseSim _:
          _engine.pause();
        case ResumeSim _:
          _engine.resume();
        case final SerialInput si:
          _engine.sendSerialInput(si.text);
        case final MicReading m:
          _mic.set(m.volts, isHigh: m.isHigh);
        case final ButtonStates b:
          _applyButtonStates(b.states);
        case final RebuildCircuit r:
          _output.nodes = r.nodesJson.map(ComponentInstance.fromJson).toList();
          _output.wires = r.wiresJson.map(WireModel.fromJson).toList();
          _engine.rebuildCircuit();
      }
    } catch (e, st) {
      _send(SimError('$e\n$st'));
    }
  }

  /// Mirrors UI-side button presses onto the local node snapshot so the engine's
  /// [SimulationEngine] dynamic-netlist update sees them next frame.
  void _applyButtonStates(Map<String, bool> states) {
    for (final node in _output.nodes) {
      if (node.part.name != PartNames.pushButton) continue;
      final id = (node.key as ValueKey<String>).value;
      final pressed = states[id];
      if (pressed != null) {
        node.properties[ComponentProps.isPressed] = pressed;
      }
    }
  }
}
