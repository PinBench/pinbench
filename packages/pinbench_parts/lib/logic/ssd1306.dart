import 'dart:convert';
import 'dart:typed_data';

/// An SSD1306 display controller: the chip behind every 0.96" OLED module,
/// decoded from the raw I²C byte stream the sketch writes to it.
///
/// This is a *protocol* model, not a picture. It owns the same two things the
/// real chip owns — a 1 KB graphics RAM and a handful of registers — and knows
/// nothing about how either is drawn. That split is what makes a display
/// testable: a test can write the bytes `Adafruit_SSD1306` writes and assert on
/// pixels, with no canvas, no emulator and no simulation running.
///
/// **Why the whole thing serializes.** A `PartLogic` gets one map per frame and
/// must not keep fields of its own (one registration is shared by every placed
/// instance — see `PartLogic`), so all of this lives in the component's state
/// map, travels to the canvas, and comes back next frame. [pack] and
/// [Ssd1306Controller.unpack] are that round trip: one base64 string holding the registers and the GDDRAM.
/// One key rather than twenty also means change detection is a string compare —
/// an idle display costs one comparison per frame and never redraws.
class Ssd1306Controller() {
  /// Columns and rows of the panel this models. The 128 × 64 part is the one
  /// in every tutorial; a 128 × 32 module writes the same GDDRAM and simply
  /// leaves the lower half untouched, so it renders correctly here too.
  static const width = 128;
  static const height = 64;

  /// GDDRAM is addressed as 8 pages of 128 columns, each byte a vertical run
  /// of 8 pixels with the LSB on top.
  static const pages = height ~/ 8;
  static const _ramBytes = pages * width;

  /// Bumped if the packed layout ever changes; an older blob is discarded
  /// rather than misread (a stale frame is redrawn on the next write anyway).
  static const _formatVersion = 1;

  /// Registers, then up to [_maxPendingArgs] bytes of a half-read command.
  static const _headerBytes = 24;

  /// The longest argument list any command takes (0x26, horizontal scroll).
  static const _maxPendingArgs = 6;

  /// The display's graphics RAM: `ram[page * width + column]`.
  final ram = Uint8List(_ramBytes);

  // --- Registers, in the order the datasheet numbers them ------------------

  /// 0xAF / 0xAE. A display that was never turned on shows nothing, which is
  /// also what a sketch that forgot `display.begin()` should look like.
  var displayOn = false;

  /// 0xA5 / 0xA4 — lights every pixel regardless of GDDRAM (a "is it alive?"
  /// test, and the flash in some libraries' splash screens).
  var entireDisplayOn = false;

  /// 0xA7 / 0xA6 — inverse video.
  var inverted = false;

  /// 0x81. Drawn as opacity, which is what it looks like on the real panel.
  var contrast = 0x7F;

  /// 0x20: 0 horizontal, 1 vertical, 2 page addressing.
  var addressingMode = 2;

  /// 0x21 / 0x22 — the window auto-incrementing writes wrap inside.
  var columnStart = 0;
  var columnEnd = width - 1;
  var pageStart = 0;
  var pageEnd = pages - 1;

  /// Where the next data byte lands.
  var column = 0;
  var page = 0;

  /// 0x40–0x7F — the first RAM row shown at the top of the panel.
  var startLine = 0;

  /// 0xA1 / 0xA0 and 0xC8 / 0xC0.
  ///
  /// Both default to the *remapped* setting rather than the chip's power-on
  /// value, because that is the pairing every library's init sequence sends
  /// (`Adafruit_SSD1306` and `U8g2` both do) and the one the glass is wired
  /// for: with 0xA1 + 0xC8 the pixel at GDDRAM column 0, page 0, bit 0 is the
  /// one in the panel's top-left corner. [pixelAt] treats that pairing as the
  /// identity and flips only when a sketch departs from it.
  var segmentRemap = true;
  var comScanDescending = true;

  // Multi-byte commands arrive one byte at a time and a transaction can be
  // split across frames, so the half-read command has to survive the round
  // trip through the state map like everything else.
  var _pendingCommand = -1;
  final _pendingArgs = <int>[];

  /// Whether the sketch has written anything at all since [reset].
  ///
  /// Used to tell "off" from "never spoke to" — an unaddressed display draws
  /// its idle glass, not a black screen it was commanded into.
  var addressed = false;

