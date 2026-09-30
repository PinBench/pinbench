import 'part_logic.dart';

/// Where an I²C module sits relative to the board: on the bus, powered, and
/// at which address its jumpers put it.
///
/// Every check reads the wiring rather than a setting, because the wiring is
/// the lesson. A sensor with swapped SDA/SCL, or no VCC, is not acknowledged —
/// an I²C scanner finds nothing and the library reports "chip not found",
/// exactly as on a desk.
abstract final class I2cWiring {
  /// The board ports a module's supply pin counts as powered from.
  static const supplies = {'5V', '3.3V'};

  /// Whether [sda] and [scl] reach the ATmega328P's TWI pads.
  ///
  /// `A4`/`A5` specifically, because the hardware I²C is wired to those two
  /// pads and nothing else. The R3 header's separate `SDA`/`SCL` pins count
  /// too: they are the same two pads brought out twice.
  static bool isOnTheBus(PartLogicContext context, {String sda = 'sda', String scl = 'scl'}) =>
      const {'A4', 'SDA'}.contains(context.pins.boardPortFor(sda)) &&
      const {'A5', 'SCL'}.contains(context.pins.boardPortFor(scl));

  /// Whether [vcc] reaches one of [accepted] and [gnd] reaches a ground.
  static bool isPowered(
    PartLogicContext context, {
    String vcc = 'vcc',
    String gnd = 'gnd',
    Set<String> accepted = supplies,
  }) =>
      accepted.contains(context.pins.boardPortFor(vcc)) &&
      (context.pins.boardPortFor(gnd)?.startsWith('GND') ?? false);

  /// Whether [pin] is tied to a supply — how an address jumper (AD0, ADDR) is
  /// set. Anything else, including unconnected, reads low: the modules pull
  /// these pins down on board.
  static bool isTiedHigh(PartLogicContext context, String pin) =>
      supplies.contains(context.pins.boardPortFor(pin));

  /// An address as people write it: `0x3C`, `60`, or a number from the
  /// properties panel. Null for anything that is not a 7-bit address.
  static int? parseAddress(Object? raw) {
    final address = switch (raw) {
      final num n => n.toInt(),
      final String s => _parse(s.trim().toLowerCase()),
      _ => null,
    };
    if (address == null || address < 0 || address > 0x7F) return null;
    return address;
  }

  static int? _parse(String text) =>
      text.startsWith('0x') ? int.tryParse(text.substring(2), radix: 16) : int.tryParse(text);
}

/// I²C sensors: parts whose whole behaviour is a register bank the sketch
/// reads.
///
/// Each one serves its registers and republishes its reading every frame, so
/// the bus can answer a read the moment the sketch clocks it (see
/// [PartI2cApi]). What the sketch *writes* — a mode, a range, the time — comes
/// back through `drain` and is tracked in declared `STATE`, which is the only
/// memory a `.pdl` part keeps between frames.
abstract final class I2cSensors {
  // --- BH1750 ---------------------------------------------------------------

  /// A BH1750 ambient light sensor (the GY-302 module).
  ///
  /// It has no registers to select: the sketch writes one-byte opcodes and
  /// reads two bytes of result, so it is served with `pointerBytes: 0`. Until
  /// the sketch sends a measurement opcode the result reads 0, as a chip
  /// that has only been powered up does.
  static void bh1750(PartLogicContext context) {
    if (!I2cWiring.isPowered(context) || !I2cWiring.isOnTheBus(context)) return;

    final address = I2cWiring.isTiedHigh(context, 'addr') ? 0x5C : 0x23;
    context.i2c.serve(address, size: 2, pointerBytes: 0);

    var mode = _int(context.state['mode']);
    var mtreg = _int(context.state['mtreg'], 69);
    for (final transaction in context.i2c.drain(address)) {
      for (final opcode in transaction) {
        (mode, mtreg) = bh1750Command(opcode, mode: mode, mtreg: mtreg);
      }
    }
    context.state['mode'] = mode;
    context.state['mtreg'] = mtreg;

    if (mode == 0) {
      context.i2c.setRegisters(address, 0, const [0, 0]);
      return;
    }
    final counts = bh1750Counts(context.number('illuminance', 250), mode: mode, mtreg: mtreg);
    context.i2c.setRegisters(address, 0, [counts >> 8, counts & 0xFF]);
  }

