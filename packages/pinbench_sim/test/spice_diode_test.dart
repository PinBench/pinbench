import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';

import 'support/bench.dart';

/// The three diodes' models: the forward drop each makes at a few milliamps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  double forwardDrop(String id) {
    final board = uno();
    final diode = pdlPart(id);
    final r = resistor('r1', '1000');
    final bench = Bench(
      [board, diode, r],
      [
        wire(board, '9', r, 'left'),
        wire(r, 'right', diode, 'anode'),
        wire(diode, 'cathode', board, 'GND_1'),
      ],
    )..drive({'9': 5});
    return bench.voltage(diode, 'anode');
  }

  test('silicon diodes drop about 0.7 V at a few milliamps', () {
    expect(forwardDrop('diode_1n4148'), inInclusiveRange(0.6, 0.8));
    expect(forwardDrop('diode_1n4007'), inInclusiveRange(0.6, 0.8));
  });

  test('the Schottky drops a fraction of that', () {
    final schottky = forwardDrop('diode_1n5819');
    expect(schottky, lessThan(0.35));
    expect(schottky, lessThan(forwardDrop('diode_1n4148') - 0.3));
  });
}
