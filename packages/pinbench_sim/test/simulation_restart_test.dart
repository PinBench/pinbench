import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Regression test for the "LED stops blinking after Stop -> Start" bug.
///
/// The root cause was global/static state in [SpiceEngine] (the ngspice native
/// singleton lifecycle) leaking between simulation runs: the first run lit the
/// LED, but a second run after a restart produced no output vectors, so the LED
/// current came back as zero. This test drives the STOP -> START -> STOP -> START
/// cycle directly against [SpiceEngine] and asserts the LED still toggles on the
/// SECOND run, not just the first.
///
/// The circuit is built by populating [CircuitNetlist.adj] directly. The engine's
/// legacy build path keys off [PartModel.name] and reads node topology from
/// the netlist, so no painter / canvas widget is required — this keeps the test a
/// focused unit test of the simulation core.

/// Adds a bidirectional connection between two ports, mirroring the private
/// `_addEdge` used by [CircuitNetlist.buildStatic].
void _connect(CircuitNetlist netlist, PortLocation a, PortLocation b) {
  netlist.adj.putIfAbsent(a, () => {}).add(b);
  netlist.adj.putIfAbsent(b, () => {}).add(a);
}

ComponentInstance _node(String name, String keyId) => ComponentInstance(
  key: ValueKey(keyId),
  position: Offset.zero,
  part: PartModel(name: name, size: const Size(40, 40)),
);

class _Circuit(
  final CircuitNetlist netlist,
  final List<ComponentInstance> nodes,
  final String ledKey,
);

/// Builds a minimal "Arduino pin 13 -> 220Ω resistor -> LED -> GND" circuit.
///
/// Each call produces fresh nodes and a fresh netlist, emulating what the app
/// does when a simulation is (re)started.
_Circuit _buildCircuit() {
  final uno = _node(PartNames.arduinoUno, 'uno');
  final resistor = _node(PartNames.resistor, 'r1');
  final led = _node(PartNames.led, 'led1');

  final netlist = CircuitNetlist();

  // pin 13 --> resistor.left
  _connect(
    netlist,
    PortLocation(nodeKey: uno.key, portId: '13'),
    PortLocation(nodeKey: resistor.key, portId: 'left'),
  );
  // resistor internal pass-through (left <-> right)
  _connect(
    netlist,
    PortLocation(nodeKey: resistor.key, portId: 'left'),
    PortLocation(nodeKey: resistor.key, portId: 'right'),
  );
  // resistor.right --> LED.anode
  _connect(
    netlist,
    PortLocation(nodeKey: resistor.key, portId: 'right'),
    PortLocation(nodeKey: led.key, portId: 'anode'),
  );
  // LED.cathode --> Arduino GND (portId starting with 'GND' marks the ground net)
  _connect(
    netlist,
    PortLocation(nodeKey: led.key, portId: 'cathode'),
    PortLocation(nodeKey: uno.key, portId: 'GND'),
  );

  return _Circuit(netlist, [uno, resistor, led], led.key.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Threshold for "LED is lit". A red LED on 5V through ~260Ω draws several mA,
  // so anything above 1µA is unambiguously "on" vs the ~0 of an off pin.
  const onThreshold = 1e-6;

  test('LED still blinks on the SECOND simulation run (STOP -> START -> STOP -> START)', () {
    // ---- Run 1: first START ----
    final engine1 = SpiceEngine();
    final c1 = _buildCircuit();
    engine1.build(c1.netlist, c1.nodes);

    engine1.setPinVoltage('13', 5.0);
    engine1.solve();
    final run1On = engine1.getLedCurrent(c1.ledKey).abs();
    expect(
      run1On,
      greaterThan(onThreshold),
      reason: 'First run: LED should light when pin 13 is driven to 5V',
    );

    engine1.setPinVoltage('13', 0.0);
    engine1.solve();
    final run1Off = engine1.getLedCurrent(c1.ledKey).abs();
    expect(
      run1Off,
      lessThan(run1On),
      reason: 'First run: LED current should drop when pin 13 returns to 0V',
    );

    // ---- STOP: the previous engine is discarded ----
    // ---- Run 2: second START (a brand new engine + circuit) ----
    // This is the core of the regression: ngspice is a global native
    // singleton, so a second run must still produce a valid operating point.
    final engine2 = SpiceEngine();
    final c2 = _buildCircuit();
    engine2.build(c2.netlist, c2.nodes);

    engine2.setPinVoltage('13', 5.0);
    engine2.solve();
    final run2On = engine2.getLedCurrent(c2.ledKey).abs();
    expect(
      run2On,
      greaterThan(onThreshold),
      reason: 'REGRESSION: LED must still light on the SECOND run after a restart',
    );

    engine2.setPinVoltage('13', 0.0);
    engine2.solve();
    final run2Off = engine2.getLedCurrent(c2.ledKey).abs();
    expect(
      run2Off,
      lessThan(run2On),
      reason: 'Second run: LED must toggle OFF when pin 13 returns to 0V',
    );

    // Drive it high once more to prove the toggle is repeatable mid-run.
    engine2.setPinVoltage('13', 5.0);
    engine2.solve();
    final run2OnAgain = engine2.getLedCurrent(c2.ledKey).abs();
    expect(
      run2OnAgain,
      greaterThan(onThreshold),
      reason: 'Second run: LED must toggle back ON, proving a real blink',
    );
  });
}
