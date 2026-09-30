import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_parts/logic/built_in_part_logic.dart';
import 'package:pinbench_parts/logic/i2c_sensors.dart';
import 'package:pinbench_parts/logic/part_logic.dart';
import 'package:pinbench_parts/part_registry.dart';

/// The I²C sensors: `LOGIC` parts whose whole behaviour is a register bank.
///
/// These drive each logic frame by frame against a bus that keeps registers
/// the way the emulator's does, so a test reads exactly what a sketch would.
/// `test/i2c_sensor_sketches_test.dart` in `pinbench_sim` runs the same parts
/// under the real Arduino libraries.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    BuiltInPartLogic.ensureRegistered();
    await PartRegistry.initializeAsync();
  });

  /// The wiring every module here is happy with: powered from 5 V, on A4/A5.
  const onTheBus = {'vcc': '5V', 'gnd': 'GND_2', 'sda': 'A4', 'scl': 'A5'};

  /// One placed sensor, run frame by frame. [state] carries between frames
  /// like the engine's `lastState`, starting from the part's declared values.
  _Sensor sensor(
    String id, {
    Map<String, String> wiring = onTheBus,
    Map<String, Object?> properties = const {},
  }) {
    final definition = PartRegistry.getPart(id)!;
    return _Sensor(
      logic: PartLogicRegistry.find(definition.logic!)!,
      definition: definition,
      wiring: wiring,
      properties: {...definition.defaultProperties(), ...properties},
      state: definition.initialState(),
    );
  }

  group('BH1750', () {
    test('reads 0 until the sketch starts a measurement', () {
      final light = sensor('bh1750')..frame();
      expect(light.bus.read(0x23, 0, 2), [0, 0]);

      light
        ..bus.write(0x23, [0x10]) // continuous high-resolution mode
        ..frame();
      // 250 lx x 1.2 counts/lx = 300 = 0x012C.
      expect(light.bus.read(0x23, 0, 2), [0x01, 0x2C]);
    });

    test('high-resolution mode 2 doubles the count, as libraries expect', () {
      final light = sensor('bh1750')
        ..bus.write(0x23, [0x11])
        ..frame();
      expect(light.bus.read(0x23, 0, 2), [0x02, 0x58]);
    });

    test('ADDR tied high moves it to 0x5C', () {
      final light = sensor('bh1750', wiring: {...onTheBus, 'addr': '5V'})..frame();
      expect(light.bus.served, {0x5C});
    });

    test('a changed MTreg scales the count', () {
      expect(I2cSensors.bh1750Counts(100, mode: 0x10, mtreg: 138), 240);
      final (_, mtreg) = I2cSensors.bh1750Command(0x44, mode: 0x10, mtreg: 69);
      expect(mtreg, 0x85, reason: 'high bits 100 over the default low bits 00101');
    });
  });

  group('MPU-6050', () {
    test('answers WHO_AM_I and boots asleep, reading zeros', () {
      final imu = sensor('mpu6050')..frame();
      expect(imu.bus.read(0x68, 0x75, 1), [0x68]);
      expect(imu.bus.read(0x68, 0x6B, 1), [0x40]);
      expect(imu.bus.read(0x68, 0x3B, 6), [0, 0, 0, 0, 0, 0]);
    });

    test('once woken, reports 1 g on Z at the ±2 g range', () {
      final imu = sensor('mpu6050')
        ..frame()
        ..bus.write(0x68, [0x6B, 0x00])
        ..frame();
      // X, Y, Z: 0, 0, 16384 counts.
      expect(imu.bus.read(0x68, 0x3B, 6), [0, 0, 0, 0, 0x40, 0x00]);
    });

    test('scales to the range the sketch sets', () {
      final imu = sensor('mpu6050', properties: {'gyroZ': 100.0})
        ..frame()
        ..bus.write(0x68, [0x6B, 0x00])
        ..bus.write(0x68, [0x1B, 0x08, 0x10]) // gyro ±500 °/s, accel ±8 g
        ..frame();
      expect(imu.bus.read(0x68, 0x3F, 2), [0x10, 0x00], reason: '1 g at 4096 counts/g');
      // 100 °/s x 65.5 counts = 6550 = 0x1996.
      expect(imu.bus.read(0x68, 0x47, 2), [0x19, 0x96]);
    });

    test('clears its own reset bit, which Adafruit_MPU6050 waits for', () {
      final imu = sensor('mpu6050')
        ..frame()
        ..bus.write(0x68, [0x6B, 0x80]);
      expect(imu.bus.read(0x68, 0x6B, 1), [0x80], reason: 'as the sketch wrote it, mid-frame');
      imu.frame();
      expect(imu.bus.read(0x68, 0x6B, 1), [0x40]);
    });

    test('the die temperature follows the datasheet formula', () {
      final imu = sensor('mpu6050', properties: {'temperature': 36.53})
        ..frame()
        ..bus.write(0x68, [0x6B, 0x00])
        ..frame();
      expect(imu.bus.read(0x68, 0x41, 2), [0, 0]);
    });

    test('AD0 tied high moves it to 0x69', () {
      final imu = sensor('mpu6050', wiring: {...onTheBus, 'ad0': '3.3V'})..frame();
      expect(imu.bus.served, {0x69});
    });
  });

  group('DS1307', () {
    test('a fresh chip is halted at 2000-01-01 until the sketch sets it', () {
      final rtc = sensor('ds1307', properties: {'startsAt': 'unset'})..frame();
      // CH set, 00:00:00, Saturday, 01/01/00.
      expect(rtc.bus.read(0x68, 0, 7), [0x80, 0, 0, 6, 0x01, 0x01, 0x00]);

      rtc.elapsed = const Duration(seconds: 5);
      rtc.frame();
      expect(rtc.bus.read(0x68, 0, 1), [0x80], reason: 'a halted clock does not count');
    });

    test('keeps the time the sketch sets, and counts simulated seconds from it', () {
      final rtc = sensor('ds1307', properties: {'startsAt': 'unset'})..frame();
      // 2026-09-30 12:34:56, clock-halt cleared, as RTClib's adjust() writes it.
      rtc.bus.write(0x68, [0x00, 0x56, 0x34, 0x12, 0x03, 0x30, 0x09, 0x26]);
      rtc.frame();
      expect(rtc.bus.read(0x68, 0, 7), [0x56, 0x34, 0x12, 0x03, 0x30, 0x09, 0x26]);

      rtc.elapsed = const Duration(seconds: 2);
      rtc.frame();
      expect(rtc.bus.read(0x68, 0, 1), [0x58]);
    });

    test('RAM reads back what the sketch stored', () {
      final rtc = sensor('ds1307')
        ..frame()
        ..bus.write(0x68, [0x08, 0xAB, 0xCD])
        ..frame();
      expect(rtc.bus.read(0x68, 0x08, 2), [0xAB, 0xCD]);
    });

    test('does not run from 3.3 V', () {
      final rtc = sensor('ds1307', wiring: {...onTheBus, 'vcc': '3.3V'})..frame();
      expect(rtc.bus.served, isEmpty);
    });

    test('the register encoding round-trips, 12-hour hours included', () {
      final seconds = I2cSensors.secondsSince2000(DateTime(2031, 2, 28, 23, 59, 58));
      final registers = I2cSensors.ds1307Registers(seconds);
      expect(I2cSensors.ds1307Seconds(registers), seconds);

      // 11 PM written in 12-hour mode: bit 6 set, bit 5 = PM, BCD 11.
      final twelveHour = [...registers]..[2] = 0x40 | 0x20 | 0x11;
      expect(I2cSensors.ds1307Seconds(twelveHour), seconds);
    });
  });

  group('AHT20', () {
    test('answers with status, humidity, temperature and a valid CRC', () {
      final aht = sensor('aht20', properties: {'humidity': 50.0, 'temperature': 25.0})..frame();
      final bytes = aht.bus.read(0x38, 0, 7);

      expect(bytes[0] & 0x08, 0x08, reason: 'calibrated');
      expect(bytes[0] & 0x80, 0, reason: 'never busy');
      final humidity = (bytes[1] << 12 | bytes[2] << 4 | bytes[3] >> 4) / (1 << 20) * 100;
      final celsius = ((bytes[3] & 0x0F) << 16 | bytes[4] << 8 | bytes[5]) / (1 << 20) * 200 - 50;
      expect(humidity, closeTo(50, 0.001));
      expect(celsius, closeTo(25, 0.001));
      expect(_crc8(bytes), 0, reason: 'a CRC over the data and its own CRC is 0');
    });
  });

  group('every I²C sensor', () {
    test('stays off the bus unless powered and wired to A4/A5', () {
      for (final id in ['bh1750', 'mpu6050', 'ds1307', 'aht20']) {
        for (final wiring in const [
          <String, String>{'sda': 'A4', 'scl': 'A5'}, // no power
          {'vcc': '5V', 'sda': 'A4', 'scl': 'A5'}, // no ground
          {'vcc': '5V', 'gnd': 'GND_2', 'sda': 'A5', 'scl': 'A4'}, // swapped
          {'vcc': '5V', 'gnd': 'GND_2', 'sda': '2', 'scl': '3'},
        ]) {
          final part = sensor(id, wiring: wiring)..frame();
          expect(part.bus.served, isEmpty, reason: '$id wired as $wiring');
        }
      }
    });
  });
}

