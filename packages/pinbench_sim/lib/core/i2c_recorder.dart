import 'dart:typed_data';

/// Records what the sketch writes onto the I²C bus, per slave address, and
/// answers what it reads from devices that [serve] registers.
///
/// The emulator's TWI peripheral reports the bus as *events* — start, address,
/// byte, stop — while a peripheral wants *transactions*, because the first byte
/// of one is a control byte that says how to read the rest. This turns one into
/// the other and holds the result until the part that cares drains it.
///
/// **Why it buffers at all.** Everything else a part reads is a level it can
/// sample whenever it likes; bus traffic is not. The frame loop runs the CPU
/// for a whole frame and only then lets parts look, so an entire screen
/// refresh — a thousand bytes — can arrive between two looks. Sampling would
/// lose all but the last byte and a display would show noise.
///
/// **Reads are answered here, not by the part.** A read has to be answered
/// the moment the sketch clocks it, in the middle of the CPU's frame, and a
/// part only runs between frames. So a part that talks back publishes its
/// registers with [serve] and [setRegisters], and the bus answers from them.
/// That is how almost every I²C sensor is built anyway: the sketch writes a
/// register pointer, then reads, and the pointer advances after every byte.
/// Values a part refreshes each frame are at most one frame (16 ms) old, far
/// fresher than any real sensor's conversion time.
///
/// Kept out of the emulator facades because both of them need it and neither
/// owns it: the bridge feeds this from `avr8_dart`'s TWI callbacks, and the
/// frame loop drains it.
class I2cRecorder {
  /// Addresses some part has claimed by draining them.
  ///
  /// This gates the *acknowledgement*, not the recording, and the difference
  /// matters on the very first frame. A part only claims its address when its
  /// logic first runs, which is after the frame in which the sketch's `setup()`
  /// already sent the display's entire initialisation sequence. Gating the
  /// recording on a claim would throw that sequence away and the display would
  /// never come on. So everything is recorded and the claim decides only who
  /// the bus admits exists — which is what an I²C scanner sketch asks.
  final Set<int> _listening = {};

  /// How many distinct addresses may hold undrained traffic.
  ///
  /// Recording before anyone claims means a sketch writing to addresses that
  /// have no part behind them would otherwise accumulate a queue each. Real
  /// circuits here have one or two devices; this is only a backstop.
  static const maxRecordedAddresses = 16;

  final Map<int, List<List<int>>> _pending = {};

  /// How many bytes may sit undrained per address before the oldest
  /// transactions are dropped.
  ///
  /// A ceiling rather than a promise: a part that stops draining (its logic
  /// threw, or the display was deleted mid-run) must not grow the heap for the
  /// rest of the session. 64 KB is many full screen refreshes — far more than
  /// the one frame's worth a healthy run ever holds.
  static const maxBufferedBytesPerAddress = 64 * 1024;

  final Map<int, int> _bufferedBytes = {};

  List<int>? _current;
  int? _currentAddress;

  /// Devices that answer reads, by address.
  final Map<int, I2cRegisterDevice> _devices = {};

  /// The device the open transaction talks to, if it serves registers.
  I2cRegisterDevice? _device;

  /// Whether the open transaction is a write, while [_device] is set.
  var _writing = false;

  /// Pointer bytes still to come in the open write transaction. A write
  /// starts by setting the register pointer, most significant byte first;
  /// everything after that is data.
  var _pointerBytesLeft = 0;

  /// Claims [address] so its traffic is recorded from now on.
  void listenAt(int address) => _listening.add(address);

  bool isListening(int address) => _listening.contains(address);

  /// Makes [address] answer reads from a bank of [size] registers.
  ///
  /// [pointerBytes] is how many bytes of a write set the register pointer:
  /// 1 for most sensors, 2 for large EEPROMs, and 0 for devices with no
  /// registers to choose between (a PCF8574 port expander), whose every read
  /// starts again at register 0.
  ///
  /// Serving claims the address, like [listenAt]. Calling it again with the
  /// same shape keeps the registers and the pointer, so a part can declare
  /// itself every frame without resetting what the sketch wrote; a different
  /// shape starts over, zero-filled.
  void serve(int address, {int size = 256, int pointerBytes = 1}) {
    assert(
      size > 0 && pointerBytes >= 0 && pointerBytes <= 2,
      'size $size, pointerBytes $pointerBytes',
    );
    _listening.add(address);
    final existing = _devices[address];
    if (existing != null &&
        existing.registers.length == size &&
        existing.pointerBytes == pointerBytes) {
      return;
    }
    _devices[address] = I2cRegisterDevice(size: size, pointerBytes: pointerBytes);
  }

