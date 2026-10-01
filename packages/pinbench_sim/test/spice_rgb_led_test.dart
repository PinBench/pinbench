import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';

import 'support/bench.dart';

/// The RGB LED solved for real: three dies on one cathode, each lit from the
/// current through it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('each colour conducts at its own forward voltage and lights on its own', () {
    // Red on pin 9 and green on pin 10, each through its own 220 Ω; blue open.
    final board = uno();
    final led = pdlPart('rgb_led');
    final rRed = resistor('r_red');
    final rGreen = resistor('r_green');
    final bench = Bench(
      [board, led, rRed, rGreen],
      [
        wire(board, '9', rRed, 'left'),
        wire(rRed, 'right', led, 'red'),
        wire(board, '10', rGreen, 'left'),
        wire(rGreen, 'right', led, 'green'),
        wire(led, 'cathode', board, 'GND_1'),
      ],
    )..drive({'9': 5, '10': 5});

    expect(bench.voltage(led, 'red'), inInclusiveRange(1.7, 2.2));
    expect(bench.voltage(led, 'green'), inInclusiveRange(2.6, 3.2));
    final red = bench.current(led, 'red');
    final green = bench.current(led, 'green');
    expect(red, inInclusiveRange(0.008, 0.013), reason: '(5 - 2 V) across 260 Ω');
    expect(green, lessThan(red), reason: 'the green die drops more, so passes less');
    expect(bench.current(led, 'blue'), closeTo(0, 1e-6));
    expect(
      bench.current(led, 'cathode'),
      closeTo(-(red + green), 1e-6),
      reason: 'everything in through the anodes leaves through the cathode',
    );

    final state = bench.frame()[led.key]!;
    expect(state['red'], greaterThan(0.3));
    expect(state['green'], greaterThan(0));
    expect(state['blue'], 0.0);
  });
}
