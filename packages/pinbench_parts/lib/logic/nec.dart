/// The NEC infrared remote protocol, as a demodulating IR receiver's output
/// sees it.
///
/// A remote sends 38 kHz bursts; a receiver like the VS1838B strips the
/// carrier and pulls its OUT pin low for as long as a burst lasts, so what a
/// sketch reads is a train of low "marks" and high "spaces". NEC sends a 9 ms
/// mark and a 4.5 ms space, then 32 bits — address, inverted address,
/// command, inverted command, each least-significant bit first — every bit a
/// 562.5 µs mark followed by a space that says what it is, and a final mark to
/// close the last space.
abstract final class Nec {
  static const leadMarkUs = 9000.0;
  static const leadSpaceUs = 4500.0;
  static const bitMarkUs = 562.5;
  static const zeroSpaceUs = 562.5;
  static const oneSpaceUs = 1687.5;

  /// The quiet a remote leaves after a frame before the next: NEC frames
  /// start 108 ms apart, and a frame lasts 68 ms.
  static const frameGapUs = 40000.0;

  /// The levels OUT goes through for one press of [command] on a remote at
  /// [address]: `(isHigh, microseconds)` pairs, ending back at idle high.
  static List<(bool, double)> frame(int address, int command) {
    final bytes = [address, ~address, command, ~command];
    final levels = <(bool, double)>[(false, leadMarkUs), (true, leadSpaceUs)];
    for (final byte in bytes) {
      for (var bit = 0; bit < 8; bit++) {
        final one = (byte >> bit) & 1 == 1;
        levels
          ..add((false, bitMarkUs))
          ..add((true, one ? oneSpaceUs : zeroSpaceUs));
      }
    }
    levels.add((false, bitMarkUs));
    // Back to idle: the receiver's pull-up holds OUT high between presses.
    levels.add((true, 0));
    return levels;
  }

  /// Reads a frame back: the address and command it carries, or null if
  /// [levels] is not a well-formed NEC frame. The inverse of [frame], with a
  /// receiver's tolerance — a quarter either way on the leader, and a space
  /// read as a 1 when it is longer than a 0 and a 1 average — so it reads a
  /// measured waveform as well as a generated one.
  static (int address, int command)? decode(List<(bool, double)> levels) {
    if (levels.length < 2 + 64 + 1) return null;
    bool near(double us, double nominal) => (us - nominal).abs() <= nominal / 4;
    final (leadLow, leadMark) = levels[0];
    final (leadHigh, leadSpace) = levels[1];
    if (leadLow || !near(leadMark, leadMarkUs) || !leadHigh || !near(leadSpace, leadSpaceUs)) {
      return null;
    }
    var value = 0;
    for (var i = 0; i < 32; i++) {
      final (isHigh, us) = levels[2 + 2 * i + 1];
      if (!isHigh) return null;
      if (us > (zeroSpaceUs + oneSpaceUs) / 2) value |= 1 << i;
    }
    final address = value & 0xFF;
    final command = (value >> 16) & 0xFF;
    if ((value >> 8) & 0xFF != (~address & 0xFF)) return null;
    if ((value >> 24) & 0xFF != (~command & 0xFF)) return null;
    return (address, command);
  }
}
