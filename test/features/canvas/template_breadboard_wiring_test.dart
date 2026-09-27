import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/painting/port_provider.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Parts plugged into a breadboard are wired by *position*: nothing in the
/// .cdl says which hole a leg is in, the netlist works it out from where the
/// leg lands. That makes those circuits silently sensitive to part geometry —
/// resize a body or move a lead and a template can come unplugged with no
/// error anywhere. These tests pin the holes the bundled templates rely on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every hole each plugged-in leg lands in, as `Part.port -> hole`.
  List<String> legsToHoles(String template) {
    final file = File('assets/templates/$template/circuit.cdl');
    final data = CircuitParser.parse(file.readAsStringSync());
    final nodes = CircuitParser.applyToCanvas(data, standardParts).nodes;

    final landings = <String>[];
    for (final node in nodes) {
      final name = node.part.name;
      if (name.contains('Breadboard') || name == PartNames.arduinoUno) continue;
      final painter = node.part.getPainter();
      if (painter is! PortProvider) continue;

      for (final port in (painter! as PortProvider).getPorts()) {
        final offset = node.getPortOffset(port.id);
        if (offset == null) continue;
        final absolute = node.position + offset;

        for (final board in nodes) {
          if (!board.part.name.contains('Breadboard')) continue;
          final boardPainter = board.part.getPainter();
          if (boardPainter is! PortProvider) continue;
          final hole = (boardPainter! as PortProvider).getPortAt(board.absoluteToLocal(absolute));
          if (hole != null) landings.add('$name.${port.id} -> ${hole.id}');
        }
      }
    }
    return landings;
  }

  test('breadboard template: the LED straddles the rows its wires feed', () {
    // Two different rows, so the LED isn't shorted out by the strip it sits in.
    expect(legsToHoles('breadboard'), ['LED.anode -> sig_left_a_1', 'LED.cathode -> sig_left_a_0']);
  });

  test('clap_rhythm: every part is plugged in, and into the right rows', () {
    // Re-laid out 2026-08-06, twice: once to close the two gaps the old layout
    // carried (the mic sensor touching nothing at all, one resistor stranded
    // between rows), then again when the board itself became landscape and
    // every part had to be re-fitted to the transposed holes.
    expect(legsToHoles('clap_rhythm'), [
      // Each LED spans two rows, and its anode row is the one its resistor's
      // left leg lands in (5, 9, 13) — columns a–e of a row are one node, so
      // `d_5` and `e_5` are the series joint. The resistor's right leg crosses
      // the channel, which is what keeps it in series rather than shorted.
      'LED.anode -> sig_left_d_5',
      'LED.cathode -> sig_left_d_4',
      'LED.anode -> sig_left_d_9',
      'LED.cathode -> sig_left_d_8',
      'LED.anode -> sig_left_d_13',
      'LED.cathode -> sig_left_d_12',
      // Buttons straddle the centre channel: legs 1/2 in the a–e bank, 3/4 in
      // f–j, so the pairs a press connects aren't already joined. They land in
      // e and f — the notch is 0.3" wide, exactly a tactile switch's leg span,
      // so nothing overshoots into g the way it used to. (Legs 1 and 3 share a
      // row, which is what the switch shorts across when pressed.)
      'Push Button.leg1 -> sig_left_e_16',
      'Push Button.leg2 -> sig_left_e_18',
      'Push Button.leg3 -> sig_right_f_16',
      'Push Button.leg4 -> sig_right_f_18',
      'Push Button.leg1 -> sig_left_e_21',
      'Push Button.leg2 -> sig_left_e_23',
      'Push Button.leg3 -> sig_right_f_21',
      'Push Button.leg4 -> sig_right_f_23',
      'Push Button.leg1 -> sig_left_e_26',
      'Push Button.leg2 -> sig_left_e_28',
      'Push Button.leg3 -> sig_right_f_26',
      'Push Button.leg4 -> sig_right_f_28',
      'Resistor.left -> sig_left_e_5',
      'Resistor.right -> sig_right_f_5',
      'Resistor.left -> sig_left_e_9',
      'Resistor.right -> sig_right_f_9',
      'Resistor.left -> sig_left_e_13',
      'Resistor.right -> sig_right_f_13',
      // The buzzer sits on two rows nothing else lands on, so it's joined to
      // the circuit only by its own wires — as it always has been.
      'Piezo Buzzer.plus -> sig_right_f_32',
      'Piezo Buzzer.minus -> sig_right_f_34',
      // The mic's four pins each get a row to themselves, so none of them
      // short together through the strip they sit in.
      'Mic Sensor.A0 -> sig_right_f_39',
      'Mic Sensor.G -> sig_right_f_40',
      'Mic Sensor.+ -> sig_right_f_41',
      'Mic Sensor.D0 -> sig_right_f_42',
    ]);
  });

  test('mic: the sensor sits in the rows its wires feed', () {
    // The sensor used to hang off the board entirely — its pins in no hole,
    // its wires running to `j` rows nothing plugged into. Re-fitting the
    // template for the landscape board was the moment to seat it: one pin per
    // row, in the four rows the wires actually use.
    expect(legsToHoles('mic'), [
      // Not wired to anything: the buzzer is here to be dropped into a
      // circuit, and was floating in this template before too.
      'Piezo Buzzer.plus -> sig_right_i_3',
      'Piezo Buzzer.minus -> sig_right_i_5',
      // One pin per row, so none of the four short together.
      'Mic Sensor.A0 -> sig_right_i_10',
      'Mic Sensor.G -> sig_right_i_11',
      'Mic Sensor.+ -> sig_right_i_12',
      'Mic Sensor.D0 -> sig_right_i_13',
    ]);
  });
}
