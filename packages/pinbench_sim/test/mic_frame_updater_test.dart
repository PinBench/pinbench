import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_sim/core/avr_interop.dart';
import 'package:pinbench_sim/core/sim_io.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/core/updaters/mic_frame_updater.dart';

/// Who is allowed to write ADC channel 0.
///
/// A0 has two possible owners — a mic sensor, or whatever the analog solver
/// resolved at the Arduino's A0 pin — and they must not both write it.
/// `AnalogIoFrameUpdater` already declines when a mic is present; the other
/// direction did not hold, and the mic stamped channel 0 on every frame
/// whether or not a mic existed, so `analogRead(A0)` returned 0 for every
/// divider, potentiometer and sensor on that pin.
///
/// The ADC has no read accessor to assert against, so the "does not clobber"
/// half is covered end-to-end by `test/voltage_divider_end_to_end_test.dart`,
/// which runs the real engine and reads the Serial Monitor. What is asserted
/// here is the half that guard could plausibly break: a mic that *is* present
/// must still drive its channels.
class _LoudMic implements MicInput {
  @override
  double get analogVoltage => 3.3;
  @override
  bool get isDigitalHigh => true;
}

ComponentInstance _mic(String id) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: PartNames.ky037MicSensor, size: const Size(40, 40)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The mic path writes the ADC, which only exists once a program is loaded.
  // The no-mic case below deliberately does not need this — returning before
  // touching the ADC at all is the fix.
  setUp(() => AVRBridge.loadHex(':00000001FF'));

  test('a mic on the canvas still drives its own SPICE sources', () {
    final spice = SpiceEngine();
    final updates = <LocalKey, Map<String, dynamic>>{};

    MicFrameUpdater.update(
      micInput: _LoudMic(),
      micSensors: [_mic('mic1')],
      spiceEngine: spice,
      lastMicHigh: {},
      queueUpdate: (key, props) => updates[key] = props,
    );

    expect(spice.getPinVoltage("[<'mic1'>]_A0"), closeTo(3.3, 1e-9));
    expect(spice.getPinVoltage("[<'mic1'>]_D0"), greaterThan(2.5));
    expect(
      updates[const ValueKey('mic1')]?[ComponentProps.isDigitalHigh],
      isTrue,
      reason: 'a change in the digital line should reach the canvas',
    );
  });

  test('with no mic, nothing is injected at all', () {
    final spice = SpiceEngine();
    var queued = 0;

    MicFrameUpdater.update(
      micInput: _LoudMic(),
      micSensors: const [],
      spiceEngine: spice,
      lastMicHigh: {},
      queueUpdate: (_, _) => queued++,
    );

    expect(queued, 0);
  });
}
