import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';

/// The four transistor parts, solved for real: each wired as the switch it is
/// most often used as, driven from an Uno pin, and read back on A0.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PartRegistry.initializeAsync);

  ComponentInstance uno() => ComponentInstance(
    key: const ValueKey('uno'),
    position: Offset.zero,
    part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
  );

  ComponentInstance transistor(String id) {
    final definition = PartRegistry.getPart(id)!;
    return ComponentInstance(
      key: const ValueKey('q1'),
      position: const Offset(200, 0),
      part: PartModel(
        name: definition.name,
        size: Size(definition.visual.width, definition.visual.height),
        definitionId: id,
      ),
    );
  }

  ComponentInstance resistor(String id, String ohms) => ComponentInstance(
    key: ValueKey(id),
    position: const Offset(400, 0),
    part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
    properties: {ComponentProps.resistance: ohms},
  );

  WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
    id: '${a.key}:$ap-${b.key}:$bp',
    start: PortLocation(nodeKey: a.key, portId: ap),
    end: PortLocation(nodeKey: b.key, portId: bp),
  );

  /// Builds [nodes] joined by [wires], drives pin 9 high as the supply and
  /// pin 8 as the control, and returns A0 for each control level.
  (double low, double high) sweep(List<ComponentInstance> nodes, List<WireModel> wires) {
    final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
    final spice = SpiceEngine()..build(netlist, nodes);
    double read(double control) {
      spice
        ..setPinVoltage('9', 5)
        ..setPinVoltage('8', control)
        ..solve();
      return spice.getPortVoltage(const ValueKey('uno'), 'A0');
    }

    return (read(0), read(5));
  }

  test('an NPN low-side switch pulls its collector down when the base is driven', () {
    final board = uno();
    final q = transistor('transistor_npn');
    final load = resistor('load', '220');
    final baseR = resistor('rb', '1000');
    final (off, on) = sweep(
      [board, q, load, baseR],
      [
        wire(board, '9', load, 'left'),
        wire(load, 'right', q, 'collector'),
        wire(q, 'collector', board, 'A0'),
        wire(board, '8', baseR, 'left'),
        wire(baseR, 'right', q, 'base'),
        wire(q, 'emitter', board, 'GND_1'),
      ],
    );
    expect(off, greaterThan(4.5), reason: 'no base current: the collector floats up');
    expect(on, lessThan(0.4), reason: 'saturated: the collector sits near the emitter');
  });

  test('a PNP high-side switch conducts when its base is pulled low', () {
    final board = uno();
    final q = transistor('transistor_pnp');
    final load = resistor('load', '220');
    final baseR = resistor('rb', '1000');
    final (on, off) = sweep(
      [board, q, load, baseR],
      [
        wire(board, '9', q, 'emitter'),
        wire(board, '8', baseR, 'left'),
        wire(baseR, 'right', q, 'base'),
        wire(q, 'collector', load, 'left'),
        wire(load, 'right', board, 'GND_1'),
        wire(q, 'collector', board, 'A0'),
      ],
    );
    expect(on, greaterThan(3), reason: 'base low: the collector is pulled up to the supply');
    expect(off, lessThan(0.1), reason: 'base high: nothing flows into the load');
  });

  test('an N-channel MOSFET switches on above its threshold', () {
    final board = uno();
    final q = transistor('transistor_nmos');
    final load = resistor('load', '220');
    final (off, on) = sweep(
      [board, q, load],
      [
        wire(board, '9', load, 'left'),
        wire(load, 'right', q, 'drain'),
        wire(q, 'drain', board, 'A0'),
        wire(board, '8', q, 'gate'),
        wire(q, 'source', board, 'GND_1'),
      ],
    );
    expect(off, greaterThan(4.5));
    expect(on, lessThan(0.2));
  });

  test('a P-channel MOSFET switches on when its gate is pulled below the source', () {
    final board = uno();
    final q = transistor('transistor_pmos');
    final load = resistor('load', '220');
    final (on, off) = sweep(
      [board, q, load],
      [
        wire(board, '9', q, 'source'),
        wire(board, '8', q, 'gate'),
        wire(q, 'drain', load, 'left'),
        wire(load, 'right', board, 'GND_1'),
        wire(q, 'drain', board, 'A0'),
      ],
    );
    expect(on, greaterThan(3));
    expect(off, lessThan(0.1));
  });

  test('a TIP120 switches hard from a few milliamps of base current', () {
    final board = uno();
    final q = transistor('tip120');
    final load = resistor('load', '220');
    final baseR = resistor('rb', '1000');
    final wires = [
      wire(board, '9', load, 'left'),
      wire(load, 'right', q, 'collector'),
      wire(q, 'collector', board, 'A0'),
      wire(board, '8', baseR, 'left'),
      wire(baseR, 'right', q, 'base'),
      wire(q, 'emitter', board, 'GND_1'),
    ];
    final (off, on) = sweep([board, q, load, baseR], wires);
    expect(off, greaterThan(4.5));
    // A Darlington never saturates as far as one transistor: the output's
    // collector cannot fall below the driver's base-emitter drop.
    expect(on, inInclusiveRange(0.5, 1.2));
  });

  test('the power MOSFETs switch like their TO-92 counterparts', () {
    final board = uno();
    final n = transistor('power_nmos');
    final nLoad = resistor('load', '220');
    final (nOff, nOn) = sweep(
      [board, n, nLoad],
      [
        wire(board, '9', nLoad, 'left'),
        wire(nLoad, 'right', n, 'drain'),
        wire(n, 'drain', board, 'A0'),
        wire(board, '8', n, 'gate'),
        wire(n, 'source', board, 'GND_1'),
      ],
    );
    expect(nOff, greaterThan(4.5));
    expect(nOn, lessThan(0.05), reason: 'a logic-level power part is milliohms on at 5 V');

    final p = transistor('power_pmos');
    final pLoad = resistor('load', '220');
    final (pOn, pOff) = sweep(
      [board, p, pLoad],
      [
        wire(board, '9', p, 'source'),
        wire(board, '8', p, 'gate'),
        wire(p, 'drain', pLoad, 'left'),
        wire(pLoad, 'right', board, 'GND_1'),
        wire(p, 'drain', board, 'A0'),
      ],
    );
    expect(pOn, greaterThan(4));
    expect(pOff, lessThan(0.1));
  });

  test('an unwired MOSFET gate is off, not an unsolvable floating node', () {
    final board = uno();
    final q = transistor('transistor_nmos');
    final load = resistor('load', '220');
    final (level, _) = sweep(
      [board, q, load],
      [
        wire(board, '9', load, 'left'),
        wire(load, 'right', q, 'drain'),
        wire(q, 'drain', board, 'A0'),
        wire(q, 'source', board, 'GND_1'),
      ],
    );
    expect(level, greaterThan(4.5));
  });
}
