/// End-to-end I²C reads: a real sketch built on the Arduino `Wire` library,
/// compiled for the Uno (`test/fixtures/i2c_read/`), runs on the emulated
/// ATmega328P and reads a device the test serves.
///
/// The recorder's own tests cover the register logic; this proves the part
/// that only the real library can: that `Wire.requestFrom` after a repeated
/// start, a multi-byte read and a write-then-read-back all reach the served
/// registers through the TWI peripheral, and that an absent address is still
/// NACKed while another one answers.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_sim/core/avr_interop.dart';

void main() {
  test('a Wire sketch reads, reads back and is refused where nothing answers', () {
    final hex = File('test/fixtures/i2c_read/i2c_read.hex').readAsStringSync();
    final lines = <String>[];
    AVRBridge.loadHex(hex, onSerialPrint: lines.add);

    // Served after loading: a load resets the bus, so a new run never sees
    // the previous one's devices.
    AVRBridge.serveI2c(0x68);
    AVRBridge.setI2cRegisters(0x68, 0x75, [0x68]);
    AVRBridge.setI2cRegisters(0x68, 0x3B, [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]);

    // Two simulated seconds is ample for setup() at 115200 baud; stop early
    // once the sketch reports it is done.
    const cyclesPerStep = 160000; // 10 ms at 16 MHz
    for (var step = 0; step < 200 && !lines.contains('DONE'); step++) {
      AVRBridge.tick(cyclesPerStep);
    }

    expect(
      lines,
      containsAllInOrder(['WHO=68', 'ACC=123456789ABC', 'BACK=5A', 'ABSENT=2', 'DONE']),
    );
  });
}
