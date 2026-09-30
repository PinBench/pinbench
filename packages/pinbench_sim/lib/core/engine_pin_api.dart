import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/logic/part_logic.dart';

import 'avr_interop.dart';
import 'circuit_netlist.dart';
import '../config/sim_constants.dart';
import 'spice_engine.dart';

/// [PartPinApi] backed by the real netlist and AVR emulator.
///
/// One per placed component per run — it caches the port→pin tracing, which is
/// a netlist walk that cannot change mid-run because the canvas is read-only
/// while simulating.
class EnginePinApi({
  required final ComponentInstance node,
  required final CircuitNetlist netlist,
  required final ComponentInstance? unoNode,

  /// What the emulator has been asked to measure, shared across every
  /// instance so the engine reconciles it once — see [EmulatorMeasurements].
  required final EmulatorMeasurements measurements,
}) implements PartPinApi {
  final _traced = <String, List<String>>{};

  @override
  int? connectedTo(String portId) {
    // The board's digital ports are named by their pin number, so a port that
    // reaches the Uno and parses as a number in range *is* the pin. Scanned
    // rather than taken from [boardPortFor], because a net can touch the board
    // more than once and only one of those touches is a numbered pin — the
    // signal is what a caller asking for a *pin* means.
    for (final boardPort in _boardPortsFor(portId)) {
      final pin = int.tryParse(boardPort);
      if (pin != null && pin >= 0 && pin <= SimConstants.maxDigitalPin) return pin;
    }
    return null;
  }

  @override
  String? boardPortFor(String portId) => _boardPortsFor(portId).firstOrNull;

  /// Every port of the board this component's [portId] reaches, by the board's
  /// own name for each.
  List<String> _boardPortsFor(String portId) => _traced.putIfAbsent(portId, () {
    final uno = unoNode;
    if (uno == null) return const <String>[];
    // This one walk replaced `CircuitTopologyIndexer` entirely: it held three
    // near-identical tracers, one per part type, each hard-coding the port
    // names it knew about (a servo's `signal`, an LED's `anode`/`cathode`, a
    // buzzer's `plus`). Asking on behalf of a part, with the port name as an
    // argument, is the same walk without the catalogue.
    return [
      for (final port in netlist.findConnectedPorts(
        PortLocation(nodeKey: node.key, portId: portId),
      ))
        if (port.nodeKey == uno.key) port.portId,
    ];
  });

  @override
  double duty(int pin) => AVRBridge.getPinDuty(pin);

  @override
  double pulseUs(int pin) {
    measurements.addPulsePin(pin);
    return AVRBridge.getServoPulseUs(pin);
  }

  @override
  double? frequencyOn(int pin) {
    measurements.requestFrequencyPin(pin);
    return measurements.lastFrequency;
  }

  @override
  bool isHigh(int pin) => AVRBridge.getPinState(pin);
}

/// What the emulator has been asked to measure this run, and the last result.
///
/// Collected rather than pushed per call because the emulator's settings are
/// whole values — a list of pulse pins, a single frequency pin — so every part
/// that wants something contributes and the engine pushes once per frame, only
/// when it changed. Reassigning them per call would reconfigure the emulator
/// sixty times a second.
class EmulatorMeasurements {
  final Set<int> _pulsePins = {};
  int? _frequencyPin;
  var _dirty = false;

  /// The frequency the emulator last reported. Written by the engine from the
  /// detector callback; read by whichever part asked for it.
  double? lastFrequency;

  void addPulsePin(int pin) {
    if (_pulsePins.add(pin)) _dirty = true;
  }

  void requestFrequencyPin(int pin) {
    if (_frequencyPin == pin) return;
    _frequencyPin = pin;
    _dirty = true;
  }

  void clear() {
    _pulsePins.clear();
    _frequencyPin = null;
    lastFrequency = null;
    _dirty = false;
  }

  /// Pushes the requested configuration to the emulator if it changed.
  bool flush() {
    if (!_dirty) return false;
    _dirty = false;
    AVRBridge.servoPins = _pulsePins.toList();
    AVRBridge.buzzerPin = _frequencyPin;
    return true;
  }

  @visibleForTesting
  Set<int> get pulsePins => Set.unmodifiable(_pulsePins);

  @visibleForTesting
  int? get frequencyPin => _frequencyPin;
}

/// [PartI2cApi] backed by the emulator's TWI peripheral.
///
/// Stateless, unlike [EnginePinApi]: there is nothing per-component to cache,
/// because the bus is one shared wire and an address is the whole question.
/// Claiming on every drain is deliberate — it costs a set insertion and means
/// a display dropped onto a running canvas starts being recorded the first
/// frame its logic runs, with no separate registration step to forget.
class const EngineI2cApi() implements PartI2cApi {
  @override
  List<List<int>> drain(int address) {
    AVRBridge.listenI2c(address);
    return AVRBridge.drainI2c(address);
  }

  @override
  void serve(int address, {int size = 256, int pointerBytes = 1}) =>
      AVRBridge.serveI2c(address, size: size, pointerBytes: pointerBytes);

  @override
  void setRegisters(int address, int offset, List<int> bytes) =>
      AVRBridge.setI2cRegisters(address, offset, bytes);
}

/// [PartSpiceApi] backed by the running solver.
class const EngineSpiceApi({
  required final ComponentInstance node,
  required final SpiceEngine spiceEngine,
  @override required final bool isActive,
}) implements PartSpiceApi {
  @override
  double current() => isActive ? spiceEngine.getLedCurrent(node.key.toString()) : 0;
}
