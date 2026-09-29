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
sealed class SimCommand;

/// Start a run: the compiled HEX plus the circuit as JSON.
class StartSim({
  required final String hex,
  required final List<Map<String, dynamic>> nodesJson,
  required final List<Map<String, dynamic>> wiresJson,
}) extends SimCommand;

class StopSim extends SimCommand;

class PauseSim extends SimCommand;

class ResumeSim extends SimCommand;

/// Text typed into the Serial Monitor, delivered to the sketch's RX.
class SerialInput(final String text) extends SimCommand;

/// A microphone reading streamed from the UI isolate (~60 Hz while a mic
/// sensor is present), injected into the ADC/SPICE model.
class MicReading(final double volts, {required final bool isHigh}) extends SimCommand;

/// Current pressed-state of every push button, keyed by node-key string.
class ButtonStates(final Map<String, bool> states) extends SimCommand;

/// Rebuild the netlist + SPICE model from a fresh circuit snapshot (e.g. after
/// a potentiometer is turned), without recompiling the sketch.
class RebuildCircuit({
  required final List<Map<String, dynamic>> nodesJson,
  required final List<Map<String, dynamic>> wiresJson,
}) extends SimCommand;

/// An event sent from the simulation isolate back to the UI isolate.
sealed class SimEvent;

/// First message after spawn: the port the UI isolate sends [SimCommand]s to.
class IsolateReady(final SendPort commandPort) extends SimEvent;

/// A batch of per-node visual property changes, keyed by node-key string.
class FrameUpdates(final Map<String, Map<String, dynamic>> updates) extends SimEvent;

/// Solved current (amps) in each drawn wire, keyed by wire id and signed so a
/// positive value runs from the wire's `start` port to its `end`.
///
/// Wire ids are plain strings that survive the trip verbatim, so unlike
/// [FrameUpdates] these need no re-mapping on the far side.
class WireCurrents(final Map<String, double> currents) extends SimEvent;

class SerialPrint(final String text) extends SimEvent;

class SpiceLog(final String text) extends SimEvent;

class DebugLog(final String text) extends SimEvent;

/// The detected buzzer tone changed (Hz, or null when it stopped). The UI
/// isolate turns this into real audio.
class BuzzerFreq(final double? hz) extends SimEvent;

/// The run loop has fully stopped.
class SimStopped extends SimEvent;

/// Rolling frame statistics from the profiler (~2s window at 60 fps). Sent
/// periodically while the simulation is running so the UI can gauge performance
/// in Grafana / Crashlytics keys.
class FrameStatsEvent({
  required final double avgFps,
  required final double avgTotalMs,
  required final double avgAvrMs,
  required final double avgSpiceMs,
  required final int droppedFrames,
}) extends SimEvent;

class SimError(final String message) extends SimEvent;
