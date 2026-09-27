import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'buzzer_backend.dart';

/// Web buzzer backend using the Web Audio API.
///
/// `flutter_soloud` does not initialise in the browser, so the tone is produced
/// by a single persistent sawtooth [web.OscillatorNode] whose audibility is
/// toggled via a [web.GainNode] (the oscillator runs continuously; gain 0 =
/// silent). The [web.AudioContext] is resumed inside the user's "Run" gesture,
/// satisfying the browser autoplay policy.
class BuzzerBackendImpl implements BuzzerBackend {
  // A sawtooth at full gain is harsh; keep it modest but clearly audible.
  static const _volume = 0.3;

  web.AudioContext? _ctx;
  web.OscillatorNode? _osc;
  web.GainNode? _gain;
  var _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<void> init() async {
    if (_ready) return;
    final ctx = web.AudioContext();
    try {
      await ctx.resume().toDart;
    } catch (_) {
      // A suspended context still works once a gesture resumes it.
    }
    final osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.value = 440;
    final gain = ctx.createGain();
    gain.gain.value = 0;
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    _ctx = ctx;
    _osc = osc;
    _gain = gain;
    _ready = true;
  }

  @override
  void setFrequency(double hz) => _osc?.frequency.value = hz;

  @override
  void start() => _gain?.gain.value = _volume;

  @override
  void stop() => _gain?.gain.value = 0;

  @override
  void dispose() {
    try {
      _osc?.stop();
    } catch (_) {}
    _ctx?.close();
    _osc = null;
    _gain = null;
    _ctx = null;
    _ready = false;
  }
}
