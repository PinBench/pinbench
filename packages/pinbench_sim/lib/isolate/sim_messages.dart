import 'dart:isolate';

/// Messages exchanged between the UI isolate and the simulation isolate.
///
/// Every payload is built from sendable types only (primitives, `String`,
/// `List`, `Map`, and `SendPort`) so instances copy cleanly across a
/// [SendPort]. Crucially, circuit nodes/wires travel as **JSON maps**, never as
/// `ComponentInstance`/`WireModel` objects — those carry a painter *closure*
/// (`PartModel.painterBuilder`), which is not sendable. The isolate
/// rehydrates them with `fromJson` (the painter is rebuilt from the component
/// registry on the far side).

/// A command sent from the UI isolate to the simulation isolate.
sealed class SimCommand {}

/// Start a run: the compiled HEX plus the circuit as JSON.
class StartSim extends SimCommand {
  StartSim({required this.hex, required this.nodesJson, required this.wiresJson});
  final String hex;
  final List<Map<String, dynamic>> nodesJson;
  final List<Map<String, dynamic>> wiresJson;
}

class StopSim extends SimCommand {}

class PauseSim extends SimCommand {}

class ResumeSim extends SimCommand {}

/// Text typed into the Serial Monitor, delivered to the sketch's RX.
class SerialInput extends SimCommand {
  SerialInput(this.text);
  final String text;
}

/// A microphone reading streamed from the UI isolate (~60 Hz while a mic
/// sensor is present), injected into the ADC/SPICE model.
class MicReading extends SimCommand {
  MicReading(this.volts, {required this.isHigh});
  final double volts;
  final bool isHigh;
}

/// Current pressed-state of every push button, keyed by node-key string.
class ButtonStates extends SimCommand {
  ButtonStates(this.states);
  final Map<String, bool> states;
}

/// Rebuild the netlist + SPICE model from a fresh circuit snapshot (e.g. after
/// a potentiometer is turned), without recompiling the sketch.
class RebuildCircuit extends SimCommand {
  RebuildCircuit({required this.nodesJson, required this.wiresJson});
  final List<Map<String, dynamic>> nodesJson;
  final List<Map<String, dynamic>> wiresJson;
}

/// An event sent from the simulation isolate back to the UI isolate.
sealed class SimEvent {}

/// First message after spawn: the port the UI isolate sends [SimCommand]s to.
class IsolateReady extends SimEvent {
  IsolateReady(this.commandPort);
  final SendPort commandPort;
}

/// A batch of per-node visual property changes, keyed by node-key string.
class FrameUpdates extends SimEvent {
  FrameUpdates(this.updates);
  final Map<String, Map<String, dynamic>> updates;
}

/// Solved current (amps) in each drawn wire, keyed by wire id and signed so a
/// positive value runs from the wire's `start` port to its `end`.
///
/// Wire ids are plain strings that survive the trip verbatim, so unlike
/// [FrameUpdates] these need no re-mapping on the far side.
class WireCurrents extends SimEvent {
  WireCurrents(this.currents);
  final Map<String, double> currents;
}

class SerialPrint extends SimEvent {
  SerialPrint(this.text);
  final String text;
}

class SpiceLog extends SimEvent {
  SpiceLog(this.text);
  final String text;
}

class DebugLog extends SimEvent {
  DebugLog(this.text);
  final String text;
}

/// The detected buzzer tone changed (Hz, or null when it stopped). The UI
/// isolate turns this into real audio.
class BuzzerFreq extends SimEvent {
  BuzzerFreq(this.hz);
  final double? hz;
}

/// The run loop has fully stopped.
class SimStopped extends SimEvent {}

/// Rolling frame statistics from the profiler (~2s window at 60 fps). Sent
/// periodically while the simulation is running so the UI can gauge performance
/// in Grafana / Crashlytics keys.
class FrameStatsEvent extends SimEvent {
  FrameStatsEvent({
    required this.avgFps,
    required this.avgTotalMs,
    required this.avgAvrMs,
    required this.avgSpiceMs,
    required this.droppedFrames,
  });

  final double avgFps;
  final double avgTotalMs;
  final double avgAvrMs;
  final double avgSpiceMs;
  final int droppedFrames;
}

class SimError extends SimEvent {
  SimError(this.message);
  final String message;
}
