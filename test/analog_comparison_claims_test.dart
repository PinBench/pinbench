// Pins the numbers the analog comparison publishes.
//
// That page is a public claim about our analog accuracy, checked against the
// `voltage_divider` and `current_limiting` templates. It solves the *shipped
// template files* rather than a hand-built copy of them, so the circuit a
// reader opens from the welcome screen is provably the one that produced the
// published figure. If a number here moves, the page is wrong and must be
// re-dated.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_sim/core/circuit_netlist.dart';
import 'package:pinbench_sim/core/spice_engine.dart';

/// Loads a shipped comparison circuit and builds the SPICE model exactly as
/// `SimulationEngine` does — including `bridgeResistors: false`, which is what
/// makes a resistor a real two-terminal element instead of a wire.
({List<ComponentInstance> nodes, SpiceEngine spice}) _load(String template, {String? substitute}) {
  final file = File('assets/templates/$template/circuit.cdl');
  expect(file.existsSync(), isTrue, reason: 'missing shipped template ${file.path}');

  var source = file.readAsStringSync();
  if (substitute != null) {
    final replaced = source.replaceFirst('resistance: 100;', substitute);
    expect(replaced, isNot(source), reason: 'substitution did not match the shipped file');
    source = replaced;
  }

  final parsed = CircuitParser.applyToCanvas(CircuitParser.parse(source), standardParts);
  final nodes = parsed.nodes;
  final wires = parsed.wires;

  expect(nodes, isNotEmpty, reason: 'no parts resolved from $template');
  expect(wires, isNotEmpty, reason: 'no wires resolved from $template');

  final netlist = CircuitNetlist()..buildStatic(nodes, wires, bridgeResistors: false);
  return (nodes: nodes, spice: SpiceEngine()..build(netlist, nodes));
}

ComponentInstance _byName(List<ComponentInstance> nodes, String partName) =>
    nodes.firstWhere((n) => n.part.name == partName);

/// The ATmega328P's 10-bit ADC against the 5 V reference.
int _adc(double volts) => (volts / 5.0 * 1023).round().clamp(0, 1023);

void main() {
  group('demo 1 — two-resistor divider', () {
    test('A0 sits at half rail, not at the supply', () {
      final circuit = _load('voltage_divider');
      final uno = _byName(circuit.nodes, PartNames.arduinoUno);

      circuit.spice.setPinVoltage('8', 5.0);
      circuit.spice.solve();

      final volts = circuit.spice.getPortVoltage(uno.key, 'A0');

      // Published: 2.495 V / analogRead() == 510.
      expect(volts, closeTo(2.495, 0.005));
      expect(_adc(volts), 510);

      // The claim that actually distinguishes us: not the supply rail. A
      // simulator that ignores resistors returns 1023 here.
      expect(_adc(volts), lessThan(600));
    });

    test('the 5 mV shortfall is the GPIO source resistance, not solver error', () {
      final circuit = _load('voltage_divider');
      final uno = _byName(circuit.nodes, PartNames.arduinoUno);

      circuit.spice.setPinVoltage('8', 5.0);
      circuit.spice.solve();

      // 40 Ω of pin resistance in series with 10 k + 10 k pulls the midpoint
      // to 5 * 10000 / 20040 = 2.4950 V. Being *below* the ideal 2.5 V is the
      // physically correct direction.
      const ideal = 5.0 * 10000 / (10000 + 10000);
      const withPinResistance = 5.0 * 10000 / (10000 + 10000 + 40);
      final volts = circuit.spice.getPortVoltage(uno.key, 'A0');

      expect(volts, lessThan(ideal));
      expect(volts, closeTo(withPinResistance, 0.001));
    });
  });

  group('demo 2 — LED with an undersized series resistor', () {
    test('100 Ω draws roughly double what 220 Ω draws', () {
      final circuit = _load('current_limiting');
      final led = _byName(circuit.nodes, PartNames.led);

      circuit.spice.setPinVoltage('13', 5.0);
      circuit.spice.solve();

      final milliamps = circuit.spice.getLedCurrent(led.key.toString()).abs() * 1000;

      // Published: 27.8 mA — over a 5 mm red LED's 20 mA rating, and most of
      // the ATmega328P's 40 mA per-pin absolute maximum.
      expect(milliamps, closeTo(27.8, 0.5));
      expect(milliamps, greaterThan(20.0), reason: 'the whole point: this is an over-current');
    });

    test('the resistor is what sets the current', () {
      // The same shipped circuit with only the resistor value edited. If
      // resistors were ignored — the Wokwi behaviour this page is about —
      // both solves would return the same number.
      double solve({String? substitute}) {
        final circuit = _load('current_limiting', substitute: substitute);
        final led = _byName(circuit.nodes, PartNames.led);
        circuit.spice.setPinVoltage('13', 5.0);
        circuit.spice.solve();
        return circuit.spice.getLedCurrent(led.key.toString()).abs() * 1000;
      }

      final undersized = solve();
      final correct = solve(substitute: 'resistance: 220;');

      // Published: 15.0 mA at 220 Ω against 27.8 mA at 100 Ω.
      expect(correct, closeTo(15.0, 0.5));
      expect(correct, lessThan(undersized));
    });
  });

  test('a runtime resistance change reaches the solve', () {
    // What a `physics.resistance` rule does — and what the LDR and thermistor
    // depend on to respond to light and temperature. Listed on the page as a
    // limitation until ngspice_dart learned to `alter` a resistor.
    final circuit = _load('voltage_divider');
    final uno = _byName(circuit.nodes, PartNames.arduinoUno);
    final bottom = circuit.nodes.lastWhere((n) => n.part.name == PartNames.resistor);

    circuit.spice.setPinVoltage('8', 5.0);
    circuit.spice.solve();
    expect(circuit.spice.getPortVoltage(uno.key, 'A0'), closeTo(2.5, 0.01));

    final element = circuit.spice.pdlElementFor(bottom.key);
    expect(element, isNotNull);
    circuit.spice.setElementValue(element!, 30000.0);
    circuit.spice.solve();

    // Tripling the lower leg swings A0 to three quarters of the pin's 5 V.
    expect(circuit.spice.getPortVoltage(uno.key, 'A0'), closeTo(3.75, 0.01));
  });

  group('documented limits', () {
    // These guard the "what we do not model yet" section of the page. They
    // assert the *current* shortcoming on purpose: if one starts failing, the
    // limitation was fixed and the page overstates our weakness.

    test('a capacitor contributes nothing to the analog model', () {
      final capacitor = standardParts.firstWhere((p) => p.name == PartNames.capacitor);
      expect(
        PartRegistry.spiceFor(capacitor),
        isNull,
        reason: 'capacitor now has a SPICE model — update the analog comparison',
      );
    });

    test('LED forward voltage is below a real red LED', () {
      final circuit = _load('current_limiting');
      final led = _byName(circuit.nodes, PartNames.led);

      circuit.spice.setPinVoltage('13', 5.0);
      circuit.spice.solve();

      // Our diode model (Is=1e-14, N=1.5) forward-drops ~1.11 V where a real
      // red LED sits near 1.8–2.1 V, so solved currents run high. Disclosed on
      // the page rather than quietly rounded away.
      final forwardVolts = circuit.spice.getPortVoltage(led.key, 'anode');
      expect(forwardVolts, closeTo(1.11, 0.05));
      expect(forwardVolts, lessThan(1.8));
    });
  });
}
