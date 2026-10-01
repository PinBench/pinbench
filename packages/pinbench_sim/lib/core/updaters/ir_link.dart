import 'package:pinbench_parts/logic/nec.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/port_model.dart';

import '../avr_interop.dart';
import '../circuit_netlist.dart';

/// Carries an IR remote's button press to the receivers in the circuit.
///
/// Infrared needs no wire: a remote reaches every receiver it points at, so a
/// press goes to every IR receiver on the canvas. Each one that is powered —
/// VCC on the board's 5 V or 3.3 V, GND on a GND — plays the press's NEC frame
/// out of its OUT pin into whichever Arduino input that reaches, timed to the
/// cycle, which is what IRremote decodes.
///
/// An engine-side link like the microphone's, deliberately: a part's logic
/// cannot drive the board (see `PartPinApi`), and this is the board's input
/// being driven, by something outside the circuit.
abstract final class IrLink {
  /// The `.pdl` id of the parts that receive.
  static const receiverIds = {'ir_receiver'};

  /// Sends [command] from a remote at [address] to every receiver in [nodes]
  /// that can hear it. Returns the Arduino pins it was played into.
  static List<int> transmit({
    required int address,
    required int command,
    required List<ComponentInstance> nodes,
    required CircuitNetlist netlist,
    required ComponentInstance? unoNode,
  }) {
    final uno = unoNode;
    if (uno == null) return const [];
    final levels = Nec.frame(address, command);
    final pins = <int>[];
    for (final node in nodes) {
      if (!receiverIds.contains(node.part.definitionId)) continue;
      Iterable<String> boardPorts(String portId) => netlist
          .findConnectedPorts(PortLocation(nodeKey: node.key, portId: portId))
          .where((p) => p.nodeKey == uno.key)
          .map((p) => p.portId);

      final powered = boardPorts('vcc').any((id) => id == '5V' || id == '3.3V');
      final grounded = boardPorts('gnd').any((id) => id.startsWith('GND'));
      if (!powered || !grounded) continue;

      for (final id in boardPorts('out')) {
        final pin = _pinNumber(id);
        if (pin == null || AVRBridge.isPinOutput(pin)) continue;
        AVRBridge.playWaveform(pin, levels, gapUs: Nec.frameGapUs);
        pins.add(pin);
      }
    }
    return pins;
  }

  /// The Arduino pin number for a board port id: `'2'` → 2, `'A0'` → 14.
  static int? _pinNumber(String portId) {
    final digital = int.tryParse(portId);
    if (digital != null) return digital;
    if (portId.length == 2 && portId[0] == 'A') {
      final analog = int.tryParse(portId[1]);
      if (analog != null && analog <= 5) return 14 + analog;
    }
    return null;
  }
}
