// Requires a local `arduino-cli` toolchain, so tagged 'arduino'.
@Tags(['arduino'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/isolate/sim_isolate.dart';
import 'package:pinbench_sim/isolate/sim_messages.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Faithful reproduction of the production simulation path: drives the REAL sim
/// isolate (spawned) with StartSim → StopSim → StartSim and verifies the LED
/// keeps toggling (isOn AND a visible brightness) on the SECOND run — exactly
/// the "blinks once then stays off after the first simulation" report.

ComponentInstance _node(String name, String id, [Map<String, dynamic>? props]) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: name, size: const Size(40, 40)),
  properties: props,
);

void main() {
  patrolWidgetTest('sim isolate: LED keeps blinking after stop → restart', ($) async {
    final tempDir = Directory.systemTemp.createTempSync('iso_blink_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final hex = await $.tester.runAsync(() async {
      final source = File('assets/templates/blink/blink.ino').readAsStringSync();
      final dir = Directory('${tempDir.path}/blink')..createSync(recursive: true);
      File('${dir.path}/blink.ino').writeAsStringSync(source);
      return CompilerService.compileWorkspace(dir.path);
    });
    expect(hex, isNotNull);

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
    final nodesJson = [uno.toJson(), led.toJson()];
    final wiresJson = [for (final w in wires) w.toJson()];
    final ledId = nodeKeyToId(led.key);

    await $.tester.runAsync(() async {
      final fromSim = ReceivePort();
      addTearDown(fromSim.close);
      SendPort? toSim;
      final ledOn = <bool>[]; // chronological isOn values observed for the LED
      var lastBrightnessWhenOn = -1.0;
      final ready = Completer<void>();
      final stopped = StreamController<void>.broadcast();
      addTearDown(stopped.close);

      fromSim.listen((m) {
        if (m is IsolateReady) {
          toSim = m.commandPort;
          ready.complete();
        } else if (m is FrameUpdates) {
          final u = m.updates[ledId];
          if (u != null && u.containsKey('isOn')) {
            final on = u['isOn'] == true;
            ledOn.add(on);
            if (on && u['brightness'] is num) {
              lastBrightnessWhenOn = (u['brightness'] as num).toDouble();
            }
          }
        } else if (m is SimStopped) {
          stopped.add(null);
        }
      });

      final isolate = await Isolate.spawn(simIsolateMain, fromSim.sendPort);
      addTearDown(() => isolate.kill(priority: Isolate.immediate));
      await ready.future;

      Future<int> waitRises({required int target}) async {
        var rises = 0;
        var prev = false;
        var seen = 0;
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (rises < target && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          for (; seen < ledOn.length; seen++) {
            final on = ledOn[seen];
            if (on && !prev) rises++;
            prev = on;
          }
        }
        return rises;
      }

      // ---- Run 1 ----
      toSim!.send(StartSim(hex: hex!, nodesJson: nodesJson, wiresJson: wiresJson));
      final run1 = await waitRises(target: 2);
      expect(run1, greaterThanOrEqualTo(2), reason: 'LED should blink on run 1');

      // ---- Stop ----
      toSim!.send(StopSim());
      await stopped.stream.first.timeout(const Duration(seconds: 5));

      // ---- Run 2 (the regression) ----
      ledOn.clear();
      lastBrightnessWhenOn = -1.0;
      toSim!.send(StartSim(hex: hex, nodesJson: nodesJson, wiresJson: wiresJson));
      final run2 = await waitRises(target: 3);
      expect(
        run2,
        greaterThanOrEqualTo(3),
        reason: 'REGRESSION: LED must keep blinking after stop → restart (isolate path)',
      );
      expect(
        lastBrightnessWhenOn,
        greaterThan(0.0),
        reason: 'a lit LED must report brightness > 0 so it renders, not dark',
      );

      toSim!.send(StopSim());
      await stopped.stream.first.timeout(const Duration(seconds: 5));
    });
  });
}
