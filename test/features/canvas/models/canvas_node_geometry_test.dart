import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Builds a node with an explicit base size (via customWidth/Height) so geometry
/// can be checked without needing a painter.
ComponentInstance _sized(double w, double h, {double rotation = 0}) => ComponentInstance(
  position: const Offset(100, 200),
  part: PartModel(name: PartNames.led, size: Size(w, h)),
  customWidth: w,
  customHeight: h,
  rotationAngle: rotation,
);

void main() {
  group('ComponentInstance geometry', () {
    test('unrotated size equals the base size', () {
      final node = _sized(60, 20);
      expect(node.currentSize.width, closeTo(60, 0.001));
      expect(node.currentSize.height, closeTo(20, 0.001));
    });

    test('90° rotation swaps width and height of the bounding box', () {
      final node = _sized(60, 20, rotation: math.pi / 2);
      expect(node.currentSize.width, closeTo(20, 0.001));
      expect(node.currentSize.height, closeTo(60, 0.001));
    });

    test('180° rotation preserves the bounding-box size', () {
      final node = _sized(60, 20, rotation: math.pi);
      expect(node.currentSize.width, closeTo(60, 0.001));
      expect(node.currentSize.height, closeTo(20, 0.001));
    });

    test('pivotOffset for an unrotated node is (width/2, 0)', () {
      final node = _sized(60, 20);
      expect(node.pivotOffset.dx, closeTo(30, 0.001));
      expect(node.pivotOffset.dy, closeTo(0, 0.001));
    });

    test('rect combines position and current size', () {
      final node = _sized(40, 40);
      expect(node.rect, const Rect.fromLTWH(100, 200, 40, 40));
    });

    test('customWidth/customHeight override the component size', () {
      final node = ComponentInstance(
        position: Offset.zero,
        part: PartModel(name: PartNames.led, size: const Size(40, 40)),
        customWidth: 80,
        customHeight: 10,
      );
      expect(node.baseSize, const Size(80, 10));
    });
  });
}
