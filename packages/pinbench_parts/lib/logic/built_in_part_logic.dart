import '../models/part_model.dart';

import 'i2c_sensors.dart';
import 'part_logic.dart';
import 'ssd1306.dart';

/// The `LOGIC` implementations shipped with the app.
///
/// Registration is lazy and idempotent rather than done at startup, because
/// the simulation runs in its own isolate and statics do not cross isolates —
/// anything registered in `main()` would simply not exist where the frame loop
/// runs. Calling [ensureRegistered] from the frame path costs one bool check
/// and works wherever it ends up.
abstract final class BuiltInPartLogic {
  /// Minimum current (amps) above which an LED reads as lit.
  ///
  /// Moved here from the app's `SimConstants` with the logic that is its only
  /// reader. It is a simulation threshold rather than a fact about LEDs — real
  /// ones glow faintly well below a milliamp — but it belongs beside the rule
  /// that applies it, not in a constants file two layers away.
  static const ledOnAmps = 0.001;

  /// A 5 mm LED's typical rated forward current, and the yardstick for both
  /// how bright one renders and when it reads as over-driven.
  ///
  /// A single number for every LED is a simplification — real ratings vary by
  /// colour and package — but it is the value every beginner tutorial designs
  /// its series resistor around, so it is the one a wrong resistor should be
  /// judged against.
  static const ledRatedAmps = 0.020;

  static void ensureRegistered() => PartLogicRegistry.ensureBuiltIns(() {
    PartLogicRegistry.register('one_shot', oneShot);
    PartLogicRegistry.register('servo', servo);
    PartLogicRegistry.register('led', led);
    PartLogicRegistry.register('rgb_led', rgbLed);
    PartLogicRegistry.register('buzzer', buzzer);
    PartLogicRegistry.register('ssd1306', ssd1306);
    PartLogicRegistry.register('bh1750', I2cSensors.bh1750);
    PartLogicRegistry.register('mpu6050', I2cSensors.mpu6050);
    PartLogicRegistry.register('ds1307', I2cSensors.ds1307);
    PartLogicRegistry.register('aht20', I2cSensors.aht20);
  });

  /// The I²C address an SSD1306 module answers on when its property says
  /// nothing. Both addresses exist in the wild — the jumper on the back of the
  /// board picks one — but every tutorial and every `Adafruit_SSD1306` example
  /// uses this one.
  static const ssd1306DefaultAddress = 0x3C;

  /// An SSD1306 OLED display: a panel driven entirely by what the sketch says
  /// to it over I²C.
  ///
  /// The first part here whose behaviour is a *protocol* rather than a
  /// quantity. A servo reads one number off one pin; a display has to follow a
  /// conversation, and a conversation cannot be sampled — bytes missed are
  /// bytes gone. So this drains the bus queue every frame, whether or not
  /// anything is drawn, and keeps its whole decoded state in the component's
  /// own map (see [Ssd1306Controller], which owns the format).
  ///
  /// Nothing here knows how a pixel looks. The controller ends up holding the
  /// same 1 KB of graphics RAM the real chip holds, and the painter reads it.
  static void ssd1306(PartLogicContext context) {
    if (!_isOnTheBus(context)) return;

    final address = _i2cAddress(context);
    final transactions = context.i2c.drain(address);
    if (transactions.isEmpty) return;

    // Reusing the packed string when nothing changed is what keeps an idle
    // display free: the frame updater compares state maps, and an unchanged
    // string is equal, so no canvas rebuild is queued.
    final controller = Ssd1306Controller.unpack(context.state[ComponentProps.oledFrame])
      ..consume(transactions);
    context.state[ComponentProps.oledFrame] = controller.pack();
  }

