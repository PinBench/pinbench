import 'dart:collection';
import 'dart:typed_data';

import 'package:avr8_dart/avr8_dart.dart';

import 'frequency_detector.dart';
import 'i2c_recorder.dart';

/// Static facade over the `avr8_dart` ATmega328P emulator.
///
/// Loads a compiled HEX, steps the CPU ([tick]), and exposes the I/O the
/// simulator needs: digital pin levels and PWM duty ([getPinState],
/// [getPinDuty]), ADC injection ([setAnalogVoltage]) for analogRead, serial
/// RX queueing ([queueSerialInput]) and TX (via onSerialPrint), and buzzer
/// frequency detection. State is static because the emulator is a singleton per
/// process; [loadHex] fully re-creates the CPU on each run.
///
/// The same code on every platform: desktop runs it in the simulation
/// isolate, and the web app, compiled to WebAssembly, runs it inline. The web
/// once used a separate JavaScript emulator (`avr8js`, then a dart2js build of
/// this file); since `avr8_dart` 0.2.0, dart2wasm runs this loop as fast as
/// dart2js does (≈4.7× real time), so the web needs nothing of its own.
class AVRBridge {
  static late CPU _cpu;

  /// Whether a program has been loaded. Everything that reads the CPU answers
  /// a harmless default before then, because the canvas asks for pin states
  /// before the first Run.
  static var _loaded = false;
  static CPU get cpu => _cpu;
  static late AVRIOPort _portB;
  static late AVRIOPort _portC;
  static late AVRIOPort _portD;
  static late AVRADC _adc;

  // Required to keep a reference to prevent garbage collection
  // Reason: required by avr8_dart to keep timer active
  // ignore: unused_field
  static late AVRTimer _timer0;
  // Reason: required by avr8_dart to keep timer active
  // ignore: unused_field
  static late AVRTimer _timer1;
  // Reason: required by avr8_dart to keep timer active
  // ignore: unused_field
  static late AVRTimer _timer2;
  static late AVRUSART _usart;
  // The TWI peripheral installs a CPU write hook and is driven from it, so
  // nothing else references it once constructed — but it must stay reachable,
  // like the timers above.
  static late AVRTWI _twi;

  /// Everything the sketch has put on the I²C bus, waiting for the parts that
  /// listen for it. See [I2cRecorder] for why bus traffic is queued rather
  /// than sampled like a pin.
  static final _i2c = I2cRecorder();

  /// Claims [address] on the bus, so a device at it acknowledges and its
  /// traffic is kept for [drainI2c].
  static void listenI2c(int address) => _i2c.listenAt(address);

  /// Every transaction written to [address] since the last call.
  static List<List<int>> drainI2c(int address) => _i2c.drain(address);

  /// Makes [address] answer the sketch's reads from a bank of [size]
  /// registers. See [I2cRecorder.serve].
  static void serveI2c(int address, {int size = 256, int pointerBytes = 1}) =>
      _i2c.serve(address, size: size, pointerBytes: pointerBytes);

  /// Publishes [bytes] into [address]'s registers from [offset].
  static void setI2cRegisters(int address, int offset, List<int> bytes) =>
      _i2c.setRegisters(address, offset, bytes);

  static void Function(double?)? onBuzzerFrequencyChanged;

  /// The Arduino pin number connected to the piezo buzzer.
  /// Frequency detection is ONLY performed on this pin to avoid false triggers
  /// from serial TX, LED PWM, or other toggling pins.
  /// Set by SimulationRunner before starting the emulation loop.
  static int? buzzerPin;

  /// Arduino pins driving servo signal lines. HIGH-pulse widths are measured
  /// only on these pins (set from the traced netlist, like [buzzerPin]) so
  /// serial TX / LED PWM toggles can't masquerade as servo pulses.
  static List<int> servoPins = const [];

  // Per-pin servo pulse measurement: cycle stamp of the last rising edge, and
  // the width of the last completed HIGH pulse in microseconds.
  static final _servoRiseCycle = List<int>.filled(_dutyPinCount, -1);
  static final _servoPulseUs = List<double>.filled(_dutyPinCount, 0);

  /// Width (µs) of the most recent completed HIGH pulse on [pin], or 0 if none
  /// has been seen since the current program was loaded. Only meaningful for
  /// pins registered in [servoPins].
  static double getServoPulseUs(int pin) =>
      (pin >= 0 && pin < _dutyPinCount) ? _servoPulseUs[pin] : 0;

  static final _freqDetector = FrequencyDetector();

  // Bytes the user typed in the Serial Monitor, drip-fed into the USART receiver
  // as it becomes free (mirrors a real serial line into Serial.read/available).
  static final _rxQueue = Queue<int>();

