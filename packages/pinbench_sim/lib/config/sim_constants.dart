import 'avr_config.dart';

/// Physical / rendering constants for the realtime simulation loop.
///
/// Centralizes the magic numbers that were previously scattered through
/// `simulation_engine.dart` so thresholds and logic levels have a single,
/// named source of truth.
abstract class SimConstants {
  // The LED "lit" threshold used to live here; it moved into
  // `package:pinbench_parts/logic/built_in_part_logic.dart` with the rule that is
  // its only reader.

  /// Voltage (volts) representing a digital logic-high level.
  static const logicHighVolts = 5.0;

  /// Voltage (volts) representing a digital logic-low level.
  static const logicLowVolts = 0.0;

  /// Highest addressable digital pin (Arduino Uno has pins 0–13).
  static const maxDigitalPin = AVRConfig.digitalPinCount - 1; // 13

  /// Below this (amps), a change in wire current is not worth reporting.
  ///
  /// Sits a decade under the smallest current the canvas draws at all, so it
  /// only filters solver noise — never a wire going from dead to alive.
  static const wireCurrentEpsilon = 1e-7;
}
