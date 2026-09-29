import 'dart:collection';

/// Per-frame timing breakdown in microseconds.
class FrameSample {
  /// Time spent in _updateDigitalInputs + _updateMicSensors.
  final int inputsUs;

  /// Time spent in AVRBridge.tick (CPU emulation).
  final int avrUs;

  /// Time spent in SpiceEngine.solve.
  final int spiceUs;

  /// Time spent in _updateAnalogLeds + _flushFrameUpdates.
  final int ledsUs;

  /// Total frame time from start to canvas flush.
  final int totalUs;

  const FrameSample({
    required this.inputsUs,
    required this.avrUs,
    required this.spiceUs,
    required this.ledsUs,
    required this.totalUs,
  });

  /// True when this frame exceeded the 16 ms budget.
  bool get dropped => totalUs > 16000;

  double get totalMs => totalUs / 1000.0;
}

/// Aggregated stats over the most recent [FrameProfiler.maxSamples] frames.
class FrameStats {
  final double avgFps;
  final double avgTotalMs;
  final double avgAvrMs;
  final double avgSpiceMs;
  final int droppedFrames;
  final int sampleCount;

  const FrameStats({
    required this.avgFps,
    required this.avgTotalMs,
    required this.avgAvrMs,
    required this.avgSpiceMs,
    required this.droppedFrames,
    required this.sampleCount,
  });

  const FrameStats.empty()
    : avgFps = 0,
      avgTotalMs = 0,
      avgAvrMs = 0,
      avgSpiceMs = 0,
      droppedFrames = 0,
      sampleCount = 0;
}

/// Collects per-frame timing samples from SimulationEngine and computes
/// rolling statistics over the last maxSamples frames.
///
/// Enable profiling via [enabled]; the engine checks this flag each frame
/// so there is zero overhead when profiling is off.
class FrameProfiler {
  static const maxSamples = 120; // 2 seconds at 60 fps

  final _samples = ListQueue<FrameSample>(maxSamples + 1);
  var enabled = false;

  void record(FrameSample sample) {
    if (!enabled) return;
    _samples.addLast(sample);
    if (_samples.length > maxSamples) _samples.removeFirst();
  }

  void clear() => _samples.clear();

  /// A read-only view of the raw sample buffer (oldest first).
  Iterable<FrameSample> get samples => _samples;

  FrameStats get stats {
    if (_samples.isEmpty) return const FrameStats.empty();
    final n = _samples.length;

    var totalUs = 0;
    var avrUs = 0;
    var spiceUs = 0;
    var dropped = 0;

    for (final s in _samples) {
      totalUs += s.totalUs;
      avrUs += s.avrUs;
      spiceUs += s.spiceUs;
      if (s.dropped) dropped++;
    }

    final avgTotalUs = totalUs / n;
    return FrameStats(
      avgFps: avgTotalUs > 0 ? 1000000.0 / avgTotalUs : 0,
      avgTotalMs: avgTotalUs / 1000.0,
      avgAvrMs: avrUs / n / 1000.0,
      avgSpiceMs: spiceUs / n / 1000.0,
      droppedFrames: dropped,
      sampleCount: n,
    );
  }
}