  /// Queues [text] to be delivered to the running sketch's serial receiver.
  static void queueSerialInput(String text) {
    _rxQueue.addAll(text.codeUnits);
  }

  // Per-frame PWM duty-cycle sampling for digital pins 0..13. The pin is sampled
  // periodically across a [tick] call; getPinDuty returns the fraction of
  // samples the pin was high — i.e. the analogWrite() duty cycle.
  static const _dutyPinCount = 14;
  static const _dutySampleInterval = 64; // sample once every N CPU cycles
  static final _dutyHighSamples = List<int>.filled(_dutyPinCount, 0);
  static var _dutyTotalSamples = 0;

  /// Fraction of the last [tick] window that [pin] was driven high (0.0–1.0).
  /// Falls back to the instantaneous level if no samples were taken yet.
  static double getPinDuty(int pin) {
    if (!_loaded) return 0;
    if (pin < 0 || pin >= _dutyPinCount) return getPinState(pin) ? 1.0 : 0.0;
    if (_dutyTotalSamples == 0) return getPinState(pin) ? 1.0 : 0.0;
    return _dutyHighSamples[pin] / _dutyTotalSamples;
  }

  static void loadHex(String hexString, {void Function(String)? onSerialPrint}) {
    _rxQueue.clear();
    _servoRiseCycle.fillRange(0, _servoRiseCycle.length, -1);
    _servoPulseUs.fillRange(0, _servoPulseUs.length, 0);
    final program = Uint16List(0x4000); // 32KB flash is 16K x 16-bit
    _parseHex(hexString, program);
    _cpu = CPU(program);
    _timer0 = AVRTimer(_cpu, timer0Config);
    _timer1 = AVRTimer(_cpu, timer1Config);
    _timer2 = AVRTimer(_cpu, timer2Config);
    _usart = AVRUSART(_cpu, usart0Config, 16000000);
    // `Serial.println` ends lines with CRLF and the USART splits on the LF;
    // the CR is dropped here so no consumer has to.
    _usart.onLineTransmit = (line) {
      onSerialPrint?.call(line.endsWith('\r') ? line.substring(0, line.length - 1) : line);
    };
    _portB = AVRIOPort(_cpu, portBConfig);
    _portB.addListener(_handlePortBChange);

    _portC = AVRIOPort(_cpu, portCConfig);
    _portC.addListener(_handlePortCChange);

    _portD = AVRIOPort(_cpu, portDConfig);
    _portD.addListener(_handlePortDChange);

    _adc = AVRADC(_cpu, adcConfig);

    // The bus is rebuilt with the program: claims belong to the parts of the
    // run that just ended, and its traffic to the sketch that just stopped.
    _i2c.reset();
    _twi = AVRTWI(_cpu, twiConfig, 16000000);
    _twi.eventHandler = _RecordingTwiHandler(_twi, _i2c);

    _freqDetector.reset();
    _waveformEnds.clear();
    _loaded = true;
  }

  static bool isPinOutput(int pin) {
    if (!_loaded) return false;
    if (pin >= 0 && pin <= 7) {
      return (_cpu.data[portDConfig.DDR] & (1 << pin)) != 0;
    } else if (pin >= 8 && pin <= 13) {
      return (_cpu.data[portBConfig.DDR] & (1 << (pin - 8))) != 0;
    } else if (pin >= 14 && pin <= 19) {
      return (_cpu.data[portCConfig.DDR] & (1 << (pin - 14))) != 0;
    }
    return false;
  }

  static void _handlePortDChange(int value, int oldValue) => _handlePortChange(0, value, oldValue);
  static void _handlePortBChange(int value, int oldValue) => _handlePortChange(8, value, oldValue);
  static void _handlePortCChange(int value, int oldValue) => _handlePortChange(14, value, oldValue);

  static void _handlePortChange(int pinOffset, int value, int oldValue) {
    final changedBits = value ^ oldValue;
    if (changedBits == 0) return;

    final bPin = buzzerPin;
    if (bPin != null &&
        bPin >= pinOffset &&
        bPin < pinOffset + 8 &&
        (changedBits & (1 << (bPin - pinOffset))) != 0) {
      _freqDetector.onPinToggle(_cpu.cycles, (freq) => onBuzzerFrequencyChanged?.call(freq));
    }

    for (final sPin in servoPins) {
      if (sPin < pinOffset || sPin >= pinOffset + 8) continue;
      final bit = 1 << (sPin - pinOffset);
      if ((changedBits & bit) == 0) continue;
      if ((value & bit) != 0) {
        _servoRiseCycle[sPin] = _cpu.cycles;
      } else {
        final rise = _servoRiseCycle[sPin];
        if (rise >= 0) {
          final us = (_cpu.cycles - rise) / 16.0; // 16 MHz clock
          // Servo control pulses are ~0.4–3 ms; anything else on the pin
          // (PWM, glitches) is ignored.
          if (us >= 400 && us <= 3000) _servoPulseUs[sPin] = us;
        }
      }
    }
  }

