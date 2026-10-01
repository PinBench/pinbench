import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the netlist builder emits for each kind of part.
///
/// The builder used to have two paths: one driven by a part's declared SPICE
/// model, and a fallback that recognised `led`, `resistor` and `potentiometer`
/// by *display name*. The fallback ignored the properties panel — a resistor
/// was built at 220 Ω whatever the user set — so these pin both the single
/// path and the values that reach it.
void main() {
  ComponentInstance place(String partName, {Map<String, dynamic>? properties, String id = 'n1'}) =>
      ComponentInstance(
        key: ValueKey(id),
        position: Offset.zero,
        part: standardParts.firstWhere((p) => p.name == partName),
        properties: properties,
      );

  /// The netlist lines emitted for [nodes].
  List<String> netlistFor(List<ComponentInstance> nodes, [List<WireModel> wires = const []]) {
    final lines = <String>[];
    SpiceEngine(onLog: lines.add)
        .build(CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false), nodes);
    return lines.map((l) => l.trim()).toList();
  }

  String elementLine(List<String> lines, String prefix) =>
      lines.firstWhere((l) => l.startsWith(prefix), orElse: () => '<no $prefix line>');

  group('resistors carry the value the user set', () {
    test('a 1k resistor reaches SPICE as 1000, not the default', () {
      // The regression: this emitted `220` for every resistor ever placed, so
      // changing one repainted its colour bands and changed nothing
      // electrical — including the LED brightness it was supposed to limit.
      final lines = netlistFor([
        place(PartNames.resistor, properties: {ComponentProps.resistance: '1000'}),
      ]);
      expect(elementLine(lines, 'R_'), endsWith('1000.0'));
    });

    test('a resistor with no value set still gets the 220 default', () {
      final lines = netlistFor([place(PartNames.resistor)]);
      expect(elementLine(lines, 'R_'), endsWith('220.0'));
    });

    test('a nonsense value falls back rather than emitting a broken netlist', () {
      // One unparseable element makes ngspice reject the whole circuit.
      final lines = netlistFor([
        place(PartNames.resistor, properties: {ComponentProps.resistance: 'brown-black-red'}),
      ]);
      expect(elementLine(lines, 'R_'), endsWith('220.0'));
    });

    test('a numeric value works as well as a string one', () {
      // Properties arrive as strings from the panel and as numbers from a
      // behaviour rule; both have to land.
      final lines = netlistFor([
        place(PartNames.resistor, properties: {ComponentProps.resistance: 4700}),
      ]);
      expect(elementLine(lines, 'R_'), endsWith('4700.0'));
    });
  });

  group('the other primitives still build', () {
    test('an LED is a diode plus the 0V source that measures its current', () {
      // Without the measuring source there is no current to read, and the LED
      // never lights however much current flows.
      final lines = netlistFor([place(PartNames.led)]);
      expect(lines.any((l) => l.startsWith('.model D_')), isTrue);
      expect(lines.any((l) => l.startsWith('D_')), isTrue);
      expect(lines.any((l) => l.startsWith('V_led_')), isTrue);
    });

    test('a potentiometer splits its track around the wiper', () {
      final lines = netlistFor([
        place(PartNames.potentiometer, properties: {ComponentProps.potentiometerValue: '0.25'}),
      ]);
      final a = lines.firstWhere((l) => l.contains('_a '));
      final b = lines.firstWhere((l) => l.contains('_b '));
      expect(a, endsWith('7500.0'), reason: 'three quarters of the 10k track above the wiper');
      expect(b, endsWith('2500.0'), reason: 'a quarter below it');
    });

    test('a pot at either extreme never emits a zero-ohm leg', () {
      // A 0 Ω leg is a short across the wiper and fails the operating point.
      for (final position in ['0', '1']) {
        final lines = netlistFor([
          place(PartNames.potentiometer, properties: {ComponentProps.potentiometerValue: position}),
        ]);
        for (final line in lines.where((l) => l.contains('_a ') || l.contains('_b '))) {
          expect(double.parse(line.split(' ').last), greaterThan(0), reason: line);
        }
      }
    });
  });

  group('the board is not an element — it supplies pin sources instead', () {
    // The one node the builder singles out, and it is now a declared flag
    // rather than a name comparison.
    List<String> withLedOn(String board, String pin) {
      final boardNode = place(board, id: 'board');
      final led = place(PartNames.led, id: 'led');
      return netlistFor(
        [boardNode, led],
        [
          WireModel(
            id: 'w1',
            start: PortLocation(nodeKey: boardNode.key, portId: pin),
            end: PortLocation(nodeKey: led.key, portId: 'anode'),
          ),
        ],
      );
    }

    test('a wired pin gets a source behind its output resistance; the rest none', () {
      final lines = withLedOn(PartNames.arduinoUno, '13');
      expect(lines, contains('V_board_13 n_int_src_13 n_0 0.0'));
      expect(elementLine(lines, 'R_board_13'), endsWith(' 40.0'));
      expect(lines.where((l) => l.startsWith('V_board_')), hasLength(1));
      expect(
        lines.where((l) => l.startsWith('R_') && !l.startsWith('R_board_')),
        isEmpty,
        reason: 'the board itself contributes no part element',
      );
    });

    test('a wired supply rail is a source at its voltage; an unwired one is absent', () {
      final lines = withLedOn(PartNames.arduinoUno, '5V');
      expect(lines, contains('V_board_rail_5V n_int_rail_5V n_0 5.0'));
      expect(elementLine(lines, 'R_board_rail_5V'), endsWith(' 0.5'));
      expect(lines.where((l) => l.startsWith('V_board_rail_')), hasLength(1));
    });

    test("a Pico's pins drive through the RP2040's resistance", () {
      final lines = withLedOn(PartNames.picoW, '15');
      expect(lines, contains('V_board_15 n_int_src_15 n_0 0.0'));
      expect(elementLine(lines, 'R_board_15'), endsWith(' 100.0'));
    });
  });

  test('a part with no declared SPICE model contributes nothing', () {
    // `V_gnd` is the netlist tying node 0 to SPICE ground; it is always there
    // and belongs to no part.
    final lines = netlistFor([place(PartNames.breadboardHalf)]);
    expect(lines.where((l) => RegExp('^[VRDC]_').hasMatch(l) && l != 'V_gnd n_0 0 0'), isEmpty);
  });

  test('every built-in part declaring a SPICE model can be resolved by type', () {
    // `spiceFor` falls back to the catalog entry for the part name, which is
    // what keeps a hand-built PartModel — a test fixture, or fromJson's
    // unknown-part fallback — from silently losing its electrical behaviour.
    final declared = standardParts.where((p) => p.spice != null);
    expect(declared, isNotEmpty);
    for (final part in declared) {
      final handBuilt = PartModel(name: part.name, size: part.size);
      expect(handBuilt.spice, isNull, reason: 'the instance carries nothing');
      expect(PartRegistry.spiceFor(handBuilt), isNotNull, reason: '${part.name} by type');
    }
  });
}
