import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';

PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  group('ComponentInstance default properties', () {
    test('an LED defaults to the canonical capitalized Color key', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.led));
      expect(node.properties[ComponentProps.color], 'Red');
      // No legacy lowercase key should leak into the defaults.
      expect(node.properties.containsKey('color'), isFalse);
    });

    test('a Resistor defaults to the canonical Resistance key', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      expect(node.properties[ComponentProps.resistance], '220');
    });

    test('a component without defaults has an empty property map', () {
      final node = ComponentInstance(position: Offset.zero, part: _model(PartNames.pushButton));
      expect(node.properties, isEmpty);
    });
  });

  group('ComponentInstance ids', () {
    test('are unique even when many nodes are created back-to-back', () {
      final model = _model(PartNames.led);
      final ids = List.generate(
        1000,
        (_) => (ComponentInstance(position: Offset.zero, part: model).key as ValueKey).value,
      );
      expect(ids.toSet().length, ids.length);
    });
  });

  group('ComponentProps.runtimeFlags', () {
    test('contains every simulation-written flag so the editor hides them', () {
      expect(
        ComponentProps.runtimeFlags,
        containsAll(<String>[
          ComponentProps.isOn,
          ComponentProps.hasError,
          ComponentProps.isDigitalHigh,
          ComponentProps.isPressed,
          ComponentProps.frequency,
        ]),
      );
    });

    test('does not hide user-editable display properties', () {
      expect(ComponentProps.runtimeFlags, isNot(contains(ComponentProps.color)));
      expect(ComponentProps.runtimeFlags, isNot(contains(ComponentProps.resistance)));
    });
  });
}
