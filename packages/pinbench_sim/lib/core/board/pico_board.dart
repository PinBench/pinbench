import 'dart:collection';
import 'dart:typed_data';

import 'package:pinbench_parts/models/board_profile.dart';
import 'package:rp2040_dart/bootrom.dart';
import 'package:rp2040_dart/rp2040_dart.dart';

import '../frequency_detector.dart';
import '../i2c_recorder.dart';
import 'board_emulator.dart';
import 'intel_hex.dart';

/// A Raspberry Pi Pico (W): `rp2040_dart` running an arduino-pico program.
///
/// Differs from the Uno's bridge in how it learns what a pin did. The AVR
/// loop samples its ports every few instructions; here every GPIO reports its
/// own edges (the chip calls its listeners whenever SIO, PWM or PIO changes a
/// pin), so duty, pulse widths and tone are read off edge timestamps — exact,
/// and blind to the core sleeping in `WFI` for most of a `delay()`, which a
/// per-instruction sample counts as one instant.
///
/// One instance per run: [loadHex] builds a fresh chip.
class PicoBoardEmulator implements BoardEmulator {
  @override
  BoardProfile get profile => BoardProfile.picoW;

  static const _flashStart = 0x10000000;
  static const _flashSize = 16 * 1024 * 1024;
  static const _gpioCount = 30;
  static const _nanosPerCycle = 1e9 / 125e6;

  /// Full scale of the 12-bit ADC, whose reference is the 3.3 V rail.
  static const _adcMax = 4095;
  static const _adcVref = 3.3;

  /// The chip and its clock. A `Simulator` only for the pairing: its own run
  /// loop yields to the event loop on a timer, and [tick] runs fixed slices
  /// instead.
  Simulator? _sim;
  RP2040? get _mcu => _sim?.rp2040;
  late USBCDC _cdc;
  var _usbConnected = false;

  final _i2c = I2cRecorder();

  /// Typed Serial Monitor bytes waiting for `Serial` (USB) and for `Serial1`
  /// (UART0). Each line goes to both, so a sketch reads it from whichever port
  /// it listens on; one that reads both sees it twice, as it would with a
  /// terminal attached to each.
  final _rxQueue = Queue<int>();
  final _uartRxQueue = Queue<int>();
  final _freqDetector = FrequencyDetector(clockHz: BoardProfile.picoW.clockHz);

  // Per-pin edge bookkeeping, in clock nanoseconds. A pin is high exactly when
  // its `_highSince` is non-negative.
  final _highSince = Float64List(_gpioCount);
  final _highNanos = Float64List(_gpioCount);
  final _duty = Float64List(_gpioCount);
  var _windowStart = 0.0;
  final _servoRise = Float64List(_gpioCount);
  final _servoPulseUs = Float64List(_gpioCount);
  final _waveformEnds = <int, double>{};
  final _lastInput = List<bool?>.filled(_gpioCount, null);