  /// Runs the CPU for [cycles] clock cycles — simulated time, which the frame
  /// loop derives from wall-clock time.
  ///
  /// Counted in *cycles*, not instructions: most AVR instructions take one
  /// cycle but branches, calls and memory access take two to four, so a loop
  /// over instructions ran typical sketches about 30% fast (`delay(1000)`
  /// lasted 0.77 s).
  static void tick(int cycles) {
    if (!_loaded) return;
    // Everything the loop touches is read into a local first. `_cpu` and the
    // other statics are lazily initialised, so every access checks whether
    // they are set yet, and on the web that check costs far more than a
    // local read in a loop that runs about 60 million times a second.
    final cpu = _cpu;
    final usart = _usart;
    final portB = _portB;
    final portD = _portD;
    final rxQueue = _rxQueue;
    final freqDetector = _freqDetector;
    final dutyHigh = _dutyHighSamples;
    final ddrD = portDConfig.DDR;
    final ddrB = portBConfig.DDR;

    // Reset PWM duty accumulators for this frame.
    var dutyTotal = 0;
    for (var p = 0; p < _dutyPinCount; p++) {
      dutyHigh[p] = 0;
    }

    final limit = cpu.cycles + cycles;
    for (var i = 0; cpu.cycles < limit; i++) {
      avrInstruction(cpu);

      // Periodically sample digital pin levels to estimate PWM duty cycles:
      // pins 0-7 are PORTD, 8-13 are PORTB. A pin is driven high exactly when
      // `AVRIOPort.pinState` would say `High` — an output, last written 1, not
      // open-collector — and computing that as one mask per port instead of
      // fourteen enum lookups keeps the sampler off the profile.
      if ((i & (_dutySampleInterval - 1)) == 0) {
        dutyTotal++;
        final highD = cpu.data[ddrD] & portD.lastValue & ~portD.openCollector;
        final highB = cpu.data[ddrB] & portB.lastValue & ~portB.openCollector;
        if (highD != 0) {
          for (var p = 0; p < 8; p++) {
            if ((highD & (1 << p)) != 0) dutyHigh[p]++;
          }
        }
        if (highB != 0) {
          for (var p = 8; p < _dutyPinCount; p++) {
            if ((highB & (1 << (p - 8))) != 0) dutyHigh[p]++;
          }
        }
      }

      // Process all pending clock events for the current CPU cycle
      while (cpu.nextClockEvent != null && cpu.nextClockEvent!.cycles <= cpu.cycles) {
        final event = cpu.nextClockEvent!;
        cpu.nextClockEvent = event.next;
        event.callback();
        if (cpu.clockEventPool.length < 10) {
          cpu.clockEventPool.add(event);
        }
      }

      // Feed queued serial input into the receiver as it frees up. writeByte
      // returns false while the USART is busy or RX is disabled, so the byte
      // stays queued until the sketch is ready for it.
      if (rxQueue.isNotEmpty && !usart.rxBusy && usart.writeByte(rxQueue.first)) {
        rxQueue.removeFirst();
      }

      // Process interrupts
      if (cpu.interruptsEnabled && cpu.nextInterrupt >= 0) {
        final interrupt = cpu.pendingInterrupts[cpu.nextInterrupt];
        if (interrupt != null) {
          avrInterrupt(cpu, interrupt.address);
          if (!interrupt.constant) {
            cpu.clearInterrupt(interrupt);
          }
        }
      }

      if (freqDetector.checkTimeout(cpu.cycles)) {
        onBuzzerFrequencyChanged?.call(null);
      }
    }
    _dutyTotalSamples = dutyTotal;
  }

  static bool getPin13State() => _loaded && _portB.pinState(5) == PinState.High;

  /// Whether the Arduino Uno's on-board LED is currently lit.
  ///
  /// The on-board LED is hard-wired to digital pin 13 (PB5), so this reflects
  /// the raw AVR port state directly. Unlike an attached LED component — whose
  /// brightness comes from the analog (SPICE) circuit solve — this signal is
  /// available from the emulator alone, which makes it the canonical way to
  /// observe a "blink" sketch.
  static bool get isBuiltinLedOn => getPin13State();

  static bool getPinState(int pin) {
    if (!_loaded) return false;
    if (pin >= 0 && pin <= 7) {
      return _portD.pinState(pin) == PinState.High;
    } else if (pin >= 8 && pin <= 13) {
      return _portB.pinState(pin - 8) == PinState.High;
    } else if (pin >= 14 && pin <= 19) {
      return _portC.pinState(pin - 14) == PinState.High;
    }
    return false;
  }

