import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/logic/part_logic.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/engine_pin_api.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/core/updaters/part_behavior_frame_updater.dart';

/// What a part remembers between frames.
///
/// The bug this pins was invisible on the web and total on native. A part's
/// state used to persist by being written into the node's property map and
/// read back the next frame — which works only when the engine reads the same
/// live canvas it writes to, as the inline (web) engine does. The isolate's
/// output is write-only: it sends updates to the UI and its own node list
/// never sees them, so every frame started from scratch. An OLED went black
/// the frame after `display.begin()` switched it on, and a PIR sensor's hold
/// could never outlast a single frame.
///
/// So the memory is the engine's own `lastState`, and this runs the updater
/// the way the isolate does — never writing anything back onto the nodes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A part with a logic and no `.pdl`, like the LED, servo and display.
  ComponentInstance nodeFor(String logic) => ComponentInstance(
    position: Offset.zero,
    part: PartModel(name: 'Test Part', size: const Size(16, 16), logic: logic),
  );

  void runFrame(ComponentInstance node, Map<LocalKey, Map<String, Object?>> lastState) =>
      PartBehaviorFrameUpdater.update(
        nodes: [node],
        spiceEngine: SpiceEngine(),
        isSpiceActive: false,
        lastState: lastState,
        elapsed: Duration.zero,
        netlist: CircuitNetlist(),
        unoNode: null,
        measurements: EmulatorMeasurements(),
        queueUpdate: (_, _) {},
      );

  setUp(PartLogicRegistry.reset);
  tearDown(PartLogicRegistry.reset);

  test('a logic sees what it wrote last frame, with nothing written back', () {
    PartLogicRegistry.register('counter', (context) {
      final seen = context.state['ticks'];
      context.state['ticks'] = (seen is num ? seen.toInt() : 0) + 1;
    });

    final node = nodeFor('counter');
    final lastState = <LocalKey, Map<String, Object?>>{};
    for (var i = 0; i < 5; i++) {
      runFrame(node, lastState);
    }

    expect(
      lastState[node.key]?['ticks'],
      5,
      reason: 'each frame started over instead of continuing from the last',
    );
    expect(
      node.properties['ticks'],
      isNull,
      reason: 'the memory must not depend on the output writing back',
    );
  });

  test('a fresh run does not inherit the previous run at the canvas', () {
    // The node's property map still holds where the last run finished — the
    // canvas keeps showing a stopped display's final picture, which is what a
    // real one does. A new run must not resume from it, and cannot: the
    // engine clears `lastState` when it starts.
    PartLogicRegistry.register('counter', (context) {
      final seen = context.state['ticks'];
      context.state['ticks'] = (seen is num ? seen.toInt() : 0) + 1;
    });

    final node = nodeFor('counter')..properties['ticks'] = 99;
    final lastState = <LocalKey, Map<String, Object?>>{};
    runFrame(node, lastState);

    expect(lastState[node.key]?['ticks'], 100, reason: 'the first frame reads the canvas');

    lastState.clear(); // what SimulationEngine.start does
    runFrame(node, lastState);
    expect(lastState[node.key]?['ticks'], 100);
  });

  test("a .pdl part's STATE starts from its declared value, not the last run's", () async {
    // PDL.md promises STATE is "recreated from its initial value every time a
    // simulation starts". The canvas still holds where the last run ended — here
    // a PIR whose hold ran far past the end of that run — and the evaluator
    // used to seed state from it, so the new run began already triggered.
    await PartRegistry.initializeAsync();
    final pir = ComponentInstance(
      position: Offset.zero,
      part: PartModel(name: 'PIR Motion Sensor', size: const Size(128, 96), definitionId: 'pir_sensor'),
      properties: {'triggered': false, 'active': true, 'holdUntilMs': 1e9},
    );
    final lastState = <LocalKey, Map<String, Object?>>{};

    runFrame(pir, lastState);

    expect(lastState[pir.key]?['active'], isFalse);
  });
}
