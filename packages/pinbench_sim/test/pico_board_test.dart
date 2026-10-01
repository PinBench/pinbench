import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_sim/core/board/avr_board.dart';
import 'package:pinbench_sim/core/board/intel_hex.dart';
import 'package:pinbench_sim/core/board/pico_board.dart';

/// Runs a real arduino-pico program (`fixtures/pico/pico.ino`) on the Pico
/// board emulator and checks each thing the engine reads off a board.
void main() {
  final hex = File('test/fixtures/pico/pico.hex').readAsStringSync();

  // A millisecond of the Pico's 125 MHz clock.
  const ms = 125000;

  late PicoBoardEmulator board;
  late List<String> lines;

  /// Runs [board] a millisecond at a time until [line] has been printed.
  void runUntil(String line, {int maxMs = 2000}) {
    for (var t = 0; t < maxMs && !lines.contains(line); t++) {
      board.tick(ms);
    }
    expect(lines, contains(line));
  }

  setUp(() {
    lines = [];
    board = PicoBoardEmulator()..loadHex(hex, onSerialPrint: lines.add);
  });

  test('prints on Serial (USB) and Serial1 (UART0)', () {
    runUntil('DONE');
    expect(lines, contains('usb 0'));
    expect(lines, contains('usb 4'));
  });

  test('delay() keeps simulated time: DONE comes 4.5 loops of 100 ms in', () {
    var elapsedMs = 0;
    while (!lines.contains('DONE') && elapsedMs < 2000) {
      board.tick(ms);
      elapsedMs++;
    }
    // Printed halfway through the fifth loop, after a millisecond of setup().
    expect(elapsedMs, inInclusiveRange(449, 456));
    expect(board.getCycles(), closeTo(elapsedMs * ms, ms));
  });

  test('reads an injected voltage through the ADC', () {
    board.setAnalogVoltage(0, 1.65);
    runUntil('DONE');
    // Half of 3.3 V, read at arduino-pico's default 10 bits.
    expect(lines.firstWhere((l) => l.startsWith('a0=')), startsWith('a0=51'));
  });

  test('a pulled-up input reads what the circuit drives into it', () {
    board.setDigitalPin(14, isHigh: true);
    board.tick(60 * ms);
    board.setDigitalPin(14, isHigh: false);
    runUntil('DONE');
    final buttons = lines.where((l) => l.startsWith('a0=')).map((l) => l.split('btn=').last);
    expect(buttons.first, '1');
    expect(buttons.last, '0');
  });

  test('reports outputs, PWM duty and the on-board LED', () {
    board.tick(10 * ms);
    expect(board.isPinOutput(15), isTrue);
    expect(board.isPinOutput(14), isFalse);
    expect(board.getPinState(15), isTrue);
    expect(board.isBuiltinLedOn, isTrue);

    // Past 12 ms: until USB has enumerated, the pico-sdk borrows GP15 to work
    // round the RP2040's USB erratum (E5), on the chip as here.
    board.tick(10 * ms);
    board.tick(20 * ms);
    expect(board.getPinDuty(16), closeTo(64 / 255, 0.01));
    expect(board.getPinDuty(15), 1.0);

    board.tick(30 * ms);
    expect(board.getPinState(15), isFalse);
    expect(board.isBuiltinLedOn, isFalse);
  });

  test('I²C: a device the canvas claims acknowledges and receives the write', () {
    // Claimed before the sketch's setup() runs, as a part's logic does on the
    // run's first frame.
    board.listenI2c(0x3C);
    runUntil('i2c 0');
    expect(board.drainI2c(0x3C), [
      [0x42],
    ]);
  });

  test('I²C: nothing on the bus is a NACK', () {
    // arduino-pico reports a failed write as 4, "other error", not 2.
    runUntil('i2c 4');
  });

  group('I²C address probe (an empty write, as a scanner sends)', () {
    // The probe reads the lines back, so they must idle high, as the
    // circuit's pull-ups hold them.
    void pullUp() {
      board.setDigitalPin(4, isHigh: true);
      board.setDigitalPin(5, isHigh: true);
    }

    test('a claimed address acknowledges', () {
      pullUp();
      board.listenI2c(0x3C);
      runUntil('probe 0');
      // SDA is let go once the probe ends.
      board.tick(ms);
      expect(board.getPinState(4), isFalse);
      expect(board.isPinOutput(4), isFalse);
    });

    test('an unclaimed one does not', () {
      pullUp();
      runUntil('probe 2');
    });
  });

  test('typed Serial Monitor input reaches Serial.read()', () {
    board.queueSerialInput('x');
    runUntil('echo x');
  });

  group('beyond the basics (fixtures/pico/../pico_extras)', () {
    final extras = File('test/fixtures/pico_extras/pico_extras.hex').readAsStringSync();

    setUp(() => board = PicoBoardEmulator()..loadHex(extras, onSerialPrint: lines.add));

    test('Wire moved to GP8/GP9 is probed and written there', () {
      // The modules' pull-ups hold both lines high.
      board.setDigitalPin(8, isHigh: true);
      board.setDigitalPin(9, isHigh: true);
      board.listenI2c(0x3C);
      runUntil('READY');
      expect(lines, containsAllInOrder(['probe 0', 'i2c 0']));
      expect(board.drainI2c(0x3C), [
        [0x07],
      ]);
    });

    test('the temperature sensor reads room temperature and GP29 reads VSYS / 3', () {
      runUntil('READY');
      expect(lines, contains('temp 27'));
      // 4.7 V / 3 against 3.3 V, at 10 bits.
      final vsys = int.parse(lines.firstWhere((l) => l.startsWith('vsys ')).substring(5));
      expect(vsys, closeTo(486, 2));
    });

    test('typed Serial Monitor input reaches Serial1.read() too', () {
      runUntil('READY');
      board.queueSerialInput('q');
      runUntil('got q');
    });
  });

  test('refuses an Uno program, and the Uno refuses a Pico program', () {
    final uno = File('test/fixtures/sensors/sensors.hex').readAsStringSync();
    expect(() => PicoBoardEmulator().loadHex(uno), throwsFormatException);
    expect(() => const AvrBoardEmulator().loadHex(hex), throwsFormatException);
  });

  test('Intel HEX round-trips across a 64 KB boundary', () {
    final bytes = Uint8List.fromList([for (var i = 0; i < 70000; i++) i * 7 & 0xff]);
    final decoded = IntelHex.decode(IntelHex.encode(bytes, baseAddress: 0x10000000));
    expect(decoded.first.address, 0x10000000);
    final flat = BytesBuilder();
    for (final segment in decoded) {
      expect(segment.address, 0x10000000 + flat.length);
      flat.add(segment.bytes);
    }
    expect(flat.takeBytes(), bytes);
  });
}
