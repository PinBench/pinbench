import 'dart:collection';
import 'dart:typed_data';

import 'package:avr8_dart/avr8_dart.dart';

import 'sim_log.dart';
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
class AVRBridge {
  static const _log = SimLog('app.simulation.avr');
  static late CPU _cpu;
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
    _usart.onLineTransmit = (line) {
      onSerialPrint?.call(line);
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
  }

  static bool isPinOutput(int pin) {
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

  static void tick(int cycles) {
    // Reset PWM duty accumulators for this frame.
    _dutyTotalSamples = 0;
    for (var p = 0; p < _dutyPinCount; p++) {
      _dutyHighSamples[p] = 0;
    }

    for (var i = 0; i < cycles; i++) {
      avrInstruction(_cpu);

      // Periodically sample digital pin levels to estimate PWM duty cycles.
      if ((i & (_dutySampleInterval - 1)) == 0) {
        _dutyTotalSamples++;
        for (var p = 0; p < _dutyPinCount; p++) {
          if (getPinState(p)) _dutyHighSamples[p]++;
        }
      }

      // Process all pending clock events for the current CPU cycle
      while (_cpu.nextClockEvent != null && _cpu.nextClockEvent!.cycles <= _cpu.cycles) {
        final event = _cpu.nextClockEvent!;
        _cpu.nextClockEvent = event.next;
        event.callback();
        if (_cpu.clockEventPool.length < 10) {
          _cpu.clockEventPool.add(event);
        }
      }

      // Feed queued serial input into the receiver as it frees up. writeByte
      // returns false while the USART is busy or RX is disabled, so the byte
      // stays queued until the sketch is ready for it.
      if (_rxQueue.isNotEmpty && !_usart.rxBusy && _usart.writeByte(_rxQueue.first)) {
        _rxQueue.removeFirst();
      }

      // Process interrupts
      if (_cpu.interruptsEnabled && _cpu.nextInterrupt >= 0) {
        final interrupt = _cpu.pendingInterrupts[_cpu.nextInterrupt];
        if (interrupt != null) {
          avrInterrupt(_cpu, interrupt.address);
          if (!interrupt.constant) {
            _cpu.clearInterrupt(interrupt);
          }
        }
      }

      if (_freqDetector.checkTimeout(_cpu.cycles)) {
        _log.trace('Tone stopped at cycle ${_cpu.cycles}');
        onBuzzerFrequencyChanged?.call(null);
      }
    }
  }

  static bool getPin13State() => _portB.pinState(5) == PinState.High;

  /// Whether the Arduino Uno's on-board LED is currently lit.
  ///
  /// The on-board LED is hard-wired to digital pin 13 (PB5), so this reflects
  /// the raw AVR port state directly. Unlike an attached LED component — whose
  /// brightness comes from the analog (SPICE) circuit solve — this signal is
  /// available from the emulator alone, which makes it the canonical way to
  /// observe a "blink" sketch.
  static bool get isBuiltinLedOn => getPin13State();

  static bool getPinState(int pin) {
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
    if (channel >= 0 && channel < _adc.channelValues.length) {
      _adc.channelValues[channel] = voltage;
    }
  }

  static void setDigitalPin(int pin, {required bool isHigh}) {
    if (pin >= 0 && pin <= 7) {
      _portD.setPin(pin, isHigh);
    } else if (pin >= 8 && pin <= 13) {
      _portB.setPin(pin - 8, isHigh);
    } else if (pin >= 14 && pin <= 19) {
      _portC.setPin(pin - 14, isHigh);
    }
  }

  static int getPortBValue() => _cpu.data[0x25]; // PORTB address

  static int getCycles() => _cpu.cycles;

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
class _RecordingTwiHandler implements TWIEventHandler {
  _RecordingTwiHandler(this.twi, this.recorder);

  final AVRTWI twi;
  final I2cRecorder recorder;

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
    // Nothing on the canvas talks back yet. 0xFF is what an idle bus reads,
    // pulled up and undriven, which is also what a sketch reading from a
    // device that is not there would see.
    twi.completeRead(0xFF);
  }
}
