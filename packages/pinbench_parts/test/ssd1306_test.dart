import 'package:pinbench_parts/logic/ssd1306.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SSD1306 protocol model, driven with the bytes real libraries send.
///
/// These are written against `Adafruit_SSD1306`'s actual traffic rather than
/// against the datasheet's table of commands, because the traffic is what has
/// to work: a display that decodes every documented command but mis-reads the
/// one init sequence in every tutorial is a display that stays dark.
void main() {
  /// The command stream `Adafruit_SSD1306::begin()` sends to a 128 × 64 panel,
  /// as one `0x00`-prefixed transaction.
  List<int> adafruitInit() => [
    0x00, // control byte: a stream of commands follows
    0xAE, // display off
    0xD5, 0x80, // clock divide
    0xA8, 0x3F, // multiplex ratio = 64
    0xD3, 0x00, // display offset
    0x40, // start line 0
    0x8D, 0x14, // charge pump on
    0x20, 0x00, // horizontal addressing
    0xA1, // segment remap
    0xC8, // COM scan descending
    0xDA, 0x12, // COM pins
    0x81, 0xCF, // contrast
    0xD9, 0xF1, // pre-charge
    0xDB, 0x40, // VCOMH
    0xA4, // resume from RAM
    0xA6, // non-inverted
    0x2E, // scrolling off
    0xAF, // display on
  ];

  /// What `display.display()` sends before the pixel data: the full window.
  List<int> windowFullScreen() => [0x00, 0x21, 0x00, 0x7F, 0x22, 0x00, 0x07];

  group('the initialisation every library sends', () {
    test('turns the display on and leaves it non-inverted', () {
      final oled = Ssd1306Controller()..consumeTransaction(adafruitInit());

      expect(oled.displayOn, isTrue);
      expect(oled.inverted, isFalse);
      expect(oled.entireDisplayOn, isFalse);
      expect(oled.contrast, 0xCF);
      expect(oled.addressingMode, 0, reason: 'horizontal addressing');
      expect(oled.segmentRemap, isTrue);
      expect(oled.comScanDescending, isTrue);
    });

    test('never mistakes a command argument for a command', () {
      // The failure this guards is silent and total: `0xA8 0x3F` sets the
      // multiplex ratio, but read as two commands the 0x3F becomes a start
      // line and everything after it shifts. One misread argument
      // desynchronises the whole stream, and the display shows garbage or
      // nothing at all.
      final oled = Ssd1306Controller()..consumeTransaction(adafruitInit());

      expect(oled.startLine, 0, reason: '0x3F was an argument, not a start line');
      expect(oled.displayOn, isTrue, reason: 'the trailing 0xAF still arrived');
    });

    test('an unknown command does not shift everything after it', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction([0x00, 0xFF, 0xAF]); // 0xFF is not a command

      expect(oled.displayOn, isTrue);
    });
  });

  group('writing pixels', () {
    test('a byte of graphics RAM is a vertical run of eight pixels', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, 0x81]); // bits 0 and 7 of column 0, page 0

      expect(oled.pixelAt(0, 0), isTrue);
      expect(oled.pixelAt(0, 7), isTrue);
      for (var y = 1; y < 7; y++) {
        expect(oled.pixelAt(0, y), isFalse, reason: 'row $y should be dark');
      }
      expect(oled.pixelAt(1, 0), isFalse, reason: 'only column 0 was written');
    });

    test('horizontal addressing runs along the page and wraps to the next', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        // Fill page 0 completely, then one byte into page 1.
        ..consumeTransaction([0x40, ...List.filled(Ssd1306Controller.width, 0xFF), 0xFF]);

      expect(oled.pixelAt(127, 7), isTrue, reason: 'the last column of page 0');
      expect(oled.pixelAt(0, 8), isTrue, reason: 'the write wrapped into page 1');
      expect(oled.pixelAt(1, 8), isFalse);
    });

    test('a data stream can be split across transactions', () {
      // This is not a hypothetical: `Wire`\'s buffer is 32 bytes, so a screen
      // refresh is always dozens of separate transactions, and the write
      // position has to survive between them.
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, ...List.filled(16, 0x00)])
        ..consumeTransaction([0x40, 0xFF]);

      expect(oled.pixelAt(16, 0), isTrue, reason: 'the second chunk continued at column 16');
    });

    test('page addressing stays on its page', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction([0x00, 0x20, 0x02, 0xB3, 0x00, 0x10]) // page 3, column 0
        ..consumeTransaction([0x40, 0xFF]);

      expect(oled.pixelAt(0, 24), isTrue, reason: 'page 3 starts at row 24');
    });
  });

  group('what reaches the glass', () {
    test('an off display shows nothing, whatever is in RAM', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, 0xFF]);
      expect(oled.pixelAt(0, 0), isTrue);

      oled.consumeTransaction([0x00, 0xAE]);
      expect(oled.pixelAt(0, 0), isFalse);
    });

    test('inverse video flips every pixel', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, 0x01])
        ..consumeTransaction([0x00, 0xA7]);

      expect(oled.pixelAt(0, 0), isFalse);
      expect(oled.pixelAt(0, 1), isTrue);
    });

    test('entire-display-on ignores RAM', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction([0x00, 0xA5]);

      expect(oled.pixelAt(63, 31), isTrue);
    });

    test('clearing the segment remap mirrors the panel', () {
      // The standard pairing is the identity here (see the class docs), so the
      // only way to tell the mapping is applied at all is to depart from it.
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, 0x01]);
      expect(oled.pixelAt(0, 0), isTrue);

      oled.consumeTransaction([0x00, 0xA0]); // segment remap off
      expect(oled.pixelAt(0, 0), isFalse);
      expect(oled.pixelAt(127, 0), isTrue);
    });
  });

  group('the U8g2 control-byte form', () {
    test('a single command followed by another control byte', () {
      final oled = Ssd1306Controller()..consumeTransaction([0x80, 0xAF, 0x80, 0xA7]);

      expect(oled.displayOn, isTrue);
      expect(oled.inverted, isTrue);
    });

    test('a single command carrying its argument in the next control pair', () {
      final oled = Ssd1306Controller()..consumeTransaction([0x80, 0x81, 0x80, 0x20]);

      expect(oled.contrast, 0x20);
    });
  });

  group('the round trip through the component state map', () {
    test('registers and pixels survive being packed and unpacked', () {
      final oled = Ssd1306Controller()
        ..consumeTransaction(adafruitInit())
        ..consumeTransaction(windowFullScreen())
        ..consumeTransaction([0x40, 0xFF, 0x0F]);

      final restored = Ssd1306Controller.unpack(oled.pack());

      expect(restored.displayOn, isTrue);
      expect(restored.contrast, 0xCF);
      expect(restored.addressingMode, 0);
      expect(restored.column, 2, reason: 'the write position carries over');
      expect(restored.pixelAt(0, 0), isTrue);
      expect(restored.pixelAt(1, 4), isFalse);
      expect(restored.pixelAt(1, 3), isTrue);
    });

    test('a command left half-read between frames still completes', () {
      // A frame boundary can fall anywhere in the byte stream, including
      // between a command and its argument. Losing the half-read command is
      // how a display ends up permanently at the wrong contrast or window.
      final oled = Ssd1306Controller()..consumeTransaction([0x00, 0x81]);

      final restored = Ssd1306Controller.unpack(oled.pack())..consumeTransaction([0x00, 0x42]);

      expect(restored.contrast, 0x42);
    });

    test('an absent or damaged blob reads as a fresh display', () {
      expect(Ssd1306Controller.unpack(null).displayOn, isFalse);
      expect(Ssd1306Controller.unpack('').displayOn, isFalse);
      expect(Ssd1306Controller.unpack('not base64 at all !!').displayOn, isFalse);
      expect(Ssd1306Controller.unpack('AAAA').displayOn, isFalse);
    });

    test('the packed form is stable, so an idle display queues no redraw', () {
      // The frame updater compares state maps by value: an unchanged string
      // means no canvas rebuild, which is the whole reason this packs to a
      // string rather than a byte list.
      final oled = Ssd1306Controller()..consumeTransaction(adafruitInit());
      expect(oled.pack(), Ssd1306Controller.unpack(oled.pack()).pack());
    });
  });
}
