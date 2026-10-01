import 'package:pinbench_parts/models/component_instance.dart';

import '../board/board_emulator.dart';
import '../spice_engine.dart';

/// Feeds solved circuit voltages at the board's analog pins (the Uno's A0–A5,
/// the Pico's GP26–28) into the ADC so `analogRead()` reflects external
/// voltages (dividers, sensors, pots). Skips channel 0 when a mic sensor owns
/// it. Must run after
/// `SpiceEngine.solve()`. Extracted from
/// `SimulationEngine._updateAnalogInputs`.
abstract final class AnalogIoFrameUpdater {
  static void update({
    required BoardEmulator board,
    required ComponentInstance? boardNode,
    required bool micOwnsA0,
    required SpiceEngine spiceEngine,
    required Map<int, double> lastAnalog,
    void Function(String)? onDebugLog,
  }) {
    final node = boardNode;
    if (node == null) return;

    final ports = board.profile.analogInputPorts;
    for (var ch = 0; ch < ports.length; ch++) {
      if (ch == 0 && micOwnsA0) continue;
      final port = ports[ch];
      if (!spiceEngine.isPortConnected(node.key, port)) continue;

      final volts = spiceEngine.getPortVoltage(node.key, port);
      board.setAnalogVoltage(ch, volts);

      final last = lastAnalog[ch];
      if (last == null || (last - volts).abs() > 0.05) {
        lastAnalog[ch] = volts;
        onDebugLog?.call('[Analog] A$ch = ${volts.toStringAsFixed(2)} V');
      }
    }
  }
}
