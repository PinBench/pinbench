import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/wire_model.dart';

void main() {
  group('WireModel.generateId', () {
    test('produces unique ids even when generated back-to-back', () {
      final ids = List.generate(1000, (_) => WireModel.generateId());
      expect(ids.toSet().length, ids.length);
    });

    test('is namespaced with a "wire_" prefix', () {
      expect(WireModel.generateId(), startsWith('wire_'));
    });
  });
}
