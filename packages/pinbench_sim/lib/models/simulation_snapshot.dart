/// A point-in-time capture of simulation state for debugging and inspection.
///
/// Created by SimulationEngine.captureSnapshot while the simulation is running.
/// All values reflect the state at the moment of capture.
class SimulationSnapshot {
  /// Arduino digital pin states (pin 0–13 → high/low).
  final Map<int, bool> pinStates;

  /// SPICE forward current through each LED, keyed by node key string.
  final Map<String, double> ledCurrents;

  /// Total CPU cycles executed since simulation start.
  final int cpuCycles;

  const SimulationSnapshot({
    required this.pinStates,
    required this.ledCurrents,
    required this.cpuCycles,
  });
}
