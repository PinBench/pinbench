// Requires a local `arduino-cli` toolchain to compile the sketch, so it is
// tagged 'arduino' and skipped in CI (`flutter test --exclude-tags arduino`).
@Tags(['arduino'])
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// End-to-end regression for "LED blink stops working after a re-run".
///
/// Unlike the frame-stepped blink test, this drives the **real-time
/// [SimulationEngine.start] run loop** — the exact production path that had the
/// double-loop bug — then does a quick stop → restart and asserts the LED keeps
/// blinking while only ONE loop is ever active.

class _CapturingOutput implements SimulationOutput {
  _CapturingOutput(this._nodes, this._wires);
  final List<ComponentInstance> _nodes;
  final List<WireModel> _wires;

  @override
  List<ComponentInstance> get simulationNodes => _nodes;
  @override
  List<WireModel> get simulationWires => _wires;

  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final entry in updates.entries) {
      final i = _nodes.indexWhere((n) => n.key == entry.key);
      if (i != -1) {
        final merged = {..._nodes[i].properties, ...entry.value};
        _nodes[i] = _nodes[i].copyWith(properties: merged);
      }
    }
  }

  bool ledIsOn(LocalKey ledKey) =>
      _nodes.firstWhere((n) => n.key == ledKey).properties['isOn'] == true;
}

ComponentInstance _node(String name, String id, [Map<String, dynamic>? props]) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: name, size: const Size(40, 40)),
  properties: props,
);

({List<ComponentInstance> nodes, List<WireModel> wires, LocalKey ledKey}) _blinkCircuit() {
  final uno = _node(PartNames.arduinoUno, 'uno');
  final led = _node(PartNames.led, 'led1', {'Color': 'Red', 'isOn': false});
  final wires = <WireModel>[
    WireModel(
      id: 'w_anode',
      start: PortLocation(nodeKey: uno.key, portId: '13'),
      end: PortLocation(nodeKey: led.key, portId: 'anode'),
    ),
    WireModel(
      id: 'w_cathode',
      start: PortLocation(nodeKey: led.key, portId: 'cathode'),
      end: PortLocation(nodeKey: uno.key, portId: 'GND_1'),
    ),
  ];
  return (nodes: [uno, led], wires: wires, ledKey: led.key);
}

void main() {
  patrolWidgetTest('Blink: real run loop keeps blinking after stop → restart, single loop only', (
    $,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('blink_rt_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final hex = await $.tester.runAsync(() async {
      final source = File('assets/templates/blink/blink.ino').readAsStringSync();
      final dir = Directory('${tempDir.path}/blink')..createSync(recursive: true);
      File('${dir.path}/blink.ino').writeAsStringSync(source);
      return CompilerService.compileWorkspace(dir.path);
    });
    expect(hex, isNotNull);

    final circuit = _blinkCircuit();
    final out = _CapturingOutput(circuit.nodes, circuit.wires);
    final engine = SimulationEngine(output: out);

    Future<int> runUntilBlinks({required int target}) async {
      var rises = 0;
      var prevOn = out.ledIsOn(circuit.ledKey);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (rises < target && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The invariant that prevents the bug: never more than one loop.
        expect(engine.activeLoopCount, lessThanOrEqualTo(1));
        final on = out.ledIsOn(circuit.ledKey);
        if (on && !prevOn) rises++;
        prevOn = on;
      }
      return rises;
    }

    await $.tester.runAsync(() async {
      // ---- Run 1 (real loop) ----
      await engine.start(hex!, onStop: () {});
      expect(engine.activeLoopCount, 1);
      final run1 = await runUntilBlinks(target: 2);
      expect(run1, greaterThanOrEqualTo(2), reason: 'LED should blink on run 1');

      // ---- Quick stop → restart: the exact bug trigger ----
      engine.stop();
      await engine.start(hex, onStop: () {});
      expect(engine.activeLoopCount, 1, reason: 'restart must not leave two loops');

      final run2 = await runUntilBlinks(target: 2);
      expect(
        run2,
        greaterThanOrEqualTo(2),
        reason: 'REGRESSION: LED must keep blinking through the real run loop after restart',
      );

      engine.stop();
      await engine.loopDone;
      expect(engine.activeLoopCount, 0);
    });
  });
}
