// Full AVR bridge backed by avr8js (hand-optimized JS, ~16 MHz+ in-browser).
//
// On the web the pure-Dart `avr8_dart` emulator (compiled by dart2js) tops out
// around ~10 MHz — too slow to run the 16 MHz ATmega328P in real time, which
// makes time-based sketches (clap rhythm, delays) lag. avr8js runs the same
// core in optimized JS at real-time speed, so the web build delegates the AVR
// emulation here. This mirrors `lib/features/simulation/core/avr_interop.dart`.
import {
  CPU,
  avrInstruction,
  AVRIOPort,
  portBConfig,
  portCConfig,
  portDConfig,
  PinState,
  AVRTimer,
  timer0Config,
  timer1Config,
  timer2Config,
  AVRADC,
  adcConfig,
  AVRUSART,
  usart0Config,
  AVRTWI,
  twiConfig,
} from 'https://unpkg.com/avr8js@0.21.0/dist/esm/index.js';

let cpu = null;
let portB = null, portC = null, portD = null;
let adc = null, usart = null, twi = null;
// Timers must be kept referenced so they keep ticking.
// eslint-disable-next-line no-unused-vars
let timer0 = null, timer1 = null, timer2 = null;

let buzzerPin = null;
let onSerialPrint = null;     // (String) => void  (Dart callback)
let onBuzzerFrequency = null; // (double|null) => void  (Dart callback)

// Servo signal pins (set from the traced netlist, like buzzerPin). HIGH-pulse
// widths are measured only on these pins.
let servoPins = [];
const servoRise = new Float64Array(14).fill(-1);
const servoPulseUs = new Float64Array(14);

const rxQueue = [];
let txLine = '';

// --- PWM duty sampling (pins 0..13) -----------------------------------------
const DUTY_PINS = 14;
const DUTY_SAMPLE_MASK = 63; // sample every 64 cycles
const dutyHigh = new Int32Array(DUTY_PINS);
let dutyTotal = 0;

// --- Frequency detector (port of FrequencyDetector) -------------------------
const CLOCK = 16000000;
const fd = {
  lastToggleCycle: 0, prevDelta: 0, stableDelta: 0, stableCount: 0,
  timeoutCycles: 160000, playing: false,
  reset() {
    this.lastToggleCycle = 0; this.prevDelta = 0; this.stableDelta = 0;
    this.stableCount = 0; this.timeoutCycles = 160000; this.playing = false;
  },
  onToggle(cycle) {
    if (this.lastToggleCycle !== 0) {
      const d = cycle - this.lastToggleCycle;
      if (d > 400 && d < 400000) {
        if (this.stableDelta === 0 || Math.abs(this.stableDelta - d) > 2000) {
          this.stableDelta = d; this.stableCount = 1;
        } else {
          this.stableDelta = ((this.stableDelta * 3) + d + 2) >> 2;
          this.stableCount++;
        }
        this.timeoutCycles = Math.max(this.stableDelta * 4, 4000);
        if (this.stableCount >= 4) {
          if (!this.playing || Math.abs(this.prevDelta - this.stableDelta) > 2000) {
            this.prevDelta = this.stableDelta;
            let freq = CLOCK / (2.0 * this.stableDelta);
            if (Math.abs(freq - 2000.0) < 20.0) freq = 2000.0;
            this.playing = true;
            if (onBuzzerFrequency) onBuzzerFrequency(freq);
          }
        }
      }
    }
    this.lastToggleCycle = cycle;
  },
  checkTimeout(cycles) {
    if (this.playing && this.lastToggleCycle !== 0 &&
        (cycles - this.lastToggleCycle) > this.timeoutCycles) {
      this.reset();
      return true;
    }
    return false;
  },
};

function parseHex(hexString) {
  const flash = new Uint16Array(0x4000); // 32KB flash = 16K x 16-bit words
  const lines = hexString.split('\n');
  for (let line of lines) {
    line = line.trim();
    if (line.length === 0 || line[0] !== ':') continue;
    if (line.substr(7, 2) !== '00') continue; // data records only
    const length = parseInt(line.substr(1, 2), 16);
    const addr = parseInt(line.substr(3, 4), 16);
    for (let i = 0; i < length; i += 2) {
      const lsb = parseInt(line.substr(9 + i * 2, 2), 16);
      let msb = 0;
      if (i + 1 < length) msb = parseInt(line.substr(11 + i * 2, 2), 16);
      flash[(addr + i) >> 1] = (msb << 8) | lsb;
    }
  }
  return flash;
}

