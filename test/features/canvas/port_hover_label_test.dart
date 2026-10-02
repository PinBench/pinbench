import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/canvas/utils/canvas_geometry.dart';
import 'package:pinbench/features/canvas/widgets/core/port_hover_label.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/painters/breadboard_painter/breadboard_painter.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_ui/theme/testing.dart';

/// The pin name shown over a hovered pin: what it says for each way a part
/// declares its ports, and where it sits as the canvas pans and zooms.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PartRegistry.initializeAsync);

  ComponentInstance place(String name, String id) => ComponentInstance(
    key: ValueKey(id),
    position: Offset.zero,
    part: standardParts.firstWhere((p) => p.name == name).clone(),
  );

  String? nameOf(ComponentInstance node, String portId) =>
      CanvasGeometry.getPortName(PortLocation(nodeKey: node.key, portId: portId), [node]);

  group('getPortName', () {
    test("a board's pins by the names printed on it", () {
      final pico = place(PartNames.picoW, 'pico');
      expect(nameOf(pico, '15'), 'GP15');
      expect(nameOf(pico, '5V'), 'VBUS');
      expect(nameOf(pico, '28'), 'GP28 (A2)');
      expect(nameOf(pico, 'GND_7'), 'AGND');
      expect(nameOf(place(PartNames.arduinoUno, 'uno'), 'A0'), 'A0');
    });

    test("a painted part's ports", () {
      expect(nameOf(place(PartNames.led, 'led'), 'anode'), 'Anode');
    });

    test("a .pdl part's pins", () {
      final definition = PartRegistry.getPart('ir_receiver')!;
      final receiver = ComponentInstance(
        key: const ValueKey('ir'),
        position: Offset.zero,
        part: PartModel.fromDefinition(definition),
      );
      final pin = definition.pins.first;
      expect(nameOf(receiver, pin.id), pin.name);
    });

    test('a breadboard hole, which the board finds by position rather than listing', () {
      final board = place(PartNames.breadboardHalf, 'bb');
      final painter = board.part.getPainter()! as BreadboardPainter;
      final hole = painter.getPortAt(painter.nearestHoles(const Offset(120, 120)).last)!;
      expect(hole.name, startsWith('Terminal Strip'));
      expect(nameOf(board, hole.id), hole.name);
    });

    test('nothing for a port or node that is not there', () {
      final led = place(PartNames.led, 'led');
      expect(nameOf(led, 'gate'), isNull);
      expect(
        CanvasGeometry.getPortName(const PortLocation(nodeKey: ValueKey('gone'), portId: 'anode'), [
          led,
        ]),
        isNull,
      );
    });
  });

  group('PortHoverLabel', () {
    Future<Rect> chipAt(WidgetTester tester, ValueNotifier<Matrix4> viewer) async {
      await tester.pumpWidget(
        appTestApp(
          Stack(
            children: [
              PortHoverLabel(name: 'GP15', canvasPosition: const Offset(100, 200), viewer: viewer),
            ],
          ),
        ),
      );
      return tester.getRect(find.byType(DecoratedBox).last);
    }

    testWidgets('sits centred just above the pin', (tester) async {
      final viewer = ValueNotifier(Matrix4.identity());
      addTearDown(viewer.dispose);
      final chip = await chipAt(tester, viewer);

      expect(find.text('GP15'), findsOneWidget);
      expect(chip.center.dx, closeTo(100, 0.5));
      expect(chip.bottom, closeTo(200 - PortHoverLabel.gap, 0.5));
    });

    testWidgets('follows a pan and zoom, at the same size', (tester) async {
      final viewer = ValueNotifier(Matrix4.identity());
      addTearDown(viewer.dispose);
      final before = await chipAt(tester, viewer);

      // Zoomed to 2x and panned: the pin is now at (100·2 + 30, 200·2 + 40).
      viewer.value = Matrix4.identity()
        ..translateByDouble(30, 40, 0, 1)
        ..scaleByDouble(2, 2, 1, 1);
      await tester.pump();
      final after = tester.getRect(find.byType(DecoratedBox).last);

      expect(after.center.dx, closeTo(230, 0.5));
      expect(after.bottom, closeTo(440 - PortHoverLabel.gap, 0.5));
      expect(after.size, before.size, reason: 'readable at any zoom: a screen-space label');
    });
  });
}
