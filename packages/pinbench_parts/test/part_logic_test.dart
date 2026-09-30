import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:flutter/services.dart';
import 'package:pinbench_parts/logic/part_logic.dart';
import 'package:pinbench_parts/logic/built_in_part_logic.dart';
import 'package:pinbench_parts/logic/ssd1306.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// `LOGIC <name>` — the Dart escape hatch for parts a rule cannot express.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PartLogicContext contextFor(
    PartDefinition definition, {
    Map<String, Object?> state = const {},
    Map<String, Object?> properties = const {},
    Duration elapsed = Duration.zero,
    Map<String, double> pins = const {},
    Map<String, double>? physics,
  }) => PartLogicContext(
    definition: definition,
    state: {...definition.initialState(), ...state},
    properties: {...definition.defaultProperties(), ...properties},
    physics: physics ?? {},
    elapsed: elapsed,
    analog: (id) => pins[id] ?? 0,
    pins: const _FakePins(),
    spice: const _FakeSpice(),
  );

  group('the registry', () {
    setUp(PartLogicRegistry.reset);
    tearDown(() {
      PartLogicRegistry.reset();
      BuiltInPartLogic.ensureRegistered();
    });

    test('an unknown name simply finds nothing', () {
      // Not fatal by design: a part that names a missing logic still draws and
      // still runs whatever BEHAVIOR it declared. Losing the Dart half quietly
      // is bad; losing the whole part is worse.
      expect(PartLogicRegistry.find('nope'), isNull);
    });

    test('a registration can be found and replaced', () {
      var calls = 0;
      PartLogicRegistry.register('probe', (_) => calls++);
      PartLogicRegistry.find('probe')!(contextFor(_stub));
      expect(calls, 1);

      PartLogicRegistry.register('probe', (_) => calls += 10);
      PartLogicRegistry.find('probe')!(contextFor(_stub));
      expect(calls, 11, reason: 'the later registration should win');
    });

    test('the built-ins register lazily, so they exist in the sim isolate', () {
      // Statics do not cross isolates, so anything registered in main() would
      // not exist where the frame loop actually runs.
      expect(PartLogicRegistry.find('one_shot'), isNull);
      BuiltInPartLogic.ensureRegistered();
      expect(PartLogicRegistry.find('one_shot'), isNotNull);
    });
  });

  group('the one-shot, which is why LOGIC exists', () {
    late PartDefinition pir;

    setUpAll(() async {
      const dir = 'packages/pinbench_parts/assets/parts/pir_sensor';
      final result = PdlParser.parse(
        await rootBundle.loadString('$dir/pir_sensor.pdl'),
        assetDirectory: dir,
      );
      expect(result.diagnostics, isEmpty, reason: result.diagnostics.join('\n'));
      pir = result.definition!;
    });

    /// Runs one frame and returns the mutated context.
    PartLogicContext frame({
      required bool triggered,
      required Duration at,
      Map<String, Object?> state = const {},
    }) {
      final context = contextFor(
        pir,
        state: state,
        properties: {'triggered': triggered, 'holdSeconds': 2, 'outputVoltage': 3.3},
        elapsed: at,
      );
      BuiltInPartLogic.oneShot(context);
      return context;
    }

    test('the part declares its logic by name', () {
      expect(pir.logic, 'one_shot');
      expect(pir.behavior, isEmpty, reason: 'this part is entirely Dart-driven');
    });

    test('idle output is low', () {
      final c = frame(triggered: false, at: Duration.zero);
      expect(c.state['active'], isFalse);
      expect(c.physics['voltage'], 0);
    });

    test('a trigger drives the output to the configured level', () {
      final c = frame(triggered: true, at: Duration.zero);
      expect(c.state['active'], isTrue);
      expect(c.physics['voltage'], 3.3);
    });

    test('the output holds after the trigger clears, then falls', () {
      // The whole point: BEHAVIOR has no clock and no memory of when something
      // stopped, so this shape is not expressible as a rule.
      var state = frame(triggered: true, at: Duration.zero).state;

      final duringHold = frame(
        triggered: false,
        at: const Duration(milliseconds: 1500),
        state: state,
      );
      expect(duringHold.state['active'], isTrue, reason: 'still within the 2s hold');
      expect(duringHold.physics['voltage'], 3.3);
      state = duringHold.state;

      final afterHold = frame(
        triggered: false,
        at: const Duration(milliseconds: 2500),
        state: state,
      );
      expect(afterHold.state['active'], isFalse, reason: 'the 2s hold has expired');
      expect(afterHold.physics['voltage'], 0);
    });

    test('it is retriggerable — a held trigger keeps pushing the deadline out', () {
      var state = frame(triggered: true, at: Duration.zero).state;
      for (final ms in [1000, 2000, 3000, 10000]) {
        state = frame(
          triggered: true,
          at: Duration(milliseconds: ms),
          state: state,
        ).state;
        expect(state['active'], isTrue, reason: 'still triggered at ${ms}ms');
      }
      // And only starts counting from the last trigger.
      final justAfter = frame(
        triggered: false,
        at: const Duration(milliseconds: 11000),
        state: state,
      );
      expect(justAfter.state['active'], isTrue, reason: '1s after a 10s trigger, hold is 2s');
    });

    test('a zero hold falls on the very next frame', () {
      final context = contextFor(pir, properties: {'triggered': true, 'holdSeconds': 0});
      BuiltInPartLogic.oneShot(context);
      expect(context.state['active'], isTrue, reason: 'still triggered');

      final next = contextFor(
        pir,
        state: context.state,
        properties: {'triggered': false, 'holdSeconds': 0},
        elapsed: const Duration(milliseconds: 1),
      );
      BuiltInPartLogic.oneShot(next);
      expect(next.state['active'], isFalse);
    });
  });

  group('the catalog names only logics that exist', () {
    setUp(BuiltInPartLogic.ensureRegistered);

    test('every built-in part that declares a logic has one registered', () {
      // The claim `logic: 'servo'` in the catalog is a *string* resolved at
      // runtime. Before the built-ins lived in this package nothing could
      // check it, and an unregistered name is deliberately non-fatal — so a
      // typo produced a part that drew perfectly and silently never behaved.
      final declared = {
        for (final part in standardParts)
          if (part.logic != null) part.name: part.logic!,
      };
      expect(declared, isNotEmpty, reason: 'the catalog should declare some logics');

      for (final entry in declared.entries) {
        expect(
          PartLogicRegistry.find(entry.value),
          isNotNull,
          reason: '"${entry.key}" declares logic "${entry.value}", which nothing registers',
        );
      }
    });

    test('every .pdl LOGIC line resolves too', () async {
      await PartRegistry.initializeAsync();
      for (final definition in PartRegistry.getAllParts()) {
        final name = definition.logic;
        if (name == null) continue;
        expect(
          PartLogicRegistry.find(name),
          isNotNull,
          reason: '${definition.id}.pdl declares LOGIC "$name", which nothing registers',
        );
      }
    });

    test('resolution finds a logic for a hand-built model, not just a clone', () {
      // `PartRegistry.logicFor` falls back to the catalog entry for the part
      // *name*, which is what keeps a model built by hand — a test fixture, or
      // `PartModel.fromJson`'s unknown-part fallback — behaving.
      final handBuilt = PartModel(name: PartNames.led, size: const Size(40, 40));
      expect(handBuilt.logic, isNull, reason: 'the instance carries nothing');
      expect(PartRegistry.logicFor(handBuilt), 'led', reason: 'the type still does');
    });
  });

  group('the LDR, moved out of its .pdl', () {
    double resistance(Map<String, Object?> properties) {
      final physics = <String, double>{};
      BuiltInPartLogic.ldr(
        PartLogicContext(
          definition: null,
          state: {},
          properties: {...BuiltInPartLogic.ldrDefaults, ...properties},
          physics: physics,
          elapsed: Duration.zero,
          analog: (_) => 0,
          pins: const _FakePins(),
          spice: const _FakeSpice(),
        ),
      );
      return physics['resistance']!;
    }

    test('resistance falls as light rises, between the two published values', () {
      expect(resistance({ComponentProps.illumination: '0'}), 1000000);
      expect(resistance({ComponentProps.illumination: '100'}), 1000);
      expect(
        resistance({ComponentProps.illumination: '50'}),
        allOf(lessThan(1000000), greaterThan(1000)),
      );
    });

    test('light outside 0-100 % is clamped', () {
      expect(resistance({ComponentProps.illumination: '150'}), 1000);
      expect(resistance({ComponentProps.illumination: '-20'}), 1000000);
    });

    test('its first solve starts where a freshly placed one settles', () {
      // The netlist is built before the logic first runs, from the static
      // value; if the two disagreed the reading would jump on frame one.
      final ldr = standardParts.firstWhere((p) => p.name == PartNames.ldr);
      expect(ldr.spice!.defaultValue, resistance(const {}));
    });
  });

  group('the servo, moved out of the engine', () {
    /// A board where the signal port reaches [pin] and reports [us].
    PartLogicContext servoContext({
      int? pin,
      double us = 0,
      Map<String, Object?> state = const {},
    }) => PartLogicContext(
      definition: null,
      state: {...state},
      properties: const {},
      physics: {},
      elapsed: Duration.zero,
      analog: (_) => 0,
      pins: _ScriptedPins(signalPin: pin, pulse: us),
      spice: const _FakeSpice(),
    );

    test('maps the Servo library pulse range onto 0-180 degrees', () {
      double angleFor(double us) {
        final c = servoContext(pin: 9, us: us);
        BuiltInPartLogic.servo(c);
        return c.state['servoAngle']! as double;
      }

      expect(angleFor(544), 0, reason: 'the library minimum is 0 degrees');
      expect(angleFor(2400), 180, reason: 'the library maximum is 180 degrees');
      expect(angleFor(1472), closeTo(90, 0.5), reason: 'midpoint');
    });

    test('clamps a hand-pulsed sketch outside the library range', () {
      for (final us in [1.0, 300.0, 3000.0, 20000.0]) {
        final c = servoContext(pin: 9, us: us);
        BuiltInPartLogic.servo(c);
        final angle = c.state['servoAngle']! as double;
        expect(angle, inInclusiveRange(0, 180), reason: 'at ${us}us');
      }
    });

    test('holds its pose when no pulse has been seen', () {
      // Also the first frame after a fresh measurement request, which must not
      // read as "commanded to zero".
      final c = servoContext(pin: 9, state: {'servoAngle': 137.0});
      BuiltInPartLogic.servo(c);
      expect(c.state['servoAngle'], 137.0);
    });

    test('does nothing when its signal line reaches no board pin', () {
      final c = servoContext(us: 1500);
      BuiltInPartLogic.servo(c);
      expect(c.state, isEmpty);
    });

    test('asking for a pulse width registers the pin for measurement', () {
      // The emulator only measures pins it has been told to watch, and a part
      // asking is the only evidence anyone needs them.
      final pins = _ScriptedPins(signalPin: 9, pulse: 1500);
      BuiltInPartLogic.servo(
        PartLogicContext(
          definition: null,
          state: {},
          properties: const {},
          physics: {},
          elapsed: Duration.zero,
          analog: (_) => 0,
          pins: pins,
          spice: const _FakeSpice(),
        ),
      );
      expect(pins.measured, contains(9));
    });
  });

  group('the LED, moved out of the engine', () {
    /// [amps] through the element, with the driving pin (if any) at [duty].
    PartLogicContext ledContext({double amps = 0, int? pin, double duty = 1}) => PartLogicContext(
      definition: null,
      state: {},
      properties: const {},
      physics: {},
      elapsed: Duration.zero,
      analog: (_) => 0,
      pins: _ScriptedPins(anodePin: pin, dutyValue: duty),
      spice: _FakeSpice(amps: amps),
    );

    test('lights only once current passes the on-threshold', () {
      final off = ledContext(amps: BuiltInPartLogic.ledOnAmps / 2);
      BuiltInPartLogic.led(off);
      expect(off.state[ComponentProps.isOn], isFalse);
      expect(off.state[ComponentProps.brightness], 0);

      final on = ledContext(amps: BuiltInPartLogic.ledOnAmps * 10);
      BuiltInPartLogic.led(on);
      expect(on.state[ComponentProps.isOn], isTrue);
    });

    test('current in either direction lights it', () {
      // Which leg is wired to the pin decides the sign; neither is "off".
      final c = ledContext(amps: -BuiltInPartLogic.ledOnAmps * 10);
      BuiltInPartLogic.led(c);
      expect(c.state[ComponentProps.isOn], isTrue);
    });

    test('brightness follows duty and current together', () {
      // 10 mA at half duty averages 5 mA — a quarter of the 20 mA rating.
      final c = ledContext(amps: BuiltInPartLogic.ledRatedAmps / 2, pin: 9, duty: 0.5);
      BuiltInPartLogic.led(c);
      expect(c.state[ComponentProps.brightness], closeTo(0.25, 1e-9));
    });

    test('the series resistor changes brightness, not just the duty', () {
      // The regression this whole model exists for: two LEDs driven flat out,
      // differing only in the current their resistor allows, must not render
      // identically.
      final dim = ledContext(amps: BuiltInPartLogic.ledRatedAmps * 0.75);
      final bright = ledContext(amps: BuiltInPartLogic.ledRatedAmps);
      BuiltInPartLogic.led(dim);
      BuiltInPartLogic.led(bright);

      expect(dim.state[ComponentProps.brightness], closeTo(0.75, 1e-9));
      expect(bright.state[ComponentProps.brightness], 1.0);
      expect(dim.state[ComponentProps.brightness], isNot(bright.state[ComponentProps.brightness]));
    });

    test('an LED at its rated current on the rail is full brightness', () {
      final c = ledContext(amps: BuiltInPartLogic.ledRatedAmps);
      BuiltInPartLogic.led(c);
      expect(c.state[ComponentProps.brightness], 1.0);
    });

    test('brightness saturates rather than exceeding full', () {
      final c = ledContext(amps: BuiltInPartLogic.ledRatedAmps * 5);
      BuiltInPartLogic.led(c);
      expect(c.state[ComponentProps.brightness], 1.0);
    });

    test('over-driving sets the error flag; correct driving does not', () {
      final overDriven = ledContext(amps: BuiltInPartLogic.ledRatedAmps * 1.4);
      BuiltInPartLogic.led(overDriven);
      expect(overDriven.state[ComponentProps.hasError], isTrue);

      final healthy = ledContext(amps: BuiltInPartLogic.ledRatedAmps * 0.75);
      BuiltInPartLogic.led(healthy);
      expect(healthy.state[ComponentProps.hasError], isFalse);
    });

    test('PWM dimming a hard-driven LED is not an over-current', () {
      // 28 mA peak at 25% duty averages 7 mA. Judging the peak would call this
      // damage; judging the average — what actually heats the die — does not.
      final c = ledContext(amps: BuiltInPartLogic.ledRatedAmps * 1.4, pin: 9, duty: 0.25);
      BuiltInPartLogic.led(c);
      expect(c.state[ComponentProps.hasError], isFalse);
    });

    test('brightness is quantized so duty jitter cannot spam the canvas', () {
      final a = ledContext(amps: BuiltInPartLogic.ledRatedAmps, pin: 9, duty: 0.501);
      final b = ledContext(amps: BuiltInPartLogic.ledRatedAmps, pin: 9, duty: 0.504);
      BuiltInPartLogic.led(a);
      BuiltInPartLogic.led(b);
      expect(
        a.state[ComponentProps.brightness],
        b.state[ComponentProps.brightness],
        reason: 'sampling jitter should not produce a different value',
      );
    });

    test('either leg can be the one wired to the board', () {
      final viaCathode = PartLogicContext(
        definition: null,
        state: {},
        properties: const {},
        physics: {},
        elapsed: Duration.zero,
        analog: (_) => 0,
        pins: _ScriptedPins(cathodePin: 9, dutyValue: 0.25),
        spice: const _FakeSpice(amps: BuiltInPartLogic.ledRatedAmps),
      );
      BuiltInPartLogic.led(viaCathode);
      expect(viaCathode.state[ComponentProps.brightness], closeTo(0.25, 1e-9));
    });
  });

  group('the buzzer, moved out of the engine', () {
    PartLogicContext buzzerContext({int? pin, double? hz, Map<String, Object?> state = const {}}) =>
        PartLogicContext(
          definition: null,
          state: {...state},
          properties: const {},
          physics: {},
          elapsed: Duration.zero,
          analog: (_) => 0,
          pins: _ScriptedPins(plusPin: pin, hertz: hz),
          spice: const _FakeSpice(),
        );

    test('sounds at the detected frequency', () {
      final c = buzzerContext(pin: 8, hz: 440);
      BuiltInPartLogic.buzzer(c);
      expect(c.state[ComponentProps.isOn], isTrue);
      expect(c.state[ComponentProps.frequency], 440);
    });

    test('silence turns it off but keeps the last note', () {
      // A stopped buzzer reading 0 Hz would draw as though it were playing a
      // subsonic tone; keeping the last pitch is what the old updater did.
      final c = buzzerContext(pin: 8, state: {ComponentProps.frequency: 440.0});
      BuiltInPartLogic.buzzer(c);
      expect(c.state[ComponentProps.isOn], isFalse);
      expect(c.state[ComponentProps.frequency], 440.0);
    });

    test('asking for a frequency points the detector at that pin', () {
      // Detection across every toggling pin picks up serial TX and blinking
      // LEDs — audio garbage rather than a tone.
      final pins = _ScriptedPins(plusPin: 8, hertz: 440);
      BuiltInPartLogic.buzzer(
        PartLogicContext(
          definition: null,
          state: {},
          properties: const {},
          physics: {},
          elapsed: Duration.zero,
          analog: (_) => 0,
          pins: pins,
          spice: const _FakeSpice(),
        ),
      );
      expect(pins.frequencyAsked, 8);
    });

    test('an unwired buzzer does nothing', () {
      final c = buzzerContext(hz: 440);
      BuiltInPartLogic.buzzer(c);
      expect(c.state, isEmpty);
    });
  });

  group('the context helpers coerce the way expressions do', () {
    test('number() reads through defaults and tolerates strings', () {
      final c = contextFor(_stub, properties: {'a': '2.5', 'b': true});
      expect(c.number('a'), 2.5);
      expect(c.number('b'), 1);
      expect(c.number('missing', 7), 7);
    });

    test('flag() accepts bools, numbers and the words', () {
      final c = contextFor(_stub, properties: {'a': 1, 'b': 'true', 'c': 0});
      expect(c.flag('a'), isTrue);
      expect(c.flag('b'), isTrue);
      expect(c.flag('c'), isFalse);
      expect(c.flag('missing', orElse: true), isTrue);
    });

    test('digital() uses the same 2.5V threshold as the expression language', () {
      final c = contextFor(_stub, pins: {'p': 3.3});
      expect(c.digital('p'), isTrue);
      expect(c.digital('p', 4), isFalse);
    });
  });
  group('the OLED display, the first part that follows a protocol', () {
    setUp(BuiltInPartLogic.ensureRegistered);

    /// A built-in part has no `.pdl`, so its whole state is its property map —
    /// which is also the only memory its logic has between frames.
    /// Wired the way the template wires it, unless a test says otherwise.
    const wiredToBus = {'SDA': 'A4', 'SCL': 'A5'};

    PartLogicContext displayContext({
      required _FakeBus bus,
      Map<String, Object?> properties = const {},
      Map<String, Object?> state = const {},
      Map<String, String> boardPorts = wiredToBus,
    }) => PartLogicContext(
      definition: null,
      state: {...state},
      properties: properties,
      physics: {},
      elapsed: Duration.zero,
      analog: (_) => 0,
      pins: _FakeBoardPorts(boardPorts),
      spice: const _FakeSpice(),
      i2c: bus,
    );

    List<int> initSequence() => [0x00, 0xAF];

    test('listens on 0x3C unless told otherwise', () {
      final bus = _FakeBus({
        0x3C: [initSequence()],
      });
      final context = displayContext(bus: bus);

      PartLogicRegistry.find('ssd1306')!(context);

      expect(bus.drained, [0x3C]);
      expect(Ssd1306Controller.unpack(context.state[ComponentProps.oledFrame]).displayOn, isTrue);
    });

    test('a display that is not on the bus stays dark', () {
      // The bus is global — the emulator records what the sketch transmits,
      // not what a wire carries — so without this an unwired display would
      // show the sketch's output while a real one sat dark.
      for (final wiring in const [
        <String, String>{},
        {'SDA': 'A4'},
        {'SDA': 'A5', 'SCL': 'A4'}, // swapped, the classic first mistake
        {'SDA': '9', 'SCL': '10'},
      ]) {
        final bus = _FakeBus({
          0x3C: [initSequence()],
        });
        final context = displayContext(bus: bus, boardPorts: wiring);

        PartLogicRegistry.find('ssd1306')!(context);

        expect(context.state, isEmpty, reason: 'wired as $wiring');
        expect(bus.drained, isEmpty, reason: 'wired as $wiring');
      }
    });

    test('a hex address in the property panel is understood', () {
      // The spelling people copy out of a sketch. A plain number works too,
      // because the properties panel writes numeric fields back as numbers.
      for (final written in <Object>['0x3D', '0X3D', ' 0x3d ', 61]) {
        final bus = _FakeBus({
          0x3D: [initSequence()],
        });
        PartLogicRegistry.find('ssd1306')!(
          displayContext(bus: bus, properties: {ComponentProps.i2cAddress: written}),
        );
        expect(bus.drained, [0x3D], reason: 'address written as "$written"');
      }
    });

    test('an unreadable address falls back rather than never running', () {
      final bus = _FakeBus({
        0x3C: [initSequence()],
      });
      PartLogicRegistry.find('ssd1306')!(
        displayContext(bus: bus, properties: {ComponentProps.i2cAddress: 'not an address'}),
      );

      expect(bus.drained, [0x3C]);
    });

    test('a silent frame writes nothing, so an idle display never redraws', () {
      final bus = _FakeBus(const {});
      final context = displayContext(bus: bus);

      PartLogicRegistry.find('ssd1306')!(context);

      expect(context.state, isEmpty);
    });

    test('the display picks up where the previous frame left off', () {
      // The state map is the round trip: what the logic writes goes to the
      // canvas and comes back next frame. A refresh split across frames — which
      // every refresh is — depends on it.
      final first = displayContext(
        bus: _FakeBus({
          0x3C: [
            [0x00, 0xAF, 0x20, 0x00, 0x21, 0x00, 0x7F, 0x22, 0x00, 0x07],
          ],
        }),
      );
      PartLogicRegistry.find('ssd1306')!(first);

      final second = displayContext(
        bus: _FakeBus({
          0x3C: [
            [0x40, 0xFF],
          ],
        }),
        state: first.state,
      );
      PartLogicRegistry.find('ssd1306')!(second);

      final display = Ssd1306Controller.unpack(second.state[ComponentProps.oledFrame]);
      expect(display.displayOn, isTrue, reason: "the first frame's commands survived");
      expect(display.pixelAt(0, 0), isTrue, reason: "the second frame's pixels landed");
    });
  });
}