function pinState(pin) {
  if (pin >= 0 && pin <= 7) return portD.pinState(pin) === PinState.High;
  if (pin >= 8 && pin <= 13) return portB.pinState(pin - 8) === PinState.High;
  if (pin >= 14 && pin <= 19) return portC.pinState(pin - 14) === PinState.High;
  return false;
}

function handlePortChange(pinOffset, value, oldValue) {
  const changed = value ^ oldValue;
  if (changed === 0) return;

  if (buzzerPin !== null && buzzerPin >= pinOffset && buzzerPin < pinOffset + 8 &&
      (changed & (1 << (buzzerPin - pinOffset))) !== 0) {
    fd.onToggle(cpu.cycles);
  }

  for (const sPin of servoPins) {
    if (sPin < pinOffset || sPin >= pinOffset + 8) continue;
    const bit = 1 << (sPin - pinOffset);
    if ((changed & bit) === 0) continue;
    if ((value & bit) !== 0) {
      servoRise[sPin] = cpu.cycles;
    } else if (servoRise[sPin] >= 0) {
      const us = (cpu.cycles - servoRise[sPin]) / 16.0; // 16 MHz clock
      // Servo control pulses are ~0.4-3 ms; ignore anything else on the pin.
      if (us >= 400 && us <= 3000) servoPulseUs[sPin] = us;
    }
  }
}

// --- I2C bus recording (port of I2cRecorder) --------------------------------
//
// Bus traffic is queued rather than sampled: the frame loop runs the CPU for a
// whole frame before any part looks, and a screen refresh is a thousand bytes.
// See `packages/pinbench_sim/lib/core/i2c_recorder.dart` for the full reasoning —
// this is the same model, kept in JS so the per-byte callbacks never cross into
// Dart.
const MAX_I2C_BYTES_PER_ADDRESS = 64 * 1024;
const MAX_I2C_ADDRESSES = 16;
const i2c = {
  listening: new Set(),
  pending: new Map(),   // address -> array of transactions (arrays of bytes)
  buffered: new Map(),  // address -> queued byte count
  current: null,
  currentAddress: null,

  reset() {
    this.listening.clear();
    this.pending.clear();
    this.buffered.clear();
    this.current = null;
    this.currentAddress = null;
  },

  begin(address, write) {
    this.end();
    if (!write) return;
    if (!this.pending.has(address) && this.pending.size >= MAX_I2C_ADDRESSES) return;
    this.currentAddress = address;
    this.current = [];
  },

  write(value) {
    if (this.current) this.current.push(value & 0xff);
  },

  end() {
    const address = this.currentAddress;
    const bytes = this.current;
    this.currentAddress = null;
    this.current = null;
    if (address === null || !bytes || !bytes.length) return;

    if (!this.pending.has(address)) this.pending.set(address, []);
    const queue = this.pending.get(address);
    queue.push(bytes);
    let buffered = (this.buffered.get(address) || 0) + bytes.length;
    while (buffered > MAX_I2C_BYTES_PER_ADDRESS && queue.length > 1) {
      buffered -= queue.shift().length;
    }
    this.buffered.set(address, buffered);
  },

  // Flattened as [length, ...bytes] per transaction, so the whole frame's
  // traffic crosses into Dart as one typed array rather than a thousand
  // boxed numbers.
  drain(address) {
    const queue = this.pending.get(address);
    this.pending.delete(address);
    this.buffered.delete(address);
    if (!queue || !queue.length) return new Int32Array(0);
    let total = 0;
    for (const transaction of queue) total += transaction.length + 1;
    const flat = new Int32Array(total);
    let at = 0;
    for (const transaction of queue) {
      flat[at++] = transaction.length;
      flat.set(transaction, at);
      at += transaction.length;
    }
    return flat;
  },
};

function attachTwi() {
  twi = new AVRTWI(cpu, twiConfig, CLOCK);
  twi.eventHandler = {
    start() { twi.completeStart(); },
    stop() { i2c.end(); twi.completeStop(); },
    connectToSlave(addr, write) {
      i2c.begin(addr, write);
      // The ACK is the only answer that reaches the sketch, so a device that
      // is not on the canvas must not answer for one that is.
      twi.completeConnect(i2c.listening.has(addr));
    },
    writeByte(value) { i2c.write(value); twi.completeWrite(true); },
    // Nothing on the canvas talks back yet; 0xff is what an idle bus reads.
    readByte() { twi.completeRead(0xff); },
  };
}

