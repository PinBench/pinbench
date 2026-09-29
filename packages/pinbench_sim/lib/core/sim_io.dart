/// Platform-free I/O seams for the simulation engine.
///
/// The engine must be able to run inside a background isolate, where the audio
/// (buzzer) and microphone platform plugins are unavailable. Instead of calling
/// those singletons directly, the engine reads the mic through [MicInput] and
/// emits buzzer frequency changes through a plain callback. The owner (the
/// runner, on the UI isolate) supplies real implementations; the isolate feeds a
/// mutable holder fed by streamed readings; tests use [SilentMicInput].
library;

/// Latest microphone reading the engine should inject into the ADC/SPICE model
/// each frame. Implementations are cheap synchronous getters.
abstract class MicInput {
  double get analogVoltage;
  bool get isDigitalHigh;
}

/// The microphone as a *device*: [MicInput]'s readings plus the lifecycle of
/// opening and closing it.
///
/// A port, because a microphone is a host device. The engine should be able to
/// run with a real one, with a stream of readings forwarded from another
/// isolate, or with nothing at all — and it should not have to know which, nor
/// carry a recording plugin to find out.
abstract interface class MicrophoneDevice implements MicInput {
  /// Opens the device. May fail (permission denied, no hardware, unsupported
  /// on the web) — callers treat that as "no microphone" rather than an error,
  /// because a circuit with a mic part on it should still run.
  Future<void> init();

  Future<void> dispose();
}

/// Where the simulation's tones are played.
///
/// The other half of the same story: a speaker is the host's, not the
/// emulator's. The engine decides *that* a tone should sound and at what
/// pitch; this decides how.
abstract interface class ToneOutput {
  Future<void> init();
  void playTone(double frequency);
  void stopTone();
  void dispose();
}

/// A mic that reports silence — the default when no microphone is wired in, in
/// tests, and as the isolate's starting state before any reading streams in.
class SilentMicInput implements MicInput {
  const SilentMicInput();

  @override
  double get analogVoltage => 0.0;

  @override
  bool get isDigitalHigh => false;
}

/// A mutable [MicInput] whose value is updated from outside (e.g. by streamed
/// `MicReading` messages inside the simulation isolate).
class MutableMicInput implements MicInput {
  @override
  var analogVoltage = 0.0;

  @override
  var isDigitalHigh = false;

  void set(double volts, {required bool isHigh}) {
    analogVoltage = volts;
    isDigitalHigh = isHigh;
  }
}
