import 'package:pinbench_parts/models/board_profile.dart';

import 'avr_board.dart';
import 'pico_board.dart';

/// The microcontroller running the sketch, whichever board it is.
///
/// Everything the engine, the frame updaters and part logic ask of the chip,
/// and nothing about how it is emulated: an Uno is `avr8_dart` behind the
/// static `AVRBridge`, a Pico is `rp2040_dart`. Pins are numbered the way the
/// sketch numbers them (see [BoardProfile]) and time is counted in cycles of
/// the board's own clock, [BoardProfile.clockHz].
///
/// The method names are the bridge's, so code that drove the Uno directly
/// reads the same driving either board.
abstract class BoardEmulator {
  /// The emulator for [profile]'s board.
  factory forProfile(BoardProfile profile) =>
      identical(profile, BoardProfile.picoW) ? PicoBoardEmulator() : const AvrBoardEmulator();

  BoardProfile get profile;

  /// Loads [hex] — the compiled program, as Intel HEX — onto a freshly reset
  /// chip, with complete lines of serial output going to [onSerialPrint].
  ///
  /// Throws a [FormatException] whose message reads as an explanation when
  /// the program was built for another board.
  void loadHex(String hex, {void Function(String line)? onSerialPrint});

  /// Runs the chip for [cycles] clock cycles of simulated time.
  void tick(int cycles);

  /// Cycles run since the program was loaded.
  int getCycles();

  /// Whether the sketch is driving [pin] high.
  bool getPinState(int pin);

  /// Fraction of the last [tick] that [pin] was driven high — what
  /// `analogWrite` set, on a PWM pin.
  double getPinDuty(int pin);

  /// Whether the sketch has made [pin] an output.
  bool isPinOutput(int pin);

  /// Drives input [pin] from outside the chip.
  void setDigitalPin(int pin, {required bool isHigh});

  /// Plays [levels] into input [pin], each `(isHigh, microseconds)` holding
  /// for its time, exactly on the cycle — or [gapUs] after a waveform already
  /// playing there.
  void playWaveform(int pin, List<(bool, double)> levels, {double gapUs = 0});

  /// Whether a [playWaveform] waveform is still driving [pin].
  bool isPinDriven(int pin);

  /// Sets the voltage ADC [channel] reads.
  void setAnalogVoltage(int channel, double voltage);

  /// Queues [text] for the sketch's `Serial` to read.
  void queueSerialInput(String text);

  /// Pins whose HIGH-pulse widths to measure (servo signals).
  List<int> get servoPins;
  set servoPins(List<int> pins);

  /// Width of the last HIGH pulse on [pin], in microseconds; 0 before one.
  double getServoPulseUs(int pin);

  /// The pin whose tone frequency to detect, or null for none.
  int? get buzzerPin;
  set buzzerPin(int? pin);

  /// Told the detected tone on [buzzerPin], in hertz, or null when it stops.
  void Function(double? hz)? get onBuzzerFrequencyChanged;
  set onBuzzerFrequencyChanged(void Function(double? hz)? callback);

  /// Whether the board's own LED (`LED_BUILTIN`) is lit.
  bool get isBuiltinLedOn;

  /// Claims [address] on the I²C bus, so a device there acknowledges and its
  /// traffic is kept.
  void listenI2c(int address);

  /// Every transaction written to [address] since the last call.
  List<List<int>> drainI2c(int address);

  /// Makes [address] answer reads from a bank of [size] registers.
  void serveI2c(int address, {int size = 256, int pointerBytes = 1});

  /// Publishes [bytes] into [address]'s registers from [offset].
  void setI2cRegisters(int address, int offset, List<int> bytes);
}
