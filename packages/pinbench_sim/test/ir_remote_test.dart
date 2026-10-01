import 'dart:io';

import 'package:avr8_dart/avr8_dart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/logic/nec.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/avr_interop.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/updaters/ir_link.dart';

/// An IR code played into an Arduino input, edge by edge, on the CPU's clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);
  // An empty program: the CPU runs NOPs, which is all a clock needs.
  setUp(() => AVRBridge.loadHex(':00000001FF'));

  bool pin2() => AVRBridge.cpu.data[portDConfig.PIN] & (1 << 2) != 0;

  /// Samples pin 2 every microsecond for [us] and returns its levels as
  /// `(isHigh, microseconds)` runs, the shape [Nec.frame] produces.
  List<(bool, double)> record(double us) {
    final runs = <(bool, double)>[];
    var level = pin2();
    var start = 0;
    for (var t = 1; t <= us; t++) {
      AVRBridge.tick(16);
      if (pin2() != level) {
        runs.add((level, (t - start).toDouble()));
        level = pin2();
        start = t;
      }
    }
    runs.add((level, 0));
    return runs;
  }

  test('a frame plays into the pin with every edge on time', () {
    AVRBridge.setDigitalPin(2, isHigh: true);
    final sent = Nec.frame(0x00, 0x45);
    AVRBridge.playWaveform(2, sent);
    expect(AVRBridge.isPinDriven(2), isTrue);

    final heard = record(70000);
    // The first run is the idle high before the first edge; drop it.
    final frame = heard.skipWhile((r) => r.$1).toList();
    expect(frame, hasLength(sent.length));
    for (var i = 0; i < sent.length - 1; i++) {
      expect(frame[i].$1, sent[i].$1, reason: 'level $i');
      expect(frame[i].$2, closeTo(sent[i].$2, 1.5), reason: 'duration $i');
    }
    expect(Nec.decode(frame), (0x00, 0x45));
    expect(AVRBridge.isPinDriven(2), isFalse, reason: 'released once it has played');
  });

  test('a second press queues behind the first, a frame gap apart', () {
    AVRBridge.setDigitalPin(2, isHigh: true);
    AVRBridge.playWaveform(2, Nec.frame(0x00, 0x45), gapUs: Nec.frameGapUs);
    AVRBridge.playWaveform(2, Nec.frame(0x00, 0x46), gapUs: Nec.frameGapUs);
    final heard = record(180000);

    // Two whole frames, each decodable, with the gap between them idle high.
    final leaders = [
      for (var i = 0; i < heard.length; i++)
        if (!heard[i].$1 && heard[i].$2 > 8000) i,
    ];
    expect(leaders, hasLength(2));
    expect(Nec.decode(heard.sublist(leaders[0])), (0x00, 0x45));
    expect(Nec.decode(heard.sublist(leaders[1])), (0x00, 0x46));
    final (gapIsHigh, gapUs) = heard[leaders[1] - 1];
    expect(gapIsHigh, isTrue);
    expect(gapUs, closeTo(Nec.frameGapUs, 2));
  });

  test('an IRremote sketch decodes the code it is sent', () {
    // test/fixtures/ir_receive: IRremote's receive example, printing each
    // decoded command. The real library, timing the real waveform.
    final serial = StringBuffer();
    AVRBridge.loadHex(
      File('test/fixtures/ir_receive/ir_receive.hex').readAsStringSync(),
      onSerialPrint: serial.write,
    );
    AVRBridge.setDigitalPin(2, isHigh: true); // the receiver idles high

    void run(double ms) {
      for (var i = 0; i < ms; i++) {
        AVRBridge.tick(16000);
      }
    }

    run(100); // setup: Serial, then IrReceiver.begin(2)
    AVRBridge.playWaveform(2, Nec.frame(0x00, 0x45));
    run(150);
    expect(serial.toString(), contains('CMD 0x45'));

    AVRBridge.playWaveform(2, Nec.frame(0x00, 0x4A), gapUs: Nec.frameGapUs);
    run(150);
    expect(serial.toString(), contains('CMD 0x4A'), reason: 'and the next press after it');
  });

  group('the link from a remote to the receivers', () {
    ComponentInstance uno() => ComponentInstance(
      key: const ValueKey('uno'),
      position: Offset.zero,
      part: standardParts.firstWhere((p) => p.name == PartNames.arduinoUno),
    );
    ComponentInstance receiver() => ComponentInstance(
      key: const ValueKey('ir1'),
      position: const Offset(300, 0),
      part: PartModel(name: 'IR Receiver', size: const Size(40, 72), definitionId: 'ir_receiver'),
    );
    WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
      id: '${a.key}:$ap-${b.key}:$bp',
      start: PortLocation(nodeKey: a.key, portId: ap),
      end: PortLocation(nodeKey: b.key, portId: bp),
    );

    List<int> transmit(List<WireModel> Function(ComponentInstance, ComponentInstance) wires) {
      final board = uno();
      final ir = receiver();
      final netlist = CircuitNetlist()..buildStatic([board, ir], wires(board, ir));
      return IrLink.transmit(
        address: 0,
        command: 0x45,
        nodes: [board, ir],
        netlist: netlist,
        unoNode: board,
      );
    }

    test('reaches a powered receiver, out of the pin its OUT is wired to', () {
      final pins = transmit(
        (board, ir) => [
          wire(ir, 'vcc', board, '5V'),
          wire(ir, 'gnd', board, 'GND_1'),
          wire(ir, 'out', board, '2'),
        ],
      );
      expect(pins, [2]);
      expect(AVRBridge.isPinDriven(2), isTrue);
    });

    test('an unpowered receiver hears nothing', () {
      final pins = transmit(
        (board, ir) => [wire(ir, 'gnd', board, 'GND_1'), wire(ir, 'out', board, '2')],
      );
      expect(pins, isEmpty);
      expect(AVRBridge.isPinDriven(2), isFalse);
    });
  });
}
