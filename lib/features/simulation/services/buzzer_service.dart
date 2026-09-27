import 'package:pinbench_sim/core/sim_io.dart';
import 'package:pinbench_sim/core/sim_log.dart';

import 'buzzer_backend.dart';

/// Plays the piezo buzzer tone for the running simulation.
///
/// Holds the platform-agnostic tone logic (pitch correction and change
/// thresholding) and delegates raw audio to a [BuzzerBackend] — `flutter_soloud`
/// on native, the Web Audio API on the web.
class BuzzerService implements ToneOutput {
  static const _log = SimLog('app.simulation.buzzer');

  final _backend = BuzzerBackend();
  double? _currentFrequency;
  var _isPlaying = false;

  BuzzerService._();

  static final instance = BuzzerService._();

  /// Piezo buzzers have a natural resonance that makes them sound higher-pitched
  /// than the raw driving frequency. This multiplier simulates that effect.
  static const _pitchMultiplier = 0.9;

  @override
  Future<void> init() => _backend.init();

  @override
  void playTone(double frequency) {
    if (!_backend.isReady) return;

    try {
      final actualFrequency = frequency * _pitchMultiplier;

      // Update the frequency only when it changes by more than 5Hz, to ignore
      // micro-fluctuations.
      if (_currentFrequency == null || (_currentFrequency! - actualFrequency).abs() > 5.0) {
        _backend.setFrequency(actualFrequency);
        _currentFrequency = actualFrequency;
      }

      if (!_isPlaying) {
        _backend.start();
        _isPlaying = true;
      }
    } catch (e, stackTrace) {
      _log.error('Error playing tone', error: e, stackTrace: stackTrace);
    }
  }

  @override
  void stopTone() {
    if (!_backend.isReady || !_isPlaying) return;
    _backend.stop();
    _isPlaying = false;
  }

  @override
  void dispose() {
    _isPlaying = false;
    _currentFrequency = null;
    _backend.dispose();
  }
}
