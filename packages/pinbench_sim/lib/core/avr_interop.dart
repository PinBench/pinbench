// Selects the AVR emulator backend at compile time.
//
// Native platforms use the pure-Dart `avr8_dart` port. The web delegates to
// `avr8js` (optimized JS, real-time on the 16 MHz ATmega328P) via the bridge in
// `web/avr_bridge.js`, because `avr8_dart` compiled by dart2js is too slow to
// keep real time (so time-based sketches lag). Both expose the same `AVRBridge`
// static API used by the simulation engine.
export 'avr_interop_io.dart' if (dart.library.js_interop) 'avr_interop_web.dart';
