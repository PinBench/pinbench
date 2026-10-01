import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';

import '../../config/sim_constants.dart';
import '../board/board_emulator.dart';
import '../sim_io.dart';
import '../spice_engine.dart';

/// Per-frame microphone sensor update: injects the latest mic reading into
/// the board's ADC and the SPICE model, queuing a digital-state canvas update
/// only when it changed. Extracted from `SimulationEngine._updateMicSensors`.
abstract final class MicFrameUpdater {
  static void update({
    required BoardEmulator board,
    required MicInput micInput,
    required List<ComponentInstance> micSensors,
    required SpiceEngine spiceEngine,
    required Map<LocalKey, bool> lastMicHigh,
    required void Function(LocalKey key, Map<String, dynamic> props) queueUpdate,
  }) {
    // Nothing to inject when no mic is on the canvas — and injecting anyway is
    // not harmless. This ran before the CPU tick and wrote silence into ADC
    // channel 0 unconditionally, so any *other* analog source on A0 — a
    // divider, a potentiometer, a sensor — was overwritten with 0 V every
    // frame before the sketch could read it. `analogRead(A0)` returned 0
    // forever while the solver quietly computed the right voltage.
    //
    // `AnalogIoFrameUpdater` already declines to touch A0 when a mic owns it;
    // this is the other half of that agreement.
    if (micSensors.isEmpty) return;

    final analogVolts = micInput.analogVoltage;
    final isHigh = micInput.isDigitalHigh;

    board.setAnalogVoltage(0, analogVolts);

    for (final node in micSensors) {
      spiceEngine.setPinVoltage('${node.key}_A0', analogVolts);
      spiceEngine.setPinVoltage(
        '${node.key}_D0',
        isHigh ? SimConstants.logicHighVolts : SimConstants.logicLowVolts,
      );
      if (lastMicHigh[node.key] != isHigh) {
        lastMicHigh[node.key] = isHigh;
        queueUpdate(node.key, {ComponentProps.isDigitalHigh: isHigh});
      }
    }
  }
}
