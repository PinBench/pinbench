import 'package:pinbench_sim/core/i2c_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turning the emulator's I²C bus events into transactions a peripheral can
/// read.
void main() {
  /// One write transaction: address, bytes, stop.
  void send(I2cRecorder recorder, int address, List<int> bytes) {
    recorder.beginTransaction(address, write: true);
    bytes.forEach(recorder.writeByte);
    recorder.endTransaction();
  }

  test('a stop closes one transaction and the next start opens another', () {
    // The boundary is the whole point: the first byte of a transaction is a
    // control byte saying how to read the rest, so a display given one
    // concatenated stream could not tell commands from pixels.
    final recorder = I2cRecorder()..listenAt(0x3C);
    send(recorder, 0x3C, [0x00, 0xAF]);
    send(recorder, 0x3C, [0x40, 0xFF]);

    expect(recorder.drain(0x3C), [
      [0x00, 0xAF],
      [0x40, 0xFF],
    ]);
  });

  test('draining hands the traffic over exactly once', () {
    final recorder = I2cRecorder()..listenAt(0x3C);
    send(recorder, 0x3C, [0x01]);

    expect(recorder.drain(0x3C), hasLength(1));
    expect(recorder.drain(0x3C), isEmpty, reason: 'the queue was handed over, not copied');
  });

  test("one device does not see another device's traffic", () {
    final recorder = I2cRecorder()
      ..listenAt(0x3C)
      ..listenAt(0x68);
    send(recorder, 0x3C, [0xAA]);
    send(recorder, 0x68, [0xBB]);

    expect(recorder.drain(0x3C), [
      [0xAA],
    ]);
    expect(recorder.drain(0x68), [
      [0xBB],
    ]);
  });

  test('traffic sent before anyone claims the address is still kept', () {
    // The reason this matters is the first frame. A sketch sends the display's
    // whole initialisation sequence inside `setup()`, which runs before any
    // part's logic has had a chance to claim an address. Dropping it would
    // leave the display switched off for the rest of the run.
    final recorder = I2cRecorder();
    send(recorder, 0x3C, [0x00, 0xAF]);
    recorder.listenAt(0x3C);

    expect(recorder.drain(0x3C), [
      [0x00, 0xAF],
    ]);
  });

  test('only a claimed address is acknowledged', () {
    // The ACK is what `Wire.endTransmission()` reports and what an I²C scanner
    // counts, so a device that is not on the canvas must not answer.
    final recorder = I2cRecorder()..listenAt(0x3C);

    expect(recorder.acknowledges(0x3C), isTrue);
    expect(recorder.acknowledges(0x3D), isFalse);
  });

  test('a read transaction records nothing but still closes the last write', () {
    final recorder = I2cRecorder()..listenAt(0x3C);
    recorder.beginTransaction(0x3C, write: true);
    recorder.writeByte(0x01);
    recorder.beginTransaction(0x3C, write: false); // a repeated start to read
    recorder.writeByte(0x02); // the bus is not recording; this is not ours

    expect(recorder.drain(0x3C), [
      [0x01],
    ]);
  });

  test('an undrained address stops growing instead of eating the heap', () {
    // A part whose logic stopped running — deleted mid-run, or throwing —
    // must not cost memory for the rest of the session.
    final recorder = I2cRecorder()..listenAt(0x3C);
    final chunk = List.filled(1024, 0xFF);
    for (var i = 0; i < 200; i++) {
      send(recorder, 0x3C, chunk);
    }

    final queued = recorder.drain(0x3C);
    final bytes = queued.fold<int>(0, (sum, t) => sum + t.length);
    expect(bytes, lessThanOrEqualTo(I2cRecorder.maxBufferedBytesPerAddress));
    expect(queued.last, chunk, reason: 'the newest traffic is the traffic worth keeping');
  });

  test('addresses nobody listens for cannot multiply without limit', () {
    final recorder = I2cRecorder();
    for (var address = 0; address < 0x40; address++) {
      send(recorder, address, [0x01]);
    }

    var recorded = 0;
    for (var address = 0; address < 0x40; address++) {
      if (recorder.drain(address).isNotEmpty) recorded++;
    }
    expect(recorded, I2cRecorder.maxRecordedAddresses);
  });

  test('loading a program drops the previous run entirely', () {
    final recorder = I2cRecorder()..listenAt(0x3C);
    send(recorder, 0x3C, [0x01]);

    recorder.reset();

    expect(recorder.drain(0x3C), isEmpty);
    expect(recorder.acknowledges(0x3C), isFalse);
  });

  group('answering reads', () {
    /// A register read the way `Wire` does it: write the pointer, then a
    /// repeated start and a read of [count] bytes.
    List<int> readRegisters(I2cRecorder bus, int address, int register, int count) {
      bus.beginTransaction(address, write: true);
      bus.writeByte(register);
      bus.beginTransaction(address, write: false); // repeated start
      final bytes = [for (var i = 0; i < count; i++) bus.readByte()];
      bus.endTransaction();
      return bytes;
    }

    test('a read returns the register the sketch pointed at', () {
      final bus = I2cRecorder()
        ..serve(0x68)
        ..setRegisters(0x68, 0x75, [0x68]); // MPU6050 WHO_AM_I

      expect(readRegisters(bus, 0x68, 0x75, 1), [0x68]);
    });

    test('the pointer advances after every byte and wraps at the end', () {
      // How a sensor hands over a multi-byte reading in one read: the
      // accelerometer's six bytes start at 0x3B and follow each other.
      final bus = I2cRecorder()
        ..serve(0x68, size: 4)
        ..setRegisters(0x68, 0, [0xA0, 0xA1, 0xA2, 0xA3]);

      expect(readRegisters(bus, 0x68, 2, 4), [0xA2, 0xA3, 0xA0, 0xA1]);
    });

    test('what the sketch writes after the pointer can be read back', () {
      // Setting an RTC's clock and reading it again depends on this.
      final bus = I2cRecorder()..serve(0x68);
      bus.beginTransaction(0x68, write: true);
      [0x00, 0x30, 0x15, 0x09].forEach(bus.writeByte);
      bus.endTransaction();

      expect(readRegisters(bus, 0x68, 0x00, 3), [0x30, 0x15, 0x09]);
    });

    test('a two-byte pointer selects the register most significant byte first', () {
      final bus = I2cRecorder()
        ..serve(0x50, size: 32 * 1024, pointerBytes: 2) // 24LC256 EEPROM
        ..setRegisters(0x50, 0x1234, [0x5A]);
      bus.beginTransaction(0x50, write: true);
      bus
        ..writeByte(0x12)
        ..writeByte(0x34);
      bus.beginTransaction(0x50, write: false);

      expect(bus.readByte(), 0x5A);
    });

    test('a pointer-less device starts every read at register 0', () {
      // A PCF8574 has one register, its port; writes drive the pins rather
      // than change what a read returns.
      final bus = I2cRecorder()
        ..serve(0x20, size: 1, pointerBytes: 0)
        ..setRegisters(0x20, 0, [0xF0]);
      bus.beginTransaction(0x20, write: true);
      bus.writeByte(0x0F);
      bus.beginTransaction(0x20, write: false);
      final first = bus.readByte();
      bus.beginTransaction(0x20, write: false);

      expect([first, bus.readByte()], [0xF0, 0xF0]);
    });

    test('an address nothing serves reads as an idle bus', () {
      final bus = I2cRecorder()..listenAt(0x3C);
      bus.beginTransaction(0x3C, write: false);

      expect(bus.readByte(), 0xFF, reason: 'a display listens but does not answer');
    });

    test('serving claims the address, so it is acknowledged', () {
      final bus = I2cRecorder()..serve(0x68);

      expect(bus.acknowledges(0x68), isTrue);
      expect(bus.acknowledges(0x69), isFalse);
    });

    test('serving the same shape again keeps the registers and the pointer', () {
      // Parts declare themselves every frame; that must not wipe what the
      // sketch wrote a frame ago.
      final bus = I2cRecorder()..serve(0x68);
      bus.beginTransaction(0x68, write: true);
      [0x10, 0x42].forEach(bus.writeByte);
      bus.endTransaction();
      bus.serve(0x68);

      expect(bus.registersOf(0x68)![0x10], 0x42);
      bus.serve(0x68, size: 128);
      expect(bus.registersOf(0x68)![0x10], 0, reason: 'a new shape starts over');
    });

    test('writes to a served device still reach drain', () {
      // A part reacts to configuration (a power-on command, a range setting)
      // by reading the transactions, exactly as a display does.
      final bus = I2cRecorder()..serve(0x68);
      bus.beginTransaction(0x68, write: true);
      [0x6B, 0x00].forEach(bus.writeByte);
      bus.endTransaction();

      expect(bus.drain(0x68), [
        [0x6B, 0x00],
      ]);
    });

    test('setRegisters is ignored for an address nothing serves', () {
      final bus = I2cRecorder()..setRegisters(0x68, 0, [1, 2, 3]);

      expect(bus.registersOf(0x68), isNull);
    });

    test('reset forgets every served device', () {
      final bus = I2cRecorder()..serve(0x68);
      bus.reset();

      expect(bus.registersOf(0x68), isNull);
      expect(bus.acknowledges(0x68), isFalse);
    });
  });
}
