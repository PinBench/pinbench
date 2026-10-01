import '../config/avr_config.dart';

/// Detects audio frequency from a toggling digital pin.
///
/// Tracks half-period deltas in CPU cycles, stabilizes over 4 consecutive
/// toggles, and signals both frequency detection and tone-stop events.
///
/// Cycles of [clockHz], whatever board is running: every threshold below is a
/// time, written in microseconds and turned into cycles once. They were
/// written as 16 MHz cycle counts while the Uno was the only board, and a
/// 125 MHz Pico would have read each one eight times too short.
class FrequencyDetector {
  new({this.clockHz = AVRConfig.clockFrequency})
    : _minHalfPeriod = _cycles(25, clockHz),
      _maxHalfPeriod = _cycles(25000, clockHz),
      _pitchTolerance = _cycles(125, clockHz),
      _defaultTimeoutCycles = _cycles(10000, clockHz),
      _minTimeoutCycles = _cycles(250, clockHz),
      _timeoutCycles = _cycles(10000, clockHz);

  final int clockHz;

  static int _cycles(double us, int clockHz) => (us * clockHz / 1e6).round();

  /// Valid audible range: 20 Hz to 20 kHz, as half-periods.
  final int _minHalfPeriod;
  final int _maxHalfPeriod;

  /// How far a half-period may move before it counts as a new pitch.
  final int _pitchTolerance;

  final int _defaultTimeoutCycles;
  final int _minTimeoutCycles;

  var _lastToggleCycle = 0;
  var _prevDelta = 0;
  var _stableDelta = 0;
  var _stableCount = 0;
  int _timeoutCycles;
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

      if (deltaCycles > _minHalfPeriod && deltaCycles < _maxHalfPeriod) {
        if (_stableDelta == 0 || (_stableDelta - deltaCycles).abs() > _pitchTolerance) {
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
        if (_timeoutCycles < _minTimeoutCycles) _timeoutCycles = _minTimeoutCycles;

        if (_stableCount >= 4) {
          if (!_isTonePlaying || (_prevDelta - _stableDelta).abs() > _pitchTolerance) {
            _prevDelta = _stableDelta;
            var freq = clockHz / (2.0 * _stableDelta);

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

  /// Returns true and resets state when the tone times out (pin has been
  /// silent for [_timeoutCycles] cycles). The AVR asks every cycle; anything
  /// coarser stops the tone that much later.
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
