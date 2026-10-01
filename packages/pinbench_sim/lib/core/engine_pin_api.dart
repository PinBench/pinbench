import 'package:flutter/foundation.dart';

import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/port_model.dart';
import 'package:pinbench_parts/logic/part_logic.dart';

import 'board/board_emulator.dart';
import 'circuit_netlist.dart';
import 'spice_engine.dart';

/// [PartPinApi] backed by the real netlist and the board's emulator.
///
/// One per placed component per run — it caches the port→pin tracing, which is
/// a netlist walk that cannot change mid-run because the canvas is read-only
/// while simulating.
class EnginePinApi({
  required final ComponentInstance node,
  required final CircuitNetlist netlist,
  required final BoardEmulator board,
  required final ComponentInstance? boardNode,

  /// What the emulator has been asked to measure, shared across every
  /// instance so the engine reconciles it once — see [EmulatorMeasurements].
  required final EmulatorMeasurements measurements,
}) implements PartPinApi {
  final _traced = <String, List<String>>{};

  @override
  int? connectedTo(String portId) {
    // A port that reaches the board on one of its numbered pins *is* that
    // pin. Scanned rather than taken from [boardPortFor], because a net can
    // touch the board more than once and only one of those touches is a
    // numbered pin — the signal is what a caller asking for a *pin* means.
    for (final boardPort in _boardPortsFor(portId)) {
      if (int.tryParse(boardPort) case final pin? when board.profile.digitalPins.contains(pin)) {
        return pin;
      }
    }
    return null;
  }

  @override
  String? boardPortFor(String portId) => _boardPortsFor(portId).firstOrNull;

  @override
  I2cLine? i2cLineFor(String portId) {
    for (final boardPort in _boardPortsFor(portId)) {
      if (board.profile.i2cLineAt(boardPort) case final line?) return line;
    }
    return null;
  }

  /// Every port of the board this component's [portId] reaches, by the board's
  /// own name for each.
  List<String> _boardPortsFor(String portId) => _traced.putIfAbsent(portId, () {
    final boardKey = boardNode?.key;
    if (boardKey == null) return const <String>[];
    // This one walk replaced `CircuitTopologyIndexer` entirely: it held three
    // near-identical tracers, one per part type, each hard-coding the port
    // names it knew about (a servo's `signal`, an LED's `anode`/`cathode`, a
    // buzzer's `plus`). Asking on behalf of a part, with the port name as an
    // argument, is the same walk without the catalogue.
    return [
      for (final port in netlist.findConnectedPorts(
        PortLocation(nodeKey: node.key, portId: portId),
      ))
        if (port.nodeKey == boardKey) port.portId,
    ];
  });

  @override
  double duty(int pin) => board.getPinDuty(pin);

  @override
  double pulseUs(int pin) {
    measurements.addPulsePin(pin);
    return board.getServoPulseUs(pin);
  }

  @override
  double? frequencyOn(int pin) {
    measurements.requestFrequencyPin(pin);
    return measurements.lastFrequency;
  }

  @override
  bool isHigh(int pin) => board.getPinState(pin);
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

  /// Pushes the requested configuration to [board] if it changed.
  bool flush(BoardEmulator board) {
    if (!_dirty) return false;
    _dirty = false;
    board.servoPins = _pulsePins.toList();
    board.buzzerPin = _frequencyPin;
    return true;
  }

  @visibleForTesting
  Set<int> get pulsePins => Set.unmodifiable(_pulsePins);

  @visibleForTesting
  int? get frequencyPin => _frequencyPin;
}

/// [PartI2cApi] backed by the board's I²C peripheral.
///
/// Stateless, unlike [EnginePinApi]: there is nothing per-component to cache,
/// because the bus is one shared wire and an address is the whole question.
/// Claiming on every drain is deliberate — it costs a set insertion and means
/// a display dropped onto a running canvas starts being recorded the first
/// frame its logic runs, with no separate registration step to forget.
class const EngineI2cApi(final BoardEmulator board) implements PartI2cApi {
  @override
  List<List<int>> drain(int address) {
    board.listenI2c(address);
    return board.drainI2c(address);
  }

  @override
  void serve(int address, {int size = 256, int pointerBytes = 1}) =>
      board.serveI2c(address, size: size, pointerBytes: pointerBytes);

  @override
  void setRegisters(int address, int offset, List<int> bytes) =>
      board.setI2cRegisters(address, offset, bytes);
}

/// [PartSpiceApi] backed by the running solver.
class const EngineSpiceApi({
  required final ComponentInstance node,
  required final SpiceEngine spiceEngine,
  @override required final bool isActive,
}) implements PartSpiceApi {
  @override
  double current() => isActive ? spiceEngine.getLedCurrent(node.key.toString()) : 0;

  @override
  double pinCurrent(String pinId) => isActive ? spiceEngine.portCurrent(node.key, pinId) : 0;
}