  @override
  void loadHex(String hex, {void Function(String line)? onSerialPrint}) {
    final segments = IntelHex.decode(hex);
    bool inFlash(HexSegment s) =>
        s.address >= _flashStart && s.address + s.bytes.length <= _flashStart + _flashSize;
    if (!segments.any(inFlash)) {
      throw const FormatException(
        'This program was built for a different board, not the Raspberry Pi Pico W on the canvas.',
      );
    }

    final sim = _sim = Simulator();
    final mcu = sim.rp2040
      ..logger = const _QuietLogger()
      // Resets the chip, which erases flash, so the program goes in after it.
      ..loadBootrom(bootromB1);
    for (final segment in segments.where(inFlash)) {
      mcu.flash.setAll(segment.address - _flashStart, segment.bytes);
    }
    // Start at the second-stage bootloader at the top of flash, as rp2040js's
    // examples do, skipping the boot ROM's search for it.
    mcu.core.PC = _flashStart;

    _usbConnected = false;
    _rxQueue.clear();
    _uartRxQueue.clear();
    _sdaPin = _defaultSdaPin;
    _sclPin = _defaultSclPin;

    // ADC inputs no part drives. Channel 3 is GP29, wired on the board to VSYS
    // through a 3:1 divider; channel 4 is the die's temperature sensor, which
    // reads 0.706 V at 27 °C. Left at 0, `analogReadTemp()` reported a chip
    // at 437 °C.
    mcu.adc.channelValues[3] = _adcCounts(BoardProfile.picoW.supplies['VSYS']! / 3);
    mcu.adc.channelValues[4] = _adcCounts(0.706);
    _cdc = USBCDC(mcu.usbCtrl)
      ..onDeviceConnected = (() => _usbConnected = true)
      ..onSerialData = _lineSplitter(onSerialPrint);
    final uartLine = _lineSplitter(onSerialPrint);
    mcu.uart[0].onByte = (byte) => uartLine(Uint8List.fromList([byte]));

    _i2c.reset();
    mcu.i2c.forEach(_wireI2c);

    _probeBits = -1;
    _probeHeldSda = null;
    _scl = true;
    _sda = true;
    _freqDetector.reset();
    _waveformEnds.clear();
    _lastInput.fillRange(0, _gpioCount, null);
    _highSince.fillRange(0, _gpioCount, -1);
    _highNanos.fillRange(0, _gpioCount, 0);
    _duty.fillRange(0, _gpioCount, 0);
    _servoRise.fillRange(0, _gpioCount, -1);
    _servoPulseUs.fillRange(0, _gpioCount, 0);
    _windowStart = 0;
    for (var pin = 0; pin < _gpioCount; pin++) {
      mcu.gpio[pin].addListener((state, old) => _onEdge(pin, state, old));
    }
  }

  /// Bytes in, whole lines out: `println` ends lines with CRLF, and the CR is
  /// dropped here so no consumer has to.
  static void Function(Uint8List bytes) _lineSplitter(void Function(String)? onLine) {
    final line = StringBuffer();
    return (bytes) {
      for (final byte in bytes) {
        if (byte == 0x0a) {
          onLine?.call(line.toString());
          line.clear();
        } else if (byte != 0x0d) {
          line.writeCharCode(byte);
        }
      }
    };
  }

  void _wireI2c(RPI2C bus) {
    final i2c = _i2c;
    bus
      ..onStart = ((_) => bus.completeStart())
      ..onConnect = (address, mode) {
        i2c.beginTransaction(address, write: mode == I2CMode.Write);
        // The ACK is what `Wire.endTransmission()` returns and an I²C scanner
        // counts, so only a device on the canvas may give it.
        bus.completeConnect(i2c.acknowledges(address));
      }
      ..onWriteByte = (value) {
        i2c.writeByte(value);
        bus.completeWrite(true);
      }
      ..onReadByte = ((_) => bus.completeRead(i2c.readByte()))
      ..onStop = () {
        i2c.endTransaction();
        bus.completeStop();
      };
  }

  void _onEdge(int pin, GPIOPinState state, GPIOPinState old) {
    // Before the high/low filter below: a released open-drain line changes
    // from driven-low to an input, which is a rise on the bus but not a pin
    // the sketch drives high.
    if (pin != _sdaPin && pin != _sclPin && _probeBits < 0) _followProbe(pin);
    if (pin == _sdaPin || pin == _sclPin) _watchProbe();

    final isHigh = state == GPIOPinState.High;
    if (isHigh == (old == GPIOPinState.High)) return;
    final now = _sim!.clock.nanos;
    if (isHigh) {
      _highSince[pin] = now;
      _servoRise[pin] = now;
    } else {
      final since = _highSince[pin];
      if (since >= 0) _highNanos[pin] += now - since;
      _highSince[pin] = -1;
      final rise = _servoRise[pin];
      if (rise >= 0) {
        final us = (now - rise) / 1000;
        // Servo control pulses are ~0.4–3 ms; anything else on the pin (PWM,
        // glitches) is ignored.
        if (us >= 400 && us <= 3000) _servoPulseUs[pin] = us;
      }
    }
    if (pin == buzzerPin) {
      _freqDetector.onPinToggle(getCycles(), (hz) => onBuzzerFrequencyChanged?.call(hz));
    }
  }

