import 'package:flutter/foundation.dart';

import 'part_model.dart';

/// What the rest of the app needs to know about a microcontroller board: how
/// its sketch is built, how fast it runs, what voltage its pins drive, and
/// which of its ports are which.
///
/// Data, not behaviour. The emulator that runs the sketch lives in the
/// simulation package and is picked by [partName]; this is everything about a
/// board that the parts, the validator and the compiler can know without one.
///
/// A board's ports are named the way its sketch numbers its pins wherever it
/// can be: the Uno's digital header is `'0'`–`'13'`, the Pico's GPIOs `'0'`–
/// `'28'`, because `digitalWrite(13, …)` and `digitalWrite(15, …)` mean those
/// ports. Everything else — `'A0'`, `'5V'`, `'GND_1'` — is named for what it
/// is, and a ground is any port whose id starts with `GND`.
@immutable
class const BoardProfile({
  /// The [PartModel.name] of the board this describes.
  required final String partName,

  /// What a message calls the board: "Arduino pin 13", "Pico pin GP15".
  required final String shortName,

  /// What its GPIOs are called before their number — `GP` on a Pico.
  final String gpioPrefix = '',

  /// The board `arduino-cli` builds a sketch for.
  required final String fqbn,

  /// The Boards Manager index the board's core comes from, for a core
  /// `arduino-cli` does not know out of the box; null for Arduino's own.
  final String? coreIndexUrl,

  /// The CPU clock, which turns simulated microseconds into cycles.
  required final int clockHz,

  /// The voltage an output pin drives when it is high.
  required final double logicHighVolts,

  /// The output resistance of a pin's driver, in the analog solve.
  ///
  /// What keeps an LED wired straight to a pin from drawing an infinite
  /// current, and makes it draw roughly what it would on a desk.
  required final double pinSourceOhms,

  /// The pins a sketch can use as digital I/O, each the port named by its
  /// number.
  required final List<int> digitalPins,

  /// The board's supply pins and the voltage each holds, on USB power.
  ///
  /// Stiff rails, not pins: the analog solve gives each one wired to anything
  /// a source of its own, so a divider, potentiometer or sensor powered from
  /// the board reads what it would on a desk.
  required final Map<String, double> supplies,

  /// The ADC's inputs, as board ports, in channel order: entry 0 is channel 0.
  required final List<String> analogInputPorts,

  /// The board ports wired to the hardware I²C peripheral `Wire` drives.
  required final Set<String> i2cSdaPorts,
  required final Set<String> i2cSclPorts,

  /// Ports named for something other than their pin number that a sketch can
  /// still address by number — the Uno's `A0` is pin 14.
  final Map<String, int> numberedAliases = const {},

  /// The pin the on-board LED hangs off (`LED_BUILTIN`), or null.
  final int? builtinLedPin,

  /// Where the toolchain's raw `.bin` image loads, for a board whose build
  /// writes one instead of Intel HEX — the Pico's, at the start of its XIP
  /// flash. Null for a board that gets a `.hex` straight from `arduino-cli`.
  final int? binLoadAddress,

  /// Header pins that neither drive nor supply anything, so tying one to
  /// ground is not a short: a reference, an enable, a reset.
  final Set<String> passivePorts = const {},
}) {
  static const arduinoUno = BoardProfile(
    partName: PartNames.arduinoUno,
    shortName: 'Arduino',
    fqbn: 'arduino:avr:uno',
    clockHz: 16000000,
    logicHighVolts: 5.0,
    // Typical for an ATmega328P output.
    pinSourceOhms: 40,
    digitalPins: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    supplies: {'5V': 5.0, '3.3V': 3.3},
    analogInputPorts: ['A0', 'A1', 'A2', 'A3', 'A4', 'A5'],
    // The ATmega328P's TWI hardware is wired to A4/A5 and nothing else; the
    // R3 header's separate SDA/SCL pins are the same two pads brought out
    // twice.
    i2cSdaPorts: {'A4', 'SDA'},
    i2cSclPorts: {'A5', 'SCL'},
    numberedAliases: {'A0': 14, 'A1': 15, 'A2': 16, 'A3': 17, 'A4': 18, 'A5': 19},
    builtinLedPin: 13,
    passivePorts: {'NC', 'AREF', 'IOREF', 'RESET'},
  );

  /// A Raspberry Pi Pico W, built with the arduino-pico core.
  ///
  /// Built as a plain Pico (`rpipico`), not a `rpipicow`. On the W the
  /// on-board LED hangs off the CYW43439 radio rather than a GPIO, and the
  /// radio is not emulated: a `rpipicow` sketch that blinks `LED_BUILTIN`
  /// spends every call waiting out the radio driver's timeouts, so the first
  /// sketch anyone writes would crawl. Built as a Pico, `LED_BUILTIN` is GP25
  /// — the pin the W's radio sits on in its place — and the LED drawn on the
  /// board follows it. The cost is that `WiFi.h` does not build, which is the
  /// honest answer for a board whose radio is not simulated.
  static const picoW = BoardProfile(
    partName: PartNames.picoW,
    shortName: 'Pico',
    gpioPrefix: 'GP',
    fqbn: 'rp2040:rp2040:rpipico',
    coreIndexUrl: 'https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json',
    clockHz: 125000000,
    logicHighVolts: 3.3,
    // The RP2040 guarantees at most a 0.68 V drop at its default 4 mA drive
    // (170 Ω); a typical part does better.
    pinSourceOhms: 100,
    digitalPins: [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
      16, 17, 18, 19, 20, 21, 22, 26, 27, 28,
    ],
    // VBUS is the USB 5 V; VSYS is VBUS after the board's Schottky diode,
    // about 0.3 V down; 3V3 OUT is the buck regulator's output.
    supplies: {'5V': 5.0, 'VSYS': 4.7, '3.3V': 3.3},
    // ADC0–2 are GP26–28; arduino-pico calls them A0–A2 and numbers them 26–28.
    analogInputPorts: ['26', '27', '28'],
    // `Wire`'s default pins in arduino-pico: I2C0 on GP4/GP5.
    i2cSdaPorts: {'4'},
    i2cSclPorts: {'5'},
    builtinLedPin: 25,
    binLoadAddress: 0x10000000,
    // RUN low holds the chip in reset (a reset button does exactly that), and
    // 3V3_EN low switches the regulator off; both are meant to be grounded.
    passivePorts: {'RUN', '3V3_EN', 'ADC_VREF'},
  );

  static const all = [arduinoUno, picoW];

  /// The profile of the board [part] is, or null for anything that is not a
  /// board.
  static BoardProfile? of(PartModel part) => forName(part.name);

  static BoardProfile? forName(String partName) {
    for (final profile in all) {
      if (profile.partName == partName) return profile;
    }
    return null;
  }

  /// The pin number a sketch uses for board port [portId] — `'13'` → 13, and
  /// on the Uno `'A0'` → 14 — or null for a port that is not a pin.
  int? pinNumberFor(String portId) {
    final number = int.tryParse(portId);
    if (number != null) return digitalPins.contains(number) ? number : null;
    return numberedAliases[portId];
  }

  /// Board port [portId] as a message names it: `Arduino pin 13`,
  /// `Pico pin GP15`, `Pico pin 3.3V`.
  String describePort(String portId) =>
      '$shortName pin ${int.tryParse(portId) == null ? portId : '$gpioPrefix$portId'}';

  /// The I²C line board port [portId] carries, if any.
  I2cLine? i2cLineAt(String portId) {
    if (i2cSdaPorts.contains(portId)) return I2cLine.sda;
    if (i2cSclPorts.contains(portId)) return I2cLine.scl;
    return null;
  }
}

/// The two wires of an I²C bus.
enum I2cLine { sda, scl }