  /// Whether this display's data and clock lines actually reach the board's
  /// I²C pins.
  ///
  /// Worth the check because the bus is global: the emulator records what the
  /// sketch transmits, not what any particular wire carries, so without this a
  /// display sitting unwired on the canvas would happily show the sketch's
  /// output. On a desk it would stay dark, and staying dark is the lesson —
  /// swapped SDA and SCL is the single commonest way a first display fails.
  ///
  /// `A4` and `A5` specifically, because the ATmega328P's I²C hardware is
  /// wired to those two pads and no others. A sketch bit-banging the protocol
  /// on different pins is not emulated at all, here or in the peripheral. The
  /// R3 header's separate `SDA`/`SCL` pins count too: they are the same two
  /// pads brought out twice, so a display wired to them is on the same bus.
  static bool _isOnTheBus(PartLogicContext context) =>
      I2cWiring.isOnTheBus(context, sda: 'SDA', scl: 'SCL');

  /// The address this display listens on, read from its `I2C Address`
  /// property. Accepts the hex spelling people copy out of a sketch (`0x3C`)
  /// as well as a plain number, and falls back to
  /// [ssd1306DefaultAddress] for anything it cannot read — a typo should cost
  /// a wrong address at worst, not a part that silently never runs.
  static int _i2cAddress(PartLogicContext context) =>
      I2cWiring.parseAddress(context.properties[ComponentProps.i2cAddress]) ??
      ssd1306DefaultAddress;

  /// A piezo buzzer: sounding, and at what pitch, from the frequency the
  /// emulator detects on its driving pin.
  ///
  /// Audio output itself stays with the engine — a speaker is a host device,
  /// like the microphone — so this owns only what the part *is*: on or off,
  /// and at what frequency. Asking for the frequency is also what points the
  /// detector at the right pin; without that it triggers on every toggling
  /// pin, including serial TX, which sounds like garbage rather than a tone.
  static void buzzer(PartLogicContext context) {
    final pin = context.pins.connectedTo('plus');
    if (pin == null) return;

    final hz = context.pins.frequencyOn(pin);
    context.state[ComponentProps.isOn] = hz != null;
    // Only overwrite the pitch while there is one, so a stopped buzzer keeps
    // the last note it played rather than reading as 0 Hz.
    if (hz != null) context.state[ComponentProps.frequency] = hz;
  }

  /// An LED: lit when current flows, brightness from the driving pin's PWM
  /// duty.
  ///
  /// The second peripheral out of the engine, and a different shape from the
  /// servo — it needs a solved analog result *and* an emulated pin, which is
  /// what the two capability APIs exist to provide.
  ///
  /// An LED wired to the 5 V rail rather than to a pin is simply full or off;
  /// only a pin-driven one can be dimmed.
  static void led(PartLogicContext context) {
    final amps = context.spice.current().abs();
    final isOn = amps > ledOnAmps;

    // Either leg may be the one wired to the board — a sketch can sink through
    // the cathode just as well as source through the anode.
    final pin = context.pins.connectedTo('anode') ?? context.pins.connectedTo('cathode');
    final duty = !isOn ? 0.0 : (pin != null ? context.pins.duty(pin) : 1.0);

    // Brightness tracks *average* current: how hard the LED is driven while
    // conducting, times the fraction of the time it conducts.
    //
    // Duty alone used to decide this, which meant the series resistor changed
    // nothing on screen — swapping 220 Ω for 100 Ω lit the LED identically, so
    // the one mistake this simulator exists to catch was invisible. The engine
    // drives SPICE to the full logic level whenever duty is non-zero, so
    // `amps` is a stable peak rather than a PWM sample, and multiplying the
    // two is safe.
    final averageAmps = amps * duty;
    // Quantized so tiny sampling jitter does not spam canvas updates.
    final brightness = ((averageAmps / ledRatedAmps).clamp(0.0, 1.0) * 20).round() / 20;

    context.state[ComponentProps.isOn] = isOn;
    context.state[ComponentProps.brightness] = brightness;
    // Judged on the average too, so dimming an LED with PWM does not read as
    // over-driving it — only actually running it too hard does.
    context.state[ComponentProps.hasError] = averageAmps > ledRatedAmps;
  }

