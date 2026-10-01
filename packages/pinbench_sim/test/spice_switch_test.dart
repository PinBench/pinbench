import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';

import 'support/bench.dart';

/// The slide switch solved for real, and thrown mid-run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  test('common meets a, then b once the lever is thrown, without a rebuild', () {
    // Pin 9 into common; each throw into its own 1 kΩ to ground.
    final board = uno();
    final sw = pdlPart('slide_switch_spdt', properties: {'position': 'A'});
    final loadA = resistor('load_a', '1000');
    final loadB = resistor('load_b', '1000');
    final bench = Bench(
      [board, sw, loadA, loadB],
      [
        wire(board, '9', sw, 'common'),
        wire(sw, 'a', loadA, 'left'),
        wire(loadA, 'right', board, 'GND_1'),
        wire(sw, 'b', loadB, 'left'),
        wire(loadB, 'right', board, 'GND_2'),
      ],
    )..drive({'9': 5});
    expect(bench.voltage(sw, 'a'), greaterThan(4.5));
    expect(bench.voltage(sw, 'b'), lessThan(0.01));

    sw.properties['position'] = 'B';
    bench
      ..frame()
      ..drive({});
    expect(bench.voltage(sw, 'a'), lessThan(0.01));
    expect(bench.voltage(sw, 'b'), greaterThan(4.5));
  });
}