/// No analog model — the parts under test here are driven by pins and
/// properties.
class const _FakeSpice({final double amps = 0}) implements PartSpiceApi {
  @override
  bool get isActive => amps != 0;
  @override
  double current() => amps;
}

/// A board wired to one pin, reporting one pulse width.
class _ScriptedPins({
  final int? signalPin,
  final int? anodePin,
  final int? cathodePin,
  final int? plusPin,
  final double pulse = 0,
  final double dutyValue = 0,
  final double? hertz,
}) implements PartPinApi {
  int? frequencyAsked;
  final measured = <int>{};

  @override
  int? connectedTo(String portId) => switch (portId) {
    'signal' => signalPin,
    'anode' => anodePin,
    'cathode' => cathodePin,
    'plus' => plusPin,
    _ => null,
  };

  @override
  String? boardPortFor(String portId) => connectedTo(portId)?.toString();
  @override
  double duty(int pin) => dutyValue;
  @override
  double pulseUs(int pin) {
    measured.add(pin);
    return pulse;
  }

  @override
  bool isHigh(int pin) => false;
  @override
  double? frequencyOn(int pin) {
    frequencyAsked = pin;
    return hertz;
  }
}

/// A board that reports nothing — the one-shot under test is driven by a
/// property, not by the emulator.
class const _FakePins() implements PartPinApi {
  @override
  double? frequencyOn(int pin) => null;
  @override
  int? connectedTo(String portId) => null;
  @override
  String? boardPortFor(String portId) => null;
  @override
  double duty(int pin) => 0;
  @override
  double pulseUs(int pin) => 0;
  @override
  bool isHigh(int pin) => false;
}

/// A board whose ports are wired however the test says.
class const _FakeBoardPorts(final Map<String, String> wiring) implements PartPinApi {
  @override
  String? boardPortFor(String portId) => wiring[portId];
  @override
  int? connectedTo(String portId) => int.tryParse(wiring[portId] ?? '');
  @override
  double duty(int pin) => 0;
  @override
  double pulseUs(int pin) => 0;
  @override
  bool isHigh(int pin) => false;
  @override
  double? frequencyOn(int pin) => null;
}

/// A bus that hands over a fixed batch of transactions and records who asked.
class _FakeBus(final Map<int, List<List<int>>> traffic) implements PartI2cApi {
  final drained = <int>[];

  @override
  List<List<int>> drain(int address) {
    drained.add(address);
    return traffic[address] ?? const [];
  }

  @override
  void serve(int address, {int size = 256, int pointerBytes = 1}) {}

  @override
  void setRegisters(int address, int offset, List<int> bytes) {}
}

/// A minimal definition for the helper tests — nothing about it matters except
/// that it exists.
final _stub = PdlParser.parse('''
PART "Stub"
ID stub
SIZE 32px 16px
SVG "s.svg"

PINS
  p 4px 4px passive "P"
''').definition!;
