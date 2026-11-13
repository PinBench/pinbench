import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/painters/led_painter.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/features/canvas/controller/canvas_controller.dart';
import 'package:pinbench/features/canvas/widgets/core/canvas.dart' as fap;

import '../../support/harness.dart';
import '../../support/simulation_bindings.dart';

/// A run leaves its last frame behind in the live overlay, drawn over each
/// part's own properties — and a part driven by Dart logic reports its whole
/// property map as state, so that overlay held the part's `Color` too. Every
/// edit after a run, from the properties panel or the `.cdl`, was drawn
/// underneath it: the LED stayed the colour it ran in until the next run.
final _shot = GlobalKey();

PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  late ProviderContainer container;
  late CanvasController controller;

  setUp(() {
    container = ProviderContainer(overrides: fakeSimulationBindings());
    controller = container.read(canvasControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  ComponentInstance led() => ComponentInstance(
    position: const Offset(200, 200),
    part: _model(PartNames.led),
    properties: {'Color': 'Red'},
  );

  /// What a run leaves in the overlay: the part's properties echoed back, and
  /// the LED switched off.
  void runAndStop(ComponentInstance node) => controller.batchSimulationUpdate({
    node.key: {...node.properties, 'isOn': false},
  });

  group('the live overlay after a run', () {
    test('drops a property the user changes, and keeps the run-only keys', () {
      final node = led();
      controller.updateState(nodes: [node]);
      runAndStop(node);

      controller.updateNodeProperties(node.key, {...node.properties, 'Color': 'Green'});

      expect(controller.liveProperties(node.key).value, {'isOn': false});
    });

    test('drops it when the .cdl replaces the circuit with the part kept', () {
      final node = led();
      controller.updateState(nodes: [node]);
      runAndStop(node);

      controller.updateCircuit([
        node.copyWith(properties: {'Color': 'Blue'}),
      ], const []);

      expect(controller.liveProperties(node.key).value.containsKey('Color'), isFalse);
    });

    test('drops it again when an edit is undone', () {
      final node = led();
      controller.updateState(nodes: [node]);
      controller.updateNodeProperties(node.key, {'Color': 'Green'});
      runAndStop(controller.nodes.single);

      controller.undo();

      expect(controller.nodes.single.properties['Color'], 'Red');
      expect(controller.liveProperties(node.key).value.containsKey('Color'), isFalse);
    });

    test('is untouched by a drag, which keeps the property map', () {
      final node = led();
      controller.updateState(nodes: [node]);
      runAndStop(node);
      final before = controller.liveProperties(node.key).value;

      controller.updateState(nodes: [node.copyWith(position: const Offset(300, 200))]);

      expect(identical(controller.liveProperties(node.key).value, before), isTrue);
    });
  });

  testWidgets('an LED recoloured after a run changes colour on screen at once', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final node = led();
    controller.updateState(nodes: [node]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: _shot, child: appTestApp(const fap.Canvas())),
      ),
    );
    await tester.pumpAndSettle();
    runAndStop(node);
    await tester.pumpAndSettle();

    final ledPaint = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is LEDPainter && !(w.painter! as LEDPainter).isOutline,
    );
    // The lens, just above the body's centre, clear of the legs.
    final lens = tester.getCenter(ledPaint) - const Offset(0, 10);

    Future<(int, int, int)> pixel() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        // Raw RGBA, the default.
        final data = (await image.toByteData())!;
        final i = (lens.dy.round() * image.width + lens.dx.round()) * 4;
        return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      }))!;
    }

    final (r0, g0, _) = await pixel();
    expect(r0, greaterThan(g0), reason: 'starts red');

    controller.updateNodeProperties(node.key, {...node.properties, 'Color': 'Green'});
    await tester.pumpAndSettle();

    final (r1, g1, _) = await pixel();
    expect(g1, greaterThan(r1), reason: 'turns green without another run');
  });
}
