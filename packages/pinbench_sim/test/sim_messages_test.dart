import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_sim/isolate/sim_messages.dart';

/// The isolate messages are plain value carriers (the isolate copies them over a
/// SendPort), so this just pins down their shape: payloads stay built from
/// sendable types and the sealed hierarchies are exhaustive over the kinds the
/// runner/worker switch on.

void main() {
  test('commands expose their payloads', () {
    final start = StartSim(
      hex: ':00000001FF',
      nodesJson: [
        {'id': 'uno'},
      ],
      wiresJson: const [],
    );
    expect(start.hex, ':00000001FF');
    expect(start.nodesJson.first['id'], 'uno');
    expect(start.wiresJson, isEmpty);

    expect(SerialInput('hi').text, 'hi');
    final mic = MicReading(3.3, isHigh: true);
    expect(mic.volts, 3.3);
    expect(mic.isHigh, isTrue);
    expect(ButtonStates({'b1': true}).states['b1'], isTrue);
  });

  test('events expose their payloads', () {
    final frame = FrameUpdates({
      'led1': {'isOn': true},
    });
    expect(frame.updates['led1']!['isOn'], isTrue);
    expect(BuzzerFreq(440).hz, 440);
    expect(BuzzerFreq(null).hz, isNull);
    expect(SimError('boom').message, 'boom');
  });

  test('every command is a SimCommand and every event a SimEvent', () {
    expect(StopSim(), isA<SimCommand>());
    expect(PauseSim(), isA<SimCommand>());
    expect(ResumeSim(), isA<SimCommand>());
    expect(RebuildCircuit(nodesJson: const [], wiresJson: const []), isA<SimCommand>());
    expect(SimStopped(), isA<SimEvent>());
    expect(SerialPrint('x'), isA<SimEvent>());
    expect(SpiceLog('x'), isA<SimEvent>());
    expect(DebugLog('x'), isA<SimEvent>());
  });
}