  static void setAnalogVoltage(int channel, double voltage) {
    if (!_loaded) return;
    if (channel >= 0 && channel < _adc.channelValues.length) {
      _adc.channelValues[channel] = voltage;
    }
  }

  /// The cycle each waveform-driven input pin's waveform ends on.
  static final Map<int, int> _waveformEnds = {};

  /// Plays [levels] into input [pin], each `(isHigh, microseconds)` holding
  /// for its time, starting now — or [gapUs] after any waveform already
  /// playing on the pin, so presses queue rather than garble one another.
  ///
  /// Every edge is a CPU clock event, so it lands on its exact cycle however
  /// the frame loop slices time: a 562 µs IR mark is 9000 cycles here, where a
  /// frame is a quarter of a million. Pin-change and external interrupts fire
  /// on each edge as they would for a real signal. While it plays, the pin is
  /// [isPinDriven], and the per-frame input update leaves it alone.
  static void playWaveform(int pin, List<(bool, double)> levels, {double gapUs = 0}) {
    if (!_loaded) return;
    final cpu = _cpu;
    final previous = _waveformEnds[pin];
    final start = previous == null || previous <= cpu.cycles
        ? cpu.cycles
        : previous + 1 + (gapUs * _cyclesPerUs).round();
    var at = start - cpu.cycles;
    for (final (isHigh, us) in levels) {
      cpu.addClockEvent(() => setDigitalPin(pin, isHigh: isHigh), at);
      at += (us * _cyclesPerUs).round();
    }
    _waveformEnds[pin] = cpu.cycles + at;
  }

  /// Whether a [playWaveform] waveform is still driving input [pin].
  static bool isPinDriven(int pin) {
    final end = _waveformEnds[pin];
    if (end == null) return false;
    if (_loaded && _cpu.cycles < end) return true;
    _waveformEnds.remove(pin);
    return false;
  }

  static const _cyclesPerUs = 16; // 16 MHz clock

  static void setDigitalPin(int pin, {required bool isHigh}) {
    if (!_loaded) return;
    if (pin >= 0 && pin <= 7) {
      _portD.setPin(pin, isHigh);
    } else if (pin >= 8 && pin <= 13) {
      _portB.setPin(pin - 8, isHigh);
    } else if (pin >= 14 && pin <= 19) {
      _portC.setPin(pin - 14, isHigh);
    }
  }

  static int getPortBValue() => _loaded ? _cpu.data[0x25] : 0; // PORTB address

  static int getCycles() => _loaded ? _cpu.cycles : 0;

  static void _parseHex(String hexString, Uint16List flash) {
    flash.fillRange(0, flash.length, 0);
    final lines = hexString.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line[0] != ':') continue;

      final type = line.substring(7, 9);
      if (type == '00') {
        // Data record
        final length = int.parse(line.substring(1, 3), radix: 16);
        final addr = int.parse(line.substring(3, 7), radix: 16);

        for (var i = 0; i < length; i += 2) {
          final lsb = int.parse(line.substring(9 + i * 2, 11 + i * 2), radix: 16);
          var msb = 0;
          if (i + 1 < length) {
            msb = int.parse(line.substring(11 + i * 2, 13 + i * 2), radix: 16);
          }
          flash[(addr + i) >> 1] = (msb << 8) | lsb;
        }
      }
    }
  }
}

/// Feeds the emulator's TWI (I²C) peripheral into an [I2cRecorder].
///
/// The peripheral drives this: every event asks a question and waits for the
/// matching `complete*` call, which is what lets a real implementation model
/// bus timing. Nothing here needs to — a simulated peripheral answers as fast
/// as the wire allows — so each event completes immediately, and the whole
/// class is the translation from bus events to recorded transactions.
class _RecordingTwiHandler(final AVRTWI twi, final I2cRecorder recorder)
    implements TWIEventHandler {
  @override
  void start(bool repeated) => twi.completeStart();

  @override
  void stop() {
    recorder.endTransaction();
    twi.completeStop();
  }

  @override
  void connectToSlave(int addr, bool write) {
    recorder.beginTransaction(addr, write: write);
    // The ACK is the only answer that reaches the sketch: it is what
    // `Wire.endTransmission()` returns and what an I²C scanner counts, so a
    // device that is not on the canvas must not answer for one that is.
    twi.completeConnect(recorder.acknowledges(addr));
  }

  @override
  void writeByte(int value) {
    recorder.writeByte(value);
    twi.completeWrite(true);
  }

  @override
  void readByte(bool ack) {
    // From the registers a part serves, or 0xFF — what a pulled-up, undriven
    // bus reads — when nothing on the canvas answers at this address.
    twi.completeRead(recorder.readByte());
  }
}
