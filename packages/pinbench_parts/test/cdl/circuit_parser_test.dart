import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/painting/part_palette.dart';

ComponentInstance _node(String name, String id, Offset pos) => ComponentInstance(
  key: ValueKey(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
);

void main() {
  group('CircuitParser.generate', () {
    test('round-trips through parse with matching part and wire counts', () {
      final uno = _node(PartNames.arduinoUno, 'uno', Offset.zero);
      final led = _node(PartNames.led, 'led', const Offset(100, 50));
      final wires = [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: led.key, portId: 'anode'),
          end: PortLocation(nodeKey: uno.key, portId: '13'),
          color: PartPalette.red,
        ),
      ];

      final generated = CircuitParser.generate([uno, led], wires);
      expect(generated, contains('uno := ArduinoUno {'));
      expect(generated, contains('led := LED {'));
      expect(generated, contains('from: led.anode;'));
      expect(generated, contains('to: uno.13;'));

      final reparsed = CircuitParser.parse(generated);
      expect(reparsed.parts.length, 2);
      expect(reparsed.wires.length, 1);
      expect(reparsed.wires.first.fromPort, 'anode');
      expect(reparsed.wires.first.toPort, '13');
    });

    test('omits simulation-written runtime flags but keeps design properties', () {
      // Regression test: batchSimulationUpdate merges runtime flags (isOn,
      // brightness, ...) into a node's properties map for the duration of a
      // run. If generate() serialized them verbatim, the .cdl produced right
      // after a simulation would differ from the pre-run file and the tab
      // would show as unsaved even though the user changed nothing.
      final led = ComponentInstance(
        key: const ValueKey('led'),
        position: Offset.zero,
        part: PartModel(name: PartNames.led, size: const Size(40, 40)),
        properties: const {
          ComponentProps.color: 'Red',
          ComponentProps.isOn: true,
          ComponentProps.brightness: 0.8,
          ComponentProps.hasError: false,
        },
      );

      final generated = CircuitParser.generate([led], const []);
      expect(generated, contains('color: red'));
      expect(generated, isNot(contains('isOn')));
      expect(generated, isNot(contains('brightness')));
      expect(generated, isNot(contains('hasError')));
    });

    test("omits a .pdl part's declared STATE but keeps its properties", () async {
      // The same false-dirty as above, for data-driven parts: every frame
      // writes a part's STATE onto the canvas, and saving it would also hand
      // the next run the last run's value to start from.
      TestWidgetsFlutterBinding.ensureInitialized();
      await PartRegistry.initializeAsync();
      final ntc = ComponentInstance(
        key: const ValueKey('ntc'),
        position: Offset.zero,
        part: PartModel(
          name: 'Thermistor (NTC)',
          size: const Size(80, 40),
          definitionId: 'thermistor',
        ),
        properties: const {'temperature': 30, 'kelvin': 303.15},
      );

      final generated = CircuitParser.generate([ntc], const []);
      expect(generated, contains('temperature: 30'));
      expect(generated, isNot(contains('kelvin')));
    });

    test('regenerating after a simulated run produces identical text (no false-dirty)', () {
      // End-to-end regression for the "circuit.cdl shows unsaved after
      // simulation ends" bug: parse a real template, apply it to canvas
      // nodes exactly like CircuitCanvasApplier does, then merge simulation
      // runtime updates (as batchSimulationUpdate does mid-run and as
      // SimulationEngine.stop()'s LED reset does at the very end) before
      // regenerating. The regenerated text must match what a pristine,
      // never-simulated load would produce — otherwise the tab flips dirty
      // for no user-visible reason the moment a run ends.
      const blinkCdl = '''
// Circuit description (.cdl) — kept in sync with the canvas.
// Edit components and wires here or on the canvas; both update together.
Circuit {
    uno := ArduinoUno {
        position: (-190, -140);
    }
    led1 := LED {
        position: (-30, -220);
        color: red;
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

      final uno = _node(PartNames.arduinoUno, 'uno', const Offset(-190, -140));
      var led = ComponentInstance(
        key: const ValueKey('led1'),
        position: const Offset(-30, -220),
        part: PartModel(name: PartNames.led, size: const Size(40, 40)),
        properties: const {ComponentProps.color: 'Red'},
      );
      final wires = [
        WireModel(
          id: 'w1',
          start: PortLocation(nodeKey: led.key, portId: 'cathode'),
          end: PortLocation(nodeKey: uno.key, portId: 'GND_1'),
          color: PartPalette.black,
        ),
        WireModel(
          id: 'w2',
          start: PortLocation(nodeKey: led.key, portId: 'anode'),
          end: PortLocation(nodeKey: uno.key, portId: '13'),
          color: PartPalette.red,
        ),
      ];

      final pristine = CircuitParser.generate([uno, led], wires);
      expect(pristine, blinkCdl);

      // Simulate a full run: the LED blinks on (batchSimulationUpdate merge),
      // then the engine's stop() resets it back off — merging, never
      // replacing, so any prior runtime keys accumulate exactly like the
      // live canvas controller does.
      led = led.copyWith(
        properties: {
          ...led.properties,
          ComponentProps.isOn: true,
          ComponentProps.brightness: 1.0,
          ComponentProps.hasError: false,
        },
      );
      led = led.copyWith(
        properties: {...led.properties, ComponentProps.isOn: false, ComponentProps.hasError: false},
      );

      final afterRun = CircuitParser.generate([uno, led], wires);
      expect(afterRun, pristine);
    });
  });

  group('CircuitParser.parse (Slint element format)', () {
    const cdl = '''
// a comment
Circuit {

    led_red := LED {
        position: (x: 30px, y: 40px);
        rotation: 90deg;
        flip: H;
        color: red;
    }

    uno := ArduinoUno {
        position: (x: -10, y: -20);
    }

    Wire {
        from: led_red.anode;
        to: uno.13;
        color: red;
        bend: (1px, 2px) -> (3px, 4px);
    }

    Wire {
        from: led_red.cathode;
        to: uno.GND_1;
        color: black;
    }
}
''';

    test('tolerates px/deg units and parses flip and properties', () {
      final data = CircuitParser.parse(cdl);
      expect(data.parts.length, 2);

      final led = data.parts[0];
      expect(led.id, 'led_red');
      expect(led.type, 'LED'); // the type token round-trips (LED == LED)
      expect(led.position, const CdlPoint(30, 40));
      // 90deg is stored internally as radians.
      expect(led.rotationAngle, closeTo(1.5708, 0.0001));
      expect(led.flipHorizontal, isTrue);
      expect(led.flipVertical, isFalse);
      expect(led.properties?['Color'], 'Red');
    });

    // Written as plain numbers, though `90deg` / `220 Ω` still parse — a unit
    // is how a value is displayed, not what it is, and leaving it out keeps
    // the file readable and machine-writable.
    test('writes rotations and values without units', () {
      final resistor = ComponentInstance(
        key: const ValueKey('r1'),
        position: Offset.zero,
        part: standardParts.firstWhere((c) => c.name == PartNames.resistor),
        rotationAngle: math.pi / 2,
        properties: {ComponentProps.resistance: '220 Ω'},
      );

      final cdl = CircuitParser.generate([resistor], const []);

      expect(cdl, contains('rotation: 90;'));
      expect(cdl, contains('resistance: 220;'));
      expect(cdl, isNot(contains('deg')));
      expect(cdl, isNot(contains('Ω')));
    });

    test('keeps a multiplier while dropping the unit', () {
      final resistor = ComponentInstance(
        key: const ValueKey('r1'),
        position: Offset.zero,
        part: standardParts.firstWhere((c) => c.name == PartNames.resistor),
        properties: {ComponentProps.resistance: '4.7 kΩ'},
      );

      expect(CircuitParser.generate([resistor], const []), contains('resistance: 4.7k;'));
    });

    test('resolves a spaced type token (ArduinoUno) back to the component', () {
      final data = CircuitParser.parse(cdl);
      final applied = CircuitParser.applyToCanvas(data, standardParts);
      final names = applied.nodes.map((n) => n.part.name).toList();
      expect(names, contains(PartNames.arduinoUno));
      expect(names, contains(PartNames.led));
    });

    test('resolves an alias, so a file written under an old name still loads', () {
      // The LDR was a `.pdl` part called "Photoresistor"; files saved then say
      // `Photoresistor`, and its properties in the `.pdl`'s camelCase.
      final data = CircuitParser.parse('''
Circuit {
    ldr1 := Photoresistor {
        position: (0, 0);
        illumination: 80;
    }
}''');
      final node = CircuitParser.applyToCanvas(data, standardParts).nodes.single;
      expect(node.part.name, PartNames.ldr);
      expect(node.properties[ComponentProps.illumination], '80');

      expect(
        CircuitParser.generate([node], const []),
        allOf(contains('ldr1 := LDR {'), contains('illumination: 80;')),
        reason: 'it is written back under its current name',
      );
    });

    test('parses Wire from/to ports, color and bend tuples', () {
      final data = CircuitParser.parse(cdl);
      expect(data.wires.length, 2);

      final w = data.wires[0];
      expect(w.fromId, 'led_red');
      expect(w.fromPort, 'anode');
      expect(w.toId, 'uno');
      expect(w.toPort, '13');
      expect(w.color, 'red');
      expect(w.bendPoints, [const CdlPoint(1, 2), const CdlPoint(3, 4)]);
    });

    test('parses the compact position tuple and bracketed bends list', () {
      final data = CircuitParser.parse('''
Circuit {
    led_red := LED {
        position: (30, 40);
    }
    uno := ArduinoUno {
        position: (-10, -20);
    }
    Wire {
        from: led_red.anode;
        to: uno.13;
        color: red;
        bends: [(1, 2), (3, 4)];
    }
    Wire {
        from: led_red.cathode;
        to: uno.GND;
        color: black;
        bends: [(5, 6) (7, 8)];
    }
}
''');

      expect(data.parts[0].position, const CdlPoint(30, 40));
      expect(data.parts[1].position, const CdlPoint(-10, -20));
      expect(data.wires[0].bendPoints, [const CdlPoint(1, 2), const CdlPoint(3, 4)]);
      // The pre-comma spelling (points separated by spaces) still parses.
      expect(data.wires[1].bendPoints, [const CdlPoint(5, 6), const CdlPoint(7, 8)]);
    });
  });
}
