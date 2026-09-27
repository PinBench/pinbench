import 'package:pinbench_parts/models/component_instance.dart';

import '../../config/avr_config.dart';
import '../avr_interop.dart';
import '../spice_engine.dart';

/// Feeds solved circuit voltages at the Arduino's analog pins (A0–A5) into
/// the ADC so `analogRead()` reflects external voltages (dividers, sensors,
/// pots). Skips A0 when a mic sensor owns that channel. Must run after
/// `SpiceEngine.solve()`. Extracted from
/// `SimulationEngine._updateAnalogInputs`.
abstract final class AnalogIoFrameUpdater {
  static void update({
    required ComponentInstance? unoNode,
    required bool micOwnsA0,
    required SpiceEngine spiceEngine,
    required Map<int, double> lastAnalog,
    void Function(String)? onDebugLog,
  }) {
    final uno = unoNode;
    if (uno == null) return;

    for (var ch = 0; ch < AVRConfig.analogInputPorts.length; ch++) {
      if (ch == 0 && micOwnsA0) continue;
      final port = AVRConfig.analogInputPorts[ch];
      if (!spiceEngine.isPortConnected(uno.key, port)) continue;

      final volts = spiceEngine.getPortVoltage(uno.key, port);
      AVRBridge.setAnalogVoltage(ch, volts);

      final last = lastAnalog[ch];
      if (last == null || (last - volts).abs() > 0.05) {
        lastAnalog[ch] = volts;
        onDebugLog?.call('[Analog] A$ch = ${volts.toStringAsFixed(2)} V');
      }
    }
  }
}
