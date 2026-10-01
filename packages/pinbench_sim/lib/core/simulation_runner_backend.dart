import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';

/// Platform-specific mechanics for running a compiled sketch: native spawns
/// a background isolate running the AVR+SPICE engine; the web runs the
/// engine inline on the UI isolate (no `Isolate.spawn` there). Selected at
/// compile time via the conditional-import trio
/// (`simulation_runner_backend_io.dart`/`_web.dart`).
///
/// `SimulationRunner` owns everything platform-agnostic (the
/// isSimulating/isPaused guards, the mic-timer's periodic bookkeeping, the
/// self-stop teardown sequence); a backend only implements how to actually
/// start/stop/pause/resume/rebuild the underlying engine and how to feed it
/// button/mic input.
abstract class SimulationRunnerBackend {
  /// Gets whatever the backend needs *before* a run as ready as it can be,
  /// off the click path. Native spawns its engine isolate here, so the first
  /// Run does not pay `Isolate.spawn` while the user watches a frozen
  /// spinner; the web has nothing to spawn and does nothing. Idempotent, and
  /// safe to call without ever starting a run.
  Future<void> warmUp();

  /// Starts the backend. [startMicStream] must be called by the
  /// implementation if/when it successfully brings up the mic plugin (each
  /// platform has different init-failure tolerance, so the decision of
  /// *whether* to start streaming stays with the backend; the periodic timer
  /// itself is owned by `SimulationRunner`).
  Future<void> start(
    String compiledHex, {
    required List<ComponentInstance> nodes,
    required List<WireModel> wires,
    required void Function() startMicStream,
  });

  void stop();
  void pause();
  void resume();
  void sendSerialInput(String text);
  void rebuildCircuit({required List<ComponentInstance> nodes, required List<WireModel> wires});

  /// Forwards push-button presses made mid-run. No-op on the web backend,
  /// which reads button state straight from the live canvas each frame.
  void forwardButtonStates(Map<String, bool> states);

  /// Delivers properties the user changed mid-run to the engine.
  void forwardPropertyEdits(Map<String, Map<String, dynamic>> byNode);

  /// Delivers a part's own event — a remote's button press — to the engine.
  void sendPartEvent(String nodeId, String event);

  /// Feeds one microphone reading into the running engine.
  void feedMicReading(double analogVoltage, {required bool isHigh});

  /// Tears down the backend entirely (called when the owning
  /// `SimulationRunner` is disposed).
  void dispose();
}
