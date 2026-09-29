import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_sim/core/simulation_engine.dart';
import 'package:pinbench_sim/core/simulation_output.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Verifies the SPICE-skip optimisation: the per-frame analog solve is only
/// armed when something actually observes its output (an LED, a connected
/// analog input, or a mic sensor). A bare pin-13 blink pays no SPICE cost.

ComponentInstance _node(String name, String id, [Offset pos = Offset.zero]) => ComponentInstance(
  key: ValueKey(id),
  position: pos,
  part: PartModel(name: name, size: const Size(40, 40)),
);

WireModel _wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
  id: '${a.key}:$ap-${b.key}:$bp',
  start: PortLocation(nodeKey: a.key, portId: ap),
  end: PortLocation(nodeKey: b.key, portId: bp),
);

class _FakeOutput(
  @override final List<ComponentInstance> simulationNodes,
  @override final List<WireModel> simulationWires,
) implements SimulationOutput {
  @override
  void applyNodeUpdates(Map<LocalKey, Map<String, dynamic>> updates) {}
}

// Minimal Intel HEX: a single end-of-file record (empty program).
const _emptyHex = ':00000001FF';

SimulationEngine _prepared(List<ComponentInstance> nodes, List<WireModel> wires) {
  final engine = SimulationEngine(output: _FakeOutput(nodes, wires));
  engine.prepareForFrameStepping(_emptyHex);
  return engine;
}

void main() {
  test('bare pin-13 blink (no analog parts) skips SPICE', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final engine = _prepared([uno], const []);
    expect(engine.isSpiceActive, isFalse);
  });

  test('an attached LED arms SPICE', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    final led = _node(PartNames.led, 'led1', const Offset(200, 0));
    final wires = [_wire(uno, '13', led, 'anode'), _wire(led, 'cathode', uno, 'GND_1')];
    final engine = _prepared([uno, led], wires);
    expect(engine.isSpiceActive, isTrue);
  });

  test('a connected analog input arms SPICE', () {
    final uno = _node(PartNames.arduinoUno, 'uno');
    // Drive A0 from a digital pin — no LED, but analogRead observes the solve.
    final engine = _prepared([uno], [_wire(uno, '8', uno, 'A0')]);
    expect(engine.isSpiceActive, isTrue);
  });
}
