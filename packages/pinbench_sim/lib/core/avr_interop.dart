// Selects the AVR emulator backend at compile time.
//
// Both run the same code: the pure-Dart `avr8_dart` port behind the native
// `AVRBridge` in `avr_interop_io.dart`. Native platforms call it directly. The
// web app is WebAssembly, where that integer-heavy loop runs at about half the
// speed of JavaScript, so the web instead calls a dart2js build of the same
// bridge (`web/avr_bridge.js`, built by `tools/build_avr_bridge.sh`) through
// the `window.AVR8` facade in `avr_interop_web.dart`. Both expose the same
// `AVRBridge` static API used by the simulation engine.
export 'avr_interop_io.dart' if (dart.library.js_interop) 'avr_interop_web.dart';
