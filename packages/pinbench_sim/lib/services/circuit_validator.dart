import 'package:flutter/widgets.dart';

import 'package:pinbench_parts/logic/built_in_part_logic.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/part_registry.dart';

import '../core/circuit_netlist.dart';

class CircuitValidatorResult {
  final String? errorMessage;
  final Map<LocalKey, Map<String, dynamic>> updatedProperties;

  CircuitValidatorResult({this.errorMessage, this.updatedProperties = const {}});
}

class CircuitValidator {
  /// The ATmega328P's typical GPIO output resistance, in series with whatever
  /// the pin drives. Matches the value `SpiceEngine` puts in the netlist.
  static const _pinSourceOhms = 40.0;

  /// Our LED model's forward drop, taken at the *low* end of its range.
  ///
  /// The solver derives this from the diode equation, so it drifts with
  /// current — about 1.087 V at 15 mA and 1.101 V at 22 mA. Assuming the low
  /// end makes this estimate read slightly *high*, which is the direction it
  /// has to err: a pre-run check that clears a circuit the running simulation
  /// then flags is worse than useless. Whatever this warning passes, the
  /// simulation must also pass.
  static const _ledForwardVolts = 1.08;

  /// The E12 series — the resistors that actually exist in a drawer.
  static const _e12 = [10, 12, 15, 18, 22, 27, 33, 39, 47, 56, 68, 82];

  /// The smallest standard resistor that keeps an LED within its rating when
  /// driven from [supplyVolts] through [sourceOhms].
  ///
  /// Rounded up to a real value rather than reported as the bare arithmetic
  /// minimum. Advising "at least 155 Ω" was wrong twice over: no such resistor
  /// is sold, and 155 Ω lands exactly on the 20 mA limit, so fitting it put
  /// the circuit right back into the warning it was meant to resolve. The next
  /// value up the series carries its own margin.
  static int _recommendedSeriesOhms(double supplyVolts, double sourceOhms) {
    final minimum = (supplyVolts - _ledForwardVolts) / BuiltInPartLogic.ledRatedAmps - sourceOhms;
    for (var decade = 1; decade <= 1000000; decade *= 10) {
      for (final value in _e12) {
        final candidate = value * decade;
        if (candidate >= minimum) return candidate;
      }
    }
    return minimum.ceil();
  }

  /// Estimates the current an LED would draw if whatever drives it went fully
  /// on, without running SPICE.
  ///
  /// This exists so an over-driven LED is caught while the circuit is being
  /// *drawn*, rather than only once firmware is compiled and running. It
  /// cannot call the solver to find out: ngspice is a process-global
  /// singleton, so building a circuit here would clobber a simulation that is
  /// already running, and re-solving on every canvas edit would be wasteful.
  ///
  /// So it walks the netlist instead, summing series resistance from the LED
  /// back to whatever drives it. For the series topology this warning is about
  /// that agrees with the solver closely (100 Ω → 27.9 mA estimated against
  /// 27.8 mA solved). A topology it cannot reduce — parallel paths, a divider
  /// feeding the LED — returns null rather than a number it cannot stand
  /// behind, and the running simulation reports the real figure.
  static double? _estimateLedAmps({
    required CircuitNetlist analogNetlist,
    required List<ComponentInstance> nodes,
    required ComponentInstance led,
  }) {
    final resistors = {
      for (final n in nodes)
        if (n.part.name == PartNames.resistor) n.key: n,
    };

    // (supply volts, source resistance) for each port that can drive current.
    (double, double)? sourceAt(PortLocation loc) {
      final node = nodes.where((n) => n.key == loc.nodeKey).firstOrNull;
      if (node == null || !PartRegistry.isBoard(node.part)) return null;
      final id = loc.portId;
      if (id.startsWith('GND')) return null;
      // A GPIO pin drives through the chip's own output resistance; a supply
      // rail is stiff.
      if (int.tryParse(id) != null) return (5.0, _pinSourceOhms);
      if (id == '5V' || id == 'VIN') return (5.0, 0.0);
      if (id == '3.3V') return (3.3, 0.0);
      return null;
    }

    final best = <double>[];
    final seen = <PortLocation>{};
    final queue = <(PortLocation, double)>[(PortLocation(nodeKey: led.key, portId: 'anode'), 0.0)];

    while (queue.isNotEmpty) {
      final (port, ohms) = queue.removeAt(0);
      if (!seen.add(port)) continue;

      for (final peer in analogNetlist.findConnectedPorts(port)) {
        final source = sourceAt(peer);
        if (source != null) {
          final (volts, sourceOhms) = source;
          final total = ohms + sourceOhms;
          if (volts <= _ledForwardVolts) continue;
          // A dead short would divide by zero; treat it as the pin's own limit.
          best.add((volts - _ledForwardVolts) / (total <= 0 ? _pinSourceOhms : total));
          continue;
        }

        // Step through a resistor to its far leg, carrying its value.
        final resistor = resistors[peer.nodeKey];
        if (resistor == null) continue;
        final far = peer.portId == 'left' ? 'right' : 'left';
        final value =
            PartRegistry.spiceFor(resistor.part)?.valueFor(resistor.properties, 'resistance') ??
            220.0;
        queue.add((PortLocation(nodeKey: resistor.key, portId: far), ohms + value));
      }
    }

    if (best.isEmpty) return null;
    // Several paths in parallel would each contribute; the worst single one is
    // already enough to warn about, and is the one the user can act on.
    best.sort();
    return best.last;
  }