  /// A common-cathode RGB LED: each colour lit and dimmed from the current
  /// through its own die, judged exactly as [led] judges one.
  ///
  /// Writes `red`, `green` and `blue` as 0–1 brightness, which the part's
  /// painter mixes into the colour of the lens, and flags an over-driven die.
  static void rgbLed(PartLogicContext context) {
    var overdriven = false;
    for (final colour in const ['red', 'green', 'blue']) {
      final amps = context.spice.pinCurrent(colour).abs();
      // Either end may be the pin a sketch drives: each colour's anode, or the
      // shared cathode when it sinks through all three.
      final pin = context.pins.connectedTo(colour) ?? context.pins.connectedTo('cathode');
      final duty = amps <= ledOnAmps ? 0.0 : (pin != null ? context.pins.duty(pin) : 1.0);
      final averageAmps = amps * duty;
      context.state[colour] = ((averageAmps / ledRatedAmps).clamp(0.0, 1.0) * 20).round() / 20;
      overdriven = overdriven || averageAmps > ledRatedAmps;
    }
    context.state[ComponentProps.hasError] = overdriven;
  }

  /// A hobby servo: horn angle from the HIGH-pulse width on its signal line.
  ///
  /// Moved out of the simulation engine, which used to carry a typed bucket of
  /// servos, a map of their signal pins, and a dedicated frame updater — a
  /// whole seam per part type. All this needs is "which pin is my signal wired
  /// to", which the part can now ask itself.
  ///
  /// Uses the Arduino Servo library's default mapping (544 µs = 0°,
  /// 2400 µs = 180°), clamped, so both library-driven and hand-pulsed sketches
  /// land in range.
  static void servo(PartLogicContext context) {
    const minPulseUs = 544.0;
    const maxPulseUs = 2400.0;

    final pin = context.pins.connectedTo('signal');
    if (pin == null) return;

    final us = context.pins.pulseUs(pin);
    // No pulse seen yet — hold the current pose rather than snapping to 0°.
    // This is also what the first frame after a fresh measurement request
    // looks like, so it must not be treated as "commanded to zero".
    if (us <= 0) return;

    final raw = (us - minPulseUs) / (maxPulseUs - minPulseUs) * 180.0;
    // Quantized to half degrees so cycle-sampling jitter does not spam canvas
    // updates; the frame updater's change detection does the rest.
    context.state[ComponentProps.servoAngle] = (raw.clamp(0.0, 180.0) * 2).round() / 2;
  }

  /// A retriggerable one-shot: while its trigger is asserted the output is
  /// high, and it *stays* high for `holdSeconds` after the trigger clears.
  ///
  /// This is the shape of every motion/vibration/sound module that latches —
  /// and it is exactly what `BEHAVIOR` cannot express, because it needs a
  /// clock and a memory of when something stopped. Everything else about such
  /// a part (artwork, pins, the properties above) still lives in the `.pdl`.
  ///
  /// Reads properties `triggered` and `holdSeconds`; owns state `active` and
  /// `holdUntilMs`; drives `physics.voltage` and a `visual.led` binding.
  static void oneShot(PartLogicContext context) {
    final holdMs = context.number('holdSeconds', 2) * 1000;
    final nowMs = context.elapsed.inMilliseconds.toDouble();

    final holdUntilMs = switch (context.state['holdUntilMs']) {
      final num n => n.toDouble(),
      _ => 0.0,
    };

    final bool active;
    if (context.flag('triggered')) {
      // Retriggerable: every frame the trigger is held pushes the deadline
      // out, so a continuous trigger never lets the output drop.
      context.state['holdUntilMs'] = nowMs + holdMs;
      active = true;
    } else {
      active = nowMs < holdUntilMs;
    }

    context.state['active'] = active;
    // Left as the remaining hold rather than the absolute deadline would be
    // friendlier to read, but the deadline is what survives a frame gap: a
    // countdown would need the frame delta, which a logic is not given.
    context.state['holdUntilMs'] = active ? context.state['holdUntilMs'] ?? holdUntilMs : 0.0;

    final high = context.number('outputVoltage', 5);
    context.physics['voltage'] = active ? high : 0.0;
  }
}
