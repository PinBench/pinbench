import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_sim/config/avr_config.dart';
import 'package:pinbench_sim/core/frequency_detector.dart';

void main() {
  group('FrequencyDetector', () {
    test('detects a steady 2 kHz square wave', () {
      final detector = FrequencyDetector();
      double? detected;

      // 2 kHz => half-period = clock / (2 * f) = 16e6 / 4000 = 4000 cycles.
      const halfPeriod = 4000;
      var cycle = 0;
      for (var i = 0; i < 8; i++) {
        cycle += halfPeriod;
        detector.onPinToggle(cycle, (f) => detected = f);
      }

      expect(detector.isTonePlaying, isTrue);
      expect(detected, isNotNull);
      expect(detected, closeTo(2000.0, 1.0));
    });

    test('derives frequency from the clock for an arbitrary period', () {
      final detector = FrequencyDetector();
      double? detected;

      // ~1 kHz => half-period = 16e6 / 2000 = 8000 cycles.
      const halfPeriod = 8000;
      var cycle = 0;
      for (var i = 0; i < 8; i++) {
        cycle += halfPeriod;
        detector.onPinToggle(cycle, (f) => detected = f);
      }

      const expected = AVRConfig.clockFrequency / (2.0 * halfPeriod);
      expect(detected, closeTo(expected, 5.0));
    });

    test('checkTimeout stops the tone after silence and resets', () {
      final detector = FrequencyDetector();
      var cycle = 0;
      for (var i = 0; i < 8; i++) {
        cycle += 4000;
        detector.onPinToggle(cycle, (_) {});
      }
      expect(detector.isTonePlaying, isTrue);

      // Far past the dynamic timeout window.
      final stopped = detector.checkTimeout(cycle + 1000000);
      expect(stopped, isTrue);
      expect(detector.isTonePlaying, isFalse);
    });

    test('ignores toggles outside the audible range', () {
      final detector = FrequencyDetector();
      // 100-cycle half period => ~80 kHz, above the 20 kHz ceiling.
      var cycle = 0;
      for (var i = 0; i < 8; i++) {
        cycle += 100;
        detector.onPinToggle(cycle, (_) => fail('should not detect a tone'));
      }
      expect(detector.isTonePlaying, isFalse);
    });
  });
}
