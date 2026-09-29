/// A point-in-time capture of simulation state for debugging and inspection.
///
/// Created by SimulationEngine.captureSnapshot while the simulation is running.
/// All values reflect the state at the moment of capture.
class const SimulationSnapshot({
  /// Arduino digital pin states (pin 0–13 → high/low).
  required final Map<int, bool> pinStates,

  /// SPICE forward current through each LED, keyed by node key string.
  required final Map<String, double> ledCurrents,

  /// Total CPU cycles executed since simulation start.
  required final int cpuCycles,
});
