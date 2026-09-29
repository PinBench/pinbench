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
}
