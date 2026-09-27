import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  group('ComponentInstance JSON round-trip', () {
    test('preserves geometry, flips and properties', () {
      final original = ComponentInstance(
        position: const Offset(12.5, -33.0),
        part: _model(PartNames.led),
        rotationAngle: 1.5708,
        flipHorizontal: true,
        customWidth: 64,
        customHeight: 48,
        properties: {ComponentProps.color: 'Green'},
      );

      final restored = ComponentInstance.fromJson(original.toJson());

      expect(restored.position, original.position);
      expect(restored.rotationAngle, original.rotationAngle);
      expect(restored.flipHorizontal, isTrue);
      expect(restored.flipVertical, isFalse);
      expect(restored.customWidth, 64);
      expect(restored.customHeight, 48);
      expect(restored.part.name, PartNames.led);
      expect(restored.properties[ComponentProps.color], 'Green');
    });

    test('preserves the node id (key)', () {
      final original = ComponentInstance(position: Offset.zero, part: _model(PartNames.resistor));
      final restored = ComponentInstance.fromJson(original.toJson());
      expect((restored.key as ValueKey).value, (original.key as ValueKey).value);
    });
  });

  group('WireModel JSON round-trip', () {
    test('preserves endpoints, bend points and color', () {
      final original = WireModel(
        id: WireModel.generateId(),
        start: const PortLocation(nodeKey: ValueKey('a'), portId: '13'),
        end: const PortLocation(nodeKey: ValueKey('b'), portId: 'anode'),
        bendPoints: const [Offset(1, 2), Offset(3, 4)],
        color: const Color(0xFF112233),
      );

      final restored = WireModel.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.start.portId, '13');
      expect(restored.end.portId, 'anode');
      expect(restored.bendPoints, original.bendPoints);
      expect(restored.color.toARGB32(), original.color.toARGB32());
    });
  });
}
