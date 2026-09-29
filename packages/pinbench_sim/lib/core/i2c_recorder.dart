/// Records what the sketch writes onto the I²C bus, per slave address.
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
/// Kept out of the emulator facades because both of them need it and neither
/// owns it: the native bridge feeds this from `avr8_dart`'s TWI callbacks, the
/// web bridge from `avr8js`'s, and the frame loop drains the same shape either
/// way.
class I2cRecorder() {
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

  /// Claims [address] so its traffic is recorded from now on.
  void listenAt(int address) => _listening.add(address);

  bool isListening(int address) => _listening.contains(address);

  /// Whether any device on the canvas answers at [address] — what the TWI
  /// peripheral needs in order to ACK or NACK the address byte, and therefore
  /// what makes `Wire.endTransmission()` report success or failure to the
  /// sketch exactly as a real bus would.
  bool acknowledges(int address) => _listening.contains(address);

  /// Starts recording a write transaction to [address]. A read is not
  /// recorded — nothing on the canvas talks back yet — but it still closes
  /// whatever transaction was open.
  void beginTransaction(int address, {required bool write}) {
    endTransaction();
    if (!write) return;
    if (!_pending.containsKey(address) && _pending.length >= maxRecordedAddresses) return;
    _currentAddress = address;
    _current = [];
  }

  /// Records one byte of the open transaction. Ignored when the bus is idle or
  /// addressing a device nobody listens for.
  void writeByte(int value) => _current?.add(value & 0xFF);

  /// Closes the open transaction and queues it for its address.
  void endTransaction() {
    final address = _currentAddress;
    final bytes = _current;
    _currentAddress = null;
    _current = null;
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
    _current = null;
    _currentAddress = null;
  }
}
