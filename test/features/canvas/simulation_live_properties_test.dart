import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench/features/canvas/widgets/components/component_widget.dart';
import 'package:pinbench/features/canvas/widgets/core/canvas_node_widget.dart';
import '../../support/harness.dart';

/// A running simulation writes visual state — an LED's `isOn`, a servo's angle,
/// an OLED's picture — at 60fps. It used to write it into the canvas *state*,
/// which replaced the node list and notified every watcher of the canvas
/// provider: the whole canvas subtree rebuilt, the minimap repainted every
/// node, and the toolbar recomputed its enabled flags, sixty times a second,
/// to light one LED.
ComponentInstance _led(String id) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: 'LED', size: const Size(40, 40)),
  properties: {'Color': 'Red'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a simulation frame does not notify the canvas', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(canvasControllerProvider.notifier);

    final led = _led('led');
    controller.updateState(nodes: [led]);

    var canvasNotifications = 0;
    container.listen(canvasControllerProvider, (_, _) => canvasNotifications++);

    controller.batchSimulationUpdate({
      led.key: const {'isOn': true},
    });

    expect(canvasNotifications, 0, reason: 'a frame of visual state is not a canvas change');
    expect(controller.liveProperties(led.key).value['isOn'], isTrue);
    // And it stays out of what gets saved and undone.
    expect(controller.nodes.single.properties.containsKey('isOn'), isFalse);
  });

  test('keys the engine does not send survive, and dead nodes are dropped', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(canvasControllerProvider.notifier);

    final led = _led('led');
    controller.updateState(nodes: [led]);
    controller
      ..batchSimulationUpdate({
        led.key: const {'isOn': true, 'brightness': 1.0},
      })
      ..batchSimulationUpdate({
        led.key: const {'isOn': false},
      });

    // The engine sends only what changed, so the rest of the overlay stands.
    expect(controller.liveProperties(led.key).value, {'isOn': false, 'brightness': 1.0});

    // Opening another circuit must not leave the old part's state behind.
    controller.updateState(nodes: [_led('other')]);
    expect(controller.liveProperties(led.key).value, isEmpty);
  });

  testWidgets('the component draws with the live state merged over its own', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(canvasControllerProvider.notifier);

    final led = _led('led');
    controller.updateState(nodes: [led]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appTestApp(CanvasNodeWidget(node: led, controller: controller)),
      ),
    );

    Map<String, dynamic> drawnWith() =>
        tester.widgetList<ComponentWidget>(find.byType(ComponentWidget)).first.properties ?? {};

    expect(drawnWith()['isOn'], isNull);

    controller.batchSimulationUpdate({
      led.key: const {'isOn': true},
    });
    await tester.pump();

    expect(drawnWith()['isOn'], isTrue, reason: 'the LED should light');
    expect(drawnWith()['Color'], 'Red', reason: "the user's colour must survive the frame");
  });
}
