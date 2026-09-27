import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Regression test for "LED blink stops working on a re-run while the AVR keeps
/// running (serial still prints)".
///
/// Root cause: simulation frame updates are routed back to the canvas **by node
/// key**. The canvas <-> code (.cdl) sync regenerates the .cdl text from the
/// canvas every time a node property changes — and during a run the LED's `isOn`
/// toggles each blink, so the text changes and the editor's change-listener
/// re-parses it back onto the canvas. If that re-parse mints a NEW key for each
/// node, the live canvas node no longer matches the key the simulation engine is
/// addressing, so its visual updates are silently dropped (the LED never lights),
/// even though the emulator (and serial output) runs fine.
///
/// The invariant that prevents this: a node's key MUST survive a
/// generate -> parse round-trip, so identity is stable across re-parses.
void main() {
  final components = [
    PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
    PartModel(name: PartNames.led, size: const Size(40, 40)),
  ];

  // The user's exact circuit: LED anode -> pin 13, cathode -> GND (no resistor).
  const cdl = '''
Circuit {
    uno := ArduinoUno {
        position: (x: -190, y: -140);
        13: false;
    }
    led1 := LED {
        position: (x: -30, y: -220);
        color: red;
        isOn: false;
        brightness: 0.0;
    }
    Wire {
        from: led1.cathode;
        to: uno.GND_1;
        color: black;
    }
    Wire {
        from: led1.anode;
        to: uno.13;
        color: red;
    }
}
''';

  Key ledKeyOf(List<ComponentInstance> nodes) =>
      nodes.firstWhere((n) => n.part.name == PartNames.led).key;

  test('node identity survives a generate -> parse round-trip', () {
    final first = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), components);
    final ledKey1 = ledKeyOf(first.nodes);

    // Mirror what the canvas<->code sync does on every blink while simulating:
    // regenerate the .cdl from the canvas, then re-parse it back.
    final regenerated = CircuitParser.generate(first.nodes, first.wires);
    final second = CircuitParser.applyToCanvas(CircuitParser.parse(regenerated), components);
    final ledKey2 = ledKeyOf(second.nodes);

    expect(
      ledKey2,
      equals(ledKey1),
      reason:
          'A re-parse must preserve node keys; otherwise simulation frame '
          'updates (mapped by key) stop reaching the LED after the first sync.',
    );
  });

  test('re-parsing the same circuit twice yields the same node keys', () {
    final a = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), components);
    final b = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), components);
    expect(
      ledKeyOf(b.nodes),
      equals(ledKeyOf(a.nodes)),
      reason: 'Parsing identical CDL must produce stable, equal node keys.',
    );
  });
}
