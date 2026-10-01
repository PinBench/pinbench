import 'package:pinbench_parts/models/board_profile.dart';

import '../avr_interop.dart';
import 'board_emulator.dart';
import 'intel_hex.dart';

/// The Arduino Uno: [AVRBridge], which owns the one ATmega328P a process has.
///
/// Stateless and const — the bridge's state is static — so it costs nothing
/// to hold one before any run has started.
class const AvrBoardEmulator() implements BoardEmulator {
  @override
  BoardProfile get profile => BoardProfile.arduinoUno;

  /// The ATmega328P's flash ends at 32 KB; a program reaching past 64 KB was
  /// built for something else. A Pico's, at `0x10000000`, would otherwise
  /// load as its low 16 address bits and run as garbage.
  static const _flashLimit = 0x10000;

  @override
  void loadHex(String hex, {void Function(String line)? onSerialPrint}) {
    final segments = IntelHex.decode(hex);
    if (segments.any((s) => s.address >= _flashLimit)) {
      throw const FormatException(
        'This program was built for a different board, not the Arduino Uno on the canvas.',
      );
    }
    AVRBridge.loadHex(hex, onSerialPrint: onSerialPrint);
  }

  @override
  void tick(int cycles) => AVRBridge.tick(cycles);

  @override
  int getCycles() => AVRBridge.getCycles();

  @override
  bool getPinState(int pin) => AVRBridge.getPinState(pin);

  @override
  double getPinDuty(int pin) => AVRBridge.getPinDuty(pin);

  @override
  bool isPinOutput(int pin) => AVRBridge.isPinOutput(pin);

  @override
  void setDigitalPin(int pin, {required bool isHigh}) =>
      AVRBridge.setDigitalPin(pin, isHigh: isHigh);

  @override
  void playWaveform(int pin, List<(bool, double)> levels, {double gapUs = 0}) =>
      AVRBridge.playWaveform(pin, levels, gapUs: gapUs);

  @override
  bool isPinDriven(int pin) => AVRBridge.isPinDriven(pin);

  @override
  void setAnalogVoltage(int channel, double voltage) =>
      AVRBridge.setAnalogVoltage(channel, voltage);

  @override
  void queueSerialInput(String text) => AVRBridge.queueSerialInput(text);

  @override
  List<int> get servoPins => AVRBridge.servoPins;

  @override
  set servoPins(List<int> pins) => AVRBridge.servoPins = pins;

  @override
  double getServoPulseUs(int pin) => AVRBridge.getServoPulseUs(pin);

  @override
  int? get buzzerPin => AVRBridge.buzzerPin;

  @override
  set buzzerPin(int? pin) => AVRBridge.buzzerPin = pin;

  @override
  void Function(double? hz)? get onBuzzerFrequencyChanged => AVRBridge.onBuzzerFrequencyChanged;

  @override
  set onBuzzerFrequencyChanged(void Function(double? hz)? callback) =>
      AVRBridge.onBuzzerFrequencyChanged = callback;

  @override
  bool get isBuiltinLedOn => AVRBridge.isBuiltinLedOn;

  @override
  void listenI2c(int address) => AVRBridge.listenI2c(address);

  @override
  List<List<int>> drainI2c(int address) => AVRBridge.drainI2c(address);

  @override
  void serveI2c(int address, {int size = 256, int pointerBytes = 1}) =>
      AVRBridge.serveI2c(address, size: size, pointerBytes: pointerBytes);

  @override
  void setI2cRegisters(int address, int offset, List<int> bytes) =>
      AVRBridge.setI2cRegisters(address, offset, bytes);
}
