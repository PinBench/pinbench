import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/logic/ssd1306.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/isolate/sim_isolate.dart';
import 'package:pinbench_sim/isolate/sim_messages.dart';

/// Drives the REAL sim isolate with the OLED template and verifies the display
/// keeps showing its picture.
///
/// The reported symptom was "something for a split second, then black", and it
/// only ever happened here — on native, in the isolate. Everything else passed:
/// the protocol decoded correctly, the part logic ran, and the whole chain
/// worked when the engine ran inline the way the web build runs it. What
/// differs is the output. Inline, it writes updates into the live canvas the
/// engine also reads, so whatever a part left in its state map came back the
/// next frame. The isolate's output only *sends*; its own nodes never see the
/// update. So the display was rebuilt from nothing every frame, and only the
/// frame carrying `display.begin()`'s "switch on" command ever had a panel to
/// draw into.
///
/// Nothing short of the real isolate would have caught it, which is why this
/// test spawns one rather than calling the engine directly.
void main() {
  patrolWidgetTest('sim isolate: the OLED keeps its picture after the first frame', ($) async {
    final circuit = CircuitParser.applyToCanvas(
      CircuitParser.parse(File('assets/templates/oled/circuit.cdl').readAsStringSync()),
      standardParts,
    );
    final hex = File('assets/templates/oled/oled.ino.hex').readAsStringSync();
    final oled = circuit.nodes.firstWhere((n) => n.part.name == PartNames.oledDisplay);
    final oledId = nodeKeyToId(oled.key);

    await $.tester.runAsync(() async {
      final fromSim = ReceivePort();
      addTearDown(fromSim.close);
      SendPort? toSim;

      final frames = <String>[];
      final ready = Completer<void>();
      final stopped = StreamController<void>.broadcast();
      addTearDown(stopped.close);

      fromSim.listen((m) {
        if (m is IsolateReady) {
          toSim = m.commandPort;
          ready.complete();
        } else if (m is FrameUpdates) {
          final frame = m.updates[oledId]?[ComponentProps.oledFrame];
          if (frame is String) frames.add(frame);
        } else if (m is SimStopped) {
          stopped.add(null);
        }
      });

      final isolate = await Isolate.spawn(simIsolateMain, fromSim.sendPort);
      addTearDown(() => isolate.kill(priority: Isolate.immediate));
      await ready.future;

      toSim!.send(
        StartSim(
          hex: hex,
          nodesJson: [for (final n in circuit.nodes) n.toJson()],
          wiresJson: [for (final w in circuit.wires) w.toJson()],
        ),
      );

      // The sketch redraws twice a second, so a few seconds is several frames
      // even on a slow machine.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (frames.length < 4 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      toSim!.send(StopSim());
      await stopped.stream.first.timeout(const Duration(seconds: 5));

      expect(frames.length, greaterThanOrEqualTo(4), reason: 'the display stopped being written');

      // The regression, stated the way it looked: the picture arrives and then
      // every frame after it is a dark panel. So the *last* frames are the ones
      // worth asserting on — the first was never the problem.
      for (final frame in frames.sublist(frames.length - 3)) {
        final display = Ssd1306Controller.unpack(frame);
        expect(
          display.displayOn,
          isTrue,
          reason: 'REGRESSION: the panel switched itself off after the frame that lit it',
        );
        var lit = 0;
        for (var y = 0; y < Ssd1306Controller.height; y++) {
          for (var x = 0; x < Ssd1306Controller.width; x++) {
            if (display.pixelAt(x, y)) lit++;
          }
        }
        expect(lit, greaterThan(100), reason: 'REGRESSION: a late frame came through blank');
      }
    });
  });
}
