import 'dart:js_interop';

/// Web [AVRBridge] backed by `avr8js` via the `window.AVR8` bridge defined in
/// `web/avr_bridge.js`. Mirrors the native `avr_interop_io.dart` API but runs
/// the emulator in optimized JS so the 16 MHz AVR keeps real time.
@JS('AVR8')
external _Avr8 get _avr8;

extension type _Avr8._(JSObject _) implements JSObject {
  external void setSerialPrint(JSFunction cb);
  external void setBuzzerFrequencyCallback(JSFunction cb);
  external void setBuzzerPin(JSAny? pin);
  external void setServoPins(JSArray<JSNumber> pins);
  external double getServoPulseUs(int pin);
  external void loadHex(String hex);
  external void queueSerialInput(String text);
  external void tick(int cycles);
  external bool getPinState(int pin);
  external double getPinDuty(int pin);
  external bool isPinOutput(int pin);
  // Positional args mirror the JS bridge signature.
  // ignore: avoid_positional_boolean_parameters
  external void setDigitalPin(int pin, bool isHigh);
  external void setAnalogVoltage(int channel, double voltage);
  external int getPortBValue();
  external int getCycles();
  external bool getPin13State();
  external void listenI2c(int address);
  external JSInt32Array drainI2c(int address);
}

class AVRBridge._() {
  static void Function(double?)? onBuzzerFrequencyChanged;

  static int? _buzzerPin;
  static int? get buzzerPin => _buzzerPin;
  static set buzzerPin(int? pin) {
    _buzzerPin = pin;
    _avr8.setBuzzerPin(pin?.toJS);
  }

  static List<int> _servoPins = const [];
  static List<int> get servoPins => _servoPins;
  static set servoPins(List<int> pins) {
    _servoPins = pins;
    _avr8.setServoPins(pins.map((p) => p.toJS).toList().toJS);
  }

  static double getServoPulseUs(int pin) => _avr8.getServoPulseUs(pin);

  static var _wired = false;

  static void _ensureBuzzerWired() {
    if (_wired) return;
    _wired = true;
    _avr8.setBuzzerFrequencyCallback(
      ((JSAny? freq) {
        onBuzzerFrequencyChanged?.call(freq == null ? null : (freq as JSNumber).toDartDouble);
      }).toJS,
    );
  }

  static void loadHex(String hexString, {void Function(String)? onSerialPrint}) {
    _ensureBuzzerWired();
    _avr8.setSerialPrint(((String line) => onSerialPrint?.call(line)).toJS);
    _avr8.loadHex(hexString);
  }

  static void queueSerialInput(String text) => _avr8.queueSerialInput(text);

  static void tick(int cycles) => _avr8.tick(cycles);

  static bool getPinState(int pin) => _avr8.getPinState(pin);

  static double getPinDuty(int pin) => _avr8.getPinDuty(pin);

  static bool isPinOutput(int pin) => _avr8.isPinOutput(pin);

  static void setDigitalPin(int pin, {required bool isHigh}) => _avr8.setDigitalPin(pin, isHigh);

  static void setAnalogVoltage(int channel, double voltage) =>
      _avr8.setAnalogVoltage(channel, voltage);

  static int getPortBValue() => _avr8.getPortBValue();

  static int getCycles() => _avr8.getCycles();

  static bool getPin13State() => _avr8.getPin13State();

  static bool get isBuiltinLedOn => getPin13State();

  /// Claims [address] on the I²C bus, so a device at it acknowledges and its
  /// traffic is kept for [drainI2c].
  static void listenI2c(int address) => _avr8.listenI2c(address);

  /// Every transaction written to [address] since the last call.
  ///
  /// The bridge hands the whole frame's traffic over as one flat typed array —
  /// `[length, ...bytes]` per transaction — rather than a nested array of
  /// numbers, so a screen refresh crosses the JS boundary as a single copy
  /// instead of a thousand boxed values.
  static List<List<int>> drainI2c(int address) {
    final flat = _avr8.drainI2c(address).toDart;
    final transactions = <List<int>>[];
    var at = 0;
    while (at < flat.length) {
      final length = flat[at++];
      if (length <= 0 || at + length > flat.length) break;
      transactions.add(flat.sublist(at, at + length));
      at += length;
    }
    return transactions;
  }
}