  /// Overwrites [address]'s registers from [offset], wrapping at the end of
  /// the bank. How a part publishes fresh readings. Does nothing for an
  /// address nobody [serve]s.
  void setRegisters(int address, int offset, List<int> bytes) {
    final registers = _devices[address]?.registers;
    if (registers == null) return;
    for (var i = 0; i < bytes.length; i++) {
      registers[(offset + i) % registers.length] = bytes[i] & 0xFF;
    }
  }

  /// [address]'s registers, or null when nothing serves it. For tests and
  /// for parts that want to read back what the sketch wrote.
  List<int>? registersOf(int address) => _devices[address]?.registers;

  /// Whether any device on the canvas answers at [address] — what the TWI
  /// peripheral needs in order to ACK or NACK the address byte, and therefore
  /// what makes `Wire.endTransmission()` report success or failure to the
  /// sketch exactly as a real bus would.
  bool acknowledges(int address) => _listening.contains(address);

  /// Starts a transaction with [address]. A write is recorded, and also
  /// updates the register pointer and registers of a device that [serve]s;
  /// a read is not recorded, but it still closes whatever transaction was
  /// open, and a pointer-less device starts its read at register 0.
  void beginTransaction(int address, {required bool write}) {
    endTransaction();
    final device = _devices[address];
    _device = device;
    _writing = write;
    if (device != null) {
      if (write) {
        _pointerBytesLeft = device.pointerBytes;
        if (device.pointerBytes > 0) device.pointer = 0;
      } else if (device.pointerBytes == 0) {
        device.pointer = 0;
      }
    }
    if (!write) return;
    if (!_pending.containsKey(address) && _pending.length >= maxRecordedAddresses) return;
    _currentAddress = address;
    _current = [];
  }

  /// Records one byte of the open transaction. Ignored when the bus is idle or
  /// addressing a device nobody listens for.
  void writeByte(int value) {
    final byte = value & 0xFF;
    _current?.add(byte);
    final device = _device;
    if (device == null || !_writing) return;
    if (_pointerBytesLeft > 0) {
      device.pointer = ((device.pointer << 8) | byte) % device.registers.length;
      _pointerBytesLeft--;
    } else if (device.pointerBytes > 0) {
      // A pointer-less device's writes drive its outputs, not a register the
      // sketch can read back, so only register devices store them.
      device.registers[device.pointer] = byte;
      device.advance();
    }
  }

  /// The byte the sketch reads next from the open read transaction: the
  /// register under the pointer, which then advances. 0xFF — a pulled-up,
  /// undriven bus — when nothing serves the address.
  int readByte() {
    final device = _device;
    if (device == null || _writing) return 0xFF;
    final value = device.registers[device.pointer];
    device.advance();
    return value;
  }

  /// Closes the open transaction and queues it for its address.
  void endTransaction() {
    final address = _currentAddress;
    final bytes = _current;
    _currentAddress = null;
    _current = null;
    _device = null;
    _pointerBytesLeft = 0;
    if (address == null || bytes == null || bytes.isEmpty) return;

    final queue = _pending.putIfAbsent(address, () => []);
    queue.add(bytes);
    var buffered = (_bufferedBytes[address] ?? 0) + bytes.length;
    while (buffered > maxBufferedBytesPerAddress && queue.length > 1) {
      buffered -= queue.removeAt(0).length;
    }
    _bufferedBytes[address] = buffered;
  }

  /// Everything queued for [address], oldest first, handing over ownership.
  List<List<int>> drain(int address) {
    final queued = _pending.remove(address);
    _bufferedBytes.remove(address);
    return queued ?? const [];
  }

  /// Drops every claim and every queued byte. Called when a program is loaded,
  /// so a new run never sees the previous one's traffic.
  void reset() {
    _listening.clear();
    _pending.clear();
    _bufferedBytes.clear();
    _devices.clear();
    _current = null;
    _currentAddress = null;
    _device = null;
    _pointerBytesLeft = 0;
  }
}

/// One device's registers and its pointer, as [I2cRecorder.serve] made them.
class I2cRegisterDevice({required int size, required final int pointerBytes}) {
  final registers = Uint8List(size);

  /// The register the next read or write touches.
  var pointer = 0;

  /// Moves to the next register, wrapping at the end of the bank the way an
  /// auto-incrementing device does.
  void advance() => pointer = (pointer + 1) % registers.length;
}
