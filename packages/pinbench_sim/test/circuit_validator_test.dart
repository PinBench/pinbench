import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/services/circuit_validator.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

ComponentInstance _node(String name, String id, [Offset pos = Offset.zero]) => ComponentInstance(
  key: ValueKey(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
);

WireModel _wire(ComponentInstance a, String aPort, ComponentInstance b, String bPort) => WireModel(
  id: '$aPort-$bPort',
  start: PortLocation(nodeKey: a.key, portId: aPort),
  end: PortLocation(nodeKey: b.key, portId: bPort),
);

void main() {
  group('CircuitValidator', () {
    test('flags a reverse-polarity LED', () {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final led = _node(PartNames.led, 'led', const Offset(400, 400));

      // anode -> GND and cathode -> a driven pin == backwards.
      final result = CircuitValidator.validate(
        nodes: [uno, led],
        wires: [_wire(led, 'anode', uno, 'GND_1'), _wire(led, 'cathode', uno, '13')],
      );

      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('backwards'));
      expect(result.updatedProperties[led.key]?[ComponentProps.hasError], isTrue);
    });

    test('flags a short-circuited LED (both legs tied together)', () {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final led = _node(PartNames.led, 'led', const Offset(400, 400));

      final result = CircuitValidator.validate(
        nodes: [uno, led],
        wires: [_wire(led, 'anode', led, 'cathode')],
      );

      expect(result.errorMessage, contains('short-circuited'));
      expect(result.updatedProperties[led.key]?[ComponentProps.hasError], isTrue);
    });

    test('flags a pin shorted directly to ground', () {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final result = CircuitValidator.validate(
        nodes: [uno],
        wires: [_wire(uno, '13', uno, 'GND_1')],
      );

      expect(result.errorMessage, contains('Short Circuit'));
    });

    test('reports no error for a correctly wired LED', () {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final led = _node(PartNames.led, 'led', const Offset(400, 400));
      // With a series resistor, because without one this circuit is not
      // actually correct — a bare LED on a GPIO pin draws ~98 mA, which the
      // validator now reports as an over-current in its own right.
      final resistor = ComponentInstance(
        key: const ValueKey('r'),
        position: const Offset(200, 400),
        part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
        properties: const {ComponentProps.resistance: '220'},
      );

      final result = CircuitValidator.validate(
        nodes: [uno, resistor, led],
        wires: [
          _wire(uno, '13', resistor, 'left'),
          _wire(resistor, 'right', led, 'anode'),
          _wire(led, 'cathode', uno, 'GND_1'),
        ],
      );

      expect(result.errorMessage, isNull);
    });

    test('flags an LED whose series resistor is too small to protect it', () {
      final uno = _node(PartNames.arduinoUno, 'uno');
      final led = _node(PartNames.led, 'led', const Offset(400, 400));
      final resistor = ComponentInstance(
        key: const ValueKey('r'),
        position: const Offset(200, 400),
        part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
        properties: const {ComponentProps.resistance: '100'},
      );

      final result = CircuitValidator.validate(
        nodes: [uno, resistor, led],
        wires: [
          _wire(uno, '13', resistor, 'left'),
          _wire(resistor, 'right', led, 'anode'),
          _wire(led, 'cathode', uno, 'GND_1'),
        ],
      );

      // Caught with nothing compiled and nothing running.
      expect(result.errorMessage, contains('over-current'));
      expect(result.updatedProperties[led.key]?[ComponentProps.hasError], isTrue);
    });

    test('a voltage divider is not a short circuit', () {
      // Two resistors from a pin to ground with the midpoint on A0. The
      // bridged netlist collapses that to "pin touches GND"; the validator
      // must read the unbridged view and stay quiet.
      final uno = _node(PartNames.arduinoUno, 'uno');
      ComponentInstance resistor(String id, double x) => ComponentInstance(
        key: ValueKey(id),
        position: Offset(x, 0),
        part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
        properties: const {ComponentProps.resistance: '10k'},
      );
      final top = resistor('r_top', 200);
      final bottom = resistor('r_bottom', 400);

      final result = CircuitValidator.validate(
        nodes: [uno, top, bottom],
        wires: [
          _wire(uno, '8', top, 'left'),
          _wire(top, 'right', uno, 'A0'),
          _wire(uno, 'A0', bottom, 'left'),
          _wire(bottom, 'right', uno, 'GND_1'),
        ],
      );

      expect(result.errorMessage, isNull);
    });
  });
}
