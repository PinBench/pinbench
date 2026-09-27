import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How a solved wire current becomes something you can see.
///
/// The hard part is range. A pull-up trickles a few microamps; an LED at full
/// tilt pulls tens of milliamps. That is five decades, so anything linear shows
/// one of them and nothing else — every wire in a teaching circuit would look
/// either dead or identical. Everything here is therefore driven off a
/// logarithmic position between [minAmps] and [maxAmps].
///
/// Magnitude is spent on four channels at once, because no single one survives
/// being scaled logarithmically: dot *speed* (the channel the eye reads first,
/// and the one Falstad relies on), dot size, dot brightness, and a glow around
/// the wire. Size, brightness and glow are shaped harder than speed so that the
/// middle of the range — where a browned-out part sits — pulls visibly away
/// from the top, and so that a still screenshot still shows the difference.
abstract final class WireFlow {
  /// Below this, a wire is drawn as if nothing were flowing. A hair under the
  /// microamp leakage a reverse-biased junction shows in the operating point.
  static const minAmps = 1e-6;

  /// The top of the scale — roughly an Uno pin at its absolute limit. Currents
  /// above this look the same as this.
  static const maxAmps = 1e-1;

  /// Gap between dots, in canvas pixels. Constant on purpose: spacing that
  /// varied with current would read as charge density, which is not what is
  /// being measured.
  static const dotSpacing = 26.0;

  static final _decades = math.log(maxAmps / minAmps);

  /// Where [amps] sits on the log scale, 0 (nothing flowing) to 1 (full scale).
  static double intensity(double amps) {
    final magnitude = amps.abs();
    if (!magnitude.isFinite || magnitude <= minAmps) return 0;
    return (math.log(magnitude / minAmps) / _decades).clamp(0.0, 1.0);
  }

  /// Extra contrast for everything except speed — see the class doc.
  static double _shaped(double t) => t * t * math.sqrt(t);

  /// Dot travel in canvas pixels per second.
  static double speed(double t) => 14 + t * 136;

  static double dotRadius(double t) => 1.4 + _shaped(t) * 2.0;

  static double dotOpacity(double t) => 0.42 + _shaped(t) * 0.58;

  /// A halo around the wire itself, so current is legible in a still image and
  /// not only in motion. Squared, so it stays reserved for genuinely hot wires.
  static double glowOpacity(double t) => t * t * 0.4;

  static double glowWidth(double t) => 3 + t * 7;

  /// Dots run from a dim amber at the bottom of the scale to white-hot at the
  /// top, which is the one channel that survives being viewed at low zoom.
  static Color dotColor(double t) =>
      Color.lerp(const Color(0xFFFFAE42), const Color(0xFFFFF6E0), _shaped(t))!;
}

/// Monotonic seconds since the flow animation started, ticked with the display.
///
/// A plain [AnimationController] would not do: each wire advances its dots at
/// its own speed, so what the painter needs is elapsed *time*, not a normalised
/// 0–1 value. A controller that repeats would snap every wire's phase at each
/// wrap, since no wire's speed divides the period evenly.
class WireFlowClock extends ValueNotifier<double> {
  WireFlowClock(TickerProvider vsync) : super(0) {
    _ticker = vsync.createTicker((elapsed) {
      value = _resumedAt + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
  }

  late final Ticker _ticker;

  /// A [Ticker] restarts its elapsed time from zero, so pausing and resuming
  /// would snap every dot back to the same phase. Carrying the clock forward
  /// across the gap is what lets a paused run resume where it left off.
  var _resumedAt = 0.0;

  bool get isRunning => _ticker.isActive;

  void start() {
    if (_ticker.isActive) return;
    _resumedAt = value;
    _ticker.start();
  }

  void stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
