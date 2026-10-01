import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';

import 'support/bench.dart';

/// The 7-segment display solved for real: a die per segment on one cathode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('drives the segments it is given, through either cathode pin', () {
    // Segments a and b through their own resistors; the cathode grounded only
    // through the *second* COM pin, which must be tied to the first inside.
    final board = uno();
    final display = pdlPart('seven_segment');
    final rA = resistor('r_a');
    final rB = resistor('r_b');
    final bench = Bench(
      [board, display, rA, rB],
      [
        wire(board, '9', rA, 'left'),
        wire(rA, 'right', display, 'a'),
        wire(board, '10', rB, 'left'),
        wire(rB, 'right', display, 'b'),
        wire(display, 'com2', board, 'GND_1'),
      ],
    )..drive({'9': 5, '10': 5});

    expect(bench.voltage(display, 'a'), inInclusiveRange(1.7, 2.2));
    expect(bench.current(display, 'a'), inInclusiveRange(0.008, 0.013));
    expect(bench.current(display, 'c'), closeTo(0, 1e-9));

    final state = bench.frame()[display.key]!;
    expect(state['a'], greaterThan(0.3));
    expect(state['b'], greaterThan(0.3));
    for (final dark in ['c', 'd', 'e', 'f', 'g', 'dp']) {
      expect(state[dark], 0.0, reason: '$dark has no current');
    }
  });
}
