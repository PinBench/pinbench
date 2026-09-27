// The over-current warning must fire from the static validator — i.e. while
// the circuit is being drawn, with no sketch compiled and no simulation
// running. `CircuitValidator.validate` is what the canvas/code sync calls on
// every edit, and its message is what reaches the Problems pane.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/logic/built_in_part_logic.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/services/circuit_validator.dart';

CircuitValidatorResult _validateTemplate(String template, {String? substitute}) {
  var source = File('assets/templates/$template/circuit.cdl').readAsStringSync();
  if (substitute != null) {
    final replaced = source.replaceFirst('resistance: 100;', substitute);
    expect(replaced, isNot(source), reason: 'substitution did not match the shipped file');
    source = replaced;
  }
  final parsed = CircuitParser.applyToCanvas(CircuitParser.parse(source), standardParts);
  return CircuitValidator.validate(nodes: parsed.nodes, wires: parsed.wires);
}

bool _ledFlagged(CircuitValidatorResult result, List<ComponentInstance> _) =>
    result.updatedProperties.values.any((p) => p[ComponentProps.hasError] == true);

void main() {
  test('an undersized resistor is reported before anything is compiled', () {
    final result = _validateTemplate('current_limiting');

    expect(result.errorMessage, isNotNull);
    expect(result.errorMessage, contains('over-current'));
    // The estimate should land on the solver's answer, not merely somewhere.
    expect(result.errorMessage, contains('28 mA'));
    // And it should tell the user what to do about it.
    expect(result.errorMessage, contains('Fit a series resistor'));
    expect(_ledFlagged(result, const []), isTrue, reason: 'the LED should be marked in error');
  });

  test('the correct resistor produces no problem at all', () {
    final result = _validateTemplate('current_limiting', substitute: 'resistance: 220;');

    expect(result.errorMessage, isNull);
    expect(result.updatedProperties.values.any((p) => p[ComponentProps.hasError] == true), isFalse);
  });

  test('a resistor-less LED is caught as the worst case', () {
    // What `blink` used to be: pin straight into the LED.
    const cdl = '''
Circuit {
    uno := ArduinoUno {
        position: (0, 0);
    }
    led_red := LED {
        position: (200, 0);
        color: red;
    }
    Wire {
        from: uno.13;
        to: led_red.anode;
        color: red;
    }
    Wire {
        from: led_red.cathode;
        to: uno.GND_1;
        color: black;
    }
}
''';
    final parsed = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), standardParts);
    final result = CircuitValidator.validate(nodes: parsed.nodes, wires: parsed.wires);

    expect(result.errorMessage, contains('over-current'));
    expect(result.errorMessage, contains('98 mA'));
  });

  test('the resistor it recommends is a real one, and actually resolves the warning', () {
    final advice = _validateTemplate('current_limiting').errorMessage!;
    final ohms = int.parse(RegExp(r'of (\d+) Ω').firstMatch(advice)!.group(1)!);

    // 155 Ω was neither: not a value anyone sells, and sized to land exactly on
    // the 20 mA limit so fitting it left the warning showing.
    expect(ohms, 180, reason: 'should be the next E12 value above the minimum');

    final refitted = _validateTemplate('current_limiting', substitute: 'resistance: $ohms;');
    expect(refitted.errorMessage, isNull, reason: 'taking the advice must clear the warning');
  });

  // The invariant this file exists to defend, and the one the 155 Ω advice
  // broke: the pre-run check must never clear a circuit that the running
  // simulation then flags. A user who fixes every reported problem and presses
  // Run must not be greeted by a red cross.
  test('anything the static check passes, the solver also passes', () {
    for (final ohms in ['100', '120', '140', '150', '155', '156', '160', '180', '220', '470']) {
      final source = File(
        'assets/templates/current_limiting/circuit.cdl',
      ).readAsStringSync().replaceFirst('resistance: 100;', 'resistance: $ohms;');
      final parsed = CircuitParser.applyToCanvas(CircuitParser.parse(source), standardParts);
      final led = parsed.nodes.firstWhere((n) => n.part.name == PartNames.led);

      final spice = SpiceEngine()
        ..build(
          CircuitNetlist()..buildStatic(parsed.nodes, parsed.wires, bridgeResistors: false),
          parsed.nodes,
        );
      spice.setPinVoltage('13', 5.0);
      spice.solve();

      final solvedAmps = spice.getLedCurrent(led.key.toString()).abs();
      final runtimeFlags = solvedAmps > BuiltInPartLogic.ledRatedAmps;
      final staticFlags =
          CircuitValidator.validate(nodes: parsed.nodes, wires: parsed.wires).errorMessage != null;

      if (runtimeFlags) {
        expect(
          staticFlags,
          isTrue,
          reason:
              '$ohms Ω solves to ${(solvedAmps * 1000).toStringAsFixed(2)} mA and would show a '
              'red cross at run time, but the static check reported nothing',
        );
      }
    }
  });

  test('every shipped template is clean except the deliberate one', () {
    final templates = Directory('assets/templates')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((t) => t != 'current_limiting')
        .toList();

    for (final template in templates) {
      final file = File('assets/templates/$template/circuit.cdl');
      if (!file.existsSync()) continue;
      final parsed = CircuitParser.applyToCanvas(
        CircuitParser.parse(file.readAsStringSync()),
        standardParts,
      );
      final result = CircuitValidator.validate(nodes: parsed.nodes, wires: parsed.wires);
      expect(
        result.errorMessage,
        isNull,
        reason: '$template reports "${result.errorMessage}" with nothing running',
      );
    }
  });
}
