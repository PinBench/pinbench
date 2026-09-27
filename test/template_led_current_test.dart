// Every shipped template must drive its LEDs within their rating.
//
// A template is the first circuit a beginner ever runs, so one that would
// destroy a real LED — or exceed the ATmega328P's 40 mA per-pin maximum — is
// teaching the mistake rather than catching it. Since `BuiltInPartLogic.led`
// started flagging over-current, such a template also renders as a red X on
// the canvas, which is a visible bug rather than a subtle one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/logic/built_in_part_logic.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';

/// The one template that is *supposed* to over-drive its LED: showing the
/// mistake is its entire purpose, and `analog_comparison_claims_test.dart`
/// pins the exact current it draws.
const _deliberatelyOverDriven = {'current_limiting'};

void main() {
  final templates =
      Directory('assets/templates')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();

  group('shipped templates keep their LEDs within rating', () {
    for (final template in templates) {
      test(template, () {
        if (_deliberatelyOverDriven.contains(template)) return;

        final file = File('assets/templates/$template/circuit.cdl');
        if (!file.existsSync()) return;

        final parsed = CircuitParser.applyToCanvas(
          CircuitParser.parse(file.readAsStringSync()),
          standardParts,
        );
        final leds = parsed.nodes.where((n) => n.part.name == PartNames.led).toList();
        if (leds.isEmpty) return;

        final netlist = CircuitNetlist()
          ..buildStatic(parsed.nodes, parsed.wires, bridgeResistors: false);
        final spice = SpiceEngine()..build(netlist, parsed.nodes);

        // Drive every output pin hard at once. That is not what the sketch
        // does, but it is the worst case the circuit permits, and a template
        // should be safe in it.
        for (final pin in const ['3', '5', '6', '8', '9', '10', '11', '12', '13']) {
          spice.setPinVoltage(pin, 5.0);
        }
        spice.solve();

        for (final led in leds) {
          final milliamps = spice.getLedCurrent(led.key.toString()).abs() * 1000;
          expect(
            milliamps,
            lessThanOrEqualTo(BuiltInPartLogic.ledRatedAmps * 1000),
            reason:
                '$template drives an LED at ${milliamps.toStringAsFixed(1)} mA — '
                'it needs a bigger series resistor',
          );
        }
      });
    }
  });
}
