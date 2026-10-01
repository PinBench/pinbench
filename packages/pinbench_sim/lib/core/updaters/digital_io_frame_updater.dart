import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';

import '../board/board_emulator.dart';
import '../circuit_netlist.dart';

/// Per-frame digital-pin update: reads push-button state (rebuilding the
/// netlist's dynamic adjacency only when a button actually changed),
/// resolves whether each of the board's digital pins is grounded or driven by
/// a mic sensor, and drives the chip's digital input accordingly. Extracted from
/// `SimulationEngine._updateDigitalInputs`/`_buttonsDirty`/`_mapsEqual`.
abstract final class DigitalIoFrameUpdater {
  /// The state of everything that can change the circuit's *connectivity*
  /// while it runs, as a map the next frame can compare against.
  ///
  /// Only push buttons today, because they are the only part that bridges two
  /// of its own ports on demand — `CircuitNetlist.updateDynamic` adds exactly
  /// that edge. A switch is the obvious thing to expect here and is
  /// deliberately absent: the `.pdl` slide switch is modelled as a resistance
  /// (milliohms closed, a gigaohm open) pushed to the solver with `alter`, so
  /// it changes the circuit's *values* rather than its shape and needs no
  /// rebuild.
  ///
  /// A part that genuinely makes and breaks a connection would need adding
  /// both here and to `updateDynamic`; adding it to only one is a circuit that
  /// looks connected and does not conduct, or the reverse.
  static Map<LocalKey, bool> _computeTopologyState(List<ComponentInstance> simulationNodes) {
    final current = <LocalKey, bool>{};
    for (final node in simulationNodes) {
      if (node.part.name != PartNames.pushButton) continue;
      current[node.key] =
          node.properties[ComponentProps.isPressed] == true ||
          node.properties[ComponentProps.isPressed] == 'true';
    }
    return current;
  }

  static bool _mapsEqual(Map<LocalKey, bool> a, Map<LocalKey, bool> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Returns the new button-states snapshot; the caller should reassign its
  /// `_lastTopologyState` field to this value on every call (mirrors the
  /// original method reassigning that field directly).
  static Map<LocalKey, bool> update({
    required List<ComponentInstance> simulationNodes,
    required Map<LocalKey, bool> lastTopologyState,
    required CircuitNetlist netlist,
    required BoardEmulator board,
    required ComponentInstance? boardNode,
    required Map<LocalKey, ComponentInstance> nodesByKey,
    required bool micIsDigitalHigh,
  }) {
    final current = _computeTopologyState(simulationNodes);
    // Rebuilding the adjacency map is the expensive part, and topology changes
    // a handful of times in a run while frames tick sixty times a second — so
    // it only happens when something that alters connectivity actually moved.
    if (!_mapsEqual(current, lastTopologyState)) {
      netlist.updateDynamic(simulationNodes);
    }

    if (boardNode != null) {
      for (final pin in board.profile.digitalPins) {
        final connectedPorts = netlist.findConnectedPorts(
          PortLocation(nodeKey: boardNode.key, portId: '$pin'),
        );

        var isGrounded = false;
        var isMicConnected = false;

        for (final port in connectedPorts) {
          if (port.nodeKey == boardNode.key && port.portId.startsWith('GND')) {
            isGrounded = true;
          } else {
            final connectedNode = nodesByKey[port.nodeKey] ?? boardNode;
            if (connectedNode.part.name == PartNames.ky037MicSensor && port.portId == 'D0') {
              isMicConnected = true;
            }
          }
        }

        // Do not force external voltage if the sketch configured this pin as
        // OUTPUT — it would fight the driver and cause high-frequency toggling.
        if (board.isPinOutput(pin)) continue;
        // Nor while a scheduled waveform — an IR code — is playing into it:
        // its edges land mid-frame, and this would undo them every frame.
        if (board.isPinDriven(pin)) continue;

        board.setDigitalPin(pin, isHigh: isMicConnected ? micIsDigitalHigh : !isGrounded);
      }
    }

    return current;
  }
}