/// One placed sensor and the bus it sits on.
class _Sensor({
  required final PartLogic logic,
  required final PartDefinition definition,
  required final Map<String, String> wiring,
  required final Map<String, Object?> properties,
  required final Map<String, Object?> state,
}) {
  final bus = _RegisterBus();
  var elapsed = Duration.zero;

  void frame() => logic(
    PartLogicContext(
      definition: definition,
      state: state,
      properties: properties,
      physics: {},
      elapsed: elapsed,
      analog: (_) => 0,
      pins: _Wiring(wiring),
      spice: const _NoSpice(),
      i2c: bus,
    ),
  );
}

/// A bus that keeps registers the way the emulator's recorder does: a write
/// sets the pointer from its first byte and stores the rest (pointer-less
/// devices store nothing), and a read starts at the pointer.
class _RegisterBus implements PartI2cApi {
  final served = <int>{};
  final _registers = <int, List<int>>{};
  final _pointerBytes = <int, int>{};
  final _pending = <int, List<List<int>>>{};

  /// What the sketch sends, as `Wire.write` would, landing mid-frame.
  void write(int address, List<int> bytes) {
    _pending.putIfAbsent(address, () => []).add(bytes);
    final registers = _registers[address];
    if (registers == null || _pointerBytes[address] == 0) return;
    for (var i = 1; i < bytes.length; i++) {
      registers[(bytes[0] + i - 1) % registers.length] = bytes[i];
    }
  }

