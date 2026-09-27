import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/updaters/digital_io_frame_updater.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

/// Targeted unit test for [DigitalIoFrameUpdater], extracted from
/// `SimulationEngine._updateDigitalInputs`/`_buttonsDirty` in Phase 6 of
/// docs/plans/radiant-mixing-pudding.md.
///
/// Runs with `unoNode: null` so the Arduino-pin-driving loop (which calls the
/// global `AVRBridge` — a `late static` singleton only initialized by
/// `AVRBridge.loadHex`) is skipped entirely; this isolates and verifies the
/// button-dirty-detection/netlist-rebuild behavior without touching that
/// global native-adjacent state, which would otherwise leak across tests.
PartModel _model(String name) => standardParts.firstWhere((c) => c.name == name);

void main() {
  test('rebuilds the netlist dynamic adjacency only when a button actually changes state', () {
    final button = ComponentInstance(position: Offset.zero, part: _model(PartNames.pushButton));
    final netlist = CircuitNetlist();

    Map<String, dynamic> propsWithPressed({required bool pressed}) => {
      ComponentProps.isPressed: pressed,
    };

    final unpressed = button.copyWith(properties: propsWithPressed(pressed: false));
    var lastTopologyState = <LocalKey, bool>{};

    // First call: unpressed -> unpressed is "no change" only if lastTopologyState
    // already reflects it; starting from empty, this is a change (dirty).
    lastTopologyState = DigitalIoFrameUpdater.update(
      simulationNodes: [unpressed],
      lastTopologyState: lastTopologyState,
      netlist: netlist,
      unoNode: null,
      nodesByKey: {},
      micIsDigitalHigh: false,
    );
    expect(lastTopologyState[button.key], isFalse);

    final leg1 = PortLocation(nodeKey: button.key, portId: 'leg1');
    final leg2 = PortLocation(nodeKey: button.key, portId: 'leg2');
    expect(
      netlist.findConnectedPorts(leg1).contains(leg2),
      isFalse,
      reason: 'an unpressed button must not bridge its legs',
    );

    // Second call with the SAME (unpressed) state must be a no-op — netlist
    // stays whatever it was (still no bridge).
    lastTopologyState = DigitalIoFrameUpdater.update(
      simulationNodes: [unpressed],
      lastTopologyState: lastTopologyState,
      netlist: netlist,
      unoNode: null,
      nodesByKey: {},
      micIsDigitalHigh: false,
    );
    expect(netlist.findConnectedPorts(leg1).contains(leg2), isFalse);

    // Pressing the button is a real state change: the netlist should rebuild
    // and bridge the button's two legs.
    final pressed = button.copyWith(properties: propsWithPressed(pressed: true));
    lastTopologyState = DigitalIoFrameUpdater.update(
      simulationNodes: [pressed],
      lastTopologyState: lastTopologyState,
      netlist: netlist,
      unoNode: null,
      nodesByKey: {},
      micIsDigitalHigh: false,
    );

    expect(lastTopologyState[button.key], isTrue);
    expect(
      netlist.findConnectedPorts(leg1).contains(leg2),
      isTrue,
      reason: 'pressing the button must bridge its two legs in the dynamic adjacency',
    );
  });
}
