import 'buzzer_backend_web.dart' if (dart.library.io) 'buzzer_backend_io.dart';

/// Low-level audio backend for the piezo buzzer tone.
///
/// Chosen at compile time: `flutter_soloud` on native platforms, and the Web
/// Audio API on the web (where `flutter_soloud` fails to initialise). The
/// shared frequency/pitch logic lives in `BuzzerService`; this just drives a
/// single continuous tone whose pitch and audibility can be changed.
abstract interface class BuzzerBackend {
  factory() = BuzzerBackendImpl;

  /// Prepares the audio engine. Must be safe to call more than once.
  Future<void> init();

  /// Whether [init] succeeded and the backend can produce sound.
  bool get isReady;

  /// Sets the tone frequency in Hz.
  void setFrequency(double hz);

  /// Makes the tone audible.
  void start();

  /// Silences the tone.
  void stop();

  /// Tears down the audio engine.
  void dispose();
}
