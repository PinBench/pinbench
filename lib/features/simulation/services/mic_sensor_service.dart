import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:record/record.dart';
import 'package:pinbench_sim/core/sim_io.dart';
import 'package:pinbench_sim/core/sim_log.dart';

class MicSensorService implements MicrophoneDevice {
  static const _log = SimLog('app.simulation.mic');
  AudioRecorder? _audioRecorder;
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<Uint8List>? _audioStreamSub;

  // Decibels range from approx -160 to 0.
  var currentAmplitudeDb = -160.0;

  // Fixed threshold for digital output (D0)
  // e.g., if louder than -10 dB, trigger HIGH
  var thresholdDb = -10.0;

  var _isInitialized = false;

  MicSensorService._();
  static final instance = MicSensorService._();

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _audioRecorder = AudioRecorder();
      if (await _audioRecorder!.hasPermission()) {
        final stream = await _audioRecorder!.startStream(
          const RecordConfig(encoder: AudioEncoder.pcm16bits, numChannels: 1),
        );

        // We must drain the stream otherwise it might block or cause issues
        _audioStreamSub = stream.listen((_) {});

        _amplitudeSub = _audioRecorder!.onAmplitudeChanged(const Duration(milliseconds: 50)).listen(
          (amp) {
            currentAmplitudeDb = amp.current;
          },
        );

        _isInitialized = true;
      } else {
        _log.warning('Microphone permission denied.');
      }
    } catch (e, stackTrace) {
      _log.error('Error initializing MicSensorService', error: e, stackTrace: stackTrace);
    }
  }

  @override
  double get analogVoltage {
    // Map -60dB -> 0dB to 0.0 -> 5.0V for sensitivity
    const minDb = -60.0;
    const maxDb = 0.0;

    var db = currentAmplitudeDb;
    if (db < minDb) db = minDb;
    if (db > maxDb) db = maxDb;

    final normalized = (db - minDb) / (maxDb - minDb);
    return normalized * 5.0;
  }

  @override
  bool get isDigitalHigh => currentAmplitudeDb > thresholdDb;

  @override
  Future<void> dispose() async {
    if (!_isInitialized) return;
    _isInitialized = false;

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    await _audioStreamSub?.cancel();
    _audioStreamSub = null;

    try {
      await _audioRecorder?.stop();
      await _audioRecorder?.dispose();
    } catch (e) {
      _log.warning('Error during dispose (ignored): $e');
    }
    _audioRecorder = null;
  }
}
