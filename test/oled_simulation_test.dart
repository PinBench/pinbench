/// End-to-end OLED display test: loads the bundled OLED template (circuit plus
/// the compiled `Adafruit_SSD1306` sketch), steps the engine frame by frame,
/// and asserts real pixels light up.
///
/// This covers the whole chain and is the only test that does: the sketch's
/// `Wire` calls drive the emulated TWI peripheral, the recorder turns bus
/// events into transactions, the part logic claims its address and drains
/// them, `Ssd1306Controller` decodes the protocol, and the result lands on the
/// canvas as a component property. Every link is unit-tested on its own; only
/// this one proves they are joined up, and that what a real Arduino library
/// actually transmits is what the peripheral actually understands.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/logic/ssd1306.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';

class _RecordingOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  final frames = <String>[];

  /// Deliberately write-only, like the real isolate's output.
  ///
  /// This is the difference between the two platforms, and it used to hide a
  /// bug that only appeared on native. On the web the engine runs inline and
  /// its output writes into the live canvas it also reads, so anything a logic
  /// left in its state map came back next frame. In the isolate the output
  /// only *sends* — its own node list never sees the update — so a part that
  /// leaned on that round trip had no memory at all, and a display went black
  /// the frame after the one that switched it on. The engine has to keep its
  /// own memory, and mirroring the stricter output here is what proves it.
  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {
    for (final props in updates.values) {
      final frame = props[ComponentProps.oledFrame];
      if (frame is String) frames.add(frame);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The sketch draws in `setup()` and then again every second in `loop()`;
  /// two simulated seconds covers both.
  const cyclesPerFrame = 256000; // 16 ms at 16 MHz
  const frameCount = 125;

  _RecordingOutput run(String circuitPath) {
    final source = File(circuitPath).readAsStringSync();
    final circuit = CircuitParser.applyToCanvas(CircuitParser.parse(source), standardParts);
    final hex = File('assets/templates/oled/oled.ino.hex').readAsStringSync();

    final output = _RecordingOutput(circuit.nodes, circuit.wires);
    final engine = SimulationEngine(output: output)..prepareForFrameStepping(hex);
    for (var i = 0; i < frameCount; i++) {
      engine.runFrame(cycles: cyclesPerFrame, solveSpice: false);
    }
    engine.stop();
    return output;
  }

  test('an Adafruit sketch lights real pixels on the display', () {
    final output = run('assets/templates/oled/circuit.cdl');

    expect(output.frames, isNotEmpty, reason: 'the display was never written to');

    final display = Ssd1306Controller.unpack(output.frames.last);
    expect(display.displayOn, isTrue, reason: 'begin() should have switched the panel on');

    var lit = 0;
    for (var y = 0; y < Ssd1306Controller.height; y++) {
      for (var x = 0; x < Ssd1306Controller.width; x++) {
        if (display.pixelAt(x, y)) lit++;
      }
    }
    // Text and a progress bar: hundreds of pixels, not the whole panel.
    expect(lit, greaterThan(100), reason: 'only $lit pixels lit — the screen is effectively blank');
    expect(lit, lessThan(Ssd1306Controller.width * Ssd1306Controller.height ~/ 2));
  });

  test('the picture changes as the sketch redraws', () {
    final output = run('assets/templates/oled/circuit.cdl');

    // The sketch redraws an uptime counter and a sweeping bar once a second,
    // so a run of this length must produce more than one distinct picture. One
    // distinct frame would mean the display froze after its first write.
    expect(output.frames.toSet().length, greaterThan(1));
  });

  test('a display wired to the wrong pins stays dark', () {
    final wrong = File('${Directory.systemTemp.path}/oled_miswired.cdl')
      ..writeAsStringSync(
        File('assets/templates/oled/circuit.cdl')
            .readAsStringSync()
            .replaceFirst('to: uno.A4;', 'to: uno.9;'),
      );

    final output = run(wrong.path);

    expect(
      output.frames,
      isEmpty,
      reason: 'the bus is global, so an unwired display must refuse the traffic itself',
    );
  });
}