  void reset() {
    ram.fillRange(0, ram.length, 0);
    displayOn = false;
    entireDisplayOn = false;
    inverted = false;
    contrast = 0x7F;
    addressingMode = 2;
    columnStart = 0;
    columnEnd = width - 1;
    pageStart = 0;
    pageEnd = pages - 1;
    column = 0;
    page = 0;
    startLine = 0;
    segmentRemap = true;
    comScanDescending = true;
    _pendingCommand = -1;
    _pendingArgs.clear();
    addressed = false;
  }

  /// Whether the pixel at panel coordinates ([x], [y]) is lit, with every
  /// register that affects what reaches the glass already applied.
  bool pixelAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    if (!displayOn) return false;
    if (entireDisplayOn) return !inverted;

    // Undo the panel's own mirroring: the standard init pairing is the
    // identity (see [segmentRemap]), so a sketch that clears either bit gets
    // the mirrored image it asked for.
    final col = segmentRemap ? x : width - 1 - x;
    final row = comScanDescending ? y : height - 1 - y;
    // The start line scrolls RAM under the panel; it wraps, as on the chip.
    final ramRow = (row + startLine) % height;

    final byte = ram[(ramRow >> 3) * width + col];
    final lit = (byte & (1 << (ramRow & 7))) != 0;
    return inverted ? !lit : lit;
  }

  /// Feeds one I²C transaction's payload — everything after the address byte.
  ///
  /// Each transaction opens with a control byte: bit 6 (`0x40`) selects data
  /// over command, and bit 7 (`Co`) says only one byte follows before the next
  /// control byte. `Adafruit_SSD1306` sends `0x00` then a command stream and
  /// `0x40` then a data stream; `U8g2` uses the `0x80` single-command form.
  /// All three are handled.
  void consumeTransaction(List<int> payload) {
    if (payload.isEmpty) return;
    addressed = true;

    var i = 0;
    while (i < payload.length) {
      final control = payload[i++];
      final isData = (control & 0x40) != 0;
      final single = (control & 0x80) != 0;

      if (single) {
        if (i >= payload.length) return;
        isData ? _writeData(payload[i]) : _command(payload[i]);
        i++;
        continue;
      }

      // A stream: every remaining byte in this transaction is of one kind.
      for (; i < payload.length; i++) {
        isData ? _writeData(payload[i]) : _command(payload[i]);
      }
    }
  }

  /// Feeds a batch of transactions, oldest first.
  void consume(Iterable<List<int>> transactions) => transactions.forEach(consumeTransaction);

  void _writeData(int value) {
    ram[(page & 0x07) * width + (column & 0x7F)] = value & 0xFF;

    switch (addressingMode) {
      case 0: // Horizontal: run along the page, then drop to the next one.
        if (column >= columnEnd) {
          column = columnStart;
          page = page >= pageEnd ? pageStart : page + 1;
        } else {
          column++;
        }
      case 1: // Vertical: run down the pages, then across.
        if (page >= pageEnd) {
          page = pageStart;
          column = column >= columnEnd ? columnStart : column + 1;
        } else {
          page++;
        }
      default: // Page addressing: wrap within the page, never leave it.
        column = column >= width - 1 ? 0 : column + 1;
    }
  }

  /// How many argument bytes follow [command], or 0 for a standalone one.
  static int _argumentCount(int command) => switch (command) {
    0x20 || 0x81 || 0x8D || 0xA8 || 0xD3 || 0xD5 || 0xD8 || 0xD9 || 0xDA || 0xDB => 1,
    0x21 || 0x22 || 0xA3 => 2,
    // Scrolling setups. Not modelled, but their arguments must still be eaten
    // or every byte after one would be read as a command.
    0x26 || 0x27 => 6,
    0x29 || 0x2A => 5,
    _ => 0,
  };

  void _command(int byte) {
    final value = byte & 0xFF;

    if (_pendingCommand >= 0) {
      _pendingArgs.add(value);
      if (_pendingArgs.length < _argumentCount(_pendingCommand)) return;
      final command = _pendingCommand;
      final args = List<int>.of(_pendingArgs);
      _pendingCommand = -1;
      _pendingArgs.clear();
      _applyWithArgs(command, args);
      return;
    }

    if (_argumentCount(value) > 0) {
      _pendingCommand = value;
      _pendingArgs.clear();
      return;
    }

    _applyStandalone(value);
  }

  void _applyStandalone(int command) {
    switch (command) {
      case >= 0x00 && <= 0x0F: // Lower nibble of the page-mode column.
        column = (column & 0xF0) | command;
      case >= 0x10 && <= 0x1F: // Upper nibble of the page-mode column.
        column = (column & 0x0F) | ((command & 0x0F) << 4);
      case >= 0x40 && <= 0x7F:
        startLine = command & 0x3F;
      case 0xA0 || 0xA1:
        segmentRemap = command == 0xA1;
      case 0xA4 || 0xA5:
        entireDisplayOn = command == 0xA5;
      case 0xA6 || 0xA7:
        inverted = command == 0xA7;
      case 0xAE || 0xAF:
        displayOn = command == 0xAF;
      case >= 0xB0 && <= 0xB7:
        page = command & 0x07;
      case 0xC0 || 0xC8:
        comScanDescending = command == 0xC8;
      // 0x2E/0x2F (scroll on/off), 0xE3 (nop) and anything unrecognised are
      // deliberately ignored: an unknown command must not desynchronise the
      // stream, and it cannot, because it carries no arguments.
    }
  }

  void _applyWithArgs(int command, List<int> args) {
    switch (command) {
      case 0x20:
        addressingMode = args[0] & 0x03;
      case 0x21:
        columnStart = args[0] & 0x7F;
        columnEnd = args[1] & 0x7F;
        column = columnStart;
      case 0x22:
        pageStart = args[0] & 0x07;
        pageEnd = args[1] & 0x07;
        page = pageStart;
      case 0x81:
        contrast = args[0] & 0xFF;
      // The rest — charge pump, multiplex, offset, clock, precharge, COM pins,
      // VCOMH — are power and timing settings with nothing to show for them on
      // a simulated panel. Their arguments are consumed above, which is the
      // part that matters.
    }
  }

  // --- Serialization -------------------------------------------------------

  /// This controller as one base64 string: a fixed header of registers
  /// followed by the raw GDDRAM.
  String pack() {
    final blob = Uint8List(_headerBytes + _ramBytes);
    blob[0] = _formatVersion;
    blob[1] =
        (displayOn ? 0x01 : 0) |
        (entireDisplayOn ? 0x02 : 0) |
        (inverted ? 0x04 : 0) |
        (segmentRemap ? 0x08 : 0) |
        (comScanDescending ? 0x10 : 0) |
        (addressed ? 0x20 : 0);
    blob[2] = contrast;
    blob[3] = addressingMode;
    blob[4] = columnStart;
    blob[5] = columnEnd;
    blob[6] = pageStart;
    blob[7] = pageEnd;
    blob[8] = column;
    blob[9] = page;
    blob[10] = startLine;
    // A half-read command, so one split across two frames still completes.
    blob[11] = _pendingCommand < 0 ? 0xFF : _pendingCommand;
    final pending = _pendingArgs.length.clamp(0, _maxPendingArgs);
    blob[12] = pending;
    for (var i = 0; i < pending; i++) {
      blob[13 + i] = _pendingArgs[i];
    }
    blob.setRange(_headerBytes, _headerBytes + _ramBytes, ram);
    return base64Encode(blob);
  }

  /// Restores a controller from [packed], or a freshly [reset] one when the
  /// string is absent, truncated or from an older format.
  factory unpack(Object? packed) {
    final controller = Ssd1306Controller();
    if (packed is! String || packed.isEmpty) return controller;

    final Uint8List blob;
    try {
      blob = base64Decode(packed);
    } on FormatException {
      return controller;
    }
    if (blob.length != _headerBytes + _ramBytes || blob[0] != _formatVersion) {
      return controller;
    }

    final flags = blob[1];
    controller
      ..displayOn = (flags & 0x01) != 0
      ..entireDisplayOn = (flags & 0x02) != 0
      ..inverted = (flags & 0x04) != 0
      ..segmentRemap = (flags & 0x08) != 0
      ..comScanDescending = (flags & 0x10) != 0
      ..addressed = (flags & 0x20) != 0
      ..contrast = blob[2]
      ..addressingMode = blob[3]
      ..columnStart = blob[4]
      ..columnEnd = blob[5]
      ..pageStart = blob[6]
      ..pageEnd = blob[7]
      ..column = blob[8]
      ..page = blob[9]
      ..startLine = blob[10]
      .._pendingCommand = blob[11] == 0xFF ? -1 : blob[11];
    final pendingCount = blob[12].clamp(0, _maxPendingArgs);
    for (var i = 0; i < pendingCount; i++) {
      controller._pendingArgs.add(blob[13 + i]);
    }
    controller.ram.setRange(0, _ramBytes, blob.sublist(_headerBytes));
    return controller;
  }
}