  // The pins `Wire` drives: I2C0 on GP4/GP5 until the sketch moves it, which
  // [_followI2cPins] notices. The address probe is watched on these.
  static const _defaultSdaPin = 4;
  static const _defaultSclPin = 5;
  var _sdaPin = _defaultSdaPin;
  var _sclPin = _defaultSclPin;

  /// GPIO function 3: the pin belongs to an I²C block.
  static const _functionI2c = 3;

  /// Moves the probe watch to whichever pins the sketch has given to I²C —
  /// `Wire.setSDA()`/`setSCL()`, or `Wire1` — preferring a pair on one block.
  ///
  /// On the RP2040 an even GPIO can be its I²C block's SDA and an odd one its
  /// SCL, and which block is bit 1 of the pin number. Scanned once a slice,
  /// not per edge: pins change function at `Wire.begin()`, a handful of times
  /// in a run, and during the probe itself they are plain GPIOs, so the last
  /// pair seen in I²C mode is the one being probed.
  void _followI2cPins(RP2040 mcu) {
    // (The slice-end scan; [_followProbe] catches a probe that starts within
    // the same slice as `Wire.begin()`, which is the usual case.)
    for (final bus in const [0, 1]) {
      int? sda;
      int? scl;
      for (var pin = 0; pin < _gpioCount; pin++) {
        if (mcu.gpio[pin].functionSelect != _functionI2c || (pin >> 1) & 1 != bus) continue;
        if (pin.isEven) {
          sda ??= pin;
        } else {
          scl ??= pin;
        }
      }
      if (sda != null && scl != null) {
        _sdaPin = sda;
        _sclPin = scl;
        return;
      }
    }
  }

  // The address probe in flight: bits of the address byte read so far (-1
  // when none is), the byte itself, and the bus as last seen.
  var _probeBits = -1;
  var _probeByte = 0;
  bool? _probeHeldSda;
  var _scl = true;
  var _sda = true;

  /// Switches the probe watch to [pin]'s pair when [pin] has just left I²C for
  /// a plain GPIO while its partner is still on I²C — the first step of
  /// arduino-pico's probe, which takes the pins one at a time. `Wire.begin()`
  /// and a scanner's first probe usually fall in the same slice, before the
  /// slice-end scan in [_followI2cPins] has seen the pins move.
  void _followProbe(int pin) {
    final mcu = _mcu!;
    final partner = pin.isEven ? pin + 1 : pin - 1;
    if (partner < 0 || partner >= _gpioCount) return;
    if (mcu.gpio[pin].functionSelect == _functionI2c) return;
    if (mcu.gpio[partner].functionSelect != _functionI2c) return;
    _sdaPin = pin.isEven ? pin : partner;
    _sclPin = pin.isEven ? partner : pin;
    _scl = _line(_sclPin);
    _sda = _line(_sdaPin);
  }

  /// The level on bus line [pin]: what the sketch drives when the pin is an
  /// output, and otherwise what the circuit holds it at.
  bool _line(int pin) {
    final gpio = _mcu!.gpio[pin];
    return gpio.outputEnable ? gpio.outputValue : (_lastInput[pin] ?? false);
  }