  /// The BH1750's measurement opcodes: continuous and one-time, in H, H2 and
  /// L resolution.
  static const bh1750Modes = {0x10, 0x11, 0x13, 0x20, 0x21, 0x23};

  /// Applies one opcode to the chip's mode and measurement time (MTreg).
  /// Mode 0 means no measurement is running.
  static (int mode, int mtreg) bh1750Command(int opcode, {required int mode, required int mtreg}) {
    if (bh1750Modes.contains(opcode)) return (opcode, mtreg);
    // Power down stops measuring; reset clears the result.
    if (opcode == 0x00 || opcode == 0x07) return (0, mtreg);
    // MTreg is written in two halves: 01000_hhh and 011_lllll.
    if (opcode & 0xF8 == 0x40) return (mode, (mtreg & 0x1F) | ((opcode & 0x07) << 5));
    if (opcode & 0xE0 == 0x60) return (mode, (mtreg & 0xE0) | (opcode & 0x1F));
    return (mode, mtreg);
  }

  /// The raw count the chip reports for [lux]: 1.2 counts per lux at the
  /// default measurement time of 69, scaled by MTreg, doubled in H2 mode —
  /// the inverse of what every BH1750 library divides by.
  static int bh1750Counts(double lux, {required int mode, required int mtreg}) {
    final highResolution2 = mode & 0x0F == 0x01;
    final counts = lux * 1.2 * (mtreg.clamp(31, 254) / 69) * (highResolution2 ? 2 : 1);
    return counts.round().clamp(0, 0xFFFF);
  }

  // --- MPU-6050 -------------------------------------------------------------

  static const _mpuWhoAmI = 0x75;
  static const _mpuPowerManagement = 0x6B;
  static const _mpuGyroConfig = 0x1B;
  static const _mpuAccelConfig = 0x1C;
  static const _mpuData = 0x3B;

  /// The PWR_MGMT_1 value after power-on or a reset: asleep.
  static const _mpuAsleep = 0x40;

  /// An MPU-6050 accelerometer and gyroscope (the GY-521 module).
  ///
  /// Behaves like the chip where libraries look: it answers WHO_AM_I, boots
  /// asleep so a sketch that never wakes it reads zeros, clears its own reset
  /// bit (`Adafruit_MPU6050.begin()` waits for exactly that), and scales its
  /// samples to whatever range the sketch set.
  static void mpu6050(PartLogicContext context) {
    if (!I2cWiring.isPowered(context) || !I2cWiring.isOnTheBus(context)) return;

    final address = I2cWiring.isTiedHigh(context, 'ad0') ? 0x69 : 0x68;
    context.i2c.serve(address, size: 128);

    var power = _int(context.state['powerManagement'], _mpuAsleep);
    var accelConfig = _int(context.state['accelConfig']);
    var gyroConfig = _int(context.state['gyroConfig']);
    if (context.state['booted'] != true) {
      context.i2c.setRegisters(address, _mpuPowerManagement, const [_mpuAsleep]);
      context.state['booted'] = true;
    }

    for (final write in context.i2c.drain(address)) {
      // The first byte is the register pointer; a lone pointer precedes a read.
      for (var i = 1; i < write.length; i++) {
        final value = write[i];
        switch (write[0] + i - 1) {
          case _mpuPowerManagement when value & 0x80 != 0:
            // DEVICE_RESET: registers back to their defaults, and the bit
            // clears itself, which is what the sketch polls for.
            (power, accelConfig, gyroConfig) = (_mpuAsleep, 0, 0);
            context.i2c.setRegisters(address, _mpuGyroConfig, const [0, 0]);
            context.i2c.setRegisters(address, _mpuPowerManagement, const [_mpuAsleep]);
          case _mpuPowerManagement:
            power = value;
          case _mpuGyroConfig:
            gyroConfig = value;
          case _mpuAccelConfig:
            accelConfig = value;
        }
      }
    }
    context.state['powerManagement'] = power;
    context.state['accelConfig'] = accelConfig;
    context.state['gyroConfig'] = gyroConfig;

    // Read-only on the chip; republished in case the sketch wrote over it.
    context.i2c.setRegisters(address, _mpuWhoAmI, const [0x68]);
    if (power & _mpuAsleep != 0) return;

    context.i2c.setRegisters(
      address,
      _mpuData,
      mpu6050Sample(
        accel: (context.number('accelX'), context.number('accelY'), context.number('accelZ', 1)),
        gyro: (context.number('gyroX'), context.number('gyroY'), context.number('gyroZ')),
        celsius: context.number('temperature', 25),
        accelConfig: accelConfig,
        gyroConfig: gyroConfig,
      ),
    );
  }