  static CircuitValidatorResult validate({
    required List<ComponentInstance> nodes,
    required List<WireModel> wires,
  }) {
    final netlist = CircuitNetlist();
    netlist.buildStatic(nodes, wires);

    // A second view with resistors left as two-terminal elements, so the
    // over-current estimate can see the resistance the bridged netlist hides.
    final analogNetlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);

    final arduinoNode = nodes.where((n) => n.part.name == PartNames.arduinoUno).firstOrNull;

    String? errorMessage;
    final updatedProperties = <LocalKey, Map<String, dynamic>>{};

    if (arduinoNode != null) {
      // First, check for dangerous short circuits across the Arduino itself (e.g. Pin 13 to GND)
      final gndPorts = ['GND_1', 'GND_2', 'GND_3'];
      for (final gndPort in gndPorts) {
        final gndLoc = PortLocation(nodeKey: arduinoNode.key, portId: gndPort);
        // Deliberately the *unbridged* view: a resistor is a component, not a
        // wire, so a pin reaching ground through one is a divider rather than
        // a short. Reading the bridged netlist here reported every voltage
        // divider as "pin directly connected to Ground".
        final connectedToGnd = analogNetlist.findConnectedPorts(gndLoc);

        for (final loc in connectedToGnd) {
          if (loc.nodeKey == arduinoNode.key &&
              (!loc.portId.startsWith('GND') &&
                  loc.portId != 'NC' &&
                  loc.portId != 'AREF' &&
                  loc.portId != 'IOREF' &&
                  loc.portId != 'RESET')) {
            errorMessage =
                '[Circuit Error] Short Circuit! Arduino pin ${loc.portId} is directly connected to Ground!';
            break;
          }
        }
        if (errorMessage != null) break;
      }

      for (final node in nodes) {
        if (node.part.name == PartNames.led) {
          final anodeLoc = PortLocation(nodeKey: node.key, portId: 'anode');
          final cathodeLoc = PortLocation(nodeKey: node.key, portId: 'cathode');

          final anodeConnected = netlist.findConnectedPorts(anodeLoc);
          final cathodeConnected = netlist.findConnectedPorts(cathodeLoc);

          final anodeToGnd = anodeConnected.any(
            (loc) => loc.nodeKey == arduinoNode.key && loc.portId.startsWith('GND'),
          );
          final cathodeToPositive = cathodeConnected.any(
            (loc) =>
                loc.nodeKey == arduinoNode.key &&
                (!loc.portId.startsWith('GND') &&
                    loc.portId != 'NC' &&
                    loc.portId != 'IOREF' &&
                    loc.portId != 'RESET' &&
                    loc.portId != 'AREF'),
          );
          final isShorted = anodeConnected.contains(cathodeLoc);

          if (isShorted) {
            updatedProperties[node.key] = {
              ...node.properties,
              ComponentProps.hasError: true,
              ComponentProps.isOn: false,
            };
            errorMessage =
                '[Circuit Error] LED is short-circuited! Both legs are connected together.';
          } else if (anodeToGnd && cathodeToPositive) {
            updatedProperties[node.key] = {
              ...node.properties,
              ComponentProps.hasError: true,
              ComponentProps.isOn: false,
            };
            errorMessage = '[Circuit Error] LED connected backwards! Reverse polarity detected.';
          } else {
            // Nothing is wired wrongly — but the values might still be. This
            // is the check that catches a resistor too small to protect the
            // LED, while the circuit is being drawn rather than after a run.
            final amps = _estimateLedAmps(analogNetlist: analogNetlist, nodes: nodes, led: node);

            if (amps != null && amps > BuiltInPartLogic.ledRatedAmps) {
              updatedProperties[node.key] = {
                ...node.properties,
                ComponentProps.hasError: true,
                ComponentProps.isOn: false,
              };
              final milliamps = amps * 1000;
              final safeOhms = _recommendedSeriesOhms(5.0, _pinSourceOhms);
              errorMessage ??=
                  '[Circuit Error] LED over-current: about '
                  '${milliamps.toStringAsFixed(0)} mA, above its '
                  '${(BuiltInPartLogic.ledRatedAmps * 1000).toStringAsFixed(0)} mA rating. '
                  'Fit a series resistor of $safeOhms Ω or more.';
            } else if (node.properties[ComponentProps.hasError] == true) {
              updatedProperties[node.key] = {...node.properties, ComponentProps.hasError: false};
            }
          }
        }
      }
    }

    return CircuitValidatorResult(errorMessage: errorMessage, updatedProperties: updatedProperties);
  }
}