  List<int> read(int address, int from, int count) {
    final registers = _registers[address]!;
    return [for (var i = 0; i < count; i++) registers[(from + i) % registers.length]];
  }

  @override
  List<List<int>> drain(int address) => _pending.remove(address) ?? const [];

  @override
  void serve(int address, {int size = 256, int pointerBytes = 1}) {
    served.add(address);
    _pointerBytes[address] = pointerBytes;
    if (_registers[address]?.length != size) _registers[address] = List.filled(size, 0);
  }

  @override
  void setRegisters(int address, int offset, List<int> bytes) {
    final registers = _registers[address];
    if (registers == null) return;
    for (var i = 0; i < bytes.length; i++) {
      registers[(offset + i) % registers.length] = bytes[i];
    }
  }
}

class const _Wiring(final Map<String, String> ports) implements PartPinApi {
  @override
  String? boardPortFor(String portId) => ports[portId];
  @override
  int? connectedTo(String portId) => int.tryParse(ports[portId] ?? '');
  @override
  double duty(int pin) => 0;
  @override
  double pulseUs(int pin) => 0;
  @override
  bool isHigh(int pin) => false;
  @override
  double? frequencyOn(int pin) => null;
}

class const _NoSpice() implements PartSpiceApi {
  @override
  bool get isActive => false;
  @override
  double current() => 0;
}

int _crc8(List<int> bytes) {
  var crc = 0xFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 0x80 != 0 ? ((crc << 1) ^ 0x31) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}