  /// The 14 bytes from ACCEL_XOUT_H: acceleration, temperature and rotation,
  /// each a big-endian signed 16-bit value, at the ranges the two config
  /// registers select.
  static List<int> mpu6050Sample({
    required (double, double, double) accel,
    required (double, double, double) gyro,
    required double celsius,
    required int accelConfig,
    required int gyroConfig,
  }) {
    const accelCountsPerG = [16384.0, 8192.0, 4096.0, 2048.0];
    const gyroCountsPerDps = [131.0, 65.5, 32.8, 16.4];
    final perG = accelCountsPerG[(accelConfig >> 3) & 3];
    final perDps = gyroCountsPerDps[(gyroConfig >> 3) & 3];
    return [
      ..._int16(accel.$1 * perG),
      ..._int16(accel.$2 * perG),
      ..._int16(accel.$3 * perG),
      // The datasheet's formula, inverted: °C = raw / 340 + 36.53.
      ..._int16((celsius - 36.53) * 340),
      ..._int16(gyro.$1 * perDps),
      ..._int16(gyro.$2 * perDps),
      ..._int16(gyro.$3 * perDps),
    ];
  }

  // --- DS1307 ---------------------------------------------------------------

  static const _ds1307Address = 0x68;

  /// Registers 0–6 hold the time; the rest is control and 56 bytes of RAM,
  /// which the bus stores and reads back without this logic touching them.
  static const _ds1307TimeRegisters = 7;

  static final _epoch = DateTime.utc(2000);

  /// A DS1307 real-time clock.
  ///
  /// Counts simulated time, so it runs at the speed `millis()` does and stops
  /// when the run is paused. Starts either at the host's current time, like a
  /// module whose battery kept it set, or halted at 2000-01-01 like a chip
  /// that never was — the case `if (!rtc.isrunning()) rtc.adjust(...)` exists
  /// for. Needs 5 V: the DS1307 does not run from 3.3 V.
  static void ds1307(PartLogicContext context) {
    if (!I2cWiring.isPowered(context, accepted: const {'5V'}) || !I2cWiring.isOnTheBus(context)) {
      return;
    }
    context.i2c.serve(_ds1307Address, size: 64);

    final nowMs = context.elapsed.inMicroseconds / 1000;
    var halted = context.state['halted'] == true;
    var baseSeconds = _double(context.state['baseSeconds']);
    var anchorMs = _double(context.state['anchorMs']);
    if (context.state['booted'] != true) {
      halted = context.properties['startsAt'] == 'unset';
      baseSeconds = halted ? 0 : secondsSince2000(DateTime.now()).toDouble();
      anchorMs = nowMs;
      context.state['booted'] = true;
    }

    double current() => halted ? baseSeconds : baseSeconds + (nowMs - anchorMs) / 1000;

    for (final write in context.i2c.drain(_ds1307Address)) {
      if (write.length < 2 || write[0] >= _ds1307TimeRegisters) continue;
      // Written registers over the current time, so setting only the minutes
      // keeps the rest of the clock.
      final registers = ds1307Registers(current().floor(), halted: halted);
      for (var i = 1; i < write.length && write[0] + i - 1 < _ds1307TimeRegisters; i++) {
        registers[write[0] + i - 1] = write[i];
      }
      halted = registers[0] & 0x80 != 0;
      baseSeconds = ds1307Seconds(registers).toDouble();
      anchorMs = nowMs;
    }

    context.state['halted'] = halted;
    context.state['baseSeconds'] = baseSeconds;
    context.state['anchorMs'] = anchorMs;
    context.i2c.setRegisters(_ds1307Address, 0, ds1307Registers(current().floor(), halted: halted));
  }

  /// [time]'s wall-clock fields as seconds since 2000-01-01, ignoring its
  /// zone: the clock shows local time, whatever the host's offset.
  static int secondsSince2000(DateTime time) => DateTime.utc(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
    time.second,
  ).difference(_epoch).inSeconds;

