import '../config/avr_config.dart';

/// Detects audio frequency from a toggling digital pin.
///
/// Tracks half-period deltas in CPU cycles, stabilizes over 4 consecutive
/// toggles, and signals both frequency detection and tone-stop events.
class FrequencyDetector {
  static const _defaultTimeoutCycles = 160000;

  var _lastToggleCycle = 0;
  var _prevDelta = 0;
  var _stableDelta = 0;
  var _stableCount = 0;
  var _timeoutCycles = _defaultTimeoutCycles;
  var _isTonePlaying = false;

  bool get isTonePlaying => _isTonePlaying;

  void reset() {
    _lastToggleCycle = 0;
    _prevDelta = 0;
    _stableDelta = 0;
    _stableCount = 0;
    _timeoutCycles = _defaultTimeoutCycles;
    _isTonePlaying = false;
  }

  /// Called when the monitored pin toggles. Fires [onFrequencyChanged] when a
  /// stable frequency is detected or the pitch shifts significantly.
  void onPinToggle(int currentCycle, void Function(double freq) onFrequencyChanged) {
    if (_lastToggleCycle != 0) {
      final deltaCycles = currentCycle - _lastToggleCycle;

      // Valid audible range: 20 Hz (400,000 cycles/half) to 20 kHz (400 cycles/half)
      if (deltaCycles > 400 && deltaCycles < 400000) {
        if (_stableDelta == 0 || (_stableDelta - deltaCycles).abs() > 2000) {
          _stableDelta = deltaCycles;
          _stableCount = 1;
        } else {
          // Smoothed average — +2 before >>2 gives proper mathematical rounding
          // to prevent downward pitch drift over many toggles.
          _stableDelta = ((_stableDelta * 3) + deltaCycles + 2) ~/ 4;
          _stableCount++;
        }

        // Dynamically extend timeout to 4 full waveforms so even tiny 1ms gaps trigger stop.
        _timeoutCycles = _stableDelta * 4;
        if (_timeoutCycles < 4000) _timeoutCycles = 4000;

        if (_stableCount >= 4) {
          if (!_isTonePlaying || (_prevDelta - _stableDelta).abs() > 2000) {
            _prevDelta = _stableDelta;
            var freq = AVRConfig.clockFrequency / (2.0 * _stableDelta);

            // AVR Timer2 CTC mode has a slight offset (e.g. 2011 Hz instead of 2000 Hz).
            // Snap values within 20 Hz of 2000 to exactly 2000 for acoustic accuracy.
            if ((freq - 2000.0).abs() < 20.0) freq = 2000.0;

            _isTonePlaying = true;
            onFrequencyChanged(freq);
          }
        }
      }
    }
    _lastToggleCycle = currentCycle;
  }

  /// Must be called every CPU cycle. Returns true and resets state when the
  /// tone times out (pin has been silent for [_timeoutCycles] cycles).
  bool checkTimeout(int currentCycles) {
    if (_isTonePlaying &&
        _lastToggleCycle != 0 &&
        (currentCycles - _lastToggleCycle) > _timeoutCycles) {
      reset();
      return true;
    }
    return false;
  }
}
