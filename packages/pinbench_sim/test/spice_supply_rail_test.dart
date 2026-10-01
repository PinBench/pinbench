/// The board's supply pins in the analog solve: each rail wired to anything
/// holds its voltage, so a divider, an LED or a module powered from `5V` or
/// `3.3V` sees what it would on a desk. They used to be plain nets that solved
/// at 0 V, and only a pin driven high could stand in for a supply.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';

import 'support/bench.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  ComponentInstance pico() => ComponentInstance(
    key: const ValueKey('pico'),
    position: Offset.zero,
    part: PartModel(name: PartNames.picoW, size: const Size(40, 40)),
  );

  ComponentInstance led() => ComponentInstance(
    key: const ValueKey('led'),
    position: const Offset(600, 0),
    part: PartModel(name: PartNames.led, size: const Size(40, 40)),
  );

  /// The midpoint of two 10 kΩ resistors from [board]'s [rail] to [gnd],
  /// read at [port], with nothing driven by the sketch.
  ///
  /// [port] is an input, as a sketch reading it would leave it: on a Pico the
  /// ADC pins are GPIOs too, and a pin left at its driven default would sink
  /// the divider through its 100 Ω.
  double divider(ComponentInstance board, String rail, String gnd, String port) {
    final top = resistor('top', '10k');
    final bottom = resistor('bottom', '10k');
    final bench = Bench(
      [board, top, bottom],
      [
        wire(board, rail, top, 'left'),
        wire(top, 'right', board, port),
        wire(board, port, bottom, 'left'),
        wire(bottom, 'right', board, gnd),
      ],
    );
    bench.spice.setPinDrive(port, voltage: 0, isOutput: false);
    bench.drive({});
    return bench.voltage(board, port);
  }

  group("the Uno's rails", () {
    test('a divider from 5V reads half of it at A0', () {
      expect(divider(uno(), '5V', 'GND_1', 'A0'), closeTo(2.5, 0.01));
    });

    test('a divider from 3.3V reads half of it at A0', () {
      expect(divider(uno(), '3.3V', 'GND_1', 'A0'), closeTo(1.65, 0.01));
    });

    test('an LED and resistor across 5V light with no pin driven', () {
      final board = uno();
      final r = resistor('r');
      final diode = led();
      final bench = Bench(
        [board, r, diode],
        [
          wire(board, '5V', r, 'left'),
          wire(r, 'right', diode, 'anode'),
          wire(diode, 'cathode', board, 'GND_1'),
        ],
      )..drive({});
      // (5 V less the LED's ~1.1 V) over 220 Ω: about 17 mA.
      expect(bench.spice.getLedCurrent(diode.key.toString()).abs(), closeTo(0.0177, 0.002));
      // And the rail is where it comes from: it flows *out* of the board at
      // 5V, which reads negative, as it does for a pin sourcing current.
      expect(bench.current(board, '5V'), closeTo(-0.0177, 0.002));
    });

    test('a rail shorted to GND still solves: a large current, not an error', () {
      final board = uno();
      final bench = Bench([board], [wire(board, '5V', board, 'GND_1')])..drive({});
      // 5 V across the rail's own half an ohm.
      expect(bench.current(board, '5V').abs(), closeTo(10, 0.1));
    });
  });

  group("the Pico's rails", () {
    test('3V3 OUT, VSYS and VBUS each hold their own voltage', () {
      expect(divider(pico(), '3.3V', 'GND_1', '26'), closeTo(1.65, 0.01));
      expect(divider(pico(), 'VSYS', 'GND_1', '26'), closeTo(2.35, 0.01));
      expect(divider(pico(), '5V', 'GND_1', '26'), closeTo(2.5, 0.01));
    });
  });
}