window.AVR8 = {
  listenI2c(address) { i2c.listening.add(address); },
  drainI2c(address) { return i2c.drain(address); },

  setSerialPrint(cb) { onSerialPrint = cb; },
  setBuzzerFrequencyCallback(cb) { onBuzzerFrequency = cb; },
  setBuzzerPin(pin) { buzzerPin = (pin === undefined || pin === null) ? null : pin; },
  setServoPins(pins) { servoPins = pins || []; },
  getServoPulseUs(pin) {
    return (pin >= 0 && pin < servoPulseUs.length) ? servoPulseUs[pin] : 0;
  },

  loadHex(hexString) {
    rxQueue.length = 0;
    txLine = '';
    servoRise.fill(-1);
    servoPulseUs.fill(0);
    const program = parseHex(hexString);
    cpu = new CPU(program);
    timer0 = new AVRTimer(cpu, timer0Config);
    timer1 = new AVRTimer(cpu, timer1Config);
    timer2 = new AVRTimer(cpu, timer2Config);
    usart = new AVRUSART(cpu, usart0Config, CLOCK);
    usart.onByteTransmit = (value) => {
      const ch = String.fromCharCode(value);
      if (ch === '\n') {
        if (onSerialPrint) onSerialPrint(txLine);
        txLine = '';
      } else if (ch !== '\r') {
        txLine += ch;
      }
    };
    portB = new AVRIOPort(cpu, portBConfig);
    portB.addListener((v, o) => handlePortChange(8, v, o));
    portC = new AVRIOPort(cpu, portCConfig);
    portC.addListener((v, o) => handlePortChange(14, v, o));
    portD = new AVRIOPort(cpu, portDConfig);
    portD.addListener((v, o) => handlePortChange(0, v, o));
    adc = new AVRADC(cpu, adcConfig);
    // The bus is rebuilt with the program: claims belong to the parts of the
    // run that just ended, and its traffic to the sketch that just stopped.
    i2c.reset();
    attachTwi();
    fd.reset();
  },

  queueSerialInput(text) {
    for (let i = 0; i < text.length; i++) rxQueue.push(text.charCodeAt(i) & 0xff);
  },

  tick(cycles) {
    if (!cpu) return;
    dutyTotal = 0;
    dutyHigh.fill(0);
    const limit = cpu.cycles + cycles;
    let i = 0;
    while (cpu.cycles < limit) {
      avrInstruction(cpu);
      cpu.tick();

      if ((i & DUTY_SAMPLE_MASK) === 0) {
        dutyTotal++;
        for (let p = 0; p < DUTY_PINS; p++) if (pinState(p)) dutyHigh[p]++;
      }

      // Feed queued serial input as the receiver frees up.
      if (rxQueue.length && usart.writeByte && usart.writeByte(rxQueue[0])) {
        rxQueue.shift();
      }

      if (fd.checkTimeout(cpu.cycles)) {
        if (onBuzzerFrequency) onBuzzerFrequency(null);
      }
      i++;
    }
  },

  getPinState(pin) { return cpu ? pinState(pin) : false; },

  getPinDuty(pin) {
    if (!cpu) return 0;
    if (pin < 0 || pin >= DUTY_PINS) return pinState(pin) ? 1.0 : 0.0;
    if (dutyTotal === 0) return pinState(pin) ? 1.0 : 0.0;
    return dutyHigh[pin] / dutyTotal;
  },

  isPinOutput(pin) {
    if (!cpu) return false;
    if (pin >= 0 && pin <= 7) return (cpu.data[portDConfig.DDR] & (1 << pin)) !== 0;
    if (pin >= 8 && pin <= 13) return (cpu.data[portBConfig.DDR] & (1 << (pin - 8))) !== 0;
    if (pin >= 14 && pin <= 19) return (cpu.data[portCConfig.DDR] & (1 << (pin - 14))) !== 0;
    return false;
  },

  setDigitalPin(pin, isHigh) {
    if (!cpu) return;
    if (pin >= 0 && pin <= 7) portD.setPin(pin, isHigh);
    else if (pin >= 8 && pin <= 13) portB.setPin(pin - 8, isHigh);
    else if (pin >= 14 && pin <= 19) portC.setPin(pin - 14, isHigh);
  },

  setAnalogVoltage(channel, voltage) {
    if (adc && channel >= 0 && channel < adc.channelValues.length) {
      adc.channelValues[channel] = voltage;
    }
  },

  getPortBValue() { return cpu ? cpu.data[0x25] : 0; },
  getCycles() { return cpu ? cpu.cycles : 0; },
  getPin13State() { return portB ? portB.pinState(5) === PinState.High : false; },
};

console.log('AVR8 (avr8js) bridge loaded.');
