import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/board/avr_board.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/engine_pin_api.dart';
import 'package:pinbench_sim/core/spice_engine.dart';
import 'package:pinbench_sim/core/updaters/part_behavior_frame_updater.dart';

/// Circuits for engine tests: parts placed and wired, built into SPICE and
/// stepped through a part-behaviour frame, without the canvas or the app.
/// Needs `PartRegistry.initializeAsync` to have run.

/// The board, keyed `uno`.
ComponentInstance uno() => ComponentInstance(
  key: const ValueKey('uno'),
  position: Offset.zero,
  part: PartModel(name: PartNames.arduinoUno, size: const Size(40, 40)),
);

/// The `.pdl` part [definitionId], placed as [key].
ComponentInstance pdlPart(
  String definitionId, {
  String key = 'part',
  Map<String, dynamic>? properties,
}) {
  final definition = PartRegistry.getPart(definitionId)!;
  return ComponentInstance(
    key: ValueKey(key),
    position: const Offset(200, 0),
    part: PartModel(
      name: definition.name,
      size: Size(definition.visual.width, definition.visual.height),
      definitionId: definitionId,
    ),
    properties: properties,
  );
}

/// A resistor of [ohms], placed as [key]; its ends are `left` and `right`.
ComponentInstance resistor(String key, [String ohms = '220']) => ComponentInstance(
  key: ValueKey(key),
  position: const Offset(400, 0),
  part: PartModel(name: PartNames.resistor, size: const Size(40, 40)),
  properties: {ComponentProps.resistance: ohms},
);

/// A wire from [a]'s port [ap] to [b]'s port [bp].
WireModel wire(ComponentInstance a, String ap, ComponentInstance b, String bp) => WireModel(
  id: '${a.key}:$ap-${b.key}:$bp',
  start: PortLocation(nodeKey: a.key, portId: ap),
  end: PortLocation(nodeKey: b.key, portId: bp),
);

/// [nodes] joined by [wires] — the first node the board — built into SPICE.
class Bench(final List<ComponentInstance> nodes, final List<WireModel> wires) {
  late final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
  late final spice = SpiceEngine()..build(netlist, nodes);

  /// Holds each board pin in [volts] at its voltage, then solves.
  void drive(Map<String, double> volts) {
    volts.forEach(spice.setPinVoltage);
    spice.solve();
  }

  double voltage(ComponentInstance node, String port) => spice.getPortVoltage(node.key, port);
  double current(ComponentInstance node, String port) => spice.portCurrent(node.key, port);

  /// Runs one part-behaviour frame against the last solve, and returns the
  /// state each part's logic and rules wrote, by node key.
  Map<LocalKey, Map<String, Object?>> frame() {
    final state = <LocalKey, Map<String, Object?>>{};
    PartBehaviorFrameUpdater.update(
      nodes: nodes,
      spiceEngine: spice,
      isSpiceActive: true,
      lastState: state,
      elapsed: Duration.zero,
      netlist: netlist,
      board: const AvrBoardEmulator(),
      boardNode: nodes.first,
      measurements: EmulatorMeasurements(),
      queueUpdate: (_, _) {},
    );
    return state;
  }
}
