import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/painters/potentiometer_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';

void main() {
  group('PotentiometerPainter.position', () {
    test('defaults to mid-travel', () {
      expect(PotentiometerPainter().position, 0.5);
    });

    test('parses a string value and clamps to 0..1', () {
      expect(
        PotentiometerPainter(
          properties: const {ComponentProps.potentiometerValue: '0.25'},
        ).position,
        0.25,
      );
      expect(
        PotentiometerPainter(properties: const {ComponentProps.potentiometerValue: '2'}).position,
        1.0,
      );
      expect(
        PotentiometerPainter(properties: const {ComponentProps.potentiometerValue: '-1'}).position,
        0.0,
      );
    });

    test('exposes term1 / wiper / term2 ports', () {
      final ids = PotentiometerPainter().getPorts().map((p) => p.id).toList();
      expect(ids, containsAll(['term1', 'wiper', 'term2']));
    });
  });

  test('potentiometer is registered as a standard component', () {
    expect(standardParts.any((c) => c.name == PartNames.potentiometer), isTrue);
  });

  test('a placed potentiometer defaults to a mid Position property', () {
    final model = standardParts.firstWhere((c) => c.name == PartNames.potentiometer);
    final node = ComponentInstance(position: Offset.zero, part: model);
    expect(node.properties[ComponentProps.potentiometerValue], '0.5');
  });
}
