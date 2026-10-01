import 'dart:typed_data';

/// One run of bytes from an Intel HEX file, at the absolute address it loads
/// to.
typedef HexSegment = ({int address, Uint8List bytes});

/// Reads and writes Intel HEX, the text format every board's program travels
/// in here.
///
/// One format for every board, because a program is a `String` from the
/// compiler to the emulator — through the compile service's JSON, the
/// simulation isolate's messages, a template's `.ino.hex` and the "Load
/// Compiled .hex" menu — and none of that has to change for a board whose
/// toolchain writes a `.bin` instead. An AVR program needs only data records;
/// a Pico's lives at `0x10000000`, which the extended-linear-address records
/// reach.
abstract final class IntelHex {
  /// The data records in [text], each at its absolute address. Lines that are
  /// not records are skipped, as is anything after the end-of-file record.
  static List<HexSegment> decode(String text) {
    final segments = <HexSegment>[];
    var base = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.length < 11 || line[0] != ':') continue;
      int byteAt(int index) => int.parse(line.substring(1 + index * 2, 3 + index * 2), radix: 16);

      final length = byteAt(0);
      final offset = (byteAt(1) << 8) | byteAt(2);
      final type = byteAt(3);
      if (line.length < 11 + length * 2) {
        throw FormatException('Truncated Intel HEX record', line);
      }
      switch (type) {
        case 0x00:
          segments.add((
            address: base + offset,
            bytes: Uint8List.fromList([for (var i = 0; i < length; i++) byteAt(4 + i)]),
          ));
        case 0x01:
          return segments;
        case 0x02:
          base = ((byteAt(4) << 8) | byteAt(5)) << 4;
        case 0x04:
          base = ((byteAt(4) << 8) | byteAt(5)) << 16;
      }
    }
    return segments;
  }

  /// [bytes] as Intel HEX loading at [baseAddress], 16 bytes to a record.
  static String encode(Uint8List bytes, {int baseAddress = 0}) {
    final out = StringBuffer();
    void record(int type, int offset, List<int> data) {
      final fields = [data.length, (offset >> 8) & 0xff, offset & 0xff, type, ...data];
      final sum = fields.fold<int>(0, (a, b) => a + b);
      out.write(':');
      for (final byte in [...fields, (-sum) & 0xff]) {
        out.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      out.write('\n');
    }

    int? upper;
    for (var i = 0; i < bytes.length; i += 16) {
      final address = baseAddress + i;
      if (address >> 16 != upper) {
        upper = address >> 16;
        record(0x04, 0, [(upper >> 8) & 0xff, upper & 0xff]);
      }
      final end = i + 16 < bytes.length ? i + 16 : bytes.length;
      record(0x00, address & 0xffff, bytes.sublist(i, end));
    }
    record(0x01, 0, const []);
    return out.toString();
  }
}
