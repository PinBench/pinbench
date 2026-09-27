// Requires a local `arduino-cli` toolchain to compile the sketch, so it is
// tagged 'arduino' and skipped in environments without it (e.g. CI via
// `flutter test --exclude-tags arduino`).
@Tags(['arduino'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';
import 'package:pinbench/features/workspace/services/compiler_service.dart';
import 'package:pinbench_parts/painters/led_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Drives the **real** [SimulationEngine] against the Blink template circuit and
/// asserts that the external LED *component* blinks repeatedly — its painter
/// `isOn`/glow state toggling, which is what the user actually sees on the
/// canvas — and that it keeps blinking after a stop → restart.
///
/// The whole production analog path now runs headless thanks to the pure-Dart
/// `ngspice_dart`: arduino-cli compiles the sketch, `avr8_dart` runs it, and the
/// pure-Dart SPICE engine solves the LED current each frame. Frames are stepped
/// deterministically via [SimulationEngine.runFrame] so the test never depends
/// on wall-clock pacing.

/// A [SimulationOutput] that folds the engine's visual writes back onto the
/// circuit nodes — faithfully mirroring `CanvasController.batchSimulationUpdate`.
///
/// Crucially it **replaces** the node object via `copyWith` (and **merges** the
/// partial property update) rather than mutating in place. This reproduces the
/// production behaviour that makes any node reference the engine cached at
/// start-time go stale — the exact condition behind the "LED misbehaves on
/// re-run" bug. A fake that mutated in place would mask the regression.
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

  /// The LED painter glows when `isOn` is true (see [LEDPainter]).
  bool ledIsOn(LocalKey ledKey) =>
      _nodes.firstWhere((n) => n.key == ledKey).properties['isOn'] == true;
}

ComponentInstance _node(String name, String id, [Map<String, dynamic>? props]) => ComponentInstance(
  key: ValueKey(id),
  position: Offset.zero,
  part: PartModel(name: name, size: const Size(40, 40)),
  properties: props,
);

/// Builds the Blink template circuit: Arduino pin 13 → LED anode, LED cathode →
/// Arduino GND (mirrors `assets/templates/blink/circuit.cdl`).
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

/// Steps the engine frame-by-frame until the LED has switched ON [targetRises]
/// times (a blink) or [maxFrames] is reached. Returns the observed off→on edge
/// count.
int _runUntilBlinks(
  SimulationEngine engine,
  _CapturingOutput out,
  LocalKey ledKey, {
  required int targetRises,
  int maxFrames = 400,
}) {
  var rises = 0;
  var prevOn = out.ledIsOn(ledKey);
  for (var frame = 0; frame < maxFrames && rises < targetRises; frame++) {
    engine.runFrame();
    final on = out.ledIsOn(ledKey);
    if (on && !prevOn) rises++;
    prevOn = on;
  }
  return rises;
}

/// Renders the production [LEDPainter] and counts how many pixels it lights up
/// (alpha > 0). The glow halo only paints when the LED is on, so an on LED must
/// light strictly more pixels than an off one — i.e. the glow is visible.
Future<int> _litPixelCount({required bool isOn}) async {
  const pad = 24.0; // room for the glow halo, which extends outside the body
  final w = (LEDPainter.width + pad * 2).ceil();
  final h = (LEDPainter.height + pad * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(pad, pad);
  LEDPainter(
    properties: {'isOn': isOn, 'Color': 'Red'},
  ).paint(canvas, const Size(LEDPainter.width, LEDPainter.height));

  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData())!.buffer.asUint8List();

  var lit = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    if (bytes[i] > 0) lit++; // alpha channel
  }
  return lit;
}

void main() {
  patrolWidgetTest('Blink template: LED component blinks repeatedly and survives stop → restart', (
    $,
  ) async {
    // Compile the real Blink template sketch (production compiler path).
    final tempDir = Directory.systemTemp.createTempSync('blink_led_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final hex = await $.tester.runAsync(() async {
      final source = File('assets/templates/blink/blink.ino').readAsStringSync();
      final dir = Directory('${tempDir.path}/blink')..createSync(recursive: true);
      File('${dir.path}/blink.ino').writeAsStringSync(source);
      return CompilerService.compileWorkspace(dir.path);
    });
    expect(hex, isNotNull, reason: 'compileWorkspace returned no HEX');

    final circuit = _blinkCircuit();
    final out = _CapturingOutput(circuit.nodes, circuit.wires);
    final engine = SimulationEngine(output: out);

    // ---- Run 1: the LED component must blink multiple times ----
    engine.prepareForFrameStepping(hex!);
    final run1Rises = _runUntilBlinks(engine, out, circuit.ledKey, targetRises: 3);
    engine.stop();
    expect(
      run1Rises,
      greaterThanOrEqualTo(3),
      reason: 'LED component should blink (off→on) several times on run 1',
    );
    expect(
      out.ledIsOn(circuit.ledKey),
      isFalse,
      reason: 'stop() must leave the LED off (no stuck glow)',
    );

    // ---- Run 2: after stop → restart, it must still blink ----
    engine.prepareForFrameStepping(hex);
    final run2Rises = _runUntilBlinks(engine, out, circuit.ledKey, targetRises: 3);
    engine.stop();
    expect(
      run2Rises,
      greaterThanOrEqualTo(3),
      reason: 'REGRESSION: LED must keep blinking after a stop → restart cycle',
    );

    // ---- The glow is actually visible to the user ----
    final lit = await $.tester.runAsync(() => _litPixelCount(isOn: true));
    final dark = await $.tester.runAsync(() => _litPixelCount(isOn: false));
    expect(
      lit,
      greaterThan(dark!),
      reason: 'an on LED must render its glow halo (more lit pixels)',
    );
  });
}