  /// Answers arduino-pico's address probe, the empty `Wire` write every I²C
  /// scanner makes.
  ///
  /// The RP2040's I²C block cannot send an address with no data after it, so
  /// for a zero-length write arduino-pico takes SDA and SCL as plain GPIOs and
  /// bit-bangs a START, the address, and a ninth clock, reading SDA there for
  /// the ACK. The peripheral above never sees any of it. This watches the two
  /// lines instead and, for an address a part on the canvas has claimed, holds
  /// SDA low through that ninth clock as the device would.
  void _watchProbe() {
    final scl = _line(_sclPin);
    final sda = _line(_sdaPin);
    if (scl && _scl) {
      if (_sda && !sda) {
        // START: SDA falls while SCL is high.
        _probeBits = 0;
        _probeByte = 0;
      } else if (!_sda && sda) {
        // STOP: SDA rises while SCL is high.
        _endProbe();
      }
    } else if (scl && !_scl) {
      if (_probeBits >= 0 && _probeBits < 8) {
        _probeByte = (_probeByte << 1) | (sda ? 1 : 0);
        _probeBits++;
      }
    } else if (!scl && _scl) {
      if (_probeBits == 8) {
        _probeBits = 9;
        if (_i2c.acknowledges(_probeByte >> 1)) {
          _probeHeldSda = _lastInput[_sdaPin] ?? true;
          setDigitalPin(_sdaPin, isHigh: false);
        }
      } else if (_probeBits == 9) {
        _endProbe();
      }
    }
    _scl = scl;
    _sda = _line(_sdaPin);
  }

  void _endProbe() {
    _probeBits = -1;
    final held = _probeHeldSda;
    if (held == null) return;
    _probeHeldSda = null;
    setDigitalPin(_sdaPin, isHigh: held);
  }

  @override
  void tick(int cycles) {
    final mcu = _mcu;
    if (mcu == null) return;
    final clock = _sim!.clock;
    final core = mcu.core;

    // A new duty window: whatever was high carries on being high from now.
    final start = clock.nanos;
    for (var pin = 0; pin < _gpioCount; pin++) {
      _highNanos[pin] = 0;
      if (_highSince[pin] >= 0) _highSince[pin] = start;
    }
    _windowStart = start;

    _feedSerial();
    final end = start + cycles * _nanosPerCycle;
    while (clock.nanos < end) {
      if (core.waiting) {
        // Asleep in WFI/WFE until the next alarm: skip straight to it, but not
        // past the end of the slice, so the frame loop stays in charge of time.
        final toAlarm = clock.nanosToNextAlarm;
        final remaining = end - clock.nanos;
        clock.tick(toAlarm > 0 && toAlarm < remaining ? toAlarm : remaining);
      } else {
        clock.tick(core.executeInstruction().toDouble() * _nanosPerCycle);
      }
    }

    final now = clock.nanos;
    final window = now - _windowStart;
    for (var pin = 0; pin < _gpioCount; pin++) {
      var high = _highNanos[pin];
      if (_highSince[pin] >= 0) high += now - _highSince[pin];
      _duty[pin] = window > 0 ? high / window : (_highSince[pin] >= 0 ? 1 : 0);
    }
    if (_freqDetector.checkTimeout(getCycles())) onBuzzerFrequencyChanged?.call(null);
    _followI2cPins(mcu);
  }

  /// The UART's receive-FIFO-full flag (UARTFR.RXFF).
  static const _uartRxFull = 1 << 6;

  /// Moves typed bytes into each serial port as it has room: USB once the
  /// sketch's USB stack has enumerated, which is when `Serial` exists at all,
  /// and UART0 once `Serial1.begin()` has enabled it.
  void _feedSerial() {
    if (_usbConnected) {
      final fifo = _cdc.txFIFO;
      while (_rxQueue.isNotEmpty && !fifo.full) {
        _cdc.sendSerialByte(_rxQueue.removeFirst());
      }
    }
    final uart = _mcu!.uart[0];
    while (_uartRxQueue.isNotEmpty && uart.enabled && uart.flags & _uartRxFull == 0) {
      uart.feedByte(_uartRxQueue.removeFirst());
    }
  }

  @override
  int getCycles() => _mcu == null ? 0 : (_sim!.clock.nanos / _nanosPerCycle).round();