  /// Registers 0–6 for [seconds] since 2000-01-01: BCD seconds (bit 7 is
  /// the clock-halt flag), minutes, 24-hour hours, day of week (Monday = 1),
  /// date, month, two-digit year.
  static List<int> ds1307Registers(int seconds, {bool halted = false}) {
    final t = _epoch.add(Duration(seconds: seconds));
    return [
      _bcd(t.second) | (halted ? 0x80 : 0),
      _bcd(t.minute),
      _bcd(t.hour),
      t.weekday,
      _bcd(t.day),
      _bcd(t.month),
      _bcd(t.year % 100),
    ];
  }

  /// The inverse of [ds1307Registers]. Reads 12-hour hours too, since a
  /// sketch may set bit 6 of the hours register.
  static int ds1307Seconds(List<int> registers) {
    final hoursRegister = registers[2];
    final hours = hoursRegister & 0x40 != 0
        ? _fromBcd(hoursRegister & 0x1F) % 12 + (hoursRegister & 0x20 != 0 ? 12 : 0)
        : _fromBcd(hoursRegister & 0x3F);
    return DateTime.utc(
      2000 + _fromBcd(registers[6]),
      _fromBcd(registers[5] & 0x1F),
      _fromBcd(registers[4] & 0x3F),
      hours,
      _fromBcd(registers[1] & 0x7F),
      _fromBcd(registers[0] & 0x7F),
    ).difference(_epoch).inSeconds;
  }

  // --- AHT20 ----------------------------------------------------------------

  static const _aht20Address = 0x38;

  /// Status byte: calibrated (bit 3), never busy — a measurement here is
  /// ready the moment it is asked for, so a sketch polling bit 7 moves on.
  static const _aht20Status = 0x18;

  /// An AHT20 temperature and humidity sensor.
  ///
  /// Like the BH1750 it has no registers to select: the sketch sends commands
  /// (trigger a measurement, soft reset) and reads a status byte followed by
  /// 20 bits of humidity, 20 bits of temperature and a CRC. The reading is
  /// always current, so it is published every frame rather than on trigger.
  static void aht20(PartLogicContext context) {
    if (!I2cWiring.isPowered(context) || !I2cWiring.isOnTheBus(context)) return;

    context.i2c.serve(_aht20Address, size: 7, pointerBytes: 0);
    // Commands need no answer beyond the reading itself; draining keeps the
    // queue from growing.
    context.i2c.drain(_aht20Address);
    context.i2c.setRegisters(
      _aht20Address,
      0,
      aht20Reading(
        humidity: context.number('humidity', 50),
        celsius: context.number('temperature', 25),
      ),
    );
  }

  /// The seven bytes the AHT20 answers a read with: status, humidity
  /// (`RH% = raw / 2^20 × 100`), temperature (`°C = raw / 2^20 × 200 − 50`),
  /// and a CRC-8 over the first six.
  static List<int> aht20Reading({required double humidity, required double celsius}) {
    const fullScale = 1 << 20;
    final rawHumidity = (humidity.clamp(0, 100) / 100 * fullScale).round().clamp(0, fullScale - 1);
    final rawTemperature = ((celsius.clamp(-50, 150) + 50) / 200 * fullScale).round().clamp(
      0,
      fullScale - 1,
    );
    final bytes = [
      _aht20Status,
      rawHumidity >> 12,
      (rawHumidity >> 4) & 0xFF,
      (rawHumidity & 0x0F) << 4 | rawTemperature >> 16,
      (rawTemperature >> 8) & 0xFF,
      rawTemperature & 0xFF,
    ];
    return [...bytes, _crc8(bytes)];
  }

  /// CRC-8 as the AHT20 computes it: polynomial 0x31, initial value 0xFF.
  static int _crc8(List<int> bytes) {
    var crc = 0xFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 0x80 != 0 ? ((crc << 1) ^ 0x31) & 0xFF : (crc << 1) & 0xFF;
      }
    }
    return crc;
  }

  // --- helpers --------------------------------------------------------------

  static int _bcd(int value) => (value ~/ 10) << 4 | value % 10;

  static int _fromBcd(int value) => (value >> 4) * 10 + (value & 0x0F);

  static List<int> _int16(double value) {
    final raw = value.round().clamp(-32768, 32767) & 0xFFFF;
    return [raw >> 8, raw & 0xFF];
  }

  static int _int(Object? value, [int orElse = 0]) => switch (value) {
    final num n => n.toInt(),
    _ => orElse,
  };

  static double _double(Object? value) => switch (value) {
    final num n => n.toDouble(),
    _ => 0,
  };
}
