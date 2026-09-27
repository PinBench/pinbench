import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:pinbench_sim/core/sim_log.dart';

import 'buzzer_backend.dart';

/// Native buzzer backend backed by `flutter_soloud`.
///
/// A/B testing against the physical hardware recording confirmed that a Saw
/// waveform (with the 0.9x pitch multiplier applied by `BuzzerService`) best
/// recreates the piezo disc's acoustic character.
class BuzzerBackendImpl implements BuzzerBackend {
  static const _log = SimLog('app.simulation.buzzer');
  static const _volume = 1.0;

  AudioSource? _waveform;
  SoundHandle? _handle;
  var _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      await SoLoud.instance.init();
      _waveform = await SoLoud.instance.loadWaveform(
        WaveForm.saw,
        false, // Do NOT use superWave
        1.0, // scale (amplitude) — volume is controlled via the handle
        0.0, // detune
      );
      _ready = true;
    } catch (e, stackTrace) {
      _log.error('Error initializing SoLoud', error: e, stackTrace: stackTrace);
    }
  }

  @override
  void setFrequency(double hz) {
    final waveform = _waveform;
    if (waveform == null) return;
    SoLoud.instance.setWaveformFreq(waveform, hz);
  }

  @override
  void start() {
    final waveform = _waveform;
    if (waveform == null) return;
    final handle = _handle = SoLoud.instance.play(waveform, paused: true);
    SoLoud.instance.setPause(handle, false);
    SoLoud.instance.setVolume(handle, 0);
    SoLoud.instance.fadeVolume(handle, _volume, const Duration(milliseconds: 1));
  }

  @override
  void stop() {
    final handle = _handle;
    if (handle == null) return;
    unawaited(SoLoud.instance.stop(handle));
    _handle = null;
  }

  @override
  void dispose() {
    if (!_ready) return;
    final handle = _handle;
    if (handle != null) {
      unawaited(SoLoud.instance.stop(handle));
      _handle = null;
    }
    final waveform = _waveform;
    if (waveform != null) {
      unawaited(SoLoud.instance.disposeSource(waveform));
      _waveform = null;
    }
    SoLoud.instance.deinit();
    _ready = false;
  }
}
