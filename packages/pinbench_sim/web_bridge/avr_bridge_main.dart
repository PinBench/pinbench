/// The web's ATmega328P: the same `avr8_dart` emulator and [AVRBridge] the
/// desktop runs, compiled by dart2js into `web/avr_bridge.js` and exposed as
/// `window.AVR8` for the app's web facade (`lib/core/avr_interop_web.dart`).
///
/// Why a separate dart2js build rather than calling [AVRBridge] from the app
/// directly: the web app ships as WebAssembly, and dart2wasm runs this
/// integer-heavy loop at about half the speed of dart2js (≈2× real time
/// against ≈4.4×, measured on the OLED template's firmware). JavaScript is the
/// faster home for the CPU, so the CPU lives there, and the app crosses into
/// it once per frame, exactly as it did when this was `avr8js`.
///
/// Build with `tools/build_avr_bridge.sh`; never edit `web/avr_bridge.js` by
/// hand.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pinbench_sim/core/avr_interop_io.dart';

void main() {
  globalContext['AVR8'] = createJSInteropWrapper(_Avr8());
}

/// The `window.AVR8` object. Method names and argument order are the contract
/// with the web facade's `_Avr8` extension type; change both together.
@JSExport()
class _Avr8 {
  JSFunction? _serialPrint;

  void setSerialPrint(JSFunction callback) => _serialPrint = callback;

  void setBuzzerFrequencyCallback(JSFunction callback) {
    AVRBridge.onBuzzerFrequencyChanged = (hz) => callback.callAsFunction(null, hz?.toJS);
  }

  void setBuzzerPin(JSNumber? pin) => AVRBridge.buzzerPin = pin?.toDartInt;

  void setServoPins(JSArray<JSNumber>? pins) =>
      AVRBridge.servoPins = [for (final pin in pins?.toDart ?? const <JSNumber>[]) pin.toDartInt];

  double getServoPulseUs(int pin) => AVRBridge.getServoPulseUs(pin);

  void loadHex(String hex) => AVRBridge.loadHex(hex, onSerialPrint: _printLine);

  /// `Serial.println` ends lines with CRLF and the USART splits on the LF, so
  /// the CR is dropped here, where the web always dropped it.
  void _printLine(String line) {
    final text = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    _serialPrint?.callAsFunction(null, text.toJS);
  }

  void queueSerialInput(String text) => AVRBridge.queueSerialInput(text);

  void tick(int cycles) => AVRBridge.tick(cycles);

  bool getPinState(int pin) => AVRBridge.getPinState(pin);

  double getPinDuty(int pin) => AVRBridge.getPinDuty(pin);

  bool isPinOutput(int pin) => AVRBridge.isPinOutput(pin);

  // Positional, like the facade's call.
  // ignore: avoid_positional_boolean_parameters
  void setDigitalPin(int pin, bool isHigh) => AVRBridge.setDigitalPin(pin, isHigh: isHigh);

  void setAnalogVoltage(int channel, double voltage) =>
      AVRBridge.setAnalogVoltage(channel, voltage);

  int getPortBValue() => AVRBridge.getPortBValue();

  int getCycles() => AVRBridge.getCycles();

  bool getPin13State() => AVRBridge.getPin13State();

  void listenI2c(int address) => AVRBridge.listenI2c(address);

  /// The frame's traffic as one flat typed array, `[length, ...bytes]` per
  /// transaction, so it crosses into the app as a single copy.
  JSInt32Array drainI2c(int address) {
    final transactions = AVRBridge.drainI2c(address);
    var total = 0;
    for (final t in transactions) {
      total += t.length + 1;
    }
    final flat = Int32List(total);
    var at = 0;
    for (final t in transactions) {
      flat[at++] = t.length;
      flat.setAll(at, t);
      at += t.length;
    }
    return flat.toJS;
  }

  void serveI2c(int address, int size, int pointerBytes) =>
      AVRBridge.serveI2c(address, size: size, pointerBytes: pointerBytes);

  void setI2cRegisters(int address, int offset, JSInt32Array bytes) =>
      AVRBridge.setI2cRegisters(address, offset, bytes.toDart);
}
