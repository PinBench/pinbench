/// `AVRBridge.tick` advances simulated time by exactly the cycles it is asked
/// for, which is what keeps `delay()` and `millis()` in step with the wall
/// clock.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_sim/core/avr_interop.dart';

void main() {
  test('tick(n) advances n cycles, not n instructions', () {
    // Any real firmware will do; this one mixes Wire, Serial and delay loops,
    // so its instructions average well over one cycle each.
    AVRBridge.loadHex(File('test/fixtures/i2c_read/i2c_read.hex').readAsStringSync());
    const frame = 256000; // one 16 ms frame at 16 MHz

    for (var f = 0; f < 50; f++) {
      final before = AVRBridge.getCycles();
      AVRBridge.tick(frame);
      final ran = AVRBridge.getCycles() - before;
      // The last instruction may finish a few cycles past the boundary (the
      // longest AVR instructions take 4 cycles, 5 with an interrupt entry).
      expect(ran, inInclusiveRange(frame, frame + 5), reason: 'frame $f ran $ran cycles');
    }
  });
}