  bool _isPin(int pin) => pin >= 0 && pin < _gpioCount;

  @override
  bool getPinState(int pin) => _isPin(pin) && _mcu?.gpio[pin].value == GPIOPinState.High;

  @override
  double getPinDuty(int pin) => _isPin(pin) && _mcu != null ? _duty[pin] : 0;

  @override
  bool isPinOutput(int pin) => _isPin(pin) && (_mcu?.gpio[pin].outputEnable ?? false);

  @override
  void setDigitalPin(int pin, {required bool isHigh}) {
    final mcu = _mcu;
    if (mcu == null || !_isPin(pin)) return;
    // Only on a change: the chip latches an edge interrupt on every call, so
    // re-asserting the same level each frame would fire `attachInterrupt`
    // handlers sixty times a second with nothing happening.
    if (_lastInput[pin] == isHigh) return;
    _lastInput[pin] = isHigh;
    mcu.gpio[pin].setInputValue(isHigh);
  }

  @override
  void playWaveform(int pin, List<(bool, double)> levels, {double gapUs = 0}) {
    if (_mcu == null || !_isPin(pin)) return;
    final now = _sim!.clock.nanos;
    final previous = _waveformEnds[pin];
    var at = previous == null || previous <= now ? 0.0 : previous - now + gapUs * 1000;
    for (final (isHigh, us) in levels) {
      _sim!.clock.createAlarm(() => setDigitalPin(pin, isHigh: isHigh)).schedule(at);
      at += us * 1000;
    }
    _waveformEnds[pin] = now + at;
  }

  @override
  bool isPinDriven(int pin) {
    final end = _waveformEnds[pin];
    if (end == null) return false;
    if (_mcu != null && _sim!.clock.nanos < end) return true;
    _waveformEnds.remove(pin);
    return false;
  }

  @override
  void setAnalogVoltage(int channel, double voltage) {
    final adc = _mcu?.adc;
    if (adc == null || channel < 0 || channel >= adc.channelValues.length) return;
    adc.channelValues[channel] = _adcCounts(voltage);
  }

  /// [voltage] as the 12-bit ADC reads it against its 3.3 V reference.
  static int _adcCounts(double voltage) => (voltage / _adcVref * _adcMax).round().clamp(0, _adcMax);

  @override
  void queueSerialInput(String text) {
    _rxQueue.addAll(text.codeUnits);
    _uartRxQueue.addAll(text.codeUnits);
  }

  /// Every pin's pulses are measured, not just these: the edges arrive anyway,
  /// and timing one costs a subtraction. Kept only to be read back.
  @override
  List<int> servoPins = const [];

  @override
  double getServoPulseUs(int pin) => _isPin(pin) ? _servoPulseUs[pin] : 0;

  @override
  int? buzzerPin;

  @override
  void Function(double? hz)? onBuzzerFrequencyChanged;

  @override
  bool get isBuiltinLedOn => getPinState(BoardProfile.picoW.builtinLedPin!);

  @override
  void listenI2c(int address) => _i2c.listenAt(address);

  @override
  List<List<int>> drainI2c(int address) => _i2c.drain(address);

  @override
  void serveI2c(int address, {int size = 256, int pointerBytes = 1}) =>
      _i2c.serve(address, size: size, pointerBytes: pointerBytes);

  @override
  void setI2cRegisters(int address, int offset, List<int> bytes) =>
      _i2c.setRegisters(address, offset, bytes);
}

/// Drops the chip's own log lines. rp2040_dart reports registers the port has
/// not implemented — the arduino-pico runtime touches a few at boot — and its
/// default logger prints each one, and *throws* on errors.
class const _QuietLogger() implements Logger {
  @override
  void debug(String componentName, String message) {}
  @override
  void info(String componentName, String message) {}
  @override
  void warn(String componentName, String message) {}
  @override
  void error(String componentName, String message) {}
}
